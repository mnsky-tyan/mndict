# On-device LLM research — engines & models for mndict (September 2026)

Research question: who runs LLMs locally on phones, is anything faster than llama.cpp, and which small GGUF models should mndict adopt for CPU inference + format-focused fine-tuning?
Method: two parallel primary-source research passes (engine ecosystem; model candidates), spot-verified against Hugging Face model cards. All URLs cited inline.

---

## 1. Verdict up front

- **llama.cpp is still the go-to in 2026** for an app that ships *custom fine-tuned GGUF* models. Every faster alternative requires abandoning GGUF (per-model AOT compilation, QNN context binaries, PyTorch `.pte` export, MNN's own quant format). llama.cpp alone loads arbitrary fine-tuned GGUFs, honors per-model chat templates, and supports runtime LoRA.
- The realistic speedups are (a) **newer small models** — the model generation moved more than the engines did, and (b) **build/config flags inside llama.cpp** we are not using yet.
- The recommended model swap: **LFM2.5-1.2B-Instruct (fast default)** + **LFM2.5-8B-A1B (deep-lookup MoE)** + **Gemma-4-E2B-it (knowledge ceiling, Apache-2.0)**.

## 2. Who runs LLMs locally on phones (2025–2026)

| Stack | What it is | Status |
|---|---|---|
| Google AI Edge / LiteRT-LM | Google's on-device inference framework (successor to MediaPipe LLM Inference API, now maintenance-mode) | Powers [AI Edge Gallery](https://play.google.com/store/apps/details?id=com.google.ai.edge.gallery) (Gemma offline); claims Gemma-3-1B prefill ~2,585 tok/s on GPU delegate ([blog](https://developers.googleblog.com/en/gemma-3-on-mobile-and-web-with-google-ai-edge/)); NPU path via LiteRT-QNN shows 100+ tok/s decode on SD 8 Elite Gen 5 ([blog](https://developers.googleblog.com/unlocking-peak-performance-on-qualcomm-npu-with-litert/)) |
| Gemini Nano / AICore | System-service model, exposed via ML Kit GenAI APIs | Flagship Pixels/Galaxies only; fixed model, no custom GGUF — unusable for mndict ([docs](https://developer.android.com/ai/gemini-nano)) |
| llama.cpp-based apps | PocketPal AI (React Native, [llama.rn](https://www.npmjs.com/package/@pocketpalai/llama.rn)), ChatterUI ([repo](https://github.com/Vali-98/ChatterUI)) | The mainstream for arbitrary GGUF on Android; mndict's CMake+JNI+FFI architecture matches this segment |
| MLC-LLM | TVM-based, GPU (OpenCL/Vulkan) | Fast but needs per-model AOT-compiled `model_lib` + MLC weight format; no GitHub releases; Android demo targets one SoC ([docs](https://llm.mlc.ai/docs/deploy/android.html)) |
| Apple Foundation Models (iOS 26) | ~3B system model via Swift, guided generation | Defines "polished on-device"; Android-irrelevant ([Apple](https://machinelearning.apple.com/research/introducing-apple-foundation-models)) |
| Qualcomm / MediaTek NPU stacks | AI Hub + Genie/QNN; MediaTek SpD+ speculative decoding | Fastest raw decode (e.g. Qwen3-4B w4a16: 38.6 tok/s decode, 2,789 prefill [AI Hub](https://aihub.qualcomm.com/models/qwen3_4b)) but per-chipset binaries, real-world reports of ~2.5x lower than published ([forum](https://mysupport.qualcomm.com/supportforums/s/question/0D5dK00000GkGOtSAN/)) |

## 3. Faster than llama.cpp? Measured on phone hardware

| Engine | Compute | Numbers (device) | Cost to adopt for mndict |
|---|---|---|---|
| llama.cpp | CPU | our 3–6 tok/s baseline (old models, old build flags) | already integrated |
| PowerServe | Hexagon NPU + ggml | Qwen2-0.5B 104–110 tok/s; Llama-3.2-1B 59 tok/s; 3B 21 tok/s (SD 8G3/8 Elite) ([README](https://github.com/powerserve-project/PowerServe)) | **Stalled upstream (last commit Aug 2025)**; QNN binaries per chipset; risky |
| MNN-LLM | CPU + OpenCL GPU | self-reported vs llama.cpp on Xiaomi 14: CPU decode **2.3x**, CPU prefill **8.6x**; explicit runtime-LoRA support ([paper](https://arxiv.org/html/2506.10443v1)) | own quant format (no GGUF); re-conversion pipeline; the only credible engine alternative |
| ExecuTorch | XNNPACK CPU / NPU | Llama-3.2-1B SpinQuant: **50.2 tok/s decode** on OnePlus 12; 3B 19.7 tok/s ([README](https://github.com/pytorch/executorch/blob/main/examples/models/llama/README.md)) | PyTorch `.pte` export + QAT/SpinQuant re-quantization; high integration cost |
| llama.cpp Vulkan on Android GPU | Adreno/Mali GPU | **not production-ready** — Mali "very bad" ([#9464](https://github.com/ggml-org/llama.cpp/discussions/9464)); community: GPU often slower than CPU on phones (memory-bandwidth-bound) | none — stay CPU |
| llama.cpp OpenCL (Qualcomm-contributed) | Adreno GPU | official backend targets Adreno 740–840; docs publish no CPU comparison, marked experimental ([OPENCL.md](https://github.com/ggml-org/llama.cpp/blob/master/docs/backend/OPENCL.md)) | optional future experiment |

**Conclusion: keep llama.cpp.** The wins above come with format lock-in, stalled projects, or per-device QA. Cheaper: rebuild llama.cpp with the flags below (est. 1.3–2x prefill):

1. `-DGGML_CPU_KLEIDIAI=ON` — ARM i8mm/dotprod microkernels ([Arm guide](https://learn.arm.com/learning-paths/mobile-graphics-and-gaming/performance_llama_cpp_sme2/kleidiai_integration/)); mndict's CMakeLists doesn't set it today.
2. Flash attention (`-fa`) on CPU — 1.3–2x prefill, prerequisite for KV quant.
3. KV cache q8_0 (`-ctk q8_0 -ctv q8_0`).
4. Threads = P-core count (not total cores); pin with `--cpu-list` equivalents ([discussion #25256](https://github.com/ggml-org/llama.cpp/discussions/25256)).
5. **Prompt/KV prefix reuse**: llama.cpp reuses the cached prefix as long as the context is kept (server formalizes it as `--cache-prompt`) ([server README](https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md)). After fine-tuning removes the system prompt entirely, per-lookup prefill is just the word itself — and the Gemma force-reload workaround can be retired (verify the original KV-degradation bug doesn't reappear on the new models).
6. Quant choice: prefer **Q4_0 over Q4_K_M on CPU** — K-quants dequantize slower in prefill; both LFM2.5 on-device tables and Android community guidance use Q4_0.

## 4. Recommended models (all verified on HF, September 2026)

### #1 fast default — LiquidAI LFM2.5-1.2B-Instruct
- 1.17B dense-hybrid (10 short-conv + 6 GQA layers), 32K context. ([card](https://huggingface.co/LiquidAI/LFM2.5-1.2B-Instruct))
- **IFEval 86.23** — vs Qwen3-1.7B 73.68, Gemma-3-1b 63.25, Llama-3.2-1B 52.37. Best instruction-following per byte found anywhere.
- **Verified on-device**: llama.cpp Q4_0 on Galaxy S25 Ultra CPU = **335 prefill / 70 decode tok/s @ 719 MB** (Qwen3-1.7B same device: 181/40 @ 1,306 MB). Even at half that on a mid-range MIUI phone it is ~10x our current Gemma-270M experience.
- GGUF: [LFM2.5-1.2B-Instruct-GGUF](https://huggingface.co/LiquidAI/LFM2.5-1.2B-Instruct-GGUF). Fine-tune: official Unsloth SFT + TRL SFT/DPO/GRPO Colabs. License: LFM 1.0 (commercial OK for <$10M-revenue entities; app redistribution allowed — verify text before shipping).
- Caveat: card says "not recommended for knowledge-intensive tasks" — the 1.2B knowledge floor; mitigated by the dictionary LoRA + #2 below.

### #2 deep lookup — LiquidAI LFM2.5-8B-A1B (MoE)
- **8.3B total / 1.5B active**, 128K context. ([card](https://huggingface.co/LiquidAI/LFM2.5-8B-A1B), release 2026-05, updated 2026-08)
- **IFEval 91.84** (best in class), and the standout for a reference app: **non-hallucination rate 63.47 vs 6–17 for same-size rivals** (AA-Omniscience). It knows when it doesn't know — exactly what a dictionary needs.
- GGUF: [LFM2.5-8B-A1B-GGUF](https://huggingface.co/LiquidAI/LFM2.5-8B-A1B-GGUF) — Q4_K_M 5.16 GB / Q4_0 4.84 GB. Needs ~6 GB RAM at runtime → 8 GB+ phones only; make it the optional "deep lookup" download.
- Day-one llama.cpp support (`lfm2moe` arch); Unsloth/TRL LoRA Colabs. Same LFM2 prompt family mndict already ships.
- Caveat: it is a reasoning model (emits `<think>` before answers; template defaults `preserve_thinking=false`) — mndict already strips `<think>` for Qwen3; reuse that path or disable thinking in the template. No published Android tok/s — verify (family estimate: LFM2.5-2.6B claims ~30 tok/s on phone; 1.5B active should be comparable).

### #3 knowledge ceiling — Google Gemma-4-E2B-it
- 5.1B raw / 2.3B effective (Per-Layer Embeddings), 128K context, **Apache 2.0**. ([card](https://huggingface.co/google/gemma-4-E2B-it))
- **MMLU-Pro 60.0 / GPQA-Diamond 43.4** — deepest English knowledge under ~3 GB by a wide margin (LFM2.5-1.2B: MMLU-Pro 44.35). IFEval not published on card (third-party table: ~82.9).
- GGUF: official [gemma-4-E2B-it-qat-q4_0-gguf](https://huggingface.co/google/gemma-4-E2B-it-qat-q4_0-gguf) (QAT = quantization-aware training, so q4_0 loses least) or [unsloth mirror](https://huggingface.co/unsloth/gemma-4-E2B-it-GGUF). Unsloth lists Gemma-4 E2B/E4B for fine-tuning; llama.cpp gemma4 support actively maintained (vision fix merged 2026-09-04).
- Caveats: llama.cpp runs the **full 5.1B raw weights** (PLE is a memory, not compute, saving) → decode roughly half of LFM2.5-1.2B (estimate; unverified). All Gemma templates must start with `<bos>` — mndict already handles this. Exact Q4 file size unverified (~3 GB expected).

### Considered and excluded
- **Qwen3.5-2B** (Feb 2026, Apache-2.0, hybrid DeltaNet): good benchmarks but **IFEval 61.2 non-thinking**, and llama.cpp Qwen3.5 LoRA-conversion bugs still open (late Aug 2026) — the fine-tune→GGUF path is central for us. Re-evaluate when #28324-class issues merge.
- **LFM2.5-2.6B**: best structured-output score found (IFStruct 85.5) but *always* emits `<think>` — latency/parse overhead for lookups.
- **Granite-4.0-H-Tiny** (7B/1B-active MoE): loses to LFM2.5-8B-A1B on every relevant benchmark (IFEval 82.2, non-halluc. 6.4); no Unsloth/PEFT path documented (Mamba2 hybrid).
- **Qwen3-1.7B / Gemma-3-1b / Llama-3.2-1B / SmolLM3-3B / Gemma-3-270M**: outclassed on IFEval per the LFM2.5-1.2B comparison table; Gemma-3n superseded by Gemma-4.

## 5. Fine-tuning plan (bake the format in)

1. **Dataset**: 500–2,000 diverse entries (words, idioms, phrases, short sentences) in the exact target format (Definition / Examples / Synonyms / Antonyms). Quality/diversity > size. (Prior 200-example run on Qwen3-0.6B overfit with more epochs — keep 1–3 epochs, watch eval.)
2. **Train on the exact runtime prompt**: user turn = the bare word/phrase, assistant turn = the formatted answer, **no system prompt** (that's the latency point of the exercise). Any mismatch between train and inference templates degrades adherence.
3. **Tool**: Unsloth SFT LoRA Colab (official for both LFM2.5 picks); export merged GGUF directly from Unsloth (Q4_0 or Q4_K_M). Merged > runtime-LoRA (llama.cpp runtime LoRA adds per-token overhead).
4. **Belt-and-braces**: llama.cpp GBNF grammar can hard-enforce the skeleton ("Definition:\n…Examples:\n…") at decode time with zero latency cost; use it as a guarantee while the LoRA handles content style.
5. New-generation floors are dramatically better: IFEval 86–92 raw means even *before* fine-tuning these models follow formats far better than Gemma-270M did after prompting.

## 6. Flags / unverified items

- LFM2.5-8B-A1B and Gemma-4-E2B have **no published Android tok/s** — measure on our device before committing (llama-bench via adb, or a bench mode in-app).
- LFM2.5 license text (LFM 1.0) — verify commercial/app-store terms before any public release.
- Gemma-4-E2B Q4 file size and LFM2.5-1.2B exact GGUF filenames not individually verified.
- LFM2.5 chat template details (BOS token, thinking toggle) need a check against our `PromptStyle` before wiring into `availableModels`.
