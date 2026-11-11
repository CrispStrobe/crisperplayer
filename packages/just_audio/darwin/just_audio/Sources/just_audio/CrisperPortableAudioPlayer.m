// SPDX-License-Identifier: MIT
// Copyright (c) 2026 CrisperPlayer contributors
#import "./include/just_audio/CrisperPortableAudioPlayer.h"
#import "./include/just_audio/CrisperDspStream.h"
#import "./include/just_audio/BetterEventChannel.h"
#import <math.h>
#include <string.h>

static NSError *portableError(NSString *message) {
    return [NSError errorWithDomain:@"CrisperPortableAudio" code:1
                          userInfo:@{NSLocalizedDescriptionKey: message}];
}
static int64_t optionalInteger(id value, int64_t fallback) {
    return [value isKindOfClass:[NSNumber class]] ? [value longLongValue] : fallback;
}
static NSMutableDictionary *mutableTree(NSDictionary *source) {
    NSMutableDictionary *tree = [source mutableCopy];
    if ([source[@"children"] isKindOfClass:[NSArray class]]) {
        NSMutableArray *children = [NSMutableArray array];
        for (NSDictionary *child in source[@"children"]) [children addObject:mutableTree(child)];
        tree[@"children"] = children;
    }
    if ([source[@"child"] isKindOfClass:[NSDictionary class]]) tree[@"child"] = mutableTree(source[@"child"]);
    return tree;
}

@implementation CrisperPortableAudioPlayer {
    FlutterMethodChannel *_methodChannel;
    BetterEventChannel *_events;
    BetterEventChannel *_dataEvents;
    dispatch_queue_t _queue;
    dispatch_source_t _timer;
    AVAudioEngine *_audioEngine;
    AVAudioPlayerNode *_node;
    CrisperDspStream *_stream;
    NSMutableDictionary *_sourceTree;
    NSMutableArray<NSDictionary *> *_sources;
    NSArray<NSNumber *> *_shuffleOrder;
    NSInteger _engine;
    NSInteger _index;
    NSInteger _generation;
    NSInteger _queuedBuffers;
    int64_t _scheduledFrames;
    int64_t _completedFrames;
    int64_t _timelineScheduledEnd;
    NSMutableArray<NSDictionary *> *_scheduledSegments;
    int64_t _lastPosition;
    double _rate;
    float _volume;
    enum ProcessingState _state;
    enum LoopMode _loopMode;
    BOOL _shuffle;
    BOOL _playing;
    BOOL _disposed;
    BOOL _manualRendering;
    FlutterResult _playResult;
    void (^_eventHandler)(NSDictionary *);
    id _configurationObserver;
    id _interruptionObserver;
    id _routeObserver;
}

+ (NSInteger)engineIdentifierForName:(NSString *)name {
    if ([name isEqualToString:@"sonic"]) return 0;
    if ([name isEqualToString:@"bungee"]) return 1;
    if ([name isEqualToString:@"signalsmith"]) return 2;
    if ([name isEqualToString:@"wsola"]) return 3;
    return -1;
}

- (instancetype)initWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar
                        playerId:(NSString *)playerId engine:(NSInteger)engine {
    self = [self initWithEngine:engine manualRendering:NO eventHandler:nil];
    if (!self) return nil;
    _methodChannel = [FlutterMethodChannel methodChannelWithName:[@"com.ryanheise.just_audio.methods." stringByAppendingString:playerId]
                                               binaryMessenger:registrar.messenger];
    _events = [[BetterEventChannel alloc] initWithName:[@"com.ryanheise.just_audio.events." stringByAppendingString:playerId]
                                          messenger:registrar.messenger];
    _dataEvents = [[BetterEventChannel alloc] initWithName:[@"com.ryanheise.just_audio.data." stringByAppendingString:playerId]
                                              messenger:registrar.messenger];
    __weak CrisperPortableAudioPlayer *weakSelf = self;
    [_methodChannel setMethodCallHandler:^(FlutterMethodCall *call, FlutterResult result) {
        CrisperPortableAudioPlayer *strongSelf = weakSelf;
        if (!strongSelf) { result(FlutterMethodNotImplemented); return; }
        [strongSelf handleMethodCall:call result:result];
    }];
    return self;
}

