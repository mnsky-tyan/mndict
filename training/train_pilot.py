# mndict LoRA pilot — train format adherence into LFM2.5-1.2B-Instruct.
# Reads training/pilot_dataset.json, renders each entry into the EXACT runtime
# prompt (short system persona + bare-headword user turn), masks the prompt out
# of the loss, trains LoRA r=32 on all linear layers, merges, saves merged model.
#
# Device: Intel XPU (Arc) preferred, falls back to cuda/cpu.
# Usage: python training/train_pilot.py

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

MODEL_ID = "LiquidAI/LFM2.5-1.2B-Instruct"
DATASET_PATH = os.path.join(os.path.dirname(__file__), "pilot_dataset.json")
OUT_DIR = os.path.join(os.path.dirname(__file__), "out")
MAX_LEN = 768

SYSTEM_PROMPT = (
    "You are a dictionary assistant. Explain the given word, phrase, idiom, or "
    "short sentence as a dictionary entry. If the headword is not a real English "
    "word or phrase, reply only: None."
)


def render_entry(entry: dict) -> str:
    if entry.get("abstain"):
        return "None"
    parts = [entry["word"], "", f"Part of speech: {entry['pos']}", "", "Meanings:", ""]
    for i, m in enumerate(entry["meanings"], start=1):
        parts.append(f"Meaning {i} ({m['label']}):")
        parts.append(m["definition"])
        parts.append("Example:")
        for ex in m["examples"]:
            parts.append(f"* {ex}")
        parts.append("")
    parts.append("Synonyms:")
    for syn in entry["synonyms"]:
        gloss = f" - {syn[1]}" if len(syn) > 1 and syn[1] else ""
        parts.append(f"* {syn[0]}{gloss}")
    parts.append("")
    parts.append("Antonyms:")
    for ant in entry["antonyms"]:
        gloss = f" - {ant[1]}" if len(ant) > 1 and ant[1] else ""
        parts.append(f"* {ant[0]}{gloss}")
    return "\n".join(parts)


def render_prompt(word: str) -> str:
    # Byte-identical to the app's lfm25 runtime template (BOS is added by the
    # tokenizer's add_bos_token, never written literally).
    return (
        "<|im_start|>system\n"
        f"{SYSTEM_PROMPT}<|im_end|>\n"
        "<|im_start|>user\n"
        f"{word}<|im_end|>\n"
        "<|im_start|>assistant\n"
    )


class PilotDataset(Dataset):
    def __init__(self, tok):
        with open(DATASET_PATH, encoding="utf-8") as f:
            data = json.load(f)
        self.rows = []
        for entry in data["entries"]:
            prompt_ids = tok(render_prompt(entry["word"]), add_special_tokens=True)["input_ids"]
            completion_ids = tok(render_entry(entry) + "<|im_end|>", add_special_tokens=False)["input_ids"]
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
    if getattr(torch, "xpu", None) and torch.xpu.is_available():
        return "xpu"
    if torch.cuda.is_available():
        return "cuda"
    return "cpu"


def main():
    device = pick_device()
    print(f"Device: {device}")
    if device == "xpu":
        print(f"XPU device: {torch.xpu.get_device_name(0)}")

    tok = AutoTokenizer.from_pretrained(MODEL_ID)
    collate.pad_id = tok.pad_token_id or tok.eos_token_id

    model = AutoModelForCausalLM.from_pretrained(
        MODEL_ID,
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

    ds = PilotDataset(tok)
    print(f"Dataset: {len(ds)} examples")
    if len(ds) < 10:
        sys.exit("Dataset too small - check pilot_dataset.json")

    args = TrainingArguments(
        output_dir=os.path.join(OUT_DIR, "ckpt"),
        num_train_epochs=3,
        per_device_train_batch_size=1,
        gradient_accumulation_steps=4,
        learning_rate=1.5e-4,
        lr_scheduler_type="cosine",
        warmup_ratio=0.05,
        logging_steps=5,
        save_strategy="no",
        bf16=(device != "cpu"),
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
