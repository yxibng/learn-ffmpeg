//
//  DbyVideoDisplayView.m
//  DbyPaas_iOS
//
//  Created by yxibng on 2019/10/16.
//

#import "RZVideoPlayView.h"
#import "libyuv.h"

static int NV12Copy(uint8_t *src_y, int src_stride_y,
                    uint8_t *src_uv, int src_stride_uv,
                    uint8_t *dst_y, int dst_stride_y,
                    uint8_t *dst_uv, int dst_stride_uv,
                    int width, int height) {
    
    void *middle_u = malloc(width * height * 0.25 + 10);
    void *middle_v = malloc(width * height * 0.25 + 10);
    int middle_stride_u = width / 2;
    int middle_stride_v = width / 2;
    SplitUVPlane(src_uv, src_stride_uv, middle_u, middle_stride_u, middle_v, middle_stride_v, width, height);
    CopyPlane(src_y, src_stride_y, dst_y, dst_stride_y, width, height);
    MergeUVPlane(middle_u, middle_stride_u,
                 middle_v, middle_stride_u,
                 dst_uv, dst_stride_uv, width, height);
    free(middle_u);
    free(middle_v);
    return 0;
}



@interface RZVideoPlayView ()
@property (nonatomic, strong) AVSampleBufferDisplayLayer *displayLayer;

@end


@implementation RZVideoPlayView

- (void)dealloc
{
    
}


#if TARGET_OS_IOS

+ (Class)layerClass
{
    return [AVSampleBufferDisplayLayer class];
}

#elif TARGET_OS_OSX

- (instancetype)initWithFrame:(NSRect)frameRect
{
    if (self = [super initWithFrame:frameRect]) {
        [self setup];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    if (self = [super initWithCoder:coder]) {
        [self setup];
    }
    return self;
}

- (void)setup
{
    self.wantsLayer = true;
    self.layer = [[AVSampleBufferDisplayLayer alloc] init];
}
#endif

- (AVSampleBufferDisplayLayer *)displayLayer
{
    return (AVSampleBufferDisplayLayer *)self.layer;
}

- (void)setGravity:(AVLayerVideoGravity)gravity
{
    if ([NSThread isMainThread]) {
        self.displayLayer.videoGravity = gravity;
        //通过改变bounds， 触发gravity 生效
        CGRect bounds = self.displayLayer.bounds;
        self.displayLayer.bounds = CGRectZero;
        self.displayLayer.bounds = bounds;
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.displayLayer.videoGravity = gravity;
            //通过改变bounds， 触发gravity 生效
            CGRect bounds = self.displayLayer.bounds;
            self.displayLayer.bounds = CGRectZero;
            self.displayLayer.bounds = bounds;
        });
    }
}

- (void)setCanvas:(VIEW_CLASS *)canvas
{
    _canvas = canvas;
    if ([NSThread isMainThread]) {
        [self addToSuperView:canvas];
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self addToSuperView:canvas];
        });
    }
}


- (void)addToSuperView:(VIEW_CLASS *)view
{
    [self removeFromSuperview];
    if (!view) {
        return;
    }

    [view addSubview:self];
    self.frame = view.bounds;

#if TARGET_OS_IOS
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
#elif TARGET_OS_OSX
    self.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
#endif
}



- (void)renderPixelBuffer:(CVPixelBufferRef)pixelBuffer
{
    [self displayPixelBuffer:pixelBuffer];
}

#pragma mark -

- (void)displayPixelBuffer:(CVPixelBufferRef)pixelBuffer
{
    if (!pixelBuffer) {
        return;
    }
    
    CVPixelBufferRetain(pixelBuffer);
    CMSampleBufferRef sampleBuffer = [self createSampleBufferWithPixelBuffer:pixelBuffer];
    CVPixelBufferRelease(pixelBuffer);

    if (!sampleBuffer) {
        return;
    }

    [self displaySampleBuffer:sampleBuffer];
    CFRelease(sampleBuffer);
}

- (CMSampleBufferRef)createSampleBufferWithPixelBuffer:(CVPixelBufferRef)pixelBuffer
{
    if (!pixelBuffer) {
        return NULL;
    }

    //不设置具体时间信息
    CMSampleTimingInfo timing = {kCMTimeInvalid, kCMTimeInvalid, kCMTimeInvalid};
    //获取视频信息
    CMVideoFormatDescriptionRef videoInfo = NULL;
    OSStatus result = CMVideoFormatDescriptionCreateForImageBuffer(NULL, pixelBuffer, &videoInfo);
    NSParameterAssert(result == 0 && videoInfo != NULL);
    if (result != 0) {
        return NULL;
    }

    CMSampleBufferRef sampleBuffer = NULL;
    result = CMSampleBufferCreateForImageBuffer(kCFAllocatorDefault, pixelBuffer, true, NULL, NULL, videoInfo, &timing, &sampleBuffer);
    NSParameterAssert(result == 0 && sampleBuffer != NULL);
    CFRelease(videoInfo);
    if (result != 0) {
        return NULL;
    }
    CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, YES);
    CFMutableDictionaryRef dict = (CFMutableDictionaryRef)CFArrayGetValueAtIndex(attachments, 0);
    CFDictionarySetValue(dict, kCMSampleAttachmentKey_DisplayImmediately, kCFBooleanTrue);

    return sampleBuffer;
}

