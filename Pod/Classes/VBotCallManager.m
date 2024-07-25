//
//  VBotCallManager.m
//  Copyright © 2022 VPMedia. All rights reserved.
//
//

#import "VBotCallManager.h"
@import CallKit;
#import "Constants.h"
#import <CocoaLumberJack/CocoaLumberjack.h>
#import "VBotAccount.h"
#import "VBotAudioController.h"
#import "VBotCall.h"
#import "VBotEndpoint.h"
#import "VBotLogging.h"
#import "VBotSIP.h"

#define VBotBlockSafeRun(block, ...) block ? block(__VA_ARGS__) : nil
@interface VBotCallManager()
@property (strong, nonatomic) NSMutableArray *calls;
@property (strong, nonatomic) VBotAudioController *audioController;
@property (strong, nonatomic) CXCallController *callController;
@end

@implementation VBotCallManager

- (instancetype)init {
    if (self = [super init]) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(callStateChanged:)
                                                     name:VBotCallStateChangedNotification object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:VBotCallStateChangedNotification object:nil];
}

- (NSMutableArray *)calls {
    if (!_calls) {
        _calls = [[NSMutableArray alloc] init];
    }
    return _calls;
}

- (VBotAudioController *)audioController {
    if (!_audioController) {
        _audioController = [[VBotAudioController alloc] init];
    }
    return _audioController;
}

- (CXCallController *)callController {
    if (!_callController) {
        _callController = [[CXCallController alloc] init];
    }
    return _callController;
}

- (void)startCallToNumber:(NSString *)number forAccount:(VBotAccount *)account completion:(void (^)(VBotCall *call, NSError *error))completion {
    [account registerAccountWithCompletion:^(BOOL success, NSError * _Nullable error) {
        if (!success) {
            VBotLogError(@"Error registering the account: %@", error);
            dispatch_async(dispatch_get_main_queue(), ^{
                VBotBlockSafeRun(completion, nil, error);
            });
        } else {
            VBotCall *call = [[VBotCall alloc] initOutboundCallWithNumberToCall:number account:account];
            [self addCall:call];

            CXHandle *numberHandle = [[CXHandle alloc] initWithType:CXHandleTypePhoneNumber value:call.numberToCall];
            CXAction *startCallAction = [[CXStartCallAction alloc] initWithCallUUID:call.uuid handle:numberHandle];

            [self requestCallKitAction:startCallAction completion:^(NSError *error) {
                if (error) {
                    VBotLogError(@"Error requesting \"Start Call Transaction\" error: %@", error);
                    [self removeCall:call];
                    dispatch_async(dispatch_get_main_queue(), ^{
                        VBotBlockSafeRun(completion, nil, error);
                    });
                } else {
                    VBotLogInfo(@"\"Start Call Transaction\" requested succesfully for Call(%@) with account(%ld)", call.uuid.UUIDString, (long)account.accountId);
                    dispatch_async(dispatch_get_main_queue(), ^{
                        VBotBlockSafeRun(completion, call, nil);
                    });
                }
            }];
        }
    }];
}

- (void)answerCall:(VBotCall *)call completion:(void (^)(NSError *error))completion {
    [call answerWithCompletion:completion];
}

- (void)endCall:(VBotCall *)call completion:(void (^)(NSError *error))completion {
    CXAction *endCallAction = [[CXEndCallAction alloc] initWithCallUUID:call.uuid];
    [self requestCallKitAction:endCallAction completion:completion];
    VBotLogInfo(@"\"End Call Transaction\" requested succesfully for Call(%@)", call.uuid.UUIDString);
}

- (void)toggleMuteForCall:(VBotCall *)call completion:(void (^)(NSError *error))completion {
    CXAction *toggleMuteAction = [[CXSetMutedCallAction alloc] initWithCallUUID:call.uuid muted:false];
    [self requestCallKitAction:toggleMuteAction completion:completion];
    VBotLogInfo(@"\"Mute Call Transaction\" requested succesfully for Call(%@)", call.uuid.UUIDString);
}

- (void)toggleHoldForCall:(VBotCall *)call completion:(void (^)(NSError * _Nullable))completion {
    CXAction *toggleHoldAction = [[CXSetHeldCallAction alloc] initWithCallUUID:call.uuid onHold:!call.onHold];
    [self requestCallKitAction:toggleHoldAction completion:completion];
    VBotLogInfo(@"\"Hold Call Transaction\" requested succesfully for Call(%@)", call.uuid.UUIDString);
}

- (void)sendDTMFForCall :(VBotCall *)call character:(NSString *)character completion:(void (^)(NSError * _Nullable))completion {
    CXAction *dtmfAction = [[CXPlayDTMFCallAction alloc] initWithCallUUID:call.uuid digits:character type:CXPlayDTMFCallActionTypeSingleTone];
    [self requestCallKitAction:dtmfAction completion:completion];
    VBotLogInfo(@"\"Sent DTMF Transaction\" requested succesfully for Call(%@)", call.uuid.UUIDString);
}

- (void)requestCallKitAction:(CXAction *)action completion:(void (^)(NSError *error))completion {
    CXTransaction *transaction = [[CXTransaction alloc] initWithAction:action];
    [self.callController requestTransaction:transaction completion:^(NSError * _Nullable error) {
        if (error) {
            VBotLogError(@"Error requesting transaction: %@. Error:%@", transaction, error);
            dispatch_async(dispatch_get_main_queue(), ^{
                VBotBlockSafeRun(completion,error);
            });
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                VBotBlockSafeRun(completion,nil);
            });
        }
    }];
}

