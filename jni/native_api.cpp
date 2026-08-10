#include "llama_native_api.h"
#include "llama.h"

#include <string>
#include <vector>
#include <memory>
#include <mutex>
#include <cstring>
#include <iostream>
#include <android/log.h>

struct NativeModel {
    llama_model* model = nullptr;
    llama_context* ctx = nullptr;
    llama_sampler* sampler = nullptr;
    
    std::vector<llama_token> tokens_list;
    int32_t n_past = 0;
    int32_t n_remain = 0;
    
    // Buffer for the current token text to ensure pointer validity
    std::string current_token_text;
};

static std::once_flag flag_backend_init;

static void ensure_backend_init() {
    std::call_once(flag_backend_init, []() {
        llama_backend_init();
    });
}

int32_t llama_native_init_model(const char* model_path, llama_native_init_options options, llama_native_handle* handle_out) {
    ensure_backend_init();

    if (!model_path || !handle_out) {
        return LLAMA_NATIVE_ERR_INVALID_ARGUMENT;
    }

    __android_log_print(ANDROID_LOG_INFO, "LlamaNative", "Initializing model from: %s", model_path);
    __android_log_print(ANDROID_LOG_INFO, "LlamaNative", "Options: threads=%d, context_k=%f", options.thread_count, options.max_context_k);

    llama_model_params model_params = llama_model_default_params();
    model_params.use_mmap = true; // Explicitly enable mmap for lower latency
    // model_params.n_gpu_layers = 0; // CPU only
    
    llama_model* model = llama_model_load_from_file(model_path, model_params);
    if (!model) {
        __android_log_print(ANDROID_LOG_ERROR, "LlamaNative", "Failed to load model from file");
        // TODO: Better error detection (file not found vs corrupt)
        return LLAMA_NATIVE_ERR_FILE_NOT_FOUND;
    }

    llama_context_params ctx_params = llama_context_default_params();
    ctx_params.n_ctx = options.max_context_k > 0 ? (int)(options.max_context_k * 1024) : 2048; // max_context_k is in K (1024s)
    __android_log_print(ANDROID_LOG_INFO, "LlamaNative", "Calculated n_ctx: %d", ctx_params.n_ctx);
    ctx_params.n_threads = options.thread_count > 0 ? options.thread_count : 4;
    ctx_params.n_threads_batch = ctx_params.n_threads;
    ctx_params.flash_attn_type = LLAMA_FLASH_ATTN_TYPE_ENABLED;

    llama_context* ctx = llama_init_from_model(model, ctx_params);
    if (!ctx) {
        llama_model_free(model);
        return LLAMA_NATIVE_ERR_OOM;
    }

    NativeModel* native_model = new NativeModel();
    native_model->model = model;
    native_model->ctx = ctx;
    native_model->sampler = nullptr; // Initialized in generate
    native_model->n_past = 0;        // Initialize context position
    native_model->n_remain = 0;

    *handle_out = static_cast<llama_native_handle>(native_model);
    return LLAMA_NATIVE_SUCCESS;
}


// Helper to add to batch
static void llama_batch_add(struct llama_batch& batch, llama_token id, llama_pos pos, const std::vector<llama_seq_id>& seq_ids, bool logits) {
    batch.token[batch.n_tokens] = id;
    batch.pos[batch.n_tokens] = pos;
    batch.n_seq_id[batch.n_tokens] = seq_ids.size();
    for (size_t i = 0; i < seq_ids.size(); ++i) {
        batch.seq_id[batch.n_tokens][i] = seq_ids[i];
    }
    batch.logits[batch.n_tokens] = logits ? 1 : 0;
    batch.n_tokens++;
}

