//
//  VBotRingtone.m
//  Copyright © 2022 VPMedia. All rights reserved.
//  Code based on https://github.com/petester42/swig/blob/master/Pod/Classes/Call/SWRingtone.m
//

#import "VBotRingtone.h"

#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
#import "Constants.h"
#import "VBotLogging.h"
#import <UIKit/UIKit.h>

static NSUInteger const VBotSIPVibrateDuration = 1;

@interface VBotRingtone()

@property (strong, nonatomic) AVAudioPlayer *audioPlayer;
@property (strong, nonatomic) NSTimer *vibrateTimer;
@property (strong, nonatomic) NSURL *fileURL;

@end

@implementation VBotRingtone

- (instancetype)initWithRingtonePath:(NSURL *)ringtonePath {
    if (self = [super init]) {
        if (!ringtonePath) {
            return nil;
        }
        self.fileURL = ringtonePath;
    }
    return self;
}

- (NSTimer *)vibrateTimer {
    if (!_vibrateTimer) {
        _vibrateTimer = [NSTimer timerWithTimeInterval:VBotSIPVibrateDuration target:self selector:@selector(vibrate) userInfo:nil repeats:YES];
    }
    return _vibrateTimer;
}

- (AVAudioPlayer *)audioPlayer {
	if (!_audioPlayer) {
        NSError *error;
		_audioPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:self.fileURL error:&error];
        _audioPlayer.numberOfLoops = -1;
        if (error) {
            VBotLogError(@"Audioplayer: %@", [error description]);
        }
	}
	return _audioPlayer;
}

- (void)dealloc {
    [self.audioPlayer stop];
    self.audioPlayer = nil;

    [self.vibrateTimer invalidate];
    self.vibrateTimer = nil;
}

- (BOOL)isPlaying {
    return self.audioPlayer.isPlaying;
}

- (void)start {
    [self startWithVibrate:YES];
}

- (void)startWithVibrate:(BOOL)vibrate {
    if (!self.isPlaying) {
        [self.audioPlayer prepareToPlay];
        [self configureAudioSessionBeforeRingtoneIsPlayed];
        [self.audioPlayer play];
        if (vibrate) {
            [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:nil];
            [[NSRunLoop mainRunLoop] addTimer:self.vibrateTimer forMode:NSRunLoopCommonModes];
        }
    }
}

- (void)stop {
    if (self.isPlaying) {
        [self.audioPlayer stop];
        [self.vibrateTimer invalidate];
    }
    [self.audioPlayer setCurrentTime:0];
    [self configureAudioSessionAfterRingtoneStopped];
}

- (void)vibrate {
    AudioServicesPlayAlertSound(kSystemSoundID_Vibrate);
}

- (void)configureAudioSessionBeforeRingtoneIsPlayed {
    VBotLogVerbose(@"Configuring Audio before playing ringtone");
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];

    // Set the audio session category. The category that is set repects the silent switch.
    NSError *setCategoryError;
    BOOL setCategorySuccess = [audioSession setCategory:AVAudioSessionCategorySoloAmbient
                                                  error:&setCategoryError];
    if (!setCategorySuccess) {
        if (setCategoryError != NULL) {
            VBotLogWarning(@"Error setting audioplayer category: %@", setCategoryError);
        }
    }

    // Temporarily changes the current audio route. We will not override the output port and let the
    // system default handle the outputs.
    NSError *overrideOutputAudioPortError;
    BOOL overrideOutputAudioPortSuccess = [audioSession overrideOutputAudioPort:AVAudioSessionPortOverrideNone
                                                                          error:&overrideOutputAudioPortError];
    if (!overrideOutputAudioPortSuccess) {
        if (overrideOutputAudioPortError != NULL) {
            VBotLogWarning(@"Error overriding audio port: %@", overrideOutputAudioPortError);
        }
    }

    // Activate the audio session.
    NSError *setActiveError;
    BOOL setActiveSuccess = [audioSession setActive:YES error:&setActiveError];
    if (!setActiveSuccess) {
        if (setActiveError != NULL) {
            VBotLogWarning(@"Error activatiing audio: %@", setActiveError);
        }
    }
}

- (void)configureAudioSessionAfterRingtoneStopped {
    VBotLogVerbose(@"Configuring Audio after ringtone has stoped");
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];

    // Set the audio session category. The category that is set is able to handle VoIP calls.
    NSError *setCategoryError;
    BOOL setCategorySuccess = [audioSession setCategory:AVAudioSessionCategoryPlayAndRecord
                                                  error:&setCategoryError];
    if (!setCategorySuccess) {
        if (setCategoryError != NULL) {
            VBotLogWarning(@"Error setting audioplayer category: %@", setCategoryError);
        }
    }
}

@end
