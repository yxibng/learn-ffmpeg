//
//  HWDecoder.m
//  ffmpeg-demo
//
//  Created by yxibng on 2021/1/23.
//

#import "HWDecoder.h"

@interface HWDecoder ()
{
    
    VTDecompressionSessionRef _decompressionSession;
    BOOL _setupSuccess;
    
    //解码format 封装了sps和pps
    CMVideoFormatDescriptionRef _decoderFormatDescription;
    
    //sps & pps
    uint8_t *_sps;
    uint32_t _spsSize;
    uint8_t *_pps;
    uint32_t _ppsSize;
}





@end


@implementation HWDecoder



void decodeCallback (
                     void * CM_NULLABLE decompressionOutputRefCon,
                     void * CM_NULLABLE sourceFrameRefCon,
                     OSStatus status,
                     VTDecodeInfoFlags infoFlags,
                     CM_NULLABLE CVImageBufferRef imageBuffer,
                     CMTime presentationTimeStamp,
                     CMTime presentationDuration )
{
    HWDecoder *decoder = (__bridge HWDecoder *)decompressionOutputRefCon;
    if ([decoder.delegate respondsToSelector:@selector(hwDecoder:didDecodeBuffer:)]) {
        [decoder.delegate hwDecoder:decoder didDecodeBuffer:imageBuffer];
    }
}

- (void)dealloc
{
    [self endDecoding];
}

- (BOOL)initH264Decoder {
    
    if (_setupSuccess) {
        return YES;
    }
    
    if (!_sps || !_pps) {
        return NO;
    }
    
    const uint8_t * const sps_pps[2] = {
        _sps, _pps
    };
    
    const size_t sps_pps_size[2] = {
        _spsSize, _ppsSize
    };
    
    //用sps 和pps 实例化_decoderFormatDescription
    OSStatus status = CMVideoFormatDescriptionCreateFromH264ParameterSets(NULL, 2, sps_pps, sps_pps_size, 4, &_decoderFormatDescription);
    if (status != noErr) {
        return NO;
    }
    
    NSDictionary *destinationPixelBufferAttributes = @{
        //解码为nv12
        (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange),
        (id)kCVPixelFormatCodecType:@(kCMVideoCodecType_H264)
    };
    
    
    VTDecompressionOutputCallbackRecord callBackRecord;
    callBackRecord.decompressionOutputCallback = decodeCallback;
    callBackRecord.decompressionOutputRefCon = (__bridge void *)self;
    
    status = VTDecompressionSessionCreate(NULL,
                                          _decoderFormatDescription,
                                          NULL,
                                          (__bridge CFDictionaryRef)destinationPixelBufferAttributes,
                                          &callBackRecord,
                                          &_decompressionSession);
    
    if (status != noErr) {
        return NO;
    }
    //解码的线程数量
    VTSessionSetProperty(_decompressionSession, kVTDecompressionPropertyKey_ThreadCount, (__bridge CFTypeRef)[NSNumber numberWithInt:1]);
    //实时解码
    VTSessionSetProperty(_decompressionSession, kVTDecompressionPropertyKey_RealTime, kCFBooleanTrue);
    
    _setupSuccess = YES;
    return YES;
}

- (void)decodeSps:(uint8_t *)sps spsSize:(uint32_t)spsSize
              pps:(uint8_t *)pps ppsSize:(uint32_t)ppsSize {
    
    if (!sps || !pps) {
        return;
    }

    /*
     去掉Annex-B header。
     sps,pps只需要nalu即可
     */
    
    uint32_t annexbHeaderLength = 4;

    uint32_t spsNaluLength = spsSize - annexbHeaderLength;
    _spsSize = spsNaluLength;
    _sps = realloc(_sps, spsNaluLength);
    memcpy(_sps, sps+annexbHeaderLength, spsNaluLength);

    uint32_t ppsNaluLength = ppsSize - annexbHeaderLength;
    _ppsSize = ppsNaluLength;
    _pps = realloc(_pps, ppsNaluLength);
    memcpy(_pps, pps+annexbHeaderLength, ppsNaluLength);

    if (!_decompressionSession) {
        [self initH264Decoder];
        return;
    }

    const uint8_t * const sps_pps[2] = {
        _sps, _pps
    };
    
    const size_t sps_pps_size[2] = {
        _spsSize, _ppsSize
    };
    
    //用sps 和pps 实例化_decoderFormatDescription
    CMVideoFormatDescriptionRef format;
    OSStatus status = CMVideoFormatDescriptionCreateFromH264ParameterSets(NULL, 2, sps_pps, sps_pps_size, 4, &format);
    if (status != noErr) {
        return;
    }
    BOOL needNewSession = !VTDecompressionSessionCanAcceptFormatDescription(_decompressionSession, format);
    CFRelease(format);
    if (needNewSession) {
        //重新构建session
        [self endDecoding];
        [self initH264Decoder];
    }
}


