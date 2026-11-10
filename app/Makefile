##############################################################################
#  app/Makefile — ứng dụng UIKit (Objective-C) đi kèm
##############################################################################

APPLICATION_NAME = IosNoti

IosNoti_FILES = main.m \
                AppDelegate.m \
                MainTabBarController.m \
                HistoryViewController.m \
                SettingsViewController.m \
                DetailViewController.m \
                RecordStatus.m \
                ../shared/ConfigManager.m \
                ../shared/SignatureHelper.m \
                ../shared/DatabaseManager.m \
                ../shared/ChargeRecord.m \
                ../shared/IosNotiPaths.m \
                ../shared/IosNotiDarwin.m \
                ../shared/NetworkManager.m \
                ../shared/NotificationPayloadBuilder.m \
                ../shared/NotificationDispatcher.m

# CoreFoundation cần cho CFNotificationCenterGetDarwinNotifyCenter (Darwin notification).
IosNoti_FRAMEWORKS = Foundation UIKit CoreFoundation
IosNoti_LIBRARIES  = sqlite3

IosNoti_CFLAGS     = -fobjc-arc -I../shared -I$(THEOS_PROJECT_DIR)/shared \
                     -Wno-deprecated-declarations

IosNoti_INSTALL_PATH = /Applications

# Cần entitlement để app ghi được vào thư mục Preferences dùng chung với tweak.
IosNoti_CODESIGN_FLAGS = -S$(THEOS_PROJECT_DIR)/app/entitlements.plist

include $(THEOS_MAKE_PATH)/application.mk

after-install::
	install.exec "uicache -a || uicache -p /var/jb/Applications/IosNoti.app || true"
