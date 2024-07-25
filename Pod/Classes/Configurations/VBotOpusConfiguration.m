//
//  VBotOpusConfiguration.m
//  Copyright © 2022 VPMedia. All rights reserved.
//

#import "VBotOpusConfiguration.h"

static VBotOpusConfigurationSampleRate const VBotOpusConfigurationSampleRateDefault = VBotOpusConfigurationSampleRateFullBand;
static VBotOpusConfigurationFrameDuration const VBotOpusConfigurationFrameDurationDefault = VBotOpusConfigurationFrameDurationSixty;
static NSUInteger const VBotOpusConfigurationComplexity = 5;

@implementation VBotOpusConfiguration

- (instancetype)init {
    if (self = [super init]) {
        self.sampleRate = VBotOpusConfigurationSampleRateDefault;
        self.frameDuration = VBotOpusConfigurationFrameDurationDefault;
        self.constantBitRate = NO;
        self.complexity = VBotOpusConfigurationComplexity;
    }
    return self;
}

- (void)setComplexity:(NSUInteger)complexity {
    NSAssert(complexity > 0 && complexity <= 10, @"Complexity needs to be between 0 and 10");
    _complexity = complexity;
}

@end
