# ============================================================================
#  MT Agent 复刻版构建（macOS + Xcode 命令行工具，无需 Xcode 工程文件）
#  产物布局与原包一致：Payload/CodexApp.app/{CodexApp,Helpers/*,PlugIns/...}
#  用法：  make            # 编译 app + 扩展 + ca-filetool 并装配 bundle
#          make package    # 生成 MT-Agent-replica.tipa（权限/符号链接与原包一致）
#          make clean
# ============================================================================

SDK            ?= $(shell xcrun --sdk iphoneos --show-sdk-path)
MIN_IOS        ?= 15.0
ARCH           ?= arm64
CLANG          ?= xcrun --sdk iphoneos clang
BUILD          := build/out
BUNDLE         := $(BUILD)/Payload/CodexApp.app
SRC            := MTAgent/Sources
EXT_SRC        := MTShareExtension/Sources

COMMON_FLAGS := -arch $(ARCH) -isysroot $(SDK) -miphoneos-version-min=$(MIN_IOS) \
                -fobjc-arc -fmodules -O2 -Wall -Wno-unused-parameter -Wno-deprecated-declarations \
                -I$(SRC) -DCODEXAPP_REPLICA=1

APP_SRC := $(shell find $(SRC) -name '*.m' | sort)
APP_FRAMEWORKS := -framework UIKit -framework Foundation -framework AVFoundation -framework AVFAudio \
                  -framework Security -framework CoreFoundation -framework CoreGraphics -framework QuartzCore \
                  -framework PhotosUI -framework QuickLook -framework SafariServices -framework WebKit \
                  -framework UniformTypeIdentifiers -framework ImageIO -framework CoreMedia -framework CoreVideo \
                  -lz

.PHONY: all app extension filetool bundle sign package clean

all: bundle

# ---------------------------------------------------------------- app 主体
app: $(BUNDLE)/CodexApp

$(BUNDLE)/CodexApp: $(APP_SRC) $(wildcard $(SRC)/*.h)
	@mkdir -p $(BUNDLE)
	$(CLANG) $(COMMON_FLAGS) $(APP_SRC) $(APP_FRAMEWORKS) -o $@

# ---------------------------------------------------------------- ca-filetool（独立二进制，与原包布局一致）
filetool: $(BUNDLE)/Helpers/ca-filetool

$(BUNDLE)/Helpers/ca-filetool: $(SRC)/CAFileToolMain.m $(SRC)/CAArchiveExtractor.m $(SRC)/CARuntimePaths.m \
                               $(SRC)/CALogger.m $(SRC)/CACommon.m
	@mkdir -p $(BUNDLE)/Helpers
	$(CLANG) $(COMMON_FLAGS) $(SRC)/CAFileToolMain.m $(SRC)/CAArchiveExtractor.m $(SRC)/CARuntimePaths.m \
	         $(SRC)/CALogger.m $(SRC)/CACommon.m -framework Foundation -framework UIKit -lz -o $@

# ---------------------------------------------------------------- 分享扩展
extension: $(BUNDLE)/PlugIns/MTShareExtension.appex/MTShareExtension

$(BUNDLE)/PlugIns/MTShareExtension.appex/MTShareExtension: $(wildcard $(EXT_SRC)/*.m) $(wildcard $(EXT_SRC)/*.h)
	@mkdir -p $(BUNDLE)/PlugIns/MTShareExtension.appex
	$(CLANG) $(COMMON_FLAGS) -fapplication-extension -I$(EXT_SRC) $(EXT_SRC)/MTShareExtension.m \
	         -framework UIKit -framework Foundation -framework UniformTypeIdentifiers -o $@

# ---------------------------------------------------------------- 装配 bundle（资源 + Helpers 符号链接）
bundle: app extension filetool
	@echo "== 装配 bundle（按 build/bundle_manifest.json 还原顺序/权限/符号链接）=="
	python3 build/assemble_bundle.py --bundle "$(BUNDLE)" --manifest build/bundle_manifest.json \
	        --assets OriginalAssets/Payload/CodexApp.app --keep-original-binaries

.PHONY: sign
sign: bundle
	@echo "== 签名（ldid -S<entitlements>；无 ldid 时回退 codesign adhoc）=="
	-ldid -SMTAgent/entitlements.plist "$(BUNDLE)/CodexApp" || codesign --force --sign - --entitlements MTAgent/entitlements.plist "$(BUNDLE)/CodexApp"
	-ldid -SMTShareExtension/entitlements.plist "$(BUNDLE)/PlugIns/MTShareExtension.appex/MTShareExtension" || \
	  codesign --force --sign - --entitlements MTShareExtension/entitlements.plist "$(BUNDLE)/PlugIns/MTShareExtension.appex/MTShareExtension"
	-ldid -SMTAgent/entitlements.plist "$(BUNDLE)/Helpers/ca-filetool" || codesign --force --sign - "$(BUNDLE)/Helpers/ca-filetool"

package: sign
	python3 build/package_tipa.py --bundle "$(BUILD)/Payload" --manifest build/bundle_manifest.json \
	        --output build/MT-Agent-replica.tipa

clean:
	rm -rf $(BUILD)
