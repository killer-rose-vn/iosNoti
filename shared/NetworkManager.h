//
//  NetworkManager.h
//  HTTP client dùng chung: POST JSON lên server_url.
//
//  - Chạy được trong tiến trình SpringBoard (tweak) lẫn app UIKit.
//  - Callback luôn được gọi trên main queue.
//  - `body` là response thô (đã UTF-8 decode, tối đa kMaxBodyLength ký tự).
//

#import <Foundation/Foundation.h>

/// Kết quả 1 lần gửi.
@interface NetworkResult : NSObject
@property (nonatomic, assign) NSInteger statusCode;      // 0 nếu không có HTTP response
@property (nonatomic, copy)   NSString *body;            // response body (có thể rỗng)
@property (nonatomic, copy)   NSString *errorMessage;    // nil nếu không lỗi
@property (nonatomic, assign) NSTimeInterval duration;   // giây
@property (nonatomic, readonly) BOOL success;            // status 200..299
@end

typedef void (^NetworkCompletion)(NetworkResult *result);

@interface NetworkManager : NSObject

+ (instancetype)sharedManager;

/// Timeout mặc định 15s.
@property (nonatomic, assign) NSTimeInterval timeoutInterval;

/// POST JSON bất đồng bộ. completion được gọi đúng 1 lần trên main queue.
- (void)POSTJSON:(NSDictionary *)json
           toURL:(NSString *)urlString
      completion:(NetworkCompletion)completion;

/// Phiên bản đồng bộ (block thread hiện tại). Dùng trong queue nền.
- (NetworkResult *)POSTJSONSynchronously:(NSDictionary *)json toURL:(NSString *)urlString;

@end
