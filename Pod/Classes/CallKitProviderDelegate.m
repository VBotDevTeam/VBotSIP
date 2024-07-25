//
//  CallKitProviderDelegate.m
//  Copyright © 2022 VPMedia. All rights reserved.
//
//

#import "CallKitProviderDelegate.h"
#import "VBotSIP.h"
#import "VBotAudioController.h"
#import "VBotEndpoint.h"
#import "VBotLogging.h"

NSString * const CallKitProviderDelegateOutboundCallStartedNotification = @"CallKitProviderDelegateOutboundCallStarted";
NSString * const CallKitProviderDelegateInboundCallAcceptedNotification = @"CallKitProviderDelegateInboundCallAccepted";
NSString * const CallKitProviderDelegateInboundCallRejectedNotification = @"CallKitProviderDelegateInboundCallRejected";

@interface CallKitProviderDelegate()
@property (weak, nonatomic) VBotCallManager *callManager;
@end

@implementation CallKitProviderDelegate

- (instancetype)initWithCallManager:(VBotCallManager *)callManager {
    if (self = [super init]) {
        self.callManager = callManager;
        
        self.provider = [[CXProvider alloc] initWithConfiguration:[self providerConfiguration]];
        [self.provider setDelegate:self queue:nil];
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(callStateChanged:)
                                                     name:VBotCallStateChangedNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:VBotCallStateChangedNotification object:nil];
}

- (CXProviderConfiguration *)providerConfiguration {
    NSString *appname = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"];
    CXProviderConfiguration *providerConfiguration = [[CXProviderConfiguration alloc]
                                                      initWithLocalizedName:NSLocalizedString(appname, nil)];
    
    providerConfiguration.maximumCallGroups = 2;
    providerConfiguration.maximumCallsPerCallGroup = 1;
    providerConfiguration.supportsVideo = ![VBotEndpoint sharedEndpoint].endpointConfiguration.disableVideoSupport;
    
    NSString *ringtoneFileName = [[NSBundle mainBundle] pathForResource:@"ringtone" ofType:@"wav"];
    if (ringtoneFileName) {
        providerConfiguration.ringtoneSound = @"ringtone.wav";
    }
    
    providerConfiguration.supportedHandleTypes = [NSSet setWithObject:[NSNumber numberWithInt:CXHandleTypePhoneNumber]];
    
    return providerConfiguration;
}

/**
 * This causes CallKit to update the "native" call screen.
 */
- (void)reportIncomingCall:(VBotCall *)call {
    CXCallUpdate *update = [[CXCallUpdate alloc] init];
    update.localizedCallerName = call.callerName;

    NSString * handleValue = @"";
    if ([update.localizedCallerName length] == 0) { // Doing this to not let the caller contact name override the platform's one.
        handleValue = call.callerNumber;
    }
    CXHandle *handle = [[CXHandle alloc] initWithType:CXHandleTypePhoneNumber value:handleValue];
    update.remoteHandle = handle;

    VBotLogVerbose(@"Updating CallKit provider with UUID: %@", call.uuid.UUIDString);
    [self.provider reportCallWithUUID:call.uuid updated:update];
}

// MARK: - CXProviderDelegate
/**
 * Delegate method called when the user accepts the incoming call from within the
 * "native" CallKit interface.
 */
- (void)provider:(CXProvider *)provider performAnswerCallAction:(CXAnswerCallAction *)action {
    __weak VBotCall *call = [self.callManager callWithUUID:action.callUUID];
    if (call) {
        [self.callManager.audioController configureAudioSession];

        [call answerWithCompletion:^(NSError *error) {
            if (error) {
                VBotLogError(@"Error answering call(%@) error:%@", call.uuid.UUIDString, error);
                
                [action fail];

            } else {
                VBotLogVerbose(@"Answering call %@", call.uuid.UUIDString);
                // Post a notification so the outbound call screen can be shown.
                NSDictionary *notificationInfo = @{VBotNotificationUserInfoCallKey : call};
                [[NSNotificationCenter defaultCenter] postNotificationName:CallKitProviderDelegateInboundCallAcceptedNotification
                                                                    object:self
                                                                  userInfo:notificationInfo];
                [action fulfill];
            }
        }];
    } else {
        VBotLogError(@"Error answering call(%@). No call found", action.callUUID.UUIDString);
        [action fail];
    }
}

/**
 * Delegate method called when the user declines the incoming call from within the
 * "native" CallKit interface and from our own call interface.
 */
- (void)provider:(CXProvider *)provider performEndCallAction:(CXEndCallAction *)action {
    // Find call.
    __weak VBotCall *call = [self.callManager callWithUUID:action.callUUID];
    if (!call) {
        VBotLogInfo(@"Error hanging up call(%@). No call found.", action.callUUID.UUIDString);
        [action fulfill];
        return;
    }

    // Decline if incoming, otherwise hangup.
    NSError *error;
    if (call.callState == VBotCallStateIncoming) {
        VBotLogInfo(@"Rejected incoming call, post info so that app can catch.");
        [call decline:&error];
        [[NSNotificationCenter defaultCenter] postNotificationName:CallKitProviderDelegateInboundCallRejectedNotification object:self userInfo:nil];
    } else {
        [call hangup:&error];
    }

    // Check if there was an error hanging up.
    if (error) {
        VBotLogInfo(@"Error hanging up call(%@) error:%@", call.uuid.UUIDString, error);
        [action fail];
    } else {
        VBotLogVerbose(@"Ending call %@", call.uuid.UUIDString);
        [action fulfill];
    }
}

