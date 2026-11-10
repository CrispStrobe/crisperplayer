// SPDX-License-Identifier: MIT
// Test-only introspection in one translation unit. The included BSD-3-Clause
// production source remains unchanged. Never include this bridge in app builds.
#include "../../wsola/wsola.cpp"

extern "C" int portable_search(const float* search, int search_frames,
    const float* target, int target_frames, int channels,
    int exclude_low, int exclude_high, int preferred) {
  std::vector<float> a(search_frames * channels), b(target_frames * channels);
  for (int c = 0; c < channels; ++c) {
    for (int f = 0; f < search_frames; ++f)
      a[c * search_frames + f] = search[f * channels + c];
    for (int f = 0; f < target_frames; ++f)
      b[c * target_frames + f] = target[f * channels + c];
  }
  crisper_wsola::Search matcher(channels, search_frames - target_frames + 1);
  return matcher.find({a.data(), channels, search_frames, search_frames},
      {b.data(), channels, target_frames, target_frames},
      {exclude_low, exclude_high}, preferred);
}

extern "C" float portable_dot(const float* a, const float* b, int frames) {
  return crisper_wsola::dot_product(a, b, frames);
}

extern "C" void portable_hann(float* output, int frames) {
  std::vector<float> result(frames);
  crisper_wsola::periodic_hann(result);
  std::copy(result.begin(), result.end(), output);
}

extern "C" const char* portable_simd_name() {
#if defined(__SSE2__)
  return "SSE2";
#elif defined(__ARM_NEON) || defined(__ARM_NEON__)
  return "NEON";
#else
  return "scalar";
#endif
}
