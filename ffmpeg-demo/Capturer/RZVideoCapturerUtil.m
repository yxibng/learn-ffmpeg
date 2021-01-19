//
//  DbyVideoUtil.m
//  DbyPaas_iOS
//
//  Created by yxibng on 2020/1/14.
//

#import "RZVideoCapturerUtil.h"


@implementation RZCamVideoFormat

@end


@implementation RZVideoCapturerUtil

//video capture device with specified positon
+ (AVCaptureDevice *)videoCaptureDeviceWithPosition:(AVCaptureDevicePosition)position
{
    AVCaptureDevice *videoDevice;
#if TARGET_OS_IOS
    if (@available(iOS 11.1, *)) {
        NSArray<AVCaptureDeviceType> *deviceTypes = @[ AVCaptureDeviceTypeBuiltInWideAngleCamera,
                                                       AVCaptureDeviceTypeBuiltInDualCamera,
                                                       AVCaptureDeviceTypeBuiltInTrueDepthCamera ];

        AVCaptureDeviceDiscoverySession *session = [AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:deviceTypes
                                                                                                          mediaType:AVMediaTypeVideo
                                                                                                           position:position];
        for (AVCaptureDevice *device in session.devices) {
            if (device.position == position) {
                videoDevice = device;
                break;
            }
        }
    } else if (@available(iOS 10.0, *)) {
        videoDevice = [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera mediaType:AVMediaTypeVideo position:position];
    } else {
        NSArray *cameras = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
        for (AVCaptureDevice *device in cameras) {
            if (device.position == position) {
                videoDevice = device;
                break;
            }
        }
    }
#elif TARGET_OS_OSX
    videoDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
#endif
    return videoDevice;
}

//all video capture devices
+ (NSArray<AVCaptureDevice *> *)videoCaptureDevices
{
    return [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
}
//search for AVCaptureDevice with uniqueID
+ (AVCaptureDevice *)videoCaptureDeviceWithID:(NSString *)uniqueID
{
    if (!uniqueID) {
        return nil;
    }
    return [AVCaptureDevice deviceWithUniqueID:uniqueID];
}

NSString *fourCharNSStringForFourCharCode(FourCharCode aCode)
{
    char fourChar[5] = {(aCode >> 24) & 0xFF, (aCode >> 16) & 0xFF, (aCode >> 8) & 0xFF, aCode & 0xFF, 0};

    NSString *fourCharString = [NSString stringWithCString:fourChar encoding:NSUTF8StringEncoding];

    return fourCharString;
}


static NSString *NSStringFromCode(UInt32 code)
{
    UInt8 chars[4];
    *(UInt32 *)chars = code;
    for (UInt32 i = 0; i < 4; ++i) {
        if (!isprint(chars[i])) {
            return [NSString stringWithFormat:@"%u", code];
        }
    }
    return [NSString stringWithFormat:@"%c%c%c%c", chars[3], chars[2], chars[1], chars[0]];
}


+ (void)setCaptureFrameRate:(NSInteger)frameRate
                    dstSize:(CGSize)size
                  forDevice:(AVCaptureDevice *)device
            resultFrameRate:(NSInteger *)resultFrameRate
{
    //参考 https://developer.apple.com/documentation/avfoundation/avcapturedevice?language=objc
    if (!device) {
        return;
    }

    AVCaptureDeviceFormat *format = [self closeFormatWithDimension:size forDevice:device];

    AVFrameRateRange *bestFrameRateRange = format.videoSupportedFrameRateRanges.firstObject;

    for (AVFrameRateRange *range in format.videoSupportedFrameRateRanges) {
        if ((NSInteger)range.maxFrameRate >= frameRate) {
            bestFrameRateRange = range;
            break;
        }
    }

    CMTime time;
    if (frameRate >= (NSInteger)bestFrameRateRange.maxFrameRate) {
        time = bestFrameRateRange.minFrameDuration;
        if (resultFrameRate) {
            *resultFrameRate = (NSInteger)bestFrameRateRange.maxFrameRate;
        }
    } else if (frameRate <= (NSInteger)bestFrameRateRange.minFrameRate) {
        time = bestFrameRateRange.maxFrameDuration;
        if (resultFrameRate) {
            *resultFrameRate = (NSInteger)bestFrameRateRange.minFrameRate;
        }
    } else {
        time = CMTimeMake(1, (int)frameRate);
        if (resultFrameRate) {
            *resultFrameRate = (NSInteger)frameRate;
        }
    }

    [device lockForConfiguration:NULL];
    device.activeFormat = format;
    device.activeVideoMaxFrameDuration = time;
    device.activeVideoMinFrameDuration = time;
    [device unlockForConfiguration];

    return;
}


+ (AVCaptureDeviceFormat *)closeFormatWithDimension:(CGSize)dimension forDevice:(AVCaptureDevice *)device
{
    NSMutableArray *formats = [NSMutableArray arrayWithArray:device.formats];

    [formats sortUsingComparator:^NSComparisonResult(AVCaptureDeviceFormat *_Nonnull obj1, AVCaptureDeviceFormat *_Nonnull obj2) {

        CMVideoDimensions dimension1 = CMVideoFormatDescriptionGetDimensions(obj1.formatDescription);
        CMVideoDimensions dimension2 = CMVideoFormatDescriptionGetDimensions(obj2.formatDescription);

        if (dimension1.width < dimension2.width) {
            return NSOrderedAscending;
        } else if (dimension1.width > dimension2.width) {
            return NSOrderedDescending;
        } else {
            if (dimension1.height < dimension2.height) {
                return NSOrderedAscending;
            } else if (dimension1.height > dimension2.height) {
                return NSOrderedDescending;
            } else {
                return NSOrderedSame;
            }
        }
    }];

    AVCaptureDeviceFormat *dstFormat = nil;
    for (AVCaptureDeviceFormat *format in formats) {
        CMVideoDimensions size = CMVideoFormatDescriptionGetDimensions(format.formatDescription);
        if (size.width >= dimension.width && size.height >= dimension.height) {
            dstFormat = format;
            break;
        }
    }

    if (!dstFormat) {
        dstFormat = formats.lastObject;
    }
    NSLog(@"dstFormat = %@", dstFormat);
    return dstFormat;
}


@end


@implementation RZVideoDropFrameManager

- (instancetype)init
{
    self = [super init];
    if (self) {
        _sourceFps = 30;
        _targetFps = 15;
        [self setupSet];
    }
    return self;
}

- (void)setupSet
{
    if (_sourceFps <= _targetFps) {
        _set = [NSSet set];
        return;
    }

    float stride = (float)self.sourceFps / self.targetFps;

    NSMutableSet *set = [NSMutableSet set];
    for (int i = 1; i <= self.sourceFps; i++) {
        float val = i * stride;
        if (val > self.sourceFps) {
            break;
        }

        int index = floor(val);
        [set addObject:@(index)];
    }
    _set = set;
}

- (BOOL)shoudDropBySequeceNumber:(UInt64)sequeceNumber
{
    UInt64 number = sequeceNumber % self.sourceFps;
    if (number == 0) {
        number = self.sourceFps;
    }

    BOOL shouldDrop = ![self.set containsObject:@(number)];
    return shouldDrop;
}


- (void)setSourceFps:(NSInteger)sourceFps
{
    if (_sourceFps == sourceFps) {
        return;
    }

    _sourceFps = sourceFps;
    [self setupSet];
}

- (void)setTargetFps:(NSInteger)targetFps
{
    if (_targetFps == targetFps) {
        return;
    }
    _targetFps = targetFps;
    [self setupSet];
}

@end
