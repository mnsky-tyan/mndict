#include "llama_native_api.h"
#include "llama.h"
#include "common.h"
#include "sampling.h"
#include "speculative.h"

#include <string>
#include <vector>
#include <deque>
#include <memory>
#include <mutex>
#include <cstring>
#include <iostream>
#include <algorithm>
#include <chrono>
#include <android/log.h>

struct NativeModel {
    llama_model* model = nullptr;
    llama_context* ctx = nullptr;
    common_sampler* smpl = nullptr;

    // Speculative decoding (optional, attached via llama_native_attach_draft)
    common_speculative_init_result_ptr spec_init; // owns draft model+ctx
    common_speculative* spec = nullptr;
    llama_context* ctx_dft = nullptr;
    int32_t n_draft_max = 8;
    int32_t thread_count = 4;
    llama_tokens spec_prompt;                // token history for the drafter (excludes id_last)
    llama_token id_last = 0;                 // token not yet fed to the target KV
    std::deque<llama_token> pending;         // accepted tokens awaiting emission
    bool gen_done = false;                   // round hit EOG; drain pending then EOF
    bool spec_active = false;

    // Partial-acceptance handling. The target model (LFM2.5 hybrid GDN+attn)
    // cannot seq_rm, so rejected draft cells cannot be rewound in place.
    // Upstream answer (speculative-simple): snapshot the target state before
    // verification and restore it on partial acceptance; the accepted prefix
    // is then re-verified next round (draft_reverify).
    common_prompt_checkpoint ckpt;
    llama_tokens draft_reverify;
    bool use_ckpt_tgt = false;
    int partial_streak = 0;

    int32_t n_past = 0;
    int32_t n_remain = 0;
    bool affinity_ok = false;  // fast-core pin applied (ggml workers inherit it)

    // Buffer for the current token text to ensure pointer validity
    std::string current_token_text;

    // Decode-speed accounting (one summary log per generation)
    std::chrono::steady_clock::time_point gen_start;
    int32_t gen_tokens = 0;
    bool summary_logged = false;
};

static std::once_flag flag_backend_init;

// Route llama.cpp/ggml internal logs to logcat (tag "llama.cpp") so spec/draft
// warnings are visible during on-device debugging.
static void native_log_callback(ggml_log_level level, const char* text, void* user_data) {
    (void) user_data;
    const android_LogPriority prio =
        level == GGML_LOG_LEVEL_ERROR ? ANDROID_LOG_ERROR :
        level == GGML_LOG_LEVEL_WARN  ? ANDROID_LOG_WARN  : ANDROID_LOG_INFO;
    __android_log_print(prio, "llama.cpp", "%s", text);
}

static void ensure_backend_init() {
    std::call_once(flag_backend_init, []() {
        llama_log_set(native_log_callback, nullptr);
        llama_backend_init();
    });
}

#if defined(__linux__)
#include <sched.h>
#include <fstream>
#include <cerrno>

