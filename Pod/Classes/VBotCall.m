//
//  VBotCall.m
//  Copyright © 2022 VPMedia. All rights reserved.
//

#import "VBotCall.h"
#import <AVFoundation/AVFoundation.h>
#import "NSError+VBotError.h"
#import "NSString+PJString.h"
#import "VBotAudioController.h"
#import "VBotEndpoint.h"
#import "VBotLogging.h"
#import "VBotRingback.h"
#import "VBotSIP.h"
#import "VBotUtils.h"


static NSString * const VBotCallErrorDomain = @"VBotSIP.VBotCall";
static double const VBotCallDelayTimeCheckSuccessfullHangup = 0.5;

NSString * const VBotCallStateChangedNotification = @"VBotCallStateChangedNotification";
NSString * const VBotNotificationUserInfoVideoSizeRenderKey = @"VBotNotificationUserInfoVideoSizeRenderKey";
NSString * const VBotCallConnectedNotification = @"VBotCallConnectedNotification";
NSString * const VBotCallDisconnectedNotification = @"VBotCallDisconnectedNotification";
NSString * const VBotCallDeallocNotification = @"VBotCallDeallocNotification";
NSString * const VBotCallNoAudioForCallNotification = @"VBotCallNoAudioForCallNotification";
NSString * const VBotCallErrorDuringSetupCallNotification = @"VBotCallErrorDuringSetupCallNotification";

@interface VBotCall()
@property (readwrite, nonatomic) VBotCallState callState;
@property (readwrite, nonatomic) NSString *callStateText;
@property (readwrite, nonatomic) NSInteger lastStatus;
@property (readwrite, nonatomic) NSString *lastStatusText;
@property (readwrite, nonatomic) VBotMediaState mediaState;
@property (readwrite, nonatomic) NSString *localURI;
@property (readwrite, nonatomic) NSString *remoteURI;
@property (readwrite, nonatomic) NSString *callerName;
@property (readwrite, nonatomic) NSString *callerNumber;
@property (readwrite, nonatomic) NSString *messageCallId;
@property (readwrite, nonatomic) NSUUID *uuid;
@property (readwrite, nonatomic) BOOL incoming;
@property (strong, nonatomic) VBotRingback *ringback;
@property (readwrite, nonatomic) BOOL muted;
@property (readwrite, nonatomic) BOOL speaker;
@property (readwrite, nonatomic) BOOL onHold;
@property (strong, nonatomic) NSString *currentAudioSessionCategory;
@property (nonatomic) BOOL connected;
@property (nonatomic) BOOL userDidHangUp;
@property (readwrite, nonatomic) VBotCallTransferState transferStatus;
@property (readwrite, nonatomic) NSTimeInterval lastSeenConnectDuration;
@property (strong, nonatomic) NSString *numberToCall;
@property (readwrite, nonatomic) NSTimer *audioCheckTimer;
@property (readwrite, nonatomic) int audioCheckTimerFired;
@property (readwrite, nonatomic) VBotCallAudioState callAudioState;
@property (readwrite, nonatomic) int previousRxPkt;
@property (readwrite, nonatomic) int previousTxPkt;
/**
 *  Stats
 */
@property (readwrite, nonatomic) NSString *activeCodec;
@property (readwrite, nonatomic) float totalMBsUsed;
@property (readwrite, nonatomic) float MOS;
@end

@implementation VBotCall

#pragma mark - Life Cycle

- (instancetype)initPrivateWithAccount:(VBotAccount *)account {
    if (self = [super init]) {
        self.uuid = [[NSUUID alloc] init];
        self.account = account;
    }
    return self;
}

- (instancetype)initInboundCallWithCallId:(NSUInteger)callId account:(VBotAccount *)account {
    if (self = [self initPrivateWithAccount:account]) {
        self.callId = callId;

        pjsua_call_info callInfo;
        pj_status_t status = pjsua_call_get_info((pjsua_call_id)self.callId, &callInfo);
        if (status == PJ_SUCCESS) {
            if (callInfo.state == VBotCallStateIncoming) {
                self.incoming = YES;
            } else {
                self.incoming = NO;
            }
            [self updateCallInfo:callInfo];
        }
    }
    VBotLogVerbose(@"Inbound call init with uuid:%@ and id:%ld", self.uuid.UUIDString, (long)self.callId);
    return self;
}

- (instancetype)initOutboundCallWithNumberToCall:(NSString *)number account:(VBotAccount *)account {
    if (self = [self initPrivateWithAccount:account]) {
        self.numberToCall = number;
    }
    return self;
}

- (instancetype _Nullable)initInboundCallWithCallId:(NSUInteger)callId account:(VBotAccount * _Nonnull)account andInvite:(SipInvite *)invite {
    self.invite = invite;
    
    return [self initInboundCallWithCallId:callId account:account];
}

