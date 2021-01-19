//
//  DbyCameraCapturer.m
//  DbyPaas_iOS
//
//  Created by yxibng on 2020/7/7.
//

#import "RZVideoCapturer.h"
#import "RZVideoCapturerUtil.h"
#if TARGET_OS_OSX
#import <CoreMediaIO/CMIOSampleBuffer.h>
#endif

#if TARGET_OS_IOS
#import<UIKit/UIKit.h>
#endif



typedef NS_ENUM(NSInteger, AVCamSetupResult) {
    AVCamSetupResultSuccess,
    AVCamSetupResultCameraNotAuthorized,
    AVCamSetupResultSessionConfigurationFailed
};

@interface RZVideoCapturer () <AVCaptureVideoDataOutputSampleBufferDelegate>

@property (nonatomic) AVCamSetupResult setupResult;
@property (nonatomic, strong) AVCaptureSession *session;
@property (nonatomic, strong) AVCaptureVideoDataOutput *videoOutput;
@property (nonatomic, strong) AVCaptureDevice *currentDevice;
@property (strong, nonatomic) AVCaptureDeviceInput *videoInput;
@property (nonatomic, assign) AVCaptureVideoOrientation captureVideoOrientation;
@property (nonatomic) dispatch_queue_t sessionQueue;
@property (nonatomic) dispatch_queue_t sampleBufferCallbackQueue;
@property (nonatomic) dispatch_semaphore_t semaphore;

@property (nonatomic, strong) RZVideoDropFrameManager *dropFrameManager;

@end


@implementation RZVideoCapturer

- (void)dealloc
{
    NSLog(@"%s", __FUNCTION__);
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (instancetype)init
{
    if (self = [super init]) {
        _semaphore = dispatch_semaphore_create(0);

        _setupResult = AVCamSetupResultSuccess;

        _sessionQueue = dispatch_queue_create("dby.videoRecorder.session.config.queue", DISPATCH_QUEUE_SERIAL);
        _sampleBufferCallbackQueue = dispatch_queue_create("dby.videoRecorder.session.sampleBufferCallback.queue", DISPATCH_QUEUE_SERIAL);

        _session = [[AVCaptureSession alloc] init];

        //设置采集参数默认值
        _videoConfig = (DbyCapturerConfig){CGSizeMake(640, 480), 15};

        _dropFrameManager = [[RZVideoDropFrameManager alloc] init];

#if TARGET_OS_IOS


        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sessionWasInterrupted:) name:AVCaptureSessionWasInterruptedNotification object:nil];


        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sessionInterruptionEnd:) name:AVCaptureSessionInterruptionEndedNotification object:nil];


        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sessionRuntimeError:) name:AVCaptureSessionRuntimeErrorNotification object:nil];

        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(statusBarOrientationDidChange:) name:UIApplicationDidChangeStatusBarOrientationNotification object:nil];


        switch ([AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo]) {
            case AVAuthorizationStatusAuthorized: {
                break;
            }
            case AVAuthorizationStatusNotDetermined: {
                dispatch_suspend(self.sessionQueue);
                [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
                    if (!granted) {
                        self.setupResult = AVCamSetupResultCameraNotAuthorized;
                    }
                    dispatch_resume(self.sessionQueue);
                }];
                break;
            }
            default: {
                // The user has previously denied access.
                self.setupResult = AVCamSetupResultCameraNotAuthorized;
                break;
            }
        }

#endif

        dispatch_async(self.sessionQueue, ^{
//默认设备
#if TARGET_OS_IOS
            self.currentDevice = [RZVideoCapturerUtil videoCaptureDeviceWithPosition:AVCaptureDevicePositionFront];
            dispatch_async(dispatch_get_main_queue(), ^{
                self.captureVideoOrientation = [self videoOrientation];
                dispatch_semaphore_signal(self.semaphore);
            });
            dispatch_semaphore_wait(self.semaphore, DISPATCH_TIME_FOREVER);
#elif TARGET_OS_OSX
            self.currentDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
            self.captureVideoOrientation = AVCaptureVideoOrientationPortrait;
#endif
            [self configureSession];
        });
    }
    return self;
}


