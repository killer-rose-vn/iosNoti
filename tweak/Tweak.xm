//
//  Tweak.xm
//  Bước 2: bắt TOÀN BỘ thông báo trong SpringBoard qua BBServer
//          → đóng gói JSON → POST lên server_url → lưu DB.
//
//  Hook chính:
//      BBServer -publishBulletin:destinations:
//  Đây là điểm bulletin-system giao cho SpringBoard hiển thị notification
//  (push từ app, tin nhắn, cảnh báo hệ thống...).
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <substrate.h>

#import "ConfigManager.h"
#import "SignatureHelper.h"
#import "DatabaseManager.h"
#import "ChargeRecord.h"
#import "NotificationDispatcher.h"
#import "IosNotiDarwin.h"
#import "IosNotiPaths.h"
#import "IosNotiLog.h"

#pragma mark - Bootstrap

static void IosNotiScheduleResend(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // Chờ SpringBoard lên hẳn rồi mới gửi lại: lúc %ctor, network stack
        // chưa sẵn sàng và watchdog của SpringBoard rất nhạy.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10.0 * NSEC_PER_SEC)),
                       dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            INLog(@"resend pending records (delayed)");
            [[NotificationDispatcher sharedDispatcher] resendPendingRecords];
        });
    });
}

static void IosNotiBootstrap(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        ConfigManager *config = [ConfigManager sharedManager];
        [config reload];

        INLog(@"loaded. server=%@ app_id=%@ sim=%@ secret_len=%lu",
              config.serverURL, config.appID, config.simID,
              (unsigned long)config.secretKey.length);

        if (![config isValidConfig]) {
            INLog(@"WARNING: server_url không hợp lệ: %@", config.serverURL);
        }

        [[DatabaseManager sharedManager] openDatabase];

        // In 1 chữ ký mẫu để đối chiếu công thức với server C#.
        NSString *sampleTime = [SignatureHelper currentTimestampMillisecondsString];
        NSString *plain = [SignatureHelper plainTextWithAppID:@"com.mo2pay.test"
                                                           id:sampleTime
                                                         time:sampleTime
                                                          sim:config.simID
                                                    secretKey:config.secretKey];
        INLog(@"signature sample plain=%@", plain);
        INLog(@"signature sample md5=%@", [SignatureHelper md5Lowercase:plain]);
    });

    IosNotiScheduleResend();

    // App bấm "Lưu cấu hình" → đọc lại config ngay, không cần respring.
    IosNotiObserveConfigChanged(^{
        ConfigManager *config = [ConfigManager sharedManager];
        [config reload];
        INLog(@"config reloaded via darwin notification: server=%@ sim=%@",
              config.serverURL, config.simID);
    });
}

#pragma mark - Hook handler

static void IosNotiHandleBulletin(id bulletin) {
    if (bulletin == nil) {
        return;
    }
    @autoreleasepool {
        @try {
            [[NotificationDispatcher sharedDispatcher] handleBulletin:bulletin];
        } @catch (NSException *exception) {
            INLog(@"handleBulletin exception: %@ %@", exception.name, exception.reason);
        }
    }
}

#pragma mark - Hook chính (Logos)

%hook BBServer

- (void)publishBulletin:(id)bulletin destinations:(unsigned long long)destinations {
    %orig;
    IosNotiHandleBulletin(bulletin);
}

%end

#pragma mark - Hook phụ: các biến thể publishBulletin của iOS khác nhau.
//  Chỉ hook khi method tồn tại + đúng số tham số, tránh crash trên iOS không có.

typedef void (*IosNotiPublish3IMP)(id, SEL, id, unsigned long long, id);
static IosNotiPublish3IMP IosNotiOrigPublish3 = NULL;

static void IosNotiPublishHook3(id self, SEL _cmd, id bulletin,
                                unsigned long long destinations, id context) {
    if (IosNotiOrigPublish3) {
        IosNotiOrigPublish3(self, _cmd, bulletin, destinations, context);
    }
    IosNotiHandleBulletin(bulletin);
}

static void IosNotiInstallOptionalHooks(void) {
    Class cls = objc_getClass("BBServer");
    if (cls == Nil) {
        return;
    }

    SEL sel = @selector(publishBulletin:destinations:featurizationContext:);
    Method method = class_getInstanceMethod(cls, sel);
    // self + _cmd + 3 tham số = 5
    if (method && method_getNumberOfArguments(method) == 5 && IosNotiOrigPublish3 == NULL) {
        MSHookMessageEx(cls, sel, (IMP)IosNotiPublishHook3, (IMP *)&IosNotiOrigPublish3);
        INLog(@"hooked optional publishBulletin:destinations:featurizationContext:");
    }
}

#pragma mark - SpringBoard lifecycle

%hook SpringBoard

- (void)applicationDidFinishLaunching:(id)application {
    %orig;
    IosNotiBootstrap();
}

%end

#pragma mark - Constructor

%ctor {
    @autoreleasepool {
        IosNotiBootstrap();
        IosNotiInstallOptionalHooks();
    }
}
