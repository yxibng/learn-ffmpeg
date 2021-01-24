//
//  HWEncoder.m
//  ffmpeg-demo
//
//  Created by yxibng on 2021/1/23.
//

#import "HWEncoder.h"

@interface HWEncoder()
{
    VTCompressionSessionRef _compressionSession;
    CGSize _encodeDimension;
    int _fps;
    BOOL _setupSuccess;
    uint64_t _pts;
}

@property (nonatomic, strong) dispatch_queue_t encodeQueue;

@end

@implementation HWEncoder

void hw_CompressionOutputCallback (
                                   void * CM_NULLABLE outputCallbackRefCon,
                                   void * CM_NULLABLE sourceFrameRefCon,
                                   OSStatus status,
                                   VTEncodeInfoFlags infoFlags,
                                   CM_NULLABLE CMSampleBufferRef sampleBuffer )
{
    
    if (status != noErr) {
        //编码失败
        NSLog(@"encode callback failed, status = %d", status);
        return;
    }
    
    BOOL isReady = CMSampleBufferDataIsReady(sampleBuffer);
    if (!isReady) {
        NSLog(@"encode callback, data is not ready");
        return;
    }
    CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, true);
    CFDictionaryRef theAttachment = CFArrayGetValueAtIndex(attachments, 0);
    BOOL keyFrame = CFDictionaryContainsKey(theAttachment, kCMSampleAttachmentKey_NotSync);
    
    HWEncoder *encoder = (__bridge HWEncoder *)outputCallbackRefCon;
    
    if (keyFrame) {
        /*
        关键帧，分离sps， pps
         */
        
        CMFormatDescriptionRef format = CMSampleBufferGetFormatDescription(sampleBuffer);
        size_t spsSetSize, spsSetCount;
        const uint8_t *sps;
        OSStatus status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format,
                                                                             0,
                                                                             &sps,
                                                                             &spsSetSize,
                                                                             &spsSetCount,
                                                                             NULL);
        if (status == noErr) {
            size_t ppsSetSize, ppsSetCount;
            const uint8_t *pps;
            status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format,
                                                                        1,
                                                                        &pps,
                                                                        &ppsSetSize,
                                                                        &ppsSetCount,
                                                                        NULL);
            
            if (status == noErr) {
                NSData *spsData = [NSData dataWithBytes:sps length:spsSetSize];
                NSData *ppsData = [NSData dataWithBytes:pps length:ppsSetSize];
                
                if ([encoder.delegate respondsToSelector:@selector(hwEncoder:gotSps:pps:)]) {
                    [encoder.delegate hwEncoder:encoder gotSps:spsData pps:ppsData];
                }
            }

        }
    }
    
    /*
     分离nalu 数据
     */
    
    CMBlockBufferRef dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
    size_t length, totalLength;
    char *dataPointer;
    status = CMBlockBufferGetDataPointer(dataBuffer, 0, &length, &totalLength, &dataPointer);
    if (status != noErr) {
        return;
    }
    
    size_t bufferOffset = 0;
    /*
     硬编产生的数据是AVCC格式的，另外一种是Annex-B格式的
     AVCC格式使用NALU长度（固定字节，字节数由extradata中的信息给定）进行分割，在封装文件或者直播流的头部包含extradata信息（非NALU），extradata中包含NALU长度的字节数以及SPS/PPS信息。
     Annex-B格式使用start code进行分割，start code为0x000001或0x00000001，SPS/PPS作为一般NALU单元以start code作为分隔符的方式放在文件或者直播流的头部。

     https://www.jianshu.com/p/3192162ffda1
     */
    size_t avccHeaderLength = 4;
    
    /*
    从data pointer 循环获取nalu数据
     */
    char *dataPtr = dataPointer;
    while (bufferOffset < totalLength) {
        uint32_t naluLength = 0;
        //读取nalu 长度
        memcpy(&naluLength, dataPtr, avccHeaderLength);
        //大端转系统端
        naluLength = CFSwapInt32BigToHost(naluLength);
        
        //获取nalu
        char *naluPtr = dataPtr + avccHeaderLength;
        NSData *data = [NSData dataWithBytes:naluPtr length:naluLength];
        //回调数据
        if ([encoder.delegate respondsToSelector:@selector(hwEncoder:gotEncodedData:isKeyFrame:)]) {
            [encoder.delegate hwEncoder:encoder gotEncodedData:data isKeyFrame:keyFrame];
        }
        
        //移动到下一个NALU单元
        dataPtr += avccHeaderLength + naluLength;
    }
}

- (void)dealloc
{
    [self _forceToComplete];
}


