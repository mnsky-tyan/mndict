# Build Specification

## Environment
- **OS**: Windows
- **NDK Version**: 25.1.8937393 (Example, verified in task)
- **CMake Version**: 3.22.1
- **Ninja Version**: 1.11.0

## Build Commands
```powershell
# Configure
cmake -G "Ninja" -S . -B build-android-arm64 `
    -DCMAKE_TOOLCHAIN_FILE="$env:ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake" `
    -DANDROID_ABI="arm64-v8a" `
    -DANDROID_PLATFORM="android-21" `
    -DCMAKE_BUILD_TYPE="Release"

# Build
cmake --build build-android-arm64 --config Release
```

## CMake Options
- `BUILD_SHARED_LIBS=OFF` (llama.cpp static)
- `LLAMA_BUILD_EXAMPLES=OFF`
- `LLAMA_BUILD_TESTS=OFF`
- `LLAMA_BUILD_TOOLS=OFF`
- `LLAMA_BUILD_SERVER=OFF`
- `GGML_CUDA=OFF`
- `GGML_METAL=OFF`
- `GGML_VULKAN=OFF`
- `LLAMA_CURL=OFF`

## Artifacts
- `artifacts/android/arm64-v8a/release/libllama.so`
- `artifacts/android/arm64-v8a/debug/libllama.so`
