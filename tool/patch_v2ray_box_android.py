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


# Make Android's Xray TUN bridge honor the same Smart / Global / Direct mode
# as the sing-box child process. Previously the bridge always forwarded almost
# everything to 127.0.0.1:10808, so Smart mode could still behave like Global.
bp = Path("third_party/v2box/android/src/main/kotlin/com/example/v2ray_box/bg/BoxService.kt")
bs = bp.read_text(encoding="utf-8")

old_writer = '''                if (Settings.serviceMode == ServiceMode.VPN) {
                    val bridgeConfig = buildXrayTunBridge(context)
                    val bridgeFile = File(wDir, "active_config.json")
                    bridgeFile.writeText(bridgeConfig)
                    Log.d(TAG, "Xray TUN bridge config written for raw sing-box JSON")
                }
'''
new_writer = '''                if (Settings.serviceMode == ServiceMode.VPN) {
                    val routingMode = inferRoutingModeFromSingboxConfig(configJson)
                    val bridgeConfig = buildXrayTunBridge(context, routingMode)
                    val bridgeFile = File(wDir, "active_config.json")
                    bridgeFile.writeText(bridgeConfig)
                    Log.d(TAG, "Xray TUN bridge config written for raw sing-box JSON, routeMode=$routingMode")
                }
'''
if old_writer not in bs:
    raise SystemExit("raw sing-box bridge writer pattern not found")
bs = bs.replace(old_writer, new_writer, 1)

old_bridge = '''        private fun buildXrayTunBridge(context: Context): String {
            val tunSettings = mutableMapOf<String, Any>(
                "name" to "xray0",
                "MTU" to 1500,
                "userLevel" to 8
            )
'''
new_bridge = '''        private fun inferRoutingModeFromSingboxConfig(configJson: String): String {
            return runCatching {
                val root = com.google.gson.JsonParser.parseString(configJson).asJsonObject
                val route = root.getAsJsonObject("route")
                val finalTag = route?.get("final")?.asString ?: ""
                if (finalTag == "direct") {
                    "DIRECT"
                } else {
                    val routeText = route?.toString().orEmpty()
                    if (routeText.contains("\\"geosite-cn\\"") &&
                        routeText.contains("\\"geoip-cn\\"")) {
                        "SMART"
                    } else {
                        "GLOBAL"
                    }
                }
            }.getOrElse {
                Log.w(TAG, "Unable to infer sing-box routing mode: ${it.message}")
                "GLOBAL"
            }
        }

        private fun buildXrayTunBridge(
            context: Context,
            routingMode: String = "GLOBAL"
        ): String {
            val tunSettings = mutableMapOf<String, Any>(
                "name" to "xray0",
                "MTU" to 1500,
                "userLevel" to 8
            )
'''
if old_bridge not in bs:
    raise SystemExit("buildXrayTunBridge signature pattern not found")
bs = bs.replace(old_bridge, new_bridge, 1)

