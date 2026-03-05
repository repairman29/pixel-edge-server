package com.d6.jarvis

import android.util.Log
import fi.iki.elonen.NanoHTTPD
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException

/**
 * HTTP server that exposes the LLM via two endpoints:
 *
 *   POST /infer                     { "prompt": "..." }  → { "text": "..." }
 *   POST /v1/chat/completions       OpenAI-compatible     → OpenAI response shape
 *   GET  /health                    → { "ok": true, "ready": true/false }
 */
class HttpApiServer(
    private val port: Int = 9192,
    private val llmEngine: LlmEngine
) : NanoHTTPD("0.0.0.0", port) {

    companion object {
        private const val TAG = "HttpApiServer"
        private val JSON_TYPE = "application/json"
    }

    override fun serve(session: IHTTPSession): Response {
        val uri = session.uri
        val method = session.method

        Log.d(TAG, "$method $uri")

        return when {
            method == Method.GET && uri == "/health" -> handleHealth()
            method == Method.POST && uri == "/infer" -> handleInfer(session)
            method == Method.POST && uri == "/v1/chat/completions" -> handleChatCompletions(session)
            else -> newFixedLengthResponse(
                Response.Status.NOT_FOUND, JSON_TYPE,
                """{"error":"not found"}"""
            )
        }
    }

    // ------------------------------------------------------------------
    // GET /health
    // ------------------------------------------------------------------

    private fun handleHealth(): Response {
        val body = JSONObject().apply {
            put("ok", true)
            put("ready", llmEngine.isReady)
            put("error", llmEngine.loadError)
        }
        return jsonResponse(body)
    }

    // ------------------------------------------------------------------
    // POST /infer  { "prompt": "..." }
    // ------------------------------------------------------------------

    private fun handleInfer(session: IHTTPSession): Response {
        val body = readBody(session) ?: return badRequest("Could not read body")
        val json = tryParseJson(body) ?: return badRequest("Invalid JSON")
        val prompt = json.optString("prompt", "").trim()

        if (prompt.isEmpty()) return badRequest("Missing 'prompt'")
        if (!llmEngine.isReady) return serviceUnavailable("Model not loaded")

        return try {
            val text = runBlocking { llmEngine.generate(prompt) }
            jsonResponse(JSONObject().put("text", text))
        } catch (e: Exception) {
            Log.e(TAG, "Inference error", e)
            errorResponse("Inference failed: ${e.message}")
        }
    }

    // ------------------------------------------------------------------
    // POST /v1/chat/completions  (OpenAI-compatible)
    // ------------------------------------------------------------------

    private fun handleChatCompletions(session: IHTTPSession): Response {
        val body = readBody(session) ?: return badRequest("Could not read body")
        val json = tryParseJson(body) ?: return badRequest("Invalid JSON")

        if (!llmEngine.isReady) return serviceUnavailable("Model not loaded")

        // Parse messages array
        val messagesArray = json.optJSONArray("messages")
            ?: return badRequest("Missing 'messages'")

        val messages = mutableListOf<Pair<String, String>>()
        for (i in 0 until messagesArray.length()) {
            val msg = messagesArray.getJSONObject(i)
            val role = msg.optString("role", "user")
            val content = msg.optString("content", "")
            messages.add(Pair(role, content))
        }

        if (messages.isEmpty()) return badRequest("Empty messages")

        val prompt = llmEngine.buildChatPrompt(messages)

        return try {
            val text = runBlocking { llmEngine.generate(prompt) }
            val responseBody = buildOpenAIResponse(text)
            jsonResponse(responseBody)
        } catch (e: Exception) {
            Log.e(TAG, "Chat completion error", e)
            errorResponse("Inference failed: ${e.message}")
        }
    }

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    private fun buildOpenAIResponse(text: String): JSONObject {
        val message = JSONObject().apply {
            put("role", "assistant")
            put("content", text)
        }
        val choice = JSONObject().apply {
            put("index", 0)
            put("message", message)
            put("finish_reason", "stop")
        }
        return JSONObject().apply {
            put("id", "chatcmpl-jarvis-${System.currentTimeMillis()}")
            put("object", "chat.completion")
            put("created", System.currentTimeMillis() / 1000)
            put("model", "jarvis-npu")
            put("choices", JSONArray().put(choice))
            put("usage", JSONObject().apply {
                put("prompt_tokens", 0)
                put("completion_tokens", 0)
                put("total_tokens", 0)
            })
        }
    }

    private fun readBody(session: IHTTPSession): String? {
        return try {
            val contentLength = session.headers["content-length"]?.toIntOrNull() ?: return null
            val buf = ByteArray(contentLength)
            var read = 0
            while (read < contentLength) {
                val n = session.inputStream.read(buf, read, contentLength - read)
                if (n == -1) break
                read += n
            }
            String(buf, 0, read)
        } catch (e: IOException) {
            Log.e(TAG, "Failed to read body", e)
            null
        }
    }

    private fun tryParseJson(s: String): JSONObject? = try {
        JSONObject(s)
    } catch (e: Exception) {
        null
    }

    private fun jsonResponse(body: JSONObject): Response =
        newFixedLengthResponse(Response.Status.OK, JSON_TYPE, body.toString())

    private fun badRequest(msg: String): Response =
        newFixedLengthResponse(
            Response.Status.BAD_REQUEST, JSON_TYPE,
            JSONObject().put("error", msg).toString()
        )

    private fun serviceUnavailable(msg: String): Response =
        newFixedLengthResponse(
            Response.Status.SERVICE_UNAVAILABLE, JSON_TYPE,
            JSONObject().put("error", msg).toString()
        )

    private fun errorResponse(msg: String): Response =
        newFixedLengthResponse(
            Response.Status.INTERNAL_ERROR, JSON_TYPE,
            JSONObject().put("error", msg).toString()
        )
}
