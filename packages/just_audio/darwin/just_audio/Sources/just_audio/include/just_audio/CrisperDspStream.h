// SPDX-License-Identifier: MIT
// Copyright (c) 2026 CrisperPlayer contributors
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Bounded file decoder and stretcher. Access each instance on one serial queue.
/// Source positions are relative to the clip, in original-media microseconds.
@interface CrisperDspStream : NSObject
@property(nonatomic, readonly) AVAudioFormat *format;
@property(nonatomic, readonly) int64_t durationMicroseconds;
@property(nonatomic, readonly) int64_t decodedPositionMicroseconds;
@property(nonatomic, readonly, getter=isEnded) BOOL ended;

- (nullable instancetype)initWithURL:(NSURL *)url
                             engine:(NSInteger)engine
                               rate:(double)rate
                          clipStart:(int64_t)clipStart
                            clipEnd:(int64_t)clipEnd
                           position:(int64_t)position
                              error:(NSError * _Nullable * _Nullable)error
    NS_SWIFT_NAME(init(url:engine:rate:clipStart:clipEnd:position:));

/// Returns an empty buffer only after a complete finite DSP drain.
- (nullable AVAudioPCMBuffer *)readFrames:(AVAudioFrameCount)frames
                                   error:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(read(frames:));
- (int64_t)mediaPositionForOutputFrames:(int64_t)frames NS_SWIFT_NAME(mediaPosition(outputFrames:));
@end

NS_ASSUME_NONNULL_END