old_config = '''            val config = mapOf(
                "log" to mapOf("loglevel" to if (Settings.debugMode) "debug" else "warning"),
                "inbounds" to listOf(
                    mapOf(
                        "tag" to "tun",
                        "port" to 0,
                        "protocol" to "tun",
                        "settings" to tunSettings,
                        "sniffing" to mapOf(
                            "enabled" to true,
                            "destOverride" to listOf("http", "tls")
                        )
                    )
                ),
                "outbounds" to listOf(
                    mapOf(
                        "tag" to "proxy",
                        "protocol" to "socks",
                        "settings" to mapOf(
                            "servers" to listOf(
                                mapOf(
                                    "address" to "127.0.0.1",
                                    "port" to 10808
                                )
                            )
                        )
                    ),
                    mapOf(
                        "tag" to "direct",
                        "protocol" to "freedom",
                        "settings" to mapOf("domainStrategy" to "UseIP")
                    )
                ),
                "routing" to mapOf(
                    "domainStrategy" to "AsIs",
                    "rules" to listOf(
                        mapOf(
                            "type" to "field",
                            "outboundTag" to "direct",
                            "ip" to listOf(
                                "10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16",
                                "127.0.0.0/8", "fc00::/7", "fe80::/10", "::1/128"
                            )
                        )
                    )
                ),
                "policy" to mapOf(
'''
new_config = '''            val routingRules = mutableListOf<Map<String, Any>>()
            when (routingMode) {
                "DIRECT" -> {
                    routingRules.add(
                        mapOf(
                            "type" to "field",
                            "network" to "tcp,udp",
                            "outboundTag" to "direct"
                        )
                    )
                }
                "SMART" -> {
                    routingRules.add(
                        mapOf(
                            "type" to "field",
                            "ip" to listOf("geoip:private"),
                            "outboundTag" to "direct"
                        )
                    )
                    routingRules.add(
                        mapOf(
                            "type" to "field",
                            "port" to "53",
                            "outboundTag" to "direct"
                        )
                    )
                    routingRules.add(
                        mapOf(
                            "type" to "field",
                            "domain" to listOf("geosite:cn"),
                            "outboundTag" to "direct"
                        )
                    )
                    routingRules.add(
                        mapOf(
                            "type" to "field",
                            "ip" to listOf("geoip:cn"),
                            "outboundTag" to "direct"
                        )
                    )
                    routingRules.add(
                        mapOf(
                            "type" to "field",
                            "network" to "tcp,udp",
                            "outboundTag" to "proxy"
                        )
                    )
                }
                else -> {
                    routingRules.add(
                        mapOf(
                            "type" to "field",
                            "network" to "tcp,udp",
                            "outboundTag" to "proxy"
                        )
                    )
                }
            }

            Log.d(TAG, "Xray TUN bridge routing mode=$routingMode rules=${routingRules.size}")

            val config = mapOf(
                "log" to mapOf("loglevel" to if (Settings.debugMode) "debug" else "warning"),
                "inbounds" to listOf(
                    mapOf(
                        "tag" to "tun",
                        "port" to 0,
                        "protocol" to "tun",
                        "settings" to tunSettings,
                        "sniffing" to mapOf(
                            "enabled" to true,
                            "destOverride" to listOf("http", "tls", "quic")
                        )
                    )
                ),
                "outbounds" to listOf(
                    mapOf(
                        "tag" to "proxy",
                        "protocol" to "socks",
                        "settings" to mapOf(
                            "servers" to listOf(
                                mapOf(
                                    "address" to "127.0.0.1",
                                    "port" to 10808
                                )
                            )
                        )
                    ),
                    mapOf(
                        "tag" to "direct",
                        "protocol" to "freedom",
                        "settings" to mapOf("domainStrategy" to "UseIP")
                    )
                ),
                "routing" to mapOf(
                    "domainStrategy" to "IPIfNonMatch",
                    "domainMatcher" to "hybrid",
                    "rules" to routingRules
                ),
                "policy" to mapOf(
'''
if old_config not in bs:
    raise SystemExit("Xray bridge config routing block not found")
bs = bs.replace(old_config, new_config, 1)

bp.write_text(bs, encoding="utf-8")
print("Patched Android Xray TUN bridge routing modes.")



# Optimize Smart/Direct mode latency: use the underlying Android network DNS
# instead of pinning all Xray DNS lookups to 1.1.1.1, and avoid IPIfNonMatch
# re-resolution in the TUN bridge. Also clear stale DNS overrides when switching.
bp = Path("third_party/v2box/android/src/main/kotlin/com/example/v2ray_box/bg/BoxService.kt")
bs = bp.read_text(encoding="utf-8")

bridge_sig = '''        private fun buildXrayTunBridge(
            context: Context,
            routingMode: String = "GLOBAL"
        ): String {
'''
helpers = '''        private fun inferRoutingModeFromXrayConfig(configJson: String): String {
            return runCatching {
                val root = com.google.gson.JsonParser.parseString(configJson).asJsonObject
                val routing = root.getAsJsonObject("routing")
                val rules = routing?.getAsJsonArray("rules")
                val text = rules?.toString().orEmpty()
                if (text.contains("geosite:cn") || text.contains("geoip:cn")) {
                    "SMART"
                } else {
                    val last = rules?.lastOrNull()?.asJsonObject
                    when (last?.get("outboundTag")?.asString) {
                        "direct" -> "DIRECT"
                        else -> "GLOBAL"
                    }
                }
            }.getOrElse {
                Log.w(TAG, "Unable to infer Xray routing mode: ${it.message}")
                "GLOBAL"
            }
        }

        private fun underlyingDnsServer(context: Context): String? {
            return runCatching {
                val cm = V2rayBoxPlugin.connectivity
                    ?: context.getSystemService(android.net.ConnectivityManager::class.java)
                val network = DefaultNetworkMonitor.defaultNetwork ?: cm.activeNetwork
                val props = network?.let { cm.getLinkProperties(it) }
                val address = props?.dnsServers?.firstOrNull {
                    !it.isLoopbackAddress && !it.isAnyLocalAddress
                } ?: return@runCatching null
                val host = address.hostAddress?.substringBefore('%')
                    ?.takeIf { it.isNotBlank() } ?: return@runCatching null
                if (address is java.net.Inet6Address) "[$host]:53" else "$host:53"
            }.getOrNull()
        }

        private fun dnsServerForRoutingMode(context: Context, routingMode: String): String? {
            if (routingMode == "GLOBAL") return XRAY_DNS_SERVER
            val systemDns = underlyingDnsServer(context)
            Log.d(TAG, "Using underlying DNS for $routingMode: ${systemDns ?: "system/default"}")
            return systemDns
        }

        private fun buildXrayTunBridge(
            context: Context,
            routingMode: String = "GLOBAL"
        ): String {
'''
if bridge_sig not in bs:
    raise SystemExit("1.1.6 bridge signature pattern not found")
