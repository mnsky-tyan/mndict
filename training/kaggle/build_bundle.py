# Regenerates training/kaggle/run_all.ipynb from train_kaggle.py +
# ../pilot_dataset_e2b.json (dataset is embedded, so the notebook is the ONLY
# file the user needs to upload to Kaggle).
# Usage: python training/kaggle/build_bundle.py

import json
import os

HERE = os.path.dirname(__file__)


def main():
    script = open(os.path.join(HERE, "train_kaggle.py"), encoding="utf-8").read()
    dataset = open(os.path.join(HERE, "..", "pilot_dataset_e2b.json"), encoding="utf-8").read()

    # Sanity: eval words + no triple-quote collision in the payload.
    words = {e["word"] for e in json.loads(dataset)["entries"]}
    for w in ("petrichor", "harvast"):
        assert w in words, f"quick_eval word {w!r} missing from dataset"
    assert '"""' not in dataset and not dataset.rstrip().endswith("\\"), "payload unsafe for r-string"
    script = script.replace("__DATASET_JSON__", dataset)
    assert "__DATASET_JSON__" not in script

    md = lambda text: {"cell_type": "markdown", "id": f"md-{abs(hash(text)) % 99999}", "metadata": {}, "source": text}
    code = lambda text: {"cell_type": "code", "id": f"code-{abs(hash(text)) % 99999}", "metadata": {}, "execution_count": None, "outputs": [], "source": text}

    cells = [
        md(
            "# mndict E2B pilot LoRA (gemma-4-E2B-it)\n"
            "\n"
            "Trains the 52-entry rich-format pilot on 1x T4 (QLoRA), merges in fp16,\n"
            "converts to GGUF, quantizes to **q4_0** (same quant as the base model on the\n"
            "phone -> fair A/B). Expected wall time: **~45-60 min**.\n"
            "\n"
            "Requirements: Session options -> Accelerator **GPU T4 x2**, Internet **On**;\n"
            "an `HF_TOKEN` secret attached (google/gemma-4 is gated).\n"
            "\n"
            "**Run -> Run all cells.** Output: `gemma-4-E2B-pilot-q4_0.gguf` (~2.6 GB)."
        ),
        code(
            "%pip install -q -U transformers peft accelerate bitsandbytes sentencepiece protobuf torchvision\n"
            "import transformers, peft, torch\n"
            "print('transformers', transformers.__version__, '| peft', peft.__version__, '| torch', torch.__version__, '| cuda', torch.cuda.is_available())"
        ),
        code(
            "# Gated model: attach the HF_TOKEN secret (Add-ons -> Secrets) BEFORE running.\n"
            "import os\n"
            "try:\n"
            "    from kaggle_secrets import UserSecretsClient\n"
            "    os.environ['HF_TOKEN'] = UserSecretsClient().get_secret('HF_TOKEN')\n"
            "    print('HF_TOKEN: loaded from Kaggle secret')\n"
            "except Exception as e:\n"
            "    print('HF_TOKEN secret missing or not attached:', e)\n"
            "    print('Add it via Add-ons -> Secrets, name it exactly HF_TOKEN, then re-run this cell.')"
        ),
        code(
            "!git clone --depth 1 --branch b10798 https://github.com/ggml-org/llama.cpp /tmp/llama.cpp\n"
            "%pip install -q -r /tmp/llama.cpp/requirements.txt\n"
            "print('llama.cpp b10798 ready')"
        ),
        code("%%writefile train_kaggle.py\n" + script),
        code("!python train_kaggle.py"),
        code(
            "# Builds only llama-quantize (CPU, no CUDA needed). ~10-15 min.\n"
            "!cmake -S /tmp/llama.cpp -B /tmp/llama.cpp/build -DGGML_CUDA=OFF -DLLAMA_CURL=OFF \\\n"
            "  && cmake --build /tmp/llama.cpp/build --target llama-quantize -j4"
        ),
        code(
            "!/tmp/llama.cpp/build/bin/llama-quantize /tmp/e2b_pilot/pilot_f16.gguf \\\n"
            "  /kaggle/working/gemma-4-E2B-pilot-q4_0.gguf q4_0\n"
            "!ls -la /kaggle/working"
        ),
    ]

    nb = {
        "cells": cells,
        "metadata": {
            "kernelspec": {"display_name": "Python 3", "language": "python", "name": "python3"},
            "language_info": {"name": "python", "version": "3.11"},
            "accelerator": "NVIDIATeslaT4",
        },
        "nbformat": 4,
        "nbformat_minor": 5,
    }
    out = os.path.join(HERE, "run_all.ipynb")
    with open(out, "w", encoding="utf-8") as f:
        json.dump(nb, f, ensure_ascii=False, indent=1)
    print(f"Wrote {out} ({os.path.getsize(out) / 1024:.0f} KB)")


if __name__ == "__main__":
    main()
