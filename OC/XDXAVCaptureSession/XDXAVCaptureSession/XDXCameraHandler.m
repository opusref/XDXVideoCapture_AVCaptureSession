//
//  XDXCameraHandler.m
//  XDXAVCaptureSession
//
//  Created by 李承阳 on 2019/4/6.
//  Copyright © 2019 小东邪. All rights reserved.
//

#import "XDXCameraHandler.h"
#import <UIKit/UIKit.h>

#import "XDXCameraModel.h"
#import "sys/utsname.h"

#define IPAD UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad     // if current device is ipad

typedef NS_ENUM(NSUInteger, TVUIPhoneType) {
    TVUIPhoneNone = 9999,
    TVUIPhone5 = 5,
    TVUIPhone5S,
    TVUIPhone6,
    TVUIPhone6S,
    TVUIPhone7,
    TVUIPhone8,
    TVUIPhoneX = 10,
    TVUIPhoneXR = 11,
    TVUIPhoneXS = 11,
    TVUIPhoneXSMAX = 11,
};

@interface XDXCameraHandler ()<AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate>

@property (nonatomic, strong) AVCaptureSession *session;
@property (nonatomic, strong) AVCaptureDeviceInput *input;
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *videoPreviewLayer;

@property (nonatomic, assign) int captureVideoFPS;

@end

@implementation XDXCameraHandler

#pragma mark - Public
- (void)startRunning {
    [self.session startRunning];
}

- (void)stopRunning {
    [self.session stopRunning];
}

- (void)switchCamera {
    [self switchCameraWithSession:self.session
                            input:self.input
                      videoFormat:self.cameraModel.videoFormat
                 resolutionHeight:self.cameraModel.resolutionHeight
                        frameRate:self.cameraModel.frameRate];
}

