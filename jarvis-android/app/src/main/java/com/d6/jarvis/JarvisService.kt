package com.d6.jarvis

import android.app.*
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import kotlinx.coroutines.*

/**
 * The heart of everything.
 *
 * Foreground service that:
 *  1. Connects to OpenClaw Gateway in Termux (port 18789)
 *  2. Falls back to local MediaPipe LLM if gateway unavailable
 *  3. Starts the HTTP API server (port 9090)
 *  4. Starts Telegram bot long polling
 *  5. Keeps a WakeLock so operations don't stall when screen is off
 *
 * Start it via:
 *   JarvisService.start(context, token, modelPath)
 *
 * Stop it via:
 *   JarvisService.stop(context)
 */
class JarvisService : Service() {

    companion object {
        private const val TAG = "JarvisService"
        private const val NOTIF_CHANNEL_ID = "jarvis_channel"
        private const val NOTIF_ID = 1001
        private const val HTTP_PORT = 9090
        private const val GATEWAY_URL = "http://127.0.0.1:18789"
        private const val GATEWAY_API_KEY = "sk_dcd6c7f2dde7cab80421df8afab14901b3b8b16cb4b61abd"

        const val EXTRA_TOKEN = "telegram_token"
        const val EXTRA_MODEL_PATH = "model_path"

        const val ACTION_START = "com.d6.jarvis.START"
        const val ACTION_STOP  = "com.d6.jarvis.STOP"

        // Broadcast actions so MainActivity can update its UI
        const val BROADCAST_STATUS = "com.d6.jarvis.STATUS"
        const val STATUS_KEY = "status"

        fun start(context: Context, token: String, modelPath: String) {
            val intent = Intent(context, JarvisService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_TOKEN, token)
                putExtra(EXTRA_MODEL_PATH, modelPath)
            }
            context.startForegroundService(intent)
        }

