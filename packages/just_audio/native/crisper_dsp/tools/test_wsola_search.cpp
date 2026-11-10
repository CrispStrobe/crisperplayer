// SPDX-License-Identifier: MIT
// Copyright (c) 2026 CrisperPlayer contributors
// Regression fixtures for the maintained BSD WSOLA search, not a sound-quality
// benchmark. Compile against the same implementation that Android packages.
#include "wsola/wsola.h"

#include <cmath>
#include <iostream>
#include <stdexcept>
#include <vector>

namespace {
int checks = 0;
void check(bool condition, const char *message) {
    ++checks;
    if (!condition) throw std::runtime_error(message);
}
}

int main() {
    using namespace crisper_wsola;
    try {
        std::vector<float> wanted(100, 1.f), negative(120, -1.f), silence(120, 0.f);
        Search mono(1, 21);
        check(mono.find({negative.data(), 1, 120, 120}, {wanted.data(), 1, 100, 100}, {0, 7}, 10) == 10,
              "All-negative scores must return a valid unexcluded candidate");
        check(mono.find({negative.data(), 1, 120, 120}, {wanted.data(), 1, 100, 100}, {0, 19}, 10) == 20,
              "The only allowed endpoint must not fall back to excluded zero");
        check(mono.find({negative.data(), 1, 120, 120}, {wanted.data(), 1, 100, 100}, {0, 20}, 10) == -1,
              "A fully excluded search has no candidate");
        check(mono.find({silence.data(), 1, 120, 120}, {wanted.data(), 1, 100, 100}, {-200, -40}, 13) == 13,
              "Negative source-relative exclusions must not wrap unsigned");
        check(mono.find({silence.data(), 1, 120, 120}, {wanted.data(), 1, 100, 100}, {0, 3}, 14) == 14,
              "Silence should use the closest allowed nominal source position");

        // Matching two channels with opposite polarity must select the same
        // alignment as the left channel alone, rather than canceling the target.
        constexpr int target_frames = 200, search_frames = 260, shift = 27;
        std::vector<float> target(2 * target_frames), search(2 * search_frames);
        for (int i = 0; i < target_frames; ++i) {
            const float value = std::sin(i * .033f) + .31f * std::cos(i * .071f);
            target[i] = value;
            target[target_frames + i] = -value;
        }
        for (int i = 0; i < search_frames; ++i) {
            const float value = std::sin((i - shift) * .033f) + .31f * std::cos((i - shift) * .071f);
            search[i] = value;
            search[search_frames + i] = -value;
        }
        Search stereo(2, search_frames - target_frames + 1);
        const AudioView search_view{search.data(), 2, search_frames, search_frames};
        const AudioView target_view{target.data(), 2, target_frames, target_frames};
        check(stereo.find(search_view, target_view, {-1, -1}, 30) == shift,
              "Opposite-phase stereo must retain the common waveform match");
        std::fill(target.begin(), target.begin() + target_frames, 0.f);
        std::fill(search.begin(), search.begin() + search_frames, 0.f);
        check(stereo.find(search_view, target_view, {-1, -1}, 30) == shift,
              "A silent first channel must not hide the audible second channel");

        std::vector<float> impulse(1000, 0.f), zeros(100, 0.f);
        impulse[0] = 1.f;
        impulse[1] = 1e-6f;
        Search tail(1, 901);
        check(tail.find({impulse.data(), 1, 1000, 1000}, {zeros.data(), 1, 100, 100}, {-1, -1}, 850) == 850,
              "Rolling energy after a transient must remain finite through silence");

        std::cout << "{\"checks\":" << checks << ",\"failures\":0}\n";
        return 0;
    } catch (const std::exception &error) {
        std::cerr << "WSOLA search regression failed: " << error.what() << '\n';
        return 1;
    }
}
