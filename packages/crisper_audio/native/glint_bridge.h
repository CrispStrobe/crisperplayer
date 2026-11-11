// SPDX-License-Identifier: MIT
// Small bounded-frame ABI over the pinned Glint decoder subset.
#ifndef CRISPER_GLINT_BRIDGE_H
#define CRISPER_GLINT_BRIDGE_H
#include <stdint.h>
#if defined(_WIN32)
#define CA_GLINT_EXPORT __declspec(dllexport)
#else
#define CA_GLINT_EXPORT __attribute__((visibility("default")))
#endif
#ifdef __cplusplus
extern "C" {
#endif
typedef struct ca_glint_frame_info {
    int32_t sample_rate;
    int32_t channels;
    int32_t samples;
    int32_t frame_bytes;
} ca_glint_frame_info;

// codec: 1 = MPEG Layer III, 2 = ADTS AAC-LC. Returns NULL on failure.
CA_GLINT_EXPORT void* ca_glint_create(int32_t codec);
CA_GLINT_EXPORT void ca_glint_destroy(void* context);
// Exactly one complete compressed frame. The caller supplies room for
// 1152*2 floats. Returns PCM frames, 0 for MP3 reservoir warmup, or <0.
// packet_index is the absolute stream packet ordinal, including on seek.
CA_GLINT_EXPORT int32_t ca_glint_decode(void* context, const uint8_t* data,
    int32_t length, float* pcm, ca_glint_frame_info* info, int64_t packet_index);

typedef struct ca_glint_flac_info {
    int64_t first_frame;
    int32_t frames;
    int32_t encoded_bytes;
} ca_glint_flac_info;
// STREAMINFO is exactly 34 bytes. Input contains at most one bounded window;
// decode returns the consumed byte count for the first CRC-validated frame.
CA_GLINT_EXPORT int32_t ca_glint_flac_frame_info(const uint8_t* streaminfo,
    const uint8_t* data, int32_t length, ca_glint_flac_info* info);
CA_GLINT_EXPORT int32_t ca_glint_flac_decode(const uint8_t* streaminfo,
    const uint8_t* data, int32_t length, float* pcm, int32_t pcm_samples,
    ca_glint_flac_info* info);
#ifdef __cplusplus
}
#endif
#endif