- (instancetype)initWithEngine:(NSInteger)engine manualRendering:(BOOL)manualRendering eventHandler:(void (^)(NSDictionary *))eventHandler {
    self = [super init];
    if (!self) return nil;
    _engine = engine;
    _manualRendering = manualRendering;
    _rate = 1;
    _volume = 1;
    _state = psIdle;
    _eventHandler = [eventHandler copy];
    _queue = dispatch_queue_create("com.crisperplayer.portable-audio", DISPATCH_QUEUE_SERIAL);
    __weak CrisperPortableAudioPlayer *weakSelf = self;
    _timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _queue);
    dispatch_source_set_timer(_timer, dispatch_time(DISPATCH_TIME_NOW, 200 * NSEC_PER_MSEC),
                             200 * NSEC_PER_MSEC, 20 * NSEC_PER_MSEC);
    dispatch_source_set_event_handler(_timer, ^{
        CrisperPortableAudioPlayer *strongSelf = weakSelf;
        if (strongSelf && strongSelf->_playing && strongSelf->_state != psCompleted) [strongSelf broadcast:nil];
    });
    dispatch_resume(_timer);
    _configurationObserver = [[NSNotificationCenter defaultCenter]
        addObserverForName:AVAudioEngineConfigurationChangeNotification object:nil queue:nil
        usingBlock:^(NSNotification *notification) {
            CrisperPortableAudioPlayer *strongSelf = weakSelf;
            if (!strongSelf) return;
            dispatch_async(strongSelf->_queue, ^{
                if (strongSelf->_disposed || notification.object != strongSelf->_audioEngine || !strongSelf->_stream) return;
                NSError *error = nil;
                int64_t position = [strongSelf currentPosition];
                if (![strongSelf openIndex:strongSelf->_index position:position error:&error]) [strongSelf fail:error];
                else [strongSelf broadcast:nil];
            });
        }];
#if !TARGET_OS_OSX
    _interruptionObserver = [[NSNotificationCenter defaultCenter]
        addObserverForName:AVAudioSessionInterruptionNotification object:nil queue:nil
        usingBlock:^(NSNotification *notification) {
            if ([notification.userInfo[AVAudioSessionInterruptionTypeKey] unsignedIntegerValue] != AVAudioSessionInterruptionTypeBegan) return;
            CrisperPortableAudioPlayer *strongSelf = weakSelf;
            if (strongSelf) dispatch_async(strongSelf->_queue, ^{ [strongSelf pauseForSystem]; });
        }];
    _routeObserver = [[NSNotificationCenter defaultCenter]
        addObserverForName:AVAudioSessionRouteChangeNotification object:nil queue:nil
        usingBlock:^(NSNotification *notification) {
            if ([notification.userInfo[AVAudioSessionRouteChangeReasonKey] unsignedIntegerValue] != AVAudioSessionRouteChangeReasonOldDeviceUnavailable) return;
            CrisperPortableAudioPlayer *strongSelf = weakSelf;
            if (strongSelf) dispatch_async(strongSelf->_queue, ^{ [strongSelf pauseForSystem]; });
        }];
#endif
    return self;
}

- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result {
    dispatch_async(_queue, ^{ [self handleCall:call result:result]; });
}