- (void)configureCameraWithModel:(XDXCameraModel *)model {
    self.cameraModel = model;
    
    NSError *error = nil;
    AVCaptureSession *session = [[AVCaptureSession alloc] init];
    self.session = session;
    
    // Set resolution
    session.sessionPreset = model.preset;
    
    // Set position of camera (front / back )
    AVCaptureDevice *device = [XDXCameraHandler getCaptureDevicePosition:model.position];
    
    // Set frame rate and resolution
    [XDXCameraHandler setCameraFrameRateAndResolutionWithFrameRate:model.frameRate
                                               andResolutionHeight:model.resolutionHeight
                                                         bySession:session
                                                          position:model.position
                                                       videoFormat:model.videoFormat];
    
    // Set torch mode
    if ([device hasTorch]) {
        [device lockForConfiguration:&error];
        if ([device isTorchModeSupported:model.torchMode]) {
            device.torchMode = model.torchMode;
            [device addObserver:self forKeyPath:@"torchMode" options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld context:nil];
        }else {
            NSLog(@"The device not support current torch mode : %ld!",model.torchMode);
        }
        [device unlockForConfiguration];
    }else {
        NSLog(@"The device not support torch!");
    }
    
    // Set focus mode
    if ([device isFocusModeSupported:model.focusMode]) {
        CGPoint autofocusPoint = CGPointMake(0.5f, 0.5f);
        [device setFocusPointOfInterest:autofocusPoint];
        [device setFocusMode:model.focusMode];
    }else {
        NSLog(@"The device not support current focus mode : %ld!",model.focusMode);
    }
    
    // Set exposure mode
    if ([device isExposureModeSupported:model.exposureMode]) {
        CGPoint exposurePoint = CGPointMake(0.5f, 0.5f);
        [device setExposurePointOfInterest:exposurePoint];
        [device setExposureMode:AVCaptureExposureModeContinuousAutoExposure];
    }else {
        NSLog(@"The device not support current exposure mode : %ld!",model.exposureMode);
    }
    
    // Set flash mode
    if ([device hasFlash]){
        if ([device isFlashModeSupported:model.flashMode]) {
            [device setFlashMode:model.flashMode];
        }else {
            NSLog(@"The device not support current flash mode : %ld!",model.flashMode);
        }
    }else {
        NSLog(@"The device not support flash!");
    }
    
    // Set white balance mode
    if ([device isWhiteBalanceModeSupported:model.whiteBalanceMode]) {
        [device setWhiteBalanceMode:model.whiteBalanceMode];
    }else {
        NSLog(@"The device not support current white balance mode : %ld!",model.whiteBalanceMode);
    }
    
    // Add input
    AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
    if (error != noErr) {
        NSLog(@"Configure device input failed:%@",error.localizedDescription);
        return;
    }
    
    self.input = input;
    [session addInput:input];
    
    // Conigure and add output
    AVCaptureVideoDataOutput *videoDataOutput = [[AVCaptureVideoDataOutput alloc] init];
    AVCaptureAudioDataOutput *audioDataOutput = [[AVCaptureAudioDataOutput alloc] init];
    [session addOutput:videoDataOutput];
    [session addOutput:audioDataOutput];
    
    videoDataOutput.videoSettings = [NSDictionary dictionaryWithObject:[NSNumber numberWithInt:model.videoFormat]
                                                                forKey:(id)kCVPixelBufferPixelFormatTypeKey];
    videoDataOutput.alwaysDiscardsLateVideoFrames = NO;
    
    // Use serial queue to receive audio / video data
    dispatch_queue_t videoQueue = dispatch_queue_create("videoQueue", NULL);
    dispatch_queue_t audioQueue = dispatch_queue_create("audioQueue", NULL);
    [audioDataOutput setSampleBufferDelegate:self queue:audioQueue];
    [videoDataOutput setSampleBufferDelegate:self queue:videoQueue];
    
    // Set video Stabilization
    if (model.isEnableVideoStabilization) {
        // iPhoneXS 在开启防抖旋转到UIDeviceOrientationLandscapeLeft时渲染会出错,故暂时关掉iPhone X以上机型的防抖功能
        if (![XDXCameraHandler getIsIpad]) {
            if ([XDXCameraHandler compareIsGreaterEqualDeviceNum:TVUIPhoneXS]) {
                [self adjustVideoStabilizationWithOutput:videoDataOutput];
            }
        }
    }
    
    // Set video preview
    CALayer *previewViewLayer = [model.previewView layer];
    
    AVCaptureVideoPreviewLayer *videoPreviewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:session];
    self.videoPreviewLayer = videoPreviewLayer;
    previewViewLayer.backgroundColor = [[UIColor blackColor] CGColor];
    CGRect frame = [previewViewLayer bounds];
    NSLog(@"previewViewLayer = %@",NSStringFromCGRect(frame));
    
    [videoPreviewLayer setFrame:model.previewView.frame];
    [videoPreviewLayer setVideoGravity:model.videoGravity];
    
    if([[videoPreviewLayer connection] isVideoOrientationSupported]) {
        [videoPreviewLayer.connection setVideoOrientation:model.videoOrientation];
    }else {
        NSLog(@"Not support video Orientation!");
    }
    
    [previewViewLayer insertSublayer:videoPreviewLayer atIndex:0];
}

- (void)setCameraResolutionByActiveFormatWithHeight:(int)height {
    int maxResolutionHeight = [self getMaxSupportResolutionByActiveFormat];
    if (height > maxResolutionHeight) {
        height = maxResolutionHeight;
        NSLog(@"%s: Auto adjust, current resolution height:%d > max height:%d",__func__,height,maxResolutionHeight);
    }
    
    self.cameraModel.resolutionHeight = height;

    [self.class setCameraFrameRateAndResolutionWithFrameRate:self.cameraModel.frameRate andResolutionHeight:height bySession:self.session position:self.cameraModel.position videoFormat:self.cameraModel.videoFormat];

}

- (int)getMaxSupportResolutionByActiveFormat {
    int maxSupportResolutionHeight = [self getDeviceSupportMaxResolutionByFrameRate:self.cameraModel.frameRate
                                                                           position:self.cameraModel.position
                                                                        videoFormat:self.cameraModel.videoFormat];
    return maxSupportResolutionHeight;
}

