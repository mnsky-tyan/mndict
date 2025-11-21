# Agent Instructions: Build libllama.so for Android (Flutter FFI)

**Purpose:**
Provide step-by-step, concrete tasks for an engineering agent to build a CPU-only, multithreaded `libllama.so` from the existing `llama.cpp` folder, package it for Flutter FFI, and enable runtime loading of GGUF models downloaded from Hugging Face. No code examples — only clear actions, configuration items, and acceptance criteria.

---

## 1. Prerequisites (agent must ensure)

* Install Android SDK and Android NDK (record exact versions used). Use a recent stable NDK that supports arm64 builds.
* Install CMake (version compatible with the chosen NDK) and Ninja build system.
* Ensure `git` and `python` are available for any tooling.
* Confirm the repository contains the `llama.cpp` folder with full source.

Deliverable: a short README line listing the exact SDK/NDK/CMake/Ninja versions used.

---

## 2. Build target decisions (fixed for first iteration)

* ABI to compile: arm64-v8a only (initial). Do not build other ABIs in first pass.
* Android minSdkVersion: 21.
* Output artifact: shared library `libllama.so` (release and debug builds).
* Runtime: CPU-only with multithreading enabled.
* Features to include: GGUF model loader and tokenization; quantization formats required for chosen models (prefer 4-bit quantization support).
* Features to exclude: GPU backends (Vulkan/Metal/NNAPI/Metal), example binaries, tests, and tooling not needed at runtime.

Acceptance: clear list of included/excluded features recorded in build spec.

---

## 3. CMake/Ninja build configuration (what to set)

Agent tasks:

* Create an out-of-source Android build directory and configure CMake with the Android NDK toolchain.
* Use Ninja as the generator to perform compilation.
* Configure CMake options so that the build produces a shared library (.so) and enables the following behavior:

  * Enable GGUF loader support.
  * Enable only the quantization formats that will be used in production (document which ones are enabled).
  * Enable pthread/OpenMP or the threading mechanism used by the llama.cpp codebase.
  * Disable all GPU backends, samples, demo apps, and test executables to reduce binary size.
* Build both Release (optimized) and Debug artifacts.

Deliverable: build script or one-line build instructions (no code) summarizing the commands executed and the resulting paths for artifacts.

---

## 4. ABI & packaging strategy

Agent tasks:

* Produce `libllama.so` for arm64-v8a only.
* Place the resulting `libllama.so` artifact into a deliverable directory with the following structure (for handoff to Flutter packagers):

  * artifacts/android/arm64-v8a/release/libllama.so
  * artifacts/android/arm64-v8a/debug/libllama.so
* Provide a brief packaging note describing where to put .so inside a Flutter plugin (android/src/main/jniLibs/arm64-v8a/) so Gradle will bundle it into the APK.

Acceptance: produced .so files present at the artifact paths.

---

## 5. Native C ABI design (what to implement in C/C++ side)

Agent tasks (implement the ABI inside the native build):

* Expose a minimal, stable C API with these functions (names are guidelines — agent can pick exact names but must match the contract below):

  * init_model(model_path, options) -> returns handle or error code.

    * options must include: thread_count, logging_verbosity, seed (optional), max_context_k.
  * generate(handle, prompt, options) -> synchronous call returning success/failure and a tokenization pointer/length or queued stream.

    * options must include sampling params (top_k, top_p, temperature), max_tokens.
  * stream_next_token(handle) -> returns next token or indicates EOF; this supports incremental streaming.
  * free_model(handle) -> unload model and free memory/resources.
  * get_required_ram_estimate(model_path) -> returns estimated memory footprint or error if format unsupported.
* API behavior requirements:

  * All functions must return clear, documented error codes: SUCCESS, ERR_OOM, ERR_FILE_NOT_FOUND, ERR_UNSUPPORTED_FORMAT, ERR_CORRUPT_FILE, ERR_INVALID_ARGUMENT.
  * init_model should perform format validation and return an estimate of memory footprint and required RAM for successful load.
  * generate must support streaming output (allow Flutter to receive tokens incrementally) rather than buffering the whole response in native memory.
  * Thread-count must be configurable at init time and adjustable between calls if feasible.
  * API must be thread-safe for concurrent read calls where appropriate (document concurrency model).

Deliverable: C header file (API specification) placed in artifacts/include/, documenting function signatures, option structures, error codes, and expected memory ownership semantics.

---

## 6. Flutter integration contract (what Dart/FFI must expect)

Agent tasks (design contract only — Dart implementer will code FFI):

* FFI bindings will call `init_model` with a local file-system path to a GGUF file and options.
* FFI must be able to request streaming tokens (polling or callback). Provide both capabilities if convenient: a `stream_next_token` function and/or a callback registration API.
* The library must not assume where the model file came from; it just receives a valid absolute path.
* Provide clear error codes and a `get_required_ram_estimate` to enable Dart to pre-check device capacity before calling `init_model`.

Acceptance: a clear header + short explanation for how Dart should call each function (argument types and ownership). Place this in artifacts/flutter_contract.md.

---

## 7. Runtime model download & storage (Flutter responsibilities — specify requirements to implement)

Agent must document the downloader requirements for the Flutter developer. The agent is not required to implement the downloader, but must state exact expectations:

