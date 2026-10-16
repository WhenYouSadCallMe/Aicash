#!/usr/bin/env bash
# Kernel/build.sh — 编译 codex 内核到 iOS arm64（本地 macOS 或 CI 皆可）
# 用法: ./Kernel/build.sh [codex_ref] [profile]
set -euo pipefail
cd "$(dirname "$0")/.."

REF="${1:-rust-v0.162.1}"
PROFILE="${2:-release}"
TARGET=aarch64-apple-ios

command -v cargo >/dev/null || { echo "需要 Rust：https://rustup.rs"; exit 1; }
rustup target add "$TARGET"

[ -d upstream ] || git clone --filter=blob:none https://github.com/openai/codex.git upstream
cd upstream
git checkout "$REF"

for p in ../Kernel/patches/*.patch; do
  [ -e "$p" ] || continue
  echo "applying $p"
  git apply --index "$p" || { echo "PATCH FAILED: $p"; exit 1; }
done

if [ "$(uname)" = "Darwin" ]; then
  SDK=$(xcrun --sdk iphoneos --show-sdk-path)
  export SDKROOT="$SDK"
  export IPHONEOS_DEPLOYMENT_TARGET=15.0
  export CARGO_TARGET_AARCH64_APPLE_IOS_RUSTFLAGS="-C link-arg=-mios-version-min=15.0 -C link-arg=-isysroot -C link-arg=$SDK -C link-arg=-framework -C link-arg=Security -C link-arg=-framework -C link-arg=CoreFoundation"
fi

cargo build --profile "$PROFILE" --target "$TARGET" --bin codex

BIN="target/$TARGET/$PROFILE/codex"
mkdir -p ../Kernel/dist
cp "$BIN" ../Kernel/dist/codex
strip -x ../Kernel/dist/codex 2>/dev/null || true
[ "$(uname)" = "Darwin" ] && ldid -S"../Kernel/entitlements-kernel.plist" ../Kernel/dist/codex || true
shasum -a 256 ../Kernel/dist/codex | tee ../Kernel/dist/codex.sha256
echo "DONE: Kernel/dist/codex"
