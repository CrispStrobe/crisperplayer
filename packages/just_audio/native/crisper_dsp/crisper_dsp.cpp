// SPDX-License-Identifier: MIT
// Copyright (c) 2026 CrisperPlayer contributors
// Third-party implementations retain their licenses; see vendor/manifest.json.
#include "crisper_dsp.h"

#include "bungee/Bungee.h"
#include "signalsmith-stretch.h"
#include "sonic.h"
#include "wsola/wsola.h"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <limits>
#include <memory>
#include <stdexcept>
#include <string>
#include <vector>

namespace {
constexpr int kBlock = 512;
constexpr int kInputCapacity = 131072;
constexpr int kOutputCapacity = 65536;
thread_local std::string last_error;

void require(bool ok, const char *message) {
    if (!ok) throw std::invalid_argument(message);
}
void validate(int engine, int sample_rate, int channels, double rate) {
    require(engine >= CP_DSP_SONIC && engine <= CP_DSP_WSOLA, "Unknown DSP engine");
    require(sample_rate >= 8000 && sample_rate <= 192000, "Sample rate must be 8000..192000 Hz");
    require(channels == 1 || channels == 2, "Only mono and stereo PCM are supported");
    require(std::isfinite(rate) && rate >= 0.5 && rate <= 3.0, "Rate must be finite and 0.5..3.0");
}

// Fixed-capacity rings make backpressure explicit, including during EOS drain.
class Ring {
public:
    Ring(int frames, int channels) : capacity(frames), channels(channels), data(frames * channels) {}
    int size() const { return count; }
    int free() const { return capacity - count; }
    float at(int frame, int channel) const {
        return data[((head + frame) % capacity) * channels + channel];
    }
    void append(const float *interleaved, int frames) {
        require(frames >= 0 && frames <= free(), "Output/input ring overflow");
        for (int f = 0; f < frames; ++f)
            for (int c = 0; c < channels; ++c)
                data[((head + count + f) % capacity) * channels + c] = interleaved[f * channels + c];
        count += frames;
    }
    void appendPlanar(const float *planar, int stride, int offset, int frames) {
        require(frames >= 0 && frames <= free(), "Output ring overflow");
        for (int f = 0; f < frames; ++f)
            for (int c = 0; c < channels; ++c) {
                const float sample = planar[c * stride + offset + f];
                require(std::isfinite(sample), "Processor returned non-finite PCM");
                data[((head + count + f) % capacity) * channels + c] = sample;
            }
        count += frames;
    }
    void copy(float *interleaved, int frames) const {
        for (int f = 0; f < frames; ++f)
            for (int c = 0; c < channels; ++c)
                interleaved[f * channels + c] = at(f, c);
    }
    void discard(int frames) {
        require(frames >= 0 && frames <= count, "Input/output ring underflow");
        head = (head + frames) % capacity;
        count -= frames;
    }
    void clear() { head = count = 0; }
private:
    const int capacity, channels;
    std::vector<float> data;
    int head = 0, count = 0;
};
class Engine {
public:
    virtual ~Engine() = default;
    virtual bool pump(cp_dsp &) = 0;
    virtual int latency() const = 0;
};
}

struct cp_dsp {
    cp_dsp(int id, int sr, int ch, double r) : engine_id(id), sample_rate(sr), channels(ch), rate(r),
        input(kInputCapacity, ch), output(kOutputCapacity, ch), scratch(kBlock * ch) {}
    int engine_id, sample_rate, channels;
    double rate;
    Ring input, output;
    std::vector<float> scratch;
    std::unique_ptr<Engine> processor;
    int64_t accepted = 0, input_base = 0, generated = 0, delivered = 0;
    bool finishing = false, done = false;
    int64_t limit() const {
        const double exact = double(accepted) / rate;
        return finishing ? std::llround(exact) : int64_t(std::floor(exact));
    }
    int room() const {
        return int(std::min<int64_t>(output.free(), std::max<int64_t>(0, limit() - generated)));
    }
    void consume(int frames) { input.discard(frames); input_base += frames; }
    void emit(const float *planar, int stride, int offset, int frames) {
        const int n = std::min(room(), frames);
        output.appendPlanar(planar, stride, offset, n);
        generated += n;
    }
    void pump() {
        if (done) return;
        if (finishing && generated >= limit()) { done = true; return; }
        if (rate == 1.0) {
            const int n = std::min({input.size(), output.free(), kBlock});
            input.copy(scratch.data(), n);
            output.append(scratch.data(), n);
            consume(n);
            generated += n;
            if (finishing && input.size() == 0) done = true;
            return;
        }
        // One call does bounded work. Subsequent reads/writes keep pumping.
        for (int i = 0; i < 128 && !done; ++i) {
            if (finishing && generated >= limit()) { done = true; break; }
            if (!processor->pump(*this)) break;
        }
    }
};