// Call this on the session queue.
- (void)configureSession
{
    if (self.setupResult != AVCamSetupResultSuccess) {
        return;
    }

    [self.session beginConfiguration];

    // find video input device
    NSError *error = nil;
    AVCaptureDevice *captureDevice = self.currentDevice;
    AVCaptureDeviceInput *videoDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:captureDevice error:&error];
    if (!videoDeviceInput) {
        self.setupResult = AVCamSetupResultSessionConfigurationFailed;
        [self.session commitConfiguration];
        return;
    }

    NSArray *inputs = self.session.inputs;
    if (inputs.count > 0) {
        //remove old inputs
        for (AVCaptureDeviceInput *input in inputs) {
            [self.session removeInput:input];
        }
    }

    //add video input device
    if ([self.session canAddInput:videoDeviceInput]) {
        [self.session addInput:videoDeviceInput];
        self.videoInput = videoDeviceInput;
    } else {
        self.setupResult = AVCamSetupResultSessionConfigurationFailed;
        [self.session commitConfiguration];
        return;
    }


    NSInteger dstRate;
    [RZVideoCapturerUtil setCaptureFrameRate:self.videoConfig.frameRate dstSize:self.videoConfig.dimension forDevice:captureDevice resultFrameRate:&dstRate];

    NSLog(@"%s, fps = %ld", __func__, (long)dstRate);


    //add video data output
    AVCaptureVideoDataOutput *output = [[AVCaptureVideoDataOutput alloc] init];
#if TARGET_OS_OSX
    NSDictionary *settings = @{(NSString *)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange),
                               (NSString *)kCVPixelBufferWidthKey : @(self.videoConfig.dimension.width),
                               (NSString *)kCVPixelBufferHeightKey : @(self.videoConfig.dimension.height)

    };
#else
    NSDictionary *settings = @{(NSString *)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange) };
#endif
    output.videoSettings = settings;

    if ([self.session canAddOutput:output]) {
        [self.session addOutput:output];
        [output setSampleBufferDelegate:self queue:self.sampleBufferCallbackQueue];
        self.videoOutput = output;
    } else {
        self.setupResult = AVCamSetupResultSessionConfigurationFailed;
        [self.session commitConfiguration];
        return;
    }

    //设置视频的方向
    AVCaptureConnection *connect = [self.videoOutput connectionWithMediaType:AVMediaTypeVideo];
    connect.videoOrientation = self.captureVideoOrientation;

    self.setupResult = AVCamSetupResultSuccess;
    [self.session commitConfiguration];
}

- (int)start
{
    if (self.session.isRunning) {
        if ([self.delegate respondsToSelector:@selector(videoCapturer:didStartWithReason:)]) {
            [self.delegate videoCapturer:self didStartWithReason:RZVCamStartReasonUserTrigger];
        }
        return 0;
    }

#if TARGET_OS_IOS
    [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
        if (granted) {
            //have permisson, start recording
            [self startSession];
        } else {
            //not have permisson
            if ([self.delegate respondsToSelector:@selector(videoCapturer:didStopWithReason:)]) {
                [self.delegate videoCapturer:self didStopWithReason:RZVCamStopReasonNoPermission];
            }
        }
    }];

#elif TARGET_OS_OSX
    if (@available(macOS 10.14, *)) {
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
            if (granted) {
                //have permisson, start recording
                [self startSession];
            } else {
                //not have permisson
                if ([self.delegate respondsToSelector:@selector(videoCapturer:didStopWithReason:)]) {
                    [self.delegate videoCapturer:self didStopWithReason:RZVCamStopReasonNoPermission];
                }
            }
        }];
    } else {
        // Fallback on earlier versions
        [self startSession];
    }
#endif
    return 0;
}


- (void)startSession
{
    dispatch_async(self.sessionQueue, ^{
        if (self.setupResult == AVCamSetupResultSuccess) {
            //start success
            [self.session startRunning];
            if ([self.delegate respondsToSelector:@selector(videoCapturer:didStartWithReason:)]) {
                [self.delegate videoCapturer:self didStartWithReason:RZVCamStartReasonUserTrigger];
            }
        } else {
            //not setup success, stop
            if ([self.delegate respondsToSelector:@selector(videoCapturer:didStopWithReason:)]) {
                [self.delegate videoCapturer:self didStopWithReason:RZVCamStopReasonSetupError];
            }
        }
    });
}

- (int)stop
{
    return [self stopWithCallback:nil];
}

