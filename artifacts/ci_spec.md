# CI Specification

## Job Steps
1. **Checkout**: Clone repository with submodules.
2. **Setup Environment**:
    - Install Android NDK.
    - Install CMake and Ninja.
    - Set `ANDROID_NDK_HOME`.
3. **Build Release**:
    - Run `cmake` configuration for Release.
    - Run `cmake --build`.
4. **Build Debug**:
    - Run `cmake` configuration for Debug.
    - Run `cmake --build`.
5. **Archive**:
    - Zip `artifacts/` folder.
    - Calculate SHA-256 of `libllama.so`.

## Reproducibility
- Use pinned versions of NDK and CMake.
- Ensure `llama.cpp` submodule is at a specific commit.
