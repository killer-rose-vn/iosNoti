//
//  IosNotiLog.h
//  Macro log dùng chung cho Tweak và App.
//  Xem log trên máy: idevicesyslog | grep IosNoti   (hoặc Console.app)
//

#ifndef IosNotiLog_h
#define IosNotiLog_h

#import <Foundation/Foundation.h>

#define INLog(fmt, ...) NSLog((@"[IosNoti] " fmt), ##__VA_ARGS__)

#endif /* IosNotiLog_h */
