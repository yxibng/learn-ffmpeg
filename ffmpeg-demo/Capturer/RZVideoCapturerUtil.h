//
//  DbyVideoUtil.h
//  DbyPaas_iOS
//
//  Created by yxibng on 2020/1/14.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN


@interface RZCamVideoFormat : NSObject

@property (nonatomic, assign) int fps;
@property (nonatomic, strong) AVFrameRateRange *frameRateRange;
@property (nonatomic, assign) CGSize dimension;
@property (nonatomic, assign) FourCharCode format;

@end


@interface RZVideoCapturerUtil : NSObject

//video capture device with specified positon
+ (AVCaptureDevice *)videoCaptureDeviceWithPosition:(AVCaptureDevicePosition)position;
//all video capture devices
+ (NSArray<AVCaptureDevice *> *)videoCaptureDevices;
//search for AVCaptureDevice with uniqueID
+ (AVCaptureDevice *)videoCaptureDeviceWithID:(NSString *)uniqueID;

+ (void)setCaptureFrameRate:(NSInteger)frameRate
                    dstSize:(CGSize)size
                  forDevice:(AVCaptureDevice *)device
            resultFrameRate:(NSInteger *)resultFrameRate;


@end


@interface RZVideoDropFrameManager : NSObject
//default 30
@property (nonatomic, assign) NSInteger sourceFps;
//default 15
@property (nonatomic, assign) NSInteger targetFps;

@property (nonatomic, strong) NSSet *set; //采用的帧的集合 set

- (BOOL)shoudDropBySequeceNumber:(UInt64)sequeceNumber;

@end

NS_ASSUME_NONNULL_END
