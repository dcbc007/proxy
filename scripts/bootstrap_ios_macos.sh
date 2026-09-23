#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

command -v flutter >/dev/null || { echo "缺少 Flutter"; exit 1; }
command -v git >/dev/null || { echo "缺少 Git"; exit 1; }
command -v go >/dev/null || { echo "缺少 Go"; exit 1; }
command -v pod >/dev/null || { echo "缺少 CocoaPods"; exit 1; }

if [ ! -f third_party/v2box/pubspec.yaml ]; then
  mkdir -p third_party
  git clone --depth 1 https://github.com/imanheidary/v2box.git third_party/v2box
fi

if [ ! -f ios/Runner.xcodeproj/project.pbxproj ] || [ ! -f android/gradlew ]; then
  rm -rf .aurum_scaffold
  flutter create --platforms=android,ios --org com.aurumproxy --project-name aurum_proxy .aurum_scaffold
  [ -f android/gradlew ] || cp -R .aurum_scaffold/android ./android
  [ -f ios/Runner.xcodeproj/project.pbxproj ] || cp -R .aurum_scaffold/ios ./ios
  rm -rf .aurum_scaffold
fi

python3 tool/prepare_platforms.py "$ROOT"
flutter pub get

# Pin sing-box 1.14.1 so Snell support is present.
if [ ! -f third_party/sing-box/go.mod ]; then
  git clone --depth 1 --branch v1.14.1 https://github.com/SagerNet/sing-box.git third_party/sing-box
fi
# Build sing-box xcframework. iOS uses PacketTunnel NetworkExtension.
bash third_party/v2box/example/scripts/build_ios_libsingbox.sh --project-root "$ROOT" --singbox-dir "$ROOT/third_party/sing-box"

mkdir -p ios/PacketTunnelSource
if [ -d third_party/v2box/example/ios/PacketTunnel ]; then
  cp -R third_party/v2box/example/ios/PacketTunnel/. ios/PacketTunnelSource/
fi

cd ios
pod install
cd "$ROOT"
echo "基础 iOS 工程、Pods 与 Libbox.xcframework 已准备。下一步按 BUILD_IOS_CN.md 在 Xcode 中创建/配置 PacketTunnel target 并签名。"
