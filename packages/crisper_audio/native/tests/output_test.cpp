// SPDX-License-Identifier: MIT
#include "crisper_output.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <limits>
#include <thread>
#include <vector>

namespace {
int checks = 0;
#define CHECK(condition) do { ++checks; if (!(condition)) { \
    std::fprintf(stderr, "%s:%d: %s\n", __FILE__, __LINE__, #condition); \
    std::exit(1); } } while (0)

struct Output {
    CaOutput* value;
    explicit Output(int channels = 1, uint32_t capacity = 16,
                    int backend = CA_OUTPUT_MANUAL, int rate = 8000,
                    uint32_t period = 4)
        : value(ca_output_create(rate, channels, capacity, period, backend)) {
        if (!value) std::fprintf(stderr, "%s\n", ca_output_error(nullptr));
        CHECK(value != nullptr);
    }
    ~Output() { ca_output_destroy(value); }
    operator CaOutput*() const { return value; }
};

void arguments() {
    CHECK(ca_output_abi_version() == 1);
    CHECK(ca_output_create(0, 1, 16, 4, CA_OUTPUT_MANUAL) == nullptr);
    CHECK(std::strlen(ca_output_error(nullptr)) > 0);
    CHECK(ca_output_create(8000, 3, 16, 4, CA_OUTPUT_MANUAL) == nullptr);
    CHECK(ca_output_create(8000, 1, 0, 4, CA_OUTPUT_MANUAL) == nullptr);
    CHECK(ca_output_create(8000, 1, 16, 0, CA_OUTPUT_MANUAL) == nullptr);
    CHECK(ca_output_create(8000, 1, 16, 4, 99) == nullptr);
    ca_output_destroy(nullptr);
    CHECK(ca_output_start(nullptr) < 0);
    CHECK(ca_output_buffered_frames(nullptr) == 0);
    CHECK(ca_output_presented_frames(nullptr) == 0);
    CaCancellation* token = ca_cancel_create();
    CHECK(token != nullptr);
    CHECK(ca_cancel_get(token) == 0);
    ca_cancel_set(token, 123456789);
    CHECK(ca_cancel_get(token) == 123456789);
    ca_cancel_set(token, std::numeric_limits<uint64_t>::max());
    CHECK(ca_cancel_get(token) == std::numeric_limits<uint64_t>::max());
    ca_cancel_destroy(token);
    ca_cancel_destroy(nullptr);
}

void bounded_queue_and_channels() {
    for (int channels : {1, 2}) {
        Output output(channels, 4);
        CHECK(std::strcmp(ca_output_backend_name(output), "manual") == 0);
        CHECK(ca_output_capacity_frames(output) == 4);
        CHECK(ca_output_latency_frames(output) == 0);
        std::vector<float> input(7 * channels), rendered(6 * channels, 99);
        for (size_t i = 0; i < input.size(); ++i) input[i] = static_cast<float>(i) / 32;

        CHECK(ca_output_write(output, input.data(), 7) == 4);
        CHECK(ca_output_write(output, input.data(), 1) == 0);
        CHECK(std::strlen(ca_output_error(output)) == 0);
        CHECK(ca_output_buffered_frames(output) == 4);
        // Prepared audio must not move until start.
        CHECK(ca_output_test_render(output, rendered.data(), 3) == 0);
        CHECK(ca_output_presented_frames(output) == 0);
        CHECK(ca_output_underrun_frames(output) == 0);
        for (int i = 0; i < 3 * channels; ++i) CHECK(rendered[i] == 0);

        CHECK(ca_output_start(output) == 0);
        CHECK(ca_output_start(output) == 0);
        CHECK(ca_output_test_render(output, rendered.data(), 3) == 3);
        for (int i = 0; i < 3 * channels; ++i) CHECK(rendered[i] == input[i]);
        CHECK(ca_output_presented_frames(output) == 3);
        CHECK(ca_output_rendered_frames(output) == 3);
        CHECK(ca_output_buffered_frames(output) == 1);

        // Retry exactly the unaccepted suffix. This crosses the ring wrap.
        CHECK(ca_output_write(output, input.data() + 4 * channels, 3) == 3);
        CHECK(ca_output_test_render(output, rendered.data(), 6) == 4);
        for (int i = 0; i < 4 * channels; ++i) CHECK(rendered[i] == input[3 * channels + i]);
        for (int i = 4 * channels; i < 6 * channels; ++i) CHECK(rendered[i] == 0);
        CHECK(ca_output_rendered_frames(output) == 7);
        CHECK(ca_output_presented_frames(output) == 7);
        CHECK(ca_output_underrun_frames(output) == 2);
        CHECK(ca_output_buffered_frames(output) == 0);
        CHECK(ca_output_pump(output, 11) == 0);
        CHECK(ca_output_presented_frames(output) == 7);
    }
}

