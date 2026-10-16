# ============================================================================
#  MT Agent 复刻版构建（macOS + Xcode 命令行工具，无需 Xcode 工程文件）
#  产物布局与原包一致：Payload/CodexApp.app/{CodexApp,Helpers/*,PlugIns/...}
#
#  用法：  make -C build            # 编译 app + 扩展 + ca-filetool 并装配 bundle
#          make -C build sign       # 用 entitlements 签名（ldid，缺失则 codesign adhoc）
#          make -C build package    # 生成 build/MT-Agent-replica.tipa
#          make -C build clean
#
#  注意：本文件可能被 make -C build / make（在 build 内）两种方式调用，
#        因此所有路径一律基于 $(ROOT)（仓库根），不依赖当前工作目录。
# ============================================================================

ROOT           := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/..)

SDK            ?= $(shell xcrun --sdk iphoneos --show-sdk-path)
MIN_IOS        ?= 15.0
ARCH           ?= arm64
CLANG          ?= xcrun --sdk iphoneos clang

BUILD          := $(ROOT)/build/out
BUNDLE         := $(BUILD)/Payload/CodexApp.app
SRC            := $(ROOT)/MTAgent/Sources
EXT_SRC        := $(ROOT)/MTShareExtension/Sources
ASSETS         := $(ROOT)/OriginalAssets/Payload/CodexApp.app
MANIFEST       := $(ROOT)/build/bundle_manifest.json

COMMON_FLAGS := -arch $(ARCH) -isysroot $(SDK) -miphoneos-version-min=$(MIN_IOS) \
                -fobjc-arc -fmodules -O2 -Wall -Wno-unused-parameter -Wno-deprecated-declarations \
                -I$(SRC) -I$(SRC)/GeneratedUI -DCODEXAPP_REPLICA=1

# 说明：GeneratedUI/ 是"类级等价"占位骨架（无行为实现），为了让工程先跑通出包，
#       默认不参与编译；需要它们进二进制时，把下面的 NOT_GEN 去掉即可。
NOT_GEN := -not -name 'CAFileToolEntry.m'
APP_SRC := $(shell find $(SRC) -name '*.m' $(NOT_GEN) 2>/dev/null | sort)
APP_FRAMEWORKS := -framework UIKit -framework Foundation -framework AVFoundation -framework AVFAudio \
                  -framework Security -framework CoreFoundation -framework CoreGraphics -framework QuartzCore \
                  -framework PhotosUI -framework QuickLook -framework SafariServices -framework WebKit \
                  -framework UniformTypeIdentifiers -framework ImageIO -framework CoreMedia -framework CoreVideo \
                  -lz

.PHONY: all app extension filetool bundle sign package clean check-src

all: bundle

# 源文件清单自检：为空即报错（避免再现 "no sources -> undefined _main"）
check-src:
	@test -n "$(APP_SRC)" || (echo "!! 未找到任何源文件，请检查 $(SRC)"; exit 1)

# ---------------------------------------------------------------- app 主体
app: check-src $(BUNDLE)/CodexApp

$(BUNDLE)/CodexApp: $(APP_SRC)
	@mkdir -p $(BUNDLE)
	$(CLANG) $(COMMON_FLAGS) $(APP_SRC) $(APP_FRAMEWORKS) -o $@

# ------------------------------------------------- ca-filetool（独立二进制，与原包布局一致）
filetool: $(BUNDLE)/Helpers/ca-filetool

$(BUNDLE)/Helpers/ca-filetool: $(SRC)/CAFileToolMain.m $(SRC)/CAArchiveExtractor.m $(SRC)/CARuntimePaths.m \
                               $(SRC)/CALogger.m $(SRC)/CACommon.m $(SRC)/CAProcess.m $(SRC)/CAFileToolEntry.m
	@mkdir -p $(BUNDLE)/Helpers
	$(CLANG) $(COMMON_FLAGS) -DCA_NO_AGENT_RUNTIME=1 $(SRC)/CAFileToolMain.m $(SRC)/CAArchiveExtractor.m $(SRC)/CARuntimePaths.m \
	         $(SRC)/CALogger.m $(SRC)/CACommon.m $(SRC)/CAProcess.m $(SRC)/CAFileToolEntry.m -framework Foundation -framework UIKit -lz -o $@

# ---------------------------------------------------------------- 分享扩展
extension: $(BUNDLE)/PlugIns/MTShareExtension.appex/MTShareExtension

$(BUNDLE)/PlugIns/MTShareExtension.appex/MTShareExtension: $(wildcard $(EXT_SRC)/*.m) $(wildcard $(EXT_SRC)/*.h)
	@mkdir -p $(BUNDLE)/PlugIns/MTShareExtension.appex
	$(CLANG) $(COMMON_FLAGS) -fapplication-extension -bundle -I$(EXT_SRC) $(EXT_SRC)/MTShareExtension.m \
	         -framework UIKit -framework Foundation -framework UniformTypeIdentifiers -o $@

# ------------------------------------------ 装配 bundle（资源 + Helpers 符号链接，按原包清单）
bundle: app extension filetool
	@echo "== 装配 bundle（依据 build/bundle_manifest.json 还原顺序/权限/符号链接）=="
	python3 $(ROOT)/build/assemble_bundle.py --bundle "$(BUNDLE)" \
	        --manifest "$(MANIFEST)" --assets "$(ASSETS)" --keep-original-binaries

sign: bundle
	@echo "== 签名（ldid -S<entitlements>；缺失则回退 codesign adhoc）=="
	-ldid -S$(ROOT)/MTAgent/entitlements.plist "$(BUNDLE)/CodexApp" || \
	  codesign --force --sign - --entitlements $(ROOT)/MTAgent/entitlements.plist "$(BUNDLE)/CodexApp"
	-ldid -S$(ROOT)/MTShareExtension/entitlements.plist "$(BUNDLE)/PlugIns/MTShareExtension.appex/MTShareExtension" || \
	  codesign --force --sign - --entitlements $(ROOT)/MTShareExtension/entitlements.plist "$(BUNDLE)/PlugIns/MTShareExtension.appex/MTShareExtension"
	-ldid -S$(ROOT)/MTAgent/entitlements.plist "$(BUNDLE)/Helpers/ca-filetool" || \
	  codesign --force --sign - "$(BUNDLE)/Helpers/ca-filetool"
	@if [ -f "$(BUNDLE)/Helpers/codex" ]; then \
	  echo "== 签名 codex 内核 =="; \
	  ldid -S$(ROOT)/Kernel/entitlements-kernel.plist "$(BUNDLE)/Helpers/codex" || \
	    ldid -S "$(BUNDLE)/Helpers/codex" || true; \
	  ldid -e "$(BUNDLE)/Helpers/codex" | head -20 || true; \
	else \
	  echo "::warning::Helpers/codex 缺失（先跑 build-kernel-ios 工作流）"; \
	fi

package: sign
	python3 $(ROOT)/build/package_tipa.py --bundle "$(BUILD)/Payload" \
	        --manifest "$(MANIFEST)" --output $(ROOT)/build/MT-Agent-replica.tipa

clean:
	rm -rf $(BUILD)
