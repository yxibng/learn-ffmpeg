//
//  DbyVideoDisplayView.h
//  DbyPaas_iOS
//
//  Created by yxibng on 2019/10/16.
//
#import <TargetConditionals.h>
#if TARGET_OS_IOS
#import <UIKit/UIKit.h>
typedef UIView VIEW_CLASS;
typedef UIColor COLOR_CLASS;
#elif TARGET_OS_OSX
#import <AppKit/AppKit.h>
typedef NSView VIEW_CLASS;
typedef NSColor COLOR_CLASS;
#endif

#import <CoreVideo/CoreVideo.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RZVideoPlayView : VIEW_CLASS

@property (nonatomic, weak) VIEW_CLASS *canvas;
@property (nonatomic, copy) AVLayerVideoGravity gravity;

- (void)displayPixelBuffer:(CVPixelBufferRef)pixelBuffer;

- (void)displayI420:(void *)i420 frameWidth:(int)width frameHeight:(int)height;
- (void)displayNV12:(void *)nv12 frameWidth:(int)width frameHeight:(int)height;


- (void)displayI420:(void *)y
                  u:(void *)u
                  v:(void *)v
           stride_y:(int)stride_y
           stride_u:(int)stride_u
           stride_v:(int)stride_v
              width:(int)width
             height:(int)height;



@end

NS_ASSUME_NONNULL_END
