// SPDX-License-Identifier: MIT
// Copyright (c) 2026 CrisperPlayer contributors
// Third-party processor licenses and exact source pins are in vendor/manifest.json.
#ifndef CRISPER_DSP_H
#define CRISPER_DSP_H

#include <stdint.h>

#if defined(_WIN32)
#define CP_DSP_EXPORT __declspec(dllexport)
#else
#define CP_DSP_EXPORT __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef struct cp_dsp cp_dsp;
enum cp_dsp_engine {
    CP_DSP_SONIC = 0,
    CP_DSP_BUNGEE_BASIC = 1,
    CP_DSP_SIGNALSMITH = 2,
};

// A handle belongs to one audio thread. Units are FRAMES, not individual samples.
// Buffers are interleaved, with one or two channels and an unchanged sample rate.
// Supported rate: 0.5..3.0; pitch stays 1.0. At rate 1.0, samples pass through.
CP_DSP_EXPORT cp_dsp *cp_dsp_create(int engine, int sample_rate, int channels, double rate);
CP_DSP_EXPORT void cp_dsp_destroy(cp_dsp *handle);

// Return consumed/delivered frame counts, or -1 on error. Writes may be partial
// or return zero when output must be read first. Do not drop unconsumed input.
CP_DSP_EXPORT int cp_dsp_write_s16(cp_dsp *handle, const int16_t *input, int frames);
CP_DSP_EXPORT int cp_dsp_read_s16(cp_dsp *handle, int16_t *output, int max_frames);
CP_DSP_EXPORT int cp_dsp_write_f32(cp_dsp *handle, const float *input, int frames);
CP_DSP_EXPORT int cp_dsp_read_f32(cp_dsp *handle, float *output, int max_frames);
CP_DSP_EXPORT int cp_dsp_available(cp_dsp *handle);

// finish starts a finite drain; continue reading until ended is true. Priming
// audio is removed and final output is rounded to accepted_input_frames/rate.
// Repeated finish calls are harmless; writing after finish is an error.
CP_DSP_EXPORT int cp_dsp_finish(cp_dsp *handle);
CP_DSP_EXPORT int cp_dsp_ended(cp_dsp *handle);

// Reset drops old input/output/lookahead and all counters. Validate the new rate
// before use. No old audio may appear after a seek/reset.
CP_DSP_EXPORT int cp_dsp_reset(cp_dsp *handle, double rate);

// Source frames represented by output ALREADY READ, never total queued input.
// Pending output, input lookahead, initial priming and end padding are excluded.
CP_DSP_EXPORT int64_t cp_dsp_source_frames(const cp_dsp *handle);
CP_DSP_EXPORT int64_t cp_dsp_output_frames(const cp_dsp *handle);
CP_DSP_EXPORT int64_t cp_dsp_input_frames(const cp_dsp *handle);
CP_DSP_EXPORT int cp_dsp_latency_frames(const cp_dsp *handle);
CP_DSP_EXPORT const char *cp_dsp_last_error(void);

#ifdef __cplusplus
}
#endif
#endif