int32_t llama_native_generate(llama_native_handle handle, const char* prompt, llama_native_generate_options options) {
    if (!handle || !prompt) {
        return LLAMA_NATIVE_ERR_INVALID_ARGUMENT;
    }

    NativeModel* native_model = static_cast<NativeModel*>(handle);
    
    // Reset state for new generation (Single-turn optimization)
    // We discard previous context because the user wants fresh lookups every time.
    native_model->n_past = 0;
    native_model->n_remain = 0;
    
    // Clear KV cache to prevent position conflicts
    llama_memory_t mem = llama_get_memory(native_model->ctx);
    llama_memory_clear(mem, true);
    
    __android_log_print(ANDROID_LOG_INFO, "LlamaNative", "Resetting n_past to 0 and clearing KV cache");

    if (native_model->sampler) {
        // llama_sampler_free(native_model->sampler); 
    }
    
    // Initialize sampler chain
    llama_sampler_chain_params sparams = llama_sampler_chain_default_params();
    native_model->sampler = llama_sampler_chain_init(sparams);
    
    llama_sampler_chain_add(native_model->sampler, llama_sampler_init_top_k(options.top_k));
    llama_sampler_chain_add(native_model->sampler, llama_sampler_init_top_p(options.top_p, 1)); // min_keep = 1
    llama_sampler_chain_add(native_model->sampler, llama_sampler_init_temp(options.temperature));
    llama_sampler_chain_add(native_model->sampler, llama_sampler_init_dist(LLAMA_DEFAULT_SEED));

    __android_log_print(ANDROID_LOG_INFO, "LlamaNative", "Generating for prompt: %s", prompt);
    // Log first 200 chars of prompt to check for corruption/accumulation
    char debug_buf[201];
    std::strncpy(debug_buf, prompt, 200);
    debug_buf[200] = '\0';
    __android_log_print(ANDROID_LOG_INFO, "LlamaNative", "Prompt start: %s", debug_buf);

    const llama_vocab* vocab = llama_model_get_vocab(native_model->model);

    // Tokenize prompt
    // First, get the required buffer size
    const int n_prompt_bytes = std::strlen(prompt);

    int n_prompt_tokens = llama_tokenize(vocab, prompt, n_prompt_bytes, NULL, 0, true, true);
    
    __android_log_print(ANDROID_LOG_INFO, "LlamaNative", "Token count: %d", n_prompt_tokens);

    // Check for tokenization errors (negative value means we need that many tokens)
    if (n_prompt_tokens < 0) {
        n_prompt_tokens = -n_prompt_tokens;
        __android_log_print(ANDROID_LOG_INFO, "LlamaNative", "Tokenization requires %d tokens", n_prompt_tokens);
    }
    
    // Sanity check: make sure token count is reasonable
    if (n_prompt_tokens == 0 || n_prompt_tokens > 100000) {
        __android_log_print(ANDROID_LOG_ERROR, "LlamaNative", "Invalid token count: %d", n_prompt_tokens);
        return LLAMA_NATIVE_ERR_INVALID_ARGUMENT;
    }
    
    std::vector<llama_token> prompt_tokens(n_prompt_tokens);
    int actual_tokens = llama_tokenize(vocab, prompt, n_prompt_bytes, prompt_tokens.data(), n_prompt_tokens, true, true);
    if (actual_tokens < 0 || actual_tokens != n_prompt_tokens) {
        __android_log_print(ANDROID_LOG_ERROR, "LlamaNative", "Second tokenization failed: %d vs %d", actual_tokens, n_prompt_tokens);
        return LLAMA_NATIVE_ERR_UNKNOWN;
    }
    
    __android_log_print(ANDROID_LOG_INFO, "LlamaNative", "Tokenization complete. Starting batch decode.");

    // Prepare batch
    int32_t n_batch = 512;
    llama_batch batch = llama_batch_init(n_batch, 0, 1);

    // Evaluate prompt in chunks
    for (size_t i = 0; i < prompt_tokens.size(); i += n_batch) {
        size_t n_eval = prompt_tokens.size() - i;
        if (n_eval > n_batch) n_eval = n_batch;
        
        __android_log_print(ANDROID_LOG_INFO, "LlamaNative", "Processing batch chunk %zu/%zu, size: %zu", i, prompt_tokens.size(), n_eval);

        // Clear batch for this chunk
        batch.n_tokens = 0;
        
        for (size_t j = 0; j < n_eval; j++) {
            size_t token_idx = i + j;
            // logits needed only for the very last token of the whole prompt
            bool is_last = (token_idx == prompt_tokens.size() - 1);
            
            // Correctly use n_past as the base offset for new tokens
            llama_pos pos = native_model->n_past + token_idx;
            
            llama_batch_add(batch, prompt_tokens[token_idx], pos, { 0 }, is_last);
        }

        if (llama_decode(native_model->ctx, batch) != 0) {
            __android_log_print(ANDROID_LOG_ERROR, "LlamaNative", "llama_decode failed for batch chunk at index %zu", i);
            llama_batch_free(batch);
            return LLAMA_NATIVE_ERR_UNKNOWN;
        }
    }
    
    // Update n_past by adding the number of tokens we just processed
    native_model->n_past += prompt_tokens.size();
    native_model->n_remain = options.max_tokens;
    
    __android_log_print(ANDROID_LOG_INFO, "LlamaNative", "Generation setup complete. New n_past: %d, n_remain: %d", native_model->n_past, native_model->n_remain);

    llama_batch_free(batch);
    return LLAMA_NATIVE_SUCCESS;
}

