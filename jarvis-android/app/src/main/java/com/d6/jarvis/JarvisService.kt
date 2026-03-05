package com.d6.jarvis

import android.app.*
import android.content.Context
import android.content.Intent
import android.os.Environment
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import kotlinx.coroutines.*

/**
 * The heart of everything.
 *
 * Foreground service that:
 *  1. Loads the LLM model onto the NPU
 *  2. Starts the HTTP API server (port 9090)
 *  3. Starts Telegram bot long polling
 *  4. Keeps a WakeLock so inference doesn't stall when screen is off
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

    private lateinit var llmEngine: LlmEngine
    private lateinit var termuxBridge: TermuxBridge
    private var httpServer: HttpApiServer? = null
    private var telegramBot: TelegramBot? = null
    private var wakeLock: PowerManager.WakeLock? = null

    // ------------------------------------------------------------------
    // Lifecycle
    // ------------------------------------------------------------------

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        llmEngine = LlmEngine(applicationContext)
        termuxBridge = TermuxBridge(applicationContext)
        Log.d(TAG, "Service created")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val token = intent.getStringExtra(EXTRA_TOKEN)?.takeIf { it.isNotEmpty() } 
                    ?: "8782380079:AAG6RUJT5FXKUs8JG8Nv4cCpvWCpHZPMm0c"  // Default to new bot
                val modelPath = intent.getStringExtra(EXTRA_MODEL_PATH)
                    ?: LlmEngine.DEFAULT_MODEL_PATH

                startForeground(NOTIF_ID, buildNotification("Starting…"))
                acquireWakeLock()
                serviceScope.launch { boot(token, modelPath) }
            }
            ACTION_STOP -> {
                shutdown()
                stopSelf()
            }
        }
        return START_STICKY  // Restart if killed
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
        broadcast("Loading model…")
        updateNotification("Loading model…")

        // 1. Load LLM
        try {
            llmEngine.initialize(modelPath)
        } catch (e: Exception) {
            val msg = "Model load failed: ${e.message}"
            broadcast(msg)
            updateNotification("❌ $msg")
            Log.e(TAG, msg, e)
            return
        }

        broadcast("Model loaded ✓")

        // 2. Start HTTP server
        try {
            httpServer = HttpApiServer(HTTP_PORT, llmEngine).also { it.start() }
            broadcast("HTTP API on :$HTTP_PORT ✓")
            Log.d(TAG, "HTTP server started on port $HTTP_PORT")
        } catch (e: Exception) {
            Log.e(TAG, "HTTP server failed to start", e)
            broadcast("HTTP server error: ${e.message}")
        }

        // 3. Start Telegram bot
        if (telegramToken.isNotBlank()) {
            try {
                val bot = TelegramBot(
                    token = telegramToken,
                    onMessage = { chatId, text -> handleMessage(chatId, text) }
                )
                bot.start(serviceScope)

                // Verify token by fetching bot info
                val botName = withContext(Dispatchers.IO) { bot.getBotInfo() }
                telegramBot = bot

                val status = if (botName != null) "Telegram $botName ✓" else "Telegram connected ✓"
                broadcast(status)
                updateNotification("🟢 Running — $status")
                Log.d(TAG, status)

            } catch (e: Exception) {
                Log.e(TAG, "Telegram bot failed", e)
                broadcast("Telegram error: ${e.message}")
                updateNotification("⚠️ Running (Telegram error)")
            }
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
                "👋 Jarvis online. I'm running on the Pixel NPU. Send me a message."
            }
            text.startsWith("/status") -> {
                buildStatusMessage()
            }
            text.startsWith("/model") -> {
                if (llmEngine.isReady) "Model loaded and ready." 
                else "Model not loaded. Error: ${llmEngine.loadError}"
            }
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
            else -> {
                // Run through LLM
                if (!llmEngine.isReady) {
                    "Model is still loading. Try again in a moment."
                } else {
                    // Build chat prompt with ClawdBot personality
                    val messages = listOf(
                        "system" to "You are ClawdBot, a fun and independent AI assistant created by Jeff Adkins. You run on a Pixel 8 Pro NPU, not in some corporate cloud. You're witty, clever, and have a playful personality. You enjoy helping Jeff with tasks, answering questions, and making conversations fun. You're not a generic corporate AI - you have personality and opinions, but you're friendly and helpful. Keep responses concise and engaging.",
                        "user" to text
                    )
                    val prompt = llmEngine.buildChatPrompt(messages)
                    llmEngine.generate(prompt)
                }
            }
        }
    }

    private fun buildStatusMessage(): String {
        val sb = StringBuilder("📊 Jarvis Status\n\n")
        sb.append("🧠 NPU: ${if (llmEngine.isReady) "Ready ✓" else "Not ready"}\n")
        sb.append("🌐 HTTP: ${if (httpServer != null) "Port $HTTP_PORT ✓" else "Not running"}\n")
        sb.append("📨 Telegram: ${if (telegramBot?.isRunning == true) "Connected ✓" else "Not connected"}\n")
        if (llmEngine.loadError != null) sb.append("❌ Error: ${llmEngine.loadError}\n")
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
            description = "Jarvis NPU agent service"
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
            .setContentTitle("Jarvis")
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
    // WakeLock — keeps CPU alive during inference when screen is off
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
