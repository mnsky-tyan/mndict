// MNN in-app spike bridge. Binds MNN's Transformer Llm engine behind a C ABI
// so dart:ffi can drive it inside the app process and measure it against the
// llama.cpp path under identical foreground/scheduling/thermal conditions.
// Compiled only when CMake MNDICT_MNN_SPIKE=ON (gradle sets it from the
// MNN_SPIKE=1 env var) — never part of production builds.

#include <android/log.h>
#include <chrono>
#include <sstream>
#include <string>

#include "llm/llm.hpp"

namespace {

constexpr const char* kTag = "MnnSpike";

MNN::Transformer::Llm* g_llm = nullptr;

int64_t now_us() {
    return std::chrono::duration_cast<std::chrono::microseconds>(
               std::chrono::steady_clock::now().time_since_epoch())
        .count();
}

}  // namespace

extern "C" {

// Dart-side print() never reaches logcat in release builds — all spike
// progress logging funnels through here instead.
__attribute__((visibility("default")))
void mnn_spike_log(const char* msg) {
    __android_log_print(ANDROID_LOG_INFO, kTag, "%s", msg ? msg : "");
}

__attribute__((visibility("default")))
int32_t mnn_spike_create(const char* config_path) {
    if (g_llm) {
        MNN::Transformer::Llm::destroy(g_llm);
        g_llm = nullptr;
    }
    if (!config_path) return -1;
    g_llm = MNN::Transformer::Llm::createLLM(config_path);
    if (!g_llm) {
        __android_log_print(ANDROID_LOG_ERROR, kTag, "createLLM(%s) failed", config_path);
        return -2;
    }
    return 0;
}

// Merges an llm_config.json override. Must run between create() and load():
// power/thread_num/memory are consumed when the runtime is built in load().
__attribute__((visibility("default")))
int32_t mnn_spike_set_config(const char* json) {
    if (!g_llm || !json) return -1;
    return g_llm->set_config(json) ? 0 : -2;
}

__attribute__((visibility("default")))
int32_t mnn_spike_load() {
    if (!g_llm) return -1;
    const int64_t t0 = now_us();
    if (!g_llm->load()) {
        __android_log_print(ANDROID_LOG_ERROR, kTag, "load() failed");
        MNN::Transformer::Llm::destroy(g_llm);
        g_llm = nullptr;
        return -2;
    }
    __android_log_print(ANDROID_LOG_INFO, kTag, "Model loaded in %.2f s", (now_us() - t0) / 1e6);
    return 0;
}

__attribute__((visibility("default")))
int32_t mnn_spike_lookup(const char* user_content, int32_t max_new_tokens) {
    if (!g_llm || !user_content) return -1;
    std::ostringstream oss;
    const int64_t t0 = now_us();
    g_llm->response(user_content, &oss, nullptr, max_new_tokens);
    const double wall_s = (now_us() - t0) / 1e6;

    const MNN::Transformer::LlmContext* ctx = g_llm->getContext();
    const int tokens = ctx->gen_seq_len;
    const double prefill_s = ctx->prefill_us / 1e6;
    const double decode_s = ctx->decode_us / 1e6;
    // First tuple mirrors the llama.cpp "Decode summary" log exactly:
    // generated tokens over whole-call wall clock (prefill included).
    __android_log_print(ANDROID_LOG_INFO, kTag,
                        "Decode summary: %d tokens in %d ms (%.1f tok/s) | "
                        "prefill %d ms, decode %d ms (%.1f tok/s)",
                        tokens, int(wall_s * 1000), wall_s > 0 ? tokens / wall_s : 0.0,
                        int(prefill_s * 1000), int(decode_s * 1000),
                        decode_s > 0 ? tokens / decode_s : 0.0);
    std::string text = oss.str();
    if (!text.empty()) {
        for (auto& c : text) {
            if (c == '\n') c = ' ';
        }
        if (text.size() > 140) text = text.substr(0, 140) + "...";
        __android_log_print(ANDROID_LOG_INFO, kTag, "out: %s", text.c_str());
    }
    return tokens;
}

__attribute__((visibility("default")))
void mnn_spike_destroy() {
    if (g_llm) {
        MNN::Transformer::Llm::destroy(g_llm);
        g_llm = nullptr;
    }
}

}  // extern "C"
