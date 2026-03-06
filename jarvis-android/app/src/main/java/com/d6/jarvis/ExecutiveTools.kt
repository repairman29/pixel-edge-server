package com.d6.jarvis

import android.content.Context
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.URL

/**
 * Executive Tools - Advanced system access and operations
 * Provides full terminal, file, and process management capabilities
 */
class ExecutiveTools(private val context: Context) {

    companion object {
        private const val TAG = "ExecutiveTools"
        private const val MAX_OUTPUT = 4000
        private const val TERMUX_HOME = "/data/data/com.termux/files/home"
        private const val SD_CARD = "/sdcard"
    }

    // ===================================================================
    // TERMINAL OPERATIONS
    // ===================================================================

    /**
     * Execute any shell command with full environment
     */
    suspend fun executeCommand(cmd: String, workingDir: String? = null): String = withContext(Dispatchers.IO) {
        try {
            val processBuilder = ProcessBuilder("sh", "-c", cmd).apply {
                redirectErrorStream(true)
                workingDir?.let { directory(File(it)) }
                
                // Set up environment
                environment().apply {
                    put("PATH", "/system/bin:/system/xbin:/data/data/com.termux/files/usr/bin:/data/data/com.termux/files/usr/local/bin")
                    put("HOME", TERMUX_HOME)
                    put("TERM", "xterm-256color")
                }
            }
            
            val process = processBuilder.start()
            val output = StringBuilder()
            
            BufferedReader(InputStreamReader(process.inputStream)).use { reader ->
                var line: String?
                while (reader.readLine().also { line = it } != null) {
                    output.appendLine(line)
                    if (output.length > MAX_OUTPUT) {
                        output.appendLine("\n[... output truncated ...]")
                        break
                    }
                }
            }
            
            process.waitFor()
            output.toString().trim().ifEmpty { "Command executed successfully (no output)" }
            
        } catch (e: Exception) {
            Log.e(TAG, "Command execution failed", e)
            "Error: ${e.message}"
        }
    }

    /**
     * Run command with sudo/elevated privileges (if available)
     */
    suspend fun executeElevated(cmd: String): String = withContext(Dispatchers.IO) {
        // Try different privilege escalation methods
        val methods = listOf(
            "su -c \"$cmd\"",
            "tsu -c \"$cmd\"",  // Termux sudo
            "bash -c \"$cmd\""  // Fallback
        )
        
        for (method in methods) {
            val result = executeCommand(method)
            if (!result.startsWith("Error:") && !result.contains("not found")) {
                return@withContext result
            }
        }
        
        "Unable to execute with elevated privileges. Try regular command instead."
    }

    // ===================================================================
    // FILE OPERATIONS
    // ===================================================================

    /**
     * Read file contents
     */
    suspend fun readFile(path: String, lines: Int = 100): String = withContext(Dispatchers.IO) {
        try {
            val resolvedPath = resolvePath(path)
            val file = File(resolvedPath)
            
            when {
                !file.exists() -> "Error: File not found: $path"
                !file.canRead() -> "Error: Permission denied: $path"
                file.isDirectory -> "Error: $path is a directory"
                file.length() > 1024 * 1024 -> "Error: File too large (${file.length() / 1024}KB). Use shell command for large files."
                else -> {
                    file.readLines().take(lines).joinToString("\n")
                }
            }
        } catch (e: Exception) {
            "Error reading file: ${e.message}"
        }
    }

    /**
     * Write content to file
     */
    suspend fun writeFile(path: String, content: String, append: Boolean = false): String = withContext(Dispatchers.IO) {
        try {
            val resolvedPath = resolvePath(path)
            val file = File(resolvedPath)
            
            // Create parent directories if needed
            file.parentFile?.mkdirs()
            
            if (append) {
                file.appendText(content)
                "✓ Appended to $path"
            } else {
                file.writeText(content)
                "✓ Written to $path (${content.length} chars)"
            }
        } catch (e: Exception) {
            "Error writing file: ${e.message}"
        }
    }

