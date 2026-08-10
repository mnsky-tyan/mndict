#ifndef LLAMA_NATIVE_API_H
#define LLAMA_NATIVE_API_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// Error codes
#define LLAMA_NATIVE_SUCCESS 0
#define LLAMA_NATIVE_ERR_OOM -1
#define LLAMA_NATIVE_ERR_FILE_NOT_FOUND -2
#define LLAMA_NATIVE_ERR_UNSUPPORTED_FORMAT -3
#define LLAMA_NATIVE_ERR_CORRUPT_FILE -4
#define LLAMA_NATIVE_ERR_INVALID_ARGUMENT -5
#define LLAMA_NATIVE_ERR_UNKNOWN -6
#define LLAMA_NATIVE_EOF -7

// Options for init_model
typedef struct {
    int32_t thread_count;
    int32_t logging_verbosity;
    int32_t seed; // -1 for random
    float max_context_k;
} llama_native_init_options;

// Options for generate
typedef struct {
    int32_t top_k;
    float top_p;
    float temperature;
    int32_t max_tokens;
} llama_native_generate_options;

// Handle type
typedef void* llama_native_handle;

/**
 * Initialize the model from the given path.
 * 
 * @param model_path Absolute path to the GGUF model file.
 * @param options Initialization options.
 * @param handle_out Pointer to store the created model handle.
 * @return LLAMA_NATIVE_SUCCESS on success, or an error code.
 */
int32_t llama_native_init_model(const char* model_path, llama_native_init_options options, llama_native_handle* handle_out);

/**
 * Start generating text for the given prompt.
 * This function prepares the generation but does not block until completion.
 * Use llama_native_stream_next_token to retrieve tokens.
 * 
 * @param handle The model handle.
 * @param prompt The input prompt.
 * @param options Generation options.
 * @return LLAMA_NATIVE_SUCCESS on success, or an error code.
 */
int32_t llama_native_generate(llama_native_handle handle, const char* prompt, llama_native_generate_options options);

/**
 * Retrieve the next generated token.
 * 
 * @param handle The model handle.
 * @param token_text_out Pointer to store the pointer to the token text. 
 *                       The memory for the text is owned by the library and valid until the next call.
 * @return LLAMA_NATIVE_SUCCESS if a token was returned.
 *         LLAMA_NATIVE_EOF if generation is finished.
 *         Error code otherwise.
 */
int32_t llama_native_stream_next_token(llama_native_handle handle, const char** token_text_out);

/**
 * Free the model and release resources.
 * 
 * @param handle The model handle.
 */
void llama_native_free_model(llama_native_handle handle);

/**
 * Estimate the required RAM to load the model.
 * 
 * @param model_path Absolute path to the GGUF model file.
 * @param ram_estimate_out Pointer to store the estimated RAM in bytes.
 * @return LLAMA_NATIVE_SUCCESS on success, or an error code.
 */
int32_t llama_native_get_required_ram_estimate(const char* model_path, uint64_t* ram_estimate_out);

#ifdef __cplusplus
}
#endif

#endif // LLAMA_NATIVE_API_H
