# mndict LoRA pilot — Kaggle T4 edition.
# Same dataset, prompt rendering, and hyperparameters as
# training/train_e2b_pilot.py, adapted for 2x Tesla T4:
#   - T4 has no bf16 -> QLoRA (nf4 4-bit base, fp16 compute) for training,
#     then the base is reloaded in fp16 and the adapter merged there
#     (merge cannot happen into a 4-bit base).
#   - Only GPU 0 is used; the second T4 stays idle (naive model-parallel
#     would be slower than QLoRA on one card for this size).
# Produces: /kaggle/working/adapter (LoRA backup) and
#           /tmp/e2b_pilot/pilot_f16.gguf (quantized to q4_0 by the notebook).
# Run AFTER: pip installs + git clone llama.cpp @ b10798 (see run_all.ipynb).

import gc
import json
import os
import subprocess
import sys

import torch

# pip -U upgrades can leave Kaggle's preinstalled torch/torchvision pair
# mismatched, which crashes transformers' own import (torchvision
# ::nms register_fake). Realign torchvision BEFORE transformers/peft import.
subprocess.run(
    [sys.executable, "-m", "pip", "install", "-q", "-U", "torchvision"],
    check=False,
)
try:
    import torchvision  # noqa: F401

    print("torchvision", torchvision.__version__)
except Exception as e:  # text-only training works without it
    print("torchvision import failed (continuing):", e)

from peft import LoraConfig, PeftModel, get_peft_model
from torch.utils.data import Dataset
from transformers import (
    AutoModelForCausalLM,
    AutoTokenizer,
    BitsAndBytesConfig,
    Trainer,
    TrainingArguments,
)

MODEL_ID = "google/gemma-4-E2B-it"
WORK = "/kaggle/working"
TMP = "/tmp/e2b_pilot"
LLAMA_CPP = "/tmp/llama.cpp"
ADAPTER_DIR = os.path.join(WORK, "adapter")
MERGED_DIR = os.path.join(TMP, "merged")
F16_GGUF = os.path.join(TMP, "pilot_f16.gguf")
MAX_LEN = 1024

SYSTEM_PROMPT = (
    "You are a dictionary assistant. Explain the given word, phrase, idiom, or "
    "short sentence as a dictionary entry. If the headword is not a real English "
    "word or phrase, reply only: None."
)

DATASET = json.loads(r"""__DATASET_JSON__""")


def render_entry(entry: dict) -> str:
    if entry.get("abstain"):
        return "None"
    lines = []
    for i, m in enumerate(entry["meanings"], start=1):
        multi = len(entry["meanings"]) > 1
        prefix = f"{i}. " if multi else ""
        lines.append(f"{prefix}{entry['pos']} ({m['label']}): {m['definition']}")
        for ex in m["examples"]:
            lines.append(f"- {ex}")
    if entry.get("usage"):
        lines.append(f"Usage: {entry['usage']}")
    lines.append(f"Synonyms: {', '.join(entry['synonyms']) or 'none'}")
    lines.append(f"Antonyms: {', '.join(entry['antonyms']) or 'none'}")
    return "\n".join(lines)


def render_prompt(word: str) -> str:
    # Byte-identical to the app's gemma4 style: no literal <bos> — the
    # tokenizer (add_bos_token=True below) supplies the single BOS here and
    # llama.cpp's add_special=true supplies it at runtime.
    return (
        "<|turn>user\n"
        f"{SYSTEM_PROMPT}\n\n"
        f"{word}<turn|>\n"
        "<|turn>model\n"
    )


class PilotDataset(Dataset):
    def __init__(self, tok):
        self.rows = []
        for entry in DATASET["entries"]:
            prompt_ids = tok(render_prompt(entry["word"]), add_special_tokens=True)["input_ids"]
            completion = render_entry(entry) + "<turn|><eos>"
            completion_ids = tok(completion, add_special_tokens=False)["input_ids"]
            input_ids = prompt_ids + completion_ids
            if len(input_ids) > MAX_LEN:
                print(f"SKIP (too long): {entry['word']}")
                continue
            labels = [-100] * len(prompt_ids) + completion_ids
            self.rows.append({"input_ids": input_ids, "labels": labels})

    def __len__(self):
        return len(self.rows)

    def __getitem__(self, idx):
        return self.rows[idx]


def collate(batch):
    maxlen = max(len(r["input_ids"]) for r in batch)
    pad_id = collate.pad_id
    input_ids, labels, attn = [], [], []
    for r in batch:
        n = maxlen - len(r["input_ids"])
        input_ids.append(r["input_ids"] + [pad_id] * n)
        labels.append(r["labels"] + [-100] * n)
        attn.append([1] * len(r["input_ids"]) + [0] * n)
    return {
        "input_ids": torch.tensor(input_ids, dtype=torch.long),
        "labels": torch.tensor(labels, dtype=torch.long),
        "attention_mask": torch.tensor(attn, dtype=torch.long),
    }


