//
//  RZVideoHwDecoder.m
//  ffmpeg-demo
//
//  Created by yxibng on 2021/1/20.
//

#import "RZVideoHwDecoder.h"
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/avutil.h>
#include <libavutil/imgutils.h>
#include <libavutil/opt.h>
#include <libswscale/swscale.h>

@interface RZVideoHwDecoder()
{
@public
    AVCodecContext *_context;
    AVCodec *_decoder;
    enum AVHWDeviceType _type;
    enum AVPixelFormat _hw_pix_fmt;
    AVBufferRef *_hw_device_ctx;
}

@property (nonatomic, assign) BOOL setupSuccess;


@end


@implementation RZVideoHwDecoder

- (void)dealloc
{
    [self destroy];
}

- (instancetype)initWithDelegate:(id<RZVideoHwDecoderDelegate>)delegate
{
    self = [super init];
    if (self) {
        _delegate = delegate;
        [self setup];
    }
    return self;
}



- (BOOL)setup {
    
    [self destroy];
    
    _decoder = avcodec_find_decoder(AV_CODEC_ID_H264);
    if (!_decoder) {
        return NO;
    }
    
    _type = av_hwdevice_find_type_by_name("videotoolbox");
    if (_type == AV_HWDEVICE_TYPE_NONE) {
        return NO;
    }
    
    for (int i =0; ; i++) {
        const AVCodecHWConfig *config = avcodec_get_hw_config(_decoder, i);
        if (config->methods & AV_CODEC_HW_CONFIG_METHOD_HW_DEVICE_CTX &&
            config->device_type == _type) {
            _hw_pix_fmt = config->pix_fmt;
            break;
        }
    }
    
    _context = avcodec_alloc_context3(_decoder);
    _context->opaque = (__bridge void *)self;
    _context->get_format = get_hw_format;
    
    //init hw decode context
    int ret = hw_decoder_init(_context, _type);
    if (ret < 0) {
        return NO;
    }
    
    //open it
    ret = avcodec_open2(_context, _decoder, NULL);
    if (ret < 0) {
        return NO;
    }
    _setupSuccess = YES;
    return YES;
}


- (void)destroy {
    
    if (_context) {
        avcodec_free_context(&_context);
        _context = NULL;
    }
    
    if (_hw_device_ctx) {
        av_buffer_unref(&_hw_device_ctx);
        _hw_device_ctx = NULL;
    }
    _setupSuccess = NO;
}

- (void)decodeH264:(void *)packet length:(int)length timestamp:(NSTimeInterval)timestamp {
    
    if (!self.setupSuccess) {
        BOOL ret = [self setup];
        if (!ret) {
            return;
        }
    }

    AVPacket *pkt = av_packet_alloc();
    av_init_packet(pkt);
    pkt->data = packet;
    pkt->size = length;
    
    //do decode
    decode(_context, pkt);
    
    av_packet_free(&pkt);
}



static enum AVPixelFormat get_hw_format(AVCodecContext *ctx,
                                        const enum AVPixelFormat *pix_fmts)
{
    /*
     //TOOD:可以直接解出来yuv420p
     return  AV_PIX_FMT_YUV420P;
     */
    RZVideoHwDecoder *decoder = (__bridge RZVideoHwDecoder *)ctx->opaque;
    const enum AVPixelFormat *p;
    for (p = pix_fmts; *p != -1; p++) {
        if (*p == decoder->_hw_pix_fmt)
            return *p;
    }
    fprintf(stderr, "Failed to get HW surface format.\n");
    return AV_PIX_FMT_NONE;
}

static int hw_decoder_init(AVCodecContext *ctx, const enum AVHWDeviceType type)
{
    int err = 0;

    RZVideoHwDecoder *decoder = (__bridge RZVideoHwDecoder *)ctx->opaque;
    if ((err = av_hwdevice_ctx_create(&decoder->_hw_device_ctx, type,
                                      NULL, NULL, 0)) < 0) {
        fprintf(stderr, "Failed to create specified HW device.\n");
        return err;
    }
    ctx->hw_device_ctx = av_buffer_ref(decoder->_hw_device_ctx);
    return err;
}

static int decode(AVCodecContext *avctx, AVPacket *packet) {
    
    AVFrame *frame = NULL, *sw_frame = NULL;
    AVFrame *tmp_frame = NULL;
    uint8_t *buffer = NULL;
    int ret = 0;

    RZVideoHwDecoder *decoder = (__bridge RZVideoHwDecoder *)avctx->opaque;
    
    ret = avcodec_send_packet(avctx, packet);
    if (ret < 0) {
        fprintf(stderr, "Error during decoding\n");
        return ret;
    }

    while (1) {
        if (!(frame = av_frame_alloc()) || !(sw_frame = av_frame_alloc())) {
            fprintf(stderr, "Can not alloc frame\n");
            ret = AVERROR(ENOMEM);
            goto fail;
        }

        ret = avcodec_receive_frame(avctx, frame);
        if (ret == AVERROR(EAGAIN) || ret == AVERROR_EOF) {
            av_frame_free(&frame);
            av_frame_free(&sw_frame);
            return 0;
        } else if (ret < 0) {
            fprintf(stderr, "Error while decoding\n");
            goto fail;
        }

        if (frame->format == decoder->_hw_pix_fmt) {
            /* retrieve data from GPU to CPU */
            if ((ret = av_hwframe_transfer_data(sw_frame, frame, 0)) < 0) {
                fprintf(stderr, "Error transferring the data to system memory\n");
                goto fail;
            }
            tmp_frame = sw_frame;
        } else {
            tmp_frame = frame;
        }

        //got frame
        
        int width = tmp_frame->width;
        int height = tmp_frame->height;
        
        if ([decoder.delegate respondsToSelector:@selector(videoHwDecoder:receiveDecodedData:yuvStride:width:height:pix_format:)]) {
            
            if (tmp_frame->format == AV_PIX_FMT_NV12) {
                
                [decoder.delegate videoHwDecoder:decoder
                         receiveDecodedData:tmp_frame->data
                                  yuvStride:tmp_frame->linesize
                                      width:width
                                     height:height
                                 pix_format:RZYUVTypeNV12];
                
            } else if (tmp_frame->format == AV_PIX_FMT_YUV420P) {
                [decoder.delegate videoHwDecoder:decoder
                         receiveDecodedData:tmp_frame->data
                                  yuvStride:tmp_frame->linesize
                                      width:width
                                     height:height
                                 pix_format:RZYUVTypeI420];
            } else {
                //not support
            }
        }
        
    fail:
        av_frame_free(&frame);
        av_frame_free(&sw_frame);
        av_freep(&buffer);
        if (ret < 0)
            return ret;
    }
    
    return 0;
}

@end