- (void)renderOfflineFrames:(AVAudioFrameCount)frames completion:(void (^)(AVAudioPCMBuffer *, NSError *))completion {
    dispatch_async(_queue, ^{
        NSError *error = nil;
        AVAudioPCMBuffer *buffer = nil;
        if (self->_disposed || !self->_manualRendering || !self->_playing || !self->_stream || frames == 0 || frames > 65536) {
            error = portableError(@"Offline rendering requires an active offline integration player and 1–65536 frames.");
        } else {
            buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:self->_stream.format frameCapacity:frames];
            AVAudioPCMBuffer *block = [[AVAudioPCMBuffer alloc] initWithPCMFormat:self->_stream.format frameCapacity:MIN(frames, 4096)];
            for (AVAudioFrameCount offset = 0; offset < frames; offset += 4096) {
                block.frameLength = 0;
                AVAudioEngineManualRenderingStatus status = [self->_audioEngine renderOffline:MIN(frames - offset, 4096) toBuffer:block error:&error];
                if (status == AVAudioEngineManualRenderingStatusError && !error) error = portableError(@"Offline audio rendering failed.");
                if (error || block.frameLength == 0) break;
                for (AVAudioChannelCount channel = 0; channel < buffer.format.channelCount; ++channel) {
                    memcpy(buffer.floatChannelData[channel] + buffer.frameLength, block.floatChannelData[channel], block.frameLength * sizeof(float));
                }
                buffer.frameLength += block.frameLength;
            }
            [self broadcast:nil];
        }
        dispatch_async(dispatch_get_main_queue(), ^{ completion(buffer, error); });
    });
}

- (void)reply:(FlutterResult)result value:(id)value {
    if (result) dispatch_async(dispatch_get_main_queue(), ^{ result(value); });
}

- (void)finishPlay {
    FlutterResult result = _playResult;
    _playResult = nil;
    [self reply:result value:@{}];
}

- (int64_t)currentPosition {
    if (!_stream || !_node || !_playing) return _lastPosition;
    int64_t frames = _completedFrames;
    BOOL audiblePCM = NO;
    AVAudioTime *renderTime = _node.lastRenderTime;
    AVAudioTime *playerTime = renderTime ? [_node playerTimeForNodeTime:renderTime] : nil;
    BOOL validClock = _manualRendering ? _audioEngine.manualRenderingSampleTime > 0 : playerTime.isSampleTimeValid;
    if (validClock && _audioEngine.isRunning && _node.isPlaying) {
        // Rendering can run ahead of the device. Never count queued PCM as
        // heard media, and never move behind a dataPlayedBack boundary.
        int64_t latency = _manualRendering ? 0 : (int64_t)llround(_node.outputPresentationLatency * _stream.format.sampleRate);
        int64_t timelineTime = _manualRendering ? _audioEngine.manualRenderingSampleTime : playerTime.sampleTime;
        int64_t heardTime = timelineTime - latency;
        // A slow decode may leave a silent gap on the node's timeline. Count
        // only intervals containing scheduled PCM, never that silence.
        for (NSDictionary *segment in _scheduledSegments) {
            int64_t start = [segment[@"timelineStart"] longLongValue];
            int64_t end = [segment[@"timelineEnd"] longLongValue];
            if (heardTime < start) break;
            int64_t output = [segment[@"outputStart"] longLongValue] + MIN(heardTime, end) - start;
            frames = MAX(frames, output);
            if (heardTime < end) { audiblePCM = YES; break; }
        }
    }
    int64_t position = MAX(_lastPosition, [_stream mediaPositionForOutputFrames:frames]);
    if (_state == psReady || _state == psBuffering) {
        // Merely queuing PCM after starvation does not mean the listener has
        // heard it. Stay buffering until the source clock actually advances
        // into a scheduled interval, including through device startup latency.
        BOOL resumed = _state != psBuffering || position > _lastPosition;
        _state = audiblePCM && resumed ? psReady : psBuffering;
    }
    _lastPosition = position;
    return _lastPosition;
}

- (void)broadcast:(NSError *)error {
    if (_disposed) return;
    // Evaluate position first: the same render-clock snapshot also determines
    // ready/buffering. Dictionary expression ordering must not send stale ready.
    int64_t position = [self currentPosition];
    NSDictionary *event = @{
        @"processingState": @(_state),
        @"updatePosition": @(position),
        @"updateTime": @((int64_t)llround(NSDate.date.timeIntervalSince1970 * 1000)),
        @"bufferedPosition": @(_stream ? _stream.decodedPositionMicroseconds : _lastPosition),
        @"icyMetadata": @{},
        @"duration": _stream ? @(_stream.durationMicroseconds) : [NSNull null],
        @"currentIndex": @(_index),
        @"errorCode": error ? @1001 : [NSNull null],
        @"errorMessage": error ? error.localizedDescription : [NSNull null]
    };
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self->_disposed) {
            [self->_events sendEvent:event];
            if (self->_eventHandler) self->_eventHandler(event);
        }
    });
}