namespace {
class SonicEngine final : public Engine {
public:
    SonicEngine(int sr, int ch, double rate) : stream(sonicCreateStream(sr, ch)), channels(ch), sample_rate(sr), buffer(8192 * ch) {
        if (!stream) throw std::bad_alloc();
        sonicSetSpeed(stream, float(rate));
        sonicSetPitch(stream, 1.f);
        sonicSetRate(stream, 1.f);
        sonicSetQuality(stream, 1);
    }
    ~SonicEngine() override { sonicDestroyStream(stream); }
    int latency() const override { return 2 * sample_rate / 65; }
    bool pump(cp_dsp &h) override {
        const int available = sonicSamplesAvailable(stream);
        const int n = std::min({available, h.room(), 8192});
        if (n > 0) {
            const int read = sonicReadFloatFromStream(stream, buffer.data(), n);
            require(read == n, "Sonic failed to provide available PCM");
            h.output.append(buffer.data(), n);
            h.generated += n;
            return true;
        }
        if (h.output.free() < 8192) return false;
        if (h.input.size() >= kBlock || (h.finishing && h.input.size())) {
            const int frames = std::min(kBlock, h.input.size());
            h.input.copy(buffer.data(), frames);
            require(sonicWriteFloatToStream(stream, buffer.data(), frames), "Sonic could not accept PCM");
            h.consume(frames);
            return true;
        }
        if (h.finishing && !flushed) {
            require(sonicFlushStream(stream), "Sonic could not flush PCM");
            flushed = true;
            return true;
        }
        if (h.finishing && h.generated < h.limit() && available == 0) {
            // Sonic's pitch-period rounding can leave a short residual. Process
            // silence through the same filter, never fabricate a repeated sample.
            require(padded < sample_rate, "Sonic drain exceeded its bounded tail");
            std::fill(buffer.begin(), buffer.end(), 0.f);
            require(sonicWriteFloatToStream(stream, buffer.data(), kBlock), "Sonic tail padding failed");
            padded += kBlock;
            require(sonicFlushStream(stream), "Sonic tail flush failed");
            return true;
        }
        return false;
    }
private:
    sonicStream stream;
    int channels, sample_rate, padded = 0;
    bool flushed = false;
    std::vector<float> buffer;
};

class SignalsmithEngine final : public Engine {
public:
    SignalsmithEngine(int sr, int ch, double rate) : stretch(0), channels(ch), rate(rate) {
        stretch.presetDefault(ch, float(sr));
        stretch.setTransposeFactor(1.f);
        prime_frames = stretch.outputSeekLength(float(rate));
        require(prime_frames < kInputCapacity, "Signalsmith lookahead exceeds the input bound");
        stride = std::max(prime_frames, kBlock);
        planar.resize(stride * ch);
        const int max_tail = int(std::ceil(prime_frames / rate)) + 8;
        output_stride = std::max(2 * kBlock + 8, max_tail);
        require(output_stride < kOutputCapacity, "Signalsmith tail exceeds the output bound");
        rendered.resize(output_stride * ch);
        for (int c = 0; c < ch; ++c) {
            inputs[c] = planar.data() + c * stride;
            outputs[c] = rendered.data() + c * output_stride;
        }
    }
    int latency() const override { return prime_frames; }
    bool pump(cp_dsp &h) override {
        if (!primed) {
            if (h.input.size() < prime_frames && !h.finishing) return false;
            std::fill(planar.begin(), planar.end(), 0.f);
            const int n = std::min(prime_frames, h.input.size());
            copy(h, n);
            stretch.outputSeek(inputs, prime_frames);
            h.consume(n);
            primed = true;
            return true;
        }
        if (h.input.size() >= kBlock || (h.finishing && h.input.size())) {
            const int n = std::min(kBlock, h.input.size());
            const int64_t total = std::llround(double(processed + n) / rate);
            const int out = int(total - rendered_frames);
            if (h.output.free() < out) return false;
            copy(h, n);
            stretch.process(inputs, n, outputs, out);
            h.consume(n);
            processed += n;
            rendered_frames = total;
            h.emit(rendered.data(), output_stride, 0, out);
            return true;
        }
        if (h.finishing && !flushed) {
            const int out = int(h.limit() - h.generated);
            require(out <= output_stride, "Signalsmith tail exceeds its planned bound");
            if (h.output.free() < out) return false;
            // outputSeek removes preroll. Flush includes the real last samples,
            // then zero-pad internally and trim to the original source duration.
            stretch.flush(outputs, out, float(rate));
            h.emit(rendered.data(), output_stride, 0, out);
            flushed = true;
            h.done = true;
            return true;
        }
        return false;
    }
private:
    void copy(const cp_dsp &h, int n) {
        for (int c = 0; c < channels; ++c)
            for (int f = 0; f < n; ++f) planar[c * stride + f] = h.input.at(f, c);
    }
    signalsmith::stretch::SignalsmithStretch<float> stretch;
    int channels, prime_frames, stride, output_stride;
    double rate;
    int64_t processed = 0, rendered_frames = 0;
    bool primed = false, flushed = false;
    std::vector<float> planar, rendered;
    const float *inputs[2]{};
    float *outputs[2]{};
};

class BungeeEngine final : public Engine {
public:
    BungeeEngine(int sr, int ch, double rate) : stretcher({sr, sr}, ch), channels(ch), rate(rate) {
        stride = stretcher.maxInputFrameCount();
        planar.resize(stride * ch);
        request.position = 0.;
        request.speed = rate;
        request.pitch = 1.;
        stretcher.preroll(request);
    }
    int latency() const override { return stride / 2; }
    bool pump(cp_dsp &h) override {
        // At unit pitch each grain is considerably smaller than maxInputFrameCount.
        // Reserve a complete grain's output before advancing the native state.
        if (h.output.free() < std::max(4096, stride / 8 + 1)) return false;
        if (!specified) {
            // Rebase input indices for every grain. Unlike Stream's int cumulative
            // positions, this remains safe for audiobooks longer than 2^31 frames.
            const auto chunk = stretcher.specifyGrain(request, double(h.input_base));
            begin = h.input_base + chunk.begin;
            end = h.input_base + chunk.end;
            specified = true;
        }
        if (!h.finishing && end > h.accepted) return false;
        const int n = int(end - begin);
        require(n >= 0 && n <= stride, "Bungee requested an invalid input span");
        std::fill(planar.begin(), planar.end(), 0.f);
        const int head = int(std::min<int64_t>(n, std::max<int64_t>(0, -begin)));
        const int tail = int(std::min<int64_t>(n - head, std::max<int64_t>(0, end - h.accepted)));
        for (int c = 0; c < channels; ++c)
            for (int f = head; f < n - tail; ++f) {
                const int64_t index = begin + f - h.input_base;
                require(index >= 0 && index < h.input.size(), "Bungee requested discarded input");
                planar[c * stride + f] = h.input.at(int(index), c);
            }
        stretcher.analyseGrain(planar.data(), stride, head, tail);
        Bungee::OutputChunk output{};
        stretcher.synthesiseGrain(output);
        stretcher.next(request);
        specified = false;
        if (output.frameCount > 0 && output.request[0] && output.request[1]) {
            const double start = output.request[0]->position;
            const double stop = output.request[1]->position;
            if (std::isfinite(start) && std::isfinite(stop) && stop > start) {
                const double step = (stop - start) / output.frameCount;
                const int skip = int(std::clamp(std::ceil(-start / step - 1e-8), 0., double(output.frameCount)));
                h.emit(output.data, int(output.channelStride), skip, output.frameCount - skip);
            }
        }
        const int discard = int(std::clamp<int64_t>(begin - h.input_base, 0, h.input.size()));
        h.consume(discard);
        return true;
    }
private:
    Bungee::Stretcher<Bungee::Basic> stretcher;
    Bungee::Request request{};
    int channels, stride;
    double rate;
    int64_t begin = 0, end = 0;
    bool specified = false;
    std::vector<float> planar;
};

class WsolaEngine final : public Engine {
public:
    WsolaEngine(int sr, int ch, double rate) : processor(sr, ch, rate), channels(ch),
        stride(processor.maximum_input_frames()), planar(stride * ch) {
        require(stride < kInputCapacity, "WSOLA lookahead exceeds the input bound");
    }
    int latency() const override { return stride; }
    bool pump(cp_dsp &h) override {
        const int hop = processor.hop_frames();
        if (h.output.free() < hop || (!h.finishing && h.room() < hop)) return false;
        const auto range = processor.input_range();
        // Hold at least one source hop beyond a complete output hop. At fast
        // rates the ordinary search window can end before that hop's mapped
        // media endpoint; without this reserve the final words could already
        // be irreversibly emitted before EOS tells us where the source ends.
        const int64_t lookahead_end = std::max(range.end,
            int64_t(std::ceil(double(h.generated + hop) * h.rate)) + hop);
        if (!h.finishing && lookahead_end > h.accepted) return false;
        const int frames = int(range.end - range.begin);
        require(frames >= 0 && frames <= stride, "WSOLA requested an invalid input span");
        for (int c = 0; c < channels; ++c) {
            for (int f = 0; f < frames; ++f) {
                const int64_t absolute = range.begin + f;
                const int64_t offset = absolute - h.input_base;
                if (absolute < 0 || absolute >= h.accepted) {
                    planar[c * stride + f] = 0.f;
                } else {
                    require(offset >= 0 && offset < h.input.size(), "WSOLA requested discarded input");
                    planar[c * stride + f] = h.input.at(int(offset), c);
                }
            }
        }
        processor.process({planar.data(), channels, frames, stride}, range.begin);
        const int64_t remaining = h.limit() - h.generated;
        if (h.finishing && remaining <= hop) {
            const int final_frames = int(remaining);
            // Anchor the last output hop to the real final source segment.
            // A complementary half-cosine blend begins at the normal WSOLA
            // continuation and ends at the actual final sample. This general
            // boundary rule also covers partial/short hops; it does not scan
            // for impulses or fabricate/repeat an isolated final sample.
            for (int c = 0; c < channels; ++c) {
                for (int f = 0; f < final_frames; ++f) {
                    const int64_t source = h.accepted - final_frames + f;
                    float ending = 0.f;
                    if (source >= 0) {
                        const int64_t offset = source - h.input_base;
                        require(offset >= 0 && offset < h.input.size(), "WSOLA discarded its final source segment");
                        ending = h.input.at(int(offset), c);
                    }
                    const double weight = final_frames == 1 ? 1.
                        : .5 * (1. - std::cos(std::acos(-1.) * f / (final_frames - 1)));
                    planar[c * stride + f] = float(
                        processor.output()[c * hop + f] * (1. - weight) + ending * weight);
                }
            }
            h.emit(planar.data(), stride, 0, final_frames);
        } else {
            h.emit(processor.output(), hop, 0, hop);
        }
        const int64_t next = processor.input_range().begin;
        h.consume(int(std::clamp<int64_t>(next - h.input_base, 0, h.input.size())));
        return true;
    }
private:
    crisper_wsola::Processor processor;
    int channels, stride;
    std::vector<float> planar;
};

std::unique_ptr<Engine> make_engine(int id, int sr, int ch, double rate) {
    if (rate == 1.) return {};
    switch (id) {
    case CP_DSP_SONIC: return std::make_unique<SonicEngine>(sr, ch, rate);
    case CP_DSP_BUNGEE_BASIC: return std::make_unique<BungeeEngine>(sr, ch, rate);
    case CP_DSP_SIGNALSMITH: return std::make_unique<SignalsmithEngine>(sr, ch, rate);
    case CP_DSP_WSOLA: return std::make_unique<WsolaEngine>(sr, ch, rate);
    default: throw std::invalid_argument("Unknown DSP engine");
    }
}

template<typename F> int guarded(F &&f) {
    try { last_error.clear(); return f(); }
    catch (const std::exception &e) { last_error = e.what(); return -1; }
    catch (...) { last_error = "Unknown native DSP error"; return -1; }
}
int write(cp_dsp *h, const void *input, int frames, bool pcm16) {
    return guarded([&] {
        require(h && frames >= 0 && (input || frames == 0), "Invalid DSP input");
        require(!h->finishing, "Cannot write after finish; reset first");
        h->pump();
        const int n = std::min({frames, h->input.free(), kBlock});
        require(h->accepted < (int64_t(1) << 50) - n, "Stream duration exceeds precise frame counters");
        for (int i = 0; i < n * h->channels; ++i) {
            const float sample = pcm16 ? static_cast<const int16_t *>(input)[i] / 32768.f : static_cast<const float *>(input)[i];
            require(std::isfinite(sample), "Input contains non-finite PCM");
            h->scratch[i] = sample;
        }
        h->input.append(h->scratch.data(), n);
        h->accepted += n;
        h->pump();
        return n;
    });
}
int read(cp_dsp *h, void *output, int frames, bool pcm16) {
    return guarded([&] {
        require(h && frames >= 0 && (output || frames == 0), "Invalid DSP output");
        h->pump();
        const int n = std::min(frames, h->output.size());
        for (int f = 0; f < n; ++f)
            for (int c = 0; c < h->channels; ++c) {
                const float sample = h->output.at(f, c);
                if (pcm16) {
                    const double clamped = std::clamp(double(sample), -1., 32767. / 32768.);
                    static_cast<int16_t *>(output)[f * h->channels + c] = int16_t(std::lrint(clamped * 32768.));
                } else static_cast<float *>(output)[f * h->channels + c] = sample;
            }
        h->output.discard(n);
        h->delivered += n;
        h->pump();
        return n;
    });
}
}