- (instancetype _Nullable)initInboundCallWithUUID:(NSUUID * _Nonnull)uuid number:(NSString * _Nonnull)number name:(NSString * _Nonnull)name {
    self.uuid = uuid;
    self.callerNumber = [VBotUtils cleanPhoneNumber:number];
    self.incoming = YES;
    self.callerName = name;
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] postNotificationName:VBotCallDeallocNotification
                                                        object:nil
                                                      userInfo:nil];
    VBotLogVerbose(@"Dealloc call with uuid:%@ callId:%ld", self.uuid.UUIDString, (long)self.callId);
}

#pragma mark - Properties
- (void)setCallState:(VBotCallState)callState {
    if (_callState != callState) {
        NSString *stringFromCallStateProperty = NSStringFromSelector(@selector(callState));
        [self willChangeValueForKey:stringFromCallStateProperty];
        VBotLogDebug(@"Call(%@). CallState will change from %@(%ld) to %@(%ld)", self.uuid.UUIDString, VBotCallStateString(_callState),
                   (long)_callState, VBotCallStateString(callState), (long)callState);
        _callState = callState;

        switch (_callState) {
            case VBotCallStateNull: {

            } break;
            case VBotCallStateIncoming: {
                pj_status_t status = pjsua_call_answer((pjsua_call_id)self.callId, PJSIP_SC_RINGING, NULL, NULL);
                if (status != PJ_SUCCESS) {
                    VBotLogWarning(@"Error %d while sending status code PJSIP_SC_RINGING", status);
                }
            } break;

            case VBotCallStateCalling: {

            } break;

            case VBotCallStateEarly: {
                if (!self.incoming) {
                    [self.ringback start];
                }
            } break;

            case VBotCallStateConnecting: {
            } break;

            case VBotCallStateConfirmed: {
                self.connected = YES;
                if (!self.incoming) {
                    // Stop ringback for outgoing calls.
                    [self.ringback stop];
                    self.ringback = nil;
                }
                // Register for the audio interruption notification to be able to restore the sip audio session after an interruption (incoming call/alarm....).
                [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(audioInterruption:) name:VBotAudioControllerAudioInterrupted object:nil];
                [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(audioInterruption:) name:VBotAudioControllerAudioResumed object:nil];
            } break;

            case VBotCallStateDisconnected: {
                [self calculateStats];
                if (!self.incoming) {
                    // Stop ringback for outgoing calls.
                    [self.ringback stop];
                    self.ringback = nil;
                }

                [[NSNotificationCenter defaultCenter] removeObserver:self name:VBotAudioControllerAudioResumed object:nil];
                [[NSNotificationCenter defaultCenter] removeObserver:self name:VBotAudioControllerAudioInterrupted object:nil];

                
            } break;
        }
        [self didChangeValueForKey:stringFromCallStateProperty];

        NSDictionary *notificationUserInfo = @{
                                               VBotNotificationUserInfoCallKey : self,
                                               VBotNotificationUserInfoCallStateKey: [NSNumber numberWithInt:callState]
                                               };
        [[NSNotificationCenter defaultCenter] postNotificationName:VBotCallStateChangedNotification
                                                            object:nil
                                                          userInfo:notificationUserInfo];
    }
}

- (void)setTransferStatus:(VBotCallTransferState)transferStatus {
    if (_transferStatus != transferStatus) {
        NSString *stringFromTranferStatusProperty = NSStringFromSelector(@selector(transferStatus));
        [self willChangeValueForKey:stringFromTranferStatusProperty];
        _transferStatus = transferStatus;
        [self didChangeValueForKey:stringFromTranferStatusProperty];
    }
}

- (void)setMediaState:(VBotMediaState)mediaState {
    if (_mediaState != mediaState) {
        VBotLogDebug(@"MediaState will change from %@(%ld) to %@(%ld)", VBotMediaStateString(_mediaState),
                   (long)_mediaState, VBotMediaStateString(mediaState), (long)mediaState);
        _mediaState = mediaState;
    }
}

- (VBotRingback *)ringback {
    if (!_ringback) {
        _ringback = [[VBotRingback alloc] init];
    }
    return _ringback;
}

- (NSTimeInterval)connectDuration {
    // Check if call was ever connected before.
    if (self.callId == PJSUA_INVALID_ID) {
        return 0;
    }

    pjsua_call_info callInfo;
    pjsua_call_get_info((pjsua_call_id)self.callId, &callInfo);
    NSTimeInterval latestConnecDuration = callInfo.connect_duration.sec;

    // Workaround for callInfo.connect_duration being 0 at end of call
    if (latestConnecDuration > self.lastSeenConnectDuration) {
        self.lastSeenConnectDuration = latestConnecDuration;
        return latestConnecDuration;
    } else {
        return self.lastSeenConnectDuration;
    }
}