int32_t llama_native_stream_next_token(llama_native_handle handle, const char** token_text_out) {
    if (!handle || !token_text_out) {
        return LLAMA_NATIVE_ERR_INVALID_ARGUMENT;
    }

    NativeModel* native_model = static_cast<NativeModel*>(handle);

    if (native_model->n_remain <= 0) {
        __android_log_print(ANDROID_LOG_INFO, "LlamaNative", "Hit token limit (n_remain <= 0)");
        return LLAMA_NATIVE_EOF;
    }

    // Sample next token
    llama_token new_token_id = llama_sampler_sample(native_model->sampler, native_model->ctx, -1);
    
    // Accept token (update sampler state)
    llama_sampler_accept(native_model->sampler, new_token_id);

    const llama_vocab* vocab = llama_model_get_vocab(native_model->model);

    // Check for EOS
    if (llama_vocab_is_eog(vocab, new_token_id)) {
        __android_log_print(ANDROID_LOG_INFO, "LlamaNative", "Hit EOS token");
        native_model->n_remain = 0;
        return LLAMA_NATIVE_EOF;
    }

    // Detokenize
    char buf[256];
    int n = llama_token_to_piece(vocab, new_token_id, buf, sizeof(buf), 0, true);
    if (n < 0) {
        // Buffer too small?
        native_model->current_token_text = ""; // Should handle better
    } else {
        native_model->current_token_text = std::string(buf, n);
    }
    
    *token_text_out = native_model->current_token_text.c_str();
    
    __android_log_print(ANDROID_LOG_INFO, "LlamaNative", "Generated token: '%s' (id: %d)", *token_text_out, new_token_id);

    // Check for stop strings (hallucinations/next turn markers)
    // Check for stop strings (hallucinations/next turn markers)
    const char* text = *token_text_out;
    if (strstr(text, "<|user|>") || strstr(text, "<|assistant|>") || 
        strstr(text, "<luser") || strstr(text, "<lassistant") ||
        strstr(text, "<|end|>") || strstr(text, "<|system|>") ||
        strstr(text, "<|im_end|>") || strstr(text, "<|im_start|>") ||
        strstr(text, "<|eot_id|>") || strstr(text, "<leot-id") ||
        strstr(text, "<|start_header_id|>") || strstr(text, "<Istart-header-id") ||
        strstr(text, "<|end_header_id|>") || strstr(text, "<lend-header-id") ||
        strstr(text, "<leot-idl>") || strstr(text, "< start-header-idl>") ||
        strstr(text, "<lend-header-idl>") || strstr(text, "idl>")) {
        
        __android_log_print(ANDROID_LOG_INFO, "LlamaNative", "Stop string detected: %s. Stopping generation.", text);
        native_model->n_remain = 0;
        return LLAMA_NATIVE_EOF;
    }

    // Prepare next batch (single token)
    llama_batch batch = llama_batch_init(1, 0, 1);
    llama_batch_add(batch, new_token_id, native_model->n_past, { 0 }, true);
    
    if (llama_decode(native_model->ctx, batch) != 0) {
        __android_log_print(ANDROID_LOG_ERROR, "LlamaNative", "llama_decode failed during streaming");
        llama_batch_free(batch);
        return LLAMA_NATIVE_ERR_UNKNOWN;
    }
    
    native_model->n_past += 1;
    native_model->n_remain -= 1;
    
    llama_batch_free(batch);

    return LLAMA_NATIVE_SUCCESS;
}

void llama_native_free_model(llama_native_handle handle) {
    if (!handle) return;
    NativeModel* native_model = static_cast<NativeModel*>(handle);
    
    if (native_model->sampler) {
        llama_sampler_free(native_model->sampler);
    }
    if (native_model->ctx) {
        llama_free(native_model->ctx);
    }
    if (native_model->model) {
        llama_model_free(native_model->model);
    }
    
    delete native_model;
}

int32_t llama_native_get_required_ram_estimate(const char* model_path, uint64_t* ram_estimate_out) {
    if (!model_path || !ram_estimate_out) {
        return LLAMA_NATIVE_ERR_INVALID_ARGUMENT;
    }
    
    // Try to load the model to get the size
    // This is a heavy operation but accurate
    llama_model_params model_params = llama_model_default_params();
    model_params.vocab_only = true; // Load only vocab to be fast? No, we need full size.
    // Actually, we can't easily estimate without loading. 
    // But if we load with mmap, it shouldn't consume all RAM immediately.
    
    llama_model* model = llama_model_load_from_file(model_path, model_params);
    if (!model) {
        return LLAMA_NATIVE_ERR_FILE_NOT_FOUND;
    }
    
    uint64_t size = llama_model_size(model);
    // Add some overhead for context
    size += 1024 * 1024 * 100; // +100MB arbitrary overhead for context
    
    *ram_estimate_out = size;
    
    llama_model_free(model);
    return LLAMA_NATIVE_SUCCESS;
}
