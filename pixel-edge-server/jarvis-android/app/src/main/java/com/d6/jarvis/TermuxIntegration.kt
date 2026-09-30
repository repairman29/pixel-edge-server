package com.d6.jarvis

import android.content.Context
import android.content.Intent
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.nio.charset.StandardCharsets

/**
 * Direct Termux integration using Termux API.
 * Executes commands in Termux environment.
 */
class TermuxIntegration(private val context: Context) {

    companion object {
        private const val TAG = "TermuxIntegration"
        private const val TERMUX_API_URL = "http://127.0.0.1:8080"
        private const val MAX_OUTPUT_LENGTH = 3000
    }

    /**
     * Check if Termux API is available
     */
    suspend fun isTermuxAvailable(): Boolean = withContext(Dispatchers.IO) {
        try {
            val url = URL("$TERMUX_API_URL/version")
            val connection = url.openConnection() as HttpURLConnection
            connection.requestMethod = "GET"
            connection.connectTimeout = 2000
            connection.readTimeout = 2000
            
            val responseCode = connection.responseCode
            connection.disconnect()
            responseCode == 200
        } catch (e: Exception) {
            false
        }
    }

    /**
     * Execute command in Termux via RUN_COMMAND intent
     */
    fun executeCommand(command: String, args: List<String> = emptyList()) {
        try {
            val intent = Intent("com.termux.RUN_COMMAND").apply {
                setClassName("com.termux", "com.termux.app.RunCommandService")
                putExtra("com.termux.RUN_COMMAND_PATH", command)
                putExtra("com.termux.RUN_COMMAND_ARGUMENTS", args.toTypedArray())
                putExtra("com.termux.RUN_COMMAND_BACKGROUND", true)
                putExtra("com.termux.RUN_COMMAND_WORKDIR", "/data/data/com.termux/files/home")
            }
            
            context.startService(intent)
            Log.d(TAG, "Command sent to Termux: $command ${args.joinToString(" ")}")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to execute Termux command", e)
        }
    }

    /**
     * Setup OpenClaw in Termux
     */
    fun setupOpenClaw() {
        Log.d(TAG, "Setting up OpenClaw in Termux...")
        
        // Create setup script
        val setupCommands = listOf(
            "cd ~",
            "pkg update -y",
            "pkg install -y nodejs git rust python build-essential",
            "if [ -d openclaw ]; then cd openclaw && git pull; else git clone https://github.com/DriftOS/clawdbot.git openclaw && cd openclaw; fi",
            "npm install terminal-clipboard --save",
            "npm install",
            "npm run build",
            "mkdir -p ~/.config/openclaw",
            "echo '{\"llm\":{\"provider\":\"openai\",\"baseURL\":\"http://127.0.0.1:9090/v1\",\"apiKey\":\"local\",\"model\":\"gemma-3b\"}}' > ~/.config/openclaw/config.json",
            "echo '✓ OpenClaw setup complete!'"
        )
        
        // Execute as a single script
        val script = setupCommands.joinToString(" && ")
        executeCommand("/data/data/com.termux/files/usr/bin/bash", listOf("-c", script))
    }

    /**
     * Start OpenClaw gateway
     */
    fun startOpenClawGateway() {
        Log.d(TAG, "Starting OpenClaw gateway...")
        executeCommand(
            "/data/data/com.termux/files/usr/bin/bash",
            listOf("-c", "cd ~/openclaw && nohup node bin/openclaw gateway --bind 127.0.0.1 --port 18789 > /dev/null 2>&1 &")
        )
    }

    /**
     * Execute shell command with direct output (fallback)
     */
    suspend fun executeShellFallback(command: String): String = withContext(Dispatchers.IO) {
        try {
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
                else -> "Command executed"
            }
        } catch (e: Exception) {
            Log.e(TAG, "Shell execution failed", e)
            "Error: ${e.message}"
        }
    }
}