    /**
     * List directory contents with details
     */
    suspend fun listDirectory(path: String, showHidden: Boolean = false): String = withContext(Dispatchers.IO) {
        try {
            val resolvedPath = resolvePath(path)
            val file = File(resolvedPath)
            
            when {
                !file.exists() -> "Error: Directory not found: $path"
                !file.isDirectory -> "Error: $path is not a directory"
                !file.canRead() -> executeCommand("ls -la '$resolvedPath' 2>&1")
                else -> {
                    val flags = if (showHidden) "-la" else "-l"
                    executeCommand("ls $flags '$resolvedPath' 2>&1 || ls -la '$resolvedPath' 2>&1")
                }
            }
        } catch (e: Exception) {
            "Error listing directory: ${e.message}"
        }
    }

    /**
     * Search for files
     */
    suspend fun findFiles(pattern: String, path: String = SD_CARD): String = withContext(Dispatchers.IO) {
        executeCommand("find '$path' -name '*$pattern*' -type f 2>/dev/null | head -20")
    }

    // ===================================================================
    // PROCESS MANAGEMENT
    // ===================================================================

    /**
     * List running processes
     */
    suspend fun listProcesses(): String = withContext(Dispatchers.IO) {
        executeCommand("ps -A -o PID,USER,NAME,CMDLINE | head -30")
    }

    /**
     * Kill process by PID
     */
    suspend fun killProcess(pid: String): String = withContext(Dispatchers.IO) {
        executeCommand("kill -9 $pid 2>&1 && echo 'Process $pid terminated' || echo 'Failed to kill process'")
    }

    /**
     * Get process info
     */
    suspend fun processInfo(pid: String): String = withContext(Dispatchers.IO) {
        executeCommand("cat /proc/$pid/status 2>&1 || echo 'Process not found'")
    }

    // ===================================================================
    // SYSTEM INFORMATION
    // ===================================================================

    /**
     * Comprehensive system info
     */
    suspend fun getSystemInfo(): String = withContext(Dispatchers.IO) {
        val sb = StringBuilder()
        
        sb.appendLine("📱 DEVICE INFORMATION")
        sb.appendLine("==================")
        sb.appendLine(executeCommand("getprop ro.product.model").trim())
        sb.appendLine("Android: ${executeCommand("getprop ro.build.version.release").trim()}")
        sb.appendLine("SDK: ${executeCommand("getprop ro.build.version.sdk").trim()}")
        sb.appendLine()
        
        sb.appendLine("💾 STORAGE")
        sb.appendLine("=========")
        sb.appendLine(executeCommand("df -h /data /sdcard 2>&1 | grep -v 'Filesystem'"))
        sb.appendLine()
        
        sb.appendLine("🧠 MEMORY")
        sb.appendLine("========")
        sb.appendLine(executeCommand("cat /proc/meminfo | grep -E 'MemTotal|MemAvailable|MemFree|Buffers|Cached'"))
        sb.appendLine()
        
        sb.appendLine("⚡ CPU")
        sb.appendLine("====")
        sb.appendLine(executeCommand("cat /proc/cpuinfo | grep -E 'Processor|model name|Hardware' | head -5"))
        sb.appendLine()
        
        sb.appendLine("🔋 BATTERY")
        sb.appendLine("=========")
        sb.appendLine(executeCommand("dumpsys battery | grep -E 'level|status|temperature' | head -5"))
        
        sb.toString()
    }

    /**
     * Network information
     */
    suspend fun getNetworkInfo(): String = withContext(Dispatchers.IO) {
        val sb = StringBuilder()
        
        sb.appendLine("🌐 NETWORK STATUS")
        sb.appendLine("=================")
        sb.appendLine(executeCommand("ifconfig 2>/dev/null || ip addr show | grep -E 'inet|mtu' | head -10"))
        sb.appendLine()
        
        sb.appendLine("📡 CONNECTIVITY")
        sb.appendLine("==============")
        sb.appendLine(executeCommand("ping -c 2 8.8.8.8 2>&1 | tail -3"))
        
        sb.toString()
    }

