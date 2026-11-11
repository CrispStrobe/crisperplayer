// SPDX-License-Identifier: MIT
// Copyright (c) 2026 CrisperPlayer contributors
#import "AudioPlayer.h"

NS_ASSUME_NONNULL_BEGIN
/// Optional local-file playback path. The normal AVQueuePlayer stays unchanged.
@interface CrisperPortableAudioPlayer : NSObject
+ (NSInteger)engineIdentifierForName:(NSString *)name NS_SWIFT_NAME(engineIdentifier(for:));
- (instancetype)initWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar
                        playerId:(NSString *)playerId
                          engine:(NSInteger)engine;
/// Native entry point used by the integration harness without a FlutterEngine.
/// Commands and event callbacks retain the same channel message contract.
- (instancetype)initWithEngine:(NSInteger)engine
               manualRendering:(BOOL)manualRendering
                  eventHandler:(void (^ _Nullable)(NSDictionary *event))eventHandler
    NS_SWIFT_NAME(init(engine:manualRendering:eventHandler:));
- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result;
/// Offline integration rendering uses the same scheduler, transport and DSP;
/// installed players always render to the device and reject this operation.
- (void)renderOfflineFrames:(AVAudioFrameCount)frames
                completion:(void (^)(AVAudioPCMBuffer * _Nullable, NSError * _Nullable))completion
    NS_SWIFT_NAME(renderOffline(frames:completion:));
- (void)dispose:(BOOL)calledFromDealloc;
@end
NS_ASSUME_NONNULL_END
