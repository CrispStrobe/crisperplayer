// SPDX-License-Identifier: MIT
// Copyright (c) 2026 CrisperPlayer contributors
#import "AudioPlayer.h"

/// Optional local-file playback path. The normal AVQueuePlayer stays unchanged.
@interface CrisperPortableAudioPlayer : NSObject
+ (NSInteger)engineIdentifierForName:(NSString *)name NS_SWIFT_NAME(engineIdentifier(for:));
- (instancetype)initWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar
                        playerId:(NSString *)playerId
                          engine:(NSInteger)engine;
/// Native entry point used by the integration harness without a FlutterEngine.
/// Commands and event callbacks retain the same channel message contract.
- (instancetype)initWithEngine:(NSInteger)engine
                  eventHandler:(void (^)(NSDictionary *event))eventHandler
    NS_SWIFT_NAME(init(engine:eventHandler:));
- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result;
- (void)dispose:(BOOL)calledFromDealloc;
@end
