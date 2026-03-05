package com.d6.jarvis

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.Environment
import android.os.StatFs
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.io.IOException

class ToolManager(private val context: Context) {

    companion object {
        private const val TAG = "ToolManager"
    }

    // Device info
    fun getDeviceInfo(): String {
        val batteryManager = context.getSystemService(Context.BATTERY_SERVICE) as BatteryManager
        val batteryLevel = batteryManager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
        
        val stat = StatFs(Environment.getDataDirectory().path)
        val totalSpace = stat.totalBytes / (1024.0 * 1024 * 1024)
        val freeSpace = stat.availableBytes / (1024.0 * 1024 * 1024)
        
        return """Device: ${Build.MANUFACTURER} ${Build.MODEL}
Android: ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})
Battery: ${batteryLevel}%
Storage: ${String.format("%.1f", freeSpace)}GB free / ${String.format("%.1f", totalSpace)}GB total""".trimIndent()
    }

    // App launcher
    fun launchApp(packageName: String): String {
        return try {
            val intent = context.packageManager.getLaunchIntentForPackage(packageName)
            if (intent != null) {
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(intent)
                "Launched $packageName"
            } else {
                "App not found: $packageName"
            }
        } catch (e: Exception) {
            "Failed to launch: ${e.message}"
        }
    }

    // File listing
    fun listFiles(path: String = Environment.getExternalStorageDirectory().path): String {
        return try {
            val file = File(path)
            if (!file.exists()) return "Path not found"
            val files = file.listFiles() ?: return "No files"
            files.take(50).joinToString("\n") { 
                val icon = if (it.isDirectory) "D" else "F"
                "$icon ${it.name}"
            }
        } catch (e: Exception) {
            "Error: ${e.message}"
        }
    }

    // HTTP GET
    suspend fun httpGet(url: String): String = withContext(Dispatchers.IO) {
        try {
            val client = OkHttpClient()
            val request = Request.Builder().url(url).build()
            val response = client.newCall(request).execute()
            if (response.isSuccessful) {
                response.body?.string()?.take(1000) ?: "No content"
            } else {
                "HTTP ${response.code}"
            }
        } catch (e: Exception) {
            "Error: ${e.message}"
        }
    }

    // Simple calculator
    fun quickCalc(expression: String): String {
        return try {
            val cleanExpr = expression.replace(Regex("\\s+"), "")
            val result = when {
                cleanExpr.contains("+") -> {
                    val parts = cleanExpr.split("+")
                    parts[0].toDouble() + parts[1].toDouble()
                }
                cleanExpr.contains("-") -> {
                    val parts = cleanExpr.split("-")
                    parts[0].toDouble() - parts[1].toDouble()
                }
                cleanExpr.contains("*") -> {
                    val parts = cleanExpr.split("*")
                    parts[0].toDouble() * parts[1].toDouble()
                }
                cleanExpr.contains("/") -> {
                    val parts = cleanExpr.split("/")
                    parts[0].toDouble() / parts[1].toDouble()
                }
                else -> cleanExpr.toDouble()
            }
            "Result: $result"
        } catch (e: Exception) {
            "Invalid expression"
        }
    }

    // Tool dispatcher
    suspend fun executeTool(toolName: String, args: Map<String, String>): String {
        Log.d(TAG, "Executing: $toolName")
        return when (toolName) {
            "device_info" -> getDeviceInfo()
            "launch_app" -> launchApp(args["package"] ?: "")
            "list_files" -> listFiles(args["path"] ?: Environment.getExternalStorageDirectory().path)
            "http_get" -> httpGet(args["url"] ?: "")
            "quick_calc" -> quickCalc(args["expression"] ?: "")
            else -> "Unknown tool"
        }
    }
}