#pragma mark - Actions
- (void)checkCurrentThreadIsRegisteredWithPJSUA {
    static pj_thread_desc a_thread_desc;
    static pj_thread_t *a_thread;
    if (!pj_thread_is_registered()) {
        pj_thread_register("VialerPJSIP", a_thread_desc, &a_thread);
    }
}

- (void)startWithCompletion:(void (^)(NSError * error))completion {
    NSAssert(self.account, @"An account must be set to be able to start a call");
    pj_str_t sipUri = [self.numberToCall sipUriWithDomain:self.account.accountConfiguration.sipDomain];

    // Create call settings.
    pjsua_call_setting callSetting;
    pjsua_call_setting_default(&callSetting);
    callSetting.aud_cnt = 1;

    if ([VBotEndpoint sharedEndpoint].endpointConfiguration.disableVideoSupport) {
        callSetting.vid_cnt = 0;
        callSetting.flag &= ~PJSUA_CALL_INCLUDE_DISABLED_MEDIA;
    }

    [self checkCurrentThreadIsRegisteredWithPJSUA];
    pj_status_t status = pjsua_call_make_call((int)self.account.accountId, &sipUri, &callSetting, NULL, NULL, (int *)&_callId);
    VBotLogVerbose(@"Call(%@) started with id:%ld", self.uuid.UUIDString, (long)self.callId);

    NSError *error;
    if (status != PJ_SUCCESS) {
        char statusmsg[PJ_ERR_MSG_SIZE];
        pj_strerror(status, statusmsg, sizeof(statusmsg));
        VBotLogError(@"Error creating call, status: %s", statusmsg);

        error = [NSError VBotUnderlyingError:nil
                    localizedDescriptionKey:NSLocalizedString(@"Could not setup call", nil)
                localizedFailureReasonError:[NSString stringWithFormat:NSLocalizedString(@"PJSIP status code: %d", nil), status]
                                errorDomain:VBotCallErrorDomain
                                  errorCode:VBotCallErrorCannotCreateCall];
    }

    completion(error);
}


- (BOOL)blindTransferCallWithNumber:(NSString *)number {
    NSString *cleanedNumber = [VBotUtils cleanPhoneNumber:number];

    if ([cleanedNumber isEqualToString:@""]) {
        return NO;
    }

    pj_str_t sipUri = [cleanedNumber sipUriWithDomain:self.account.accountConfiguration.sipDomain];

    pj_status_t status = pjsua_call_xfer((pjsua_call_id)self.callId, &sipUri, nil);

    if (status == PJ_SUCCESS) {
        self.transferStatus = VBotCallTransferStateInitialized;
        return YES;
    }
    return NO;
}

- (BOOL)transferToCall:(VBotCall *)secondCall {
    NSError *error;
    if (!self.onHold && ![self toggleHold:&error]) {
        VBotLogError(@"Error holding call: %@", error);
        return NO;
    }
    pj_status_t status = pjsua_call_xfer_replaces((pjsua_call_id)self.callId, (pjsua_call_id)secondCall.callId, 0, nil);

    if (status == PJ_SUCCESS) {
        self.transferStatus = VBotCallTransferStateInitialized;
        return YES;
    }
    return NO;
}

- (void)callTransferStatusChangedWithStatusCode:(NSInteger)statusCode statusText:(NSString *)text final:(BOOL)final {
    if (statusCode == PJSIP_SC_TRYING) {
        self.transferStatus = VBotCallTransferStateTrying;
    } else if (statusCode / 100 == 2) {
        self.transferStatus = VBotCallTransferStateAccepted;
        // After successfull transfer, end the call.
        NSError *error;
        [self hangup:&error];
        if (error) {
            VBotLogError(@"Error hangup call: %@", error);
        }
    } else {
        self.transferStatus = VBotCallTransferStateRejected;
    }
}

- (void)reinvite {
    if (self.callState > VBotCallStateNull && self.callState < VBotCallStateDisconnected) {
        pjsua_call_setting callSetting;
        pjsua_call_setting_default(&callSetting);
        
        callSetting.flag = PJSUA_CALL_REINIT_MEDIA + PJSUA_CALL_NO_SDP_OFFER;
                
        if ([VBotEndpoint sharedEndpoint].endpointConfiguration.disableVideoSupport) {
            callSetting.vid_cnt = 0;
        }

        VBotLogDebug(@"Sending Reinvite.");
        pj_status_t status = pjsua_call_reinvite2((pjsua_call_id)self.callId, &callSetting, NULL);
        
        if (status != PJ_SUCCESS) {
            char statusmsg[PJ_ERR_MSG_SIZE];
            pj_strerror(status, statusmsg, sizeof(statusmsg));
            VBotLogError(@"REINVITE failed for call id: %ld, status: %s.", (long)self.callId, statusmsg);
                    } else {
            VBotLogDebug(@"REINVITE successfully sent for call id: %ld", (long)self.callId);
        }
    } else {
        VBotLogDebug(@"Can not send call REINVITE because the call is not yet setup or already disconnected.");
    }
}

