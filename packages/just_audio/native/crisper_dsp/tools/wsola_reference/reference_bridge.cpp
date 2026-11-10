// SPDX-License-Identifier: MIT
// Test-only C ABI for the exact, unmodified Chromium WSOLA helper source.
// This bridge and its compatibility shims are outside every app build list.
#include "media/base/audio_bus.h"
#include "media/filters/wsola_internals.h"
#include <cstdint>
#include <vector>

static media::AudioBus bus(const float* data, int frames, int channels) {
  media::AudioBus result(channels, frames);
  for (int c = 0; c < channels; ++c)
    for (int f = 0; f < frames; ++f)
      result.channel(c)[f] = data[f * channels + c];
  return result;
}

extern "C" int reference_search(const float* search, int search_frames,
    const float* target, int target_frames, int channels, int64_t exclude_low,
    int64_t exclude_high, int mode, int decimation) {
  auto a = bus(search, search_frames, channels);
  auto b = bus(target, target_frames, channels);
  // Keep the upstream unsigned interval semantics so their edge-case behavior
  // remains observable. The production fork intentionally uses signed bounds.
  media::internal::Interval interval{static_cast<size_t>(exclude_low),
                                    static_cast<size_t>(exclude_high)};
  if (mode == 0) return media::internal::OptimalIndex(&a, &b, interval);
  std::vector<float> energies((search_frames - target_frames + 1) * channels);
  std::vector<float> target_energy(channels);
  media::internal::MultiChannelMovingBlockEnergies(&a, target_frames, energies);
  media::internal::MultiChannelDotProduct(&b, 0, &b, 0, target_frames,
                                         target_energy);
  if (mode == 1)
    return media::internal::FullSearch(0, search_frames - target_frames,
        interval, &b, &a, target_energy, energies);
  return media::internal::DecimatedSearch(decimation, interval, &b, &a,
                                          target_energy, energies);
}

extern "C" void reference_dot(const float* a, const float* b, int frames,
                              int channels, float* out) {
  auto first = bus(a, frames, channels), second = bus(b, frames, channels);
  media::internal::MultiChannelDotProduct(&first, 0, &second, 0, frames,
                                          std::span<float>(out, channels));
}

extern "C" void reference_energy(const float* samples, int frames, int channels,
                                 int window, float* out) {
  auto input = bus(samples, frames, channels);
  media::internal::MultiChannelMovingBlockEnergies(&input, window,
      std::span<float>(out, (frames - window + 1) * channels));
}

extern "C" void reference_quadratic(const float* input, float* out) {
  media::internal::QuadraticInterpolation(
      std::span<const float, 3>(input, 3), out, out + 1);
}

extern "C" void reference_hann(float* out, int frames) {
  media::internal::GetPeriodicHanningWindow(std::span<float>(out, frames));
}
