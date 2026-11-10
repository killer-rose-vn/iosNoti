//
//  ChargeRecord.m
//

#import "ChargeRecord.h"

@implementation ChargeRecord

- (NSDate *)createdDate {
    return [NSDate dateWithTimeIntervalSince1970:self.createdAt];
}

- (NSDictionary *)payloadDictionary {
    return @{
        @"app_id"        : self.appID ?: @"",
        @"sender"        : self.sender ?: @"",
        @"time"          : self.time ?: @"",
        @"id"            : self.recordID ?: @"",
        @"tracking_code" : self.trackingCode ?: @"",
        @"message"       : self.message ?: @"",
        @"signature"     : self.signature ?: @"",
        @"type"          : self.type.length > 0 ? self.type : @"NOTIFICATION",
        @"sim"           : self.sim ?: @"",
    };
}

- (NSDictionary *)dictionaryRepresentation {
    NSMutableDictionary *dict = [@{
        @"id"            : self.recordID ?: @"",
        @"app_id"        : self.appID ?: @"",
        @"sender"        : self.sender ?: @"",
        @"message"       : self.message ?: @"",
        @"time"          : self.time ?: @"",
        @"tracking_code" : self.trackingCode ?: @"",
        @"signature"     : self.signature ?: @"",
        @"sim"           : self.sim ?: @"",
        @"type"          : self.type ?: @"NOTIFICATION",
        @"http_status"   : @(self.httpStatus),
        @"response_body" : self.responseBody ?: @"",
        @"created_at"    : @(self.createdAt),
    } mutableCopy];

    if (self.payloadJSON.length > 0) {
        dict[@"payload_json"] = self.payloadJSON;
    }
    if (self.rowID > 0) {
        dict[@"row_id"] = @(self.rowID);
    }
    return dict;
}

+ (instancetype)recordWithDictionary:(NSDictionary *)dict {
    if (![dict isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    ChargeRecord *record = [[ChargeRecord alloc] init];

    record.recordID     = [self stringValue:dict[@"id"]];
    record.appID        = [self stringValue:dict[@"app_id"]];
    record.sender       = [self stringValue:dict[@"sender"]];
    record.message      = [self stringValue:dict[@"message"]];
    record.time         = [self stringValue:dict[@"time"]];
    record.trackingCode = [self stringValue:dict[@"tracking_code"]];
    record.signature    = [self stringValue:dict[@"signature"]];
    record.sim          = [self stringValue:dict[@"sim"]];
    record.type         = [self stringValue:dict[@"type"]];
    record.responseBody = [self stringValue:dict[@"response_body"]];
    record.payloadJSON  = [self stringValue:dict[@"payload_json"]];
    record.createdAt    = [self doubleValue:dict[@"created_at"]];

    if (record.type.length == 0) {
        record.type = @"NOTIFICATION";
    }

    id status = dict[@"http_status"];
    record.httpStatus = [status respondsToSelector:@selector(integerValue)] ? [status integerValue] : 0;

    id rowID = dict[@"row_id"];
    if ([rowID respondsToSelector:@selector(integerValue)]) {
        record.rowID = [rowID integerValue];
    }
    return record;
}

+ (NSString *)stringValue:(id)value {
    if (value == nil || (id)value == [NSNull null]) {
        return @"";
    }
    return [value isKindOfClass:[NSString class]] ? value : [value description];
}

+ (double)doubleValue:(id)value {
    if ([value respondsToSelector:@selector(doubleValue)]) {
        return [value doubleValue];
    }
    return 0.0;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<ChargeRecord #%ld id=%@ sim=%@ status=%ld>",
            (long)self.rowID, self.recordID, self.sim, (long)self.httpStatus];
}

@end
