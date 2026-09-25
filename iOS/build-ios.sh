#!/bin/zsh
# 一千四百一十八天 · iOS 版构建
#
#   ./build-ios.sh              检查剧本 → 生成工程 → 编译 → 装到模拟器并启动（默认 iPhone 17 Pro）
#   ./build-ios.sh device       编译 Release，装到连着的 iPhone 并启动（个人团队签名，7 天后要重装）
#   ./build-ios.sh open         只生成工程并用 Xcode 打开
#
#   SIM="iPad Pro 11-inch (M5)" ./build-ios.sh    换一台模拟器
set -euo pipefail
cd "${0:A:h}"

MODE="${1:-sim}"
BUNDLE_ID="local.leo.days1418"
SIM="${SIM:-iPhone 17 Pro}"
DERIVED="build/DerivedData"
mkdir -p build

# 同一时间只许跑一个：两次编译共用 build/DerivedData，一边还在签名，另一边就可能把签了一半的 App 装进手机
# （2026-09-25 真出过一次：装上了却报 invalid code signature 打不开）。lockf 的锁跟着进程走，退出或 Ctrl-C 自动释放
if [[ -z "${BUILD_IOS_LOCKED:-}" ]]; then
  lock_status=0
  BUILD_IOS_LOCKED=1 lockf -s -t 0 build/.lock "${0:A}" "$@" || lock_status=$?
  if [[ $lock_status == 75 ]]; then
    echo "✘ 另一个 build-ios.sh 正在跑，等它结束再试"
  fi
  exit $lock_status
fi

# 剧本和 Mac 版共用：Mac 版的检查器还在的话先过一遍静态检查（不跑模拟，几秒钟）
if [[ -x ../build/Days1418 ]]; then
  echo "▸ 检查剧本"
  if ! ../build/Days1418 -check ../story -runs 0 > build/check.log; then
    tail -n 30 build/check.log
    echo "✘ 剧本有错误，先修剧本"
    exit 1
  fi
  tail -n 1 build/check.log
fi

if [[ ! -f Days1418/Assets.xcassets/AppIcon.appiconset/icon-1024.png || tools/render-icon.swift -nt Days1418/Assets.xcassets/AppIcon.appiconset/icon-1024.png ]]; then
  echo "▸ 渲染图标"
  swiftc -parse-as-library -O tools/render-icon.swift -o build/render-icon
  build/render-icon Days1418/Assets.xcassets/AppIcon.appiconset/icon-1024.png
fi

echo "▸ 生成 Xcode 工程"
xcodegen generate --quiet

if [[ "$MODE" == "open" ]]; then
  open Days1418.xcodeproj
  exit 0
fi

if [[ "$MODE" == "device" ]]; then
  # 苹果开发者团队 ID 不进仓库：先看环境变量，再看本地的 iOS/.team（一行，比如 ABCDE12345；已在 .gitignore 里）
  # （文件不存在时别用 $(head …) 硬读：set -e 加 pipefail 会让脚本在这一行悄悄退出，提示都来不及打）
  TEAM="${DEVELOPMENT_TEAM:-}"
  if [[ -z "$TEAM" && -f .team ]]; then
    TEAM="$(head -n 1 .team | tr -d '[:space:]')"
  fi
  if [[ -z "$TEAM" ]]; then
    echo "✘ 装真机要用你自己的苹果开发者团队 ID（Xcode → 设置 → Apple 账户里能看到）："
    echo "  写进 iOS/.team，或者 DEVELOPMENT_TEAM=ABCDE12345 ./build-ios.sh device"
    exit 1
  fi
  # 设备名里可能有空格（"某某的 iPhone"），按列切不可靠，读 devicectl 的 JSON；xcodebuild 要的是 UDID
  xcrun devicectl list devices --json-output build/devices.json >/dev/null 2>&1 || true
  DEVICE=$(python3 - build/devices.json <<'PY'
import json, sys
try:
    devices = json.load(open(sys.argv[1]))["result"]["devices"]
except Exception:
    sys.exit(0)
# 刚插上、还没为开发准备好的手机不报 reality 字段，所以只排除明确标成 simulated 的
phones = [d for d in devices
          if d.get("hardwareProperties", {}).get("platform") == "iOS"
          and d.get("hardwareProperties", {}).get("reality") != "simulated"]
phones.sort(key=lambda d: d["hardwareProperties"].get("deviceType") != "iPhone")   # iPhone 优先于 iPad
if phones:
    print(phones[0]["hardwareProperties"]["udid"])
PY
)
  if [[ -z "$DEVICE" ]]; then
    echo "✘ 没找到连着的 iPhone：用数据线连上 Mac 并在手机上点「信任」，再到 设置 → 隐私与安全性 → 开发者模式 打开"
    exit 1
  fi
  # 刚插上的手机在 xcodebuild 眼里是"离线"的：先用 devicectl 连一下建立隧道，再等 Xcode 把它认成在线（最多 60 秒）
  echo "▸ 连接 iPhone"
  xcrun devicectl device info details --device "$DEVICE" >/dev/null 2>&1 || true
  for _ in {1..12}; do
    xcrun xctrace list devices 2>/dev/null | sed -n '/== Devices ==/,/== Devices Offline ==/p' | grep -q "$DEVICE" && break
    sleep 5
  done
  echo "▸ 编译 Release（真机 $DEVICE）"
  xcodebuild -project Days1418.xcodeproj -scheme Days1418 -configuration Release \
    -destination "id=$DEVICE" -derivedDataPath "$DERIVED" -allowProvisioningUpdates DEVELOPMENT_TEAM="$TEAM" \
    build -quiet
  APP="$DERIVED/Build/Products/Release-iphoneos/Days1418.app"
  echo "▸ 安装到 iPhone"
  xcrun devicectl device install app --device "$DEVICE" "$APP"
  xcrun devicectl device process launch --device "$DEVICE" "$BUNDLE_ID" || \
    echo "（第一次装要在手机上 设置 → 通用 → VPN与设备管理 里信任开发者证书，然后再点图标打开）"
  echo "✓ 已装到 iPhone"
  exit 0
fi

echo "▸ 编译 Debug（模拟器）"
xcodebuild -project Days1418.xcodeproj -scheme Days1418 -configuration Debug \
  -destination "platform=iOS Simulator,name=$SIM" -derivedDataPath "$DERIVED" \
  build -quiet
APP="$DERIVED/Build/Products/Debug-iphonesimulator/Days1418.app"

UDID=$(xcrun simctl list devices available | grep -F "    $SIM (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
if [[ -z "$UDID" ]]; then
  echo "✘ 没有叫「$SIM」的模拟器"
  exit 1
fi
xcrun simctl boot "$UDID" 2>/dev/null || true
# Simulator.app 不一定在 LaunchServices 里注册过，按 Xcode 的路径打开；打不开也不影响安装
open "$(xcode-select -p)/Applications/Simulator.app" 2>/dev/null || true
xcrun simctl install "$UDID" "$APP"
xcrun simctl launch "$UDID" "$BUNDLE_ID" > /dev/null
echo "✓ 已在模拟器「$SIM」里启动"
