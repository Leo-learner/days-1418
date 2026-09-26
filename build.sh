#!/bin/zsh
# 检查剧本 → 编译 → 渲染图标 → 打包 .app → 本地签名 → 放到桌面
set -euo pipefail
cd "${0:A:h}"

APP_NAME="一千四百一十八天"
EXEC="Days1418"
BUILD="build"
APP="$BUILD/$APP_NAME.app"
DEST="$HOME/Desktop/$APP_NAME.app"

mkdir -p "$BUILD"

echo "▸ 编译（-O 整模块优化）"
swiftc -O -wmo -parse-as-library -swift-version 5 \
  -target arm64-apple-macos15.0 \
  Sources/*.swift -o "$BUILD/$EXEC"

echo "▸ 检查剧本"
"$BUILD/$EXEC" -check story -runs "${RUNS:-2000}" | tail -n 60

if [[ ! -f "$BUILD/AppIcon.icns" || Sources/Icon.swift -nt "$BUILD/AppIcon.icns" ]]; then
  echo "▸ 渲染图标"
  "$BUILD/$EXEC" -render-icon "$BUILD/icon_1024.png"
  ICONSET="$BUILD/AppIcon.iconset"
  rm -rf "$ICONSET"
  mkdir -p "$ICONSET"
  for s in 16 32 128 256 512; do
    sips -z $s $s "$BUILD/icon_1024.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s * 2)) $((s * 2)) "$BUILD/icon_1024.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$BUILD/AppIcon.icns"
fi

echo "▸ 打包 $APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD/$EXEC" "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/"
cp "$BUILD/AppIcon.icns" "$APP/Contents/Resources/"
ditto story "$APP/Contents/Resources/story"
codesign --force --sign - "$APP"

if [[ "${NO_INSTALL:-0}" == "1" ]]; then
  echo "✓ 已打包（未安装）：$APP"
  exit 0
fi

echo "▸ 放到桌面"
if pgrep -x "$EXEC" >/dev/null; then
  pkill -x "$EXEC"
  sleep 0.5
fi
rm -rf "$DEST"
ditto "$APP" "$DEST"
touch "$DEST"
echo "✓ 完成：$DEST"