    // ===================================================================
    // NETWORK OPERATIONS
    // ===================================================================

    /**
     * Ping host
     */
    suspend fun ping(host: String, count: Int = 4): String = withContext(Dispatchers.IO) {
        val safeHost = host.replace(Regex("[^a-zA-Z0-9.-]"), "")
        executeCommand("ping -c $count $safeHost 2>&1 | tail -20")
    }

    /**
     * HTTP GET request
     */
    suspend fun httpGet(url: String): String = withContext(Dispatchers.IO) {
        try {
            val connection = URL(url).openConnection() as HttpURLConnection
            connection.apply {
                requestMethod = "GET"
                connectTimeout = 10000
                readTimeout = 10000
                setRequestProperty("User-Agent", "Jarvis-Pixel-Bot/1.0")
            }
            
            val responseCode = connection.responseCode
            val content = if (responseCode == 200) {
                connection.inputStream.bufferedReader().use { it.readText() }
            } else {
                "HTTP $responseCode: ${connection.responseMessage}"
            }
            
            connection.disconnect()
            content.take(2000)
            
        } catch (e: Exception) {
            "Error: ${e.message}"
        }
    }

    // ===================================================================
    // PYTHON & SCRIPTING
    // ===================================================================

    /**
     * Execute Python code
     */
    suspend fun executePython(code: String): String = withContext(Dispatchers.IO) {
        val escapedCode = code.replace("\"", "\\\"").replace("\n", "; ")
        executeCommand("python3 -c \"$escapedCode\" 2>&1 || echo 'Python not available'")
    }

    /**
     * Run script file
     */
    suspend fun runScript(scriptPath: String, interpreter: String = "bash"): String = withContext(Dispatchers.IO) {
        executeCommand("$interpreter '$scriptPath' 2>&1")
    }

    // ===================================================================
    // UTILITY FUNCTIONS
    // ===================================================================

    /**
     * Resolve path shortcuts
     */
    private fun resolvePath(path: String): String {
        return when {
            path == "~" -> TERMUX_HOME
            path.startsWith("~/") -> path.replace("~/", "${TERMUX_HOME}/")
            path == "/sdcard" -> SD_CARD
            path.startsWith("/sdcard/") -> path.replace("/sdcard/", "${SD_CARD}/")
            else -> path
        }
    }

    /**
     * Get current working directory
     */
    suspend fun getWorkingDirectory(): String = withContext(Dispatchers.IO) {
        System.getProperty("user.dir") ?: "/"
    }

    /**
     * Change directory (returns new path)
     */
    suspend fun changeDirectory(path: String): String = withContext(Dispatchers.IO) {
        val resolved = resolvePath(path)
        if (File(resolved).isDirectory) {
            System.setProperty("user.dir", resolved)
            "✓ Changed to: $resolved"
        } else {
            "Error: Not a directory: $path"
        }
    }

    /**
     * Disk usage for specific path
     */
    suspend fun diskUsage(path: String): String = withContext(Dispatchers.IO) {
        executeCommand("du -sh '$path' 2>&1 && echo '---' && df -h '$path' 2>&1 | head -2")
    }

    /**
     * Tail log files
     */
    suspend fun tailLog(path: String, lines: Int = 20): String = withContext(Dispatchers.IO) {
        executeCommand("tail -n $lines '$path' 2>&1")
    }

    /**
     * Search text in files
     */
    suspend fun grep(pattern: String, path: String, recursive: Boolean = false): String = withContext(Dispatchers.IO) {
        val flag = if (recursive) "-r" else ""
        executeCommand("grep $flag -n '$pattern' '$path' 2>&1 | head -30")
    }
}