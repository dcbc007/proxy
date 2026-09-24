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


# Improve sing-box startup diagnostics so failures are visible inside Aurum logs.
sp = Path("third_party/v2box/android/src/main/kotlin/com/example/v2ray_box/utils/SingboxProcess.kt")
ss = sp.read_text(encoding="utf-8")

if "var lastError: String = \"\"" not in ss:
    ss = ss.replace(
        "    private var process: Process? = null\n",
        "    private var process: Process? = null\n"
        "    @Volatile var lastError: String = \"\"\n"
        "        private set\n"
    )

ss = ss.replace(
    '''    fun getBinaryPath(context: Context): String? {
        val nativeLibDir = context.applicationInfo.nativeLibraryDir
        val binary = File(nativeLibDir, "libsingbox.so")
        if (binary.exists() && binary.canExecute()) {
            return binary.absolutePath
        }
        Log.w(TAG, "sing-box binary not found at: ${binary.absolutePath}")
        return null
    }
''',
    '''    fun getBinaryPath(context: Context): String? {
        val nativeLibDir = context.applicationInfo.nativeLibraryDir
        val binary = File(nativeLibDir, "libsingbox.so")
        if (!binary.exists()) {
            lastError = "binary missing: ${binary.absolutePath}"
            Log.e(TAG, lastError)
            return null
        }
        if (!binary.canExecute()) {
            runCatching { binary.setExecutable(true, false) }
        }
        if (!binary.canExecute()) {
            lastError = "binary is not executable: ${binary.absolutePath}"
            Log.e(TAG, lastError)
            return null
        }
        return binary.absolutePath
    }
'''
)

ss = ss.replace(
    '''    fun start(context: Context, configPath: String): Boolean {
        if (isRunning || isProcessAlive) {
''',
    '''    fun start(context: Context, configPath: String): Boolean {
        lastError = ""
        if (isRunning || isProcessAlive) {
'''
)


ss = ss.replace(
    '''            val workDir = context.getExternalFilesDir(null) ?: context.filesDir
            Log.d(TAG, "Starting sing-box: $binaryPath run -c $configPath -D ${workDir.absolutePath}")

            val pb = ProcessBuilder(binaryPath, "run", "-c", configPath, "-D", workDir.absolutePath)
''',
    '''            val workDir = context.getExternalFilesDir(null) ?: context.filesDir

            // Validate the generated config before starting the long-running
            // process. This surfaces the actual sing-box schema/parser error
            // instead of only returning a generic exit code 1.
            val checkProc = ProcessBuilder(binaryPath, "check", "-c", configPath)
                .directory(workDir)
                .redirectErrorStream(true)
                .start()
            val checkOutput = checkProc.inputStream.bufferedReader().readText().trim()
            val checkExit = checkProc.waitFor()
            if (checkExit != 0) {
                lastError = "config check failed (code=$checkExit): " +
                    checkOutput.takeLast(2000)
                Log.e(TAG, lastError)
                return false
            }

            Log.d(TAG, "Starting sing-box: $binaryPath run -c $configPath -D ${workDir.absolutePath}")

            val pb = ProcessBuilder(binaryPath, "run", "-c", configPath, "-D", workDir.absolutePath)
'''
)

ss = ss.replace(
    '''            if (proc.isAlive) {
                Log.d(TAG, "sing-box started successfully")
                true
            } else {
                Log.e(TAG, "sing-box process died immediately")
                isRunning = false
                process = null
                false
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start sing-box", e)
            isRunning = false
            process = null
            false
        }
''',
    '''            if (proc.isAlive) {
                Log.d(TAG, "sing-box started successfully")
                true
            } else {
                val exitCode = runCatching { proc.exitValue() }.getOrDefault(-1)
                lastError = "process exited immediately (code=$exitCode)"
                Log.e(TAG, "sing-box process died immediately, exit=$exitCode")
                isRunning = false
                process = null
                false
            }
        } catch (e: Exception) {
            lastError = "${e.javaClass.simpleName}: ${e.message ?: "unknown error"}"
            Log.e(TAG, "Failed to start sing-box: $lastError", e)
            isRunning = false
            process = null
            false
        }
'''
)

sp.write_text(ss, encoding="utf-8")

bp = Path("third_party/v2box/android/src/main/kotlin/com/example/v2ray_box/bg/BoxService.kt")
bs = bp.read_text(encoding="utf-8")
bs = bs.replace(
    '''            emitServiceLog("sing-box start failed", force = true)
            stopAndAlert(Alert.StartService, "Failed to start sing-box process")
''',
    '''            val detail = SingboxProcess.lastError.ifBlank { "unknown startup error" }
            emitServiceLog("sing-box start failed: $detail", force = true)
            stopAndAlert(Alert.StartService, "Failed to start sing-box process: $detail")
'''
)
bp.write_text(bs, encoding="utf-8")
print("Patched sing-box startup diagnostics.")


