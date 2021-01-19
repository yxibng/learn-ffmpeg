//
//  RZVideoDecoder.h
//  ffmpeg-demo
//
//  Created by yxibng on 2021/1/19.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN


#define kYUVElementMaxCount 8

typedef enum : NSUInteger {
    RZYUVTypeNV12,//2 平面
    RZYUVTypeI420,//3 平面
} RZYUVType;

@class RZVideoDecoder;
@protocol RZVideoDecoderDelegate <NSObject>

- (void)videoDecoder:(RZVideoDecoder *)videoDecoder
  receiveDecodedData:(uint8_t *_Nonnull*_Nonnull)data
           yuvStride:(int *)yuvStride
               width:(int)width
              height:(int)height
          pix_format:(RZYUVType)pix_format;

@end


@interface RZVideoDecoder : NSObject


@property (nonatomic, weak) id<RZVideoDecoderDelegate>delegate;

- (instancetype)initWithDelegate:(id<RZVideoDecoderDelegate>)delegate;

- (void)decodeH264:(void *)packet length:(int)length timestamp:(NSTimeInterval)timestamp;

@end

NS_ASSUME_NONNULL_END
