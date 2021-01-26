# learn-ffmpeg

1. 用 `AVCaptureSession`采集nv12
2. ffmpeg+x264, 编码nv12生成h264,通过ffmpeg+x264进行软件解码为yuv420p，通过`libyuv`将yuv420p转为nv12，使用`AVSampleBufferDisplayLayer`来渲染nv12数据
3. ffmpeg+videotoolbox进行硬件编解码h264,使用`AVSampleBufferDisplayLayer`来渲染
4. 封装使用原生的videotoolbox来进行h264编解码


## 测试ffmpeg,修改以下参数切换软硬件编解码
> RZCodec.h
```
//是否开启硬件编码
#define USE_HW_ENCODER 1
//是否开启硬件解码
#define USE_HW_DECODER 1
```
