# Aurum Proxy iOS 编译说明（iOS 15+）

## 你需要的环境

- 一台 Mac（Apple Silicon 或 Intel 均可）
- Xcode（登录你的 Apple ID / Apple Developer Team）
- Flutter stable
- Git、Go、Python 3、CocoaPods；核心脚本另外会使用 curl、jq
- 一台真 iPhone。系统级 Packet Tunnel VPN 不能用模拟器做真实连接测试。

## 1. 解压源码并准备依赖/核心

在终端进入项目根目录：

```bash
chmod +x scripts/bootstrap_ios_macos.sh
./scripts/bootstrap_ios_macos.sh
```

脚本会：
1. 获取 `v2ray_box`；
2. 生成标准 Flutter iOS/Android 平台工程（如果尚不存在）；
3. 设置 iOS 15.0 与相机二维码权限；
4. 编译 `ios/Frameworks/Libbox.xcframework`；
5. 执行 `flutter pub get` 与 `pod install`。

## 2. 在 Xcode 建 Packet Tunnel Extension

打开：

```bash
open ios/Runner.xcworkspace
```

然后在 Xcode：

1. `File > New > Target...`；
2. 选择 `Network Extension`；
3. 名称填写 `PacketTunnel`；
4. Provider Type 选择 `Packet Tunnel`；
5. Deployment Target 设为 iOS 15.0 或以上；
6. Runner 和 PacketTunnel 两个 target 都选择同一个 Apple Developer Team；
7. Runner 使用唯一 Bundle ID，例如 `com.yourname.aurumproxy`；
8. PacketTunnel 使用 `com.yourname.aurumproxy.PacketTunnel`。

如果 `ios/PacketTunnelSource` 中已经由脚本复制出 v2box 示例的 PacketTunnel 文件，把这些文件加入 **PacketTunnel target**（不要加入 Runner target），并以示例的 `PacketTunnelProvider.swift` 替换 Xcode 自动生成的空 Provider。

## 3. 配置 Framework / Capability

PacketTunnel target -> `General > Frameworks, Libraries, and Embedded Content`：

- `ios/Frameworks/Libbox.xcframework`
- `NetworkExtension.framework`
- `UIKit.framework`

本项目固定使用 sing-box，因此不需要 `LibXray.xcframework`。

在 `Signing & Capabilities` 中启用 Network Extensions / Packet Tunnel 能力。Apple 的签名配置必须同时覆盖主 App 与 Extension。若你的 Apple Team 不具备相应 entitlement，Xcode 会在签名或安装阶段明确报错，需要在 Apple Developer 侧启用对应能力。

## 4. 真机编译

连接 iPhone，在 Xcode 顶部选择你的真机，然后先执行：

`Product > Clean Build Folder`

再执行：

`Product > Run`

第一次点击 Aurum Proxy 首页连接按钮时，iOS 会弹出“添加 VPN 配置”授权。允许后才会建立系统级 VPN。

## 5. 导出 IPA / TestFlight

要发给其他设备：

1. Xcode 选择 `Any iOS Device (arm64)`；
2. `Product > Archive`；
3. Organizer 中选择 `Distribute App`；
4. 可选择 TestFlight / App Store Connect，或根据你的开发者证书类型导出 Development / Ad Hoc 包。

普通免费 Apple ID 适合自己真机调试；稳定分发和 TestFlight 通常需要 Apple Developer Program。

## 6. 常见错误

- **找不到 Libbox**：重新运行 `./scripts/bootstrap_ios_macos.sh`，确认 `ios/Frameworks/Libbox.xcframework` 存在。
- **VPN 点了无反应**：确认是真机、PacketTunnel target 已签名、Network Extension capability 正确。
- **扫码黑屏**：确认 `Info.plist` 存在 `NSCameraUsageDescription`，并在 iPhone 设置中允许相机权限。
- **No such module / Pods 错误**：执行 `cd ios && pod install`，必须打开 `Runner.xcworkspace`，不要打开 `Runner.xcodeproj`。
