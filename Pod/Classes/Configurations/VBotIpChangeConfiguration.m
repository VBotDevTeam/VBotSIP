//
//  VBotIpChangeConfiguration.m
//  Copyright © 2022 VPMedia. All rights reserved.
//

#import "VBotIpChangeConfiguration.h"

@implementation VBotIpChangeConfiguration

- (instancetype)init {
    if (self = [super init]) {
        self.ipChangeCallsUpdate = VBotIpChangeConfigurationIpChangeCallsDefault;
        self.ipAddressChangeShutdownTransport = YES;
        self.ipAddressChangeHangupAllCalls = NO;
        self.ipAddressChangeReinviteFlags = VBotReinviteFlagsReinitMedia | VBotReinviteFlagsUpdateVia | VBotReinviteFlagsUpdateContact;
    }
    return self;
}

+ (VBotReinviteFlags)defaultReinviteFlags {
    return VBotReinviteFlagsReinitMedia | VBotReinviteFlagsUpdateVia | VBotReinviteFlagsUpdateContact;
}

@end