- (void)setCameraForHFRWithFrameRate:(int)frameRate {
    int maxFrameRate = [self getMaxFrameRateByCurrentResolution];
    
    if (frameRate > maxFrameRate) {
        NSLog(@"%s: Auto adjust, current frame rate:%d > max frame rate:%d",__func__,frameRate,maxFrameRate);
        frameRate = maxFrameRate;
    }
    
    self.cameraModel.frameRate = frameRate;
    [self.class setCameraFrameRateAndResolutionWithFrameRate:frameRate
                                         andResolutionHeight:self.cameraModel.resolutionHeight
                                                   bySession:self.session
                                                    position:self.cameraModel.position
                                                 videoFormat:self.cameraModel.videoFormat];
}

- (int)getMaxFrameRateByCurrentResolution {
    return [self.class getMaxFrameRateByCurrentResolutionWithResolutionHeight:self.cameraModel.resolutionHeight
                                                                     position:self.cameraModel.position
                                                                  videoFormat:self.cameraModel.videoFormat];
}

- (int)getCaputreViedeoFPS {
    return self.captureVideoFPS;
}


#pragma mark - Private
- (void)switchCameraWithSession:(AVCaptureSession *)session input:(AVCaptureDeviceInput *)input videoFormat:(OSType)videoFormat resolutionHeight:(CGFloat)resolutionHeight frameRate:(int)frameRate {
    if (input) {
        [session beginConfiguration];
        [session removeInput:input];
        
        AVCaptureDevicePosition newPosition = [[input device] position] == AVCaptureDevicePositionBack ? AVCaptureDevicePositionFront : AVCaptureDevicePositionBack;
        self.cameraModel.position = newPosition;
        AVCaptureDevice *device = device = [self.class getCaptureDevicePosition:newPosition];
        
        NSError *error = nil;
        AVCaptureDeviceInput *newInput = [AVCaptureDeviceInput deviceInputWithDevice:device
                                                                               error:&error];
        
        if (error != noErr) {
            NSLog(@"%s: error:%@",__func__, error.localizedDescription);
            return;
        }
        
        // 比如: 后置是4K, 前置最多支持2K,此时切换需要降级, 而如果不先把Input添加到session中,我们无法计算当前摄像头支持的最大分辨率
        session.sessionPreset = AVCaptureSessionPresetLow;
        if ([session canAddInput:newInput])  {
            self.input = newInput;
            [session addInput:newInput];
        }else {
            NSLog(@"%s: add input failed.",__func__);
            return;
        }
        
        int maxResolutionHeight = [self getMaxSupportResolutionByPreset];
        if (resolutionHeight > maxResolutionHeight) {
            resolutionHeight = maxResolutionHeight;
            self.cameraModel.resolutionHeight = resolutionHeight;
            NSLog(@"%s: Current support max resolution height = %d", __func__, maxResolutionHeight);
        }
        
        int maxFrameRate = [self getMaxFrameRateByCurrentResolution];
        if (frameRate > maxFrameRate) {
            frameRate = maxFrameRate;
            self.cameraModel.frameRate = frameRate;
            NSLog(@"%s: Current support max frame rate = %d",__func__, maxFrameRate);
        }

        BOOL isSuccess = [self.class setCameraFrameRateAndResolutionWithFrameRate:frameRate
                                                              andResolutionHeight:resolutionHeight
                                                                        bySession:session
                                                                         position:newPosition
                                                                      videoFormat:videoFormat];
        
        if (!isSuccess) {
            NSLog(@"%s: Set resolution and frame rate failed.",__func__);
        }
        
        [self.session commitConfiguration];
    }
}


+ (AVCaptureDevice *)getCaptureDevicePosition:(AVCaptureDevicePosition)position {
    NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    for (AVCaptureDevice *device in devices) {
        if (position == device.position) {
            return device;
        }
    }
    return NULL;
}

