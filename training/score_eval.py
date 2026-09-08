# Aggregate a headword-eval JSONL: format compliance, abstention, speed.
import json
import re
import sys

REQUIRED = ["Definition:", "Examples:", "Synonyms:", "Antonyms:"]

def abstained(text: str) -> bool:
    t = text.strip().lower()
    return t.startswith("none") or "i don't know" in t or "i do not know" in t

path = sys.argv[1]
rows = [json.loads(l) for l in open(path, encoding="utf-8") if l.strip()]
cats = {}
for r in rows:
    c = cats.setdefault(r["category"], {"n": 0, "fmt": 0, "abst": 0, "tok": 0, "tps": []})
    c["n"] += 1
    if all(k in r["text"] for k in REQUIRED):
        c["fmt"] += 1
    if abstained(r["text"]):
        c["abst"] += 1
    c["tok"] += r["tokens"] or 0
    if r["tps"]:
        c["tps"].append(r["tps"])

print(f"{'category':10} {'n':>3} {'format_ok':>9} {'abstained':>9} {'avg_tok':>8} {'tok/s':>6}")
for cat, c in cats.items():
    tps = sum(c["tps"]) / len(c["tps"]) if c["tps"] else 0
    print(f"{cat:10} {c['n']:>3} {c['fmt']:>9} {c['abst']:>9} {c['tok']//c['n']:>8} {tps:>6.1f}")

print("\n-- nonwords that FAILED to abstain (hallucinations):")
for r in rows:
    if r["category"] == "nonwords" and not abstained(r["text"]):
        print(f"  {r['word']}: {r['text'][:90]!r}")
print("\n-- rare words that defined instead of abstaining:")
for r in rows:
    if r["category"] == "rare" and not abstained(r["text"]):
        print(f"  {r['word']}: {r['text'][:90]!r}")
