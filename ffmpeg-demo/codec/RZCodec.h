//
//  RZCodec.h
//  ffmpeg-demo
//
//  Created by yxibng on 2021/1/20.
//

#ifndef RZCodec_h
#define RZCodec_h


//是否开启硬件编码
#define USE_HW_ENCODER 1
//是否开启硬件解码
#define USE_HW_DECODER 1

#define kYUVElementMaxCount 8

typedef enum : NSUInteger {
    RZYUVTypeNV12,//2 平面
    RZYUVTypeI420,//3 平面
} RZYUVType;


#endif /* RZCodec_h */