-(void)adjustVideoStabilizationWithOutput:(AVCaptureVideoDataOutput *)output {
    NSArray *devices = [AVCaptureDevice devices];
    for(AVCaptureDevice *device in devices){
        if([device hasMediaType:AVMediaTypeVideo]){
            if([device.activeFormat isVideoStabilizationModeSupported:AVCaptureVideoStabilizationModeAuto]){
                for(AVCaptureConnection *connection in output.connections) {
                    for(AVCaptureInputPort *port in [connection inputPorts]) {
                        if([[port mediaType] isEqual:AVMediaTypeVideo]) {
                            if(connection.supportsVideoStabilization) {
                                connection.preferredVideoStabilizationMode = AVCaptureVideoStabilizationModeStandard;
                                NSLog(@"activeVideoStabilizationMode = %ld",(long)connection.activeVideoStabilizationMode);
                            }else{
                                NSLog(@"connection don't support video stabilization");
                            }
                        }
                    }
                }
            }else{
                NSLog(@"device don't support video stablization");
            }
        }
    }
}

#pragma mark Resolution
- (int)getDeviceSupportMaxResolutionByFrameRate:(int)frameRate position:(AVCaptureDevicePosition)position videoFormat:(OSType)videoFormat {
    int maxResolutionHeight = 0;
    
    AVCaptureDevice *captureDevice = [self.class getCaptureDevicePosition:position];
    for(AVCaptureDeviceFormat *vFormat in [captureDevice formats]) {
        CMFormatDescriptionRef description = vFormat.formatDescription;
        float maxRate = ((AVFrameRateRange*) [vFormat.videoSupportedFrameRateRanges objectAtIndex:0]).maxFrameRate;
        CMVideoDimensions dims = CMVideoFormatDescriptionGetDimensions(description);
        if (CMFormatDescriptionGetMediaSubType(description) == videoFormat && frameRate <= maxRate) {
            if ([self.class getResolutionWidthByHeight:dims.height] == dims.width) {
                maxResolutionHeight = dims.height;
            }
        }
    }
    
    return maxResolutionHeight;
}

/******************************* Only Fit : Frame Rate < 30 *******************************************************/

- (int)getMaxSupportResolutionByPreset {
    AVCaptureSession *session = self.session;
    if ([session canSetSessionPreset:AVCaptureSessionPreset3840x2160]) {
        return 2160;
    }else if ([session canSetSessionPreset:AVCaptureSessionPreset1920x1080]) {
        return 1080;
    }else if ([session canSetSessionPreset:AVCaptureSessionPreset1280x720]) {
        return 720;
    }else if ([session canSetSessionPreset:AVCaptureSessionPreset640x480]) {
        return 480;
    }else if ([session canSetSessionPreset:AVCaptureSessionPreset352x288]) {
        return 288;
    }else {
        return -1;
    }
}

- (void)setCameraResolutionByPresetWithHeight:(int)height {
    AVCaptureSessionPreset preset = [self getSessionPresetByResolutionHeight:height];
    if ([self.session.sessionPreset isEqualToString:preset]) {
        NSLog(@"Needn't to set camera resolution repeatly !");
        return;
    }
    
    if (![self.session canSetSessionPreset:preset]) {
        NSLog(@"Can't set the sessionPreset !");
        return;
    }
    
    [self.session beginConfiguration];
    self.session.sessionPreset = preset;
    [self.session commitConfiguration];
}

- (AVCaptureSessionPreset)getSessionPresetByResolutionHeight:(int)resolutionHeight {
    switch (resolutionHeight) {
        case 2160:
            return AVCaptureSessionPreset3840x2160;
        case 1080:
            return AVCaptureSessionPreset1920x1080;
        case 720:
            return AVCaptureSessionPreset1280x720;
        case 480:
            return AVCaptureSessionPreset640x480;
        default:
            return AVCaptureSessionPreset1280x720;
    }
}

