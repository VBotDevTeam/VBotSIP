//
//  VBotStunConfiguration.m
//  Copyright © 2022 VPMedia. All rights reserved.
//

#import "VBotStunConfiguration.h"

@implementation VBotStunConfiguration

- (NSArray *)stunServers {
    if (!_stunServers) {
        _stunServers = [NSArray array];
    }
    return _stunServers;
}

- (int)numOfStunServers {
    return (int)self.stunServers.count;
}

@end
