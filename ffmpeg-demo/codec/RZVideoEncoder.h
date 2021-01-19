//
//  RZVideoEncoder.h
//  ffmpeg-demo
//
//  Created by yxibng on 2021/1/19.
//

#import <Foundation/Foundation.h>
#import <VideoToolbox/VideoToolbox.h>

NS_ASSUME_NONNULL_BEGIN


@class RZVideoEncoder;


@interface RZVideoEncodeConfig : NSObject

//default 15
@property (nonatomic, assign) int fps;

//defaut is captured size
@property (nonatomic, assign) CGSize dimension;


@end


@protocol RZVideoEncoderDelegate <NSObject>

- (void)videoEncoder:(RZVideoEncoder *)videoEncoder
       didEncodeH264:(void *)h264Data
          dataLength:(int)length
          isKeyFrame:(BOOL)isKeyFrame
           timestamp:(NSTimeInterval)timestamp;

@end


@interface RZVideoEncoder : NSObject

@property (nonatomic, weak) id<RZVideoEncoderDelegate>delegate;


@property (strong ,nonatomic, readonly) RZVideoEncodeConfig *encodeConfig;

- (instancetype)initWithDelegate:(id<RZVideoEncoderDelegate>)delegate;
- (void)encodeNv12PixelBuffer:(CVPixelBufferRef)pixelBuffer timestamp:(NSTimeInterval)timestamp;

@end

NS_ASSUME_NONNULL_END