bs = bs.replace(bridge_sig, helpers, 1)

bs = bs.replace(
    '''"settings" to mapOf("domainStrategy" to "UseIP")''',
    '''"settings" to mapOf("domainStrategy" to "AsIs")''',
    1
)
bs = bs.replace(
    '''"domainStrategy" to "IPIfNonMatch",
                    "domainMatcher" to "hybrid",''',
    '''"domainStrategy" to "AsIs",
                    "domainMatcher" to "hybrid",''',
    1
)
bs = bs.replace(
    '''"destOverride" to listOf("http", "tls", "quic")
                        )''',
    '''"destOverride" to listOf("http", "tls", "quic"),
                            "routeOnly" to true
                        )''',
    1
)

old_xray_dns = '''            XrayBridge.configureSocketProtection(
                    protectFd = { fd -> platformInterface.autoDetectInterfaceControl(fd) },
                    dnsServer = XRAY_DNS_SERVER
                )
'''
new_xray_dns = '''            val routingMode = inferRoutingModeFromXrayConfig(content)
            val dnsServer = dnsServerForRoutingMode(service, routingMode)
            emitServiceLog("Xray routing=$routingMode dns=${dnsServer ?: "system/default"}", force = true)
            XrayBridge.configureSocketProtection(
                    protectFd = { fd -> platformInterface.autoDetectInterfaceControl(fd) },
                    dnsServer = dnsServer
                )
'''
if old_xray_dns not in bs:
    raise SystemExit("Xray configureSocketProtection DNS pattern not found")
bs = bs.replace(old_xray_dns, new_xray_dns, 1)

old_bridge_dns = '''                XrayBridge.configureSocketProtection(
                    protectFd = { fd -> platformInterface.autoDetectInterfaceControl(fd) },
                    dnsServer = XRAY_DNS_SERVER
                )
                val controller = XrayBridge.newCoreController(this)
'''
new_bridge_dns = '''                val bridgeRoutingMode = inferRoutingModeFromXrayConfig(bridgeContent)
                val bridgeDnsServer = dnsServerForRoutingMode(service, bridgeRoutingMode)
                emitServiceLog(
                    "TUN bridge routing=$bridgeRoutingMode dns=${bridgeDnsServer ?: "system/default"}",
                    force = true
                )
                XrayBridge.configureSocketProtection(
                    protectFd = { fd -> platformInterface.autoDetectInterfaceControl(fd) },
                    dnsServer = bridgeDnsServer
                )
                val controller = XrayBridge.newCoreController(this)
'''
if old_bridge_dns not in bs:
    raise SystemExit("sing-box bridge configureSocketProtection DNS pattern not found")
bs = bs.replace(old_bridge_dns, new_bridge_dns, 1)

bp.write_text(bs, encoding="utf-8")

xp = Path("third_party/v2box/android/src/main/kotlin/com/example/v2ray_box/xray/XrayBridge.kt")
xs = xp.read_text(encoding="utf-8")
old_dns_hook = '''        if (!dnsServer.isNullOrBlank()) {
            runCatching { LibXray.initDns(controller, dnsServer) }
                .onFailure { Log.w(TAG, "initDns failed: ${it.message}") }
        }
'''
new_dns_hook = '''        // DNS override is process-global inside libXray. Always clear the
        // previous mode's resolver before optionally applying a new one.
        runCatching { LibXray.resetDns() }
            .onFailure { Log.w(TAG, "resetDns before reconfigure failed: ${it.message}") }
        if (!dnsServer.isNullOrBlank()) {
            runCatching { LibXray.initDns(controller, dnsServer) }
                .onFailure { Log.w(TAG, "initDns failed: ${it.message}") }
        }
'''
if old_dns_hook not in xs:
    raise SystemExit("XrayBridge DNS hook pattern not found")