- (void)broadcastClockTransition {
    enum ProcessingState previous = _state;
    [self currentPosition];
    if (_state != previous) [self broadcast:nil];
}

- (void)resetOutput {
    ++_generation;
    [_node stop];
    [_audioEngine stop];
    _node = nil;
    _audioEngine = nil;
    _stream = nil;
    _queuedBuffers = 0;
    _scheduledFrames = _completedFrames = 0;
    _timelineScheduledEnd = 0;
    _scheduledSegments = [NSMutableArray array];
}

- (void)fail:(NSError *)error {
    if (!error) error = portableError(@"Portable audio playback failed.");
    [self currentPosition];
    [self resetOutput];
    _playing = NO;
    _state = psIdle;
    [self finishPlay];
    [self broadcast:error];
    dispatch_async(dispatch_get_main_queue(), ^{ if (!self->_disposed) [self->_dataEvents sendEvent:@{@"playing": @NO}]; });
}

- (void)pauseForSystem {
    if (_disposed || !_playing) return;
    [self currentPosition];
    [_node pause];
    [_audioEngine pause];
    _playing = NO;
    [self finishPlay];
    [self broadcast:nil];
    dispatch_async(dispatch_get_main_queue(), ^{ if (!self->_disposed) [self->_dataEvents sendEvent:@{@"playing": @NO}]; });
}

// Flatten the standard just_audio source tree while retaining its recursive
// shuffle order. The application supplies progressive local book-file queues.
- (NSArray<NSNumber *> *)flatten:(NSDictionary *)source start:(int64_t)start end:(int64_t)end
                           depth:(NSUInteger)depth error:(NSError **)error {
    if (depth > 32 || _sources.count >= 10000) { *error = portableError(@"Audio playlist is too large or deeply nested."); return nil; }
    NSString *type = source[@"type"];
    if ([type isEqualToString:@"progressive"]) {
        NSURL *url = [NSURL URLWithString:source[@"uri"]];
        if (!url.isFileURL) { *error = portableError(@"Portable processors require downloaded local files. Choose an Apple processor for streaming URLs."); return nil; }
        NSNumber *index = @(_sources.count);
        [_sources addObject:@{@"uri": url, @"id": source[@"id"] ?: @"", @"start": @(start), @"end": @(end)}];
        return @[index];
    }
    if ([type isEqualToString:@"clipping"]) {
        int64_t clipStart = optionalInteger(source[@"start"], 0);
        int64_t clipEnd = optionalInteger(source[@"end"], -1);
        if (clipStart < 0 || (clipEnd >= 0 && clipEnd < clipStart) || start > INT64_MAX - clipStart || (clipEnd >= 0 && start > INT64_MAX - clipEnd)) {
            *error = portableError(@"Invalid clip bounds."); return nil;
        }
        int64_t absoluteEnd = clipEnd < 0 ? end : (end < 0 ? start + clipEnd : MIN(end, start + clipEnd));
        return [self flatten:source[@"child"] start:start + clipStart end:absoluteEnd depth:depth + 1 error:error];
    }
    if ([type isEqualToString:@"looping"]) {
        NSInteger count = [source[@"count"] integerValue];
        if (count < 0 || count > 10000) { *error = portableError(@"Invalid loop count."); return nil; }
        NSMutableArray *order = [NSMutableArray array];
        for (NSInteger n = 0; n < count; ++n) {
            NSArray *child = [self flatten:source[@"child"] start:start end:end depth:depth + 1 error:error];
            if (!child) return nil;
            [order addObjectsFromArray:child];
        }
        return order;
    }
    if ([type isEqualToString:@"concatenating"]) {
        NSMutableArray<NSArray *> *groups = [NSMutableArray array];
        for (NSDictionary *child in source[@"children"]) {
            NSArray *group = [self flatten:child start:start end:end depth:depth + 1 error:error];
            if (!group) return nil;
            [groups addObject:group];
        }
        NSArray *shuffle = source[@"shuffleOrder"];
        NSMutableArray *order = [NSMutableArray array];
        NSMutableIndexSet *seen = [NSMutableIndexSet indexSet];
        if ([shuffle isKindOfClass:[NSArray class]] && shuffle.count == groups.count) {
            for (NSNumber *value in shuffle) {
                NSInteger index = value.integerValue;
                if (index < 0 || index >= (NSInteger)groups.count || [seen containsIndex:index]) { *error = portableError(@"Invalid playlist shuffle order."); return nil; }
                [seen addIndex:index];
                [order addObjectsFromArray:groups[index]];
            }
        } else for (NSArray *group in groups) [order addObjectsFromArray:group];
        return order;
    }
    *error = portableError(@"This source needs an Apple processor. Portable processors support downloaded local audio files.");
    return nil;
}

