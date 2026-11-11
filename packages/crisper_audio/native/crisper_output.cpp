// SPDX-License-Identifier: MIT
// Copyright (c) 2026 CrisperPlayer contributors
#include "crisper_output.h"
#include "miniaudio_config.h"

#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstddef>
#include <cstring>
#include <limits>
#include <new>
#include <vector>

namespace {
enum Error : int32_t {
    kOk = 0,
    kArgument = -1,
    kMemory = -2,
    kDevice = -3,
    kPcm = -4,
    kRoute = -5,
    kManualOnly = -6,
    kAtomic = -7,
};
thread_local int32_t create_error = kOk;

const char* error_text(int32_t error) {
    switch (error) {
    case kOk: return "";
    case kArgument: return "Invalid native output argument";
    case kMemory: return "Unable to allocate bounded native output buffers";
    case kDevice: return "Native audio device failed or stopped unexpectedly";
    case kPcm: return "Native output received non-finite PCM";
    case kRoute: return "Native audio route changed or was interrupted; reopen output";
    case kManualOnly: return "Manual output pump called for a real device";
    case kAtomic: return "Platform lacks lock-free audio counter atomics";
    default: return "Native output failed";
    }
}
}

struct CaOutput {
    int32_t sample_rate = 0;
    int32_t channels = 0;
    int32_t backend = CA_OUTPUT_MANUAL;
    uint32_t capacity = 0;
    uint32_t period = 0;
    uint32_t latency = 0;
    ma_pcm_rb queue{};
    bool queue_ready = false;
    ma_device device{};
    bool device_ready = false;
    bool device_started = false; // control thread only

    std::atomic<bool> active{false};
    std::atomic<bool> expected_stop{false};
    std::atomic<int32_t> error{kOk};
    std::atomic<float> volume{1.0f};
    std::atomic<uint64_t> rendered{0};
    std::atomic<uint64_t> presented{0};
    std::atomic<uint64_t> underrun{0};

    // Callback-owned, preallocated at open. One credit means a real source
    // frame; zero means pause/underrun silence. Aging credits by ALL backend
    // frames, not just music frames, prevents an EOS tail from freezing.
    std::vector<uint8_t> credits;
    uint32_t credit_cursor = 0;
};

struct CaCancellation {
    std::atomic<uint64_t> generation{0};
};

