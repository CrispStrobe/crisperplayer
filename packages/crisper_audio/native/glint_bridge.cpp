// SPDX-License-Identifier: MIT
#include "glint_bridge.h"
#include "vendor/glint/src/aac_decoder.hpp"
#include "vendor/glint/src/mp3_decoder.hpp"
#include <cmath>
#include <memory>
#include <mutex>
#include <new>

namespace {
struct Context {
    int codec;
    std::unique_ptr<glint::mp3::Mp3Decoder> mp3;
    std::unique_ptr<glint::aac::AacDecoder> aac;
};
std::once_flag tables_ready;

void initialize_tables() {
    // Upstream Huffman/window tables use plain first-use booleans. Initialize
    // them before any playback/probe isolate can concurrently enter a decoder.
    glint::mp3::Mp3Decoder mp3;
    glint::aac::AacDecoder aac;
    mp3.init();
    aac.init();
}
}

extern "C" void* ca_glint_create(int32_t codec) {
    if (codec != 1 && codec != 2) return nullptr;
    try {
        std::call_once(tables_ready, initialize_tables);
        auto c = std::make_unique<Context>();
        c->codec = codec;
        if (codec == 1) {
            c->mp3 = std::make_unique<glint::mp3::Mp3Decoder>();
            c->mp3->init();
        } else {
            c->aac = std::make_unique<glint::aac::AacDecoder>();
            c->aac->init();
        }
        return c.release();
    } catch (...) {
        return nullptr;
    }
}

extern "C" void ca_glint_destroy(void* context) {
    delete static_cast<Context*>(context);
}

extern "C" int32_t ca_glint_decode(void* context, const uint8_t* data,
    int32_t length, float* pcm, ca_glint_frame_info* info, int64_t packet_index) {
    if (info) *info = {};
    if (!context || !data || !pcm || !info || length <= 0 ||
        length > 8191 || packet_index < 0) return -1;
    auto* c = static_cast<Context*>(context);
    try {
        int frames;
        if (c->codec == 1) {
            glint::mp3::Mp3FrameInfo f{};
            if (glint::mp3::mp3_frame_info(data, length, &f) < 0 ||
                f.frame_bytes != length) return -1;
            frames = c->mp3->decode_frame(data, length, pcm, &f);
            *info = {f.sample_rate, f.channels, f.samples, f.frame_bytes};
        } else {
            glint::aac::AacFrameInfo f{};
            if (glint::aac::aac_frame_info(data, length, &f) < 0 ||
                f.frame_bytes != length) return -1;
            // AAC PNS conveys noise energy, not an exact waveform. A seed
            // derived from the packet ordinal keeps it independent per stream
            // and reproducible when probing or seeking through the same file.
            const uint64_t ordinal = static_cast<uint64_t>(packet_index);
            c->aac->set_noise_seed(static_cast<uint32_t>(
                0x1234567u ^ (ordinal * 0x9e3779b9u) ^ (ordinal >> 32)));
            frames = c->aac->decode_frame(data, length, pcm, &f);
            *info = {f.sample_rate, f.channels, f.samples, f.frame_bytes};
        }
        if (frames < 0) return frames;
        if (info->channels < 1 || info->channels > 2 || frames > 1152)
            return -1;
        for (int i = 0; i < frames * info->channels; ++i)
            if (!std::isfinite(pcm[i])) return -5;
        return frames;
    } catch (...) {
        return -6;
    }
}
