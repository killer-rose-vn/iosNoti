//
//  AppDelegate.m
//

#import "AppDelegate.h"
#import "MainTabBarController.h"
#import "ConfigManager.h"
#import "DatabaseManager.h"
#import "IosNotiPaths.h"
#import "IosNotiLog.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application
didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // Đảm bảo config mặc định tồn tại ngay lần chạy đầu (tweak cũng đọc file này).
    ConfigManager *config = [ConfigManager sharedManager];
    [config reload];
    if (![[NSFileManager defaultManager] fileExistsAtPath:[IosNotiPaths configFilePath]]) {
        [config save];
    }
    [[DatabaseManager sharedManager] openDatabase];

    INLog(@"app launched, prefs=%@", [IosNotiPaths sharedPreferencesDirectory]);

    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.window.rootViewController = [[MainTabBarController alloc] init];
    [self.window makeKeyAndVisible];
    return YES;
}

@end
