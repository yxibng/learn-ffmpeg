//
//  HWEncoder.h
//  ffmpeg-demo
//
//  Created by yxibng on 2021/1/23.
//

#import <Foundation/Foundation.h>
#import <VideoToolbox/VideoToolbox.h>

NS_ASSUME_NONNULL_BEGIN
@class HWEncoder;
@protocol HWEncoderDelegate <NSObject>

- (void)hwEncoder:(HWEncoder *)hwEncoder gotSps:(NSData *)sps pps:(NSData *)pps;
- (void)hwEncoder:(HWEncoder *)hwEncoder gotEncodedData:(NSData *)data isKeyFrame:(BOOL)isKeyFrame;

@end


@interface HWEncoder : NSObject


@property (nonatomic, weak) id<HWEncoderDelegate>delegate;

- (BOOL)setupEncoderWithSize:(CGSize)size frameRate:(int)frameRate;


- (void)encodeSampleBuffer:(CMSampleBufferRef)sampleBuffer;

- (void)stopEncoding;

@end

NS_ASSUME_NONNULL_END