- (BOOL)rebuildSources:(NSError **)error {
    _sources = [NSMutableArray array];
    _shuffleOrder = [self flatten:_sourceTree start:0 end:-1 depth:0 error:error];
    return _shuffleOrder != nil;
}

- (BOOL)openIndex:(NSInteger)index position:(int64_t)position error:(NSError **)error {
    [self resetOutput];
    _index = index;
    _lastPosition = MAX(0, position);
    if (_sources.count == 0) { _index = 0; _lastPosition = 0; _state = psCompleted; return YES; }
    if (index < 0 || index >= (NSInteger)_sources.count) { *error = portableError(@"Audio playlist index is out of range."); return NO; }
    NSDictionary *source = _sources[index];
    _stream = [[CrisperDspStream alloc] initWithURL:source[@"uri"] engine:_engine rate:_rate
                                       clipStart:[source[@"start"] longLongValue] clipEnd:[source[@"end"] longLongValue]
                                        position:MAX(0, position) error:error];
    if (!_stream) return NO;
    _lastPosition = [_stream mediaPositionForOutputFrames:0];
    _audioEngine = [[AVAudioEngine alloc] init];
    _node = [[AVAudioPlayerNode alloc] init];
    [_audioEngine attachNode:_node];
    [_audioEngine connect:_node to:_audioEngine.mainMixerNode format:_stream.format];
    _node.volume = _volume;
    if (_manualRendering && ![_audioEngine enableManualRenderingMode:AVAudioEngineManualRenderingModeOffline
                                                             format:_stream.format maximumFrameCount:4096 error:error]) return NO;
    [_audioEngine prepare];
    _state = psReady;
    if (![self fillBuffers:error]) return NO;
    if (_playing && _queuedBuffers > 0) {
        if (![_audioEngine startAndReturnError:error]) return NO;
        [_node play];
    }
    if (_queuedBuffers == 0 && _stream.isEnded) _state = psCompleted;
    return YES;
}