- (void)update {
    if (self.callState > VBotCallStateNull && self.callState < VBotCallStateDisconnected) {
        pjsua_call_setting callSetting;
        pjsua_call_setting_default(&callSetting);

        VBotIpChangeConfiguration *ipChangeConfiguration = [VBotEndpoint sharedEndpoint].endpointConfiguration.ipChangeConfiguration;
        if (ipChangeConfiguration) {
            callSetting.flag = ipChangeConfiguration.ipAddressChangeReinviteFlags;
        }

        if ([VBotEndpoint sharedEndpoint].endpointConfiguration.disableVideoSupport) {
            callSetting.vid_cnt = 0;
            callSetting.flag &= ~PJSUA_CALL_INCLUDE_DISABLED_MEDIA;
        }

        pj_status_t status = pjsua_call_update2((pjsua_call_id)self.callId, &callSetting, NULL);
        if (status != PJ_SUCCESS) {
            char statusmsg[PJ_ERR_MSG_SIZE];
            pj_strerror(status, statusmsg, sizeof(statusmsg));
            VBotLogError(@"Cannot sent UPDATE for call id: %ld, status: %s", (long)self.callId, statusmsg);
        } else {
            VBotLogDebug(@"UPDATE sent for call id: %ld", (long)self.callId);
        }
    } else {
        VBotLogDebug(@"Can not send call UPDATE because the call is not yet setup or already disconnected.");
    }
}

#pragma mark - Callback methods

- (void)updateCallInfo:(pjsua_call_info)callInfo {
    self.callState = (VBotCallState)callInfo.state;
    self.callStateText = [NSString stringWithPJString:callInfo.state_text];
    self.lastStatus = callInfo.last_status;
    self.lastStatusText = [NSString stringWithPJString:callInfo.last_status_text];

    if (self.messageCallId == nil) {
        self.messageCallId = [NSString stringWithPJString:callInfo.call_id];
    }

    if (self.callState != VBotCallStateDisconnected) {
        self.localURI = [NSString stringWithPJString:callInfo.local_info];
        self.remoteURI = [NSString stringWithPJString:callInfo.remote_info];
        if (self.remoteURI) {
            NSDictionary *callerInfo = [VBotCall getCallerInfoFromRemoteUri:self.remoteURI];
            self.callerName = callerInfo[@"caller_name"];
            self.callerNumber = callerInfo[@"caller_number"];
        }
        
        if (self.invite != nil) {
            if ([self.invite hasPAssertedIdentity]) {
                self.callerName = [self.invite getPAssertedIdentityName];
                self.callerNumber = [self.invite getPAssertedIdentityNumber];
            } else if ([self.invite hasRemotePartyId]) {
                self.callerName = [self.invite getRemotePartyIdName];
                self.callerNumber = [self.invite getRemotePartyIdNumber];
            }
        }
    }
}

- (void)callStateChanged:(pjsua_call_info)callInfo {
    [self updateCallInfo:callInfo];
}

- (void)mediaStateChanged:(pjsua_call_info)callInfo  {
    pjsua_call_media_status mediaState = callInfo.media_status;
    VBotLogVerbose(@"Media State Changed from %@ to %@", VBotMediaStateString(self.mediaState), VBotMediaStateString((VBotMediaState)mediaState));
    self.mediaState = (VBotMediaState)mediaState;

    if (self.mediaState == VBotMediaStateActive || self.mediaState == VBotMediaStateRemoteHold) {
        if (!self.incoming) {
            // Stop the ringback for outgoing calls.
            [self.ringback stop];
        }
        pjsua_conf_connect(callInfo.conf_slot, 0);
        if (!self.muted) {
            pjsua_conf_connect(0, callInfo.conf_slot);
        }
    }

    if (self.mediaState == VBotMediaStateActive && ![self.audioCheckTimer isValid]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.audioCheckTimerFired = 0;
            self.audioCheckTimer = [NSTimer scheduledTimerWithTimeInterval:2.0 target:self selector:@selector(checkIfAudioPresent) userInfo: nil repeats: YES];
        });
    }

    [self updateCallInfo:callInfo];
}

