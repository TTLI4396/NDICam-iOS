#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 一个被发现的 NDI 源
@interface NDISource : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *address;
@end

/// NDI 发送器：接收 BGRA 原始帧并通过 NDI 广播
@interface NDISenderBridge : NSObject
- (BOOL)startWithName:(NSString *)name;
- (void)sendVideoFrameBGRA:(const uint8_t *)data
                     width:(int)width
                    height:(int)height
               bytesPerRow:(int)bytesPerRow
               frameRateN:(int)frameRateN
               frameRateD:(int)frameRateD;
- (void)stop;
@end

/// NDI 接收器：连接到某个源，解码视频帧回调
@interface NDIReceiverBridge : NSObject
@property (nonatomic, copy, nullable) void (^onFrame)(CGImageRef image);
- (BOOL)connectToSource:(NDISource *)source;
- (void)disconnect;
@end

/// NDI 源发现器
@interface NDIFinderBridge : NSObject
- (BOOL)start;
- (NSArray<NDISource *> *)currentSources;
- (void)stop;
@end

NS_ASSUME_NONNULL_END
