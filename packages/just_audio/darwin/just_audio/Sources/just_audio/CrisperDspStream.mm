// SPDX-License-Identifier: MIT
// Copyright (c) 2026 CrisperPlayer contributors
#import "./include/just_audio/CrisperDspStream.h"
#include "../../../../native/crisper_dsp/crisper_dsp.h"
#include <algorithm>
#include <cmath>
#include <vector>

namespace {
NSError *streamError(NSString *message) {
    return [NSError errorWithDomain:@"CrisperPortableAudio" code:1
                          userInfo:@{NSLocalizedDescriptionKey: message}];
}
NSError *dspError() {
    return streamError([NSString stringWithUTF8String:cp_dsp_last_error()]);
}
}

@implementation CrisperDspStream {
    AVAudioFile *_file;
    AVAudioPCMBuffer *_decodeBuffer;
    cp_dsp *_dsp;
    std::vector<float> _pending;
    std::vector<float> _output;
    int _pendingFrames;
    int _pendingOffset;
    int _channels;
    double _sampleRate;
    double _rate;
    int64_t _clipStartFrame;
    int64_t _endFrame;
    int64_t _startFrame;
    BOOL _finishedInput;
}

- (instancetype)initWithURL:(NSURL *)url engine:(NSInteger)engine rate:(double)rate
                 clipStart:(int64_t)clipStart clipEnd:(int64_t)clipEnd
                  position:(int64_t)position error:(NSError **)error {
    self = [super init];
    if (!self) return nil;
    if (!url.isFileURL) {
        if (error) *error = streamError(@"Portable processors require a downloaded local audio file. Choose an Apple processor for streaming URLs.");
        return nil;
    }
    _file = [[AVAudioFile alloc] initForReading:url commonFormat:AVAudioPCMFormatFloat32
                                  interleaved:NO error:error];
    if (!_file) return nil;
    _format = _file.processingFormat;
    _sampleRate = _format.sampleRate;
    _channels = (int)_format.channelCount;
    _rate = rate;
    if (!std::isfinite(_sampleRate) || _sampleRate < 8000 || _sampleRate > 192000 ||
        (_channels != 1 && _channels != 2) ||
        std::fabs(_sampleRate - std::round(_sampleRate)) > 0.001) {
        if (error) *error = streamError(@"Portable processors support mono/stereo audio at 8–192 kHz. Choose an Apple processor for this file.");
        return nil;
    }
    if (clipStart < 0 || (clipEnd >= 0 && clipEnd < clipStart) || position < 0) {
        if (error) *error = streamError(@"Invalid audio clip or seek position.");
        return nil;
    }
    auto toFrame = [self](int64_t micros) {
        // Bound before conversion, including an arbitrarily large seek request.
        return int64_t(std::min(double(_file.length), std::round(double(micros) * _sampleRate / 1000000.0)));
    };
    _clipStartFrame = toFrame(clipStart);
    _endFrame = clipEnd < 0 ? _file.length : toFrame(clipEnd);
    _startFrame = _clipStartFrame + std::min(_endFrame - _clipStartFrame, toFrame(position));
    _file.framePosition = _startFrame;
    _durationMicroseconds = (int64_t)std::llround(double(_endFrame - _clipStartFrame) * 1000000.0 / _sampleRate);
    _dsp = cp_dsp_create((int)engine, (int)std::llround(_sampleRate), _channels, rate);
    if (!_dsp) {
        if (error) *error = dspError();
        return nil;
    }
    _decodeBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:_format frameCapacity:4096];
    _pending.resize(4096 * _channels);
    return self;
}

- (BOOL)isEnded {
    return _dsp && cp_dsp_ended(_dsp) == 1;
}

- (int64_t)mediaPositionForOutputFrames:(int64_t)frames {
    const double source = std::min(double(_endFrame), double(_startFrame) + std::max(int64_t(0), frames) * _rate);
    return (int64_t)std::llround((source - _clipStartFrame) * 1000000.0 / _sampleRate);
}

- (int64_t)decodedPositionMicroseconds {
    const int64_t accepted = _dsp ? cp_dsp_input_frames(_dsp) : 0;
    return (int64_t)std::llround(double(std::min(_endFrame, _startFrame + accepted) - _clipStartFrame) * 1000000.0 / _sampleRate);
}

- (AVAudioPCMBuffer *)readFrames:(AVAudioFrameCount)frames error:(NSError **)error {
    if (frames == 0 || frames > 16384) {
        if (error) *error = streamError(@"Invalid portable audio read size.");
        return nil;
    }
    AVAudioPCMBuffer *buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:_format frameCapacity:frames];
    _output.resize(frames * _channels);
    int delivered = 0;
    int iterations = 0;
    while (delivered < (int)frames) {
        const int count = cp_dsp_read_f32(_dsp, _output.data() + delivered * _channels, (int)frames - delivered);
        if (count < 0) { if (error) *error = dspError(); return nil; }
        delivered += count;
        if (delivered == (int)frames || self.isEnded) break;
        // Every pass either delivers output, accepts pending input, decodes a
        // bounded block or starts the one finite drain. Catch a stalled engine.
        if (++iterations > 4096) {
            if (error) *error = streamError(@"The selected processor stopped making progress.");
            return nil;
        }
        if (_pendingOffset < _pendingFrames) {
            const int written = cp_dsp_write_f32(_dsp, _pending.data() + _pendingOffset * _channels,
                                                 _pendingFrames - _pendingOffset);
            if (written < 0) { if (error) *error = dspError(); return nil; }
            _pendingOffset += written;
        } else if (!_finishedInput) {
            const AVAudioFrameCount wanted = (AVAudioFrameCount)std::min(int64_t(4096), _endFrame - _file.framePosition);
            if (wanted > 0) {
                if (![_file readIntoBuffer:_decodeBuffer frameCount:wanted error:error]) return nil;
                _pendingFrames = (int)_decodeBuffer.frameLength;
                _pendingOffset = 0;
                for (int f = 0; f < _pendingFrames; ++f)
                    for (int c = 0; c < _channels; ++c)
                        _pending[f * _channels + c] = _decodeBuffer.floatChannelData[c][f];
            } else {
                _pendingFrames = _pendingOffset = 0;
            }
            if (wanted == 0 || _pendingFrames == 0) {
                if (cp_dsp_finish(_dsp) < 0) { if (error) *error = dspError(); return nil; }
                _finishedInput = YES;
            }
        }
    }
    buffer.frameLength = (AVAudioFrameCount)delivered;
    for (int f = 0; f < delivered; ++f)
        for (int c = 0; c < _channels; ++c)
            buffer.floatChannelData[c][f] = _output[f * _channels + c];
    return buffer;
}

- (void)dealloc {
    cp_dsp_destroy(_dsp);
}
@end