- (void)checkIfAudioPresent {
    pjsua_call_info callInfo;
    pjsua_call_get_info((pjsua_call_id)self.callId, &callInfo);

    if (callInfo.media_status != PJSUA_CALL_MEDIA_ACTIVE) {
        VBotLogDebug(@"Unable to check if audio present no active stream!");
        self.audioCheckTimerFired++;
        return;
    }

    pj_status_t status;
    pjsua_stream_stat stream_stat;
    status = pjsua_call_get_stream_stat((pjsua_call_id)self.callId, callInfo.media[0].index, &stream_stat);

    if (status == PJ_SUCCESS) {
        int rxPkt = stream_stat.rtcp.rx.pkt;
        int txPkt = stream_stat.rtcp.tx.pkt;

        if ((rxPkt == 0 && txPkt == 0) || (rxPkt == self.previousRxPkt && txPkt == self.previousTxPkt)) {
            self.callAudioState = VBotCallAudioStateNoAudioBothDirections;
        } else if (txPkt == 0 || txPkt == self.previousTxPkt) {
            self.callAudioState = VBotCallAudioStateNoAudioTransmitting;
        } else if (rxPkt == 0 || rxPkt == self.previousRxPkt) {
            self.callAudioState = VBotCallAudioStateNoAudioReceiving;
        } else {
            self.callAudioState = VBotCallAudioStateOK;
        }

        self.previousRxPkt = rxPkt;
        self.previousTxPkt = txPkt;

        NSDictionary *notificationUserInfo = @{
                                               VBotNotificationUserInfoCallKey : self,
                                               VBotNotificationUserInfoCallAudioStateKey: [NSNumber numberWithInt:self.callAudioState]
                                               };
        [[NSNotificationCenter defaultCenter] postNotificationName:VBotCallNoAudioForCallNotification object:notificationUserInfo];
    }

    self.audioCheckTimerFired++;
}

#pragma mark - User actions
- (void)answerWithCompletion:(void (^)(NSError *error))completion {
    pj_status_t status;

    if (self.callId != PJSUA_INVALID_ID) {
        pjsua_call_setting callSetting;
        pjsua_call_setting_default(&callSetting);

        if ([VBotEndpoint sharedEndpoint].endpointConfiguration.disableVideoSupport) {
            callSetting.vid_cnt = 0;
        }
        status = pjsua_call_answer2((int)self.callId, &callSetting, PJSIP_SC_OK, NULL, NULL);

        if (status != PJ_SUCCESS) {
            char statusmsg[PJ_ERR_MSG_SIZE];
            pj_strerror(status, statusmsg, sizeof(statusmsg));

            NSError *error = [NSError errorWithDomain:VBotCallErrorDomain
                                                 code:VBotCallErrorCannotAnswerCall
                                             userInfo:@{
                                                 NSLocalizedDescriptionKey: @"Could not answer call",
                                                 NSLocalizedFailureReasonErrorKey: [NSString stringWithFormat:@"PJSIP status code: %d", status]
                                             }];
            completion(error);
        } else {
            completion(nil);
        }
    } else {
        NSLog(@"callId không hợp lệ");
        NSError *error = [NSError errorWithDomain:VBotCallErrorDomain
                                             code:VBotCallErrorCannotAnswerCall
                                         userInfo:@{
                                             NSLocalizedDescriptionKey: @"Could not answer calli",
                                             NSLocalizedFailureReasonErrorKey: @"callId là PJSUA_INVALID_ID"
                                         }];
        completion(error);
    }
}

- (BOOL)decline:(NSError **)error {
    pj_status_t status = pjsua_call_answer((int)self.callId, PJSIP_SC_BUSY_HERE, NULL, NULL);
    if (status != PJ_SUCCESS) {
        if (error != NULL) {
            *error = [NSError VBotUnderlyingError:nil
                         localizedDescriptionKey:NSLocalizedString(@"Could not decline call", nil)
                     localizedFailureReasonError:[NSString stringWithFormat:NSLocalizedString(@"PJSIP status code: %d", nil), status]
                                     errorDomain:VBotCallErrorDomain
                                       errorCode:VBotCallErrorCannotDeclineCall];
        }
        return NO;
    }
    return YES;
}

- (BOOL)hangup:(NSError **)error {
    if (self.callId != PJSUA_INVALID_ID) {
        if (self.callState != VBotCallStateDisconnected) {
            self.userDidHangUp = YES;
            pj_status_t status = pjsua_call_hangup((int)self.callId, 0, NULL, NULL);
            if (status != PJ_SUCCESS) {
                if (error != NULL) {
                    *error = [NSError VBotUnderlyingError:nil
                                 localizedDescriptionKey:NSLocalizedString(@"Could not hangup call", nil)
                             localizedFailureReasonError:[NSString stringWithFormat:NSLocalizedString(@"PJSIP status code: %d", nil), status]
                                             errorDomain:VBotCallErrorDomain
                                               errorCode:VBotCallErrorCannotHangupCall];
                }
            }
            
            // Hanging up the call takes some time. It could fail due to a bad or no internet connection.
            // Check after some delay if the call was indeed disconnected. If it's not the case disconnect it manually.
            __weak VBotCall *weakSelf = self;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(VBotCallDelayTimeCheckSuccessfullHangup * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (!weakSelf || weakSelf.callState == VBotCallStateDisconnected) {
                    return; // After the delay, the call was indeed successfull disconnected.
                }
                
                // The call is still not disconnected, so manual disconnect it anyway.
                VBotLogDebug(@"Hangup unsuccessfull, possibly due to bad or no internet connection, so manually disconnecting the call.");
                
                // Mute the call to make sure the other party can't hear the user anymore.
                if (!weakSelf.muted) {
                    [weakSelf toggleMute:nil];
                }
                weakSelf.callState = VBotCallStateDisconnected;
            });
        }
    }
    return YES;
}