* Download over HTTPS only.
* Support resumable downloads for large files and verify integrity via checksum (sha256 or other provided checksum).
* Save model files to app internal storage by default (app-specific files directory). If external storage is used, document necessary permissions and fallback behavior.
* Before starting download, check available disk space and warn/abort if insufficient.
* After download completes, validate the file signature/checksum and make it available to native via an absolute path.
* If a download fails partway, ensure partial files are cleaned up or resumable behavior is supported.
* Provide a small JSON metadata file next to each model that contains: model_name, format (GGUF), quantization, sha256 checksum, recommended_thread_count, required_ram_estimate.

Deliverable: downloader spec for Flutter saved as artifacts/downloader_spec.md.

---

## 8. Runtime behavior & tuning parameters

Agent tasks (implement or document behavior to expose):

* Default thread_count selection: use min(num_cpu_cores, reasonable_max). Document what "reasonable_max" is (e.g., 6 or 8) and why.
* Expose configurable sampling params and max_tokens.
* Expose a function to query runtime stats: current memory usage, peak memory usage, tokens generated per second.
* On OOM or load failure, init_model must return a distinct error code and release any partially allocated memory.
* Provide an option to mmap the model file if supported and documented that mmap warms may be slow on first inference.

Acceptance: runtime options documented and a short guidance file (artifacts/runtime_tuning.md).

---

## 9. Testing & validation (concrete tests agent must run)

Agent must execute the following tests on a real arm64 Android device (emulators are insufficient for performance characterization):

1. Smoke test: load a known small quantized GGUF model and generate a short prompt; verify tokens stream to Dart via FFI and final text matches expected pattern (not necessarily exact outputs; ensure generation completes and returns coherent tokens).
2. Corrupt file test: pass a truncated/corrupt GGUF file and verify init_model returns ERR_CORRUPT_FILE and resources are freed.
3. OOM test: attempt to load a model larger than device RAM and verify init_model returns ERR_OOM and no memory leak exists.
4. Threading test: vary thread_count (1, minimum viable, and a higher value) and measure token/sec and memory delta.
5. Cold start vs warmed test: measure time-to-first-token for fresh load vs second run (when mmap/file cache warmed), record metrics.
6. Packaging test: install APK with packaged .so and ensure native functions are callable via FFI; confirm .so packaged under lib/arm64-v8a in the APK.

Deliverable: test report with device model, Android version, NDK/CMake versions, model used (name + quant), measured metrics (latency, token/sec, memory). Save as artifacts/test_report.md.

---

## 10. CI and reproducible builds

Agent tasks:

* Create a reproducible build script or CI job (documented steps) that clones repo, sets NDK/CMake paths, configures CMake with the chosen flags, runs Ninja, and produces artifacts in the artifacts/ folder.
* Save build logs and create checksums for the produced `.so` files.

Deliverable: build_spec.md and CI job notes saved to artifacts/ci_spec.md.

---

## 11. Security & licensing checks

Agent tasks:

* Verify model license on Hugging Face before recommending download. Document license name and any restrictions.
* Ensure downloader uses HTTPS and verifies checksums.
* Document any third-party licenses from `llama.cpp` or other dependencies and ensure compatibility with intended distribution.

Deliverable: artifacts/license_report.md summarizing model license and code licenses.

---

## 12. Handoff deliverables (exact items to deliver)

Place all deliverables under artifacts/ with the following structure:

* artifacts/android/arm64-v8a/release/libllama.so
* artifacts/android/arm64-v8a/debug/libllama.so
* artifacts/include/llama_native_api.h (C header documenting ABI and error codes)
* artifacts/flutter_contract.md (short guide for Dart FFI bindings and expected behaviors)
* artifacts/downloader_spec.md (requirements for Flutter downloader)
* artifacts/runtime_tuning.md (threading and tuning guidance)
* artifacts/test_report.md (results of tests and measured metrics)
* artifacts/build_spec.md (build commands summary and environment versions)
* artifacts/ci_spec.md (CI build notes)
* artifacts/license_report.md (model & dependency licenses)

Acceptance: all files exist in artifacts/ and README lists how to reproduce the build and how to use the .so from Flutter.

---

## 13. Acceptance criteria (what constitutes "done")

* A working `libllama.so` (arm64-v8a, release) that loads a small quantized GGUF model from an absolute path and generates streaming tokens via the exported C ABI.
* A documented C header describing function signatures, option structures, and error codes.
* Packaging guidance for Flutter (where to place the .so and how to call via FFI) included.
* Test report demonstrating successful load & generation on a real device, plus measured latency, token/sec, and memory usage.
* Build reproducibility notes and version pinning for SDK/NDK/CMake/Ninja.

---

## 14. Notes to agent (practical constraints and helpful hints)

* Start with arm64 only — building multiple ABIs adds significant cross-compile complexity. If a future requirement needs other ABIs, document the necessary changes.
* Prefer quantized models (4-bit) to minimize RAM and improve latency. Ensure the library supports the chosen quantization format.
* Keep the native API minimal; make it easy for Dart to call and receive streaming tokens.
* Document every flag and decision in the build_spec.md to ensure reproducible builds.
* If any upstream changes in `llama.cpp` are required, record code modifications in a small patch and include it in artifacts/patch/.

---

## 15. Communication & progress updates for handoff

When work is complete, attach the artifacts/ folder to the ticket and provide a short summary email or message that includes:

* Where the artifacts are located.
* NDK/CMake/Ninja versions used.
* Which models were tested and their quant formats.
* Any known limitations or TODOs for follow-up (e.g., packaging other ABIs, iOS port later).

---

End of agent instructions.

