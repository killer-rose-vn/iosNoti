//
//  NotificationPayloadBuilder.m
//

#import "NotificationPayloadBuilder.h"
#import "ChargeRecord.h"
#import "ConfigManager.h"
#import "SignatureHelper.h"

NSString * const IosNotiPayloadTypeNotification = @"NOTIFICATION";

static NSString * INSafeString(NSString *value) {
    if (![value isKindOfClass:[NSString class]]) {
        return @"";
    }
    return value;
}

@implementation NotificationPayloadBuilder

+ (NSDictionary *)payloadWithAppID:(NSString *)appID
                            sender:(NSString *)sender
                           message:(NSString *)message
                          recordID:(NSString *)recordID
                            timeMS:(NSString *)timeMS {
    ConfigManager *config = [ConfigManager sharedManager];

    NSString *safeTime   = timeMS.length > 0 ? timeMS : [SignatureHelper currentTimestampMillisecondsString];
    NSString *safeID     = recordID.length > 0 ? recordID : safeTime;
    NSString *safeAppID  = INSafeString(appID);
    NSString *safeSender = INSafeString(sender);
    NSString *safeMsg    = INSafeString(message);
    NSString *sim        = INSafeString(config.simID);
    NSString *secret     = INSafeString(config.secretKey);

    // signature = MD5_lowercase(app_id|id|time|sim|secret_key)
    NSString *signature = [SignatureHelper signatureWithAppID:safeAppID
                                                           id:safeID
                                                         time:safeTime
                                                          sim:sim
                                                    secretKey:secret
                                                    useSHA256:NO] ?: @"";

    return @{
        @"app_id"        : safeAppID,
        @"sender"        : safeSender,
        @"time"          : safeTime,
        @"id"            : safeID,
        @"tracking_code" : sim,
        @"message"       : safeMsg,
        @"signature"     : signature,
        @"type"          : IosNotiPayloadTypeNotification,
        @"sim"           : sim,
    };
}

+ (id)recordFromPayload:(NSDictionary *)payload
           responseBody:(NSString *)responseBody
             httpStatus:(NSInteger)httpStatus
              createdAt:(NSTimeInterval)createdAt {
    if (![payload isKindOfClass:[NSDictionary class]]) {
        return nil;
    }

    ChargeRecord *record = [[ChargeRecord alloc] init];
    record.recordID     = INSafeString(payload[@"id"]);
    record.appID        = INSafeString(payload[@"app_id"]);
    record.sender       = INSafeString(payload[@"sender"]);
    record.message      = INSafeString(payload[@"message"]);
    record.time         = INSafeString(payload[@"time"]);
    record.trackingCode = INSafeString(payload[@"tracking_code"]);
    record.signature    = INSafeString(payload[@"signature"]);
    record.sim          = INSafeString(payload[@"sim"]);
    record.httpStatus   = httpStatus;
    record.responseBody = INSafeString(responseBody);
    record.createdAt    = createdAt;

    NSError *error = nil;
    NSData *json = [NSJSONSerialization dataWithJSONObject:payload options:0 error:&error];
    if (json) {
        record.payloadJSON = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] ?: @"";
    } else {
        record.payloadJSON = @"";
    }
    return record;
}

@end
