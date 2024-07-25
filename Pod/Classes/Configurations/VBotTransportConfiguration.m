//
//  VBotTransportConfiguration.m
//  Copyright © 2022 VPMedia. All rights reserved.
//

#import "VBotTransportConfiguration.h"

static NSInteger const VBotTransportConfigurationPort = 5060;
static NSInteger const VBotTransportConfigurationPortRange = 0;

@implementation VBotTransportConfiguration

- (instancetype)init {
    if (self = [super init]) {
        self.port = VBotTransportConfigurationPort;
        self.portRange = VBotTransportConfigurationPortRange;
        self.transportType = VBotTransportTypeTCP;
    }
    return self;
}

+ (instancetype)configurationWithTransportType:(VBotTransportType)transportType {
    VBotTransportConfiguration *transportConfiguration = [[VBotTransportConfiguration alloc] init];
    transportConfiguration.transportType = transportType;
    return transportConfiguration;
}

@end
