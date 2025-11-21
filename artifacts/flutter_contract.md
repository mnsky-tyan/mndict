# Flutter Integration Contract

## Overview
The `libllama.so` library exposes a C API for loading and running GGUF models. Flutter should use `dart:ffi` to bind to these functions.

## API Functions

### `init_model`
```c
int32_t llama_native_init_model(const char* model_path, llama_native_init_options options, llama_native_handle* handle_out);
```
- **Dart Signature**: `Int32 Function(Pointer<Utf8>, NativeInitOptions, Pointer<Pointer<Void>>)`
- **Behavior**: Loads the model from `model_path`. Returns 0 on success.
- **Ownership**: The `handle_out` receives a pointer to the native model instance. This handle must be passed to other functions and eventually freed with `free_model`.

### `generate`
```c
int32_t llama_native_generate(llama_native_handle handle, const char* prompt, llama_native_generate_options options);
```
- **Dart Signature**: `Int32 Function(Pointer<Void>, Pointer<Utf8>, NativeGenerateOptions)`
- **Behavior**: Prepares generation for the given prompt. Does NOT block for full generation. Returns 0 on success.

### `stream_next_token`
```c
int32_t llama_native_stream_next_token(llama_native_handle handle, const char** token_text_out);
```
- **Dart Signature**: `Int32 Function(Pointer<Void>, Pointer<Pointer<Utf8>>)`
- **Behavior**: Retrieves the next token.
    - Returns `0` (SUCCESS) if a token is available. `token_text_out` will point to a null-terminated string valid until the next call.
    - Returns `-7` (EOF) if generation is finished.
    - Returns other negative values on error.

### `free_model`
```c
void llama_native_free_model(llama_native_handle handle);
```
- **Dart Signature**: `Void Function(Pointer<Void>)`
- **Behavior**: Frees all resources associated with the model handle.

### `get_required_ram_estimate`
```c
int32_t llama_native_get_required_ram_estimate(const char* model_path, uint64_t* ram_estimate_out);
```
- **Dart Signature**: `Int32 Function(Pointer<Utf8>, Pointer<Uint64>)`
- **Behavior**: Returns estimated RAM usage in bytes.

## Structs

### `llama_native_init_options`
- `int32_t thread_count`: Number of threads (e.g., 4).
- `int32_t logging_verbosity`: 0 = off, 1 = error, 2 = info.
- `int32_t seed`: -1 for random.
- `int32_t max_context_k`: Context size (e.g., 2048).

### `llama_native_generate_options`
- `int32_t top_k`: e.g., 40.
- `float top_p`: e.g., 0.95.
- `float temperature`: e.g., 0.8.
- `int32_t max_tokens`: Max tokens to generate.

## Error Codes
- `0`: SUCCESS
- `-1`: ERR_OOM
- `-2`: ERR_FILE_NOT_FOUND
- `-3`: ERR_UNSUPPORTED_FORMAT
- `-4`: ERR_CORRUPT_FILE
- `-5`: ERR_INVALID_ARGUMENT
- `-6`: ERR_UNKNOWN
- `-7`: EOF
