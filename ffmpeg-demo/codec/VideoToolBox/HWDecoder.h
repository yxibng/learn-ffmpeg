//
//  HWDecoder.h
//  ffmpeg-demo
//
//  Created by yxibng on 2021/1/23.
//

#import <Foundation/Foundation.h>
#import <VideoToolbox/VideoToolbox.h>

/*
 参考：
 https://stackoverflow.com/questions/29525000/how-to-use-videotoolbox-to-decompress-h-264-video-stream
 */


NS_ASSUME_NONNULL_BEGIN

@class HWDecoder;
@protocol HWDecoderDelegate <NSObject>

- (void)hwDecoder:(HWDecoder *)hwDecoder didDecodeBuffer:(CVImageBufferRef)buffer;

@end

@interface HWDecoder : NSObject

@property (nonatomic, weak) id<HWDecoderDelegate>delegate;


- (BOOL)initH264Decoder;


/*
 收到sps， pps 之后，要判断是否需要重置解码器
 
 数据格式要求：
 sps = startcode(0x00 00 00 01) + sps nalu
 pps = startcode(0x00 00 00 01) + pps nalu
 */
- (void)decodeSps:(uint8_t *)sps spsSize:(uint32_t)spsSize
              pps:(uint8_t *)pps ppsSize:(uint32_t)ppsSize;
/*
 解码nalu，不包括sps，pps
 */
- (void)decodeNalu:(uint8_t *)frame size:(uint32_t)size;

- (void)endDecoding;

@end

NS_ASSUME_NONNULL_END
