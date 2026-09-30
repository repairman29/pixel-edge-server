package com.d6.jarvis

import android.util.Log
import kotlinx.coroutines.*
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.util.concurrent.TimeUnit

/**
 * Telegram bot using long polling.
 *
 * When a message arrives, [onMessage] is called with (chatId, text).
 * Whatever string it returns is sent back to the user.
 *
 * Usage:
 *   val bot = TelegramBot(token) { chatId, text -> llm.generate(text) }
 *   bot.start(serviceCoroutineScope)
 */
class TelegramBot(
    private val token: String,
    private val onMessage: suspend (chatId: Long, text: String) -> String
) {

    companion object {
        private const val TAG = "TelegramBot"
        private const val POLL_TIMEOUT_SEC = 30
        private const val ERROR_BACKOFF_MS = 5_000L
        private const val CONFLICT_BACKOFF_MS = 45_000L  // 45 seconds for 409 errors
    }

    private val baseUrl = "https://api.telegram.org/bot$token"
    
    init {
        Log.d(TAG, "Bot initialized with baseUrl: $baseUrl")
    }

    // Separate client with long read timeout for polling
    private val pollClient = OkHttpClient.Builder()
        .readTimeout((POLL_TIMEOUT_SEC + 5).toLong(), TimeUnit.SECONDS)
        .connectTimeout(10, TimeUnit.SECONDS)
        .build()

    // Fast client for sending messages
    private val sendClient = OkHttpClient.Builder()
        .readTimeout(10, TimeUnit.SECONDS)
        .connectTimeout(10, TimeUnit.SECONDS)
        .build()

    @Volatile
    var isRunning = false
        private set

    @Volatile
    var lastError: String? = null
        private set

    private var pollingJob: Job? = null
    private var offset = 0L

    // ------------------------------------------------------------------
    // Lifecycle
    // ------------------------------------------------------------------

    fun start(scope: CoroutineScope) {
        if (isRunning) return
        isRunning = true
        lastError = null
        Log.d(TAG, "Starting Telegram bot polling")

        pollingJob = scope.launch(Dispatchers.IO) {
            while (isActive && isRunning) {
                try {
                    val updates = fetchUpdates()
                    for (update in updates) {
                        processUpdate(update, scope)
                    }
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    lastError = e.message
                    Log.e(TAG, "Polling error: ${e.message}")
                    delay(ERROR_BACKOFF_MS)
                }
            }
        }
    }

    fun stop() {
        isRunning = false
        pollingJob?.cancel()
        pollingJob = null
        Log.d(TAG, "Telegram bot stopped")
    }

    // ------------------------------------------------------------------
    // Polling
    // ------------------------------------------------------------------

    private fun fetchUpdates(): List<JSONObject> {
        val url = "$baseUrl/getUpdates?offset=$offset&timeout=$POLL_TIMEOUT_SEC&allowed_updates=[\"message\"]"
        val request = Request.Builder().url(url).build()

        val response = pollClient.newCall(request).execute()
        val body = response.body?.string()

        if (!response.isSuccessful || body == null) {
            throw Exception("getUpdates failed: ${response.code}")
        }

        val json = JSONObject(body)
        if (!json.getBoolean("ok")) {
            throw Exception("Telegram error: ${json.optString("description")}")
        }

        val result = json.getJSONArray("result")
        return (0 until result.length()).map { result.getJSONObject(it) }
    }

    private fun processUpdate(update: JSONObject, scope: CoroutineScope) {
        val updateId = update.getLong("update_id")
        offset = updateId + 1  // Advance so we don't reprocess

        val message = update.optJSONObject("message") ?: return
        val chatId = message.getJSONObject("chat").getLong("id")
        val text = message.optString("text", "").trim()
        val userName = message.optJSONObject("from")?.optString("first_name", "user") ?: "user"

        if (text.isEmpty()) return

        Log.d(TAG, "Message from $userName ($chatId): $text")

        scope.launch(Dispatchers.IO) {
            // Send typing indicator
            sendChatAction(chatId, "typing")

            val reply = try {
                onMessage(chatId, text)
            } catch (e: Exception) {
                Log.e(TAG, "onMessage error", e)
                "Sorry, I hit an error: ${e.message}"
            }

            Log.d(TAG, "Sending reply to $chatId: ${reply.take(50)}...")
            sendMessage(chatId, reply)
        }
    }

    // ------------------------------------------------------------------
    // Sending
    // ------------------------------------------------------------------

    fun sendMessage(chatId: Long, text: String) {
        val truncated = if (text.length > 4096) text.take(4096) else text

        val body = JSONObject().apply {
            put("chat_id", chatId)
            put("text", truncated)
            put("parse_mode", "Markdown")
        }.toString().toRequestBody("application/json".toMediaType())

        val requestUrl = "$baseUrl/sendMessage"
        Log.d(TAG, "Sending message to: $requestUrl")
        
        val request = Request.Builder()
            .url(requestUrl)
            .post(body)
            .build()

        try {
            sendClient.newCall(request).execute().use { response ->
                if (!response.isSuccessful) {
                    val errorBody = response.body?.string() ?: "No error body"
                    Log.e(TAG, "sendMessage failed: HTTP ${response.code} - $errorBody")
                    
                    // Retry without markdown if parse error
                    val plainBody = JSONObject().apply {
                        put("chat_id", chatId)
                        put("text", truncated)
                    }.toString().toRequestBody("application/json".toMediaType())

                    val retryRequest = Request.Builder()
                        .url("$baseUrl/sendMessage")
                        .post(plainBody)
                        .build()
                    sendClient.newCall(retryRequest).execute().close()
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "sendMessage failed", e)
        }
    }

    private fun sendChatAction(chatId: Long, action: String) {
        val body = JSONObject().apply {
            put("chat_id", chatId)
            put("action", action)
        }.toString().toRequestBody("application/json".toMediaType())

        val request = Request.Builder()
            .url("$baseUrl/sendChatAction")
            .post(body)
            .build()

        try {
            sendClient.newCall(request).execute().close()
        } catch (e: Exception) {
            // Non-critical, ignore
        }
    }

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    fun getBotInfo(): String? {
        return try {
            val request = Request.Builder().url("$baseUrl/getMe").build()
            val response = sendClient.newCall(request).execute()
            val body = response.body?.string() ?: return null
            val json = JSONObject(body)
            if (json.getBoolean("ok")) {
                val result = json.getJSONObject("result")
                "@${result.getString("username")}"
            } else null
        } catch (e: Exception) {
            null
        }
    }
}