// Pin the calling thread (and every inference worker thread it later creates,
// which inherit its mask) to the n_threads highest-frequency CPUs. Without
// this the scheduler floats decode threads onto the little cores; measured
// ~18% slower tg128 on the Dimensity 8300 (1x A715 3.35GHz + 3x 2.85GHz +
// 4x A510 2.0GHz). Mirrors MNN's BackendConfig Power_High. Returns false if
// the OS rejected every candidate mask (e.g. app cold-start cpuset excludes
// the fast cores — retried at generate time, when the app is foreground).
static bool pin_to_fast_cores(int n_threads) {
    std::vector<std::pair<long, int>> freqs;  // (cpuinfo_max_freq khz, cpu)
    for (int cpu = 0; cpu < 64; cpu++) {
        std::ifstream f("/sys/devices/system/cpu/cpu" + std::to_string(cpu) +
                        "/cpufreq/cpuinfo_max_freq");
        long khz = 0;
        if ((f >> khz) && khz > 0) freqs.push_back({khz, cpu});
    }
    if (n_threads <= 0 || (int)freqs.size() < n_threads) return false;
    std::sort(freqs.rbegin(), freqs.rend());

    cpu_set_t allowed;
    CPU_ZERO(&allowed);
    if (sched_getaffinity(0, sizeof(allowed), &allowed) != 0) return false;

    // Preferred: exactly the n_threads fastest CPUs (prime+big clusters).
    // Fallback: the fastest CPUs the process is actually allowed to use, so a
    // restricted cpuset degrades to pinning within it instead of EINVAL.
    for (int attempt = 0; attempt < 2; attempt++) {
        cpu_set_t set;
        CPU_ZERO(&set);
        std::string cpus;
        int picked = 0;
        for (const auto& [khz, cpu] : freqs) {
            if (picked == n_threads) break;
            if (attempt == 1 && !CPU_ISSET(cpu, &allowed)) continue;
            CPU_SET(cpu, &set);
            cpus += " cpu" + std::to_string(cpu) + "@" + std::to_string(khz / 1000) + "MHz";
            picked++;
        }
        if (picked < n_threads) continue;
        if (sched_setaffinity(0, sizeof(set), &set) == 0) {
            __android_log_print(ANDROID_LOG_INFO, "LlamaNative", "Pinned inference to:%s%s",
                                cpus.c_str(), attempt == 1 ? " (allowed-subset)" : "");
            return true;
        }
    }
    __android_log_print(ANDROID_LOG_WARN, "LlamaNative",
                        "sched_setaffinity rejected (allowed mask may exclude all fast cores)");
    return false;
}
#endif

// One summary per generation, on whichever EOF path ends it first.
static void log_decode_summary(NativeModel* native_model) {
    if (native_model->summary_logged) return;
    native_model->summary_logged = true;
    const auto elapsed_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::steady_clock::now() - native_model->gen_start).count();
    __android_log_print(ANDROID_LOG_INFO, "LlamaNative", "Decode summary: %d tokens in %lld ms (%.1f tok/s)",
                        native_model->gen_tokens, (long long)elapsed_ms,
                        elapsed_ms > 0 ? native_model->gen_tokens * 1000.0 / elapsed_ms : 0.0);
}

int32_t llama_native_init_model(const char* model_path, llama_native_init_options options, llama_native_handle* handle_out) {
    ensure_backend_init();

    if (!model_path || !handle_out) {
        return LLAMA_NATIVE_ERR_INVALID_ARGUMENT;
    }

    __android_log_print(ANDROID_LOG_INFO, "LlamaNative", "Initializing model from: %s", model_path);
    __android_log_print(ANDROID_LOG_INFO, "LlamaNative", "Options: threads=%d, context_k=%f", options.thread_count, options.max_context_k);

    llama_model_params model_params = llama_model_default_params();
    // MMAP + MLOCK: mmap alone lets Android evict model pages under RAM
    // pressure, and each evicted page re-reads from flash mid-decode (measured
    // ~10x slowdown on a Xiaomi 14T). MLOCK pins the pages in RAM.
    model_params.load_mode = LLAMA_LOAD_MODE_MMAP_MLOCK;
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
#if defined(__linux__)
    // Must run before llama_init_from_model: the context builds its ggml
    // threadpool on the calling thread, which inherits this affinity. May
    // fail during app cold-start (restricted cpuset); retried per generate.
    const bool pinned_now = pin_to_fast_cores(ctx_params.n_threads);
#endif
    ctx_params.flash_attn_type = LLAMA_FLASH_ATTN_TYPE_ENABLED;
    // Quantized KV cache halves context RAM (matters for the 5GB MoE on 8GB
    // phones); requires flash attention. Flip to GGML_TYPE_F16 if a model
    // hits the slow FA+q8_0 path.
    ctx_params.type_k = GGML_TYPE_Q8_0;
    ctx_params.type_v = GGML_TYPE_Q8_0;

    llama_context* ctx = llama_init_from_model(model, ctx_params);
    if (!ctx) {
        llama_model_free(model);
        return LLAMA_NATIVE_ERR_OOM;
    }

    NativeModel* native_model = new NativeModel();
    native_model->model = model;
    native_model->ctx = ctx;
    native_model->thread_count = ctx_params.n_threads;
    native_model->n_past = 0;
    native_model->n_remain = 0;
#if defined(__linux__)
    native_model->affinity_ok = pinned_now;
#endif

    *handle_out = static_cast<llama_native_handle>(native_model);
    return LLAMA_NATIVE_SUCCESS;
}

