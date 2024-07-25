//
//  NSString+PJString.m
//  Copyright © 2022 VPMedia. All rights reserved.
//

#import "NSError+VBotError.h"

@implementation NSError (VBotError)

+ (NSError *)VBotUnderlyingError:(NSError *)underlyingErrorKey localizedDescriptionKey:(NSString *)localizedDescriptionKey localizedFailureReasonError:(NSString *)localizedFailureReasonError errorDomain:(NSString *)errorDomain errorCode:(NSUInteger)errorCode {
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];

    if (underlyingErrorKey) {
        [userInfo setObject:underlyingErrorKey forKey:NSUnderlyingErrorKey];
    }

    if (localizedDescriptionKey) {
        [userInfo setObject:localizedDescriptionKey forKey:NSLocalizedDescriptionKey];
    }

    if (localizedFailureReasonError) {
        [userInfo setObject:localizedFailureReasonError forKey:NSLocalizedFailureReasonErrorKey];
    }

    return [NSError errorWithDomain:errorDomain code:errorCode userInfo:[userInfo copy]];
}

@end