namespace {
int32_t fail(CaOutput* output, int32_t error) {
    if (output) {
        int32_t ok = kOk;
        output->error.compare_exchange_strong(ok, error);
        output->active.store(false, std::memory_order_release);
        return output->error.load();
    }
    return error;
}

// This is the complete audio callback work: bounded memcpy/multiply, SPSC
// ring operations, credit accounting and lock-free atomics. No allocation,
// lock, decode, DSP, logging, I/O, FFI invocation or device lifecycle call.
uint32_t pump(CaOutput* output, float* destination, uint32_t frames) {
    if (destination) {
        std::memset(destination, 0,
                    static_cast<size_t>(frames) * output->channels * sizeof(float));
    }
    if (output->error.load(std::memory_order_acquire) != kOk) return 0;

    uint32_t consumed = 0;
    const bool active = output->active.load(std::memory_order_acquire);
    const float volume = output->volume.load(std::memory_order_relaxed);
    if (active) {
        while (consumed < frames) {
            ma_uint32 count = frames - consumed;
            void* source = nullptr;
            if (ma_pcm_rb_acquire_read(&output->queue, &count, &source) != MA_SUCCESS ||
                count == 0) break;
            if (destination) {
                float* dst = destination + static_cast<size_t>(consumed) * output->channels;
                const float* src = static_cast<const float*>(source);
                const size_t samples = static_cast<size_t>(count) * output->channels;
                if (volume == 1.0f) {
                    std::memcpy(dst, src, samples * sizeof(float));
                } else {
                    for (size_t i = 0; i < samples; ++i) dst[i] = src[i] * volume;
                }
            }
            ma_pcm_rb_commit_read(&output->queue, count);
            consumed += count;
        }
        output->underrun.fetch_add(frames - consumed, std::memory_order_relaxed);
    }

    uint64_t presented = 0;
    if (output->latency == 0) {
        presented = consumed;
    } else {
        uint32_t cursor = output->credit_cursor;
        for (uint32_t i = 0; i < frames; ++i) {
            presented += output->credits[cursor];
            output->credits[cursor] = static_cast<uint8_t>(i < consumed);
            if (++cursor == output->latency) cursor = 0;
        }
        output->credit_cursor = cursor;
    }
    output->rendered.fetch_add(consumed, std::memory_order_release);
    output->presented.fetch_add(presented, std::memory_order_release);
    return consumed;
}

void data_callback(ma_device* device, void* destination, const void*, ma_uint32 frames) {
    auto* output = static_cast<CaOutput*>(device->pUserData);
    pump(output, static_cast<float*>(destination), frames);
}

void notification_callback(const ma_device_notification* notification) {
    auto* output = static_cast<CaOutput*>(notification->pDevice->pUserData);
    switch (notification->type) {
    case ma_device_notification_type_stopped:
        if (!output->expected_stop.load(std::memory_order_acquire)) fail(output, kDevice);
        break;
    case ma_device_notification_type_rerouted:
    case ma_device_notification_type_interruption_began:
        // Reopening recalculates the delay and establishes a fresh source
        // epoch. Continuing with the old device clock would silently drift.
        fail(output, kRoute);
        break;
    default:
        break;
    }
}

uint32_t estimate_latency(const CaOutput* output, uint32_t requested_period) {
    const ma_device& device = output->device;
    const uint64_t backend_rate = std::max(1u, device.playback.internalSampleRate);
    const uint64_t period = device.playback.internalPeriodSizeInFrames;
    const uint64_t periods = std::max(1u, device.playback.internalPeriods);
    uint64_t backend_buffer = period * periods;
#if defined(MA_SUPPORT_WASAPI) && !defined(MA_NO_WASAPI)
    if (device.pContext->backend == ma_backend_wasapi) {
        // WASAPI's low-latency shared buffer may differ from period*count.
        backend_buffer = std::max<uint64_t>(backend_buffer,
            device.wasapi.actualBufferSizeInFramesPlayback);
    }
#endif
    // Include an extra backend period plus miniaudio's fixed callback buffer
    // and one requested period. This deliberately lags the known buffering.
    // Unreported server/Bluetooth/DAC buffering cannot be inferred here.
    uint64_t frames = ((backend_buffer + period) * output->sample_rate + backend_rate - 1) /
                      backend_rate;
    frames += device.playback.intermediaryBufferCap;
    frames += requested_period;
    return frames > std::numeric_limits<uint32_t>::max() ? 0 : static_cast<uint32_t>(frames);
}

int32_t open_device(CaOutput* output) {
    if (output->backend == CA_OUTPUT_MANUAL) return kOk;
    ma_device_config config = ma_device_config_init(ma_device_type_playback);
    config.playback.format = ma_format_f32;
    config.playback.channels = output->channels;
    config.sampleRate = output->sample_rate;
    config.periodSizeInFrames = output->period;
    config.periods = 2;
    config.performanceProfile = ma_performance_profile_low_latency;
    config.dataCallback = data_callback;
    config.notificationCallback = notification_callback;
    config.pUserData = output;
    // Fixed callbacks let the delay estimate include the actual intermediary
    // buffer instead of assuming a maximum size for varying callbacks.
    config.noFixedSizedCallback = MA_FALSE;
    output->expected_stop.store(true, std::memory_order_release);
    ma_result result;
    if (output->backend == CA_OUTPUT_NULL) {
        const ma_backend null_backend = ma_backend_null;
        result = ma_device_init_ex(&null_backend, 1, nullptr, &config, &output->device);
    } else {
        result = ma_device_init(nullptr, &config, &output->device);
    }
    if (result != MA_SUCCESS) return fail(output, kDevice);
    output->device_ready = true;
    output->latency = estimate_latency(output, output->period);
    // Bound allocations and fail visibly for an unusably large device queue;
    // never pretend a smaller delay represents it.
    if (output->latency == 0 || output->latency > static_cast<uint32_t>(output->sample_rate) * 2) {
        return fail(output, kDevice);
    }
    try {
        output->credits.assign(output->latency, 0);
    } catch (...) { return fail(output, kMemory); }
    return kOk;
}

void cleanup(CaOutput* output) {
    if (!output) return;
    output->active.store(false, std::memory_order_release);
    output->expected_stop.store(true, std::memory_order_release);
    if (output->device_ready) ma_device_uninit(&output->device);
    if (output->queue_ready) ma_pcm_rb_uninit(&output->queue);
    delete output;
}
}

