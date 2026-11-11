// SPDX-License-Identifier: MIT
// Copyright (c) 2026 CrisperPlayer contributors
#ifndef CRISPER_OUTPUT_H
#define CRISPER_OUTPUT_H

#include <stdint.h>

#if defined(_WIN32)
#define CA_EXPORT __declspec(dllexport)
#else
#define CA_EXPORT __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef struct CaOutput CaOutput;
CA_EXPORT int32_t ca_output_abi_version(void);

// A control isolate may change this generation while a worker is doing a
// synchronous bounded scan. Polling never calls Dart from native code. The
// owner must keep the token alive until the worker has acknowledged disposal
// or exited; never free it while a worker can still read its address.
typedef struct CaCancellation CaCancellation;
CA_EXPORT CaCancellation* ca_cancel_create(void);
CA_EXPORT void ca_cancel_set(CaCancellation* token, uint64_t generation);
CA_EXPORT uint64_t ca_cancel_get(const CaCancellation* token);
CA_EXPORT void ca_cancel_destroy(CaCancellation* token);
enum ca_output_backend {
    CA_OUTPUT_DEVICE = 0,
    CA_OUTPUT_NULL = 1,
    CA_OUTPUT_MANUAL = 2,
};

// One control/producer thread owns a handle. The native device is the sole
// consumer. Do not call control functions concurrently, and never destroy a
// handle while another control call is running. No callback into Dart.
//
// All sizes and positions are FRAMES (one sample per channel), not samples.
// PCM is interleaved float32, mono or stereo, 8..384 kHz. The bounded queue
// holds exactly capacity_frames; callers retain/retry unaccepted input.
// period_frames is a device hint, not a promise from the hardware.
// Returns NULL on failure; ca_output_error(NULL) describes the create error.
CA_EXPORT CaOutput* ca_output_create(int32_t sample_rate, int32_t channels,
                                    uint32_t capacity_frames,
                                    uint32_t period_frames, int32_t backend);

// Return 0 on success, a negative value on failure. A native device failure is
// sticky: dispose/recreate the handle. start/pause are idempotent.
// Pause preserves queued PCM. An in-flight callback / submitted device tail
// may finish; keep polling presented_frames while paused. The device pumps
// silence after pause so the submitted tail can drain without losing audio.
CA_EXPORT int32_t ca_output_start(CaOutput* output);
CA_EXPORT int32_t ca_output_pause(CaOutput* output);
// Synchronously stop the device, flush its queue and the PCM ring, reset all
// counters, and leave paused. This begins a new source-position epoch.
CA_EXPORT int32_t ca_output_reset(CaOutput* output);
CA_EXPORT void ca_output_destroy(CaOutput* output);

// Non-blocking bounded write. Returns accepted frames; zero means full,
// frames==0, or an error (check ca_output_error). Invalid PCM latches failure
// before committing any part of the accepted region. Unaccepted PCM is never
// discarded or overwritten. Writes while paused are permitted.
CA_EXPORT uint32_t ca_output_write(CaOutput* output, const float* interleaved,
                                   uint32_t frames);
CA_EXPORT int32_t ca_output_set_volume(CaOutput* output, float volume);
CA_EXPORT uint32_t ca_output_buffered_frames(const CaOutput* output);
CA_EXPORT uint32_t ca_output_capacity_frames(const CaOutput* output);
CA_EXPORT int32_t ca_output_is_playing(const CaOutput* output);
CA_EXPORT const char* ca_output_error(const CaOutput* output);
CA_EXPORT const char* ca_output_backend_name(const CaOutput* output);

// rendered counts actual PCM handed to the native backend. Underrun zeros
// never increment it; PCM samples whose value happens to be zero DO count.
CA_EXPORT uint64_t ca_output_rendered_frames(const CaOutput* output);
// Estimate of rendered PCM which has passed the configured backend delay.
// Uses a per-frame credit delay line, including silence intervals, so old
// PCM finishes presenting even when the input queue is empty or paused.
// It never exceeds rendered_frames and never advances on underrun zeros.
// This is NOT a hardware/DAC clock or an absolute acoustic latency bound.
// OS audio servers, Bluetooth and hardware may add unreported latency.
// No wall-clock extrapolation is performed. Manual mode is exact, lag zero.
CA_EXPORT uint64_t ca_output_presented_frames(const CaOutput* output);
CA_EXPORT uint64_t ca_output_underrun_frames(const CaOutput* output);
// Delay used by the estimate, in stream-rate frames. Derived at open from
// miniaudio's actual backend buffer and callback sizes; fixed for the handle.
// A reported route change/interruption fails closed: recreate to remeasure.
CA_EXPORT uint32_t ca_output_latency_frames(const CaOutput* output);

// Deterministic MANUAL backend only. Runs the same pump as the real callback,
// returning consumed PCM frames; advances silence/latency too while paused.
// test_render additionally copies output samples, including volume and zeros.
CA_EXPORT uint32_t ca_output_pump(CaOutput* output, uint32_t frames);
CA_EXPORT uint32_t ca_output_test_render(CaOutput* output, float* interleaved,
                                        uint32_t frames);
// Manual only, stopped and empty: simulate backend lag for offline clock
// tests. Resets the counters. The normal manual backend always starts at zero.
CA_EXPORT int32_t ca_output_test_set_latency(CaOutput* output, uint32_t frames);

// Also anchors the existing DSP C ABI in the shared library. Its static
// archive otherwise has no C++ caller because all consumers are Dart FFI.
CA_EXPORT const char* ca_audio_dsp_error(void);

#ifdef __cplusplus
}
#endif
#endif
