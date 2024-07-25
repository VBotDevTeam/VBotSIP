//
//  VBotVideoCodecs.m
//  VBotSIP
//
//  Created by Redmer Loen on 4/5/18.
//

#import "VBotVideoCodecs.h"

@interface VBotVideoCodecs()
@property (readwrite, nonatomic) NSUInteger priority;
@property (readwrite, nonatomic) VBotVideoCodec codec;
@end

@implementation VBotVideoCodecs
-(instancetype)initWithVideoCodec:(VBotVideoCodec)codec andPriority:(NSUInteger)priority {
    if (self = [super init]) {
        self.codec = codec;
        self.priority = priority;
    }
    return self;
}

+ (NSString *)codecString:(VBotVideoCodec)codec {
    return VBotVideoCodecString(codec);
}

+ (NSString *)codecStringWithIndex:(NSInteger)index {
    return VBotVideoCodecStringWithIndex(index);
}
@end
