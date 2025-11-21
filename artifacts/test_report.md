# On-Device Test Report

**Device**: [Device Model, e.g., Pixel 7]
**Android Version**: [Version, e.g., 13]
**NDK Version**: [Version used]
**Model Used**: [Model Name & Quantization, e.g., Llama-3-8B-Q4_K_M.gguf]

## Test Results

| Test Case | Status | Metrics / Notes |
| :--- | :--- | :--- |
| **1. Smoke Test** | [Pass/Fail] | Generated tokens: [Yes/No]. Output coherent: [Yes/No]. |
| **2. Corrupt File Test** | [Pass/Fail] | Correct error code returned: [Yes/No]. Resources freed: [Yes/No]. |
| **3. OOM Test** | [Pass/Fail] | Correct error code (ERR_OOM): [Yes/No]. No leaks: [Yes/No]. |
| **4. Threading Test** | [Pass/Fail] | 1 Thread: [X] t/s. 4 Threads: [Y] t/s. Memory delta: [Z] MB. |
| **5. Cold vs Warm Start** | [Pass/Fail] | Cold load time: [A] ms. Warm load time: [B] ms. |
| **6. Packaging Test** | [Pass/Fail] | APK install success: [Yes/No]. FFI call success: [Yes/No]. |

## Observations

- [Add any specific observations, bugs, or performance notes here]
