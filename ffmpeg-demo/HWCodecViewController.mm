//
//  HWCodecViewController.m
//  ffmpeg-demo
//
//  Created by yxibng on 2021/1/25.
//

#import "HWCodecViewController.h"
#import "RZVideoPlayView.h"
#import "RZVideoCapturer.h"
#import "HWEncoder.h"
#import "HWDecoder.h"
#include <string>

@interface HWCodecViewController ()<RZVCamDelegate, HWEncoderDelegate, HWDecoderDelegate>
@property (weak) IBOutlet RZVideoPlayView *playView;
@property (nonatomic, strong) RZVideoCapturer *videoCapturer;

@property (nonatomic, strong) HWEncoder *encoder;
@property (nonatomic, strong) HWDecoder *decoder;

@property (nonatomic, strong) dispatch_queue_t encodeQueue;

@end

@implementation HWCodecViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    _encoder = [[HWEncoder alloc] init];
    _encoder.delegate = self;
    
    _decoder = [[HWDecoder alloc] init];
    _decoder.delegate = self;
    // Do view setup here.
    
    _encodeQueue = dispatch_queue_create("com.video.hw.encode.queue", DISPATCH_QUEUE_SERIAL);

    _videoCapturer = [[RZVideoCapturer alloc] init];
    _videoCapturer.delegate = self;
    
}


- (IBAction)start:(id)sender {
    [_videoCapturer start];
}

- (IBAction)stop:(id)sender {
    [_videoCapturer stop];
}


- (void)videoCapturer:(RZVideoCapturer *)videoCapturer didReceiveSampleBuffer:(CMSampleBufferRef)sampleBuffer isFromFrontCamera:(BOOL)isFromFrontCamera
{
    CFRetain(sampleBuffer);
    dispatch_async(self.encodeQueue, ^{
        [self.encoder encodeSampleBuffer:sampleBuffer];
        CFRelease(sampleBuffer);
    });
}

- (void)hwEncoder:(nonnull HWEncoder *)hwEncoder gotEncodedData:(nonnull NSData *)data isKeyFrame:(BOOL)isKeyFrame {
    
    NSString *split = @"\x00\x00\x00\x01";
    NSData *splitData = [split dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableData *nalu = [NSMutableData dataWithData:splitData];
    [nalu appendData:data];
    
    uint8_t *bytes = (uint8_t *)[nalu bytes];
    uint32_t size = (uint32_t)nalu.length;
    [self writeData:bytes length:size];
    [self.decoder decodeNalu:bytes size:size];
}

- (void)hwEncoder:(nonnull HWEncoder *)hwEncoder gotSps:(nonnull NSData *)sps pps:(nonnull NSData *)pps {
    
    NSString *split = @"\x00\x00\x00\x01";
    NSData *splitData = [split dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableData *spsNalu = [NSMutableData dataWithData:splitData];
    [spsNalu appendData:sps];
    //解码sps
    
    uint8_t *spsBytes = (uint8_t *)[spsNalu bytes];
    uint32_t spsSize = (uint32_t)spsNalu.length;
    [self writeData:spsBytes length:spsSize];

    
    
    NSMutableData *ppsNalu = [NSMutableData dataWithData:splitData];
    [ppsNalu appendData:pps];
    //解码pps
    uint8_t *ppsBytes = (uint8_t *)[ppsNalu bytes];
    uint32_t ppsSize = (uint32_t)ppsNalu.length;
    [self writeData:ppsBytes length:ppsSize];

    //解码sps pps
    [self.decoder decodeSps:spsBytes spsSize:spsSize pps:ppsBytes ppsSize:ppsSize];
}

- (void)hwDecoder:(nonnull HWDecoder *)hwDecoder didDecodeBuffer:(nonnull CVImageBufferRef)buffer {
    CVPixelBufferRetain(buffer);
    [self.playView displayPixelBuffer:buffer];
    CVPixelBufferRelease(buffer);
}


- (void)writeData:(void *)data length:(uint32_t)length {
    static FILE* m_pOutFile = nullptr;
    if (!m_pOutFile) {
        std::string home{std::getenv("HOME")};
        std::string path = home + "/video.h264";
        //删除旧文件
        remove(path.c_str());
        //打开新文件
        m_pOutFile = fopen(path.c_str(), "a+");
        printf("======== h264 file path  = %s\n",path.c_str());
    }
    fwrite(data, 1, length, m_pOutFile);
}



@end
