# Aurum Proxy v1.0.0

黑金风格的 Android / iOS 系统级代理客户端源码。UI 按本项目 `design/reference-ui.jpeg` 实现。

## 已接入的真实功能

- Android：系统 `VpnService` VPN 模式；iOS：`NetworkExtension / PacketTunnel`
- sing-box 作为实际代理核心；Android 采用 v2ray_box 的 VPN/TUN 集成
- 节点：手动添加、剪贴板批量导入、相机扫码添加
- 节点链接：Shadowsocks、VLESS、VMess、Trojan、Hysteria2；Snell v5 提供 sing-box JSON fallback
- VLESS Reality：Public Key、Short ID、SNI、uTLS 指纹、Flow
- TCP / WS / gRPC / HTTP / H2 / HTTPUpgrade / xHTTP / QUIC 参数入口
- 系统 VPN 权限申请、连接、断开、状态监听
- 真实延迟测试、实时上下行统计、核心日志/告警
- 智能 / 全局 / 直连模式切换
- 订阅保存、更新；兼容常见纯 URI 与 base64 URI-list 订阅，并调用核心订阅解析器
- 节点/订阅/选择状态本地持久化
- Android Release APK 一键构建脚本
- iOS 核心编译脚本与完整 Xcode / PacketTunnel 配置说明

## 目录

- `lib/` Flutter UI 与业务逻辑
- `scripts/build_android_release.ps1` Windows 构建 Android APK
- `scripts/bootstrap_ios_macos.sh` macOS 准备 iOS 工程与 sing-box xcframework
- `BUILD_ANDROID_CN.md` Android 编译说明
- `BUILD_IOS_CN.md` iOS 编译、签名、真机安装说明
- `platform_templates/` 平台配置模板
- `.github/workflows/build-android.yml` 可选的 GitHub Actions APK 构建工作流

## 说明

`third_party/v2box` 和代理核心二进制不会直接塞进源码压缩包。构建脚本会从其官方公开仓库获取并在本机编译，避免把不透明预编译核心混入源码。分发 APK/IPA 时请遵守 `THIRD_PARTY_NOTICES.md` 中对应开源许可证要求。
