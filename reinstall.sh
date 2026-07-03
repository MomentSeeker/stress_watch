#!/bin/bash
# ============================================================
#  MyWatch 一键重装脚本
#  免费 Apple ID 装的 App 每 7 天会过期，过期后：
#    1. 戴上手表、解锁、和 Mac 连同一个 Wi-Fi
#    2. 在这个文件夹里双击运行本脚本（或终端里执行 ./reinstall.sh）
#  就会重新编译并装回手表，数据不会丢。
# ============================================================
set -e
cd "$(dirname "$0")"

BUNDLE_ID="com.lichaochen.mywatch.wk7c33q9"
DERIVED="/tmp/mywatch-dev"

echo "🔍 正在查找已连接的 Apple Watch..."
WATCH_LINE=$(xcrun devicectl list devices 2>/dev/null | grep -i "Apple Watch" | grep -iE "connected|available \(paired\)" | head -1)
if [ -z "$WATCH_LINE" ]; then
  echo "❌ 没找到配对过的 Apple Watch。"
  echo "   请确认：手表已解锁、戴在手上、和这台 Mac 连同一个 Wi-Fi，然后重试。"
  exit 1
fi
WATCH_ID=$(echo "$WATCH_LINE" | grep -oE "[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}" | head -1)
echo "⌚️ 找到手表: $WATCH_ID"

# 取 xcodebuild 用的 watchOS 真机 destination id
DEST_ID=$(xcodebuild -project MyWatch.xcodeproj -scheme "MyWatch Watch App" -showdestinations 2>/dev/null \
  | grep -iE "platform:watchOS," | grep -iv "simulator\|placeholder" \
  | grep -oE "id:[0-9A-Za-z-]+" | head -1 | cut -d: -f2)

echo "🔨 正在编译并签名..."
xcodebuild -project MyWatch.xcodeproj -scheme "MyWatch Watch App" \
  -destination "platform=watchOS,id=${DEST_ID}" \
  -allowProvisioningUpdates \
  -derivedDataPath "$DERIVED" build >/tmp/mywatch-build.log 2>&1 \
  && echo "✅ 编译成功" || { echo "❌ 编译失败，详见 /tmp/mywatch-build.log"; tail -20 /tmp/mywatch-build.log; exit 1; }

APP="$DERIVED/Build/Products/Debug-watchos/MyWatch Watch App.app"
echo "📲 正在安装到手表..."
xcrun devicectl device install app --device "$WATCH_ID" "$APP"

echo "🚀 正在启动..."
xcrun devicectl device process launch --device "$WATCH_ID" "$BUNDLE_ID" || true

echo "🎉 完成！抬腕看你的手表上的 MyWatch。"
