##############################################################################
#  tweak/Makefile — SpringBoard tweak
##############################################################################

TWEAK_NAME = IosNotiTweak

IosNotiTweak_FILES = Tweak.xm \
                     ../shared/ConfigManager.m \
                     ../shared/SignatureHelper.m \
                     ../shared/DatabaseManager.m \
                     ../shared/ChargeRecord.m \
                     ../shared/IosNotiPaths.m \
                     ../shared/IosNotiDarwin.m \
                     ../shared/NetworkManager.m \
                     ../shared/NotificationPayloadBuilder.m \
                     ../shared/NotificationDispatcher.m

# CoreFoundation cần cho CFNotificationCenter (Darwin notification).
IosNotiTweak_FRAMEWORKS = Foundation UIKit CoreFoundation
IosNotiTweak_LIBRARIES  = sqlite3
IosNotiTweak_CFLAGS     = -fobjc-arc -I../shared -I$(THEOS_PROJECT_DIR)/shared \
                          -Wno-deprecated-declarations
IosNotiTweak_LDFLAGS    = -undefined dynamic_lookup

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 SpringBoard"