void pause_volume_and_reset() {
    Output output(2, 8);
    const float input[] = {0.2f, -0.4f, 0.6f, -0.8f, 0.1f, -0.3f, 0.5f, -0.7f};
    float result[8];
    CHECK(ca_output_write(output, input, 4) == 4);
    CHECK(ca_output_start(output) == 0);
    CHECK(ca_output_set_volume(output, 0.5f) == 0);
    CHECK(ca_output_test_render(output, result, 1) == 1);
    CHECK(result[0] == input[0] * 0.5f && result[1] == input[1] * 0.5f);
    CHECK(ca_output_pause(output) == 0);
    CHECK(ca_output_pause(output) == 0);
    CHECK(ca_output_is_playing(output) == 0);
    CHECK(ca_output_test_render(output, result, 4) == 0);
    for (float sample : result) CHECK(sample == 0);
    CHECK(ca_output_presented_frames(output) == 1);
    CHECK(ca_output_underrun_frames(output) == 0);
    CHECK(ca_output_buffered_frames(output) == 3);

    CHECK(ca_output_start(output) == 0);
    CHECK(ca_output_set_volume(output, 0) == 0);
    CHECK(ca_output_test_render(output, result, 1) == 1);
    CHECK(result[0] == 0 && result[1] == 0);
    CHECK(ca_output_presented_frames(output) == 2); // Mute is still real PCM.

    CHECK(ca_output_reset(output) == 0);
    CHECK(ca_output_is_playing(output) == 0);
    CHECK(ca_output_buffered_frames(output) == 0);
    CHECK(ca_output_presented_frames(output) == 0);
    CHECK(ca_output_rendered_frames(output) == 0);
    CHECK(ca_output_underrun_frames(output) == 0);
    CHECK(ca_output_set_volume(output, 1) == 0);
    const float replacement[] = {-0.125f, 0.375f};
    CHECK(ca_output_write(output, replacement, 1) == 1);
    CHECK(ca_output_start(output) == 0);
    CHECK(ca_output_test_render(output, result, 4) == 1);
    CHECK(result[0] == replacement[0] && result[1] == replacement[1]);
    for (int i = 2; i < 8; ++i) CHECK(result[i] == 0); // No pre-seek audio.
}

void delayed_tail_and_late_write() {
    Output output;
    CHECK(ca_output_test_set_latency(output, 5) == 0);
    CHECK(ca_output_latency_frames(output) == 5);
    const float input[] = {0.1f, 0.2f, 0.3f};
    CHECK(ca_output_write(output, input, 3) == 3);
    CHECK(ca_output_start(output) == 0);
    CHECK(ca_output_pump(output, 3) == 3);
    CHECK(ca_output_buffered_frames(output) == 0);
    CHECK(ca_output_rendered_frames(output) == 3);
    CHECK(ca_output_presented_frames(output) == 0);
    CHECK(ca_output_pump(output, 2) == 0);
    CHECK(ca_output_presented_frames(output) == 0);
    CHECK(ca_output_pump(output, 3) == 0);
    CHECK(ca_output_presented_frames(output) == 3); // EOF tail drains in zeros.
    CHECK(ca_output_underrun_frames(output) == 5);

    CHECK(ca_output_pump(output, 19) == 0);
    CHECK(ca_output_presented_frames(output) == 3);
    CHECK(ca_output_write(output, input, 2) == 2);
    CHECK(ca_output_pump(output, 2) == 2);
    CHECK(ca_output_presented_frames(output) == 3); // New PCM pays its own delay.
    CHECK(ca_output_pause(output) == 0);
    const auto underruns = ca_output_underrun_frames(output);
    CHECK(ca_output_write(output, input, 3) == 3);
    CHECK(ca_output_pump(output, 5) == 0);
    CHECK(ca_output_presented_frames(output) == 5); // Only submitted tail drains.
    CHECK(ca_output_buffered_frames(output) == 3);  // Pause preserves new queue.
    CHECK(ca_output_underrun_frames(output) == underruns);
    CHECK(ca_output_pump(output, 100) == 0);
    CHECK(ca_output_presented_frames(output) == 5);
    CHECK(ca_output_reset(output) == 0);
    CHECK(ca_output_pump(output, 100) == 0);
    CHECK(ca_output_presented_frames(output) == 0);
}

void finite_pcm_and_sticky_errors() {
    for (float invalid : {std::numeric_limits<float>::quiet_NaN(),
                          std::numeric_limits<float>::infinity()}) {
        Output output;
        const float input[] = {0.1f, invalid, 0.3f};
        CHECK(ca_output_write(output, input, 3) == 0);
        CHECK(ca_output_buffered_frames(output) == 0);
        CHECK(std::strlen(ca_output_error(output)) > 0);
        CHECK(ca_output_start(output) < 0);
        CHECK(ca_output_reset(output) < 0); // Errors require a new handle.
        float result[3] = {99, 99, 99};
        CHECK(ca_output_test_render(output, result, 3) == 0);
        for (float sample : result) CHECK(sample == 0);
        CHECK(ca_output_rendered_frames(output) == 0);
        CHECK(ca_output_presented_frames(output) == 0);
    }
    Output output;
    CHECK(ca_output_set_volume(output, 2) < 0);
    CHECK(ca_output_is_playing(output) == 0);
}

