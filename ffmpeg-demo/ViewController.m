//
//  ViewController.m
//  ffmpeg-demo
//
//  Created by yxibng on 2021/1/19.
//

#import "ViewController.h"
#import "RZVideoCapturer.h"
#import "RZVideoEncoder.h"
#import "RZVideoDecoder.h"
#import <mach/mach_time.h>
#import "RZVideoPlayView.h"


#import "RZVideoHwDecoder.h"


static uint64_t rz_milliseconds(void)
{
    static mach_timebase_info_data_t sTimebaseInfo;
    uint64_t machTime = mach_absolute_time();
    
    // Convert to nanoseconds - if this is the first time we've run, get the timebase.
    if (sTimebaseInfo.denom == 0 )
    {
        (void) mach_timebase_info(&sTimebaseInfo);
    }
    // 得到毫秒级别时间差
    uint64_t millis = ((machTime / 1e6) * sTimebaseInfo.numer) / sTimebaseInfo.denom;
    return millis;
}



@interface ViewController()<RZVideoEncoderDelegate, RZVCamDelegate, RZVideoDecoderDelegate>

@property (nonatomic, strong) RZVideoCapturer *videoCapturer;
@property (nonatomic, strong) RZVideoEncoder *videoEncoder;
@property (nonatomic, strong) dispatch_queue_t encodeQueue;

@property (nonatomic, strong) RZVideoDecoder *videoDecoder;

@property (weak) IBOutlet RZVideoPlayView *playView;

@end


@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    _videoCapturer = [[RZVideoCapturer alloc] init];
    
    //默认采集{1280,720}, 15fps
    DbyCapturerConfig config;
    config.dimension = CGSizeMake(1280, 720);
    config.frameRate = 15;
    [_videoCapturer setVideoConfig:config];
    _videoCapturer.delegate = self;
    
    _videoEncoder = [[RZVideoEncoder alloc] initWithDelegate:self];
    _videoDecoder = [[RZVideoDecoder alloc] initWithDelegate:self];
    
    _encodeQueue = dispatch_queue_create("com.video.encode.queue", DISPATCH_QUEUE_SERIAL);
}


- (void)setRepresentedObject:(id)representedObject {
    [super setRepresentedObject:representedObject];

    // Update the view, if already loaded.
}
- (IBAction)start:(id)sender {
    [_videoCapturer start];
    
    
}

- (IBAction)stop:(id)sender {
    [_videoCapturer stop];
}


- (void)videoCapturer:(RZVideoCapturer *)videoCapturer didReceiveSampleBuffer:(CMSampleBufferRef)sampleBuffer isFromFrontCamera:(BOOL)isFromFrontCamera
{
    
    CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    uint64_t timestamp = rz_milliseconds();
    CVPixelBufferRetain(pixelBuffer);
    dispatch_async(self.encodeQueue, ^{
        [self.videoEncoder encodeNv12PixelBuffer:pixelBuffer timestamp:timestamp];
        CVPixelBufferRelease(pixelBuffer);
    });
}

- (void)videoEncoder:(nonnull RZVideoEncoder *)videoEncoder didEncodeH264:(nonnull void *)h264Data dataLength:(int)length isKeyFrame:(BOOL)isKeyFrame timestamp:(NSTimeInterval)timestamp
{
//    NSLog(@"%s, lenght = %d, isKey = %d, timestamp = %f", __FUNCTION__, length, isKeyFrame, timestamp);
    [self.videoDecoder decodeH264:h264Data length:length timestamp:timestamp];
}

- (void)videoDecoder:(RZVideoDecoder *)videoDecoder
  receiveDecodedData:(uint8_t * _Nonnull *)data
           yuvStride:(int *)yuvStride
               width:(int)width
              height:(int)height
          pix_format:(RZYUVType)pix_format
{
    
    if (pix_format == RZYUVTypeI420) {
        
        uint8_t *y =  data[0];
        uint8_t *u =  data[1];
        uint8_t *v =  data[2];
        int stride_y = yuvStride[0];
        int stride_u = yuvStride[1];
        int stride_v = yuvStride[2];
        

        [self.playView displayI420:y
                                 u:u
                                 v:v
                          stride_y:stride_y
                          stride_u:stride_u
                          stride_v:stride_v
                             width:width
                            height:height];
        
        return;
    }
    
    
    if (pix_format == RZYUVTypeNV12) {
        uint8_t *y =  data[0];
        uint8_t *uv =  data[1];
        
        int stride_y = yuvStride[0];
        int stride_uv = yuvStride[1];
        
        [self.playView displayNV12:y
                                uv:uv
                          stride_y:stride_y
                         stride_uv:stride_uv
                             width:width
                            height:height];
        
        return;
    }
    
    
    
    
}

@end
