# Bake-off harness: run the headword test set through one loaded llama-server
# and dump per-item completions to JSONL for scoring.
#
# Usage:
#   python training/eval_headwords.py --template gemma4 \
#       --out training/eval_out/gemma4_e2b.jsonl
# The server must already be running on --port with the target model loaded.
import argparse
import json
import time
import urllib.request

HEADWORDS = r"C:\Users\tyanw\work\dict\app\assets\headwords_test.json"

# Mirror of prompts.dart _dictionarySystemPrompt (bake-off persona + None policy).
DICT_SYSTEM = (
    "You are a dictionary assistant. Explain the given word, phrase, idiom, "
    "or short sentence. Reply in exactly this format:\n"
    "Definition: <definition>\n"
    "Examples:\n- <example sentence>\n- <example sentence>\n"
    "Synonyms: <comma-separated synonyms, or none>\n"
    "Antonyms: <comma-separated antonyms, or none>\n"
    "Plain text only, no markdown. "
    "If you are not certain the entry exists, or you don't know it, reply only: None."
)


def build_prompt(template: str, word: str) -> str:
    # Byte-faithful to the corresponding buildLookupPrompt branches.
    if template == "lfm25":
        # GGUF add_bos_token=true prepends BOS; no literal <bos> here.
        return (
            "<|im_start|>system\n" + DICT_SYSTEM + "<|im_end|>\n"
            "<|im_start|>user\n" + word + "\n\n"
            "Use the exact entry format: numbered Meanings with a short sense "
            "label in parentheses, an Example block with bullet sentence(s) under "
            "each meaning, and Synonyms/Antonyms lines each formatted as: "
            "word - short gloss.<|im_end|>\n"
            "<|im_start|>assistant\n"
        )
    if template == "gemma4":
        # No system role; BOS literal; <|turn>/<turn|> markers.
        return (
            "<bos><|turn>user\n" + DICT_SYSTEM + "\n\n" + word + "<turn|>\n"
            "<|turn>model\n"
        )
    if template == "qwen3":
        # Qwen3.5 thinks by default and IGNORES the /no_think soft switch —
        # verified 2026-09-07 (every reply burned its budget inside <think>).
        # The empty think block is the actual disable switch.
        return (
            "<|im_start|>system\n" + DICT_SYSTEM + "<|im_end|>\n"
            "<|im_start|>user\nDefine: " + word + "<|im_end|>\n"
            "<|im_start|>assistant\n<think>\n\n</think>\n\n"
        )
    raise ValueError(template)


STOP_STRINGS = {
    "lfm25": ["<|im_end|>"],
    "gemma4": ["<turn|>"],
    "qwen3": ["<|im_end|>"],
}


def complete(port: int, prompt: str, template: str, n_predict: int) -> dict:
    body = json.dumps({
        "prompt": prompt,
        "n_predict": n_predict,
        "temperature": 0.0,
        "cache_prompt": False,
        "stop": STOP_STRINGS[template],
    }).encode()
    req = urllib.request.Request(
        f"http://127.0.0.1:{port}/completion", data=body,
        headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=300) as r:
        return json.load(r)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--template", required=True,
                    choices=["lfm25", "gemma4", "qwen3"])
    ap.add_argument("--model-tag", required=True)
    ap.add_argument("--port", type=int, default=8081)
    ap.add_argument("--out", required=True)
    ap.add_argument("--n-predict", type=int, default=300)
    ap.add_argument("--limit", type=int, default=0,
                    help="cap items per category (0 = all)")
    args = ap.parse_args()

    with open(HEADWORDS, encoding="utf-8") as f:
        data = json.load(f)

    done = 0
    with open(args.out, "w", encoding="utf-8", newline="\n") as out:
        for category in ("common", "idioms", "phrases", "rare", "nonwords"):
            words = data[category]
            if args.limit:
                words = words[: args.limit]
            for word in words:
                t0 = time.time()
                res = complete(args.port, build_prompt(args.template, word),
                               args.template, args.n_predict)
                rec = {
                    "model": args.model_tag,
                    "category": category,
                    "word": word,
                    "text": res.get("content", "").strip(),
                    "tokens": res.get("tokens_predicted"),
                    "ms": round((time.time() - t0) * 1000),
                    "tps": res.get("timings", {}).get("predicted_per_second"),
                }
                out.write(json.dumps(rec, ensure_ascii=False) + "\n")
                out.flush()
                done += 1
                print(f"[{done}] {category}/{word}: {rec['tokens']} tok, "
                      f"{rec['tps'] and round(rec['tps'], 1)} tok/s", flush=True)


if __name__ == "__main__":
    main()