int32_t llama_native_attach_draft(llama_native_handle handle, const char* draft_path, int32_t n_draft_max) {
    if (!handle || !draft_path) {
        return LLAMA_NATIVE_ERR_INVALID_ARGUMENT;
    }
    NativeModel* native_model = static_cast<NativeModel*>(handle);
    if (!native_model->model || !native_model->ctx) {
        return LLAMA_NATIVE_ERR_INVALID_ARGUMENT;
    }

    __android_log_print(ANDROID_LOG_INFO, "LlamaNative", "Attaching draft model: %s", draft_path);

    // Upstream convention: init_from_params loads the draft from
    // params.model.path (common_base_params_to_speculative swaps it in).
    common_params params;
    params.model.path = draft_path;
    params.speculative.draft.mparams.path = draft_path;
    params.speculative.draft.n_max = n_draft_max > 0 ? n_draft_max : 8;
    params.speculative.draft.n_min = 0;
    // init_from_params maps ctx_dft threads from the top-level cpuparams; a
    // default-constructed params carries n_threads = -1, which creates a draft
    // context whose decodes all fail.
    params.cpuparams.n_threads = native_model->thread_count;
    params.cpuparams_batch.n_threads = native_model->thread_count;
    params.speculative.draft.cpuparams.n_threads = native_model->thread_count;
    params.speculative.draft.cpuparams_batch.n_threads = native_model->thread_count;
    // The draft block decode samples every position of [id_last, mask...] in
    // one pass (backend-attached samplers), so the draft context must allow
    // n_max+1 outputs per sequence. Upstream tools get this from
    // common_base_params_to_speculative; a default params has 1, which fails
    // every draft decode with "backend sampling supports at most 1 outputs".
    const int32_t n_outputs_per_seq = (n_draft_max > 0 ? n_draft_max : 8) + 1;
    params.n_outputs_max = n_outputs_per_seq;
    params.n_outputs_max_per_seq = n_outputs_per_seq;

    // Prefer the implementation the draft GGUF was made for; fall back to a
    // plain greedy draft model.
    auto types = common_speculative_types_from_gguf(draft_path);
    if (types.empty()) {
        types = { COMMON_SPECULATIVE_TYPE_DRAFT_DSPARK, COMMON_SPECULATIVE_TYPE_DRAFT_SIMPLE };
    }
    params.speculative.types = types;
    {
        std::string types_str;
        for (auto t : types) {
            if (!types_str.empty()) types_str += ",";
            types_str += common_speculative_type_to_str(t);
        }
        __android_log_print(ANDROID_LOG_INFO, "LlamaNative", "Speculative types: %s", types_str.c_str());
    }

    auto spec_init = common_speculative_init_from_params(params, native_model->model, native_model->ctx);
    if (!spec_init || !spec_init->model() || !spec_init->context()) {
        __android_log_print(ANDROID_LOG_ERROR, "LlamaNative", "Failed to load draft model");
        return LLAMA_NATIVE_ERR_FILE_NOT_FOUND;
    }

    params.speculative.draft.ctx_tgt = native_model->ctx;
    params.speculative.draft.ctx_dft = spec_init->context();

    llama_context* ctx_dft = spec_init->context();

    common_speculative* spec = common_speculative_init(params.speculative, 1);
    if (!spec) {
        __android_log_print(ANDROID_LOG_ERROR, "LlamaNative", "Failed to init speculative decoding");
        return LLAMA_NATIVE_ERR_UNKNOWN;
    }

    native_model->spec_init = std::move(spec_init);
    native_model->spec = spec;
    native_model->ctx_dft = ctx_dft;
    native_model->n_draft_max = params.speculative.draft.n_max;
    native_model->spec_active = true;
    // can_seq_rm probes the memory with a 2-token decode; safe here, the
    // context is idle and every generate() clears the KV anyway. FULL means
    // the memory cannot remove ranges -> checkpoints are required.
    native_model->use_ckpt_tgt =
        common_context_can_seq_rm(native_model->ctx) == COMMON_CONTEXT_SEQ_RM_TYPE_FULL;
    __android_log_print(ANDROID_LOG_INFO, "LlamaNative", "Target checkpoint mode: %s",
                        native_model->use_ckpt_tgt ? "on (memory cannot seq_rm)" : "off (seq_rm supported)");

    __android_log_print(ANDROID_LOG_INFO, "LlamaNative", "Speculative decoding active (n_draft_max=%d)",
                        native_model->n_draft_max);
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

#if defined(__linux__)
    // Cold-start cpuset can reject the pin at model load; by the first real
    // lookup the app is foreground with the full cpuset. The ggml worker pool
    // is spawned per graph compute from this thread, so a late pin still
    // reaches every worker.
    if (!native_model->affinity_ok) {
        native_model->affinity_ok = pin_to_fast_cores(native_model->thread_count);
    }
#endif

    // Reset state for new generation (Single-turn optimization)
    // We discard previous context because the user wants fresh lookups every time.
    native_model->n_past = 0;
    native_model->n_remain = 0;
    native_model->pending.clear();
    native_model->draft_reverify.clear();
    native_model->ckpt.clear();
    native_model->partial_streak = 0;

    // Clear KV cache to prevent position conflicts
    llama_memory_t mem = llama_get_memory(native_model->ctx);
    llama_memory_clear(mem, true);
    if (native_model->ctx_dft) {
        llama_memory_clear(llama_get_memory(native_model->ctx_dft), true);
    }

    __android_log_print(ANDROID_LOG_INFO, "LlamaNative", "Resetting n_past to 0 and clearing KV cache");

    // Sampler chain (fresh per generation)
    if (native_model->smpl) {
        common_sampler_free(native_model->smpl);
        native_model->smpl = nullptr;
    }
    common_params_sampling sp;
    sp.top_k = options.top_k;
    sp.top_p = options.top_p;
    sp.temp = options.temperature;
    sp.seed = LLAMA_DEFAULT_SEED;
    native_model->smpl = common_sampler_init(native_model->model, sp);

    __android_log_print(ANDROID_LOG_INFO, "LlamaNative", "Generating for prompt: %s", prompt);
    char debug_buf[201];
    std::strncpy(debug_buf, prompt, 200);
    debug_buf[200] = '\0';
    __android_log_print(ANDROID_LOG_INFO, "LlamaNative", "Prompt start: %s", debug_buf);

    const llama_vocab* vocab = llama_model_get_vocab(native_model->model);

    const int n_prompt_bytes = std::strlen(prompt);
    int n_prompt_tokens = llama_tokenize(vocab, prompt, n_prompt_bytes, NULL, 0, true, true);

    __android_log_print(ANDROID_LOG_INFO, "LlamaNative", "Token count: %d", n_prompt_tokens);

    if (n_prompt_tokens < 0) {
        n_prompt_tokens = -n_prompt_tokens;
    }

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

    // Feed all prompt tokens except the last; the last one (id_last) is fed
    // by the first stream_next_token call. This mirrors the speculative loop
    // invariant: id_last is never in the KV cache until it is batched.
    const int n_feed = n_prompt_tokens - 1;
    const int32_t n_batch = 512;
    llama_batch batch = llama_batch_init(n_batch, 0, 1);

    for (int i = 0; i < n_feed; i += n_batch) {
        int n_eval = std::min(n_feed - i, n_batch);
        batch.n_tokens = 0;
        for (int j = 0; j < n_eval; j++) {
            llama_batch_add(batch, prompt_tokens[i + j], i + j, { 0 }, false);
        }
        if (llama_decode(native_model->ctx, batch) != 0) {
            __android_log_print(ANDROID_LOG_ERROR, "LlamaNative", "llama_decode failed for batch chunk at index %d", i);
            llama_batch_free(batch);
            return LLAMA_NATIVE_ERR_UNKNOWN;
        }
        // Prime the draft model's context along the prompt - without this the
        // drafter runs at the wrong positions and crashes on the first round.
        if (native_model->spec && !common_speculative_process(native_model->spec, batch)) {
            __android_log_print(ANDROID_LOG_ERROR, "LlamaNative", "speculative prompt processing failed");
            llama_batch_free(batch);
            return LLAMA_NATIVE_ERR_UNKNOWN;
        }
    }
    llama_batch_free(batch);

    native_model->n_past = n_feed;
    native_model->id_last = prompt_tokens.back();
    // Upstream keeps the drafter's prompt view excluding id_last; each round
    // appends the previous id_last as tokens are accepted.
    native_model->spec_prompt.assign(prompt_tokens.begin(), prompt_tokens.end() - 1);
    native_model->n_remain = options.max_tokens;
    native_model->gen_done = false;
    native_model->gen_start = std::chrono::steady_clock::now();
    native_model->gen_tokens = 0;
    native_model->summary_logged = false;

    if (native_model->spec) {
        common_speculative_begin(native_model->spec, 0, native_model->spec_prompt);
    }

    __android_log_print(ANDROID_LOG_INFO, "LlamaNative", "Generation setup complete. n_past: %d, n_remain: %d, spec: %s",
                        native_model->n_past, native_model->n_remain, native_model->spec ? "on" : "off");

    return LLAMA_NATIVE_SUCCESS;
}

