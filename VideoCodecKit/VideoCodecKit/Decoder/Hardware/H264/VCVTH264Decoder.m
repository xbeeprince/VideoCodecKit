//
//  VCVTH264Decoder.m
//  VideoCodecKitDemo
//
//  Created by CmST0us on 2018/9/22.
//  Copyright © 2018年 eric3u. All rights reserved.
//

#import <VideoToolbox/VideoToolbox.h>
#import <pthread.h>
#import "VCVTH264Decoder.h"
#import "VCH264Frame.h"
#import "VCYUV420PImage.h"
#import "VCPriorityObjectQueue.h"
#import "VCH264SPSFrame.h"
@interface VCVTH264Decoder () {
    CMVideoFormatDescriptionRef _videoFormatDescription;
    VTDecompressionSessionRef _decodeSession;
    
    uint8_t *_sps;
    size_t _spsSize;
    uint8_t *_pps;
    size_t _ppsSize;
    uint8_t *_sei;
    size_t _seiSize;
    NSInteger _startCodeSize;
    
    BOOL _isVideoFormatDescriptionUpdate;
    BOOL _hasSEI;
    
    pthread_mutex_t _decoderLock;
}

@end

@implementation VCVTH264Decoder

static void decompressionOutputCallback(void *decompressionOutputRefCon,
                                        void *sourceFrameRefCon,
                                        OSStatus status,
                                        VTDecodeInfoFlags infoFlags,
                                        CVImageBufferRef imageBuffer,
                                        CMTime presentationTimeStamp,
                                        CMTime presentationDuration) {
    CVPixelBufferRef *outputPixelBuffer = (CVPixelBufferRef *)sourceFrameRefCon;
    *outputPixelBuffer = CVPixelBufferRetain(imageBuffer);
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _videoFormatDescription = NULL;
        _decodeSession = NULL;
        _spsSize = 0;
        _ppsSize = 0;
        _seiSize = 0;
        
        pthread_mutex_init(&_decoderLock, NULL);
        _hasSEI = NO;
        _isVideoFormatDescriptionUpdate = NO;
    }
    return self;
}

- (void)dealloc {
    [self freeSPS];
    [self freePPS];
    [self freeSEI];
    
    [self freeVideoFormatDescription];
    [self freeDecodeSession];
    pthread_mutex_destroy(&_decoderLock);
}

#pragma mark - Decoder Public Method
- (BOOL)setup {
    if ([super setup]) {
        pthread_mutex_lock(&_decoderLock);
        [self commitStateTransition];
        pthread_mutex_unlock(&_decoderLock);
        return YES;
    }
    [self rollbackStateTransition];
    return NO;
}

- (BOOL)invalidate {
    if ([super invalidate]) {
        pthread_mutex_lock(&_decoderLock);
        [self commitStateTransition];
        
        [self freeDecodeSession];
        [self freeVideoFormatDescription];
        [self freeSPS];
        [self freePPS];
        [self freeSEI];
        pthread_mutex_unlock(&_decoderLock);
        return YES;
    }
    [self rollbackStateTransition];
    return NO;
}

#pragma mark - Decoder Private Method

- (void)freeDecodeSession {
    if (_decodeSession != NULL) {
        VTDecompressionSessionInvalidate(_decodeSession);
        CFRelease(_decodeSession);
        _decodeSession = NULL;
    }
}

- (void)freeVideoFormatDescription {
    if (_videoFormatDescription != NULL) {
        CFRelease(_videoFormatDescription);
        _videoFormatDescription = NULL;
    }
}

- (void)freeSPS {
    if (_sps != NULL) {
        free(_sps);
        _sps = NULL;
        _spsSize = 0;
    }
}

- (void)freePPS {
    if (_pps != NULL) {
        free(_pps);
        _pps = NULL;
        _ppsSize = 0;
    }
}

- (void)freeSEI {
    if (_sei != NULL) {
        free(_sei);
        _sei = NULL;
        _seiSize = 0;
    }
}

- (BOOL)setupVideoFormatDescription {
    [self freeVideoFormatDescription];
    
    const uint8_t *para[3] = {_sps, _pps, _sei};
    const size_t paraSize[3] = {_spsSize, _ppsSize, _seiSize};
    
    OSStatus ret = CMVideoFormatDescriptionCreateFromH264ParameterSets(kCFAllocatorDefault,
                                                                       _hasSEI ? 2 : 2,
                                                                       para,
                                                                       paraSize,
                                                                       4,
                                                                       &_videoFormatDescription);
    if (ret == 0) {
        return YES;
    }
    return NO;
}