- (void)decodeNalu:(uint8_t *)frame size:(uint32_t)size {
    
    /*
     Annex-B 类型的nalu， startcode(4 bytes) + naluheader(1 byte) + rbsp
     转换为 AVCC 格式 length(4 bytes) + naluheader(1 byte) + rbsp
     
     NAL Header 的组成为：
     forbidden_zero_bit(1bit) + nal_ref_idc(2bit) + nal_unit_type(5bit)
     
     
     Annex-B 解码的序列： sps - pps - IDR - P - B ...
     需要先拿到 sps 和 pps 构建 编码session
     之后根据 sps 和 pps 进行解码
     
     替换start code 为 nalu length
     TODO: 这里修改了原始数据，不太好
    */
    
    /*
     系统端转大端
     */
    uint32_t naluSize = CFSwapInt32HostToBig(size - 4);
    void *pNaluSize = (void *)(&naluSize);
    memcpy(frame, pNaluSize, 4);
        
    int nalu_type = frame[4] & 0x1F;
    switch (nalu_type) {
        case 0x05:
            //关键帧
        {
            if ([self initH264Decoder]) {
                [self _decodeAVCC:frame size:size];
            }
        }
            break;
        case 0x07:
            //sps
            _spsSize = size - 4;
            _sps = realloc(_sps, _spsSize);
            memcpy(_sps, &frame[4], _spsSize);
            break;
        case 0x08:
            //pps
            _ppsSize = size - 4;
            _pps = realloc(_pps, _ppsSize);
            memcpy(_pps, &frame[4], _ppsSize);
            break;
        default:
        {
            //B/P frame
            if ([self initH264Decoder]) {
                [self _decodeAVCC:frame size:size];
            }
        }
            break;
    }
}


- (void)endDecoding {
 
    if (_decompressionSession) {
        VTDecompressionSessionInvalidate(_decompressionSession);
        CFRelease(_decompressionSession);
        _decompressionSession = NULL;
    }
    
    
    if (_decoderFormatDescription) {
        CFRelease(_decoderFormatDescription);
        _decoderFormatDescription = NULL;
    }
    
    if (_sps) {
        free(_sps);
        _sps = NULL;
    }
    
    if (_pps) {
        _pps = NULL;
    }
    
    _ppsSize = 0;
    _spsSize = 0;

}



- (void)_decodeAVCC:(uint8_t *)data size:(uint32_t)size {
    
    
    CMBlockBufferRef blockBuffer = NULL;
    OSStatus status = CMBlockBufferCreateWithMemoryBlock(NULL, (void *)data, size, NULL, NULL, 0, size, kCMBlockBufferAssureMemoryNowFlag, &blockBuffer);
    if (status != kCMBlockBufferNoErr) {
        return;
    }
        
    CMSampleBufferRef sampleBuffer = NULL;
    const size_t sampleSizeArray[] = {size};
    
    //创建sample Buffer
    
    status = CMSampleBufferCreateReady(NULL, blockBuffer, _decoderFormatDescription, 1, 0, NULL, 1, sampleSizeArray, &sampleBuffer);
    if (status != noErr || !sampleBuffer) {
        goto failed;
        return;
    }
    
    //同步解码
    VTDecodeFrameFlags decodeFlags = 0;
    
    status = VTDecompressionSessionDecodeFrame(_decompressionSession, sampleBuffer, decodeFlags, NULL, NULL);
    if (status != noErr) {
        switch (status) {
            case kVTInvalidSessionErr:
                //Invalid session, reset decoder session
                NSLog(@"decode error, Invalid session, reset decoder session");
                break;
            default:
                NSLog(@"decode error, status = %d", status);
                break;
        }
        goto failed;
    }
    goto failed;
failed:
    if (sampleBuffer) {    
        CFRelease(sampleBuffer);
    }
    
}



@end