xs = xs.replace(old_dns_hook, new_dns_hook, 1)
xp.write_text(xs, encoding="utf-8")

print("Patched Smart/Direct DNS path and removed duplicate route DNS resolution.")



# Fix the actual Android VPN DNS advertised to apps.
# Upstream hard-codes 1.1.1.1 and 8.8.8.8 into VpnService.Builder, so even
# Smart/Direct traffic first depends on public DNS that can be slow or blocked.
# Capture DNS from the underlying Wi-Fi/mobile network before establishing the
# VPN. Only fall back to China-reachable public resolvers if Android exposes none.
vpns = Path("third_party/v2box/android/src/main/kotlin/com/example/v2ray_box/bg/VPNService.kt")
vns = vpns.read_text(encoding="utf-8")

old_builder = '''        val builder = Builder()
            .setSession("V2Ray Box")
            .setMtu(TUN_MTU)
            .addAddress(TUN_ADDR4, 30)
            .addAddress(TUN_ADDR6, 126)
            .addRoute("0.0.0.0", 0)
            .addRoute("::", 0)
            .addDnsServer("1.1.1.1")
            .addDnsServer("8.8.8.8")
'''

new_builder = '''        val underlyingNetwork =
            DefaultNetworkMonitor.defaultNetwork ?: connectivity.activeNetwork
        val underlyingDns = runCatching {
            underlyingNetwork
                ?.let { connectivity.getLinkProperties(it) }
                ?.dnsServers
                ?.filter { !it.isLoopbackAddress && !it.isAnyLocalAddress }
                ?.distinct()
                .orEmpty()
        }.getOrDefault(emptyList())

        val selectedDns = if (underlyingDns.isNotEmpty()) {
            underlyingDns
        } else {
            listOf(
                java.net.InetAddress.getByName("223.5.5.5"),
                java.net.InetAddress.getByName("119.29.29.29")
            )
        }

        Log.d(
            TAG,
            "VPN DNS from underlying network: " +
                selectedDns.joinToString(",") { it.hostAddress ?: it.toString() }
        )

        val builder = Builder()
            .setSession("V2Ray Box")
            .setMtu(TUN_MTU)
            .addAddress(TUN_ADDR4, 30)
            .addAddress(TUN_ADDR6, 126)
            .addRoute("0.0.0.0", 0)
            .addRoute("::", 0)

        selectedDns.forEach { builder.addDnsServer(it) }
'''
if old_builder not in vns:
    raise SystemExit("VPNService hard-coded DNS builder pattern not found")
vns = vns.replace(old_builder, new_builder, 1)

vpns.write_text(vns, encoding="utf-8")
print("Patched Android VPN DNS to underlying network resolvers.")

# 1.1.8 Smart DNS routing:
# - Direct mode keeps underlying DNS and direct routing.
# - Smart/Global advertise public DNS targets to Android apps, but DNS packets
#   are routed through the proxy path.
bp = Path("third_party/v2box/android/src/main/kotlin/com/example/v2ray_box/bg/BoxService.kt")
bs = bp.read_text(encoding="utf-8")

old_smart_dns = '''                    routingRules.add(
                        mapOf(
                            "type" to "field",
                            "port" to "53",
                            "outboundTag" to "direct"
                        )
                    )
'''
new_smart_dns = '''                    routingRules.add(
                        mapOf(
                            "type" to "field",
                            "port" to "53",
                            "outboundTag" to "proxy"
                        )
                    )
'''
if old_smart_dns not in bs:
    raise SystemExit("SMART DNS direct rule pattern not found")
bs = bs.replace(old_smart_dns, new_smart_dns, 1)

old_dns_mode = '''        private fun dnsServerForRoutingMode(context: Context, routingMode: String): String? {
            if (routingMode == "GLOBAL") return XRAY_DNS_SERVER
            val systemDns = underlyingDnsServer(context)
            Log.d(TAG, "Using underlying DNS for $routingMode: ${systemDns ?: \"system/default\"}")
            return systemDns
        }
'''
new_dns_mode = '''        private fun dnsServerForRoutingMode(context: Context, routingMode: String): String? {
            val systemDns = underlyingDnsServer(context)
            Log.d(TAG, "Core endpoint DNS for $routingMode: ${systemDns ?: \"system/default\"}")
            return systemDns
        }
'''
if old_dns_mode not in bs:
    raise SystemExit("dnsServerForRoutingMode pattern not found")
