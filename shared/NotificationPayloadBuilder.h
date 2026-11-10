//
//  NotificationPayloadBuilder.h
//  Dựng payload JSON chuẩn cho 1 thông báo bắt được.
//
//  Cấu trúc gửi lên server (Content-Type: application/json):
//  {
//    "app_id":       "com.mo2pay.test",
//    "sender":       "[TEST] Thông báo thử nghiệm",
//    "time":         "1793884666515",
//    "id":           "1793884666515",
//    "tracking_code":"bank_vietcombank|123",
//    "message":      "Kiểm tra kết nối ...",
//    "signature":    "cee29fbfdcc54853ff50c67fdb7e2ce9",
//    "type":         "NOTIFICATION",
//    "sim":          "bank_vietcombank|123"
//  }
//
//  signature = MD5_lowercase( app_id|id|time|sim|secret_key )
//

#import <Foundation/Foundation.h>

extern NSString * const IosNotiPayloadTypeNotification;   // "NOTIFICATION"

@interface NotificationPayloadBuilder : NSObject

/// Dựng payload từ dữ liệu thô của BBBulletin + config hiện tại.
/// @param appID    sectionID của app phát thông báo
/// @param sender   title (fallback subtitle)
/// @param message  nội dung message
/// @param recordID mã định danh (bulletinID); nil → dùng chính chuỗi time
/// @param timeMS   unix milliseconds dạng chuỗi
+ (NSDictionary *)payloadWithAppID:(NSString *)appID
                            sender:(NSString *)sender
                           message:(NSString *)message
                          recordID:(NSString *)recordID
                            timeMS:(NSString *)timeMS;

/// Map payload → ChargeRecord để lưu DB.
/// apiStatus = -1 nghĩa là chưa gửi (pending); payload_json được giữ nguyên để app hiển thị.
+ (id)recordFromPayload:(NSDictionary *)payload
             responseBody:(NSString *)responseBody
               httpStatus:(NSInteger)httpStatus
                createdAt:(NSTimeInterval)createdAt;

@end
