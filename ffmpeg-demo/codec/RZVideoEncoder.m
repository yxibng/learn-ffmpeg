//
//  RZVideoEncoder.m
//  ffmpeg-demo
//
//  Created by yxibng on 2021/1/19.
//

#import "RZVideoEncoder.h"

#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/avutil.h>
#include <libavutil/imgutils.h>
#include <libavutil/opt.h>
#include <libswscale/swscale.h>



@implementation RZVideoEncodeConfig

- (instancetype)init
{
    self = [super init];
    if (self) {
        //默认编码15帧
        _fps = 15;
    }
    return self;
}

@end


@interface RZVideoEncoder()
{
    AVCodec *_codec;
    AVCodecContext *_context;
    AVFrame *_frame;
    AVPacket *_pkt;
    NSUInteger _pts;
}


@property (nonatomic, assign) BOOL setupSuccess;

@end

@implementation RZVideoEncoder

- (void)dealloc
{
    [self destory];
}


- (instancetype)initWithDelegate:(id<RZVideoEncoderDelegate>)delegate {
    if (self = [super init]) {
        _delegate = delegate;
        _encodeConfig = [RZVideoEncodeConfig new];
    }
    return self;
}

- (void)encodeNv12PixelBuffer:(CVPixelBufferRef)pixelBuffer timestamp:(NSTimeInterval)timestamp {

    if (!pixelBuffer) {
        return;
    }
    
    CVPixelBufferRetain(pixelBuffer);
    
    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    
    
    int width = (int)CVPixelBufferGetWidth(pixelBuffer);
    int height = (int)CVPixelBufferGetHeight(pixelBuffer);
    
    uint8_t *y = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0);
    uint8_t *uv = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1);
    int stride_y = (int)CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0);
    int stride_uv = (int)CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1);
    
    [self encode_y:y
                uv:uv
          stride_y:stride_y
         stride_uv:stride_uv
             width:width
            height:height
         timestamp:timestamp];
    
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
    CVPixelBufferRelease(pixelBuffer);
}


- (void)encode_y:(void *)y
              uv:(void *)uv
        stride_y:(int)stride_y
       stride_uv:(int)stride_uv
           width:(int)width
          height:(int)height
       timestamp:(NSTimeInterval)timestamp
{
    RZVideoEncodeConfig *config = [RZVideoEncodeConfig new];
    config.dimension = CGSizeMake(width, height);
    if (!self.setupSuccess) {
        [self setupWithConfig:config];
    } else {
        BOOL shouldReset = !CGSizeEqualToSize(self.encodeConfig.dimension, CGSizeMake(width, height));
        if (shouldReset) {
            [self destory];
            [self setupWithConfig:config];
        }
    }
    if (!self.setupSuccess) {
        return;
    }
    
    _encodeConfig.dimension = CGSizeMake(width, height);
    
    _frame->width = width;
    _frame->height = height;
    _frame->format = AV_PIX_FMT_NV12;
    _frame->data[0] = y;
    _frame->data[1] = uv;
    _frame->linesize[0] = stride_y;
    _frame->linesize[1] = stride_uv;
    _frame->pts = _pts++;
    
    int ret = avcodec_send_frame(_context, _frame);
    if (ret < 0) {
        return;
    }
    
    while (ret >= 0) {
        ret = avcodec_receive_packet(_context, _pkt);
        if (ret == AVERROR((EAGAIN) || ret == AVERROR_EOF)) {
            return;
        }

        if (ret < 0) {
            return;
        }
        
        if ([self.delegate respondsToSelector:@selector(videoEncoder:didEncodeH264:dataLength:isKeyFrame:timestamp:)]) {
            
            BOOL iskey = _pkt->flags & AV_PKT_FLAG_KEY;
            
            [self.delegate videoEncoder:self
                          didEncodeH264:_pkt->data
                             dataLength:_pkt->size
                             isKeyFrame:iskey
                              timestamp:timestamp];
        }
        
        av_packet_unref(_pkt);
    }
}

- (BOOL)setupWithConfig:(RZVideoEncodeConfig *)config  {
    
    [self destory];
    
    _codec = avcodec_find_encoder(AV_CODEC_ID_H264);
    if (!_codec) {
        return NO;
    }
    
    _context = avcodec_alloc_context3(_codec);
    if (!_context) {
        return NO;
    }
    
    _context->codec_type = AVMEDIA_TYPE_VIDEO;
    _context->pix_fmt = AV_PIX_FMT_NV12;
    
    _context->bit_rate = 400000;
    _context->width = config.dimension.width;
    _context->height = config.dimension.height;
    
    _context->time_base = (AVRational){1, config.fps};
    _context->framerate = (AVRational){config.fps, 1};
    
    _context->gop_size = 10;
    _context->max_b_frames = 1;
    
    av_opt_set(_context->priv_data, "coder", "cabac", 0);
    av_opt_set(_context->priv_data, "x264-params", "ref=1:deblock=1,1:analyse=p8x8:8x8dct=1", 0);
    /*
     ultrafast
     superfast
     veryfast
     faster
     fast
     medium – default preset
     slow
     slower
     veryslow
     placebo – ignore this as it is not useful (see FAQ)
     */
    av_opt_set(_context->priv_data, "preset", "ultrafast", 0);
    
    /*
     tune 通过--tune的参数值指定片子的类型，是和视觉优化的参数，或有特别的情况。
     --tune的值有:
     film：电影、真人类型；
     animation：动画；
     grain：需要保留大量的grain时用；
     stillimage：静态图像编码时使用；
     psnr：为提高psnr做了优化的参数；
     ssim：为提高ssim做了优化的参数；
     fastdecode：可以快速解码的参数；
     zerolatency：零延迟，用在需要非常低的延迟的情况下，比如电视电话会议的编码。
     */
    av_opt_set(_context->priv_data, "tune", "zerolatency", 0);
    
    /*
     H.264有四种画质级别,分别是baseline, extended, main, high：
     　　1、Baseline Profile：基本画质。支持I/P 帧，只支持无交错（Progressive）和CAVLC；
     　　2、Extended profile：进阶画质。支持I/P/B/SP/SI 帧，只支持无交错（Progressive）和CAVLC；(用的少)
     　　3、Main profile：主流画质。提供I/P/B 帧，支持无交错（Progressive）和交错（Interlaced），
     　　　 也支持CAVLC 和CABAC 的支持；
     　　4、High profile：高级画质。在main Profile 的基础上增加了8x8内部预测、自定义量化、 无损视频编码和更多的YUV 格式；
     H.264 Baseline profile、Extended profile和Main profile都是针对8位样本数据、4:2:0格式(YUV)的视频序列。在相同配置情况下，High profile（HP）可以比Main profile（MP）降低10%的码率。
     */
    av_opt_set(_context->priv_data, "profile", "high", 0);

    /*
     open it
     */
    avcodec_open2(_context, _codec, NULL);
    
    _pkt = av_packet_alloc();
    if (!_pkt) {
        return NO;
    }
        
    _frame = av_frame_alloc();
    if (!_frame) {
        return NO;
    }
    _pts = 1;
    _setupSuccess = YES;
    return YES;
}

- (void)destory {
    if (_context) {
        avcodec_close(_context);
        avcodec_free_context(&_context);
    }
    if (_frame) {
        av_frame_free(&_frame);
    }
    if (_pkt) {
        av_packet_free(&_pkt);
    }
    _setupSuccess = NO;
}



@end
