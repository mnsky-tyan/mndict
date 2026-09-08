# mndict LoRA pilot v2 — train the RICH entry format + None abstention into
# gemma-4-E2B-it (2026-09 bake-off winner).
#
# Reads training/pilot_dataset_e2b.json, renders each entry into the EXACT
# runtime prompt (the app's fixed gemma4 style: persona rides in the user
# turn, NO literal <bos> — the GGUF add_bos_token prepends it, and the native
# tokenize call runs with add_special=true), masks the prompt out of the loss,
# trains LoRA r=32 on all linear layers, merges, saves the merged model.
#
# Completions end "<turn|><eos>": canonical gemma-4 turn end, and the GGUF's
# tokenizer.ggml.eos_token_id=1 makes llama.cpp stop on the <eos>.
#
# Device: Intel XPU (Arc) preferred, falls back to cuda/cpu.
# Usage: python training/train_e2b_pilot.py

import json
import os
import sys

import torch
from peft import LoraConfig, get_peft_model
from torch.utils.data import Dataset
from transformers import (
    AutoModelForCausalLM,
    AutoTokenizer,
    Trainer,
    TrainingArguments,
)

MODEL_PATH = os.path.join(os.path.dirname(__file__), "models", "gemma-4-E2B-it")
DATASET_PATH = os.path.join(os.path.dirname(__file__), "pilot_dataset_e2b.json")
OUT_DIR = os.path.join(os.path.dirname(__file__), "out_e2b")
MAX_LEN = 1024

SYSTEM_PROMPT = (
    "You are a dictionary assistant. Explain the given word, phrase, idiom, or "
    "short sentence as a dictionary entry. If the headword is not a real English "
    "word or phrase, reply only: None."
)


def render_entry(entry: dict) -> str:
    # Rich entry: numbered meanings "N. pos (label): definition", one example
    # line per meaning, optional entry-level Usage, single-line syn/ant.
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
    # Byte-identical to the app's FIXED gemma4 style: no literal <bos> (the
    # tokenizer's add_special_tokens=True supplies the single BOS here, and
    # llama.cpp's add_special=true supplies it at runtime).
    return (
        "<|turn>user\n"
        f"{SYSTEM_PROMPT}\n\n"
        f"{word}<turn|>\n"
        "<|turn>model\n"
    )


class PilotDataset(Dataset):
    def __init__(self, tok):
        with open(DATASET_PATH, encoding="utf-8") as f:
            data = json.load(f)
        self.rows = []
        for entry in data["entries"]:
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


def pick_device():
    # The E2B base is ~9.7GB in bf16 — the 7.86GB Arc card cannot hold it, so
    # fall back to CPU training there (bf16 weights + cpu autocast).
    if getattr(torch, "xpu", None) and torch.xpu.is_available():
        if torch.xpu.get_device_properties(0).total_memory > 10e9:
            return "xpu"
        print("XPU present but < 10GB — E2B bf16 will not fit; using CPU")
    if torch.cuda.is_available():
        return "cuda"
    return "cpu"


def main():
    device = pick_device()
    print(f"Device: {device}")
    if device == "xpu":
        print(f"XPU device: {torch.xpu.get_device_name(0)}")

    tok = AutoTokenizer.from_pretrained(MODEL_PATH)
    # unsloth's HF copy ships add_bos_token=False (canonical gemma-4 puts BOS
    # in the chat template), but the app's google QAT GGUF sets
    # add_bos_token=true — force it on so training sequences carry exactly the
    # one BOS that llama.cpp prepends at runtime.
    tok.add_bos_token = True
    print(f"add_bos_token: {getattr(tok, 'add_bos_token', 'n/a')}")
    collate.pad_id = tok.pad_token_id or tok.eos_token_id

    model = AutoModelForCausalLM.from_pretrained(
        MODEL_PATH,
        torch_dtype=torch.bfloat16,
    ).to(device)
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
    # LoRA + gradient checkpointing: embeddings must require grads.
    model.enable_input_require_grads()

    ds = PilotDataset(tok)
    print(f"Dataset: {len(ds)} examples")
    if len(ds) < 10:
        sys.exit("Dataset too small - check pilot_dataset_e2b.json")

    args = TrainingArguments(
        output_dir=os.path.join(OUT_DIR, "ckpt"),
        num_train_epochs=2,
        per_device_train_batch_size=1,
        gradient_accumulation_steps=4,
        gradient_checkpointing=True,
        learning_rate=1.5e-4,
        lr_scheduler_type="cosine",
        logging_steps=1,
        save_strategy="no",
        bf16=True,  # cuda/xpu autocast AND torch.cpu bf16 autocast
        # transformers 5.x auto-detects the iGPU and force-moves the model
        # there (OOM: bf16 E2B needs ~9.7GB, the Arc has 7.9GB) — pin CPU
        # whenever our device resolution said CPU.
        use_cpu=(device == "cpu"),
        report_to=[],
        seed=42,
    )

    trainer = Trainer(model=model, args=args, train_dataset=ds, data_collator=collate)
    trainer.train()

    merged = model.merge_and_unload()
    merged_out = os.path.join(OUT_DIR, "merged")
    merged.save_pretrained(merged_out)
    tok.save_pretrained(merged_out)
    print(f"Merged model saved to {merged_out}")


if __name__ == "__main__":
    main()
