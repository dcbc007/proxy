$ErrorActionPreference = "Stop"
$Root = (Resolve-Path "$PSScriptRoot\..").Path
Set-Location $Root

& "$PSScriptRoot\ensure_scaffold.ps1" -Root $Root

foreach ($cmd in @('go','bash')) {
  if (!(Get-Command $cmd -ErrorAction SilentlyContinue)) { throw "未找到 $cmd。Android 核心编译需要 Go 与 Git Bash。" }
}

$env:ANDROID_NDK_HOME = if ($env:ANDROID_NDK_HOME) { $env:ANDROID_NDK_HOME } elseif ($env:ANDROID_NDK_ROOT) { $env:ANDROID_NDK_ROOT } else { $env:ANDROID_NDK_HOME }
if (!$env:ANDROID_NDK_HOME) {
  Write-Warning "未检测到 ANDROID_NDK_HOME。请在 Android Studio > SDK Manager > SDK Tools 安装 NDK，并设置环境变量后重试。"
}

Write-Host "[1/3] 编译 Android Xray TUN bridge..." -ForegroundColor Cyan
bash third_party/v2box/example/scripts/build_android_libxray.sh --project-root "$Root"

Write-Host "[2/3] 编译 Android sing-box 1.14.1 核心（arm64，含 Snell v5）..." -ForegroundColor Cyan
if (!(Test-Path "third_party\sing-box\go.mod")) {
  git clone --depth 1 --branch v1.14.1 https://github.com/SagerNet/sing-box.git third_party/sing-box
}
bash third_party/v2box/example/scripts/build_android_libsingbox.sh --project-root "$Root" --singbox-dir "$Root/third_party/sing-box" --android-abis arm64-v8a

Write-Host "[3/3] 构建 Release APK..." -ForegroundColor Cyan
flutter build apk --release --target-platform android-arm64

New-Item -ItemType Directory -Force -Path dist | Out-Null
Copy-Item -Force build/app/outputs/flutter-apk/app-release.apk dist/AurumProxy-1.0.0-arm64.apk
Write-Host "完成：$Root\dist\AurumProxy-1.0.0-arm64.apk" -ForegroundColor Green
