//
//  VCFLVTag.h
//  VideoCodecKit
//
//  Created by CmST0us on 2019/1/30.
//  Copyright © 2019 eric3u. All rights reserved.
//

#import <Foundation/Foundation.h>

#define kVCFLVTagHeaderSize (11)
#define kVCFLVVideoTagExternHeaderSize (5)
#define kVCFLVAudioTagExternHeaderSize (2)
#define kVCFLVMetaTagExternHeaderSize (0)

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(uint8_t, VCFLVTagType) {
    VCFLVTagTypeAudio = 8,
    VCFLVTagTypeVideo = 9,
    VCFLVTagTypeMeta = 18,
    VCFLVTagReserve = 0,
};

@interface VCFLVTag : NSObject
@property (nonatomic, readonly) NSData *tagData;

@property (nonatomic, readonly) VCFLVTagType tagType;
@property (nonatomic, readonly) uint32_t dataSize;
@property (nonatomic, readonly) uint32_t timestamp;
@property (nonatomic, readonly) uint8_t timestampExtended;
@property (nonatomic, readonly) uint32_t streamID;
@property (nonatomic, readonly) NSData *payloadData;

- (nullable instancetype)initWithData:(NSData *)data;
- (uint32_t)extendedTimeStamp;
@end

typedef NS_ENUM(uint8_t, VCFLVVideoTagFrameType) {
    VCFLVVideoTagFrameTypeKeyFrame = 1,
    VCFLVVideoTagFrameTypeInterFrame = 2,
    VCFLVVideoTagFrameTypeDisposableInterFrame = 3,
    VCFLVVideoTagFrameTypeGeneratedKeyFrame = 4,
    VCFLVVideoTagFrameTypeVideoInfoFrame = 5,
};

typedef NS_ENUM(uint8_t, VCFLVVideoTagEncodeID) {
    VCFLVVideoTagEncodeIDJPEG = 1,
    VCFLVVideoTagEncodeIDH263 = 2,
    VCFLVVideoTagEncodeIDScreenVideo = 3,
    VCFLVVideoTagEncodeIDOn2VP6 = 4,
    VCFLVVideoTagEncodeIDOn2VP6WithAlpha = 5,
    VCFLVVideoTagEncodeIDScreenVideoVersion2 = 6,
    VCFLVVideoTagEncodeIDAVC = 7,
};

typedef NS_ENUM(uint8_t, VCFLVVideoTagAVCPacketType) {
    VCFLVVideoTagAVCPacketTypeSequenceHeader = 0,
    VCFLVVideoTagAVCPacketTypeNALU = 1,
    VCFLVVideoTagAVCPacketTypeEndOfSequence = 2,
};

@interface VCFLVVideoTag : VCFLVTag
@property (nonatomic, readonly) VCFLVVideoTagFrameType frameType;
@property (nonatomic, readonly) VCFLVVideoTagEncodeID encodeID;
@property (nonatomic, readonly) VCFLVVideoTagAVCPacketType AVCPacketType;
@property (nonatomic, readonly) uint32_t compositionTime;
- (BOOL)isSupportCurrentFrameType;
- (uint32_t)presentationTimeStamp;
@end

typedef NS_ENUM(uint8_t, VCFLVAudioTagFormatType) {
    VCFLVAudioTagFormatTypeLinearPCMPlatformEndian = 0,
    VCFLVAudioTagFormatTypeADPCM = 1,
    VCFLVAudioTagFormatTypeMP3 = 2,
    VCFLVAudioTagFormatTypeLinearPCMLittleEndian = 3,
    VCFLVAudioTagFormatTypeNellymoser16kHzMono = 4,
    VCFLVAudioTagFormatTypeNellymoser8kHzMono = 5,
    VCFLVAudioTagFormatTypeNellymoser = 6,
    VCFLVAudioTagFormatTypeG711ALaw = 7,
    VCFLVAudioTagFormatTypeG711MuLaw = 8,
    VCFLVAudioTagFormatTypeReserved = 9,
    VCFLVAudioTagFormatTypeAAC = 10,
    VCFLVAudioTagFormatTypeSpeex = 11,
    VCFLVAudioTagFormatTypeMP38kHz = 14,
    VCFLVAudioTagFormatTypeDeviceSpecificSound = 15,
};

typedef NS_ENUM(uint8_t, VCFLVAudioTagSampleRate) {
    VCFLVAudioTagSampleRate5k5Hz = 0,
    VCFLVAudioTagSampleRate11kHz = 1,
    VCFLVAudioTagSampleRate22kHz = 2,
    VCFLVAudioTagSampleRate44kHz = 3,
};

typedef NS_ENUM(uint8_t, VCFLVAudioTagSampleLength) {
    VCFLVAudioTagSampleLength8Bit = 0,
    VCFLVAudioTagSampleLength16Bit = 1,
};

typedef NS_ENUM(uint8_t, VCFLVAudioTagAudioType) {
    VCFLVAudioTagAudioTypeMono = 0,
    VCFLVAudioTagAudioTypeStereo = 1,
};

typedef NS_ENUM(uint8_t, VCFLVAudioTagAACPacketType) {
    VCFLVAudioTagAACPacketTypeSequenceHeader = 0,
    VCFLVAudioTagAACPacketTypeRaw = 1,
};

@interface VCFLVAudioTag : VCFLVTag
@property (nonatomic, readonly) VCFLVAudioTagFormatType formatType;
@property (nonatomic, readonly) VCFLVAudioTagSampleRate sampleRate;
@property (nonatomic, readonly) VCFLVAudioTagSampleLength sampleLength;
@property (nonatomic, readonly) VCFLVAudioTagAudioType audioType;
@property (nonatomic, readonly) VCFLVAudioTagAACPacketType AACPacketType;
@end

@interface VCFLVMetaTag : VCFLVTag

@end
NS_ASSUME_NONNULL_END
