//
//  HWDecoder.h
//  ffmpeg-demo
//
//  Created by yxibng on 2021/1/23.
//

#import <Foundation/Foundation.h>
#import <VideoToolbox/VideoToolbox.h>

NS_ASSUME_NONNULL_BEGIN

@class HWDecoder;
@protocol HWDecoderDelegate <NSObject>

- (void)hwDecoder:(HWDecoder *)hwDecoder didDecodeBuffer:(CVImageBufferRef)buffer;

@end

@interface HWDecoder : NSObject

@property (nonatomic, weak) id<HWDecoderDelegate>delegate;


- (BOOL)initH264Decoder;

- (void)decodeNalu:(uint8_t *)frame size:(uint32_t)size;

- (void)endDecoding;

@end

NS_ASSUME_NONNULL_END
