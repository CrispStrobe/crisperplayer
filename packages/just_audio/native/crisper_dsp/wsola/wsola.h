// Copyright 2013 The Chromium Authors
// Copyright 2026 CrisperPlayer contributors
// SPDX-License-Identifier: BSD-3-Clause
// Portable maintained adaptation; see UPSTREAM.md and
// ../vendor/chromium-wsola/LICENSE for the original license and source snapshot.
#ifndef CRISPER_WSOLA_H
#define CRISPER_WSOLA_H

#include <array>
#include <cstdint>
#include <vector>

namespace crisper_wsola {

struct AudioView {
    const float *data;
    int channels, frames, stride;
    const float *channel(int index) const { return data + index * stride; }
};

// Signed inclusive search exclusions. Negative endpoints are legitimate when
// the preceding grain lies before the current search interval.
struct Interval { int begin, end; };
struct InputRange { int64_t begin, end; };

// No per-search allocation: channels, candidates and energy scratch are bounded
// at construction. Returns -1 only if every candidate is explicitly excluded.
class Search {
public:
    Search(int channels, int maximum_candidates);
    int find(AudioView search, AudioView target, Interval exclude, int preferred);
private:
    int channels_, maximum_candidates_;
    std::array<double, 2> target_energy_{};
    std::vector<double> candidate_energy_;
};

// Configuration-sized portable WSOLA. The caller supplies a planar copy of
// input_range(), zero-prepending before frame zero and padding only after EOS.
// Each process() generates hop_frames() planar output. The caller trims the
// final hop to round(real_input_frames/rate) and owns streaming/backpressure.
class Processor {
public:
    Processor(int sample_rate, int channels, double rate);
    InputRange input_range() const;
    int maximum_input_frames() const { return maximum_input_frames_; }
    int hop_frames() const { return hop_; }
    const float *output() const { return rendered_.data(); }
    void process(AudioView input, int64_t origin);
private:
    int channels_, window_, hop_, candidates_, search_frames_, center_offset_;
    int maximum_input_frames_;
    double rate_;
    int64_t output_position_ = 0, target_position_ = 0, search_position_ = 0;
    bool first_ = true;
    Search search_;
    std::vector<float> window_weights_, transition_weights_, tail_, optimal_, rendered_;
};

} // namespace crisper_wsola
#endif