// Independently track the ending device-frame time of each real PCM frame.
// A frame is presented when that ending time is <= current time - delay.
// This exercises wrap, partial writes, changing callback sizes and pauses.
void presentation_model() {
    Output output(1, 17);
    constexpr uint32_t delay = 11;
    CHECK(ca_output_test_set_latency(output, delay) == 0);
    std::deque<float> queue;
    std::deque<uint64_t> pending_ends;
    uint64_t timeline = 0, rendered_total = 0, presented_total = 0, underruns = 0;
    bool playing = false;
    float next_sample = 0;
    for (uint32_t step = 0; step < 600; ++step) {
        if (step % 17 == 0) {
            playing = !playing;
            CHECK((playing ? ca_output_start(output) : ca_output_pause(output)) == 0);
        }
        const uint32_t requested = (step * 7) % 23;
        std::vector<float> samples(requested);
        for (float& sample : samples) sample = next_sample += 0.0001f;
        const uint32_t want = std::min<uint32_t>(requested, 17 - queue.size());
        const uint32_t accepted = ca_output_write(output, samples.data(), requested);
        CHECK(accepted == want);
        for (uint32_t i = 0; i < accepted; ++i) queue.push_back(samples[i]);
        const uint32_t frames = (step * 13) % 31 + 1;
        const uint32_t consumed = playing ? std::min<uint32_t>(frames, queue.size()) : 0;
        std::vector<float> result(frames, 99);
        CHECK(ca_output_test_render(output, result.data(), frames) == consumed);
        for (uint32_t i = 0; i < frames; ++i) {
            ++timeline;
            if (i < consumed) {
                CHECK(result[i] == queue.front());
                queue.pop_front();
                pending_ends.push_back(timeline);
                ++rendered_total;
            } else {
                CHECK(result[i] == 0);
                if (playing) ++underruns;
            }
            while (!pending_ends.empty() && timeline >= delay &&
                   pending_ends.front() <= timeline - delay) {
                pending_ends.pop_front();
                ++presented_total;
            }
        }
        CHECK(ca_output_rendered_frames(output) == rendered_total);
        CHECK(ca_output_presented_frames(output) == presented_total);
        CHECK(ca_output_underrun_frames(output) == underruns);
        CHECK(ca_output_buffered_frames(output) == queue.size());
    }
}

bool wait_until_presented(CaOutput* output, uint64_t frames) {
    const auto end = std::chrono::steady_clock::now() + std::chrono::seconds(2);
    while (std::chrono::steady_clock::now() < end) {
        if (std::strlen(ca_output_error(output)) != 0) return false;
        if (ca_output_presented_frames(output) == frames) return true;
        std::this_thread::sleep_for(std::chrono::milliseconds(2));
    }
    return false;
}

void actual_null_device() {
    Output output(2, 1024, CA_OUTPUT_NULL, 44100, 128);
    CHECK(std::strcmp(ca_output_backend_name(output), "Null") == 0 ||
          std::strcmp(ca_output_backend_name(output), "null") == 0);
    CHECK(ca_output_latency_frames(output) > 0);
    std::vector<float> pcm(512, 0.125f);
    CHECK(ca_output_write(output, pcm.data(), 256) == 256);
    CHECK(ca_output_start(output) == 0);
    CHECK(wait_until_presented(output, 256));
    CHECK(ca_output_rendered_frames(output) == 256);
    CHECK(ca_output_buffered_frames(output) == 0);
    CHECK(ca_output_underrun_frames(output) > 0);
    CHECK(ca_output_pause(output) == 0);
    CHECK(ca_output_write(output, pcm.data(), 256) == 256);
    std::this_thread::sleep_for(std::chrono::milliseconds(25));
    CHECK(ca_output_buffered_frames(output) == 256);
    CHECK(ca_output_rendered_frames(output) == 256);
    CHECK(ca_output_presented_frames(output) == 256);
    CHECK(ca_output_start(output) == 0);
    CHECK(wait_until_presented(output, 512));
    CHECK(ca_output_reset(output) == 0);
    CHECK(ca_output_is_playing(output) == 0);
    CHECK(ca_output_rendered_frames(output) == 0);
    CHECK(ca_output_presented_frames(output) == 0);
    CHECK(ca_output_buffered_frames(output) == 0);
    CHECK(ca_output_write(output, pcm.data(), 256) == 256);
    CHECK(ca_output_start(output) == 0);
    CHECK(wait_until_presented(output, 256));
    CHECK(ca_output_pause(output) == 0);
}
}

int main() {
    arguments();
    bounded_queue_and_channels();
    pause_volume_and_reset();
    delayed_tail_and_late_write();
    finite_pcm_and_sticky_errors();
    presentation_model();
    actual_null_device();
    std::printf("native output: %d checks passed (manual + real null device)\n", checks);
    return 0;
}