+ (int)getResolutionWidthByHeight:(int)height {
    switch (height) {
        case 2160:
            return 3840;
        case 1080:
            return 1920;
        case 720:
            return 1280;
        case 480:
            return 640;
        default:
            return -1;
    }
}



#pragma mark FPS
// Only for frame rate <= 30
- (void)setCameraForLFRWithFrameRate:(int)frameRate {
    AVCaptureDevice *captureDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    [captureDevice lockForConfiguration:NULL];
    [captureDevice setActiveVideoMinFrameDuration:CMTimeMake(1, frameRate)];
    [captureDevice setActiveVideoMaxFrameDuration:CMTimeMake(1, frameRate)];
    [captureDevice unlockForConfiguration];
}

+ (BOOL)setCameraFrameRateAndResolutionWithFrameRate:(int)frameRate andResolutionHeight:(CGFloat)resolutionHeight bySession:(AVCaptureSession *)session position:(AVCaptureDevicePosition)position videoFormat:(OSType)videoFormat {
    AVCaptureDevice *captureDevice = [self getCaptureDevicePosition:position];
    
    BOOL isSuccess = NO;
    for(AVCaptureDeviceFormat *vFormat in [captureDevice formats]) {
        CMFormatDescriptionRef description = vFormat.formatDescription;
        float maxRate = ((AVFrameRateRange*) [vFormat.videoSupportedFrameRateRanges objectAtIndex:0]).maxFrameRate;
        if (maxRate >= frameRate && CMFormatDescriptionGetMediaSubType(description) == videoFormat) {
            if ([captureDevice lockForConfiguration:NULL] == YES) {
                // 对比镜头支持的分辨率和当前设置的分辨率
                CMVideoDimensions dims = CMVideoFormatDescriptionGetDimensions(description);
                if (dims.height == resolutionHeight && dims.width == [self getResolutionWidthByHeight:resolutionHeight]) {
                    [session beginConfiguration];
                    if ([captureDevice lockForConfiguration:NULL]){
                        captureDevice.activeFormat = vFormat;
                        [captureDevice setActiveVideoMinFrameDuration:CMTimeMake(1, frameRate)];
                        [captureDevice setActiveVideoMaxFrameDuration:CMTimeMake(1, frameRate)];
                        [captureDevice unlockForConfiguration];
                    }
                    [session commitConfiguration];
                    
                    return YES;
                }
            }else {
                NSLog(@"%s: lock failed!",__func__);
            }
        }
    }
    
    NSLog(@"Set camera frame is success : %d, frame rate is %lu, resolution height = %f",isSuccess,(unsigned long)frameRate,resolutionHeight);
    return NO;
}

+ (int)getMaxFrameRateByCurrentResolutionWithResolutionHeight:(int)resolutionHeight position:(AVCaptureDevicePosition)position videoFormat:(OSType)videoFormat {
    int maxFrameRate = 0;
    
    AVCaptureDevice *captureDevice = [self getCaptureDevicePosition:position];
    for(AVCaptureDeviceFormat *vFormat in [captureDevice formats]) {
        CMFormatDescriptionRef description = vFormat.formatDescription;
        CMVideoDimensions dims = CMVideoFormatDescriptionGetDimensions(description);
        if (CMFormatDescriptionGetMediaSubType(description) == videoFormat && dims.height == resolutionHeight && dims.width == [self getResolutionWidthByHeight:resolutionHeight]) {
            float maxRate = vFormat.videoSupportedFrameRateRanges.firstObject.maxFrameRate;
            if (maxRate > maxFrameRate) {
                maxFrameRate = maxRate;
            }
        }
    }
    
    return maxFrameRate;
}

- (void)calculatorCaptureFPS {
    static int count = 0;
    static float lastTime = 0;
    CMClockRef hostClockRef = CMClockGetHostTimeClock();
    CMTime hostTime = CMClockGetTime(hostClockRef);
    float nowTime = CMTimeGetSeconds(hostTime);
    if(nowTime - lastTime >= 1) {
        self.captureVideoFPS = count;
        lastTime = nowTime;
        count = 0;
    }else {
        count ++;
    }
}