/**
 * Delegate method called when CallKit approves the apps request to start an outbound call.
 */
- (void)provider:(CXProvider *)provider performStartCallAction:(CXStartCallAction *)action {
    __weak VBotCall *call = [self.callManager callWithUUID:action.callUUID];
    [self.callManager.audioController configureAudioSession];

    [call startWithCompletion:^(NSError *error) {
        if (error) {
            VBotLogError(@"Error starting call(%@) error: %@", call.uuid.UUIDString, error);
            [action fail];
        } else {
            VBotLogInfo(@"Call %@ started", call.uuid.UUIDString);

            // Post a notification so the outbound call screen can be shown.
            NSDictionary *notificationInfo = @{VBotNotificationUserInfoCallKey : call};
            [[NSNotificationCenter defaultCenter] postNotificationName:CallKitProviderDelegateOutboundCallStartedNotification
                                                                object:self
                                                              userInfo:notificationInfo];
            [action fulfill];
        }
    }];
}

- (void)provider:(CXProvider *)provider performSetMutedCallAction:(CXSetMutedCallAction *)action {
    __weak VBotCall *call = [self.callManager callWithUUID:action.callUUID];
    if (!call) {
        [action fail];
        return;
    }

    NSError *muteError;
    [call toggleMute:&muteError];
    if (muteError) {
        VBotLogError(@"Could not mute call(%@). Error: %@", call.uuid.UUIDString, muteError);
        [action fail];
    } else {
        [action fulfill];
    }
}

- (void)provider:(CXProvider *)provider performSetHeldCallAction:(CXSetHeldCallAction *)action {
    __weak VBotCall *call = [self.callManager callWithUUID:action.callUUID];
    if (!call) {
        [action fail];
        return;
    }
    NSError *holdError;
    [call toggleHold:&holdError];
    if (holdError) {
        VBotLogError(@"Could not hold call(%@). Error: %@", call.uuid.UUIDString, holdError);
        [action fail];
    } else {
        call.onHold ? [self.callManager.audioController deactivateAudioSession] : [self.callManager.audioController activateAudioSession];
        [action fulfill];
    }
}

- (void)provider:(CXProvider *)provider performPlayDTMFCallAction:(CXPlayDTMFCallAction *)action {
    __weak VBotCall *call = [self.callManager callWithUUID:action.callUUID];
    if (!call) {
        [action fail];
        return;
    }
    NSError *dtmfError;
    [call sendDTMF:action.digits error:&dtmfError];
    if (dtmfError) {
        VBotLogError(@"Call(%@). Could not send DTMF. Error %@", call.uuid.UUIDString, dtmfError);
        [action fail];
    } else {
        [action fulfill];
    }
}

- (void)provider:(CXProvider *)provider didActivateAudioSession:(AVAudioSession *)audioSession {
    [self.callManager.audioController activateAudioSession];
}

- (void)provider:(CXProvider *)provider didDeactivateAudioSession:(AVAudioSession *)audioSession {
    [self.callManager.audioController deactivateAudioSession];
}

- (void)providerDidReset:(CXProvider *)provider {
    VBotLogDebug(@"Provider reset: end all calls");
    [self.callManager endAllCalls];
}

- (void)callStateChanged:(NSNotification *)notification {
    __weak VBotCall *call = [[notification userInfo] objectForKey:VBotNotificationUserInfoCallKey];

    switch (call.callState) {
        case VBotCallStateNull:
            break;

        case VBotCallStateCalling:
            if (!call.isIncoming) {
                VBotLogDebug(@"Outgoing call, in CALLING state, with UUID: %@", call.uuid);
                [self.provider reportOutgoingCallWithUUID:call.uuid startedConnectingAtDate:[NSDate date]];
            }
            break;

        case VBotCallStateIncoming:
            // An incoming call is reported to the provider immediately after the push message is received in the APNSHandler.
            break;

        case VBotCallStateEarly:
            if (!call.isIncoming) {
                VBotLogDebug(@"Outgoing call, in EARLY state, with UUID: %@", call.uuid);
                [self.provider reportOutgoingCallWithUUID:call.uuid startedConnectingAtDate:[NSDate date]];
            }
            break;
        case VBotCallStateConnecting:
            if (!call.isIncoming) {
                VBotLogDebug(@"Outgoing call, in CONNECTING state, with UUID: %@", call.uuid);
                [self.provider reportOutgoingCallWithUUID:call.uuid startedConnectingAtDate:[NSDate date]];
            }
            break;

        case VBotCallStateConfirmed:
            if (!call.isIncoming) {
                VBotLogDebug(@"Outgoing call, in CONFIRMED state, with UUID: %@", call.uuid);
                [self.provider reportOutgoingCallWithUUID:call.uuid connectedAtDate:[NSDate date]];
            }
            break;

        case VBotCallStateDisconnected:
            if (!call.connected) {
                VBotLogDebug(@"Call never connected, in DISCONNECTED state, with UUID: %@", call.uuid);
                [self.provider reportOutgoingCallWithUUID:call.uuid connectedAtDate:[NSDate date]];
                [self.provider reportCallWithUUID:call.uuid endedAtDate:[NSDate date] reason:CXCallEndedReasonUnanswered];
            } else if (!call.userDidHangUp) {
                VBotLogDebug(@"Call remotly ended, in DISCONNECTED state, with UUID: %@", call.uuid);
                [self.provider reportCallWithUUID:call.uuid endedAtDate:[NSDate date] reason:CXCallEndedReasonRemoteEnded];
            }
            break;
    }
}

@end
