from pathlib import Path
import re, sys, shutil

root = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parents[1]

# Android manifest
manifest = root / 'android/app/src/main/AndroidManifest.xml'
template = root / 'platform_templates/android/AndroidManifest.xml'
if manifest.exists():
    manifest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(template, manifest)

# Android MainActivity (explicit VPN permission bridge)
main_activity = root / 'android/app/src/main/kotlin/com/aurumproxy/aurum_proxy/MainActivity.kt'
main_activity_template = root / 'platform_templates/android/MainActivity.kt'
if main_activity_template.exists():
    main_activity.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(main_activity_template, main_activity)

# Android Gradle (Kotlin DSL current Flutter template)
kts = root / 'android/app/build.gradle.kts'
if kts.exists():
    s = kts.read_text()
    s = re.sub(r'minSdk\s*=\s*flutter\.minSdkVersion', 'minSdk = 24', s)
    if 'multiDexEnabled = true' not in s:
        s = s.replace('defaultConfig {', 'defaultConfig {\n        multiDexEnabled = true', 1)
    if 'implementation(fileTree' not in s:
        s += '\n\ndependencies {\n    implementation(fileTree(mapOf("dir" to "libs", "include" to listOf("*.aar"))))\n}\n'
    kts.write_text(s)

# Android Gradle (older Groovy template)
groovy = root / 'android/app/build.gradle'
if groovy.exists():
    s = groovy.read_text()
    s = re.sub(r'minSdkVersion\s+flutter\.minSdkVersion', 'minSdkVersion 24', s)
    if 'multiDexEnabled true' not in s:
        s = s.replace('defaultConfig {', 'defaultConfig {\n        multiDexEnabled true', 1)
    if "implementation fileTree(dir: 'libs'" not in s:
        s += "\n\ndependencies {\n    implementation fileTree(dir: 'libs', include: ['*.aar'])\n}\n"
    groovy.write_text(s)

# iOS camera permission and minimum target hints
plist = root / 'ios/Runner/Info.plist'
if plist.exists():
    s = plist.read_text()
    if 'NSCameraUsageDescription' not in s:
        s = s.replace('</dict>', '\t<key>NSCameraUsageDescription</key>\n\t<string>用于扫描代理节点和订阅二维码</string>\n</dict>')
    plist.write_text(s)

podfile = root / 'ios/Podfile'
if podfile.exists():
    s = podfile.read_text()
    if re.search(r"platform :ios, ['\"]\d+(?:\.\d+)?['\"]", s):
        s = re.sub(r"platform :ios, ['\"]\d+(?:\.\d+)?['\"]", "platform :ios, '15.0'", s)
    elif "platform :ios, '15.0'" not in s:
        s = "platform :ios, '15.0'\n" + s
    podfile.write_text(s)

print('Platform patches applied.')