#pragma mark Other
- (void)setFocusPoint:(CGPoint)point {
    CGPoint convertedFocusPoint = [self convertToPointOfInterestFromViewCoordinates:point];
    NSLog(@"Focus point: %@",NSStringFromCGPoint(point));
    [self autoFocusAtPoint:convertedFocusPoint];
}

- (CGPoint)convertToPointOfInterestFromViewCoordinates:(CGPoint)viewCoordinates {
    AVCaptureVideoPreviewLayer *captureVideoPreviewLayer = self.videoPreviewLayer;
    CGPoint pointOfInterest = CGPointMake(.5f, .5f);
    
    CGSize frameSize = [captureVideoPreviewLayer frame].size;
    
    if ([captureVideoPreviewLayer.connection isVideoMirrored]) {
        viewCoordinates.x = frameSize.width - viewCoordinates.x;
    }
    
    CGRect cleanAperture;
    for (AVCaptureInputPort *port in [self.input ports]) {
        if ([port mediaType] == AVMediaTypeVideo) {
            cleanAperture = CMVideoFormatDescriptionGetCleanAperture([port formatDescription], YES);
            CGSize apertureSize = cleanAperture.size;
            CGPoint point = viewCoordinates;
            
            CGFloat apertureRatio = apertureSize.height / apertureSize.width;
            CGFloat viewRatio = frameSize.width / frameSize.height;
            CGFloat xc = .5f;
            CGFloat yc = .5f;
            
            if ( [[captureVideoPreviewLayer videoGravity] isEqualToString:AVLayerVideoGravityResize] ) {
                // Scale, switch x and y, and reverse x
                pointOfInterest = CGPointMake(viewCoordinates.y / frameSize.height, 1.f - (viewCoordinates.x / frameSize.width));
            } else if ([[captureVideoPreviewLayer videoGravity] isEqualToString:AVLayerVideoGravityResizeAspect]) {
                if (viewRatio > apertureRatio) {
                    CGFloat y2 = frameSize.height;
                    CGFloat x2 = frameSize.height * apertureRatio;
                    CGFloat x1 = frameSize.width;
                    CGFloat blackBar = (x1 - x2) / 2;
                    // If point is inside letterboxed area, do coordinate conversion; otherwise, don't change the default value returned (.5,.5)
                    if (point.x >= blackBar && point.x <= blackBar + x2) {
                        // Scale (accounting for the letterboxing on the left and right of the video preview), switch x and y, and reverse x
                        xc = point.y / y2;
                        yc = 1.f - ((point.x - blackBar) / x2);
                    }
                } else {
                    CGFloat y2 = frameSize.width / apertureRatio;
                    CGFloat y1 = frameSize.height;
                    CGFloat x2 = frameSize.width;
                    CGFloat blackBar = (y1 - y2) / 2;
                    // If point is inside letterboxed area, do coordinate conversion. Otherwise, don't change the default value returned (.5,.5)
                    if (point.y >= blackBar && point.y <= blackBar + y2) {
                        // Scale (accounting for the letterboxing on the top and bottom of the video preview), switch x and y, and reverse x
                        xc = ((point.y - blackBar) / y2);
                        yc = 1.f - (point.x / x2);
                    }
                }
            } else if ([[captureVideoPreviewLayer videoGravity] isEqualToString:AVLayerVideoGravityResizeAspectFill]) {
                // Scale, switch x and y, and reverse x
                if (viewRatio > apertureRatio) {
                    CGFloat y2 = apertureSize.width * (frameSize.width / apertureSize.height);
                    xc = (point.y + ((y2 - frameSize.height) / 2.f)) / y2; // Account for cropped height
                    yc = (frameSize.width - point.x) / frameSize.width;
                } else {
                    CGFloat x2 = apertureSize.height * (frameSize.height / apertureSize.width);
                    yc = 1.f - ((point.x + ((x2 - frameSize.width) / 2)) / x2); // Account for cropped width
                    xc = point.y / frameSize.height;
                }
            }
            
            pointOfInterest = CGPointMake(xc, yc);
            break;
        }
    }
    return pointOfInterest;
}

