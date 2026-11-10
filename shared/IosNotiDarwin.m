//
//  IosNotiDarwin.m
//

#import "IosNotiDarwin.h"
#import "IosNotiLog.h"
#import <CoreFoundation/CoreFoundation.h>

NSString * const IosNotiConfigChangedNotification = @"com.iosnoti.config.changed";

static void (^IosNotiConfigChangedHandler)(void) = nil;
static BOOL IosNotiDarwinObserverInstalled = NO;

static void IosNotiDarwinCallback(CFNotificationCenterRef center,
                                  void *observer,
                                  CFStringRef name,
                                  const void *object,
                                  CFDictionaryRef userInfo) {
    (void)center; (void)observer; (void)object; (void)userInfo;
    INLog(@"darwin notification received: %@", (__bridge NSString *)name);
    void (^handler)(void) = IosNotiConfigChangedHandler;
    if (handler) {
        dispatch_async(dispatch_get_main_queue(), ^{ handler(); });
    }
}

void IosNotiPostConfigChanged(void) {
    CFNotificationCenterRef center = CFNotificationCenterGetDarwinNotifyCenter();
    CFNotificationCenterPostNotification(center,
                                         (__bridge CFStringRef)IosNotiConfigChangedNotification,
                                         NULL,
                                         NULL,
                                         true);
    INLog(@"posted darwin notification %@", IosNotiConfigChangedNotification);
}

void IosNotiObserveConfigChanged(void (^handler)(void)) {
    IosNotiConfigChangedHandler = [handler copy];
    if (IosNotiDarwinObserverInstalled) {
        return;
    }
    IosNotiDarwinObserverInstalled = YES;
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                    NULL,
                                    IosNotiDarwinCallback,
                                    (__bridge CFStringRef)IosNotiConfigChangedNotification,
                                    NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
}
