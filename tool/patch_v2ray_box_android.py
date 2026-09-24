from pathlib import Path

p = Path("third_party/v2box/android/src/main/kotlin/com/example/v2ray_box/V2rayBoxPlugin.kt")
s = p.read_text(encoding="utf-8")

old = (
    "    private fun startService() {\n"
    "        if (!checkNotificationPermission()) {\n"
    "            grantNotificationPermission()\n"
    "            return\n"
    "        }\n"
    "        scope.launch(Dispatchers.IO) {\n"
)

new = (
    "    private fun startService() {\n"
    "        // Android 13+ notification permission is not required to start a VPN foreground service.\n"
    "        // Do not block the VPN consent flow behind POST_NOTIFICATIONS.\n"
    "        scope.launch(Dispatchers.IO) {\n"
)

if old not in s:
    raise SystemExit("v2ray_box startService permission gate pattern not found")

p.write_text(s.replace(old, new, 1), encoding="utf-8")
print("Patched v2ray_box Android startService permission gate.")