extern "C" {
cp_dsp *cp_dsp_create(int engine, int sample_rate, int channels, double rate) {
    try {
        last_error.clear();
        validate(engine, sample_rate, channels, rate);
        auto h = std::make_unique<cp_dsp>(engine, sample_rate, channels, rate);
        h->processor = make_engine(engine, sample_rate, channels, rate);
        return h.release();
    } catch (const std::exception &e) { last_error = e.what(); return nullptr; }
    catch (...) { last_error = "Unknown native DSP creation error"; return nullptr; }
}
void cp_dsp_destroy(cp_dsp *h) { delete h; }
int cp_dsp_write_s16(cp_dsp *h, const int16_t *p, int frames) { return write(h, p, frames, true); }
int cp_dsp_read_s16(cp_dsp *h, int16_t *p, int frames) { return read(h, p, frames, true); }
int cp_dsp_write_f32(cp_dsp *h, const float *p, int frames) { return write(h, p, frames, false); }
int cp_dsp_read_f32(cp_dsp *h, float *p, int frames) { return read(h, p, frames, false); }
int cp_dsp_available(cp_dsp *h) {
    return guarded([&] { require(h, "Null DSP handle"); h->pump(); return h->output.size(); });
}
int cp_dsp_finish(cp_dsp *h) {
    return guarded([&] { require(h, "Null DSP handle"); h->finishing = true; h->pump(); return 0; });
}
int cp_dsp_ended(cp_dsp *h) {
    return guarded([&] { require(h, "Null DSP handle"); h->pump(); return int(h->done && h->output.size() == 0); });
}
int cp_dsp_reset(cp_dsp *h, double rate) {
    return guarded([&] {
        require(h, "Null DSP handle");
        validate(h->engine_id, h->sample_rate, h->channels, rate);
        // Construct before replacing so invalid/failed reconfiguration preserves state.
        auto replacement = make_engine(h->engine_id, h->sample_rate, h->channels, rate);
        h->processor = std::move(replacement);
        h->rate = rate;
        h->input.clear(); h->output.clear();
        h->accepted = h->input_base = h->generated = h->delivered = 0;
        h->finishing = h->done = false;
        return 0;
    });
}
int64_t cp_dsp_source_frames(const cp_dsp *h) {
    if (!h) return -1;
    if (h->done && h->delivered == h->limit()) return h->accepted;
    return std::min(h->accepted, int64_t(std::floor(h->delivered * h->rate)));
}
int64_t cp_dsp_output_frames(const cp_dsp *h) { return h ? h->delivered : -1; }
int64_t cp_dsp_input_frames(const cp_dsp *h) { return h ? h->accepted : -1; }
int cp_dsp_latency_frames(const cp_dsp *h) { return h ? (h->processor ? h->processor->latency() : 0) : -1; }
const char *cp_dsp_last_error(void) { return last_error.c_str(); }
}
