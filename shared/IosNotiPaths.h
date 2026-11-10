//
//  IosNotiPaths.h
//  Quản lý đường dẫn dùng chung, tự nhận biết rootless (/var/jb) hay rootful.
//
//  Rootless (iOS 15+):  /var/jb/var/mobile/Library/Preferences/
//  Rootful  (iOS 14) :  /var/mobile/Library/Preferences/
//

#import <Foundation/Foundation.h>

@interface IosNotiPaths : NSObject

/// @"/var/jb" nếu máy rootless, @"" nếu rootful. (Dùng khi build path thủ công.)
+ (NSString *)jbRootPrefix;
+ (BOOL)isRootless;

/// Thư mục Preferences dùng chung giữa Tweak (SpringBoard) và App.
+ (NSString *)sharedPreferencesDirectory;

/// .../Preferences/com.iosnoti.config.plist
+ (NSString *)configFilePath;

/// .../Preferences/com.iosnoti.records.db
+ (NSString *)databaseFilePath;

/// Tạo thư mục nếu chưa có. Trả về NO nếu không tạo được / không ghi được.
+ (BOOL)ensureDirectoryAtPath:(NSString *)path;

/// Thư mục Preferences dùng chung có ghi được không.
/// App bị sandbox: nếu chưa có entitlement, hàm này trả NO → App chỉ đọc được.
+ (BOOL)isSharedDirectoryWritable;

@end
