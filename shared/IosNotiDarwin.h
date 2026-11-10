//
//  IosNotiDarwin.h
//  Darwin notification nội bộ: App báo Tweak đọc lại config ngay, không cần respring.
//
//  App  : IosNotiPostConfigChanged()
//  Tweak: IosNotiObserveConfigChanged(^{ ... })
//

#import <Foundation/Foundation.h>

/// Tên notification: "com.iosnoti.config.changed"
extern NSString * const IosNotiConfigChangedNotification;

/// Bắn Darwin notification (gọi được từ App lẫn Tweak).
void IosNotiPostConfigChanged(void);

/// Đăng ký 1 lần; handler được gọi trên main queue.
void IosNotiObserveConfigChanged(void (^handler)(void));