- (BOOL)toggleMute:(NSError **)error {
    if (self.callState != VBotCallStateConfirmed) {
        return YES;
    }

    pjsua_call_info callInfo;
    pjsua_call_get_info((pjsua_call_id)self.callId, &callInfo);

    if (callInfo.conf_slot <= 0) {
        if (error != NULL) {
            NSDictionary *userInfo = @{NSLocalizedDescriptionKey:NSLocalizedString(@"Could not toggle mute call", nil)};
            *error = [NSError errorWithDomain:VBotCallErrorDomain code:VBotCallErrorCannotToggleMute userInfo:userInfo];
        }
        VBotLogError(@"Unable to toggle mute, pjsua has not provided a valid conf_slot for this call");
        return NO;
    }

    pj_status_t status;
    if (!self.muted) {
        status = pjsua_conf_disconnect(0, callInfo.conf_slot);
    } else {
        status = pjsua_conf_connect(0, callInfo.conf_slot);
    }

    if (status == PJ_SUCCESS) {
        self.muted = !self.muted;
        VBotLogVerbose(self.muted ? @"Microphone muted": @"Microphone unmuted");
    } else {
        char statusmsg[PJ_ERR_MSG_SIZE];
        pj_strerror(status, statusmsg, sizeof(statusmsg));
        VBotLogError(@"Error toggle muting microphone in call %@, status: %s", self.uuid.UUIDString, statusmsg);

        if (error != NULL) {
            NSDictionary *userInfo = @{NSLocalizedDescriptionKey:NSLocalizedString(@"Could not toggle mute call", nil),
                                       NSLocalizedFailureReasonErrorKey:[NSString stringWithFormat:NSLocalizedString(@"PJSIP status code: %d", status)]
                                       };
            *error = [NSError errorWithDomain:VBotCallErrorDomain code:VBotCallErrorCannotToggleMute userInfo:userInfo];
        }
        return NO;
    }
    return YES;
}

- (BOOL)toggleHold:(NSError **)error {
    if (self.callState != VBotCallStateConfirmed) {
        return YES;
    }
    pj_status_t status;

    if (self.onHold) {
        pjsua_call_setting callSetting;
        pjsua_call_setting_default(&callSetting);
        callSetting.flag = PJSUA_CALL_UNHOLD;

        if ([VBotEndpoint sharedEndpoint].endpointConfiguration.disableVideoSupport) {
            callSetting.vid_cnt = 0;
        }
        
        status = pjsua_call_reinvite2((pjsua_call_id)self.callId, &callSetting, NULL);
    } else {
        status = pjsua_call_set_hold((pjsua_call_id)self.callId, NULL);
    }
    
    if (status == PJ_SUCCESS) {
        self.onHold = !self.onHold;
        VBotLogVerbose(self.onHold ? @"Call is on hold": @"On hold state ended");
    } else {
        char statusmsg[PJ_ERR_MSG_SIZE];
        pj_strerror(status, statusmsg, sizeof(statusmsg));
        VBotLogError(@"Error toggle holding in call %@, status: %s", self.uuid.UUIDString, statusmsg);

        if (error != NULL) {
            NSDictionary *userInfo = @{NSLocalizedDescriptionKey:NSLocalizedString(@"Could not toggle onhold call", nil),
                                       NSLocalizedFailureReasonErrorKey:[NSString stringWithFormat:NSLocalizedString(@"PJSIP status code: %d", status)]
                                       };
            *error = [NSError errorWithDomain:VBotCallErrorDomain code:VBotCallErrorCannotToggleHold userInfo:userInfo];
        }
        return NO;
    }
    return YES;
}

