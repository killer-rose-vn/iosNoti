//
//  SignatureHelper.h
//  Tạo chữ ký cho request gửi lên server C#.
//
//  ======================= CÔNG THỨC =======================
//     plain = app_id + "|" + id + "|" + time + "|" + sim + "|" + secret_key
//     signature = MD5(plain)  -> hex CHỮ THƯỜNG (32 ký tự)
//
//  - id        : mã giao dịch / tracking code (chuỗi, KHÔNG format lại)
//  - time      : Unix timestamp dạng chuỗi giây (vd "1731000000")
//  - sim       : giá trị sim_id ("bank_vietcombank|123")
//  - secret_key: khóa bí mật dùng chung
//
//  Rỗng/nil được coi là chuỗi "" (không bỏ qua field nào), ví dụ:
//    "bank_vietcombank||1731000000|bank_vietcombank|123|123456"
//
//  Chuỗi plain PHẢI là UTF-8 khi hash.
//  Bên C# tương đương:
//    var plain = $"{app_id}|{id}|{time}|{sim}|{secret_key}";
//    var sig = MD5.HashData(Encoding.UTF8.GetBytes(plain))
//               -> Convert.ToHexString(sig).ToLowerInvariant();
//  =========================================================
//

#import <Foundation/Foundation.h>

@interface SignatureHelper : NSObject

/// Chuỗi gốc trước khi hash (dùng để debug / log / so khớp với server C#).
+ (NSString *)plainTextWithAppID:(NSString *)appID
                              id:(NSString *)recordID
                            time:(NSString *)time
                             sim:(NSString *)sim
                       secretKey:(NSString *)secretKey;

/// MD5 -> hex chữ thường. Trả nil nếu input nil.
+ (NSString *)md5Lowercase:(NSString *)input;

/// SHA256 -> hex chữ thường (phương án thay thế nếu server đổi).
+ (NSString *)sha256Lowercase:(NSString *)input;

/// Mặc định dùng MD5. useSHA256 = YES để dùng SHA256.
+ (NSString *)signatureWithAppID:(NSString *)appID
                              id:(NSString *)recordID
                            time:(NSString *)time
                             sim:(NSString *)sim
                       secretKey:(NSString *)secretKey
                       useSHA256:(BOOL)useSHA256;

/// Tiện dụng: time = now (Unix seconds), MD5.
+ (NSString *)signatureNowWithAppID:(NSString *)appID
                                 id:(NSString *)recordID
                                sim:(NSString *)sim
                          secretKey:(NSString *)secretKey;

/// Unix timestamp (giây) dạng chuỗi.
+ (NSString *)currentTimestampString;

/// Unix timestamp (MILI giây) dạng chuỗi, vd "1793884666515".
/// Trường `time` gửi lên server dùng đơn vị này.
+ (NSString *)currentTimestampMillisecondsString;

@end
