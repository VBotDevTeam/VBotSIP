//
//  VBotCodecs.m
//  Copyright © 2022 VPMedia. All rights reserved.
//

#import "VBotAudioCodecs.h"

@interface VBotAudioCodecs()
@property (readwrite, nonatomic) NSUInteger priority;
@property (readwrite, nonatomic) VBotAudioCodec codec;
@end

@implementation VBotAudioCodecs
- (instancetype)initWithAudioCodec:(VBotAudioCodec)codec andPriority:(NSUInteger)priority {
    if (self = [super init]) {
        self.codec = codec;
        self.priority = priority;
    }

    return self;
}

+ (NSString *)codecString:(VBotAudioCodec)codec {
    return VBotAudioCodecString(codec);
}

+ (NSString *)codecStringWithIndex:(NSInteger)index {
    return VBotAudioCodecStringWithIndex(index);
}
@end
