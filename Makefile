##############################################################################
#  IosNoti — aggregate Theos project (SpringBoard tweak + companion app)
#
#  Mặc định trong project này:
#    - Jailbreak    : ROOTLESS (Dopamine / palera1n rootless), iOS 15/16
#    - Deployment   : iOS 15.0
#    - Kiến trúc    : arm64 + arm64e
#
#  Nếu máy bạn là iOS 14 ROOTFUL: đổi dòng THEOS_PACKAGE_SCHEME bên dưới
#  thành "rootful" (hoặc comment lại) và đổi deployment target xuống 14.0.
#
#  Build:
#    export THEOS=/opt/theos
#    make clean package
#    make install THEOS_DEVICE_IP=<IP_iPhone> THEOS_DEVICE_PORT=22
##############################################################################

export THEOS_PACKAGE_SCHEME = rootless
export TARGET               = iphone:clang:latest:15.0
export ARCHS                = arm64 arm64e

include $(THEOS)/makefiles/common.mk

SUBPROJECTS += tweak
SUBPROJECTS += app

include $(THEOS_MAKE_PATH)/aggregate.mk

after-install::
	install.exec "killall -9 SpringBoard || true"
