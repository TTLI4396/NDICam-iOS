#!/bin/bash
# 在 macOS 上构建未签名 NDICam.ipa
# 用法: ./scripts/build_ipa.sh
set -euo pipefail

cd "$(dirname "$0")/.."
PROJECT_DIR="$(pwd)"
SDK_DIR="$PROJECT_DIR/NDI SDK for Apple"
BUILD_DIR="$PROJECT_DIR/build"
ARCHIVE_PATH="$BUILD_DIR/NDICam.xcarchive"
IPA_PATH="$BUILD_DIR/NDICam.ipa"

echo "=== 1. 检查 NDI SDK ==="
if [ ! -f "$SDK_DIR/lib/iOS/libndi_ios.a" ]; then
    echo "未找到 NDI SDK，正在下载并解包..."
    PKG_PATH="/tmp/Install_NDI_SDK_v6_Apple.pkg"
    curl -fL --retry 3 -o "$PKG_PATH" \
        "https://downloads.ndi.tv/SDK/NDI_SDK_Mac/Install_NDI_SDK_v6_Apple.pkg"
    rm -rf /tmp/ndi_sdk_expanded
    pkgutil --expand-full "$PKG_PATH" /tmp/ndi_sdk_expanded
    SDK_SRC="$(dirname "$(find /tmp/ndi_sdk_expanded -name 'libndi_ios.a' -path '*/lib/iOS/*' | head -1)")/../.."
    cp -R "$SDK_SRC" "$SDK_DIR"
fi
echo "SDK OK: $SDK_DIR"

echo "=== 2. 生成 Xcode 工程 ==="
if ! command -v xcodegen >/dev/null 2>&1; then
    echo "安装 xcodegen..."
    brew install xcodegen
fi
xcodegen generate

echo "=== 3. 归档 (无签名) ==="
rm -rf "$ARCHIVE_PATH"
xcodebuild archive \
    -project NDICam.xcodeproj \
    -scheme NDICam \
    -configuration Release \
    -destination "generic/platform=iOS" \
    -archivePath "$ARCHIVE_PATH" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    | xcpretty 2>/dev/null || xcodebuild archive \
    -project NDICam.xcodeproj \
    -scheme NDICam \
    -configuration Release \
    -destination "generic/platform=iOS" \
    -archivePath "$ARCHIVE_PATH" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY=""

echo "=== 4. 打包 IPA ==="
rm -rf "$BUILD_DIR/Payload" "$IPA_PATH"
mkdir -p "$BUILD_DIR/Payload"
cp -R "$ARCHIVE_PATH/Products/Applications/NDICam.app" "$BUILD_DIR/Payload/"
cd "$BUILD_DIR"
zip -qry NDICam.ipa Payload
rm -rf Payload

echo ""
echo "✅ 构建完成: $IPA_PATH"
echo "注意: 这是未签名 IPA，安装到设备前需要用 AltStore/Sideloadly/开发者证书重新签名。"
