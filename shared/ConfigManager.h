//
//  ConfigManager.h
//  Cấu hình dùng chung giữa Tweak (SpringBoard) và App.
//
//  Lưu ở: <Preferences>/com.iosnoti.config.plist
//    - rootless: /var/jb/var/mobile/Library/Preferences/com.iosnoti.config.plist
//    - rootful : /var/mobile/Library/Preferences/com.iosnoti.config.plist
//
//  Dùng plist (không phải NSUserDefaults suite) để SpringBoard và App
//  cùng đọc được chắc chắn, kể cả khi app chưa từng chạy.
//

#import <Foundation/Foundation.h>

extern NSString * const IosNotiConfigKeyServerURL;
extern NSString * const IosNotiConfigKeyAppID;
extern NSString * const IosNotiConfigKeySimID;
extern NSString * const IosNotiConfigKeySecretKey;

@interface ConfigManager : NSObject

+ (instancetype)sharedManager;

/// Đọc lại toàn bộ config từ file plist (merge default cho key thiếu).
- (void)reload;

/// Chỉ đọc lại nếu file plist đã bị sửa (so modification date).
/// Dùng trước mỗi lần gửi để App sửa config là Tweak thấy ngay, không cần respring.
- (void)reloadIfChanged;

/// Ghi ra file plist (atomic, chmod 0644).
- (BOOL)save;

// ---- 3 trường bắt buộc ----
@property (nonatomic, copy) NSString *serverURL;   // mặc định: http://domain:10007/api/MM/PutChargeNotify
@property (nonatomic, copy) NSString *simID;       // mặc định: bank_vietcombank|123
@property (nonatomic, copy) NSString *secretKey;   // mặc định: 123456

/// app_id dùng khi tạo chữ ký (server C# cũng phải có cùng giá trị).
/// Mặc định: "bank_vietcombank"
@property (nonatomic, copy) NSString *appID;

/// Toàn bộ config dưới dạng dictionary (tiện cho debug / gửi lên server).
- (NSDictionary *)dictionaryRepresentation;

// ---- Tiện ích ----
- (void)resetToDefaults;
- (NSDictionary *)defaultValues;
- (BOOL)isValidConfig;   // serverURL hợp lệ (http/https + host)

@end
