//
//  ChargeRecord.h
//  Model cho 1 bản ghi thông báo đã bắt được.
//

#import <Foundation/Foundation.h>

@interface ChargeRecord : NSObject

@property (nonatomic, assign) NSInteger rowID;         // khóa tự tăng trong SQLite
@property (nonatomic, copy)   NSString *recordID;      // cột "id" (bulletinID hoặc timestamp)
@property (nonatomic, copy)   NSString *appID;
@property (nonatomic, copy)   NSString *sender;
@property (nonatomic, copy)   NSString *message;
@property (nonatomic, copy)   NSString *time;          // Unix milliseconds dạng chuỗi
@property (nonatomic, copy)   NSString *trackingCode;
@property (nonatomic, copy)   NSString *signature;
@property (nonatomic, copy)   NSString *sim;
@property (nonatomic, copy)   NSString *type;          // "NOTIFICATION"
@property (nonatomic, assign) NSInteger httpStatus;    // xem IosNotiHTTPStatus*
@property (nonatomic, copy)   NSString *responseBody;
@property (nonatomic, copy)   NSString *payloadJSON;   // JSON đã gửi (để app hiển thị/copy)
@property (nonatomic, assign) double createdAt;        // Unix seconds (double)

@property (nonatomic, readonly) NSDate *createdDate;

- (NSDictionary *)dictionaryRepresentation;

/// Payload gửi server dựng lại từ record (dùng cho retry/debug).
- (NSDictionary *)payloadDictionary;

/// Tạo từ row của SQLite hoặc từ dictionary JSON.
+ (instancetype)recordWithDictionary:(NSDictionary *)dict;

@end