- (instancetype)init
{
    self = [super init];
    if (self) {
        _fps = 15;
        _encodeDimension = CGSizeMake(640, 480);
        _encodeQueue = dispatch_queue_create("com.hw.encode.queue", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}


- (BOOL)setupEncoderWithSize:(CGSize)size frameRate:(int)frameRate {
    
    if (_setupSuccess) {
        
        if (CGSizeEqualToSize(size, _encodeDimension) && frameRate == _fps) {
            return YES;
        } else {
            //重置编码器
            [self _forceToComplete];
        }
    }
    
    return [self _createSessionWithSize:size frameRate:frameRate];
}


- (void)encodeSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    

    if (!sampleBuffer) {
        return;
    }
    
    CVImageBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (!_setupSuccess) {
        //如果解码器未创建，创建解码器
        CVPixelBufferLockBaseAddress(pixelBuffer, 0);
        size_t width = CVPixelBufferGetWidth(pixelBuffer);
        size_t height = CVPixelBufferGetWidth(pixelBuffer);
        CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
        BOOL ret = [self setupEncoderWithSize:CGSizeMake(width, height) frameRate:_fps];
        if (!ret) {
            //创建失败
            return;
        }
    }
    /*
     CMTime
     https://developer.apple.com/documentation/coremedia/cmtime-u58?language=objc
     */
    CMTime pts = CMTimeMake(_pts++, 600);
    VTEncodeInfoFlags flags;
    OSStatus status = VTCompressionSessionEncodeFrame(_compressionSession,
                                                      pixelBuffer,
                                                      pts,
                                                      kCMTimeInvalid,
                                                      NULL,
                                                      NULL,
                                                      &flags);
    
    if (status != noErr) {
        /*
         编码失败
         */
        NSLog(@"VTCompressionSessionEncodeFrame failed, status = %d",status);
        [self _forceToComplete];
        return;
    }
    NSLog(@"encode success");
}


- (void)stopEncoding {
    [self _forceToComplete];
}


- (BOOL)_createSessionWithSize:(CGSize)size frameRate:(int)frameRate {
    assert(_setupSuccess == NO);
    
    OSStatus status = VTCompressionSessionCreate(NULL, size.width, size.height,
                                                 kCMVideoCodecType_H264,
                                                 NULL,
                                                 NULL,
                                                 NULL,
                                                 hw_CompressionOutputCallback,
                                                 (__bridge  void *)self,
                                                 &_compressionSession);
    if (status != noErr) {
        NSLog(@"h264 encode session create failed, status = %d", status);
        return NO;
    }
    
    //实时编码
    VTSessionSetProperty(_compressionSession, kVTCompressionPropertyKey_RealTime, kCFBooleanTrue);
    /*
     参考： https://blog.csdn.net/sphone89/article/details/17492433?utm_medium=distribute.pc_relevant_t0.none-task-blog-BlogCommendFromBaidu-1.control&depth_1-utm_source=distribute.pc_relevant_t0.none-task-blog-BlogCommendFromBaidu-1.control
     baseline 多用于实时通讯领域
     */
    VTSessionSetProperty(_compressionSession, kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_H264_Baseline_AutoLevel);
    
    /*
     gop size 代表两个 IDR（立即刷新帧）之间的帧数
     https://blog.csdn.net/Liu1314you/article/details/77185215
     */
    int gopSize = 15;
    VTSessionSetProperty(_compressionSession, kVTCompressionPropertyKey_MaxKeyFrameInterval, (__bridge CFNumberRef)@(gopSize));
    /*
     设置帧率
     */
    VTSessionSetProperty(_compressionSession, kVTCompressionPropertyKey_ExpectedFrameRate, (__bridge CFNumberRef)@(frameRate));
    
    /*
     设置平均码率，单位bit
     https://www.jianshu.com/p/594164b0d70d
     */
    uint64_t bitRate = size.width * size.height * 3 * 8;
    VTSessionSetProperty(_compressionSession, kVTCompressionPropertyKey_AverageBitRate, (__bridge CFNumberRef)@(bitRate));
    /*
     设置码率上限，单位byte
     */
    uint64_t maxByptesPerSec = size.width * size.height * 3 * 2;
    VTSessionSetProperty(_compressionSession, kVTCompressionPropertyKey_DataRateLimits, (__bridge CFNumberRef)@(maxByptesPerSec));
    
    /**
     开始编码前进行必要的资源申请，
     如果不调用，会在首次编码首帧的时候进行资源的申请
     */
    status = VTCompressionSessionPrepareToEncodeFrames(_compressionSession);
    if (status != noErr) {
        return NO;
    }
    
    _fps = frameRate;
    _encodeDimension = size;
    
    _pts = 1;
    _setupSuccess = YES;
    return YES;
}


- (void)_forceToComplete {
    
    if (_compressionSession) {
        //强制刷新，丢弃所有penging的数据
        VTCompressionSessionCompleteFrames(_compressionSession, kCMTimeInvalid);
        VTCompressionSessionInvalidate(_compressionSession);
        CFRelease(_compressionSession);
        _compressionSession = NULL;
        _setupSuccess = NO;
    }
    
}


@end