- (int)stopWithCallback:(void (^)(void))callback
{
    if (!self.session.isRunning) {
        if ([self.delegate respondsToSelector:@selector(videoCapturer:didStopWithReason:)]) {
            [self.delegate videoCapturer:self didStopWithReason:RZVCamStopReasonUserTrigger];
        }
        if (callback) {
            callback();
        }
        return 0;
    }
    dispatch_async(self.sessionQueue, ^{
        [self.session stopRunning];
        if ([self.delegate respondsToSelector:@selector(videoCapturer:didStopWithReason:)]) {
            [self.delegate videoCapturer:self didStopWithReason:RZVCamStopReasonUserTrigger];
        }
        if (callback) {
            callback();
        }
    });
    return 0;
}


#if TARGET_OS_IOS
//切换前后摄像头
- (void)swapFrontAndBackCameras
{
    dispatch_async(self.sessionQueue, ^{

        AVCaptureDevicePosition currentPosition = self.currentDevice.position;
        AVCaptureDevicePosition preferredPosition;
        switch (currentPosition) {
            case AVCaptureDevicePositionFront:
                preferredPosition = AVCaptureDevicePositionBack;
                break;
            case AVCaptureDevicePositionUnspecified:
            case AVCaptureDevicePositionBack:
                preferredPosition = AVCaptureDevicePositionFront;
                break;
        }

        AVCaptureDevice *nextCaptureDevice = [RZVideoCapturerUtil videoCaptureDeviceWithPosition:preferredPosition];
        if (!nextCaptureDevice) {
            return;
        }
        [self setCurrentInputDevice:nextCaptureDevice];
    });
}
#endif


#pragma mark - AVCaptureVideoDataOutputSampleBufferDelegate
- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
    //这里需要做一下丢帧处理
//    if ([self shouldDisposeBuffer:sampleBuffer]) {
//        return;
//    }
    
#if TARGET_OS_OSX
    BOOL isFront = YES;
#else
    BOOL isFront = self.currentDevice.position == AVCaptureDevicePositionFront;
#endif
    
    if ([self.delegate respondsToSelector:@selector(videoCapturer:didReceiveSampleBuffer:isFromFrontCamera:)]) {
        [self.delegate videoCapturer:self didReceiveSampleBuffer:sampleBuffer isFromFrontCamera:isFront];
    }
}

#pragma mark - getter

- (RZVCamSource)source
{
    return RZVCamSourceCamera;
}

- (AVCaptureVideoOrientation)videoOrientation
{
#if TARGET_OS_IOS
    UIInterfaceOrientation statusBarOrientation = UIApplication.sharedApplication.statusBarOrientation;
    if (statusBarOrientation == UIInterfaceOrientationUnknown) {
        return AVCaptureVideoOrientationPortrait;
    }
    return (AVCaptureVideoOrientation)statusBarOrientation;
#endif
    return AVCaptureVideoOrientationPortrait;
}

- (BOOL)shouldDisposeBuffer:(CMSampleBufferRef)sampleBuffer
{
#if TARGET_OS_OSX
    NSInteger targetRate = self.videoConfig.frameRate;
    UInt64 sequenceNumber = CMIOSampleBufferGetSequenceNumber(sampleBuffer);
    CMTime duration = CMSampleBufferGetDuration(sampleBuffer);
    NSInteger frameRate = duration.timescale / duration.value;

    if (frameRate <= targetRate) {
        //采集的帧率，小于编码要求的帧率，此时不需要丢帧
        return NO;
    }

    self.dropFrameManager.targetFps = targetRate;
    self.dropFrameManager.sourceFps = frameRate;
    return [self.dropFrameManager shoudDropBySequeceNumber:sequenceNumber];
#endif
    return NO;
}

#pragma mark - setter
- (void)setVideoConfig:(DbyCapturerConfig)videoConfig
{
    _videoConfig = videoConfig;


    dispatch_async(self.sessionQueue, ^{
        //设置分辨率和帧率
        [self.session beginConfiguration];

#if TARGET_OS_OSX
        NSDictionary *settings = @{(NSString *)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange),
                                   (NSString *)kCVPixelBufferWidthKey : @(self.videoConfig.dimension.width),
                                   (NSString *)kCVPixelBufferHeightKey : @(self.videoConfig.dimension.height)

        };
        self.videoOutput.videoSettings = settings;
#endif
        NSInteger dstRate;
        [RZVideoCapturerUtil setCaptureFrameRate:videoConfig.frameRate
                                  dstSize:videoConfig.dimension
                                forDevice:self.currentDevice
                          resultFrameRate:&dstRate];

        NSLog(@"%s, fps = %ld", __func__, (long)dstRate);
        [self.session commitConfiguration];
    });
}

