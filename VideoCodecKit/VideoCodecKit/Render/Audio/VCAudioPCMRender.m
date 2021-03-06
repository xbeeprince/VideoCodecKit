//
//  VCAudioPCMRender.m
//  VideoCodecKit
//
//  Created by CmST0us on 2019/2/2.
//  Copyright © 2019 eric3u. All rights reserved.
//

#import "VCAudioPCMRender.h"

@interface VCAudioPCMRender ()
@property (nonatomic, strong) AVAudioEngine *audioEngine;
@property (nonatomic, strong) AVAudioPlayerNode *playerNode;

@property (nonatomic, strong) AVAudioFormat *pcmFormat;
@end

@implementation VCAudioPCMRender
- (instancetype)initWithPCMFormat:(AVAudioFormat *)format {
    self = [super init];
    if (self) {
        _audioEngine = [[AVAudioEngine alloc] init];
        _playerNode = [[AVAudioPlayerNode alloc] init];
        _pcmFormat = format;
        
        [_audioEngine attachNode:_playerNode];
        [_audioEngine connect:_playerNode to:_audioEngine.mainMixerNode format:format];
        [_audioEngine prepare];
        
        NSError *error = nil;
        [_audioEngine startAndReturnError:&error];
        if (error != nil) {
            return nil;
        }
        
    }
    return self;
}

- (void)play {
    [_playerNode play];
}

- (void)stop {
    [_playerNode stop];
}

- (void)pause {
    [_playerNode pause];
}

- (void)renderPCMBuffer:(AVAudioPCMBuffer *)pcmBuffer withPresentationTimeStamp:(CMTime)presentationTimeStamp completionHandler:(AVAudioNodeCompletionHandler)handler {
    [_playerNode scheduleBuffer:pcmBuffer completionHandler:handler];
}

- (void)dealloc {
    [self.audioEngine stop];
}
@end