- (BOOL)setupDecompressionSession {
    if (_videoFormatDescription == NULL) return NO;
    [self freeDecodeSession];
    
    //get width and height of video
    CMVideoDimensions dimension = CMVideoFormatDescriptionGetDimensions (_videoFormatDescription);
    
    // Set the pixel attributes for the destination buffer
    CFMutableDictionaryRef destinationPixelBufferAttributes = CFDictionaryCreateMutable(
                                                                                        kCFAllocatorDefault,
                                                                                        0,
                                                                                        &kCFTypeDictionaryKeyCallBacks,
                                                                                        &kCFTypeDictionaryValueCallBacks);
    
    SInt32 destinationPixelType = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange;
    
    CFNumberRef pixelType = CFNumberCreate(NULL, kCFNumberSInt32Type, &destinationPixelType);
    CFDictionarySetValue(destinationPixelBufferAttributes,kCVPixelBufferPixelFormatTypeKey, pixelType);
    CFRelease(pixelType);
    
    CFNumberRef width = CFNumberCreate(NULL, kCFNumberSInt32Type, &dimension.width);
    CFDictionarySetValue(destinationPixelBufferAttributes,kCVPixelBufferWidthKey, width);
    CFRelease(width);
    
    CFNumberRef height = CFNumberCreate(NULL, kCFNumberSInt32Type, &dimension.height);
    CFDictionarySetValue(destinationPixelBufferAttributes, kCVPixelBufferHeightKey, height);
    CFRelease(height);
    
//    CFDictionarySetValue(destinationPixelBufferAttributes, kCVPixelBufferOpenGLCompatibilityKey, kCFBooleanTrue);
    
    VTDecompressionOutputCallbackRecord callbackRecord;
    callbackRecord.decompressionOutputCallback = decompressionOutputCallback;
    callbackRecord.decompressionOutputRefCon = NULL;
    
    OSStatus ret = VTDecompressionSessionCreate(kCFAllocatorDefault,
                                 _videoFormatDescription,
                                 NULL,
                                 destinationPixelBufferAttributes,
                                 &callbackRecord,
                                 &_decodeSession);
    CFRelease(destinationPixelBufferAttributes);
    
    if (ret == 0) {
        return YES;
    }
    return NO;
}

- (void)tryUseSPS:(uint8_t *)spsData length:(size_t)length {
    
    if (spsData != NULL && _sps != NULL && memcmp(spsData, _sps, length) == 0) {
        // same
        return;
    }
    
    [self freeSPS];
    
    _spsSize = length;
    _sps = (uint8_t *)malloc(_spsSize);
    memcpy(_sps, spsData, _spsSize);
    _isVideoFormatDescriptionUpdate = YES;
}

- (void)tryUsePPS:(uint8_t *)ppsData length:(size_t)length {
    if (ppsData != NULL && _pps != NULL && memcmp(ppsData, _pps, length) == 0) {
        // same
        return;
    }
    
    [self freePPS];
    
    _ppsSize = length;
    _pps = (uint8_t *)malloc(_ppsSize);
    memcpy(_pps, ppsData, _ppsSize);
    _isVideoFormatDescriptionUpdate = YES;
}

- (void)tryUseSEI:(uint8_t *)seiData length:(size_t)length {
    if (seiData != NULL && _sei != NULL && memcmp(seiData, _sei, length) == 0) {
        // same
        return;
    }

    [self freeSEI];
    
    _seiSize = length;
    _sei = (uint8_t *)malloc(_seiSize);
    memcpy(_sei, seiData, _seiSize);
    _isVideoFormatDescriptionUpdate = YES;
    _hasSEI = YES;
}

