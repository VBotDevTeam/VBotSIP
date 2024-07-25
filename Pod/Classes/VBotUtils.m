//
//  VBotUtils.m
//  Copyright © 2022 VPMedia. All rights reserved.
//

#import "VBotUtils.h"

@implementation VBotUtils

+ (NSString *)cleanPhoneNumber:(NSString *)phoneNumber {
    // Sometimes a number has a country code and the leading zero for the local area code. When cleaning the number, we keep the country code and strip out the leading area code.
    phoneNumber = [phoneNumber stringByReplacingOccurrencesOfString:@"(0)" withString:@""];

    phoneNumber = [[phoneNumber componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] componentsJoinedByString:@""];
    phoneNumber = [[phoneNumber componentsSeparatedByCharactersInSet:[[NSCharacterSet characterSetWithCharactersInString:@"+0123456789*#"] invertedSet]] componentsJoinedByString:@""];
    return [phoneNumber isEqualToString:@""] ? nil : phoneNumber;
}

@end
