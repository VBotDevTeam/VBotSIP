//
//  VBotNetworkMonitor.m
//  Copyright © 2022 VPMedia. All rights reserved.
//

#import "VBotNetworkMonitor.h"

#import "Constants.h"
#import "Reachability.h"
#import "VBotLogging.h"


static double const VBotNetworkMonitorDelayTimeForNotification = 1;

NSString * const VBotNetworkMonitorChangedNotification = @"VBotNetworkMonitorChangedNotification";

@interface VBotNetworkMonitor()

@property (strong, nonatomic) NSString *host;
@property (strong, nonatomic) Reachability *networkMonitor;
@property (nonatomic) BOOL isChangingNetwork;

@end

@implementation VBotNetworkMonitor

- (VBotNetworkMonitor *)initWithHost:(NSString *)host {
    if (self = [super init]) {
        self.host = host;
    }
    return self;
}

# pragma mark - Properties

- (Reachability *)networkMonitor {
    if (!_networkMonitor) {
        _networkMonitor = [Reachability reachabilityWithHostName:self.host];
    }
    return _networkMonitor;
}

#pragma mark - Actions

- (void)startMonitoring {
    [self.networkMonitor startNotifier];
    // Delay the registering of the notification to ignore the initial reachability changed notifications.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(VBotNetworkMonitorDelayTimeForNotification * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(internetConnectionChanged:) name:kReachabilityChangedNotification object:nil];
    });
}

- (void)stopMonitoring {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:kReachabilityChangedNotification object:nil];
    [self.networkMonitor stopNotifier];
    self.networkMonitor = nil;
}

#pragma mark - Notifications

- (void)internetConnectionChanged:(NSNotification *)notification {
    /**
     *  Don't respond immediately to every network change. Because network changes will happen rapidly and go back an forth
     *  a couple of times, wait a little before posting the notification.
     */
    VBotLogDebug(@"Internet connection changed");

    if (self.isChangingNetwork) {
        return;
    }
    self.isChangingNetwork = YES;

     VBotNetworkMonitor *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(VBotNetworkMonitorDelayTimeForNotification * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        VBotLogInfo(@"Posting notification that internet connection has changed.");
        weakSelf.isChangingNetwork = NO;
        [[NSNotificationCenter defaultCenter] postNotificationName:VBotNetworkMonitorChangedNotification object:nil];
    });
}

@end