- (void)setCurrentInputDevice:(nonnull AVCaptureDevice *)currentInputDevice
{
    NSError *error;
    AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:currentInputDevice error:&error];
    if (error) {
        return;
    }

    dispatch_async(self.sessionQueue, ^{
        [self.session beginConfiguration];

#if TARGET_OS_OSX
        NSDictionary *settings = @{(NSString *)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange),
                                   (NSString *)kCVPixelBufferWidthKey : @(self.videoConfig.dimension.width),
                                   (NSString *)kCVPixelBufferHeightKey : @(self.videoConfig.dimension.height)

        };

        self.videoOutput.videoSettings = settings;
#endif
        if (self.videoInput) {
            [self.session removeInput:self.videoInput];
        }

        if ([self.session canAddInput:input]) {
            [self.session addInput:input];
            self.videoInput = input;
        } else {
            if (self.videoInput) {
                [self.session addInput:self.videoInput];
            }
        }
        NSInteger dstRate;
        [RZVideoCapturerUtil setCaptureFrameRate:self.videoConfig.frameRate dstSize:self.videoConfig.dimension forDevice:currentInputDevice resultFrameRate:&dstRate];
        NSLog(@"%s, fps = %ld", __func__, (long)dstRate);
        self->_currentDevice = currentInputDevice;

        //设置视频的方向
        AVCaptureConnection *connect = [self.videoOutput connectionWithMediaType:AVMediaTypeVideo];
        connect.videoOrientation = self.captureVideoOrientation;

        [self.session commitConfiguration];
    });
}


#pragma mark - Notification
#if TARGET_OS_IOS


- (void)sessionWasInterrupted:(NSNotification *)notification
{
    if ([self.delegate respondsToSelector:@selector(videoCapturer:didStopWithReason:)]) {
        [self.delegate videoCapturer:self didStopWithReason:RZVCamStopReasonSystemInterrupt];
    }
}

- (void)sessionInterruptionEnd:(NSNotification *)notification
{
    if ([self.delegate respondsToSelector:@selector(videoCapturer:didStartWithReason:)]) {
        [self.delegate videoCapturer:self didStartWithReason:RZVCamStartReasonSystemInterruptEnd];
    }
}

- (void)sessionRuntimeError:(NSNotification *)notification
{
    NSError *error = notification.userInfo[AVCaptureSessionErrorKey];
    // If media services were reset, and the last start succeeded, restart the session.
    if (error.code == AVErrorMediaServicesWereReset) {
        [self startSession];
    } else {
        if ([self.delegate respondsToSelector:@selector(videoCapturer:didStopWithReason:)]) {
            [self.delegate videoCapturer:self didStopWithReason:RZVCamStopReasonSystemError];
        }
    }
}

- (void)statusBarOrientationDidChange:(NSNotification *)notification
{
    AVCaptureConnection *connection = [self.videoOutput connectionWithMediaType:AVMediaTypeVideo];
    dispatch_async(dispatch_get_main_queue(), ^{
        AVCaptureVideoOrientation orientation = [self videoOrientation];
        self.captureVideoOrientation = orientation;
        if (connection.videoOrientation != orientation) {
            connection.videoOrientation = orientation;
        }
    });
}

#endif




#if TARGET_OS_IOS
#pragma mark - 自动对焦
/*
 参考：https://github.com/donggaizhi/DHCamera
 */
- (void)focusInCenter {
    [self focus:CGPointMake(0.5, 0.5)];
}

#pragma mark 设置聚焦点和自动曝光
- (NSError *)focus:(CGPoint)point {
    AVCaptureDevice *device = self.currentDevice;
    NSError *error = nil;
    if ([device lockForConfiguration:&error]) {
        if ([device isFocusPointOfInterestSupported] && [device isFocusModeSupported:AVCaptureFocusModeContinuousAutoFocus]) {
            device.focusPointOfInterest = point;
            device.focusMode = AVCaptureFocusModeContinuousAutoFocus;
        }
        if ([device isExposurePointOfInterestSupported] && [device isExposureModeSupported:AVCaptureExposureModeContinuousAutoExposure]) {
            device.exposurePointOfInterest = point;
            device.exposureMode = AVCaptureExposureModeContinuousAutoExposure;
        }
        if ([device isWhiteBalanceModeSupported:AVCaptureWhiteBalanceModeContinuousAutoWhiteBalance]) {
            device.whiteBalanceMode = AVCaptureWhiteBalanceModeContinuousAutoWhiteBalance;
        }
        [device unlockForConfiguration];
    }
    return error;
}

#endif

@end
