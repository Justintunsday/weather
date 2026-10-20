TARGET := iphone:clang:17.5:15.0
ARCHS := arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = WeatherSource
WeatherSource_FILES = Tweak.xm $(wildcard src/*.m) $(wildcard src/*.mm)
WeatherSource_CFLAGS = -fobjc-arc -Wno-nullability-completeness -Wno-error=unguarded-availability-new -I$(THEOS_PROJECT_DIR)/src -DWS_VERSION=\"0.1.0\"
WeatherSource_CCFLAGS = -fobjc-arc -Wno-nullability-completeness -Wno-error=unguarded-availability-new -std=c++17 -I$(THEOS_PROJECT_DIR)/src
WeatherSource_FRAMEWORKS = Foundation UIKit CoreLocation
WeatherSource_INSTALL_PATH = /Library/MobileSubstrate/DynamicLibraries

BUNDLE_NAME = WeatherSourcePrefs
WeatherSourcePrefs_FILES = prefs/WSRootListController.m prefs/WSLogController.m src/WSSettings.m
WeatherSourcePrefs_INSTALL_PATH = /Library/PreferenceBundles
WeatherSourcePrefs_FRAMEWORKS = UIKit Foundation
WeatherSourcePrefs_RESOURCE_DIRS = prefs/Resources
WeatherSourcePrefs_CFLAGS = -fobjc-arc -Wno-nullability-completeness -Wno-error=unguarded-availability-new -I$(THEOS_PROJECT_DIR)/src -DWS_VERSION=\"0.1.0\"
WeatherSourcePrefs_LDFLAGS = -Wl,-undefined,dynamic_lookup

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/bundle.mk

after-install::
	install.exec "killall -9 Weather 2>/dev/null || true; killall -9 WeatherWidget 2>/dev/null || true"






