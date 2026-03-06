package com.d6.jarvis

import android.content.Context
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.URL

/**
 * Executes tool calls from OpenClaw Gateway
 * Runs commands via Termux or Android shell
 */
class ToolExecutor(private val context: Context) {
    
    companion object {
        private const val TAG = "ToolExecutor"
        private const val MAX_OUTPUT = 4000
        private const val TERMUX_HOME = "/data/data/com.termux/files/home"
        private const val SD_CARD = "/storage/emulated/0"
        private const val MAX_EXECUTION_TIME_MS = 30000L
    }

    /**
     * Execute tool call by name
     */
    suspend fun execute(toolName: String, args: JSONObject): String = withContext(Dispatchers.IO) {
        Log.d(TAG, "Executing tool: $toolName with args: $args")
        
        try {
            when (toolName) {
                "shell", "bash", "sh" -> executeShell(args)
                "read_file", "cat", "read" -> readFile(args)
                "write_file", "write" -> writeFile(args)
                "list_directory", "ls", "list" -> listDirectory(args)
                "find", "search" -> findFiles(args)
                "grep", "search_text" -> grepText(args)
                "ping" -> pingHost(args)
                "http_get", "fetch" -> httpGet(args)
                "python", "py" -> executePython(args)
                "get_system_info", "system_info", "system" -> getSystemInfo()
                "get_network_info", "network_info", "network" -> getNetworkInfo()
                "disk_usage", "du" -> diskUsage(args)
                "tail_log", "tail" -> tailLog(args)
                "run_script", "script", "exec" -> runScript(args)
                "kill_process", "kill" -> killProcess(args)
                "list_processes", "ps", "processes" -> listProcesses()
                "process_info", "proc_info" -> processInfo(args)
                "change_directory", "cd" -> changeDirectory(args)
                "get_working_directory", "pwd", "cwd" -> getWorkingDirectory()
                "termux_run", "termux", "t" -> termuxRun(args)
                "send_message", "telegram", "msg" -> sendTelegramMessage(args)
                else -> "Error: Unknown tool: $toolName"
            }
        } catch (e: Exception) {
            Log.e(TAG, "Tool execution failed: $toolName", e)
            "Error executing $toolName: ${e.message}"
        }
    }

    /**
     * Execute shell command
     */
    private suspend fun executeShell(args: JSONObject): String {
        val command = args.getString("command")
        val workingDir = args.optString("working_dir", null)
        return executeShellCommand(command, workingDir)
    }

    /**
     * Execute shell command via Runtime
     */
    private fun executeShellCommand(cmd: String, workingDir: String? = null): String {
        val resolvedDir = workingDir?.let { resolvePath(it) }
        val process = try {
            ProcessBuilder("sh", "-c", cmd).apply {
                redirectErrorStream(true)
                resolvedDir?.let { directory(File(it)) }
                environment().apply {
                    put("PATH", "/system/bin:/system/xbin:/data/data/com.termux/files/usr/bin:/data/data/com.termux/files/usr/local/bin")
                    put("HOME", TERMUX_HOME)
                    put("TERM", "xterm-256color")
                }
            }.start()
        } catch (e: Exception) {
            return "Error starting process: ${e.message}"
        }

        val output = StringBuilder()
        val reader = BufferedReader(InputStreamReader(process.inputStream))
        
        try {
            var line: String?
            while (reader.readLine().also { line = it } != null) {
                output.appendLine(line)
                if (output.length > MAX_OUTPUT) {
                    output.appendLine("\n[... output truncated ...]")
                    break
                }
            }
        } finally {
            reader.close()
        }

        // Wait for process with timeout
        val finished = process.waitFor(MAX_EXECUTION_TIME_MS, java.util.concurrent.TimeUnit.MILLISECONDS)
        if (!finished) {
            process.destroyForcibly()
            return "Error: Command timed out after ${MAX_EXECUTION_TIME_MS / 1000}s\nPartial output:\n${output.toString().take(1000)}"
        }

        return output.toString().trim().ifEmpty { "Command executed successfully (no output)" }
    }