bs = bs.replace(old_dns_mode, new_dns_mode, 1)
bp.write_text(bs, encoding="utf-8")

vpns = Path("third_party/v2box/android/src/main/kotlin/com/example/v2ray_box/bg/VPNService.kt")
vns = vpns.read_text(encoding="utf-8")

old_selected = '''        val selectedDns = if (underlyingDns.isNotEmpty()) {
            underlyingDns
        } else {
            listOf(
                java.net.InetAddress.getByName("223.5.5.5"),
                java.net.InetAddress.getByName("119.29.29.29")
            )
        }

        Log.d(
            TAG,
            "VPN DNS from underlying network: " +
                selectedDns.joinToString(",") { it.hostAddress ?: it.toString() }
        )
'''
new_selected = '''        val routingMode = runCatching {
            val content = java.io.File(Settings.activeConfigPath).readText()
            val root = com.google.gson.JsonParser.parseString(content).asJsonObject
            val singRoute = root.getAsJsonObject("route")
            if (singRoute != null) {
                val finalTag = singRoute.get("final")?.asString.orEmpty()
                val text = singRoute.toString()
                when {
                    finalTag == "direct" -> "DIRECT"
                    text.contains("geosite-cn") || text.contains("geoip-cn") -> "SMART"
                    else -> "GLOBAL"
                }
            } else {
                val xrayRouting = root.getAsJsonObject("routing")
                val rules = xrayRouting?.getAsJsonArray("rules")
                val text = rules?.toString().orEmpty()
                when {
                    text.contains("geosite:cn") || text.contains("geoip:cn") -> "SMART"
                    rules?.lastOrNull()?.asJsonObject?.get("outboundTag")?.asString == "direct" -> "DIRECT"
                    else -> "GLOBAL"
                }
            }
        }.getOrElse {
            Log.w(TAG, "Unable to infer VPN routing mode for DNS: ${it.message}")
            "GLOBAL"
        }

        val selectedDns = if (routingMode == "DIRECT") {
            if (underlyingDns.isNotEmpty()) {
                underlyingDns
            } else {
                listOf(
                    java.net.InetAddress.getByName("223.5.5.5"),
                    java.net.InetAddress.getByName("119.29.29.29")
                )
            }
        } else {
            listOf(
                java.net.InetAddress.getByName("1.1.1.1"),
                java.net.InetAddress.getByName("8.8.8.8")
            )
        }

        Log.d(
            TAG,
            "VPN DNS mode=$routingMode servers=" +
                selectedDns.joinToString(",") { it.hostAddress ?: it.toString() }
        )
'''
if old_selected not in vns:
    raise SystemExit("VPN selectedDns pattern not found")
vns = vns.replace(old_selected, new_selected, 1)
vpns.write_text(vns, encoding="utf-8")

print("Patched Smart/Global DNS to proxy path; Direct keeps system DNS.")

# 1.1.9 Smart route correctness:
# Restore DNS->IP fallback only for Smart mode so geoip:cn can match domains
# that are absent from geosite:cn. Direct/Global remain AsIs to avoid the
# previous latency regression. Add domain:cn as a deterministic fallback.
bp = Path("third_party/v2box/android/src/main/kotlin/com/example/v2ray_box/bg/BoxService.kt")
bs = bp.read_text(encoding="utf-8")

old_domain_rule = '''                            "domain" to listOf("geosite:cn"),'''
new_domain_rule = '''                            "domain" to listOf("geosite:cn", "domain:cn"),'''
if old_domain_rule not in bs:
    raise SystemExit("SMART geosite domain rule pattern not found")
bs = bs.replace(old_domain_rule, new_domain_rule, 1)

config_anchor = '''            val config = mapOf(
'''
strategy_decl = '''            val routeDomainStrategy =
                if (routingMode == "SMART") "IPIfNonMatch" else "AsIs"

            val config = mapOf(
'''
if config_anchor not in bs:
    raise SystemExit("bridge config anchor not found")
bs = bs.replace(config_anchor, strategy_decl, 1)

old_strategy = '''                    "domainStrategy" to "AsIs",
                    "domainMatcher" to "hybrid",'''
new_strategy = '''                    "domainStrategy" to routeDomainStrategy,
                    "domainMatcher" to "hybrid",'''
