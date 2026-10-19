# 抖音福袋助手 —— relaxin(无根)越狱构建
#
# 无根方案构建:
#   make clean package THEOS_PACKAGE_SCHEME=rootless
# 传统有根方案构建:
#   make clean package
#
# 目标进程:抖音 40.7.0 (com.ss.iphone.ugc.Aweme), 主二进制 AwemeCore.framework

TARGET = iphone:clang:latest:15.0
ARCHS = arm64 arm64e

INSTALL_TARGET_PROCESSES = Aweme

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = FudaiHelper

FudaiHelper_FILES = src/Tweak.x \
                    src/FudaiConfig.m \
                    src/FudaiScan.m \
                    src/FudaiProbe.m \
                    src/FudaiEngine.m \
                    src/FudaiUI.m \
                    src/FudaiPanel.m

FUDAI_VERSION := $(shell grep '^Version:' control | awk '{print $$2}')
FUDAI_BUILD_TIME := $(shell TZ=Asia/Shanghai date '+%Y-%m-%d %H:%M')

FudaiHelper_CFLAGS = -fobjc-arc -Isrc -Wno-deprecated-declarations \
    -DFUDAI_VERSION='"$(FUDAI_VERSION)"' \
    -DFUDAI_BUILD_TIME='"$(FUDAI_BUILD_TIME)"'

FudaiHelper_FRAMEWORKS = UIKit Foundation QuartzCore

include $(THEOS_MAKE_PATH)/tweak.mk
