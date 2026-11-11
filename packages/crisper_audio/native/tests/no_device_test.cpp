// SPDX-License-Identifier: MIT
#include "crisper_output.h"
#include "miniaudio_config.h"

#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <thread>
#include <vector>

namespace {
int checks = 0;
#define CHECK(condition) do { ++checks; if (!(condition)) { \
    std::fprintf(stderr, "%s:%d: %s\n", __FILE__, __LINE__, #condition); \
    std::exit(1); } } while (0)

void verify_null_only_fixture() {
    // These are the real miniaudio backend probes, not an output-layer mock.
    // Keep this fixture independent of the runner's hardware/audio servers.
    for (int backend = 0; backend <= ma_backend_null; ++backend) {
        CHECK(ma_is_backend_enabled(static_cast<ma_backend>(backend)) ==
              (backend == ma_backend_null ? MA_TRUE : MA_FALSE));
    }
    ma_device_config config = ma_device_config_init(ma_device_type_playback);
    config.playback.format = ma_format_f32;
    config.playback.channels = 1;
    config.sampleRate = 8000;
    ma_device device{};
    CHECK(ma_device_init(nullptr, &config, &device) == MA_SUCCESS);
    CHECK(device.pContext->backend == ma_backend_null);
    ma_device_uninit(&device);
}

void production_requires_an_output_device() {
    for (int attempt = 0; attempt < 3; ++attempt) {
        CaOutput* output = ca_output_create(8000, 1, 256, 32, CA_OUTPUT_DEVICE);
        const bool rejected = output == nullptr;
        if (output) {
            std::fprintf(stderr, "Production mode accepted silent backend: %s\n",
                         ca_output_backend_name(output));
            ca_output_destroy(output);
        }
        CHECK(rejected);
        CHECK(std::strlen(ca_output_error(nullptr)) > 0);
        CHECK(std::strstr(ca_output_error(nullptr), "output device") != nullptr);
    }
}

void explicit_null_still_plays_for_tests() {
    CaOutput* output = ca_output_create(8000, 1, 256, 32, CA_OUTPUT_NULL);
    if (!output) std::fprintf(stderr, "%s\n", ca_output_error(nullptr));
    CHECK(output != nullptr);
    CHECK(std::strlen(ca_output_error(nullptr)) == 0);
    CHECK(std::strcmp(ca_output_backend_name(output), "Null") == 0 ||
          std::strcmp(ca_output_backend_name(output), "null") == 0);
    const std::vector<float> pcm(128, 0.125f);
    CHECK(ca_output_write(output, pcm.data(), 128) == 128);
    CHECK(ca_output_start(output) == 0);
    const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(2);
    while (ca_output_presented_frames(output) < 128 &&
           std::chrono::steady_clock::now() < deadline) {
        std::this_thread::sleep_for(std::chrono::milliseconds(2));
    }
    CHECK(std::strlen(ca_output_error(output)) == 0);
    CHECK(ca_output_rendered_frames(output) == 128);
    CHECK(ca_output_presented_frames(output) == 128);
    CHECK(ca_output_buffered_frames(output) == 0);
    CHECK(ca_output_reset(output) == 0);
    CHECK(ca_output_presented_frames(output) == 0);
    ca_output_destroy(output);
}
}

int main() {
    verify_null_only_fixture();
    production_requires_an_output_device();
    explicit_null_still_plays_for_tests();
    std::printf("no-device output: %d checks passed (real null-only miniaudio)\n", checks);
    return 0;
}
