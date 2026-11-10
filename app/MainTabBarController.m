//
//  MainTabBarController.m
//

#import "MainTabBarController.h"
#import "HistoryViewController.h"
#import "SettingsViewController.h"

@implementation MainTabBarController

- (void)viewDidLoad {
    [super viewDidLoad];

    HistoryViewController *history =
        [[HistoryViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    UINavigationController *historyNav =
        [[UINavigationController alloc] initWithRootViewController:history];
    historyNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Lịch sử"
                                                          image:[UIImage systemImageNamed:@"clock.arrow.circlepath"]
                                                            tag:0];

    SettingsViewController *settings = [[SettingsViewController alloc] init];
    UINavigationController *settingsNav =
        [[UINavigationController alloc] initWithRootViewController:settings];
    settingsNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Cấu hình"
                                                          image:[UIImage systemImageNamed:@"gearshape"]
                                                            tag:1];

    self.viewControllers = @[historyNav, settingsNav];
    self.selectedIndex = 0;
}

@end