    /**
     * Execute via Termux (run-as com.termux)
     */
    private suspend fun termuxRun(args: JSONObject): String {
        val command = args.getString("command")
        val useRunAs = args.optBoolean("run_as", false)
        
        return if (useRunAs) {
            executeShellCommand("run-as com.termux bash -c '$command'")
        } else {
            // Try to send intent to Termux
            executeViaTermuxIntent(command)
        }
    }

    private fun executeViaTermuxIntent(command: String): String {
        return try {
            val intent = android.content.Intent().apply {
                action = "com.termux.RUN_COMMAND"
                putExtra("com.termux.RUN_COMMAND_PATH", "/data/data/com.termux/files/usr/bin/bash")
                putExtra("com.termux.RUN_COMMAND_ARGUMENTS", arrayOf("-c", command))
                putExtra("com.termux.RUN_COMMAND_WORKDIR", TERMUX_HOME)
                putExtra("com.termux.RUN_COMMAND_BACKGROUND", true)
                setPackage("com.termux")
            }
            context.sendBroadcast(intent)
            "Command sent to Termux in background: $command"
        } catch (e: Exception) {
            "Error sending Termux intent: ${e.message}. Falling back to run-as..."
        }
    }

    /**
     * Read file
     */
    private fun readFile(args: JSONObject): String {
        val path = resolvePath(args.getString("path"))
        val limit = args.optInt("limit", 100)
        val file = File(path)
        
        return when {
            !file.exists() -> "Error: File not found: $path"
            !file.canRead() -> "Error: Permission denied: $path"
            file.isDirectory -> "Error: $path is a directory"
            file.length() > 1024 * 1024 -> "Error: File too large (${file.length() / 1024}KB)"
            else -> file.readLines().take(limit).joinToString("\n")
        }
    }