- (void)addCall:(VBotCall *)call {
    [self.calls addObject:call];
    VBotLogVerbose(@"Call(%@) added. Calls count:%ld",call.uuid.UUIDString, (long)[self.calls count]);
}

- (void)removeCall:(VBotCall *)call {
    [self.calls removeObject:call];

    if ([self.calls count] == 0) {
        self.calls = nil;
        self.audioController = nil;
    }
    VBotLogVerbose(@"Call(%@) removed. Calls count: %ld",call.uuid.UUIDString, (long)[self.calls count]);
}

- (void)endAllCalls {
    if ([self.calls count] == 0) {
        return;
    }
    
    for (VBotCall *call in self.calls) {
        VBotLogVerbose(@"Ending call: %@", call.uuid.UUIDString);
        NSError *hangupError;
        [call hangup:&hangupError];
        if (hangupError) {
            VBotLogError(@"Could not hangup call(%@). Error: %@", call.uuid.UUIDString, hangupError);
        } else {
            [self.audioController deactivateAudioSession];
        }
        [self removeCall:call];
    }
}

- (void)endAllCallsForAccount:(VBotAccount *)account {
    for (VBotCall *call in [self callsForAccount:account]) {
        [self endCall:call completion:nil];
    }
}

/**
 *  Checks if there is a call with the given UUID.
 *
 *  @param uuid The UUID of the call to find.
 *
 *  @retrun A VBotCall object or nil if not found.
 */
- (VBotCall *)callWithUUID:(NSUUID *)uuid {
    VBotLogVerbose(@"Looking for a call with UUID:%@", uuid.UUIDString);
    NSUInteger callIndex = [self.calls indexOfObjectPassingTest:^BOOL(VBotCall* _Nonnull call, NSUInteger idx, BOOL * _Nonnull stop) {
        if ([call.uuid isEqual:uuid] && uuid) {
            return YES;
        }
        return NO;
    }];

    if (callIndex != NSNotFound) {
        VBotCall *call = [self.calls objectAtIndex:callIndex];
        VBotLogDebug(@"VBotCall found for UUID:%@ VBotCall:%@", uuid.UUIDString, call);
        return call;
    }
    VBotLogDebug(@"No VBotCall found for UUID:%@", uuid.UUIDString);
    return nil;
}

- (VBotCall *)callWithCallId:(NSInteger)callId {
    NSUInteger callIndex = [self.calls indexOfObjectPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
        VBotCall *call = (VBotCall *)obj;
        if (call.callId == callId && call.callId != PJSUA_INVALID_ID) {
            return YES;
        }
        return NO;
    }];

    if (callIndex != NSNotFound) {
        return [self.calls objectAtIndex:callIndex];
    }
    return nil;
}

- (NSArray *)callsForAccount:(VBotAccount *)account {
    if ([self.calls count] == 0) {
        return nil;
    }

    NSMutableArray *callsForAccount = [[NSMutableArray alloc] init];
    for (VBotCall *call in self.calls) {
        if ([call.account isEqual:account]) {
            [callsForAccount addObject:call];
        }
    }

    if ([callsForAccount count]) {
        return callsForAccount;
    } else {
        return nil;
    }
}

- (VBotCall *)firstCallForAccount:(VBotAccount *)account {
    NSArray *callsForAccount = [self callsForAccount:account];
    return [callsForAccount firstObject];
}

- (VBotCall *)firstActiveCallForAccount:(VBotAccount *)account {
    for (VBotCall *call in [self activeCallsForAccount:(VBotAccount *)account]) {
        if (call.callState > VBotCallStateNull && call.callState < VBotCallStateDisconnected) {
            return call;
        }
    }
    return nil;
}

- (VBotCall *)lastCallForAccount:(VBotAccount *)account {
    NSArray *callsForAccount = [self callsForAccount:account];
    return [callsForAccount lastObject];
}

- (NSArray <VBotCall *> *)activeCallsForAccount:(VBotAccount *)account {
    if ([self.calls count] == 0) {
        
    }

    NSMutableArray *activeCallsForAccount = [[NSMutableArray alloc] init];
    for (VBotCall *call in self.calls) {
        if (call.callState > VBotCallStateNull && call.callState < VBotCallStateDisconnected) {
            if ([call.account isEqual:account]) {
                [activeCallsForAccount addObject:call];
            }
        }
    }

    if ([activeCallsForAccount count]) {
        return activeCallsForAccount;
    } else {
        return nil;
    }
}

- (void)reinviteActiveCallsForAccount:(VBotAccount *)account {
    VBotLogDebug(@"Reinviting calls");
    for (VBotCall *call in [self activeCallsForAccount:account]) {
        [call reinvite];
    }
}

- (void)updateActiveCallsForAccount:(VBotAccount *)account {
    VBotLogDebug(@"Sent UPDATE for calls");
    for (VBotCall *call in [self activeCallsForAccount:account]) {
        [call update];
    }
}

- (void)callStateChanged:(NSNotification *)notification {
    __weak VBotCall *call = [[notification userInfo] objectForKey:VBotNotificationUserInfoCallKey];
    if (call.callState == VBotCallStateDisconnected) {
        [self removeCall:call];
    }
}
@end