- (BOOL)fillBuffers:(NSError **)error {
    // Report a depleted audible queue before doing decoder/DSP work. Queuing
    // future buffers below must not prematurely report recovery from that gap.
    [self broadcastClockTransition];
    // Four buffers bound queued output to 16,384 frames. All decoding/DSP runs
    // on this worker queue, never on the real-time render callback.
    while (_queuedBuffers < 4 && !_stream.isEnded) {
        AVAudioPCMBuffer *buffer = [_stream readFrames:4096 error:error];
        if (!buffer) return NO;
        if (buffer.frameLength == 0) break;
        NSInteger generation = _generation;
        int64_t timelineStart = _timelineScheduledEnd;
        AVAudioTime *renderTime = _node.lastRenderTime;
        AVAudioTime *playerTime = renderTime ? [_node playerTimeForNodeTime:renderTime] : nil;
        int64_t now = _manualRendering ? _audioEngine.manualRenderingSampleTime :
            (playerTime.isSampleTimeValid ? playerTime.sampleTime : -1);
        if (now > timelineStart) {
            // Recovery after starvation: explicitly schedule in the future and
            // retain the gap in the clock map instead of skipping source time.
            timelineStart = now + (_manualRendering ? 0 : (int64_t)ceil(_stream.format.sampleRate * .05));
        }
        int64_t completed = _scheduledFrames + buffer.frameLength;
        _timelineScheduledEnd = timelineStart + buffer.frameLength;
        [_scheduledSegments addObject:@{@"timelineStart": @(timelineStart), @"timelineEnd": @(_timelineScheduledEnd),
                                         @"outputStart": @(_scheduledFrames), @"outputEnd": @(completed)}];
        _scheduledFrames = completed;
        ++_queuedBuffers;
        __weak CrisperPortableAudioPlayer *weakSelf = self;
        AVAudioTime *time = [AVAudioTime timeWithSampleTime:timelineStart atRate:_stream.format.sampleRate];
        [_node scheduleBuffer:buffer atTime:time options:0
          completionCallbackType:_manualRendering ? AVAudioPlayerNodeCompletionDataRendered : AVAudioPlayerNodeCompletionDataPlayedBack
          completionHandler:^(AVAudioPlayerNodeCompletionCallbackType callbackType) {
            CrisperPortableAudioPlayer *strongSelf = weakSelf;
            if (!strongSelf) return;
            dispatch_async(strongSelf->_queue, ^{
                if (strongSelf->_disposed || generation != strongSelf->_generation) return;
                strongSelf->_completedFrames = MAX(strongSelf->_completedFrames, completed);
                --strongSelf->_queuedBuffers;
                while (strongSelf->_scheduledSegments.count &&
                       [strongSelf->_scheduledSegments.firstObject[@"outputEnd"] longLongValue] <= strongSelf->_completedFrames) {
                    [strongSelf->_scheduledSegments removeObjectAtIndex:0];
                }
                NSError *nextError = nil;
                if (![strongSelf fillBuffers:&nextError]) { [strongSelf fail:nextError]; return; }
                if (strongSelf->_queuedBuffers == 0 && strongSelf->_stream.isEnded) [strongSelf advance];
            });
        }];
    }
    [self broadcastClockTransition];
    return YES;
}

- (void)advance {
    // At most one traversal: an empty file/clip in an all-empty looping list
    // must terminate, never spin the worker or leave a play future hanging.
    for (NSUInteger skipped = 0; skipped < MAX((NSUInteger)1, _sources.count); ++skipped) {
        _lastPosition = _stream.durationMicroseconds;
        NSInteger next = _index + 1;
        if (_loopMode == lmLoopOne) {
            if (_stream.durationMicroseconds == 0) break;
            next = _index;
        } else if (_shuffle) {
            NSUInteger at = [_shuffleOrder indexOfObject:@(_index)];
            next = at != NSNotFound && at + 1 < _shuffleOrder.count ? _shuffleOrder[at + 1].integerValue : _sources.count;
        }
        if (next >= (NSInteger)_sources.count && _loopMode == lmLoopAll && _sources.count) next = _shuffle ? _shuffleOrder.firstObject.integerValue : 0;
        if (next >= (NSInteger)_sources.count) break;
        NSError *error = nil;
        if (![self openIndex:next position:0 error:&error]) { [self fail:error]; return; }
        if (_queuedBuffers > 0) { [self broadcast:nil]; return; }
    }
    [_node pause];
    [_audioEngine pause];
    _state = psCompleted;
    [self finishPlay];
    [self broadcast:nil];
}

- (NSMutableDictionary *)findSource:(NSString *)identifier inTree:(NSMutableDictionary *)tree {
    if ([tree[@"id"] isEqual:identifier]) return tree;
    for (NSMutableDictionary *child in tree[@"children"]) {
        NSMutableDictionary *match = [self findSource:identifier inTree:child];
        if (match) return match;
    }
    return tree[@"child"] ? [self findSource:identifier inTree:tree[@"child"]] : nil;
}

