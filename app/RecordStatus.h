//
//  RecordStatus.h
//  Hiển thị trạng thái gửi dùng chung cho History / Detail.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

/// "Thành công" / "Thất bại (500)" / "Lỗi mạng" / "Chờ gửi"
NSString *IosNotiStatusText(NSInteger httpStatus);

/// Màu tương ứng.
UIColor *IosNotiStatusColor(NSInteger httpStatus);

/// "dd/MM HH:mm:ss" từ chargeRecord.time (ms) — fallback createdDate.
NSString *IosNotiDisplayTime(NSString *timeMillis, NSTimeInterval createdAt);
