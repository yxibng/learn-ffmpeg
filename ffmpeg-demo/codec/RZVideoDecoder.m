//
//  RZVideoDecoder.m
//  ffmpeg-demo
//
//  Created by yxibng on 2021/1/19.
//

#import "RZVideoDecoder.h"
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/avutil.h>
#include <libavutil/imgutils.h>
#include <libavutil/opt.h>
#include <libswscale/swscale.h>


@interface RZVideoDecoder ()
{
    AVCodec *_codec;
    AVCodecContext *_context;
    AVCodecParserContext *_parser;
    AVFrame *_frame;
    AVPacket *_pkt;
}

@property (nonatomic, assign) BOOL setupSuccess;


@end

@implementation RZVideoDecoder


- (void)dealloc
{
    [self destroy];
}


- (instancetype)initWithDelegate:(id<RZVideoDecoderDelegate>)delegate
{
    self = [super init];
    if (self) {
        _delegate = delegate;
    }
    return self;
}

- (void)decodeH264:(void *)packet length:(int)length timestamp:(NSTimeInterval)timestamp {
    
    if (!packet) {
        return;
    }
    
    if (!self.setupSuccess) {
        BOOL ret = [self setup];
        if (!ret) {
            NSLog(@"setup failed");
            return;
        }
    }
    
    int buf_size = length;
    uint8_t *buffer = (uint8_t *)packet;
    
    while (buf_size > 0) {
        int bytes_used = av_parser_parse2(_parser, _context, &_pkt->data, &_pkt->size, buffer, buf_size, 0, 0, AV_NOPTS_VALUE);
        if (bytes_used < 0) {
            fprintf(stderr, "Error while parsing\n");
            return;
        }
        buffer += bytes_used;
        buf_size -= bytes_used;
        if (_pkt->size) {
            [self decodePacket:_pkt];
        }
    }
}


- (void)decodePacket:(AVPacket *)packet {
    
    if (!packet) {
        return;
    }
    
    
    int ret = avcodec_send_packet(_context, packet);
    if (ret < 0) {
        return;
    }
    
    while (1) {
        
        ret = avcodec_receive_frame(_context, _frame);
        if (ret == AVERROR(EAGAIN) || ret == AVERROR_EOF) {
            return;
        }
        
        if (ret < 0) {
            return;
        }
        //got frame
        
        int width = _frame->width;
        int height = _frame->height;
        
        if ([self.delegate respondsToSelector:@selector(videoDecoder:receiveDecodedData:yuvStride:width:height:pix_format:)]) {
            
            if (_frame->format == AV_PIX_FMT_NV12) {
                
                [self.delegate videoDecoder:self
                         receiveDecodedData:_frame->data
                                  yuvStride:_frame->linesize
                                      width:width
                                     height:height
                                 pix_format:RZYUVTypeNV12];
                
            } else if (_frame->format == AV_PIX_FMT_YUV420P) {
                [self.delegate videoDecoder:self
                         receiveDecodedData:_frame->data
                                  yuvStride:_frame->linesize
                                      width:width
                                     height:height
                                 pix_format:RZYUVTypeI420];
            } else {
                //not support
            }
            
            

        }
        
        
    }
}


- (BOOL)setup {
    
    [self destroy];
    
    _codec = avcodec_find_decoder(AV_CODEC_ID_H264);
    if (!_codec) {
        return NO;
    }
    
    _parser = av_parser_init(AV_CODEC_ID_H264);
    if (!_parser) {
        return NO;
    }
    
    _context = avcodec_alloc_context3(_codec);
    if (!_context) {
        return NO;
    }
    _context->codec_type = AVMEDIA_TYPE_VIDEO;
    
    int ret = avcodec_open2(_context, _codec, NULL);
    if (ret < 0) {
        return NO;
    }
    
    _frame = av_frame_alloc();
    if (!_frame) {
        return NO;
    }
    
    _pkt = av_packet_alloc();
    if (!_pkt) {
        return NO;
    }
    
    _setupSuccess = YES;
    return YES;
}

- (void)destroy {
    if (_parser) {
        av_parser_close(_parser);
    }
    
    if (_context) {
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
