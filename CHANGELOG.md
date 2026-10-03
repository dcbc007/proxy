## 1.2.2

- Smart 模式改为 Android TUN 边缘分流：中国私网/CN 域名/CN IP 直接连接，DNS 与非 CN 流量送入 sing-box。
- Smart 规则切换到官方 geosite-cn + geoip-cn 规则集，避免 geolocation 标签与原生桥接识别不一致。
- 国内 DNS 使用 AliDNS DoH，并固定 TLS SNI 为 dns.alidns.com；移除 Smart DNS 的 evaluate/respond 探测链，降低阻塞与误判。
- CI 增加 Smart 分流结构回归检查，防止再次退化成全部转发模式。

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

- 构建验证：1.0.2 Android release pipeline.