- (void)autoFocusAtPoint:(CGPoint)point {
    AVCaptureDevice *device = self.input.device;
    if ([device isFocusPointOfInterestSupported] && [device isFocusModeSupported:AVCaptureFocusModeAutoFocus]) {
        NSError *error;
        if ([device lockForConfiguration:&error]) {
            [device setExposurePointOfInterest:point];
            [device setExposureMode:AVCaptureExposureModeContinuousAutoExposure];
            [device setFocusPointOfInterest:point];
            [device setFocusMode:AVCaptureFocusModeAutoFocus];
            [device unlockForConfiguration];
        } else {
            
        }
    }
}

#pragma mark - Delegate
- (void)captureOutput:(AVCaptureOutput *)output didDropSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    if ([output isKindOfClass:[AVCaptureVideoDataOutput class]] == YES) {
        NSLog(@"Error: Drop video frame");
    }else {
        NSLog(@"Error: Drop audio frame");
    }
    
    if ([self.delegate respondsToSelector:@selector(xdxCaptureOutput:didDropSampleBuffer:fromConnection:)]) {
        [self.delegate xdxCaptureOutput:output didDropSampleBuffer:sampleBuffer fromConnection:connection];
    }
}

- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    if(!CMSampleBufferDataIsReady(sampleBuffer)) {
        NSLog( @"sample buffer is not ready. Skipping sample" );
        return;
    }
    
    if ([output isKindOfClass:[AVCaptureVideoDataOutput class]] == YES) {
        [self calculatorCaptureFPS];
        // NSLog(@"capture: video data");
    }else if ([output isKindOfClass:[AVCaptureAudioDataOutput class]] == YES) {
        // NSLog(@"capture: audio data");
    }
    
    if ([self.delegate respondsToSelector:@selector(xdxCaptureOutput:didOutputSampleBuffer:fromConnection:)]) {
        [self.delegate xdxCaptureOutput:output didOutputSampleBuffer:sampleBuffer fromConnection:connection];
    }
}

#pragma mark - KVO
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
    if ([keyPath isEqualToString:@"torchMode"]) {
        if ([change objectForKey:NSKeyValueChangeNewKey] != nil) {
            //            [self adjustFlash:[[change objectForKey:NSKeyValueChangeNewKey] intValue]];
        }
    }
}

#pragma mark - Other
+ (BOOL)compareIsGreaterEqualDeviceNum:(TVUIPhoneType)iPhoneType {
    if ([self getIsIpad]) {
        return NO;
    }
    
    struct utsname systemInfo;
    uname(&systemInfo);
    NSString    *deviceModel = [NSString stringWithCString:systemInfo.machine encoding:NSUTF8StringEncoding];
    NSUInteger  typeCode;
    NSString    *originLocStr;
    
    originLocStr = [deviceModel substringFromIndex:6];    // cut iphone
    
    NSRange rangeComma      = [originLocStr  rangeOfString:@","];
    NSString *typeCodeStr   = [originLocStr  substringToIndex:rangeComma.location];
    typeCode                = [typeCodeStr   integerValue];
    
    // Compare iphone by type code ,ex :iPhone9,1 is iPhone 7;
    if (typeCode >= iPhoneType) {
        return YES;
    }else {
        return NO;
    }
    
}

//如果想要判断设备是ipad，要用如下方法
+ (BOOL)getIsIpad {
    NSString *deviceType = [UIDevice currentDevice].model;
    
    if([deviceType isEqualToString:@"iPhone"]) {
        //iPhone
        return NO;
    }
    else if([deviceType isEqualToString:@"iPod touch"]) {
        //iPod Touch
        return NO;
    }
    else if([deviceType isEqualToString:@"iPad"]) {
        //iPad
        return YES;
    }
    return NO;
}

@end