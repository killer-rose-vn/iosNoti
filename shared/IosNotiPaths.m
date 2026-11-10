//
//  IosNotiPaths.m
//

#import "IosNotiPaths.h"
#import "IosNotiLog.h"

static NSString * const kJBRoot            = @"/var/jb";
static NSString * const kRootlessPrefsDir  = @"/var/jb/var/mobile/Library/Preferences";
static NSString * const kRootfulPrefsDir   = @"/var/mobile/Library/Preferences";
static NSString * const kConfigFileName    = @"com.iosnoti.config.plist";
static NSString * const kDatabaseFileName  = @"com.iosnoti.records.db";

@implementation IosNotiPaths

+ (BOOL)isRootless {
    static BOOL rootless = NO;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        rootless = [[NSFileManager defaultManager] fileExistsAtPath:kJBRoot];
    });
    return rootless;
}

+ (NSString *)jbRootPrefix {
    return [self isRootless] ? kJBRoot : @"";
}

+ (NSString *)sharedPreferencesDirectory {
    static NSString *dir = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSFileManager *fm = [NSFileManager defaultManager];

        // Ưu tiên đường dẫn rootless nếu thực sự tồn tại (trên rootless,
        // /var/jb/var/mobile trỏ về /var/mobile thật của hệ thống).
        if ([fm fileExistsAtPath:kRootlessPrefsDir]) {
            dir = kRootlessPrefsDir;
        } else if ([fm fileExistsAtPath:kRootfulPrefsDir]) {
            dir = kRootfulPrefsDir;
        } else {
            // Chưa có thư mục: chọn theo loại jailbreak rồi tự tạo sau.
            dir = [self isRootless] ? kRootlessPrefsDir : kRootfulPrefsDir;
        }
        INLog(@"shared preferences dir = %@ (rootless=%d)", dir, [self isRootless]);
    });
    return dir;
}

+ (NSString *)configFilePath {
    return [[self sharedPreferencesDirectory] stringByAppendingPathComponent:kConfigFileName];
}

+ (NSString *)databaseFilePath {
    return [[self sharedPreferencesDirectory] stringByAppendingPathComponent:kDatabaseFileName];
}

+ (BOOL)ensureDirectoryAtPath:(NSString *)path {
    if (path.length == 0) {
        return NO;
    }
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir = NO;
    if ([fm fileExistsAtPath:path isDirectory:&isDir]) {
        return isDir;
    }
    NSError *error = nil;
    BOOL ok = [fm createDirectoryAtPath:path
            withIntermediateDirectories:YES
                             attributes:@{NSFilePosixPermissions: @0755}
                                  error:&error];
    if (!ok) {
        INLog(@"createDirectory failed: %@ (%@)", path, error.localizedDescription);
    }
    return ok;
}

+ (BOOL)isSharedDirectoryWritable {
    NSString *dir = [self sharedPreferencesDirectory];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:dir]) {
        return [self ensureDirectoryAtPath:dir];
    }

    // Thử ghi thật một file tạm — isWritableFileAtPath không đáng tin trên iOS.
    NSString *probe = [dir stringByAppendingPathComponent:@".iosnoti_write_probe"];
    NSData *data = [@"ok" dataUsingEncoding:NSUTF8StringEncoding];
    BOOL ok = [data writeToFile:probe atomically:YES];
    if (ok) {
        [fm removeItemAtPath:probe error:NULL];
    }
    return ok;
}

@end