// Run one speculative round: draft from the draft model, verify with the
// target, and queue the accepted tokens. Returns false on decode failure.
//
// Mirrors examples/speculative-simple, including the checkpoint path for the
// target model: LFM2.5's hybrid memory cannot seq_rm, so a partial acceptance
// restores the target from the pre-round snapshot and the accepted prefix is
// re-verified next round instead of being rewound in place.
static bool spec_round(NativeModel* nm) {
    auto pos_max = [](llama_memory_t mem) {
        return (int) llama_memory_seq_pos_max(mem, 0);
    };
    llama_memory_t mem_tgt = llama_get_memory(nm->ctx);
    llama_memory_t mem_dft = llama_get_memory(nm->ctx_dft);

    llama_tokens draft;

    if (nm->draft_reverify.empty()) {
        // Fresh draft round: snapshot bookkeeping, draft, and reset the draft
        // KV so the verification injection stays contiguous.
        nm->ckpt.update_pos((int64_t) nm->spec_prompt.size(),
                            (llama_pos) llama_memory_seq_pos_min(mem_tgt, 0),
                            (llama_pos) pos_max(mem_tgt));

        const int32_t n_ctx = (int32_t) llama_n_ctx(nm->ctx);
        int32_t n_cap = nm->n_draft_max;
        n_cap = std::min(n_cap, n_ctx - nm->n_past - 2);
        n_cap = std::min(n_cap, nm->n_remain - 1);
        n_cap = std::max(n_cap, 0);

        common_speculative_get_draft_params(nm->spec, 0) = {
            /* .drafting = */ true,
            /* .n_max    = */ n_cap,
            /* .n_past   = */ nm->n_past,
            /* .id_last  = */ nm->id_last,
            /* .prompt   = */ &nm->spec_prompt,
            /* .result   = */ &draft,
        };
        common_speculative_draft(nm->spec);

        if (!draft.empty() && nm->use_ckpt_tgt) {
            nm->ckpt.update_tgt(nm->ctx, 0, LLAMA_STATE_SEQ_FLAGS_PARTIAL_ONLY);
        }

        // The draft block decode parked its tokens at [n_past, ...) in the
        // draft KV - the draft memory supports seq_rm, unlike the target.
        llama_memory_seq_rm(mem_dft, 0, nm->ckpt.pos_max + 1, -1);
    } else {
        // Re-verify round: replay the accepted prefix from the restored state.
        draft = std::move(nm->draft_reverify);
        nm->draft_reverify.clear();
    }

    llama_batch batch = llama_batch_init(1 + draft.size(), 0, 1);
    llama_batch_add(batch, nm->id_last, nm->n_past++, { 0 }, true);
    for (size_t i = 0; i < draft.size(); ++i) {
        llama_batch_add(batch, draft[i], nm->n_past + (llama_pos)i, { 0 }, true);
    }
    if (llama_decode(nm->ctx, batch) != 0) {
        __android_log_print(ANDROID_LOG_ERROR, "LlamaNative", "llama_decode failed during speculative round");
        llama_batch_free(batch);
        return false;
    }
    if (!common_speculative_process(nm->spec, batch)) {
        __android_log_print(ANDROID_LOG_ERROR, "LlamaNative", "speculative process failed");
        llama_batch_free(batch);
        return false;
    }
    llama_batch_free(batch);

    const size_t n_draft = draft.size();

    // Sampler state as of before verification - partial acceptance replays
    // the round with the restored state, so the resampled tokens must match.
    common_sampler_ptr smpl_save;
    if (nm->use_ckpt_tgt) {
        smpl_save.reset(common_sampler_clone(nm->smpl));
    }

    auto ids = common_sampler_sample_and_accept_n(nm->smpl, nm->ctx, draft);
    GGML_ASSERT(!ids.empty());

    if (nm->use_ckpt_tgt && ids.size() - 1 < n_draft) {
        // Partial acceptance: rewind via checkpoint, re-verify next round.
        nm->partial_streak++;
        if (nm->partial_streak > 16) {
            __android_log_print(ANDROID_LOG_ERROR, "LlamaNative", "speculative re-verify stuck");
            return false;
        }
        nm->draft_reverify = std::move(ids);
        nm->ckpt.load_tgt(nm->ctx, 0, LLAMA_STATE_SEQ_FLAGS_PARTIAL_ONLY);
        // Restore replaced the whole sequence; the range removal is a no-op
        // on memories that support it and on those that do not.
        llama_memory_seq_rm(mem_tgt, 0, nm->ckpt.pos_max + 1, -1);
        llama_memory_seq_rm(mem_dft, 0, nm->ckpt.pos_max + 1, -1);
        nm->spec_prompt.resize(nm->ckpt.n_tokens);
        if (smpl_save) {
            common_sampler_free(nm->smpl);
            nm->smpl = smpl_save.release();
        }
        nm->n_past = (int32_t) nm->spec_prompt.size();
        __android_log_print(ANDROID_LOG_INFO, "LlamaNative", "spec partial: %d/%d accepted, rewound to %d (tgt max %d)",
                            (int32_t) nm->draft_reverify.size() - 1, (int32_t) n_draft, nm->n_past, pos_max(mem_tgt));
        return true;
    }
    nm->partial_streak = 0;

    common_speculative_accept(nm->spec, 0, (int32_t) ids.size() - 1);
    nm->n_past += (int32_t) ids.size() - 1;

    const llama_vocab* vocab = llama_model_get_vocab(nm->model);
    for (size_t i = 0; i < ids.size(); ++i) {
        nm->spec_prompt.push_back(nm->id_last);
        nm->id_last = ids[i];
        if (llama_vocab_is_eog(vocab, nm->id_last)) {
            nm->gen_done = true;
            break;
        }
        nm->pending.push_back(ids[i]);
    }

    llama_memory_seq_rm(mem_tgt, 0, nm->n_past, -1);
    llama_memory_seq_rm(mem_dft, 0, nm->n_past, -1);

    __android_log_print(ANDROID_LOG_INFO, "LlamaNative", "spec round: accepted %d/%d, +%d tokens (tgt max %d)",
                        (int32_t) ids.size() - 1, (int32_t) n_draft, (int32_t) ids.size(), pos_max(mem_tgt));
    return true;
}