    /**
     * Write file
     */
    private fun writeFile(args: JSONObject): String {
        val path = resolvePath(args.getString("path"))
        val content = args.getString("content")
        val append = args.optBoolean("append", false)
        val file = File(path)
        
        return try {
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
     * List directory
     */
    private fun listDirectory(args: JSONObject): String {
        val path = resolvePath(args.getString("path"))
        val showHidden = args.optBoolean("show_hidden", false)
        val file = File(path)
        
        return when {
            !file.exists() -> "Error: Directory not found: $path"
            !file.isDirectory -> "Error: $path is not a directory"
            !file.canRead() -> executeShellCommand("ls -la '$path' 2>&1")
            else -> {
                val flags = if (showHidden) "-la" else "-l"
                executeShellCommand("ls $flags '$path' 2>&1 || ls -la '$path' 2>&1")
            }
        }
    }

    /**
     * Find files
     */
    private fun findFiles(args: JSONObject): String {
        val pattern = args.getString("pattern")
        val path = resolvePath(args.optString("path", SD_CARD))
        return executeShellCommand("find '$path' -name '*$pattern*' -type f 2>/dev/null | head -20")
    }

    /**
     * Search text in files
     */
    private fun grepText(args: JSONObject): String {
        val pattern = args.getString("pattern")
        val path = resolvePath(args.getString("path"))
        val recursive = args.optBoolean("recursive", false)
        val flag = if (recursive) "-r" else ""
        return executeShellCommand("grep $flag -n '$pattern' '$path' 2>&1 | head -30")
    }

    /**
     * Ping host
     */
    private fun pingHost(args: JSONObject): String {
        val host = args.getString("host").replace(Regex("[^a-zA-Z0-9.-]"), "")
        val count = args.optInt("count", 4)
        return executeShellCommand("ping -c $count $host 2>&1 | tail -20")
    }

    /**
     * HTTP GET request
     */
    private fun httpGet(args: JSONObject): String {
        val urlString = args.getString("url")
        return try {
            val connection = URL(urlString).openConnection() as HttpURLConnection
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

    /**
     * Execute Python code
     */
    private fun executePython(args: JSONObject): String {
        val code = args.getString("code")
        val escaped = code.replace("\"", "\\\"").replace("\n", "; ")
        return executeShellCommand("python3 -c \"$escaped\" 2>&1 || python -c \"$escaped\" 2>&1 || echo 'Python not available'")
    }

    /**
     * Run script file
     */
    private fun runScript(args: JSONObject): String {
        val scriptPath = resolvePath(args.getString("script_path"))
        val interpreter = args.optString("interpreter", "bash")
        return executeShellCommand("$interpreter '$scriptPath' 2>&1")
    }

    /**
     * Get system info
     */
    private fun getSystemInfo(): String {
        val sb = StringBuilder()
        
        sb.appendLine("📱 DEVICE INFORMATION")
        sb.appendLine("==================")
        sb.appendLine(executeShellCommand("getprop ro.product.model").trim())
        sb.appendLine("Android: ${executeShellCommand("getprop ro.build.version.release").trim()}")
        sb.appendLine("SDK: ${executeShellCommand("getprop ro.build.version.sdk").trim()}")
        sb.appendLine()
        
        sb.appendLine("💾 STORAGE")
        sb.appendLine("=========")
        sb.appendLine(executeShellCommand("df -h /data /sdcard 2>&1 | grep -v 'Filesystem'"))
        sb.appendLine()
        
        sb.appendLine("🧠 MEMORY")
        sb.appendLine("========")
        sb.appendLine(executeShellCommand("cat /proc/meminfo | grep -E 'MemTotal|MemAvailable|MemFree|Buffers|Cached'"))
        sb.appendLine()
        
        sb.appendLine("⚡ CPU")
        sb.appendLine("====")
        sb.appendLine(executeShellCommand("cat /proc/cpuinfo | grep -E 'Processor|model name|Hardware' | head -5"))
        sb.appendLine()
        
        sb.appendLine("🔋 BATTERY")
        sb.appendLine("=========")
        sb.appendLine(executeShellCommand("dumpsys battery | grep -E 'level|status|temperature' | head -5"))
        
        return sb.toString()
    }

    /**
     * Get network info
     */
    private fun getNetworkInfo(): String {
        val sb = StringBuilder()
        
        sb.appendLine("🌐 NETWORK STATUS")
        sb.appendLine("=================")
        sb.appendLine(executeShellCommand("ifconfig 2>/dev/null || ip addr show | grep -E 'inet|mtu' | head -10"))
        sb.appendLine()
        
        sb.appendLine("📡 CONNECTIVITY")
        sb.appendLine("==============")
        sb.appendLine(executeShellCommand("ping -c 2 8.8.8.8 2>&1 | tail -3"))
        
        return sb.toString()
    }

    /**
     * Disk usage
     */
    private fun diskUsage(args: JSONObject): String {
        val path = resolvePath(args.getString("path"))
        return executeShellCommand("du -sh '$path' 2>&1 && echo '---' && df -h '$path' 2>&1 | head -2")
    }

    /**
     * Tail log file
     */
    private fun tailLog(args: JSONObject): String {
        val path = resolvePath(args.getString("path"))
        val lines = args.optInt("lines", 20)
        return executeShellCommand("tail -n $lines '$path' 2>&1")
    }

    /**
     * Kill process
     */
    private fun killProcess(args: JSONObject): String {
        val pid = args.getString("pid")
        return executeShellCommand("kill -9 $pid 2>&1 && echo 'Process $pid terminated' || echo 'Failed to kill process'")
    }

    /**
     * List processes
     */
    private fun listProcesses(): String {
        return executeShellCommand("ps -A -o PID,USER,NAME,CMDLINE | head -30")
    }

    /**
     * Get process info
     */
    private fun processInfo(args: JSONObject): String {
        val pid = args.getString("pid")
        return executeShellCommand("cat /proc/$pid/status 2>&1 || echo 'Process not found'")
    }

    /**
     * Change directory
     */
    private fun changeDirectory(args: JSONObject): String {
        val path = resolvePath(args.getString("path"))
        val file = File(path)
        return if (file.isDirectory) {
            System.setProperty("user.dir", path)
            "✓ Changed to: $path"
        } else {
            "Error: Not a directory: $path"
        }
    }

    /**
     * Get working directory
     */
    private fun getWorkingDirectory(): String {
        return System.getProperty("user.dir") ?: "/"
    }

    /**
     * Send Telegram message (placeholder - actual sending happens via TelegramBot)
     */
    private fun sendTelegramMessage(args: JSONObject): String {
        val chatId = args.getString("chat_id")
        val message = args.getString("message")
        return "Message queued for chat $chatId: ${message.take(50)}..."
    }

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
}
