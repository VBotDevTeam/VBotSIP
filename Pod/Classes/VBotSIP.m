//
//  VBotSIP.m
//  Copyright © 2022 VPMedia. All rights reserved.
//

#import "VBotSIP.h"

#import "Constants.h"
#import "NSError+VBotError.h"
#import "VBotAccount.h"
#import "VBotEndpoint.h"
#import "VBotLogging.h"

static NSString * const VBotSIPErrorDomain = @"VBotSIP.error";
NSString * const VBotNotificationUserInfoCallKey = @"VBotNotificationUserInfoCallKey";
NSString * const VBotNotificationUserInfoCallIdKey = @"VBotNotificationUserInfoCallIdKey";
NSString * const VBotNotificationUserInfoWindowIdKey = @"VBotNotificationUserInfoWindowIdKey";
NSString * const VBotNotificationUserInfoWindowSizeKey = @"VBotNotificationUserInfoWindowSizeKey";
NSString * const VBotNotificationUserInfoCallStateKey = @"VBotNotificationUserInfoCallStateKey";
NSString * const VBotNotificationUserInfoCallAudioStateKey = @"VBotNotificationUserInfoCallAudioStateKey";
NSString * const VBotNotificationUserInfoErrorStatusCodeKey = @"VBotNotificationUserInfoErrorStatusCodeKey";
NSString * const VBotNotificationUserInfoErrorStatusMessageKey = @"VBotNotificationUserInfoErrorStatusMessageKey";

@interface VBotSIP()
@property (strong, nonatomic) VBotEndpoint *endpoint;
@property (strong, nonatomic) VBotCallManager *callManager;
@end

@implementation VBotSIP