- (BOOL)sendDTMF:(NSString *)character error:(NSError **)error {
    // Return if the call is not confirmed or when the call is on hold.
    if (self.callState != VBotCallStateConfirmed || self.onHold) {
        return YES;
    }

    pj_status_t status;
    pj_str_t digits = [character pjString];

    // Try sending DTMF digits to remote using RFC 2833 payload format first.
    status = pjsua_call_dial_dtmf((pjsua_call_id)self.callId, &digits);

    if (status == PJ_SUCCESS) {
        VBotLogVerbose(@"Succesfull send character: %@ for DTMF for call %@", character, self.uuid.UUIDString);
    } else {
        // The RFC 2833 payload format did not work.
        const pj_str_t kSIPINFO = pj_str("INFO");

        for (NSUInteger i = 0; i < [character length]; ++i) {
            pjsua_msg_data messageData;
            pjsua_msg_data_init(&messageData);
            messageData.content_type = pj_str("application/dtmf-relay");

            NSString *messageBody = [NSString stringWithFormat:@"Signal=%C\r\nDuration=300", [character characterAtIndex:i]];
            messageData.msg_body = [messageBody pjString];

            status = pjsua_call_send_request((pjsua_call_id)self.callId, &kSIPINFO, &messageData);
            if (status == PJ_SUCCESS) {
                VBotLogVerbose(@"Succesfull send character: %@ for DTMF for call %@", character, self.uuid.UUIDString);
            } else {
                char statusmsg[PJ_ERR_MSG_SIZE];
                pj_strerror(status, statusmsg, sizeof(statusmsg));
                VBotLogError(@"Error error sending DTMF for call %@, status: %s", self.uuid.UUIDString, statusmsg);

                if (error != NULL) {
                    NSDictionary *userInfo = @{NSLocalizedDescriptionKey:NSLocalizedString(@"Could not send DTMF", nil),
                                               NSLocalizedFailureReasonErrorKey:[NSString stringWithFormat:NSLocalizedString(@"PJSIP status code: %d", status)]
                                               };
                    *error = [NSError errorWithDomain:VBotCallErrorDomain code:VBotCallErrorCannotSendDTMF userInfo:userInfo];
                }
                return NO;
            }
        }
    }
    return YES;
}

/**
 * The Actual audio interuption is handled in VBotAudioController
 */
- (void)audioInterruption:(NSNotification *)notification {
    if (([notification.name isEqualToString:VBotAudioControllerAudioInterrupted] && !self.onHold) ||
        ([notification.name isEqualToString:VBotAudioControllerAudioResumed] && self.onHold)) {
        [self toggleHold:nil];
    }
}

#pragma mark - KVO override

+ (BOOL)automaticallyNotifiesObserversOfCallState {
    return NO;
}

+ (BOOL)automaticallyNotifiesObserversOfTransferStatus {
    return NO;
}

#pragma mark - helper function

/**
 *  Get the caller_name and caller_number from a string
 *
 *  @param string the input string formatter like "name" <sip:42@sip.nl>
 *
 *  @return NSDictionary output like @{"caller_name: name, "caller_number": 42}.
 */
+ (NSDictionary *)getCallerInfoFromRemoteUri:(NSString *)string {
    NSString *callerName = @"";
    NSString *callerNumber = @"";
    NSString *callerHost;
    NSString *destination;
    NSRange delimterRange;
    NSRange atSignRange;
    NSRange semiColonRange;
    // Create a character set which will be trimmed from the string.
    NSMutableCharacterSet *charactersToTrim = [[NSCharacterSet whitespaceCharacterSet] mutableCopy];

    if ([[NSPredicate predicateWithFormat:@"SELF MATCHES '.+\\\\s\\\\(.+\\\\)'"] evaluateWithObject:string]) {
        /**
         * This matches the remote_uri for a format of: "destination (display_name)
         */

        delimterRange = [string rangeOfString:@" (" options:NSBackwardsSearch];

        // Create a character set which will be trimmed from the string.
        // All in-line whitespace and double quotes.
        [charactersToTrim addCharactersInString:@"\"()"];

        callerName = [[string substringFromIndex:delimterRange.location] stringByTrimmingCharactersInSet:charactersToTrim];

        destination = [string substringToIndex:delimterRange.location];

        // Get the last part of the uri starting from @
        atSignRange = [destination rangeOfString:@"@" options:NSBackwardsSearch];
        callerHost = [destination substringToIndex: atSignRange.location];

        // Get the telephone part starting from the :
        semiColonRange = [callerHost rangeOfString:@":" options:NSBackwardsSearch];
        callerNumber = [callerHost substringFromIndex:semiColonRange.location + 1];
    } else if ([[NSPredicate predicateWithFormat:@"SELF MATCHES '.+\\\\s<.+>'"] evaluateWithObject:string]) {
        /**
         *  This matches the remote_uri format of: "display_name" <destination_address>
         */

        delimterRange = [string rangeOfString:@" <" options:NSBackwardsSearch];

        // All in-line whitespace and double quotes.
        [charactersToTrim addCharactersInString:@"\""];

        // Get the caller_name from to where the first < is
        // and also trimming the characters defined in charactersToTrim.
        callerName = [[string substringToIndex:delimterRange.location] stringByTrimmingCharactersInSet:charactersToTrim];

        // Get the second part of the uri starting from the <
        NSRange destinationRange = NSMakeRange(delimterRange.location + 2,
                                               ([string length] - (delimterRange.location + 2) - 1));
        destination = [string substringWithRange: destinationRange];

        // Get the last part of the uri starting from @
        atSignRange = [destination rangeOfString:@"@" options:NSBackwardsSearch];
        callerHost = [destination substringToIndex: atSignRange.location];

        // Get the telephone part starting from the :
        semiColonRange = [callerHost rangeOfString:@":" options:NSBackwardsSearch];
        callerNumber = [callerHost substringFromIndex:semiColonRange.location + 1];
    } else if ([[NSPredicate predicateWithFormat:@"SELF MATCHES '<.+\\\\>'"] evaluateWithObject:string]) {
        /**
         * This matches the remote_uri format of: <sip:42@test.nl>
         */

        // Get the second part of the uri starting from the <
        NSRange destinationRange = NSMakeRange(1,
                                               ([string length] - 2));
        destination = [string substringWithRange: destinationRange];

        // Get the last part of the uri starting from @
        atSignRange = [destination rangeOfString:@"@" options:NSBackwardsSearch];
        callerHost = [destination substringToIndex: atSignRange.location];

        // Get the telephone part starting from the :
        semiColonRange = [callerHost rangeOfString:@":" options:NSBackwardsSearch];
        callerNumber = [callerHost substringFromIndex:semiColonRange.location + 1];
    } else {
        /**
         * This matches the remote_uri format of: sip:42@test.nl
         */

        // Get the last part of the uri starting from @
        atSignRange = [string rangeOfString:@"@" options:NSBackwardsSearch];
        if (atSignRange.location != NSNotFound) {
            callerHost = [string substringToIndex: atSignRange.location];

            // Get the telephone part starting from the :
            semiColonRange = [callerHost rangeOfString:@":" options:NSBackwardsSearch];
            if (semiColonRange.location != NSNotFound) {
                callerNumber = [callerHost substringFromIndex:semiColonRange.location + 1];
            }
        }
    }

    return @{
             @"caller_name": callerName,
             @"caller_number": callerNumber,
             };
}

