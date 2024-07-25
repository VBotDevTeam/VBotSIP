//
//  VBotAccountConfiguration.m
//  Copyright © 2022 VPMedia. All rights reserved.
//

#import "VBotAccountConfiguration.h"

@implementation VBotAccountConfiguration

- (instancetype)init {
    if (self = [super init]) {
        self.sipAuthRealm = @"*";
        self.sipAuthScheme = @"digest";
        self.dropCallOnRegistrationFailure = NO;
        self.mediaStunType = VBotStunUseDefault;
        self.sipStunType = VBotStunUseDefault;
        self.contactRewriteMethod = VBotContactRewriteMethodAlwaysUpdate;
        self.contactUseSrcPort = YES;
        self.allowViaRewrite = YES;
        self.allowContactRewrite = YES;
    }
    return self;
}

- (NSString *)sipAddress {
    if (self.sipAccount && self.sipDomain) {
        return [NSString stringWithFormat:@"%@@%@", self.sipAccount, self.sipDomain];
    }
    return nil;
}

@end
