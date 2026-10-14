#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
xcodebuild -project InfiniteCalendar.xcodeproj -scheme InfiniteCalendar \
  -configuration Release -derivedDataPath build/DerivedData \
  -destination 'generic/platform=macOS' ARCHS=arm64 ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO build 2>&1 | tee build/xcodebuild.log
APP="build/DerivedData/Build/Products/Release/InfiniteCalendar.app"
mkdir -p "$APP/Contents/Resources"
swift scripts/CreateIcon.swift build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - --options runtime "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
file "$APP/Contents/MacOS/InfiniteCalendar" | tee build/binary-info.txt
lipo "$APP/Contents/MacOS/InfiniteCalendar" -verify_arch arm64
plutil -lint "$APP/Contents/Info.plist"
mkdir -p build/dmg-root
ditto "$APP" build/dmg-root/InfiniteCalendar.app
ln -sfn /Applications build/dmg-root/Applications
cp INSTALL.md build/dmg-root/Installazione.txt
rm -f build/InfiniteCalendar.dmg
hdiutil create -volname InfiniteCalendar -srcfolder build/dmg-root \
  -ov -format UDZO build/InfiniteCalendar.dmg
hdiutil verify build/InfiniteCalendar.dmg
shasum -a 256 build/InfiniteCalendar.dmg > build/InfiniteCalendar.dmg.sha256
echo 'Release DMG built and verified.'
