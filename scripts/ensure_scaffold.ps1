param([string]$Root = (Resolve-Path "$PSScriptRoot\.."))
$ErrorActionPreference = "Stop"
Set-Location $Root

if (!(Get-Command flutter -ErrorAction SilentlyContinue)) { throw "未找到 Flutter。请先安装 Flutter stable 并加入 PATH。" }
if (!(Get-Command git -ErrorAction SilentlyContinue)) { throw "未找到 Git。" }

if (!(Test-Path "third_party\v2box\pubspec.yaml")) {
  New-Item -ItemType Directory -Force -Path third_party | Out-Null
  git clone --depth 1 https://github.com/imanheidary/v2box.git third_party/v2box
}

if (!(Test-Path "android\gradlew") -or !(Test-Path "ios\Runner.xcodeproj\project.pbxproj")) {
  $tmp = Join-Path $Root ".aurum_scaffold"
  if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
  flutter create --platforms=android,ios --org com.aurumproxy --project-name aurum_proxy $tmp
  if (!(Test-Path "android\gradlew")) { Copy-Item -Recurse -Force "$tmp\android" "$Root\android" }
  if (!(Test-Path "ios\Runner.xcodeproj\project.pbxproj")) { Copy-Item -Recurse -Force "$tmp\ios" "$Root\ios" }
  Remove-Item -Recurse -Force $tmp
}

python tool/prepare_platforms.py $Root
flutter pub get
Write-Host "平台工程已准备完成。" -ForegroundColor Green
