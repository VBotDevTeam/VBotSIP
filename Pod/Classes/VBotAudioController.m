//
//  VBotAudioController.m
//  Copyright © 2022 VPMedia. All rights reserved.
//

#import "VBotAudioController.h"

@import AVFoundation;
#import "Constants.h"
#import "VBotSIP.h"
#import "VBotLogging.h"

NSString * const VBotAudioControllerAudioInterrupted = @"VBotAudioControllerAudioInterrupted";
NSString * const VBotAudioControllerAudioResumed = @"VBotAudioControllerAudioResumed";

@implementation VBotAudioController

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:AVAudioSessionInterruptionNotification
                                                  object:nil];
}

- (BOOL)hasBluetooth {
    NSArray *availableInputs = [[AVAudioSession sharedInstance] availableInputs];

    for (AVAudioSessionPortDescription *input in availableInputs) {
        if ([input.portType isEqualToString:AVAudioSessionPortBluetoothHFP]) {
            return YES;
        }
    }
    return NO;
}

- (VBotAudioControllerOutputs)output {
    AVAudioSessionRouteDescription *route = [[AVAudioSession sharedInstance] currentRoute];
    for (AVAudioSessionPortDescription *output in route.outputs) {
        if ([output.portType isEqualToString:AVAudioSessionPortBluetoothHFP]) {
            return VBotAudioControllerOutputBluetooth;
        } else if ([output.portType isEqualToString:AVAudioSessionPortBuiltInSpeaker]) {
            return VBotAudioControllerOutputSpeaker;
        }
    }
    return VBotAudioControllerOutputOther;
}

- (void)setOutput:(VBotAudioControllerOutputs)output {
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    if (output == VBotAudioControllerOutputSpeaker) {
        [audioSession overrideOutputAudioPort:AVAudioSessionPortOverrideSpeaker error:nil];
    } else if (output == VBotAudioControllerOutputOther) {
        [audioSession overrideOutputAudioPort:AVAudioSessionPortOverrideNone error:nil];
    }
    VBotLogVerbose(output == VBotAudioControllerOutputSpeaker ? @"Speaker modus activated": @"Speaker modus deactivated");
}

- (void)configureAudioSession {
    NSError *audioSessionCategoryError;
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayAndRecord error:&audioSessionCategoryError];
    VBotLogVerbose(@"Setting AVAudioSessionCategory to \"Play and Record\"");

    if (audioSessionCategoryError) {
        VBotLogError(@"Error setting the correct AVAudioSession category");
    }

    // set the mode to voice chat
    NSError *audioSessionModeError;
    [[AVAudioSession sharedInstance] setMode:AVAudioSessionModeVoiceChat error:&audioSessionModeError];
    VBotLogVerbose(@"Setting AVAudioSessionCategory to \"Mode Voice Chat\"");

    if (audioSessionModeError) {
        VBotLogError(@"Error setting the correct AVAudioSession mode");
    }
}

- (void)checkCurrentThreadIsRegisteredWithPJSUA {
    static pj_thread_desc a_thread_desc;
    static pj_thread_t *a_thread;
    if (!pj_thread_is_registered()) {
        pj_thread_register("VialerPJSIP", a_thread_desc, &a_thread);
    }
}

- (BOOL)activateSoundDevice {
    VBotLogDebug(@"Activating audiosession");
    [self checkCurrentThreadIsRegisteredWithPJSUA];
    pjsua_set_no_snd_dev();
    pj_status_t status;
    status = pjsua_set_snd_dev(PJMEDIA_AUD_DEFAULT_CAPTURE_DEV, PJMEDIA_AUD_DEFAULT_PLAYBACK_DEV);
    if (status == PJ_SUCCESS) {
        return YES;
    } else {
        char statusmsg[PJ_ERR_MSG_SIZE];
        pj_strerror(status, statusmsg, sizeof(statusmsg));
        VBotLogWarning(@"Failure in enabling sound device, status: %s", statusmsg);
        
        return NO;
    }
}

- (void)activateAudioSession {
    if ([self activateSoundDevice]) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(audioInterruption:)
                                                     name:AVAudioSessionInterruptionNotification
                                                   object:nil];
    }
}

- (void)deactivateSoundDevice {
    VBotLogDebug(@"Deactivating audiosession");
    [self checkCurrentThreadIsRegisteredWithPJSUA];
    pjsua_set_no_snd_dev();

}

- (void)deactivateAudioSession {
    [self deactivateSoundDevice];
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:AVAudioSessionInterruptionNotification
                                                  object:nil];
}

/**
 *  Function called on AVAudioSessionInterruptionNotification
 *
 *  The class registers for AVAudioSessionInterruptionNotification to be able to regain
 *  audio after it has been interrupted by another call or other audio event.
 *
 *  @param notification The notification which lead to this function being invoked over GCD.
 */
- (void)audioInterruption:(NSNotification *)notification {
    NSInteger avInteruptionType = [[notification.userInfo valueForKey:AVAudioSessionInterruptionTypeKey] intValue];
    if (avInteruptionType == AVAudioSessionInterruptionTypeBegan) {
        [self deactivateSoundDevice];
        [[NSNotificationCenter defaultCenter] postNotificationName:VBotAudioControllerAudioInterrupted
                                                            object:self
                                                          userInfo:nil];

    } else if (avInteruptionType == AVAudioSessionInterruptionTypeEnded) {
        [self activateSoundDevice];
        [[NSNotificationCenter defaultCenter] postNotificationName:VBotAudioControllerAudioResumed
                                                            object:self
                                                          userInfo:nil];
    }
}

@end
