package com.aurumproxy.aurum_proxy

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.InetAddress
import java.net.ServerSocket
import java.net.URL
import java.net.URLEncoder
import java.util.concurrent.TimeUnit

/** Real HTTP delay through the selected outbound, never a direct-network fallback. */
object NodeLatencyProbe {
    fun measure(context: Context, config: String?, tag: String): Int {
        var process: Process? = null
        var directory: File? = null
        try {
            var port = 9090
            if (config != null) {
                port = ServerSocket(0, 1, InetAddress.getByName("127.0.0.1")).use { it.localPort }
                directory = File(context.cacheDir, "latency-${java.util.UUID.randomUUID()}").apply { mkdirs() }
                val root = JSONObject(config)
                root.put("inbounds", JSONArray())
                root.put("experimental", JSONObject().put("clash_api",
                    JSONObject().put("external_controller", "127.0.0.1:$port")))
                val configFile = File(directory, "config.json").apply { writeText(root.toString()) }
                val binary = File(context.applicationInfo.nativeLibraryDir, "libsingbox.so")
                process = ProcessBuilder(binary.absolutePath, "run", "-c", configFile.absolutePath,
                    "-D", directory.absolutePath).redirectErrorStream(true)
                    .redirectOutput(File(directory, "core.log")).start()
                val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(4)
                var ready = false
                while (System.nanoTime() < deadline && process.isAlive) {
                    try {
                        get("http://127.0.0.1:$port/version", 250)
                        ready = true
                        break
                    } catch (_: Exception) { Thread.sleep(60) }
                }
                if (!ready) return -1
            }
            // The Clash delay endpoint dials the named outbound explicitly,
            // including in direct mode and when our app UID bypasses the VPN.
            val target = URLEncoder.encode("https://www.gstatic.com/generate_204", "UTF-8")
            val name = URLEncoder.encode(tag, "UTF-8").replace("+", "%20")
            val reply = get("http://127.0.0.1:$port/proxies/$name/delay?timeout=6000&url=$target", 6500)
            val delay = JSONObject(reply).optInt("delay", -1)
            return if (delay >= 0) delay.coerceAtLeast(1) else -1
        } catch (_: Exception) {
            return -1
        } finally {
            process?.let {
                it.destroy()
                if (!it.waitFor(500, TimeUnit.MILLISECONDS)) {
                    it.destroyForcibly()
                    it.waitFor(500, TimeUnit.MILLISECONDS)
                }
            }
            directory?.deleteRecursively()
        }
    }

    private fun get(url: String, timeout: Int): String {
        val connection = URL(url).openConnection(java.net.Proxy.NO_PROXY) as HttpURLConnection
        try {
            connection.connectTimeout = timeout.coerceAtMost(1000)
            connection.readTimeout = timeout
            connection.useCaches = false
            if (connection.responseCode != 200) throw java.io.IOException("Probe failed")
            return connection.inputStream.bufferedReader().use { it.readText() }
        } finally { connection.disconnect() }
    }
}
