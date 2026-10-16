#!/bin/bash
# ============================================================================
#  MT Agent 复刻版：一键构建 + 打包（macOS）
#  依赖：Xcode 命令行工具（xcrun/clang）、python3、ldid（或 Theos 自带 ldid）
#  用法：bash build/build.sh [--no-package] [--keep-binaries]
# ============================================================================
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PKG=1
KEEP_BINARIES=0
for arg in "$@"; do
  case "$arg" in
    --no-package) PKG=0 ;;
    --keep-binaries) KEEP_BINARIES=1 ;;
    *) echo "未知参数: $arg"; exit 2 ;;
  esac
done

echo "== 环境检查 =="
if ! xcrun --sdk iphoneos --show-sdk-path >/dev/null 2>&1; then
  echo "!! 未找到 iPhoneOS SDK：请安装 Xcode 或 xcode-select --install"; exit 1
fi
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
echo "   SDK      : $SDK"
echo "   clang    : $(xcrun --sdk iphoneos clang --version | head -n1)"
if command -v ldid >/dev/null 2>&1; then
  echo "   ldid     : $(command -v ldid)"
else
  echo "   ldid     : 未安装（将回退 codesign --sign - adhoc）"
fi

echo
echo "== 编译 =="
make -C build all

echo
echo "== 签名 =="
make -C build sign

if [ "$PKG" = "1" ]; then
  echo
  echo "== 打包 .tipa =="
  make -C build package
  echo
  echo "产物: $ROOT/build/MT-Agent-replica.tipa"
  echo "校验: python3 verify/verify_package.py --replica build/MT-Agent-replica.tipa"
fi

echo
echo "== 完成 =="
echo "bundle : build/out/Payload/CodexApp.app"
echo "提示   : Helpers 符号链接由 build/assemble_bundle.py 按 bundle_manifest.json 还原；"
echo "         若本机文件系统不支持符号链接，请改用 DMG 或 APFS 卷后再装配。"