        fun stop(context: Context) {
            val intent = Intent(context, JarvisService::class.java).apply {
                action = ACTION_STOP
            }
            context.startService(intent)
        }
    }

    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    // Gateway integration (new)
    private lateinit var toolExecutor: ToolExecutor
    private lateinit var gatewayClient: GatewayClient
    
    // Fallback local LLM
    private lateinit var llmEngine: LlmEngine
    
    // Legacy bridges
    private lateinit var termuxBridge: TermuxBridge
    private lateinit var termuxIntegration: TermuxIntegration
    
    private var httpServer: HttpApiServer? = null
    private var telegramBot: TelegramBot? = null
    private var wakeLock: PowerManager.WakeLock? = null

    @Volatile
    private var useGateway = true

    @Volatile
    private var availableTools: List<Map<String, Any>> = emptyList()

    // ------------------------------------------------------------------
    // Lifecycle
    // ------------------------------------------------------------------

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        
        // Initialize components
        toolExecutor = ToolExecutor(applicationContext)
        gatewayClient = GatewayClient(GATEWAY_URL, toolExecutor, GATEWAY_API_KEY)
        llmEngine = LlmEngine(applicationContext)
        termuxBridge = TermuxBridge(applicationContext)
        termuxIntegration = TermuxIntegration(applicationContext)
        
        Log.d(TAG, "Service created")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val token = intent.getStringExtra(EXTRA_TOKEN)?.takeIf { it.isNotEmpty() } 
                    ?: "8757734547:AAE-MCgafrmkEAIoXINA2zsAPb3mjBHFdvM"
                val modelPath = intent.getStringExtra(EXTRA_MODEL_PATH)
                    ?: LlmEngine.DEFAULT_MODEL_PATH

                startForeground(NOTIF_ID, buildNotification("Starting…"), ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
                acquireWakeLock()
                serviceScope.launch { boot(token, modelPath) }
            }
            ACTION_STOP -> {
                shutdown()
                stopSelf()
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        shutdown()
        super.onDestroy()
        Log.d(TAG, "Service destroyed")
    }

    override fun onBind(intent: Intent?): IBinder? = null

    // ------------------------------------------------------------------
    // Boot sequence
    // ------------------------------------------------------------------

    private suspend fun boot(telegramToken: String, modelPath: String) {
        broadcast("Initializing services…")
        updateNotification("Initializing services…")

        // 1. Check gateway availability
        broadcast("Checking OpenClaw Gateway…")
        val gatewayAvailable = gatewayClient.checkHealth()
        
        if (gatewayAvailable) {
            broadcast("✓ Gateway connected (OpenClaw)")
            useGateway = true
            
            // Get available tools (Android-side tools exposed to the gateway)
            availableTools = gatewayClient.getTools()
            broadcast("✓ Loaded ${availableTools.size} tools")
        } else {
            broadcast("⚠️ Gateway unavailable - JARVIS needs OpenClaw gateway running on port 18789")
            updateNotification("⚠️ Waiting for OpenClaw gateway…")
            useGateway = false
        }

        // 2. Load local LLM as fallback (disabled to prevent crashes)
        // if (!useGateway) {
        //     broadcast("Loading local LLM (fallback)…")
        //     try {
        //         llmEngine.initialize(modelPath, LlmEngine.Companion.BackendPreference.AUTO)
        //         broadcast("${llmEngine.getStatus()} ✓")
        //     } catch (e: Exception) {
        //         val msg = "Model load failed: ${e.message}"
        //         broadcast(msg)
        //         Log.e(TAG, msg, e)
        //     }
        // }

        // 3. Start HTTP server
        try {
            httpServer = HttpApiServer(HTTP_PORT, llmEngine).also { it.start() }
            broadcast("HTTP API on :$HTTP_PORT ✓")
            Log.d(TAG, "HTTP server started on port $HTTP_PORT")
        } catch (e: Exception) {
            Log.e(TAG, "HTTP server failed to start", e)
            broadcast("HTTP server error: ${e.message}")
        }

        // 4. Start Telegram bot (skip if gateway is handling Telegram)
        if (telegramToken.isNotBlank() && !useGateway) {
            try {
                val bot = TelegramBot(
                    token = telegramToken,
                    onMessage = { chatId, text -> handleMessage(chatId, text) }
                )
                bot.start(serviceScope)

                val botName = withContext(Dispatchers.IO) { bot.getBotInfo() }
                telegramBot = bot

                val backend = if (useGateway) "OpenClaw Gateway" else "Local NPU"
                val status = "Telegram ${botName ?: "connected"} ✓ ($backend)"
                broadcast(status)
                updateNotification("🟢 Running — $status")
                Log.d(TAG, status)

            } catch (e: Exception) {
                Log.e(TAG, "Telegram bot failed", e)
                broadcast("Telegram error: ${e.message}")
                updateNotification("⚠️ Running (Telegram error)")
            }
        } else if (useGateway) {
            broadcast("Gateway connected — Telegram handled by OpenClaw")
            updateNotification("🟢 Running — Gateway (Telegram via OpenClaw)")
        } else {
            broadcast("No Telegram token — HTTP only")
            updateNotification("🟢 Running — HTTP only")
        }
    }

    // ------------------------------------------------------------------
    // Message handler — called for every Telegram message
    // ------------------------------------------------------------------

    private suspend fun handleMessage(chatId: Long, text: String): String {
        Log.d(TAG, "Handling message: $text")

        // Built-in commands
        return when {
            text.startsWith("/start") -> {
                val backend = if (useGateway) "OpenClaw Gateway (InferrLM)" else "Pixel NPU"
                "👋 Jarvis online using $backend.\n\nAvailable commands:\n" +
                "/status - System status\n" +
                "/model - Model info\n" +
                "/gateway - Gateway status\n" +
                "!shell <cmd> - Run shell command\n" +
                "!ls <path> - List directory\n" +
                "!system - System info"
            }
            text.startsWith("/status") -> buildStatusMessage()
            text.startsWith("/model") -> {
                if (useGateway) "Using OpenClaw Gateway - no local model needed"
                else if (llmEngine.isReady) llmEngine.getStatus()
                else "Model not loaded. Error: ${llmEngine.loadError}"
            }
            text.startsWith("/gateway") -> {
                val available = gatewayClient.checkHealth()
                val tools = if (available) availableTools.size else 0
                buildString {
                    append("🔗 Gateway Status\n")
                    append("================\n")
                    append("URL: $GATEWAY_URL\n")
                    append("Available: ${if (available) "✓" else "✗"}\n")
                    append("Tools loaded: $tools\n")
                    append("Active mode: ${if (useGateway) "Gateway" else "Local LLM"}\n")
                }
            }
            text.equals("!use gateway", ignoreCase = true) -> {
                useGateway = true
                serviceScope.launch {
                    val available = gatewayClient.checkHealth()
                    broadcast(if (available) "✓ Switched to Gateway mode" else "⚠️ Gateway unavailable, staying local")
                }
                "Switching to Gateway mode..."
            }
            text.equals("!use local", ignoreCase = true) -> {
                useGateway = false
                if (!llmEngine.isReady) {
                    serviceScope.launch {
                        broadcast("Loading local LLM...")
                        try {
                            llmEngine.initialize(LlmEngine.DEFAULT_MODEL_PATH, LlmEngine.Companion.BackendPreference.AUTO)
                            broadcast("✓ Local LLM ready")
                        } catch (e: Exception) {
                            broadcast("❌ Failed to load local LLM: ${e.message}")
                        }
                    }
                }
                "Switching to Local LLM mode..."
            }
            // Direct tool commands (execute locally)
            text.startsWith("!shell ") -> {
                val cmd = text.removePrefix("!shell ")
                termuxBridge.executeShell(cmd)
            }
            text.startsWith("!ls ") -> {
                val path = text.removePrefix("!ls ")
                termuxBridge.listDirectory(path)
            }
            text.startsWith("!system") -> {
                termuxBridge.getSystemInfo()
            }
            text.startsWith("!ping ") -> {
                val host = text.removePrefix("!ping ")
                termuxBridge.ping(host)
            }
            text.startsWith("!python ") -> {
                val code = text.removePrefix("!python ")
                termuxBridge.executePython(code)
            }
            text.startsWith("!read ") -> {
                val path = text.removePrefix("!read ")
                termuxBridge.readFile(path)
            }
            text.startsWith("!write ") -> {
                // Format: !write <path> | <content>
                val parts = text.removePrefix("!write ").split("|", limit = 2)
                if (parts.size == 2) {
                    termuxBridge.writeFile(parts[0].trim(), parts[1].trim())
                } else {
                    "Usage: !write <path> | <content>"
                }
            }
            text.startsWith("!find ") -> {
                val pattern = text.removePrefix("!find ")
                termuxBridge.findFiles(pattern)
            }
            text.startsWith("!exec ") -> {
                val scriptPath = text.removePrefix("!exec ")
                termuxBridge.runScript(scriptPath)
            }
            // Gateway chat - process through OpenClaw
            else -> {
                if (useGateway && gatewayClient.isAvailable) {
                    // Send to gateway for full tool capabilities
                    val messages = listOf(
                        mapOf("role" to "system", "content" to buildSystemPrompt()),
                        mapOf("role" to "user", "content" to text)
                    )
                    
                    try {
                        gatewayClient.chat(messages, availableTools)
                    } catch (e: Exception) {
                        Log.e(TAG, "Gateway chat failed", e)
                        "[Gateway error: ${e.message}]"
                    }
                } else if (llmEngine.isReady) {
                    // Fallback to local LLM
                    val messages = listOf(
                        "system" to buildSystemPrompt(),
                        "user" to text
                    )
                    val prompt = llmEngine.buildChatPrompt(messages)
                    llmEngine.generate(prompt)
                } else {
                    "Error: No LLM available. Try '!use local' or '!use gateway'"
                }
            }
        }
    }

    private fun buildSystemPrompt(): String {
        val tools = availableTools.joinToString(", ") { 
            (it["function"] as? Map<*, *>)?.get("name")?.toString() ?: "unknown"
        }
        
        return """You are Jarvis, an AI assistant running on a Pixel 8 Pro.
            |You have access to the following tools: $tools
            |
            |When you need to use a tool, you'll receive a tool call and can execute it.
            |Keep responses concise and helpful.
            |Current time: ${java.util.Date()}
        """.trimMargin()
    }

    private fun buildStatusMessage(): String {
        val sb = StringBuilder("📊 Jarvis Status\n\n")
        
        sb.append("🔗 Gateway: ${if (gatewayClient.isAvailable) "✓ Connected" else "✗ Unavailable"}\n")
        if (gatewayClient.isAvailable) {
            sb.append("   Tools: ${availableTools.size}\n")
        }
        
        sb.append("🧠 Local LLM: ${if (llmEngine.isReady) llmEngine.getStatus() else "Not loaded"}\n")
        sb.append("   Mode: ${if (useGateway) "Gateway (OpenClaw)" else "Local NPU"}\n")
        sb.append("🌐 HTTP: ${if (httpServer != null) "Port $HTTP_PORT ✓" else "Not running"}\n")
        sb.append("📨 Telegram: ${if (telegramBot?.isRunning == true) "Connected ✓" else "Not connected"}\n")
        
        if (llmEngine.loadError != null) sb.append("❌ Local LLM Error: ${llmEngine.loadError}\n")
        
        sb.append("\n💡 Commands:\n")
        sb.append("  /gateway - Gateway status\n")
        sb.append("  !use gateway - Switch to gateway mode\n")
        sb.append("  !use local - Switch to local LLM\n")
        
        return sb.toString()
    }

    // ------------------------------------------------------------------
    // Shutdown
    // ------------------------------------------------------------------

    private fun shutdown() {
        Log.d(TAG, "Shutting down")
        telegramBot?.stop()
        httpServer?.stop()
        llmEngine.shutdown()
        gatewayClient.shutdown()
        serviceScope.cancel()
        releaseWakeLock()
        broadcast("Stopped")
    }

    // ------------------------------------------------------------------
    // Notification
    // ------------------------------------------------------------------

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            NOTIF_CHANNEL_ID,
            "Jarvis Service",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Jarvis OpenClaw agent service"
            setShowBadge(false)
        }
        getSystemService(NotificationManager::class.java)
            .createNotificationChannel(channel)
    }

    private fun buildNotification(status: String): Notification {
        val stopIntent = Intent(this, JarvisService::class.java).apply {
            action = ACTION_STOP
        }
        val stopPending = PendingIntent.getService(
            this, 0, stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val openIntent = Intent(this, MainActivity::class.java)
        val openPending = PendingIntent.getActivity(
            this, 0, openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, NOTIF_CHANNEL_ID)
            .setContentTitle("Jarvis (OpenClaw)")
            .setContentText(status)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentIntent(openPending)
            .addAction(android.R.drawable.ic_delete, "Stop", stopPending)
            .setOngoing(true)
            .setSilent(true)
            .build()
    }

    private fun updateNotification(status: String) {
        val nm = getSystemService(NotificationManager::class.java)
        nm.notify(NOTIF_ID, buildNotification(status))
    }

    // ------------------------------------------------------------------
    // Broadcast status to MainActivity
    // ------------------------------------------------------------------

    private fun broadcast(status: String) {
        Log.d(TAG, "Status: $status")
        val intent = Intent(BROADCAST_STATUS).apply {
            putExtra(STATUS_KEY, status)
            setPackage(packageName)
        }
        sendBroadcast(intent)
    }

    // ------------------------------------------------------------------
    // WakeLock — keeps CPU alive during operations
    // ------------------------------------------------------------------

    private fun acquireWakeLock() {
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "Jarvis::InferenceLock"
        ).also { it.acquire() }
    }

    private fun releaseWakeLock() {
        wakeLock?.let {
            if (it.isHeld) it.release()
        }
        wakeLock = null
    }
}
