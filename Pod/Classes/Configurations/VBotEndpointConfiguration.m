//
//  VBotEndPointConfiguration.m
//  Copyright © 2022 VPMedia. All rights reserved.
//

#import "VBotEndpointConfiguration.h"

#import <VialerPJSIP/pjsua.h>
#import "VBotTransportConfiguration.h"

static NSUInteger const VBotEndpointConfigurationMaxCalls = 4;
static NSUInteger const VBotEndpointConfigurationLogLevel = 5;
static NSUInteger const VBotEndpointConfigurationLogConsoleLevel = 4;
static NSString * const VBotEndpointConfigurationLogFileName = nil;
static NSUInteger const VBotEndpointConfigurationClockRate = PJSUA_DEFAULT_CLOCK_RATE;
static NSUInteger const VBotEndpointConfigurationSndClockRate = 0;

@implementation VBotEndpointConfiguration

- (instancetype)init {
    if (self = [super init]) {
        self.maxCalls = VBotEndpointConfigurationMaxCalls;
        self.logLevel = VBotEndpointConfigurationLogLevel;
        self.logConsoleLevel = VBotEndpointConfigurationLogConsoleLevel;
        self.logFilename = VBotEndpointConfigurationLogFileName;
        self.logFileFlags = PJ_O_APPEND;
        self.clockRate = VBotEndpointConfigurationClockRate;
        self.sndClockRate = VBotEndpointConfigurationSndClockRate;
        self.disableVideoSupport = NO;
        self.unregisterAfterCall = NO;
    }
    return self;
}

- (NSArray *)transportConfigurations {
    if (!_transportConfigurations) {
        _transportConfigurations = [NSArray array];
    }
    return _transportConfigurations;
}

- (VBotIpChangeConfiguration *)ipChangeConfiguration {
    if (!_ipChangeConfiguration) {
        _ipChangeConfiguration = [[VBotIpChangeConfiguration alloc] init];
    }
    return _ipChangeConfiguration;
}

- (VBotStunConfiguration *)stunConfiguration {
    if (!_stunConfiguration) {
        _stunConfiguration = [[VBotStunConfiguration alloc] init];
    }
    return _stunConfiguration;
}

- (VBotCodecConfiguration *)codecConfiguration {
    if (!_codecConfiguration) {
        _codecConfiguration = [[VBotCodecConfiguration alloc] init];
    }
    return _codecConfiguration;
}

- (void)setLogLevel:(NSUInteger)logLevel {
    NSAssert(logLevel > 0, @"Log level needs to be set higher than 0");
    _logLevel = logLevel;
}

- (void)setLogConsoleLevel:(NSUInteger)logConsoleLevel {
    NSAssert(logConsoleLevel > 0, @"Console log level needs to be higher than 0");
    _logConsoleLevel = logConsoleLevel;
}

- (BOOL)hasTCPConfiguration {
    NSUInteger index = [self.transportConfigurations indexOfObjectPassingTest:^BOOL(VBotTransportConfiguration *transportConfiguration, NSUInteger idx, BOOL *stop) {
        if (transportConfiguration.transportType == VBotTransportTypeTCP || transportConfiguration.transportType == VBotTransportTypeTCP6) {
            *stop = YES;
            return YES;
        }
        return NO;
    }];

    if (index == NSNotFound) {
        return NO;
    }
    return YES;
}

- (BOOL)hasTLSConfiguration {
    NSUInteger index = [self.transportConfigurations indexOfObjectPassingTest:^BOOL(VBotTransportConfiguration *transportConfiguration, NSUInteger idx, BOOL *stop) {
        if (transportConfiguration.transportType == VBotTransportTypeTLS || transportConfiguration.transportType == VBotTransportTypeTLS6) {
            *stop = YES;
            return YES;
        }
        return NO;
    }];

    if (index == NSNotFound) {
        return NO;
    }
    return YES;
}

-(BOOL)hasUDPConfiguration {
    NSUInteger index = [self.transportConfigurations indexOfObjectPassingTest:^BOOL(VBotTransportConfiguration *transportConfiguration, NSUInteger idx, BOOL *stop) {
        if (transportConfiguration.transportType == VBotTransportTypeUDP || transportConfiguration.transportType == VBotTransportTypeUDP6) {
            *stop = YES;
            return YES;
        }
        return NO;
    }];

    if (index == NSNotFound) {
        return NO;
    }
    return YES;
}

@end
