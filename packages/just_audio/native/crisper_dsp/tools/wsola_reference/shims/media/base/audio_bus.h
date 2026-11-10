// SPDX-License-Identifier: MIT
// Test-only compatibility shim; never compiled into the app.
#pragma once
#include <memory>
#include <span>
#include <vector>
namespace media {
class AudioBus {
 public:
  AudioBus(int channels, int frames) : channels_(channels), frames_(frames), data_(channels, std::vector<float>(frames)) {}
  static std::unique_ptr<AudioBus> Create(int channels, int frames) { return std::make_unique<AudioBus>(channels, frames); }
  int channels() const { return channels_; }
  int frames() const { return frames_; }
  std::span<float> channel(int channel) { return data_.at(channel); }
  std::span<const float> channel(int channel) const { return data_.at(channel); }
 private:
  int channels_, frames_;
  std::vector<std::vector<float>> data_;
};
}