- (NSArray *)extractKeyFrame:(VCH264Frame *)frame {
    if (!frame.isKeyFrame){
        return nil;
    }
    
    NSMutableArray *frames = [NSMutableArray array];
    NSMutableDictionary *offsetDict = [NSMutableDictionary dictionary];
    NSInteger lastIndex = 0;
    for (NSInteger i = frame.startCodeSize; i < frame.parseSize - 4; i++) {
        static uint8_t startCode1[4] = {0x00, 0x00, 0x00, 0x01};
        static uint8_t startCode2[3] = {0x00, 0x00, 0x01};
        if (memcmp(frame.parseData + i, startCode1, sizeof(startCode1)) == 0) {
            offsetDict[@(lastIndex)] = @(i - lastIndex);
            lastIndex = i;
            i += 3;
        }
        if(memcmp(frame.parseData + i, startCode2, sizeof(startCode2)) == 0) {
            offsetDict[@(lastIndex)] = @(i - lastIndex);
            lastIndex = i;
            i += 3;
        }
    }
    
    if (lastIndex < frame.parseSize) {
        offsetDict[@(lastIndex)] = @(frame.parseSize - lastIndex);
    }
    
    NSArray *sortOffsetKeys = [offsetDict.allKeys sortedArrayUsingComparator:^NSComparisonResult(id  _Nonnull obj1, id  _Nonnull obj2) {
        if ([obj1 integerValue] > [obj2 integerValue]) return NSOrderedDescending;
        if ([obj1 integerValue] < [obj2 integerValue]) return NSOrderedAscending;
        return NSOrderedSame;
    }];
    
    for (NSNumber *offset in sortOffsetKeys) {
        NSNumber *size = offsetDict[offset];
        VCH264Frame *f = [[VCH264Frame alloc] initWithWidth:frame.width height:frame.height];
        [f createParseDataWithSize:size.integerValue];
        memcpy(f.parseData, frame.parseData + offset.integerValue, size.integerValue);
        
        f.frameType = [VCH264Frame getFrameType:f];
        // check if frame is sps
        if (f.frameType == VCH264FrameTypeSPS) {
            f = [[VCH264SPSFrame alloc] initWithWidth:frame.width height:frame.height];
            [f createParseDataWithSize:size.integerValue];
            memcpy(f.parseData, frame.parseData + offset.integerValue, size.integerValue);
            f.frameType = [VCH264Frame getFrameType:f];
        }
        
        f.frameIndex = frame.frameIndex;
        f.pts = frame.pts;
        f.dts = frame.dts;
        f.isKeyFrame = NO;
        [frames addObject:f];
    }
    return frames;
}

- (VCBaseImage *)decode:(VCBaseFrame *)frame {
    if (self.currentState.unsignedIntegerValue != VCBaseCodecStateRunning) return nil;
    
    if (![[frame class] isSubclassOfClass:[VCH264Frame class]]) return nil;
    
    VCH264Frame *decodeFrame = (VCH264Frame *)frame;
    
    if (decodeFrame.startCodeSize < 0) return nil;
    
    pthread_mutex_lock(&_decoderLock);
    
    _startCodeSize = decodeFrame.startCodeSize;
    if (_startCodeSize == 3) {
        decodeFrame.parseData -= 1;
        decodeFrame.parseSize += 1;
        decodeFrame.startCodeSize = 4;
        _startCodeSize = 4;
    }
    
    uint32_t nalSize = (uint32_t)(decodeFrame.parseSize - _startCodeSize);
    uint32_t *pNalSize = (uint32_t *)decodeFrame.parseData;
    *pNalSize = CFSwapInt32HostToBig(nalSize);
    
    if (decodeFrame.frameType == VCH264FrameTypeSPS) {
        // copy sps
        VCH264SPSFrame *spsFrame = (VCH264SPSFrame *)frame;
        _currentSPSFrame = spsFrame;
        self.fps = _currentSPSFrame.fps;
        [self tryUseSPS:spsFrame.parseData + _startCodeSize length:nalSize];
        pthread_mutex_unlock(&_decoderLock);
        return nil;
    } else if (decodeFrame.frameType == VCH264FrameTypePPS) {
        // copy pps
        [self tryUsePPS:decodeFrame.parseData + _startCodeSize length:nalSize];
        pthread_mutex_unlock(&_decoderLock);
        return nil;
    } else if (decodeFrame.frameType == VCH264FrameTypeSEI) {
        // copy sei
        [self tryUseSEI:decodeFrame.parseData + _startCodeSize length:nalSize];
        pthread_mutex_unlock(&_decoderLock);
        return nil;
    }
    
    if (decodeFrame.frameType == VCH264FrameTypeIDR) {
        if (_isVideoFormatDescriptionUpdate) {
            if (![self setupVideoFormatDescription]) {
                _isVideoFormatDescriptionUpdate = YES;
            } else {
                if ([self setupDecompressionSession]) {
                    _isVideoFormatDescriptionUpdate = NO;
                }
            }
        }
    }
    
    if (_videoFormatDescription == NULL) {
        pthread_mutex_unlock(&_decoderLock);
        return nil;
    }
    
    // decode process
    CMBlockBufferRef blockBuffer = NULL;
    CVPixelBufferRef outputPixelBuffer = NULL;
    OSStatus ret = CMBlockBufferCreateWithMemoryBlock(kCFAllocatorDefault,
                                                      decodeFrame.parseData,
                                                      decodeFrame.parseSize,
                                                      kCFAllocatorNull,
                                                      NULL,
                                                      0,
                                                      decodeFrame.parseSize,
                                                      0,
                                                      &blockBuffer);
    if (ret == kCMBlockBufferNoErr) {
        // decode success
        CMSampleBufferRef sampleBuffer = NULL;
        const size_t sampleSizeArray[] = {decodeFrame.parseSize};
        
        ret = CMSampleBufferCreateReady(kCFAllocatorDefault,
                                        blockBuffer,
                                        _videoFormatDescription,
                                        1,
                                        0,
                                        NULL,
                                        1,
                                        sampleSizeArray,
                                        &sampleBuffer);
        
        if (ret == kCMBlockBufferNoErr && sampleBuffer) {
            VTDecodeFrameFlags flags = 0;
            VTDecodeInfoFlags flagOut = 0;
            OSStatus decodeStatus = VTDecompressionSessionDecodeFrame(_decodeSession,
                                                                      sampleBuffer,
                                                                      flags,
                                                                      &outputPixelBuffer,
                                                                      &flagOut);
            if (decodeStatus == kVTInvalidSessionErr) {
                [self setupDecompressionSession];
            }
            CFRelease(sampleBuffer);
            sampleBuffer = NULL;
        }
        CFRelease(blockBuffer);
        blockBuffer = NULL;
    }
    
    if (outputPixelBuffer == NULL) {
        pthread_mutex_unlock(&_decoderLock);
        return nil;
    }
    
    VCYUV420PImage *image = [[VCYUV420PImage alloc] initWithWidth:decodeFrame.width height:decodeFrame.height];
    [image.userInfo setObject:@(decodeFrame.frameIndex) forKey:kVCBaseImageUserInfoFrameIndexKey];
    if (decodeFrame.frameType == VCH264FrameTypeIDR) {
        [image.userInfo setObject:@(kVCPriorityIDR) forKey:kVCBaseImageUserInfoFrameIndexKey];
    }
    
    [image setPixelBuffer:outputPixelBuffer];
    
    CVPixelBufferRelease(outputPixelBuffer);
    pthread_mutex_unlock(&_decoderLock);
    return image;
}

