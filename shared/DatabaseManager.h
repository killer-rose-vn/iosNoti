//
//  DatabaseManager.h
//  Lưu lịch sử thông báo bằng SQLite3.
//
//  File DB: <Preferences>/com.iosnoti.records.db
//    - rootless: /var/jb/var/mobile/Library/Preferences/com.iosnoti.records.db
//    - rootful : /var/mobile/Library/Preferences/com.iosnoti.records.db
//
//  Bảng charge_records:
//    row_id | id | app_id | sender | message | time | tracking_code
//           | signature | sim | http_status | response_body | created_at
//
//  An toàn đa luồng: mọi thao tác chạy tuần tự trên 1 serial queue.
//

#import <Foundation/Foundation.h>
#import "ChargeRecord.h"

/// http_status mặc định khi bản ghi chưa được gửi lên server.
static const NSInteger IosNotiHTTPStatusPending      = 0;
/// Lỗi mạng / không nhận được HTTP response (timeout, mất kết nối).
static const NSInteger IosNotiHTTPStatusNetworkError = -1;

@interface DatabaseManager : NSObject

+ (instancetype)sharedManager;

/// Mở DB + tạo schema. Tự gọi khi cần, gọi tay cũng được.
- (BOOL)openDatabase;
- (void)closeDatabase;

// ---- Ghi ----
- (BOOL)insertRecord:(ChargeRecord *)record;
- (BOOL)updateHTTPStatus:(NSInteger)status
            responseBody:(NSString *)responseBody
                forRowID:(NSInteger)rowID;
- (BOOL)updateHTTPStatus:(NSInteger)status
            responseBody:(NSString *)responseBody
        forTrackingCode:(NSString *)trackingCode;

// ---- Đọc ----
- (NSArray<ChargeRecord *> *)recordsWithLimit:(NSInteger)limit offset:(NSInteger)offset;  // mới nhất trước
- (NSArray<ChargeRecord *> *)recordsWithStatus:(NSInteger)status limit:(NSInteger)limit;
- (ChargeRecord *)recordWithRowID:(NSInteger)rowID;
- (ChargeRecord *)recordWithTrackingCode:(NSString *)trackingCode;
- (ChargeRecord *)recordWithRecordID:(NSString *)recordID;
- (NSInteger)recordCount;
- (NSInteger)countWithStatus:(NSInteger)status;

// ---- Dọn dẹp ----
- (BOOL)deleteRecordWithRowID:(NSInteger)rowID;
- (BOOL)deleteRecordsWithStatus:(NSInteger)status;
- (BOOL)deleteRecordsOlderThan:(NSTimeInterval)timestamp;
- (BOOL)deleteAllRecords;
/// Giữ lại tối đa `maxRecords` bản ghi mới nhất.
- (BOOL)trimToMaxRecords:(NSInteger)maxRecords;

// ---- Tiện ích ----
- (NSArray<NSDictionary *> *)dictionariesWithLimit:(NSInteger)limit offset:(NSInteger)offset;
- (NSString *)databasePath;

@end
