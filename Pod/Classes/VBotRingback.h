//
//  VBotRingback.h
//  Copyright © 2022 VPMedia. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface VBotRingback : NSObject

/**
 *  The current status if the Ringback is playing.
 */
@property (nonatomic) BOOL isPlaying;

/**
 *  This will start the ringback if it isn't playing already.
 */
- (void)start;

/**
 *  This will stop the ringback if it isn't stopped already.
 */
- (void)stop;

@end