// Non-speculative round: feed id_last, sample one token.
static bool plain_round(NativeModel* nm) {
    llama_batch batch = llama_batch_init(1, 0, 1);
    llama_batch_add(batch, nm->id_last, nm->n_past++, { 0 }, true);
    if (llama_decode(nm->ctx, batch) != 0) {
        __android_log_print(ANDROID_LOG_ERROR, "LlamaNative", "llama_decode failed during streaming");
        llama_batch_free(batch);
        return false;
    }
    llama_batch_free(batch);

    llama_token tok = common_sampler_sample(nm->smpl, nm->ctx, -1);
    common_sampler_accept(nm->smpl, tok, true);
    nm->id_last = tok;
    nm->spec_prompt.push_back(tok);
    nm->pending.push_back(tok);
    return true;
}

int32_t llama_native_stream_next_token(llama_native_handle handle, const char** token_text_out) {
    if (!handle || !token_text_out) {
        return LLAMA_NATIVE_ERR_INVALID_ARGUMENT;
    }

    NativeModel* native_model = static_cast<NativeModel*>(handle);

    if (native_model->n_remain <= 0) {
        __android_log_print(ANDROID_LOG_INFO, "LlamaNative", "Hit token limit (n_remain <= 0)");
        log_decode_summary(native_model);
        return LLAMA_NATIVE_EOF;
    }

    // A partial-acceptance round leaves pending empty by design (the accepted
    // prefix is re-verified next round), so loop until tokens are available.
    while (native_model->pending.empty()) {
        if (native_model->gen_done) {
            log_decode_summary(native_model);
            return LLAMA_NATIVE_EOF;
        }
        bool ok = native_model->spec ? spec_round(native_model) : plain_round(native_model);
        if (!ok) {
            log_decode_summary(native_model);
            return LLAMA_NATIVE_ERR_UNKNOWN;
        }
    }

    const llama_token new_token_id = native_model->pending.front();
    native_model->pending.pop_front();
    native_model->n_remain -= 1;
    native_model->gen_tokens += 1;

    const llama_vocab* vocab = llama_model_get_vocab(native_model->model);

    // Check for EOS
    if (llama_vocab_is_eog(vocab, new_token_id)) {
        __android_log_print(ANDROID_LOG_INFO, "LlamaNative", "Hit EOS token");
        log_decode_summary(native_model);
        native_model->n_remain = 0;
        native_model->pending.clear();
        return LLAMA_NATIVE_EOF;
    }

    // Detokenize
    char buf[256];
    int n = llama_token_to_piece(vocab, new_token_id, buf, sizeof(buf), 0, true);
    if (n < 0) {
        native_model->current_token_text = "";
    } else {
        native_model->current_token_text = std::string(buf, n);
    }

    *token_text_out = native_model->current_token_text.c_str();

    // Per-token logcat writes cost ~10-30ms each on MIUI logd and dominated
    // decode time. Define LLAMA_NATIVE_VERBOSE to restore them for debugging.
#ifdef LLAMA_NATIVE_VERBOSE
    __android_log_print(ANDROID_LOG_INFO, "LlamaNative", "Generated token: '%s' (id: %d)", *token_text_out, new_token_id);
#endif

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
        strstr(text, "<end_of_turn>") || strstr(text, "<turn|>") ||
        strstr(text, "<lend-header-idl>") || strstr(text, "idl>")) {

        __android_log_print(ANDROID_LOG_INFO, "LlamaNative", "Stop string detected: %s. Stopping generation.", text);
        log_decode_summary(native_model);
        native_model->n_remain = 0;
        native_model->pending.clear();
        return LLAMA_NATIVE_EOF;
    }

    return LLAMA_NATIVE_SUCCESS;
}

void llama_native_free_model(llama_native_handle handle) {
    if (!handle) return;
    NativeModel* native_model = static_cast<NativeModel*>(handle);

    if (native_model->smpl) {
        common_sampler_free(native_model->smpl);
    }
    if (native_model->spec) {
        common_speculative_free(native_model->spec);
        native_model->spec = nullptr;
    }
    native_model->spec_init.reset(); // frees draft model + context
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

    llama_model_params model_params = llama_model_default_params();
    model_params.vocab_only = true;

    llama_model* model = llama_model_load_from_file(model_path, model_params);
    if (!model) {
        return LLAMA_NATIVE_ERR_FILE_NOT_FOUND;
    }

    uint64_t size = llama_model_size(model);
    size += 1024 * 1024 * 100; // +100MB arbitrary overhead for context

    *ram_estimate_out = size;

    llama_model_free(model);
    return LLAMA_NATIVE_SUCCESS;
}