#pragma mark - Stats

- (void)calculateStats {
    pjsua_call_info callInfo;
    pjsua_call_get_info((pjsua_call_id)self.callId, &callInfo);

    if (callInfo.media_status != PJSUA_CALL_MEDIA_ACTIVE) {
        VBotLogDebug(@"Stream is not active!");
    } else {
        VBotCallStats *callStats = [[VBotCallStats alloc] initWithCall: self];
        NSDictionary *stats = [callStats generate];
        if ([stats count] > 0) {
            self.activeCodec = stats[VBotCallStatsActiveCodec];
            self.MOS = [[stats objectForKey:VBotCallStatsMOS] floatValue];
            self.totalMBsUsed = [stats[VBotCallStatsTotalMBsUsed] floatValue];

            VBotLogDebug(@"activeCodec: %@ with MOS score: %f and MBs used: %f", self.activeCodec, self.MOS, self.totalMBsUsed);
        }
    }
    [self.audioCheckTimer invalidate];
}

- (NSString *)debugDescription {
    NSMutableString *desc = [[NSMutableString alloc] initWithFormat:@"%@\n", self];
    [desc appendFormat:@"\t UUID: %@\n", self.uuid.UUIDString];
    [desc appendFormat:@"\t Call ID: %ld\n", (long)self.callId];
    [desc appendFormat:@"\t CallState: %@\n", VBotCallStateString(self.callState)];
    [desc appendFormat:@"\t VBotMediaState: %@\n", VBotMediaStateString(self.mediaState)];
    [desc appendFormat:@"\t VBotCallTransferState: %@\n", VBotCallTransferStateString(self.transferStatus)];
    [desc appendFormat:@"\t Account: %ld\n", (long)self.account.accountId];
    [desc appendFormat:@"\t Last Status: %@(%ld)\n", self.lastStatusText, (long)self.lastStatus];
    [desc appendFormat:@"\t Number to Call: %@\n", self.numberToCall];
    [desc appendFormat:@"\t Local URI: %@\n", self.localURI];
    [desc appendFormat:@"\t Remote URI: %@\n", self.remoteURI];
    [desc appendFormat:@"\t Caller Name: %@\n", self.callerName];
    [desc appendFormat:@"\t Caller Number: %@\n", self.callerNumber];
    [desc appendFormat:@"\t Is Incoming: %@\n", self.isIncoming? @"YES" : @"NO"];
    [desc appendFormat:@"\t Is muted: %@\n", self.muted? @"YES" : @"NO"];
    [desc appendFormat:@"\t On Speaker: %@\n", self.speaker? @"YES" : @"NO"];
    [desc appendFormat:@"\t On Hold: %@\n", self.onHold? @"YES" : @"NO"];
    [desc appendFormat:@"\t User Did Hangup: %@\n", self.userDidHangUp? @"YES" : @"NO"];

    return desc;
}

@end