# Fix connectWithJson() in sing-box VPN mode.
# Upstream writes raw JSON to active_config.json. BoxService later reuses
# active_config.json as the Xray TUN bridge config, so it accidentally feeds
# sing-box JSON (mixed inbound/listen_port) into Xray. Store sing-box JSON in
# singbox_config.json and generate the real Xray bridge separately.
bp = Path("third_party/v2box/android/src/main/kotlin/com/example/v2ray_box/bg/BoxService.kt")
bs = bp.read_text(encoding="utf-8")
old_json_writer = '''        fun writeJsonConfigFile(context: Context, configJson: String): String {
            val wDir = getWorkingDir(context)
            val configFile = File(wDir, "active_config.json")
            configFile.writeText(configJson)
            Log.d(TAG, "JSON config written to: ${configFile.absolutePath}")
            return configFile.absolutePath
        }
'''
new_json_writer = '''        fun writeJsonConfigFile(context: Context, configJson: String): String {
            val wDir = getWorkingDir(context)

            if (Settings.coreEngine == CoreEngine.SINGBOX) {
                val singboxFile = File(wDir, "singbox_config.json")
                singboxFile.writeText(configJson)
                Log.d(TAG, "Sing-box JSON config written to: ${singboxFile.absolutePath}")

                if (Settings.serviceMode == ServiceMode.VPN) {
                    val bridgeConfig = buildXrayTunBridge(context)
                    val bridgeFile = File(wDir, "active_config.json")
                    bridgeFile.writeText(bridgeConfig)
                    Log.d(TAG, "Xray TUN bridge config written for raw sing-box JSON")
                }

                return singboxFile.absolutePath
            }

            val configFile = File(wDir, "active_config.json")
            configFile.writeText(configJson)
            Log.d(TAG, "Xray JSON config written to: ${configFile.absolutePath}")
            return configFile.absolutePath
        }
'''
if old_json_writer not in bs:
    raise SystemExit("BoxService.writeJsonConfigFile pattern not found")
bs = bs.replace(old_json_writer, new_json_writer, 1)
bp.write_text(bs, encoding="utf-8")
print("Patched raw sing-box JSON VPN bridge separation.")


# Make status events independent of Activity lifecycle.
# Some OEMs temporarily detach/null the Flutter Activity around the system VPN
# consent flow. Upstream only emitted status events through
# activity?.runOnUiThread, so a final Started event could be lost even though
# the native service was connected. Emit through the main looper directly.
vp = Path("third_party/v2box/android/src/main/kotlin/com/example/v2ray_box/V2rayBoxPlugin.kt")
vs = vp.read_text(encoding="utf-8")

old_observer = '''        serviceStatus.observeForever { status ->
            activity?.runOnUiThread {
                statusEventSink?.success(mapOf("status" to status.name))
            }
'''
new_observer = '''        serviceStatus.observeForever { status ->
            android.os.Handler(android.os.Looper.getMainLooper()).post {
                statusEventSink?.success(mapOf("status" to status.name))
            }
'''
if old_observer not in vs:
    raise SystemExit("V2rayBoxPlugin serviceStatus observer pattern not found")
vs = vs.replace(old_observer, new_observer, 1)

old_callback = '''    override fun onServiceStatusChanged(status: Status) {
        serviceStatus.postValue(status)
    }
'''
new_callback = '''    override fun onServiceStatusChanged(status: Status) {
        serviceStatus.postValue(status)
        android.os.Handler(android.os.Looper.getMainLooper()).post {
            statusEventSink?.success(mapOf("status" to status.name))
        }
    }
'''
if old_callback not in vs:
    raise SystemExit("V2rayBoxPlugin onServiceStatusChanged pattern not found")
vs = vs.replace(old_callback, new_callback, 1)

vp.write_text(vs, encoding="utf-8")
print("Patched VPN status event delivery independent of Activity lifecycle.")

# buildConfig is used by generate_config. The Android child process must not
# create a privileged TUN: VpnService and the Xray bridge own that descriptor.
bs = bp.read_text(encoding='utf-8')
needle = 'SingboxConfigParser.buildSingboxConfig(configLink, !proxyOnly)'
if needle not in bs:
    raise SystemExit('generate_config sing-box TUN pattern not found')
bs = bs.replace(needle, 'SingboxConfigParser.buildSingboxConfig(configLink, false)', 1)
bp.write_text(bs, encoding='utf-8')

# Preserve the real stderr tail on startup failure; a valid schema can still
# fail at runtime (TUN permission, port collision, DNS, etc.).
ss = sp.read_text(encoding='utf-8')
ss = ss.replace('    private var process: Process? = null', '''    private val recentOutput = java.util.ArrayDeque<String>()
    private var process: Process? = null''', 1)
ss = ss.replace('        lastError = ""', '''        lastError = ""
        synchronized(recentOutput) { recentOutput.clear() }''', 1)
ss = ss.replace('                        Log.i("SingboxCore", line)', '''                        synchronized(recentOutput) {
                            if (recentOutput.size >= 12) recentOutput.removeFirst()
                            recentOutput.addLast(line.take(500))
                        }
                        Log.i("SingboxCore", line)''', 1)
ss = ss.replace('lastError = "process exited immediately (code=$exitCode)"', '''lastError = "process exited immediately (code=$exitCode): " +
                    synchronized(recentOutput) { recentOutput.joinToString(" | ").takeLast(2000) }''', 1)
# A dying old process must not clear the state of a newly started process.
ss = ss.replace('''                    isRunning = false
                    if (process == proc) {
                        process = null
                    }''', '''                    if (process == proc) {
                        isRunning = false
                        process = null
                    }''', 1)
sp.write_text(ss, encoding='utf-8')
print('Patched Android TUN ownership and runtime stderr diagnostics.')