- (void)displaySampleBuffer:(CMSampleBufferRef)sampleBuffer
{
    if (sampleBuffer == NULL) {
        return;
    }
    CFRetain(sampleBuffer);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.displayLayer.status == AVQueuedSampleBufferRenderingStatusFailed) {
            [self.displayLayer flush];
        }
        if (!self.window) {
            //如果当前视图不再window上，就不要显示了
            CFRelease(sampleBuffer);
            return;
        }
        
#if TARGET_OS_IOS
        //后台不渲染了
        BOOL applicationActive = [UIApplication sharedApplication].applicationState == UIApplicationStateActive ? YES : NO;
        if (!applicationActive) {
            CFRelease(sampleBuffer);
            return;
        }
#endif
        if (self.displayLayer.status == AVQueuedSampleBufferRenderingStatusFailed) {
            //此时无法将sampleBuffer加入队列，强行往队列里面添加，会造成崩溃
            CFRelease(sampleBuffer);
            return;
        }

        [self.displayLayer enqueueSampleBuffer:sampleBuffer];
        CFRelease(sampleBuffer);
    });
}


- (void)displayI420:(void *)i420 frameWidth:(int)width frameHeight:(int)height {
    
    if (!i420) {
        return;
    }
    
    
    CVPixelBufferRef pixelBuffer;
    NSDictionary *att = @{(NSString *)kCVPixelBufferIOSurfacePropertiesKey : @{}};
    CVReturn ret =  CVPixelBufferCreate(NULL, width, height, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,   (__bridge CFDictionaryRef _Nullable)att, &pixelBuffer);
    if (ret != kCVReturnSuccess) {
        return;
    }
    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    
    uint8_t *src_y = i420;
    uint8_t *src_u = src_y + width * height;
    uint8_t *src_v = src_u + width * height / 4;
    
    int src_stride_y = width;
    int src_stride_u = width / 2;
    int src_stride_v = width / 2;

    
    uint8_t *dst_y = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0);
    uint8_t *dst_uv = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1);
    
    
    int dst_stride_y = (int)CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0);
    int dst_stride_uv = (int)CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1);
    
    
    ret = I420ToNV12(src_y, src_stride_y,
                     src_u, src_stride_u,
                     src_v, src_stride_v,
                     dst_y, dst_stride_y,
                     dst_uv, dst_stride_uv, width, height);
    assert(ret == 0);
    
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
    
    [self displayPixelBuffer:pixelBuffer];
    CVPixelBufferRelease(pixelBuffer);

    
    
    
}


- (void)displayNV12:(void *)nv12 frameWidth:(int)width frameHeight:(int)height {
    
    if (!nv12) {
        return;
    }
    
    CVPixelBufferRef pixelBuffer;
    CVReturn ret =  CVPixelBufferCreate(NULL, width, height, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, nil, &pixelBuffer);
    if (ret != kCVReturnSuccess) {
        return;
    }
    
    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    
    uint8_t *src_y = nv12;
    uint8_t *src_uv = src_y + width * height;

    int src_stride_y = width;
    int src_stride_uv = width;
    
    uint8_t *dst_y = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0);
    uint8_t *dst_uv = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1);
    
    int dst_stride_y = (int)CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0);
    int dst_stride_uv = (int)CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1);
    
    NV12Copy(src_y, src_stride_y,
             src_uv, src_stride_uv,
             dst_y, dst_stride_y,
             dst_uv, dst_stride_uv,
             width, height);

    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
    [self displayPixelBuffer:pixelBuffer];
    CVPixelBufferRelease(pixelBuffer);
}



- (void)displayI420:(void *)y
                  u:(void *)u
                  v:(void *)v
           stride_y:(int)stride_y
           stride_u:(int)stride_u
           stride_v:(int)stride_v
              width:(int)width
             height:(int)height
{
    
    if (!y || !u || !v) {
        return;
    }
    
    CVPixelBufferRef pixelBuffer;
    NSDictionary *att = @{(NSString *)kCVPixelBufferIOSurfacePropertiesKey : @{}};
    CVReturn ret =  CVPixelBufferCreate(NULL, width, height, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,   (__bridge CFDictionaryRef _Nullable)att, &pixelBuffer);
    if (ret != kCVReturnSuccess) {
        return;
    }
    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    
    uint8_t *src_y = y;
    uint8_t *src_u = u;
    uint8_t *src_v = v;
    
    int src_stride_y = stride_y;
    int src_stride_u = stride_u;
    int src_stride_v = stride_v;

    
    uint8_t *dst_y = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0);
    uint8_t *dst_uv = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1);
    
    
    int dst_stride_y = (int)CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0);
    int dst_stride_uv = (int)CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1);
    
    
    ret = I420ToNV12(src_y, src_stride_y,
                     src_u, src_stride_u,
                     src_v, src_stride_v,
                     dst_y, dst_stride_y,
                     dst_uv, dst_stride_uv, width, height);
    assert(ret == 0);
    
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
    
    [self displayPixelBuffer:pixelBuffer];
    CVPixelBufferRelease(pixelBuffer);
    
}


@end