def quick_eval(merged, tok):
    # Greedy generation on one rare, one misspelling, one nonword — eyeball
    # the notebook log to judge whether the format/abstention took.
    abstains = [e["word"] for e in DATASET["entries"] if e.get("abstain")]
    eval_words = ["petrichor", "harvast"] + (abstains[:1] or [])
    merged.eval()
    merged.config.use_cache = True
    for word in eval_words:
        ids = tok(render_prompt(word), add_special_tokens=True, return_tensors="pt").to("cuda")
        out = merged.generate(
            **ids,
            max_new_tokens=300,
            do_sample=False,
            pad_token_id=tok.pad_token_id or tok.eos_token_id,
            eos_token_id=tok.eos_token_id,
        )
        text = tok.decode(out[0][ids["input_ids"].shape[1]:], skip_special_tokens=True)
        print(f"\n===== EVAL: {word!r} =====\n{text.strip()}\n")


def main():
    assert torch.cuda.is_available(), "No CUDA GPU — select GPU T4 x2 in session options"
    props = torch.cuda.get_device_properties(0)
    print(f"GPU: {props.name} ({props.total_memory / 1e9:.1f} GB)")
    os.makedirs(TMP, exist_ok=True)

    tok = AutoTokenizer.from_pretrained(MODEL_ID)
    # The runtime GGUF prepends exactly one BOS (add_bos_token=true); train
    # sequences must match. Google's HF repo ships add_bos_token=False.
    tok.add_bos_token = True
    print(f"add_bos_token: {getattr(tok, 'add_bos_token', 'n/a')}")
    collate.pad_id = tok.pad_token_id or tok.eos_token_id

    bnb = BitsAndBytesConfig(
        load_in_4bit=True,
        bnb_4bit_quant_type="nf4",
        bnb_4bit_use_double_quant=True,
        bnb_4bit_compute_dtype=torch.float16,
    )
    model = AutoModelForCausalLM.from_pretrained(
        MODEL_ID,
        quantization_config=bnb,
        device_map={"": 0},
        attn_implementation="eager",
    )
    model.config.use_cache = False

    lora = LoraConfig(
        r=32,
        lora_alpha=64,
        lora_dropout=0.05,
        bias="none",
        task_type="CAUSAL_LM",
        target_modules="all-linear",
    )
    model = get_peft_model(model, lora)
    model.print_trainable_parameters()
    model.enable_input_require_grads()

    ds = PilotDataset(tok)
    print(f"Dataset: {len(ds)} examples")
    if len(ds) < 10:
        sys.exit("Dataset too small")

    args = TrainingArguments(
        output_dir="/tmp/e2b_ckpt",
        num_train_epochs=2,
        per_device_train_batch_size=1,
        gradient_accumulation_steps=4,
        gradient_checkpointing=True,
        gradient_checkpointing_kwargs={"use_reentrant": False},
        learning_rate=1.5e-4,
        lr_scheduler_type="cosine",
        logging_steps=1,
        save_strategy="no",
        fp16=True,
        report_to=[],
        seed=42,
    )
    Trainer(model=model, args=args, train_dataset=ds, data_collator=collate).train()

    model.save_pretrained(ADAPTER_DIR)
    tok.save_pretrained(ADAPTER_DIR)
    print(f"Adapter saved to {ADAPTER_DIR}")

    # Merge in fp16 (cannot merge into a 4-bit base): reload clean base.
    del model
    gc.collect()
    torch.cuda.empty_cache()
    base = AutoModelForCausalLM.from_pretrained(MODEL_ID, dtype=torch.float16, device_map={"": 0})
    merged = PeftModel.from_pretrained(base, ADAPTER_DIR).merge_and_unload()
    merged.config.use_cache = True

    quick_eval(merged, tok)

    merged.save_pretrained(MERGED_DIR)
    tok.save_pretrained(MERGED_DIR)
    del merged, base
    gc.collect()
    torch.cuda.empty_cache()

    r = subprocess.run(
        [sys.executable, os.path.join(LLAMA_CPP, "convert_hf_to_gguf.py"),
         MERGED_DIR, "--outfile", F16_GGUF, "--outtype", "f16"],
    )
    if r.returncode != 0:
        sys.exit(f"GGUF conversion failed (rc={r.returncode})")
    print(f"\nF16 GGUF ready: {F16_GGUF} ({os.path.getsize(F16_GGUF) / 1e9:.2f} GB)")
    print("NEXT: run the quantize cell -> /kaggle/working/gemma-4-E2B-pilot-q4_0.gguf")


if __name__ == "__main__":
    main()