- (void)copyShuffle:(NSDictionary *)incoming toTree:(NSMutableDictionary *)tree {
    if (incoming[@"shuffleOrder"]) tree[@"shuffleOrder"] = incoming[@"shuffleOrder"];
    NSArray *children = incoming[@"children"];
    NSMutableArray *targets = tree[@"children"];
    for (NSUInteger i = 0; i < MIN(children.count, targets.count); ++i) [self copyShuffle:children[i] toTree:targets[i]];
    if (incoming[@"child"] && tree[@"child"]) [self copyShuffle:incoming[@"child"] toTree:tree[@"child"]];
}

- (void)handleCall:(FlutterMethodCall *)call result:(FlutterResult)result {
    if (_disposed) { [self reply:result value:[FlutterError errorWithCode:@"disposed" message:@"Audio player is disposed." details:nil]]; return; }
    @try {
        NSDictionary *request = call.arguments;
        NSString *method = call.method;
        NSError *error = nil;
        if ([method isEqualToString:@"load"]) {
            _state = psLoading;
            [self resetOutput];
            _lastPosition = 0;
            [self broadcast:nil];
            _sourceTree = mutableTree(request[@"audioSource"]);
            if ([self rebuildSources:&error]) [self openIndex:optionalInteger(request[@"initialIndex"], 0) position:optionalInteger(request[@"initialPosition"], 0) error:&error];
            if (!error) {
                if (_playing && _state == psCompleted) [self advance];
                [self broadcast:nil];
                [self reply:result value:@{@"duration": _stream ? @(_stream.durationMicroseconds) : [NSNull null]}];
                return;
            }
        } else if ([method isEqualToString:@"play"]) {
            if (_playResult) [self finishPlay];
            _playResult = result;
            _playing = YES;
            if (_state == psCompleted) {
                if (_stream.durationMicroseconds == 0 && _sources.count) [self advance];
                else [self finishPlay];
                return;
            }
            if (_node) {
                if (![_audioEngine startAndReturnError:&error]) { /* reported below */ }
                else [_node play];
            }
            if (!error) { [self broadcast:nil]; return; }
            _playResult = nil;
        } else if ([method isEqualToString:@"pause"]) {
            [self currentPosition];
            [_node pause];
            [_audioEngine pause];
            _playing = NO;
            [self finishPlay];
            [self broadcast:nil];
        } else if ([method isEqualToString:@"setVolume"]) {
            double volume = [request[@"volume"] doubleValue];
            if (!isfinite(volume) || volume < 0 || volume > 1) error = portableError(@"Volume must be between 0 and 1.");
            else { _volume = (float)volume; _node.volume = _volume; }
        } else if ([method isEqualToString:@"setSpeed"]) {
            double rate = [request[@"speed"] doubleValue];
            if (!isfinite(rate) || rate < .5 || rate > 3) error = portableError(@"Portable playback speed must be between 0.5 and 3.0.");
            else if (rate != _rate) {
                int64_t position = [self currentPosition];
                _rate = rate;
                if (_stream) [self openIndex:_index position:position error:&error];
                [self broadcast:nil];
            }
        } else if ([method isEqualToString:@"seek"]) {
            NSInteger index = optionalInteger(request[@"index"], _index);
            [self openIndex:index position:optionalInteger(request[@"position"], 0) error:&error];
            if (!error && _playing && _state == psCompleted) [self advance];
            [self broadcast:nil];
        } else if ([method isEqualToString:@"setLoopMode"]) {
            NSInteger mode = [request[@"loopMode"] integerValue];
            if (mode < lmLoopOff || mode > lmLoopAll) error = portableError(@"Invalid loop mode.");
            else _loopMode = (enum LoopMode)mode;
        } else if ([method isEqualToString:@"setShuffleMode"]) {
            _shuffle = [request[@"shuffleMode"] integerValue] == 1;
        } else if ([method isEqualToString:@"setShuffleOrder"]) {
            if (_sourceTree) { [self copyShuffle:request[@"audioSource"] toTree:_sourceTree]; [self rebuildSources:&error]; }
        } else if ([method hasPrefix:@"concatenating"]) {
            int64_t position = [self currentPosition];
            NSString *currentId = _index < (NSInteger)_sources.count ? _sources[_index][@"id"] : nil;
            NSMutableDictionary *target = [self findSource:request[@"id"] inTree:_sourceTree];
            NSMutableArray *children = target[@"children"];
            if (!children) error = portableError(@"Playlist source was not found.");
            else {
                if ([method isEqualToString:@"concatenatingInsertAll"]) {
                    NSInteger at = [request[@"index"] integerValue];
                    if (at < 0) at = children.count;
                    for (NSDictionary *child in request[@"children"]) [children insertObject:mutableTree(child) atIndex:at++];
                } else if ([method isEqualToString:@"concatenatingRemoveRange"]) {
                    NSInteger start = [request[@"startIndex"] integerValue];
                    NSInteger end = [request[@"endIndex"] integerValue];
                    if (end < 0) end = children.count;
                    [children removeObjectsInRange:NSMakeRange(start, end - start)];
                } else if ([method isEqualToString:@"concatenatingMove"]) {
                    NSInteger from = [request[@"currentIndex"] integerValue];
                    id child = children[from];
                    [children removeObjectAtIndex:from];
                    [children insertObject:child atIndex:[request[@"newIndex"] integerValue]];
                } else error = portableError(@"Unknown playlist operation.");
                if (!error) {
                    target[@"shuffleOrder"] = request[@"shuffleOrder"];
                    if ([self rebuildSources:&error]) {
                        NSInteger next = MIN(_index, MAX(0, (NSInteger)_sources.count - 1));
                        BOOL found = NO;
                        for (NSInteger i = 0; i < (NSInteger)_sources.count; ++i) if ([_sources[i][@"id"] isEqual:currentId]) { next = i; found = YES; break; }
                        [self openIndex:next position:found ? position : 0 error:&error];
                        if (!error && _playing && _state == psCompleted) [self advance];
                        [self broadcast:nil];
                    }
                }
            }
        } else if ([method isEqualToString:@"setSkipSilence"]) {
            if ([request[@"enabled"] boolValue]) error = portableError(@"Skip silence is unavailable with portable Apple processors.");
        } else if ([method isEqualToString:@"setAllowsExternalPlayback"]) {
            if ([request[@"allowsExternalPlayback"] boolValue]) error = portableError(@"External AVPlayer playback requires an Apple processor.");
        } else if ([method isEqualToString:@"setAutomaticallyWaitsToMinimizeStalling"] ||
                   [method isEqualToString:@"setCanUseNetworkResourcesForLiveStreamingWhilePaused"] ||
                   [method isEqualToString:@"setPreferredPeakBitRate"] ||
                   [method isEqualToString:@"setAndroidAudioAttributes"]) {
            // These AVPlayer network preferences have no effect on local PCM.
        } else { [self reply:result value:FlutterMethodNotImplemented]; return; }
        if (error) {
            [self fail:error];
            [self reply:result value:[FlutterError errorWithCode:@"portableAudio" message:error.localizedDescription details:nil]];
        } else [self reply:result value:@{}];
    } @catch (NSException *exception) {
        NSError *error = portableError(exception.reason ?: @"Invalid portable audio operation.");
        [self fail:error];
        [self reply:result value:[FlutterError errorWithCode:@"portableAudio" message:error.localizedDescription details:nil]];
    }
}

- (void)dispose:(BOOL)calledFromDealloc {
    [_methodChannel setMethodCallHandler:nil];
    if (_configurationObserver) [[NSNotificationCenter defaultCenter] removeObserver:_configurationObserver];
    if (_interruptionObserver) [[NSNotificationCenter defaultCenter] removeObserver:_interruptionObserver];
    if (_routeObserver) [[NSNotificationCenter defaultCenter] removeObserver:_routeObserver];
    dispatch_sync(_queue, ^{
        if (self->_disposed) return;
        self->_disposed = YES;
        dispatch_source_cancel(self->_timer);
        [self resetOutput];
        if (!calledFromDealloc) [self finishPlay];
        else self->_playResult = nil;
    });
    [_events dispose];
    [_dataEvents dispose];
}
@end
