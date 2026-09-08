# AGENTS.md

mndict — an offline dictionary app where a local LLM (via llama.cpp) explains words, phrases, and idioms on-device. **Android (arm64) is the only working target**; the Windows desktop target is broken (CppWinRT nuget) and the other platform folders are untested Flutter scaffolding.

## Layout

| Path | What it is |
|---|---|
| `app/` | Flutter app (Dart sources in `app/lib/`) |
| `jni/` | `native_api.cpp` — the C wrapper (`llama_native_*` API) built into `libllama.so` |
| `CMakeLists.txt` | Native build: links `llama.cpp` (static) + `jni/native_api.cpp` → `libllama.so` |
| `llama.cpp/` | Upstream llama.cpp, git submodule |
| `artifacts/` | Native API header (`include/llama_native_api.h`), build/FFI specs, manual-build `.so` copies |
| `scripts/` | `build_android.ps1` (manual native build), `download_models.ps1`, LoRA training scripts (untracked) |
| `docs/` | Local notes on models and llama.cpp (untracked) |
| `wiki/` | GitHub wiki sources (untracked, pending publish) |

`app/lib/` is `main.dart` + `services/` (settings, dictionary/vocabulary logic, isolate, downloader, FFI bindings) + `ui/` (`screens/`, `widgets/`, `theme/`). The search/definition flow: `ui/glass_dictionary_app.dart` → `services/dictionary_service.dart` → `services/llama_isolate.dart` → `services/native_llama.dart` (dart:ffi) → `libllama.so`.

## Native wiring (non-obvious)

`app/android/app/build.gradle.kts` points Gradle's `externalNativeBuild` at the repo-root `CMakeLists.txt`, so `flutter build apk` compiles llama.cpp + the JNI wrapper itself and packages `libllama.so` into the APK. `scripts/build_android.ps1` is only the standalone/manual path (it also copies `libomp.so` into `app/android/app/src/main/jniLibs/`); the prebuilt `.so` files under `artifacts/android/` are outputs of that script, not the authoritative build.

Prompt templates are per-model-family (`app_settings.dart` `PromptStyle`) and built in `dictionary_service.dart`. GGUF models are downloaded at runtime from the Hugging Face URLs in `app_settings.dart` `availableModels`; model weights are never committed (*.gguf is gitignored).

## Commands

```sh
cd app
flutter analyze          # lint gate
flutter test             # widget test (needs the mocks it already sets up)
flutter build apk --release   # APK lands in build/app/outputs/flutter-apk/
```

## Conventions & gotchas

- **Farm art is data + one renderer**: `ui/widgets/pig_design.dart` holds the 50-breed design vocabulary (coat patterns, ears, tails, hats, back items, props, auras) and `ui/widgets/pig_painter.dart` (`PigArt`) renders any breed at any stage from a `PigPose`; `services/pig_service.dart` pairs breed i with `pigDesigns[i]`, and `pig_care_test.dart` locks the pairing 1:1 (50 breeds, all designs worn, auras only on 4★+). Style bible: bold dark outlines, flat candy colors, two-tone cel shading, glow rings at the feet for 4★+ — never ship a recolor breed.
- **Worlds**: `services/worlds.dart` is the catalog (meadow lv1 / beach lv7 / ship lv10 / sky island lv13, persisted on FarmProfile with lock enforcement); `ui/widgets/world_themes.dart` (`WorldBackdrop`) paints each backdrop. farm_view's `_WorldPainter` draws backdrop → care stations → herd; the world picker sheet lives in farm_view. Meadow keeps the level-unlock props (pond/windmill/…); other worlds are self-contained.
- `.gitignore` excludes `*.md` and `*.txt` repo-wide except `README.md` and `AGENTS.md` — new markdown docs stay local unless an exception is added.
- The llama.cpp submodule is pinned to numbered release tags (currently `b10798`, 2026-09); rebuild flags live in the root `CMakeLists.txt`: `GGML_CPU_KLEIDIAI=ON` (ARM i8mm kernels, FetchContent'd at configure time), flash attention + q8_0 KV cache are set in `jni/native_api.cpp` (`ctx_params.flash_attn_type` / `type_k` / `type_v`).
- BOS handling differs per model family and is easy to get wrong: gemma-3 and MiniCPM5 need a literal BOS (`<bos>` / `<s>`) in the Dart template; gemma-4 (E2B) and LFM2.5 GGUFs set `add_bos_token=true`, so the tokenizer prepends it and a literal BOS would double it (gemma-4 double-BOS shipped accidentally until 2026-09-07 — verify per GGUF with the `tokenizer.ggml.add_bos_token` metadata, never per family). Templates were taken verbatim from each model's `chat_template.jinja`; they live in `app/lib/services/prompts.dart` (`buildLookupPrompt`/`buildSimilarityPrompt`), and `app/test/prompts_test.dart` locks the invariants (BOS rules, single user turn, byte-exact LoRA training prompt).
- Gemma-4 replaced gemma-3's `<start_of_turn>`/`<end_of_turn>` with `<|turn>`/`<turn|>` and has no system role.
- Prompt format for Gemma (legacy gemma-3 path) must start with `<bos>`, or the model can end generation immediately.
- `DictionaryService.searchWord` has a double-submit guard (`isGenerating`) and Gemma lookups force a model reload to clear the KV context — preserve both when editing the lookup flow.
- `DictionaryService.init()` must complete before consumers subscribe to its streams; `SideMenu` renders standalone (no Material wrapper around it).
- The aurora background animates forever: in widget tests use fixed `tester.pump` durations, never `pumpAndSettle`. Tests mock `SharedPreferences` and the `path_provider` channel.
- Verify on-device via wireless adb (`adb connect <phone-ip>`), release builds for perf. On MIUI: commit IME input with Enter, and retry an edge-tap once before concluding it failed.
- Deep architecture docs live in `wiki/` (Architecture, Building-and-Running, Models-and-Sampling, LoRA-Fine-Tuning) and `artifacts/*.md` (build/FFI specs); the 2026-09 model bake-off plan lives in `docs/on-device-llm-research-2026-09.md`, its headword set in `app/assets/headwords_test.json`.