extern "C" {

int32_t ca_output_abi_version(void) { return 1; }

CaCancellation* ca_cancel_create(void) {
    create_error = kOk;
    auto* token = new (std::nothrow) CaCancellation;
    if (!token) create_error = kMemory;
    return token;
}
void ca_cancel_set(CaCancellation* token, uint64_t generation) {
    if (token) token->generation.store(generation, std::memory_order_release);
}
uint64_t ca_cancel_get(const CaCancellation* token) {
    return token ? token->generation.load(std::memory_order_acquire) : 0;
}
void ca_cancel_destroy(CaCancellation* token) { delete token; }

CaOutput* ca_output_create(int32_t sample_rate, int32_t channels,
                            uint32_t capacity_frames, uint32_t period_frames,
                            int32_t backend) {
    create_error = kOk;
    if (sample_rate < 8000 || sample_rate > 384000 || channels < 1 || channels > 2 ||
        capacity_frames == 0 || capacity_frames > static_cast<uint32_t>(sample_rate) * 30 ||
        period_frames == 0 || period_frames > static_cast<uint32_t>(sample_rate) ||
        backend < CA_OUTPUT_DEVICE || backend > CA_OUTPUT_MANUAL) {
        create_error = kArgument;
        return nullptr;
    }
    CaOutput* output = new (std::nothrow) CaOutput;
    if (!output) { create_error = kMemory; return nullptr; }
    output->sample_rate = sample_rate;
    output->channels = channels;
    output->capacity = capacity_frames;
    output->period = period_frames;
    output->backend = backend;
    if (!output->rendered.is_lock_free() || !output->presented.is_lock_free() ||
        !output->underrun.is_lock_free() || !output->volume.is_lock_free() ||
        !output->active.is_lock_free() || !output->error.is_lock_free()) {
        create_error = kAtomic;
        cleanup(output);
        return nullptr;
    }
    if (ma_pcm_rb_init(ma_format_f32, channels, capacity_frames, nullptr, nullptr,
                      &output->queue) != MA_SUCCESS) {
        create_error = kMemory;
        cleanup(output);
        return nullptr;
    }
    output->queue_ready = true;

    create_error = open_device(output);
    if (create_error != kOk) {
        cleanup(output);
        return nullptr;
    }
    return output;
}

int32_t ca_output_start(CaOutput* output) {
    if (!output) return kArgument;
    if (output->error.load() != kOk) return output->error.load();
    output->active.store(true, std::memory_order_release);
    if (output->device_ready && !output->device_started) {
        output->expected_stop.store(false, std::memory_order_release);
        if (ma_device_start(&output->device) != MA_SUCCESS) return fail(output, kDevice);
        output->device_started = true;
    }
    return output->error.load();
}

int32_t ca_output_pause(CaOutput* output) {
    if (!output) return kArgument;
    output->active.store(false, std::memory_order_release);
    return output->error.load();
}

int32_t ca_output_reset(CaOutput* output) {
    if (!output) return kArgument;
    output->active.store(false, std::memory_order_release);
    output->expected_stop.store(true, std::memory_order_release);
    if (output->device_ready) {
        // stop alone is insufficient: PulseAudio corks and retains buffered
        // PCM. Closing the stream is required to discard the old epoch on
        // every backend. All allocations/reopening happen on this thread.
        ma_device_uninit(&output->device);
        output->device_ready = false;
        output->device_started = false;
    }
    // No callback is now running; both SPSC cursors may be changed safely.
    ma_pcm_rb_reset(&output->queue);
    std::fill(output->credits.begin(), output->credits.end(), 0);
    output->credit_cursor = 0;
    output->rendered.store(0, std::memory_order_release);
    output->presented.store(0, std::memory_order_release);
    output->underrun.store(0, std::memory_order_release);
    if (output->error.load() != kOk) return output->error.load();
    return open_device(output);
}

void ca_output_destroy(CaOutput* output) { cleanup(output); }

uint32_t ca_output_write(CaOutput* output, const float* input, uint32_t frames) {
    if (!output || output->error.load() != kOk || frames == 0) return 0;
    if (!input) { fail(output, kArgument); return 0; }
    const uint32_t accepted = std::min(frames, ma_pcm_rb_available_write(&output->queue));
    // Validate before committing; the callback only ever sees finite PCM.
    const size_t samples = static_cast<size_t>(accepted) * output->channels;
    for (size_t i = 0; i < samples; ++i) {
        if (!std::isfinite(input[i])) { fail(output, kPcm); return 0; }
    }
    uint32_t written = 0;
    while (written < accepted) {
        ma_uint32 count = accepted - written;
        void* destination = nullptr;
        if (ma_pcm_rb_acquire_write(&output->queue, &count, &destination) != MA_SUCCESS ||
            count == 0) break;
        std::memcpy(destination, input + static_cast<size_t>(written) * output->channels,
                    static_cast<size_t>(count) * output->channels * sizeof(float));
        ma_pcm_rb_commit_write(&output->queue, count);
        written += count;
    }
    return written;
}

int32_t ca_output_set_volume(CaOutput* output, float volume) {
    if (!output) return kArgument;
    if (!std::isfinite(volume) || volume < 0 || volume > 1) return fail(output, kArgument);
    if (output->error.load() != kOk) return output->error.load();
    output->volume.store(volume, std::memory_order_relaxed);
    return kOk;
}

uint32_t ca_output_buffered_frames(const CaOutput* output) {
    return output ? ma_pcm_rb_available_read(const_cast<ma_pcm_rb*>(&output->queue)) : 0;
}
uint32_t ca_output_capacity_frames(const CaOutput* output) { return output ? output->capacity : 0; }
int32_t ca_output_is_playing(const CaOutput* output) {
    return output && output->active.load(std::memory_order_acquire) && output->error.load() == kOk;
}
const char* ca_output_error(const CaOutput* output) {
    return error_text(output ? output->error.load(std::memory_order_acquire) : create_error);
}
const char* ca_output_backend_name(const CaOutput* output) {
    if (!output) return "unavailable";
    if (output->backend == CA_OUTPUT_MANUAL) return "manual";
    return output->device_ready ? ma_get_backend_name(output->device.pContext->backend) : "unavailable";
}
uint64_t ca_output_rendered_frames(const CaOutput* output) {
    return output ? output->rendered.load(std::memory_order_acquire) : 0;
}
uint64_t ca_output_presented_frames(const CaOutput* output) {
    return output ? output->presented.load(std::memory_order_acquire) : 0;
}
uint64_t ca_output_underrun_frames(const CaOutput* output) {
    return output ? output->underrun.load(std::memory_order_relaxed) : 0;
}
uint32_t ca_output_latency_frames(const CaOutput* output) { return output ? output->latency : 0; }

uint32_t ca_output_test_render(CaOutput* output, float* destination, uint32_t frames) {
    if (!output) return 0;
    if (output->backend != CA_OUTPUT_MANUAL) { fail(output, kManualOnly); return 0; }
    return pump(output, destination, frames);
}
uint32_t ca_output_pump(CaOutput* output, uint32_t frames) {
    return ca_output_test_render(output, nullptr, frames);
}
int32_t ca_output_test_set_latency(CaOutput* output, uint32_t frames) {
    if (!output) return kArgument;
    if (output->backend != CA_OUTPUT_MANUAL) return kManualOnly;
    if (output->active.load() || ca_output_buffered_frames(output) != 0 ||
        frames > static_cast<uint32_t>(output->sample_rate) * 2) return kArgument;
    if (ca_output_reset(output) != kOk) return output->error.load();
    try {
        output->credits.assign(frames, 0);
    } catch (...) { return fail(output, kMemory); }
    output->latency = frames;
    return kOk;
}

} // extern "C"
