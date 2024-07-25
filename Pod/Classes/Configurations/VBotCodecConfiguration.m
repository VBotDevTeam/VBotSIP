//
//  VBotCodecConfiguration.m
//  Copyright © 2022 VPMedia. All rights reserved.


#import "VBotCodecConfiguration.h"

#import "NSString+PJString.h"

@implementation VBotCodecConfiguration

- (instancetype)init {
    if (self = [super init]) {
        self.audioCodecs = [self defaultAudioCodecs];
        self.videoCodecs = [self defaultVideoCodecs];
    }
    return self;
}

- (NSArray *) defaultAudioCodecs {
    return @[
            [[VBotAudioCodecs alloc] initWithAudioCodec:VBotAudioCodecG711a andPriority:210],
            [[VBotAudioCodecs alloc] initWithAudioCodec:VBotAudioCodecG722 andPriority:209],
            [[VBotAudioCodecs alloc] initWithAudioCodec:VBotAudioCodecILBC andPriority:208],
            [[VBotAudioCodecs alloc] initWithAudioCodec:VBotAudioCodecG711 andPriority:0],
            [[VBotAudioCodecs alloc] initWithAudioCodec:VBotAudioCodecSpeex8000 andPriority:0],
            [[VBotAudioCodecs alloc] initWithAudioCodec:VBotAudioCodecSpeex16000 andPriority:0],
            [[VBotAudioCodecs alloc] initWithAudioCodec:VBotAudioCodecSpeex32000 andPriority:0],
            [[VBotAudioCodecs alloc] initWithAudioCodec:VBotAudioCodecGSM andPriority:0],
            [[VBotAudioCodecs alloc] initWithAudioCodec:VBotAudioCodecOpus andPriority:0]
            ];
}

- (NSArray *) defaultVideoCodecs {
    return @[
             [[VBotVideoCodecs alloc] initWithVideoCodec:VBotVideoCodecH264 andPriority:210]
             ];
}

- (VBotOpusConfiguration *)opusConfiguration {
    if (!_opusConfiguration) {
        _opusConfiguration = [[VBotOpusConfiguration alloc] init];
    }
    return _opusConfiguration;
}

@end
