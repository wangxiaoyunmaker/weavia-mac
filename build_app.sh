#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
cd "$SCRIPT_DIR"

zsh "$SCRIPT_DIR/build_icon.sh"
swift build -c release -j 2

APP_DIR="${WEAVIA_APP_DIR:-$SCRIPT_DIR/WEAVIA.app}"
BIN_PATH="$SCRIPT_DIR/.build/release/MouseCompanion"

mkdir -p "$APP_DIR/Contents/MacOS"
cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/MouseCompanion"
mkdir -p "$APP_DIR/Contents/Resources"
cp "$SCRIPT_DIR/BrandAssets/WEAVIA.icns" "$APP_DIR/Contents/Resources/WEAVIA.icns"
cp "$SCRIPT_DIR/Sources/MouseCompanion/BrowserCapture.js" "$APP_DIR/Contents/Resources/BrowserCapture.js"
cp -R "$SCRIPT_DIR/Sources/MouseCompanion/DesignSkills" "$APP_DIR/Contents/Resources/"
cp -R "$SCRIPT_DIR/Sources/MouseCompanion/CuppaCanvas" "$APP_DIR/Contents/Resources/"

/usr/libexec/PlistBuddy -c 'Clear dict' "$APP_DIR/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c 'Add :CFBundleName string WEAVIA' "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleDisplayName string WEAVIA' "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleIdentifier string com.designerworkspace.mousecompanion.macworkspace' "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleVersion string 6' "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleShortVersionString string 0.2.5' "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleIconFile string WEAVIA.icns' "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleExecutable string MouseCompanion' "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundlePackageType string APPL' "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :LSUIElement bool false' "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :NSHighResolutionCapable bool true' "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :NSAppleEventsUsageDescription string 在你主动召唤、圈画或拖入内容时，读取来源浏览器的选中文字、页面标题及图片，加入鼠标伙伴的上下文。' "$APP_DIR/Contents/Info.plist"

codesign --force --deep --sign - \
  --requirements '=designated => identifier "com.designerworkspace.mousecompanion.macworkspace"' \
  "$APP_DIR"
echo "$APP_DIR"
