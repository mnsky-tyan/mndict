# Android Llama.cpp Library Artifacts

This directory contains the build artifacts and documentation for the Android `libllama.so` library.

## Directory Structure

- **android/**: Contains the compiled shared libraries.
  - `arm64-v8a/release/libllama.so`: Optimized release build.
  - `arm64-v8a/debug/libllama.so`: Debug build with symbols.
- **include/**: Contains the C header file.
  - `llama_native_api.h`: The native C API definition.
- **build_spec.md**: Details the build environment and commands used.
- **ci_spec.md**: Specifications for Continuous Integration.
- **downloader_spec.md**: Requirements for the model downloader.
- **flutter_contract.md**: Contract for Flutter FFI integration.
- **license_report.md**: License information for dependencies.
- **runtime_tuning.md**: Guidance on runtime configuration and tuning.
- **test_report.md**: Template for recording on-device test results.

## Usage

1.  **Integration**: Copy `android/arm64-v8a/release/libllama.so` to your Flutter project's `android/src/main/jniLibs/arm64-v8a/` directory.
2.  **FFI**: Use `include/llama_native_api.h` to define your Dart FFI bindings as described in `flutter_contract.md`.
3.  **Models**: Ensure you download GGUF models to the device storage as per `downloader_spec.md`.

## Reproduction

To reproduce the build:
1.  Ensure Android NDK (r25+) and CMake (3.22+) are installed.
2.  Run `build_android.ps1` from the project root.
