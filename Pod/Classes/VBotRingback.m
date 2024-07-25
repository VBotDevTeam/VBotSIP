//
//  VBotRingback.m
//  Copyright © 2022 VPMedia. All rights reserved.
//

#import "VBotRingback.h"

#import "Constants.h"
#import "NSString+PJString.h"
#import <VialerPJSIP/pjsua.h>
#import "VBotEndpoint.h"
#import "VBotLogging.h"

static int const VBotRingbackChannelCount = 1;
static int const VBotRingbackRingbackCount = 1;
static int const VBotRingbackFrequency1 = 440;
static int const VBotRingbackFrequency2 = 440;
static int const VBotRingbackOnDuration = 2000;
static int const VBotRingbackOffDuration = 4000;
static int const VBotRingbackInterval = 4000;

@interface VBotRingback()
@property (readonly, nonatomic) NSInteger ringbackSlot;
@property (readonly, nonatomic) pjmedia_port *ringbackPort;
@end

@implementation VBotRingback

-(instancetype)init {
    if (!(self = [super init])) {
        return nil;
    }

    VBotEndpoint *endpoint = [VBotEndpoint sharedEndpoint];

    pj_status_t status;
    pjmedia_tone_desc tone[VBotRingbackRingbackCount];
    pj_str_t name = pj_str("tone");

    //TODO make ptime and channel count not constant?

    NSUInteger samplesPerFrame = (PJSUA_DEFAULT_AUDIO_FRAME_PTIME * endpoint.endpointConfiguration.clockRate * VBotRingbackChannelCount) / 1000;

    status = pjmedia_tonegen_create2(endpoint.pjPool, &name, (unsigned int)endpoint.endpointConfiguration.clockRate, VBotRingbackChannelCount, (unsigned int)samplesPerFrame, 16, PJMEDIA_TONEGEN_LOOP, &_ringbackPort);

    if (status != PJ_SUCCESS) {
        char statusmsg[PJ_ERR_MSG_SIZE];
        pj_strerror(status, statusmsg, sizeof(statusmsg));
        VBotLogDebug(@"Error creating ringback tones, status: %s", statusmsg);
        return nil;
    }

    pj_bzero(&tone, sizeof(tone));

    for (int i = 0; i < VBotRingbackRingbackCount; ++i) {
        tone[i].freq1 = VBotRingbackFrequency1;
        tone[i].freq2 = VBotRingbackFrequency2;
        tone[i].on_msec = VBotRingbackOnDuration;
        tone[i].off_msec = VBotRingbackOffDuration;
    }

    tone[VBotRingbackRingbackCount - 1].off_msec = VBotRingbackInterval;

    pjmedia_tonegen_play(self.ringbackPort, VBotRingbackRingbackCount, tone, PJMEDIA_TONEGEN_LOOP);

    status = pjsua_conf_add_port(endpoint.pjPool, [self ringbackPort], (int *)&_ringbackSlot);

    if (status != PJ_SUCCESS) {
        char statusmsg[PJ_ERR_MSG_SIZE];
        pj_strerror(status, statusmsg, sizeof(statusmsg));
        VBotLogDebug(@"Error adding media port for ringback tones, status: %s", statusmsg);
        return nil;
    }
    return self;
}

-(void)dealloc {
    [self checkCurrentThreadIsRegisteredWithPJSUA];
    // Destory the conference port otherwise the maximum number of ports will reached and pjsip will crash.
    pj_status_t status = pjsua_conf_remove_port((int)self.ringbackSlot);
    if (status != PJ_SUCCESS) {
        char statusmsg[PJ_ERR_MSG_SIZE];
        pj_strerror(status, statusmsg, sizeof(statusmsg));
        VBotLogWarning(@"Error removing the port, status: %s", statusmsg);
        return;
    }
    
    pjmedia_port_destroy(self.ringbackPort);
}

-(void)start {
    VBotLogInfo(@"Start ringback, isPlaying: %@", self.isPlaying ? @"YES" : @"NO");
    if (!self.isPlaying) {
        pjsua_conf_connect((int)self.ringbackSlot, 0);
        self.isPlaying = YES;
    }
}

-(void)stop {
    VBotLogInfo(@"Stop ringback, isPlaying: %@", self.isPlaying ? @"YES" : @"NO");
    if (self.isPlaying) {
        pjsua_conf_disconnect((int)self.ringbackSlot, 0);
        self.isPlaying = NO;

        // Destory the conference port otherwise the maximum number of ports will reached and pjsip will crash.
        pj_status_t status = pjsua_conf_remove_port((int)self.ringbackSlot);
        if (status != PJ_SUCCESS) {
            char statusmsg[PJ_ERR_MSG_SIZE];
            pj_strerror(status, statusmsg, sizeof(statusmsg));
            VBotLogWarning(@"Error removing the port, status: %s", statusmsg);
        }
    }
}

- (void)checkCurrentThreadIsRegisteredWithPJSUA {
    static pj_thread_desc a_thread_desc;
    static pj_thread_t *a_thread;
    if (!pj_thread_is_registered()) {
        pj_thread_register("VialerPJSIP", a_thread_desc, &a_thread);
    }
}
@end
