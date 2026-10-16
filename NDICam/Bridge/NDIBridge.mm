#import "NDIBridge.h"

#import <atomic>

#import <Processing.NDI.Lib.h>

#pragma mark - NDISource

@implementation NDISource
@end

#pragma mark - NDISenderBridge

@implementation NDISenderBridge {
    NDIlib_send_instance_t _sender;
    std::atomic<bool> _running;
}

- (BOOL)startWithName:(NSString *)name {
    if (_sender) return YES;
    if (!NDIlib_initialize()) return NO;

    NDIlib_send_create_t createSettings;
    createSettings.p_ndi_name = name.UTF8String;
    createSettings.p_groups = nullptr;
    createSettings.clock_video = true;
    createSettings.clock_audio = false;

    _sender = NDIlib_send_create(&createSettings);
    _running = (_sender != nullptr);
    return _running.load();
}

- (void)sendVideoFrameBGRA:(const uint8_t *)data
                     width:(int)width
                    height:(int)height
               bytesPerRow:(int)bytesPerRow
                frameRateN:(int)frameRateN
                frameRateD:(int)frameRateD {
    if (!_sender || !_running.load() || !data) return;

    NDIlib_video_frame_v2_t frame;
    frame.xres = width;
    frame.yres = height;
    frame.FourCC = NDIlib_FourCC_video_type_BGRA;
    frame.frame_rate_N = frameRateN;
    frame.frame_rate_D = frameRateD;
    frame.picture_aspect_ratio = (float)width / (float)height;
    frame.frame_format_type = NDIlib_frame_format_type_progressive;
    frame.timecode = NDIlib_send_timecode_synthesize;
    frame.p_data = (uint8_t *)data;
    frame.line_stride_in_bytes = bytesPerRow;
    frame.p_metadata = nullptr;
    frame.timestamp = 0;

    // 同步发送：返回后即可安全复用 data 缓冲
    NDIlib_send_send_video_v2(_sender, &frame);
}

- (void)stop {
    _running = false;
    if (_sender) {
        NDIlib_send_destroy(_sender);
        _sender = nullptr;
    }
}

- (void)dealloc {
    [self stop];
}

@end

#pragma mark - NDIReceiverBridge

@implementation NDIReceiverBridge {
    NDIlib_recv_instance_t _receiver;
    std::atomic<bool> _running;
    dispatch_queue_t _recvQueue;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _recvQueue = dispatch_queue_create("com.ndicam.recv", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (BOOL)connectToSource:(NDISource *)source {
    [self disconnect];
    if (!NDIlib_initialize()) return NO;

    NDIlib_source_t ndiSource;
    ndiSource.p_ndi_name = source.name.UTF8String;
    ndiSource.p_url_address = source.address.UTF8String;

    NDIlib_recv_create_v3_t createSettings;
    createSettings.source_to_connect_to = ndiSource;
    createSettings.color_format = NDIlib_recv_color_format_BGRX_BGRA;
    createSettings.bandwidth = NDIlib_recv_bandwidth_highest;
    createSettings.allow_video_fields = false;
    createSettings.p_ndi_recv_name = "NDICam-iOS";

    _receiver = NDIlib_recv_create_v3(&createSettings);
    if (!_receiver) return NO;

    _running = true;
    __weak NDIReceiverBridge *weakSelf = self;
    dispatch_async(_recvQueue, ^{
        [weakSelf receiveLoop];
    });
    return YES;
}

- (void)receiveLoop {
    NDIlib_video_frame_v2_t videoFrame;
    while (_running.load()) {
        NDIlib_frame_type_e frameType = NDIlib_recv_capture_v3(
            _receiver, &videoFrame, nullptr, nullptr, 500);

        if (!_running.load()) break;

        if (frameType == NDIlib_frame_type_video) {
            CGImageRef image = [self createImageFromVideoFrame:&videoFrame];
            if (image) {
                void (^handler)(CGImageRef) = self.onFrame;
                if (handler) handler(image);
                CGImageRelease(image);
            }
            NDIlib_recv_free_video_v2(_receiver, &videoFrame);
        } else if (frameType == NDIlib_frame_type_error) {
            break;
        }
    }
}

- (CGImageRef)createImageFromVideoFrame:(NDIlib_video_frame_v2_t *)frame {
    if (!frame->p_data || frame->xres <= 0 || frame->yres <= 0) return NULL;

    int width = frame->xres;
    int height = frame->yres;
    int stride = frame->line_stride_in_bytes > 0 ? frame->line_stride_in_bytes : width * 4;
    size_t dataLen = (size_t)stride * (size_t)height;

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    if (!colorSpace) return NULL;

    CGBitmapInfo bitmapInfo;
    if (frame->FourCC == NDIlib_FourCC_video_type_BGRA) {
        bitmapInfo = kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst;
    } else { // BGRX
        bitmapInfo = kCGBitmapByteOrder32Little | kCGImageAlphaNoneSkipFirst;
    }

    NSData *frameData = [NSData dataWithBytes:frame->p_data length:dataLen];
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)frameData);
    CGImageRef image = CGImageCreate(width, height, 8, 32, stride,
                                     colorSpace, bitmapInfo, provider,
                                     NULL, true, kCGRenderingIntentDefault);
    CGDataProviderRelease(provider);
    CGColorSpaceRelease(colorSpace);
    return image;
}

- (void)disconnect {
    _running = false;
    if (_receiver) {
        // 让阻塞中的 capture 超时退出
        NDIlib_recv_destroy(_receiver);
        _receiver = nullptr;
    }
}

- (void)dealloc {
    [self disconnect];
}

@end

#pragma mark - NDIFinderBridge

@implementation NDIFinderBridge {
    NDIlib_find_instance_t _finder;
}

- (BOOL)start {
    if (_finder) return YES;
    if (!NDIlib_initialize()) return NO;

    NDIlib_find_create_t createSettings;
    createSettings.show_local_sources = true;
    createSettings.p_groups = nullptr;
    createSettings.p_extra_ips = nullptr;

    _finder = NDIlib_find_create_v2(&createSettings);
    return _finder != nullptr;
}

- (NSArray<NDISource *> *)currentSources {
    if (!_finder) return @[];

    // 给发现过程留一点等待窗口
    NDIlib_find_wait_for_sources(_finder, 200);

    uint32_t count = 0;
    const NDIlib_source_t *sources = NDIlib_find_get_current_sources(_finder, &count);
    if (!sources || count == 0) return @[];

    NSMutableArray<NDISource *> *result = [NSMutableArray arrayWithCapacity:count];
    for (uint32_t i = 0; i < count; i++) {
        NDISource *s = [[NDISource alloc] init];
        s.name = sources[i].p_ndi_name ? @(sources[i].p_ndi_name) : @"Unknown";
        s.address = sources[i].p_url_address ? @(sources[i].p_url_address) : @"";
        [result addObject:s];
    }
    return result;
}

- (void)stop {
    if (_finder) {
        NDIlib_find_destroy(_finder);
        _finder = nullptr;
    }
}

- (void)dealloc {
    [self stop];
}

@end