+ (instancetype)sharedInstance {
    static dispatch_once_t once;
    static id sharedInstance;

    dispatch_once(&once, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (VBotEndpoint *)endpoint {
    if (!_endpoint) {
        _endpoint = [VBotEndpoint sharedEndpoint];
    }
    return _endpoint;
}

- (BOOL)endpointAvailable {
    return self.endpoint.state == VBotEndpointStarted;
}

- (BOOL)hasTLSTransport {
    return self.endpointAvailable && self.endpoint.endpointConfiguration.hasTLSConfiguration;
}

- (BOOL)hasSTUNEnabled {
    return self.endpointAvailable && self.endpoint.endpointConfiguration.stunConfiguration != nil && self.endpoint.endpointConfiguration.stunConfiguration.stunServers.count > 0;
}

- (VBotCallManager *)callManager {
    if (!_callManager) {
        _callManager = [[VBotCallManager alloc] init];
    }
    return _callManager;
}

- (BOOL)configureLibraryWithEndPointConfiguration:(VBotEndpointConfiguration * _Nonnull)endpointConfiguration error:(NSError * _Nullable __autoreleasing *)error {
    // Make sure interrupts are handled by pjsip
    dispatch_async(dispatch_get_main_queue(), ^{
        [[UIApplication sharedApplication] beginReceivingRemoteControlEvents];
    });    

    // Start the Endpoint
    NSError *endpointConfigurationError;
    BOOL success = [self.endpoint startEndpointWithEndpointConfiguration:endpointConfiguration error:&endpointConfigurationError];
    if (endpointConfigurationError && error != NULL) {
        *error = [NSError VBotUnderlyingError:endpointConfigurationError
           localizedDescriptionKey:NSLocalizedString(@"The endpoint configuration has failed.", nil)
       localizedFailureReasonError:nil
                       errorDomain:VBotSIPErrorDomain
                         errorCode:VBotSIPErrorEndpointConfigurationFailed];
    }
    return success;
}

- (BOOL)shouldRemoveEndpoint {
    return (self.endpointAvailable && self.accounts.count == 0);
}

- (void)removeEndpoint {
    if ([self shouldRemoveEndpoint]){
        [self.endpoint destroyPJSUAInstance];
    }
}

- (BOOL)updateCodecConfiguration:(VBotCodecConfiguration *)codecConfiguration {
    return [self.endpoint updateCodecConfiguration:codecConfiguration];
}

- (VBotAccount *)createAccountWithSipUser:(id<SIPEnabledUser>  _Nonnull __autoreleasing)sipUser error:(NSError * _Nullable __autoreleasing *)error {
    VBotAccount *account = [self.endpoint getAccountWithSipAccount:sipUser.sipAccount];

    if (!account) {
        VBotAccountConfiguration *accountConfiguration = [[VBotAccountConfiguration alloc] init];
        accountConfiguration.sipAccount = sipUser.sipAccount;
        accountConfiguration.sipPassword = sipUser.sipPassword;
        accountConfiguration.sipDomain = sipUser.sipDomain;

        if ([sipUser respondsToSelector:@selector(sipProxy)]) {
            accountConfiguration.sipProxyServer = sipUser.sipProxy;
        }

        if ([sipUser respondsToSelector:@selector(sipRegisterOnAdd)]) {
            accountConfiguration.sipRegisterOnAdd = sipUser.sipRegisterOnAdd;
        }

        if ([sipUser respondsToSelector:@selector(dropCallOnRegistrationFailure)]) {
            accountConfiguration.dropCallOnRegistrationFailure = sipUser.dropCallOnRegistrationFailure;
        }
        
        if ([sipUser respondsToSelector:@selector(mediaStunType)]) {
            accountConfiguration.mediaStunType = (pjsua_stun_use) sipUser.mediaStunType;
        }
        
        if ([sipUser respondsToSelector:@selector(sipStunType)]) {
            accountConfiguration.sipStunType = (pjsua_stun_use) sipUser.sipStunType;
        }

        if ([sipUser respondsToSelector:@selector(contactRewriteMethod)]) {
            accountConfiguration.contactRewriteMethod = sipUser.contactRewriteMethod;
        }

        if ([sipUser respondsToSelector:@selector(iceConfiguration)]) {
            accountConfiguration.iceConfiguration = sipUser.iceConfiguration;
        }

        if ([sipUser respondsToSelector:@selector(contactUseSrcPort)]) {
            accountConfiguration.contactUseSrcPort = sipUser.contactUseSrcPort;
        }

        if ([sipUser respondsToSelector:@selector(allowViaRewrite)]) {
            accountConfiguration.allowViaRewrite = sipUser.allowViaRewrite;
        }

        if ([sipUser respondsToSelector:@selector(allowContactRewrite)]) {
            accountConfiguration.allowContactRewrite = sipUser.allowContactRewrite;
        }

        account = [[VBotAccount alloc] initWithCallManager:self.callManager];
 
        NSError *accountConfigError = nil;
        [account configureWithAccountConfiguration:accountConfiguration error:&accountConfigError];
        if (accountConfigError && error != NULL) {
            *error = accountConfigError;
            VBotLogError(@"Account configuration error: %@", accountConfigError);
            return nil;
        }
    }
    return account;
}

- (void)setIncomingCallBlock:(void (^)(VBotCall * _Nonnull))incomingCallBlock {
    [VBotEndpoint sharedEndpoint].incomingCallBlock = incomingCallBlock;
}

- (void)setMissedCallBlock:(void (^)(VBotCall * _Nonnull))missedCallBlock {
    [VBotEndpoint sharedEndpoint].missedCallBlock = missedCallBlock;
}

- (void)setLogCallBackBlock:(void (^)(DDLogMessage*))logCallBackBlock {
    [VBotEndpoint sharedEndpoint].logCallBackBlock = logCallBackBlock;
}

- (void)registerAccountWithUser:(id<SIPEnabledUser> _Nonnull __autoreleasing)sipUser forceRegistration:(BOOL)force withCompletion:(void (^)(BOOL, VBotAccount * _Nullable))completion {
    NSError *accountConfigError;
    VBotAccount *account = [self createAccountWithSipUser:sipUser error:&accountConfigError];
    if (!account) {
        VBotLogError(@"The configuration of the account has failed:\n%@", accountConfigError);
        completion(NO, nil);
    }

    account.forceRegistration = force;
    [account registerAccountWithCompletion:^(BOOL success, NSError * _Nullable error) {
        if (!success) {
            VBotLogError(@"The registration of the account has failed.\n%@", error);
            completion(NO, nil);
        } else {
            completion(YES, account);
        }
    }];
}

- (VBotCall *)getVBotCallWithId:(NSString *)callId andSipUser:(id<SIPEnabledUser>  _Nonnull __autoreleasing)sipUser {
    if (!callId) {
        return nil;
    }

    VBotAccount *account = [self.endpoint getAccountWithSipAccount:sipUser.sipAccount];

    if (!account) {
        return nil;
    }

    VBotCall *call = [account lookupCall:[callId intValue]];

    return call;
}

- (VBotAccount *)firstAccount {
    return [self.endpoint.accounts firstObject];
}

- (NSArray *)accounts {
    return self.endpoint.accounts;
}

- (BOOL)anotherCallInProgress:(VBotCall *)call {
    VBotAccount *account = [self firstAccount];
    VBotCall *activeCall = [self.callManager firstCallForAccount:account];

    if (call.callId != activeCall.callId) {
        return YES;
    }
    return NO;
}

@end
