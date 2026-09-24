# Changelog

## 1.0.2
- 修复 Android 13+ 点击连接后因通知权限流程阻塞而无响应的问题。
- VPN 授权改为由原生连接流程直接触发，授权后继续启动 VPN。
- 增加连接授权过程日志提示。
- 引入稳定开发签名；从 1.0.2 起后续 APK 可直接覆盖更新安装。

## 1.0.1
- 修复首次 VPN 授权返回值被误判为“权限拒绝”的问题。

## 1.0.0
- 将 v0.1 UI 原型改为真实 VPN 客户端架构。
- 接入 v2ray_box + sing-box。
- Android VpnService / iOS PacketTunnel 构建流程。
- 扫码、剪贴板、多行节点导入。
- 真实连接状态、流量统计、日志与延迟测试。
- 订阅拉取与更新。
- VLESS Reality / Snell v5 配置支持。
- Android Release 构建脚本与 iOS 编译指南。
