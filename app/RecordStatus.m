//
//  RecordStatus.m
//

#import "RecordStatus.h"
#import "DatabaseManager.h"

NSString *IosNotiStatusText(NSInteger httpStatus) {
    if (httpStatus == IosNotiHTTPStatusPending) {
        return @"Chờ gửi";
    }
    if (httpStatus == IosNotiHTTPStatusNetworkError) {
        return @"Lỗi mạng";
    }
    if (httpStatus >= 200 && httpStatus < 300) {
        return [NSString stringWithFormat:@"Thành công (%ld)", (long)httpStatus];
    }
    return [NSString stringWithFormat:@"Thất bại (%ld)", (long)httpStatus];
}

UIColor *IosNotiStatusColor(NSInteger httpStatus) {
    if (httpStatus == IosNotiHTTPStatusPending) {
        return [UIColor systemOrangeColor];
    }
    if (httpStatus == IosNotiHTTPStatusNetworkError) {
        return [UIColor systemRedColor];
    }
    if (httpStatus >= 200 && httpStatus < 300) {
        return [UIColor systemGreenColor];
    }
    return [UIColor systemRedColor];
}

NSString *IosNotiDisplayTime(NSString *timeMillis, NSTimeInterval createdAt) {
    static NSDateFormatter *formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"dd/MM HH:mm:ss";
    });

    NSTimeInterval seconds = createdAt;
    if ([timeMillis respondsToSelector:@selector(longLongValue)] && timeMillis.length > 0) {
        double value = timeMillis.doubleValue;
        if (value > 100000000000.0) {
            value /= 1000.0;   // ms → s
        }
        if (value > 0) {
            seconds = value;
        }
    }
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:seconds];
    return [formatter stringFromDate:date];
}
