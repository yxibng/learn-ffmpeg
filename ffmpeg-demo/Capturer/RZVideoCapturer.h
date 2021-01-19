//
//  DbyCameraCapturer.h
//  DbyPaas_iOS
//
//  Created by yxibng on 2020/7/7.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, RZVCamStartReason) {
    //用户触发点击了开始
    RZVCamStartReasonUserTrigger,
    //采集被打断后恢复运行
    RZVCamStartReasonSystemInterruptEnd,
};

typedef NS_ENUM(NSUInteger, RZVCamStopReason) {
    //用户点击了stop
    RZVCamStopReasonUserTrigger,
    //没有采集权限，停止采集
    RZVCamStopReasonNoPermission,
    //配置内部的采集 session 的时候，出错了，停止采集
    RZVCamStopReasonSetupError,
    //由于别的采集session打断，停止当前的采集
    RZVCamStopReasonSystemInterrupt,
    //运行期间错误
    RZVCamStopReasonSystemError,
};


typedef NS_ENUM(NSUInteger, RZVCamSource) {
    RZVCamSourceCamera,
    RZVCamSourceScreen,
    RZVCamSourceWindow
};

typedef struct  {
    CGSize dimension;
    int frameRate;
} DbyCapturerConfig;


@class RZVideoCapturer;
@protocol RZVCamDelegate <NSObject>
@optional
//开始,内部成功开始采集
- (void)videoCapturer:(RZVideoCapturer *)videoCapturer didStartWithReason:(RZVCamStartReason)reason;
//停止采集了
- (void)videoCapturer:(RZVideoCapturer *)videoCapturer didStopWithReason:(RZVCamStopReason)reason;
//获取到了数据
- (void)videoCapturer:(RZVideoCapturer *)videoCapturer didReceiveSampleBuffer:(CMSampleBufferRef)sampleBuffer isFromFrontCamera:(BOOL)isFromFrontCamera;
@end

@interface RZVideoCapturer : NSObject

@property (nonatomic, weak) id<RZVCamDelegate> delegate;

//是否正在运行
@property (nonatomic, assign, readonly) BOOL isRunning;

/* 当前的采集设备 */
@property (nonatomic, strong, readonly) AVCaptureDevice *currentDevice;
/**
 编码的分辨率和帧率，以及方向，镜像模式等等。 采集端只关心分辨率和帧率。
 采集端可以参考编码的参数，尽可能的采集和编码一致的数据。
 默认的编码分辨率为640*360，相机可能采集不到这个分辨率，就采集最接近的一个分辨率，然后编码之前做一下缩放。
 默认编码的帧率为15，macOS 采集的最低帧率为30帧，采集端需要处理一下丢帧。（这个实际可以直接放给编码器，编码器会做帧率的控制。）
 */

@property (nonatomic, assign) DbyCapturerConfig videoConfig;


#if TARGET_OS_IOS
/**
 iOS，默认使用前置摄像头，通过此接口切换前后置摄像头。
 */
- (void)swapFrontAndBackCameras;
#endif

#if TARGET_OS_OSX
/*
 macOS 可能存在多个视频输入设备，可以在多个采集设备之间做切换。
 通过此接口，可以设置当前使用哪个设备作为输入设备。
 */
- (void)setCurrentInputDevice:(AVCaptureDevice *)currentInputDevice;
#endif
/**
 开启采集
 */
- (int)start;
/**
 停止采集
 */
- (int)stop;

@end

NS_ASSUME_NONNULL_END
