// Copyright 2012-2013 The Chromium Authors
// Copyright 2026 CrisperPlayer contributors
// SPDX-License-Identifier: BSD-3-Clause
// Adapted from Chromium wsola_internals.cc and the WSOLA processing loop in
// audio_renderer_algorithm.cc at ddd30ef8aa98443509bf4ce006cb36b4e2296c0b.
// Local portability, bounded scratch, signed-index and numerical changes are
// documented in UPSTREAM.md. Original notice: ../vendor/chromium-wsola/LICENSE.
#include "wsola.h"

#include <algorithm>
#include <cmath>
#include <limits>
#include <numbers>
#include <stdexcept>

#if defined(__SSE2__)
#include <xmmintrin.h>
#elif defined(__ARM_NEON) || defined(__ARM_NEON__)
#include <arm_neon.h>
#endif

namespace crisper_wsola {
namespace {
bool excluded(int index, Interval interval) {
    return index >= interval.begin && index <= interval.end;
}

// Compile-time baseline SIMD avoids Chromium's base::CPU/runtime-dispatch
// dependency. Both channels are correlated independently and their normalized
// scores are summed; opposite-polarity stereo is never downmixed to silence.
float dot_product(const float *a, const float *b, int frames) {
    int i = 0;
    float result = 0.f;
#if defined(__SSE2__)
    __m128 sum = _mm_setzero_ps();
    for (; i + 4 <= frames; i += 4)
        sum = _mm_add_ps(sum, _mm_mul_ps(_mm_loadu_ps(a + i), _mm_loadu_ps(b + i)));
    sum = _mm_add_ps(_mm_movehl_ps(sum, sum), sum);
    _mm_store_ss(&result, _mm_add_ss(sum, _mm_shuffle_ps(sum, sum, 1)));
#elif defined(__ARM_NEON) || defined(__ARM_NEON__)
    float32x4_t sum = vmovq_n_f32(0);
    for (; i + 4 <= frames; i += 4)
        sum = vmlaq_f32(sum, vld1q_f32(a + i), vld1q_f32(b + i));
    const float32x2_t half = vadd_f32(vget_high_f32(sum), vget_low_f32(sum));
    result = vget_lane_f32(vpadd_f32(half, half), 0);
#endif
    for (; i < frames; ++i) result += a[i] * b[i];
    return result;
}

void periodic_hann(std::vector<float> &window) {
    const double scale = 2. * std::numbers::pi / window.size();
    for (size_t i = 0; i < window.size(); ++i)
        window[i] = float(.5 * (1. - std::cos(i * scale)));
}

int window_frames(int sample_rate) {
    const int frames = sample_rate * 20 / 1000;
    return frames + (frames & 1);
}
} // namespace

Search::Search(int channels, int maximum_candidates)
    : channels_(channels), maximum_candidates_(maximum_candidates),
      candidate_energy_(size_t(channels) * maximum_candidates) {
    if ((channels != 1 && channels != 2) || maximum_candidates < 1)
        throw std::invalid_argument("Invalid WSOLA search configuration");
}

int Search::find(AudioView search, AudioView target, Interval exclude, int preferred) {
    const int candidates = search.frames - target.frames + 1;
    if (search.channels != channels_ || target.channels != channels_ ||
        target.frames < 1 || candidates < 1 || candidates > maximum_candidates_ ||
        search.stride < search.frames || target.stride < target.frames)
        throw std::invalid_argument("Invalid WSOLA search buffers");
    preferred = std::clamp(preferred, 0, candidates - 1);

    // Chromium's sliding-energy calculation with double accumulation and an
    // explicit nonnegative clamp avoids tiny negative energies after silence.
    for (int c = 0; c < channels_; ++c) {
        const float *values = search.channel(c), *wanted = target.channel(c);
        double energy = 0, target_energy = 0;
        for (int i = 0; i < target.frames; ++i) {
            energy += double(values[i]) * values[i];
            target_energy += double(wanted[i]) * wanted[i];
        }
        target_energy_[c] = target_energy;
        candidate_energy_[c] = energy;
        for (int n = 1; n < candidates; ++n) {
            energy += double(values[n + target.frames - 1]) * values[n + target.frames - 1]
                    - double(values[n - 1]) * values[n - 1];
            energy = std::max(0., energy);
            candidate_energy_[n * channels_ + c] = energy;
        }
    }
    const auto score = [&](int offset) {
        double similarity = 0;
        for (int c = 0; c < channels_; ++c) {
            const double dot = dot_product(target.channel(c), search.channel(c) + offset, target.frames);
            similarity += dot / std::sqrt(target_energy_[c] * candidate_energy_[offset * channels_ + c] + 1e-12);
        }
        return similarity;
    };
    int best = -1;
    double best_similarity = std::numeric_limits<double>::lowest();
    const auto consider = [&](int index, double similarity) {
        if (index < 0 || index >= candidates || excluded(index, exclude)) return;
        if (best < 0 || similarity > best_similarity + 1e-12 ||
            (std::abs(similarity - best_similarity) <= 1e-12 &&
             std::abs(index - preferred) < std::abs(best - preferred))) {
            best = index;
            best_similarity = similarity;
        }
    };
    // Same coarse spacing and parabolic-peak estimate as Chromium, then a full
    // +/-5-frame refinement. Include endpoints/preferred explicitly, evaluate
    // interpolated candidates before accepting them, and honor exclusions even
    // for the initial candidate. Negative correlations are valid candidates.
    constexpr int decimation = 5;
    double previous[2] = {0, 0};
    for (int n = 0; n < candidates; n += decimation) {
        const double current = score(n);
        consider(n, current);
        if (n >= 2 * decimation && previous[1] >= previous[0] && previous[1] >= current) {
            const double a = .5 * (current + previous[0]) - previous[1];
            const double b = .5 * (current - previous[0]);
            const double extremum = a == 0. ? 0. : std::clamp(-b / (2. * a), -1., 1.);
            const int candidate = std::clamp(n - decimation + int(std::lround(extremum * decimation)), 0, candidates - 1);
            if (!excluded(candidate, exclude)) consider(candidate, score(candidate));
        }
        previous[0] = previous[1];
        previous[1] = current;
    }
    consider(candidates - 1, score(candidates - 1));
    consider(preferred, score(preferred));
    // If the allowed interval is smaller than the coarse step, find a valid
    // seed instead of falling back to an excluded zero as upstream can do.
    if (best < 0) {
        for (int n = 0; n < candidates; ++n) {
            if (!excluded(n, exclude)) { consider(n, score(n)); break; }
        }
    }
    if (best < 0) return -1;
    const int low = std::max(0, best - decimation), high = std::min(candidates - 1, best + decimation);
    for (int n = low; n <= high; ++n)
        if (!excluded(n, exclude)) consider(n, score(n));
    return best;
}

Processor::Processor(int sample_rate, int channels, double rate)
    : channels_(channels), window_(window_frames(sample_rate)), hop_(window_ / 2),
      candidates_(sample_rate * 30 / 1000), search_frames_(candidates_ + window_ - 1),
      center_offset_(candidates_ / 2 + hop_ - 1),
      maximum_input_frames_(search_frames_ + 3 * hop_ + 4), rate_(rate),
      search_(channels, candidates_), window_weights_(window_), transition_weights_(2 * window_),
      tail_(channels * hop_), optimal_(channels * window_), rendered_(channels * hop_) {
    if (sample_rate < 8000 || sample_rate > 192000 || !std::isfinite(rate) || rate < .5 || rate > 3.)
        throw std::invalid_argument("Invalid WSOLA configuration");
    periodic_hann(window_weights_);
    periodic_hann(transition_weights_);
}

InputRange Processor::input_range() const {
    return {std::min(target_position_, search_position_),
            std::max(target_position_ + window_, search_position_ + search_frames_)};
}

void Processor::process(AudioView input, int64_t origin) {
    const InputRange needed = input_range();
    if (input.channels != channels_ || origin != needed.begin ||
        input.frames != needed.end - needed.begin || input.frames > maximum_input_frames_ ||
        input.stride < input.frames)
        throw std::invalid_argument("Invalid WSOLA input range");
    const AudioView target{input.data + (target_position_ - origin), channels_, window_, input.stride};
    const AudioView search{input.data + (search_position_ - origin), channels_, search_frames_, input.stride};
    int64_t optimal_position;
    const bool direct = target_position_ >= search_position_ &&
        target_position_ + window_ <= search_position_ + search_frames_;
    if (direct) {
        optimal_position = target_position_;
    } else {
        const int64_t last_optimal = target_position_ - hop_ - search_position_;
        if (last_optimal < std::numeric_limits<int>::min() + 80 ||
            last_optimal > std::numeric_limits<int>::max() - 80)
            throw std::runtime_error("WSOLA source-window distance is unbounded");
        // Keep Chromium's heuristic 160-frame anti-repetition exclusion.
        const Interval exclude{int(last_optimal) - 80, int(last_optimal) + 80};
        int offset = search_.find(search, target, exclude, candidates_ / 2);
        if (offset < 0) offset = candidates_ / 2;
        optimal_position = search_position_ + offset;
    }
    const int offset = int(optimal_position - origin);
    for (int c = 0; c < channels_; ++c) {
        float *optimal = optimal_.data() + c * window_;
        const float *source = input.channel(c) + offset;
        for (int i = 0; i < window_; ++i) {
            optimal[i] = direct ? source[i]
                : source[i] * transition_weights_[i] + target.channel(c)[i] * transition_weights_[window_ + i];
        }
        float *out = rendered_.data() + c * hop_;
        float *tail = tail_.data() + c * hop_;
        for (int i = 0; i < hop_; ++i) {
            // Preserve the first source samples instead of fading in against
            // a fictitious all-zero preceding grain.
            out[i] = first_ ? optimal[i]
                : tail[i] * window_weights_[hop_ + i] + optimal[i] * window_weights_[i];
            tail[i] = optimal[hop_ + i];
        }
    }
    first_ = false;
    target_position_ = optimal_position + hop_;
    output_position_ += hop_;
    // Absolute coordinates never use Chromium's cumulative signed-int queue
    // offset. The enclosing ABI bounds accepted frames below 2^50.
    search_position_ = std::llround(double(output_position_) * rate_) - center_offset_;
}

} // namespace crisper_wsola
