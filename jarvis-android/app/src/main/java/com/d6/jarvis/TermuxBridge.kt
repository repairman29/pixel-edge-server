package com.d6.jarvis

import android.content.Context
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.BufferedReader
import java.io.InputStreamReader

/**
 * Bridge to execute commands on Android/Termux.
 * Uses direct shell execution since Termux SSH isn't available.
 */
class TermuxBridge(private val context: Context) {

    companion object {
        private const val TAG = "TermuxBridge"
        private const val MAX_OUTPUT_LENGTH = 2000
    }

    /**
     * Execute a shell command via ADB/system
     */
    suspend fun executeShell(command: String): String = withContext(Dispatchers.IO) {
        try {
            // Use sh -c to support pipes and shell operators
            val process = Runtime.getRuntime().exec(arrayOf("sh", "-c", command))
            
            val output = BufferedReader(InputStreamReader(process.inputStream)).use { reader ->
                reader.readText()
            }
            
            val error = BufferedReader(InputStreamReader(process.errorStream)).use { reader ->
                reader.readText()
            }
            
            process.waitFor()
            
            when {
                output.isNotEmpty() -> output.take(MAX_OUTPUT_LENGTH)
                error.isNotEmpty() -> "Error: ${error.take(MAX_OUTPUT_LENGTH)}"
                else -> "Command executed (no output)"
            }
        } catch (e: Exception) {
            Log.e(TAG, "Shell execution failed", e)
            "Error: ${e.message}"
        }
    }

    suspend fun listDirectory(path: String): String {
        return try {
            // Handle Android storage paths better
            val resolvedPath = when {
                path == "/sdcard" -> "/storage/emulated/0"
                path.startsWith("/sdcard/") -> path.replace("/sdcard/", "/storage/emulated/0/")
                else -> path
            }
            val result = executeShell("ls -la '$resolvedPath' 2>&1")
            if (result.contains("No such file") || result.contains("Permission denied")) {
                "Directory not accessible: $path\n(try: /storage/emulated/0 for SD card)"
            } else {
                result
            }
        } catch (e: Exception) {
            "Error listing directory: ${e.message}"
        }
    }

    suspend fun getSystemInfo(): String {
        return try {
            val deviceModel = executeShell("getprop ro.product.model").trim()
            val androidVersion = executeShell("getprop ro.build.version.release").trim()
            val storageInfo = executeShell("df /data 2>&1 | tail -1").trim()
            val memTotal = executeShell("cat /proc/meminfo | grep MemTotal").trim()
            val memAvailable = executeShell("cat /proc/meminfo | grep MemAvailable").trim()
            
            buildString {
                appendLine("📱 Device: $deviceModel")
                appendLine("� Android: $androidVersion")
                appendLine()
                appendLine("💾 Storage:")
                appendLine("   $storageInfo")
                appendLine()
                appendLine("🧠 Memory:")
                appendLine("   $memTotal")
                appendLine("   $memAvailable")
            }
        } catch (e: Exception) {
            "Error getting system info: ${e.message}"
        }
    }

    suspend fun ping(host: String): String {
        val safeHost = host.replace(Regex("[^a-zA-Z0-9.-]"), "")
        return try {
            executeShell("ping -c 2 $safeHost 2>&1 | tail -10")
        } catch (e: Exception) {
            "Ping failed: ${e.message}"
        }
    }

    suspend fun executePython(code: String): String {
        return "Python execution not available without Termux bridge"
    }

    suspend fun readFile(path: String): String {
        return try {
            executeShell("cat '$path' 2>&1 | head -50 || echo 'File not found'")
        } catch (e: Exception) {
            "Error reading file: ${e.message}"
        }
    }

    suspend fun getDeviceInfo(): String {
        return getSystemInfo()
    }

    // Fallback method for direct ADB
    suspend fun adbShell(command: String): String {
        return executeShell(command)
    }
}