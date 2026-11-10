//
//  NotificationDispatcher.h
//  Luồng xử lý 1 thông báo: trích xuất → đóng gói → POST → lưu DB.
//  Dùng chung cho Tweak (SpringBoard) và App (test / gửi lại).
//

#import <Foundation/Foundation.h>
#import "ChargeRecord.h"

/// Kết quả 1 lần gửi (được gọi trên main queue).
/// httpStatus: HTTP code thực, -1 = lỗi mạng, 0 = không gửi được.
typedef void (^IosNotiSendCompletion)(NSInteger httpStatus,
                                      NSString *responseBody,
                                      NSInteger rowID,
                                      BOOL success);

@interface NotificationDispatcher : NSObject

+ (instancetype)sharedDispatcher;

// ---- Tweak ----

/// Nhận bulletin thô (BBBulletin) từ hook BBServer, tự trích xuất field.
- (void)handleBulletin:(id)bulletin;

/// Nhận dữ liệu đã trích xuất (dùng cho test hoặc hook khác).
- (void)handleSectionID:(NSString *)sectionID
              bulletinID:(NSString *)bulletinID
                   title:(NSString *)title
                subtitle:(NSString *)subtitle
                 message:(NSString *)message;

/// Gửi lại các bản ghi đang pending (http_status = 0).
- (void)resendPendingRecords;

// ---- App ----

/// Gửi 1 payload bất kỳ: tạo bản ghi pending → POST → cập nhật kết quả.
- (void)submitPayload:(NSDictionary *)payload completion:(IosNotiSendCompletion)completion;

/// Gửi lại đúng gói tin của 1 bản ghi đã lưu (nút "Gửi lại").
- (void)repostRecord:(ChargeRecord *)record completion:(IosNotiSendCompletion)completion;

// ---- Tuỳ chọn ----

/// Số bản ghi tối đa giữ trong DB (mặc định 2000).
@property (nonatomic, assign) NSInteger maxRecords;

/// Số lần thử lại khi lỗi mạng (mặc định 2).
@property (nonatomic, assign) NSInteger maxRetries;

@end