- (void)decodeWithFrame:(VCBaseFrame *)frame {
    if (self.currentState.unsignedIntegerValue != VCBaseCodecStateRunning) return;
    if (![[frame class] isSubclassOfClass:[VCH264Frame class]]) return;
    VCH264Frame *decodeFrame = (VCH264Frame *)frame;
    if (decodeFrame.startCodeSize < 0) return;
    
    // check is key frame
    if (decodeFrame.isKeyFrame) {
        NSArray *array = [self extractKeyFrame:decodeFrame];
        [array enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            VCBaseImage * image = [self decode:obj];
            if (image != NULL) {
                if (self.delegate && [self.delegate respondsToSelector:@selector(decoder:didProcessImage:)]) {
                    [self.delegate decoder:self didProcessImage:image];
                }
            }
        }];
    } else {
        VCBaseImage * image = [self decode:frame];
        if (image != NULL) {
            if (self.delegate && [self.delegate respondsToSelector:@selector(decoder:didProcessImage:)]) {
                [self.delegate decoder:self didProcessImage:image];
            }
        }
    }
}

- (void)decodeFrame:(VCBaseFrame *)frame completion:(void (^)(VCBaseImage *))block {
    if (self.currentState.unsignedIntegerValue != VCBaseCodecStateRunning) return;
    if (![[frame class] isSubclassOfClass:[VCH264Frame class]]) return;
    VCH264Frame *decodeFrame = (VCH264Frame *)frame;
    if (decodeFrame.startCodeSize < 0) return;
    
    // check is key frame
    if (decodeFrame.isKeyFrame) {
        NSArray *array = [self extractKeyFrame:decodeFrame];
        [array enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            VCBaseImage * image = [self decode:obj];
            if (image != NULL) {
                if (block) {
                    block(image);
                }
            }
        }];
    } else {
        VCBaseImage * image = [self decode:frame];
        if (image != NULL) {
            if (block) {
                block(image);
            }
        }
    }
}

@end
