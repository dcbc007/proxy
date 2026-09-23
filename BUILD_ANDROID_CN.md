# Aurum Proxy Android APK 编译说明

## 环境

Windows 10/11 可用。安装：
- Flutter stable（加入 PATH）
- Android Studio + Android SDK + Android NDK
- JDK 17+
- Git for Windows（带 Git Bash）
- Go
- Python 3

v2ray_box 的核心构建脚本还需要 `curl`、`jq`、`unzip`、`zip`。如 Git Bash 缺少 `jq`，安装 jq 后加入 PATH。

在 Android Studio -> SDK Manager -> SDK Tools 中安装 NDK (Side by side)，并设置 `ANDROID_NDK_HOME` 指向对应 NDK 目录。

## 一键构建

PowerShell 进入项目根目录：

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\scripts\build_android_release.ps1
```

成功后 APK 在：

```text
dist\AurumProxy-1.0.0-arm64.apk
```

这是 arm64 手机版本，适合绝大多数当前 Android 真机。

## 首次使用

1. 安装 APK；
2. `节点 -> +`，可手动、剪贴板或扫码添加；
3. 选择节点；
4. 首页点击金色连接按钮；
5. Android 首次会弹出系统 VPN 授权，选择允许；
6. 状态变为“已连接”后，顶部系统状态栏会显示 VPN 标志。
