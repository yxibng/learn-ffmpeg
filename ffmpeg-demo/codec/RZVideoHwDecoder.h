//
//  RZVideoHwDecoder.h
//  ffmpeg-demo
//
//  Created by yxibng on 2021/1/20.
//

#import <Foundation/Foundation.h>
#import "RZCodec.h"

NS_ASSUME_NONNULL_BEGIN

@class RZVideoHwDecoder;
@protocol RZVideoHwDecoderDelegate <NSObject>

- (void)videoHwDecoder:(RZVideoHwDecoder *)videoDecoder
  receiveDecodedData:(uint8_t *_Nonnull*_Nonnull)data
           yuvStride:(int *)yuvStride
               width:(int)width
              height:(int)height
          pix_format:(RZYUVType)pix_format;

@end

@interface RZVideoHwDecoder : NSObject


@property (nonatomic, weak) id<RZVideoHwDecoderDelegate>delegate;

- (instancetype)initWithDelegate:(id<RZVideoHwDecoderDelegate>)delegate;

- (void)decodeH264:(void *)packet length:(int)length timestamp:(NSTimeInterval)timestamp;
@end

NS_ASSUME_NONNULL_END
