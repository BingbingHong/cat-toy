#!/bin/bash
# 打包成 build/CatToy.app（Intel + Apple 芯片通用），并生成可分发的 build/CatToy.zip
set -euo pipefail
cd "$(dirname "$0")"

APP=build/CatToy.app
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/"
cp ../cat.html "$APP/Contents/Resources/cat.html"
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"     # 图标由 make_icon.sh 从 icon.svg 生成
for arch in arm64 x86_64; do
  swiftc -O main.swift -target "$arch-apple-macos12" -o "build/CatToy-$arch" -framework Cocoa -framework WebKit
done
lipo -create build/CatToy-arm64 build/CatToy-x86_64 -output "$APP/Contents/MacOS/CatToy"
rm build/CatToy-arm64 build/CatToy-x86_64
codesign --force -s - "$APP" >/dev/null 2>&1
ditto -c -k --keepParent "$APP" build/CatToy.zip
echo "Built $APP and build/CatToy.zip"
