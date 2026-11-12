#!/bin/bash
# 在 macOS 上把 Sources/ 编成未签名的 DSHGo-unsigned.ipa
# 用法：chmod +x build.sh && ./build.sh
set -euo pipefail
cd "$(dirname "$0")"

APP=DSHGo
MIN=15.0
OUT=build
SDK=$(xcrun --sdk iphoneos --show-sdk-path)
echo "SDK: $SDK"

rm -rf "$OUT"
mkdir -p "$OUT/Payload/$APP.app"

xcrun --sdk iphoneos swiftc \
  -target "arm64-apple-ios$MIN" \
  -sdk "$SDK" \
  -swift-version 5 \
  -O -whole-module-optimization \
  -module-name "$APP" \
  -o "$OUT/Payload/$APP.app/$APP" \
  Sources/*.swift

cp Info.plist "$OUT/Payload/$APP.app/Info.plist"
if [ -d Resources ]; then cp -R Resources/. "$OUT/Payload/$APP.app/"; fi
printf 'APPL????' > "$OUT/Payload/$APP.app/PkgInfo"

# ad-hoc 签名：让 bundle 结构合法；装到手机前由签名工具重新签
/usr/bin/codesign --force --sign - "$OUT/Payload/$APP.app" || true

cd "$OUT"
rm -f "../$APP-unsigned.ipa"
zip -qry "../$APP-unsigned.ipa" Payload
cd ..
echo "OK: $(pwd)/$APP-unsigned.ipa"
ls -lh "$APP-unsigned.ipa"
