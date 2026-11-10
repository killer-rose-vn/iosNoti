//
//  ConfigManager.m
//

#import "ConfigManager.h"
#import "IosNotiPaths.h"
#import "IosNotiLog.h"

NSString * const IosNotiConfigKeyServerURL = @"server_url";
NSString * const IosNotiConfigKeyAppID     = @"app_id";
NSString * const IosNotiConfigKeySimID     = @"sim_id";
NSString * const IosNotiConfigKeySecretKey = @"secret_key";

static NSString * const kDefaultServerURL = @"http://domain:10007/api/MM/PutChargeNotify";
static NSString * const kDefaultAppID     = @"bank_vietcombank";
static NSString * const kDefaultSimID     = @"bank_vietcombank|123";
static NSString * const kDefaultSecretKey = @"123456";

@interface ConfigManager ()
@property (nonatomic, strong) NSMutableDictionary *store;
@property (nonatomic, strong) NSDate *lastModifiedDate;
@end

@implementation ConfigManager

+ (instancetype)sharedManager {
    static ConfigManager *manager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [[ConfigManager alloc] init];
    });
    return manager;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _store = [[NSMutableDictionary alloc] init];
        [self resetToDefaults];
        [self reload];
    }
    return self;
}

#pragma mark - Defaults

- (NSDictionary *)defaultValues {
    return @{
        IosNotiConfigKeyServerURL : kDefaultServerURL,
        IosNotiConfigKeyAppID     : kDefaultAppID,
        IosNotiConfigKeySimID     : kDefaultSimID,
        IosNotiConfigKeySecretKey : kDefaultSecretKey,
    };
}

- (void)resetToDefaults {
    @synchronized (self) {
        [self.store setDictionary:[self defaultValues]];
    }
}

#pragma mark - Load / Save

- (void)reload {
    NSMutableDictionary *loaded = [[self defaultValues] mutableCopy];
    NSString *path = [IosNotiPaths configFilePath];

    NSData *data = [NSData dataWithContentsOfFile:path];
    if (data.length > 0) {
        NSError *error = nil;
        id plist = [NSPropertyListSerialization propertyListWithData:data
                                                             options:NSPropertyListMutableContainers
                                                              format:NULL
                                                               error:&error];
        if ([plist isKindOfClass:[NSDictionary class]]) {
            for (NSString *key in plist) {
                id value = plist[key];
                if ([value isKindOfClass:[NSString class]] && [(NSString *)value length] > 0) {
                    loaded[key] = value;
                }
            }
        } else {
            INLog(@"config plist invalid: %@", error.localizedDescription);
        }
    } else {
        INLog(@"config file not found, using defaults: %@", path);
    }

    @synchronized (self) {
        self.store = loaded;
    }
    self.lastModifiedDate = [self currentFileModificationDate];
}

- (NSDate *)currentFileModificationDate {
    NSDictionary *attrs = [[NSFileManager defaultManager]
                           attributesOfItemAtPath:[IosNotiPaths configFilePath]
                                            error:NULL];
    NSDate *date = attrs[NSFileModificationDate];
    return [date isKindOfClass:[NSDate class]] ? date : nil;
}

- (void)reloadIfChanged {
    NSDate *current = [self currentFileModificationDate];
    if (current == nil) {
        return;   // file chưa tồn tại → giữ mặc định
    }
    if (self.lastModifiedDate != nil && [current isEqualToDate:self.lastModifiedDate]) {
        return;   // chưa bị sửa
    }
    INLog(@"config file changed, reloading");
    [self reload];
}

- (BOOL)save {
    NSDictionary *snapshot = [self dictionaryRepresentation];
    NSString *path = [IosNotiPaths configFilePath];

    [IosNotiPaths ensureDirectoryAtPath:[IosNotiPaths sharedPreferencesDirectory]];

    NSError *error = nil;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:snapshot
                                                              format:NSPropertyListXMLFormat_v1_0
                                                             options:0
                                                               error:&error];
    if (!data) {
        INLog(@"serialize config failed: %@", error.localizedDescription);
        return NO;
    }

    BOOL ok = [data writeToFile:path atomically:YES];
    if (ok) {
        [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions: @0644}
                                         ofItemAtPath:path
                                                error:NULL];
        INLog(@"config saved to %@", path);
    } else {
        INLog(@"write config failed: %@", path);
    }
    return ok;
}

#pragma mark - Properties

- (NSString *)serverURL {
    @synchronized (self) { return self.store[IosNotiConfigKeyServerURL]; }
}
- (void)setServerURL:(NSString *)serverURL {
    [self setString:serverURL forKey:IosNotiConfigKeyServerURL];
}

- (NSString *)appID {
    @synchronized (self) { return self.store[IosNotiConfigKeyAppID]; }
}
- (void)setAppID:(NSString *)appID {
    [self setString:appID forKey:IosNotiConfigKeyAppID];
}

- (NSString *)simID {
    @synchronized (self) { return self.store[IosNotiConfigKeySimID]; }
}
- (void)setSimID:(NSString *)simID {
    [self setString:simID forKey:IosNotiConfigKeySimID];
}

- (NSString *)secretKey {
    @synchronized (self) { return self.store[IosNotiConfigKeySecretKey]; }
}
- (void)setSecretKey:(NSString *)secretKey {
    [self setString:secretKey forKey:IosNotiConfigKeySecretKey];
}

/// setValue:forKey: với nil sẽ XOÁ key → getter trả nil. Ép về @"" để an toàn.
- (void)setString:(NSString *)value forKey:(NSString *)key {
    NSString *safe = [value isKindOfClass:[NSString class]] ? value : @"";
    @synchronized (self) { self.store[key] = safe; }
}

- (NSDictionary *)dictionaryRepresentation {
    @synchronized (self) { return [self.store copy]; }
}

- (BOOL)isValidConfig {
    NSString *urlString = self.serverURL;
    if (urlString.length == 0) {
        return NO;
    }
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url || url.host.length == 0) {
        return NO;
    }
    NSString *scheme = url.scheme.lowercaseString;
    return [scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"];
}

@end