if old_strategy not in bs:
    raise SystemExit("bridge AsIs strategy pattern not found")
bs = bs.replace(old_strategy, new_strategy, 1)

bp.write_text(bs, encoding="utf-8")
print("Patched Smart routing with IPIfNonMatch and domain:cn fallback.")

# 1.2.0 single-routing-core architecture.
# Raw sing-box configs use Xray only as a transport bridge.
bp = Path("third_party/v2box/android/src/main/kotlin/com/example/v2ray_box/bg/BoxService.kt")
bs = bp.read_text(encoding="utf-8")

old_writer = '''                if (Settings.serviceMode == ServiceMode.VPN) {
                    val routingMode = inferRoutingModeFromSingboxConfig(configJson)
                    val bridgeConfig = buildXrayTunBridge(context, routingMode)
                    val bridgeFile = File(wDir, "active_config.json")
                    bridgeFile.writeText(bridgeConfig)
                    Log.d(TAG, "Xray TUN bridge config written for raw sing-box JSON, routeMode=$routingMode")
                }
'''
new_writer = '''                if (Settings.serviceMode == ServiceMode.VPN) {
                    val bridgeConfig = buildXrayTunBridge(context, "GLOBAL")
                    val bridgeFile = File(wDir, "active_config.json")
                    bridgeFile.writeText(bridgeConfig)
                    Log.d(TAG, "Xray TUN bridge written in transport-only mode -> sing-box")
                }
'''
if old_writer not in bs:
    raise SystemExit("1.2.0 raw sing-box writer pattern not found")
bs = bs.replace(old_writer, new_writer, 1)

old_sniff = '''                        "sniffing" to mapOf(
                            "enabled" to true,
                            "destOverride" to listOf("http", "tls", "quic"),
                            "routeOnly" to true
                        )
'''
new_sniff = '''                        "sniffing" to mapOf(
                            "enabled" to false
                        )
'''
if old_sniff not in bs:
    raise SystemExit("1.2.0 bridge sniffing block not found")
bs = bs.replace(old_sniff, new_sniff, 1)

old_bridge_dns = '''                val bridgeRoutingMode = inferRoutingModeFromXrayConfig(bridgeContent)
                val bridgeDnsServer = dnsServerForRoutingMode(service, bridgeRoutingMode)
                emitServiceLog(
                    "TUN bridge routing=$bridgeRoutingMode dns=${bridgeDnsServer ?: \"system/default\"}",
                    force = true
                )
                XrayBridge.configureSocketProtection(
                    protectFd = { fd -> platformInterface.autoDetectInterfaceControl(fd) },
                    dnsServer = bridgeDnsServer
                )
'''
new_bridge_dns = '''                emitServiceLog(
                    "TUN bridge transport-only -> 127.0.0.1:10808; sing-box owns routing/DNS",
                    force = true
                )
                XrayBridge.configureSocketProtection(
                    protectFd = { fd -> platformInterface.autoDetectInterfaceControl(fd) },
                    dnsServer = null
                )
'''
if old_bridge_dns not in bs:
    raise SystemExit("1.2.0 bridge DNS block not found")
bs = bs.replace(old_bridge_dns, new_bridge_dns, 1)

bp.write_text(bs, encoding="utf-8")
print("Patched Android TUN bridge to transport-only single-routing-core mode.")

# Remove all dead Smart/Direct branches from the bridge itself. Even if a
# future caller passes another routingMode, the bridge can only forward to
# sing-box; it cannot make routing decisions.
bp = Path("third_party/v2box/android/src/main/kotlin/com/example/v2ray_box/bg/BoxService.kt")
bs = bp.read_text(encoding="utf-8")
start = bs.find('            val routingRules = mutableListOf<Map<String, Any>>()')
end = bs.find('            Log.d(', start)
if start < 0 or end < 0:
    raise SystemExit("1.2.0 routingRules block not found")
simple_rules = '''            val routingRules = listOf(
                mapOf<String, Any>(
                    "type" to "field",
                    "network" to "tcp,udp",
                    "outboundTag" to "proxy"
                )
            )

'''
bs = bs[:start] + simple_rules + bs[end:]
bs = bs.replace(
    '''            val routeDomainStrategy =
                if (routingMode == "SMART") "IPIfNonMatch" else "AsIs"''',
    '''            val routeDomainStrategy = "AsIs"''',
    1,
)
bp.write_text(bs, encoding="utf-8")
print("Removed routing decisions from Android TUN bridge.")
