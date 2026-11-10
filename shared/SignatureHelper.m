//
//  SignatureHelper.m
//

#import "SignatureHelper.h"
#import <CommonCrypto/CommonDigest.h>

@implementation SignatureHelper

#pragma mark - Helpers

static NSString * INSafeString(NSString *value) {
    if (value == nil || (id)value == [NSNull null]) {
        return @"";
    }
    if (![value isKindOfClass:[NSString class]]) {
        return [value description] ?: @"";
    }
    return value;
}

static NSString * INHexDigest(const unsigned char *bytes, NSUInteger length) {
    NSMutableString *hex = [NSMutableString stringWithCapacity:length * 2];
    for (NSUInteger i = 0; i < length; i++) {
        [hex appendFormat:@"%02x", bytes[i]];   // %02x = hex chữ THƯỜNG
    }
    return [hex copy];
}

#pragma mark - Public

+ (NSString *)plainTextWithAppID:(NSString *)appID
                              id:(NSString *)recordID
                            time:(NSString *)time
                             sim:(NSString *)sim
                       secretKey:(NSString *)secretKey {
    // ĐÚNG thứ tự: app_id | id | time | sim | secret_key
    return [NSString stringWithFormat:@"%@|%@|%@|%@|%@",
            INSafeString(appID),
            INSafeString(recordID),
            INSafeString(time),
            INSafeString(sim),
            INSafeString(secretKey)];
}

+ (NSString *)md5Lowercase:(NSString *)input {
    if (input == nil) {
        return nil;
    }
    NSData *data = [input dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_MD5_DIGEST_LENGTH];
    CC_MD5(data.bytes, (CC_LONG)data.length, digest);
    return INHexDigest(digest, CC_MD5_DIGEST_LENGTH);
}

+ (NSString *)sha256Lowercase:(NSString *)input {
    if (input == nil) {
        return nil;
    }
    NSData *data = [input dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    return INHexDigest(digest, CC_SHA256_DIGEST_LENGTH);
}

+ (NSString *)signatureWithAppID:(NSString *)appID
                              id:(NSString *)recordID
                            time:(NSString *)time
                             sim:(NSString *)sim
                       secretKey:(NSString *)secretKey
                       useSHA256:(BOOL)useSHA256 {
    NSString *plain = [self plainTextWithAppID:appID
                                            id:recordID
                                          time:time
                                           sim:sim
                                     secretKey:secretKey];
    return useSHA256 ? [self sha256Lowercase:plain] : [self md5Lowercase:plain];
}

+ (NSString *)signatureNowWithAppID:(NSString *)appID
                                 id:(NSString *)recordID
                                sim:(NSString *)sim
                          secretKey:(NSString *)secretKey {
    return [self signatureWithAppID:appID
                                 id:recordID
                               time:[self currentTimestampString]
                                sim:sim
                          secretKey:secretKey
                          useSHA256:NO];
}

+ (NSString *)currentTimestampString {
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    return [NSString stringWithFormat:@"%lld", (long long)now];
}

+ (NSString *)currentTimestampMillisecondsString {
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    return [NSString stringWithFormat:@"%lld", (long long)(now * 1000.0)];
}

@end
