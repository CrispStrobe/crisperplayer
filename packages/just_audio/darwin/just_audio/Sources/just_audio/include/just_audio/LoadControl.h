#import <Foundation/Foundation.h>

@interface LoadControl : NSObject

@property (readwrite, nonatomic) NSNumber *preferredForwardBufferDuration;
@property (readwrite, nonatomic) BOOL canUseNetworkResourcesForLiveStreamingWhilePaused;
@property (readwrite, nonatomic) NSNumber *preferredPeakBitRate;
// CrisperPlayer addition: defaults to NO, preserving upstream Time Domain.
@property (readwrite, nonatomic) BOOL useSpectralTimePitchAlgorithm;

@end
