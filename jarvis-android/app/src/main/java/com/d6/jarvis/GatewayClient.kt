package com.d6.jarvis

import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.util.concurrent.TimeUnit

/**
 * HTTP client for OpenClaw Gateway (clawdbot)
 * Connects to the gateway running in Termux on port 18789
 * Handles chat completions and tool execution
 */
class GatewayClient(
    private val baseUrl: String = "http://127.0.0.1:18789",
    private val toolExecutor: ToolExecutor
) {
    companion object {
        private const val TAG = "GatewayClient"
        private const val TIMEOUT_SECONDS = 60L
        private const val MAX_TOKENS = 8192
        private const val TEMPERATURE = 0.7
    }

    private val client: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(TIMEOUT_SECONDS, TimeUnit.SECONDS)
        .readTimeout(120, TimeUnit.SECONDS)
        .writeTimeout(TIMEOUT_SECONDS, TimeUnit.SECONDS)
        .build()

    @Volatile
    var isAvailable = false
        private set

    /**
     * Check if gateway is available
     */
    suspend fun checkHealth(): Boolean = withContext(Dispatchers.IO) {
        try {
            val request = Request.Builder()
                .url("$baseUrl/health")
                .get()
                .build()

            client.newCall(request).execute().use { response ->
                isAvailable = response.isSuccessful
                Log.d(TAG, "Gateway health check: $isAvailable (${response.code})")
                isAvailable
            }
        } catch (e: Exception) {
            Log.w(TAG, "Gateway unavailable: ${e.message}")
            isAvailable = false
            false
        }
    }

    /**
     * Send message to gateway and get response
     * Handles tool calls and returns final text response
     */
    suspend fun chat(
        messages: List<Map<String, String>>,
        tools: List<Map<String, Any>>? = null,
        maxIterations: Int = 5
    ): String = withContext(Dispatchers.IO) {
        if (!isAvailable && !checkHealth()) {
            return@withContext "[ERROR: Gateway unavailable. Using fallback LLM...]"
        }

        var currentMessages = messages.toMutableList()
        var iterations = 0

        while (iterations < maxIterations) {
            iterations++
            Log.d(TAG, "Chat iteration $iterations")

            val response = sendChatRequest(currentMessages, tools)
            
            when {
                response.has("error") -> {
                    return@withContext "[ERROR: ${response.getString("error")}]"
                }
                response.has("choices") -> {
                    val choice = response.getJSONArray("choices").getJSONObject(0)
                    val message = choice.getJSONObject("message")
                    
                    // Add assistant message to conversation
                    currentMessages.add(mapOf(
                        "role" to "assistant",
                        "content" to message.optString("content", "")
                    ))

                    // Check for tool calls
                    if (message.has("tool_calls")) {
                        val toolCalls = message.getJSONArray("tool_calls")
                        
                        for (i in 0 until toolCalls.length()) {
                            val toolCall = toolCalls.getJSONObject(i)
                            val toolResult = executeToolCall(toolCall)
                            
                            // Add tool result to conversation
                            currentMessages.add(mapOf(
                                "role" to "tool",
                                "tool_call_id" to toolCall.getString("id"),
                                "content" to toolResult
                            ))
                        }
                        // Continue loop for next iteration
                        continue
                    }

                    // No tool calls, return content
                    return@withContext message.optString("content", "[No response]")
                }
                else -> {
                    return@withContext "[ERROR: Unexpected response format]"
                }
            }
        }

        "[ERROR: Max iterations reached without completion]"
    }

    /**
     * Send single chat request to gateway
     */
    private fun sendChatRequest(
        messages: List<Map<String, String>>,
        tools: List<Map<String, Any>>?
    ): JSONObject {
        val jsonBody = JSONObject().apply {
            put("model", "gpt-4")  // Gateway handles model selection
            put("messages", JSONArray(messages.map { msg ->
                JSONObject().apply {
                    put("role", msg["role"])
                    put("content", msg["content"])
                }
            }))
            put("max_tokens", MAX_TOKENS)
            put("temperature", TEMPERATURE)
            
            if (tools != null) {
                put("tools", JSONArray(tools))
                put("tool_choice", "auto")
            }
        }

        val requestBody = jsonBody.toString().toRequestBody("application/json".toMediaType())
        
        val request = Request.Builder()
            .url("$baseUrl/v1/chat/completions")
            .post(requestBody)
            .header("Content-Type", "application/json")
            .build()

        return try {
            client.newCall(request).execute().use { response ->
                if (response.isSuccessful) {
                    val body = response.body?.string() ?: "{}"
                    JSONObject(body)
                } else {
                    JSONObject().put("error", "HTTP ${response.code}: ${response.message}")
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Request failed: ${e.message}")
            JSONObject().put("error", e.message ?: "Unknown error")
        }
    }

    /**
     * Execute a tool call from the gateway
     */
    private suspend fun executeToolCall(toolCall: JSONObject): String {
        val function = toolCall.getJSONObject("function")
        val name = function.getString("name")
        val arguments = function.getString("arguments")
        
        Log.d(TAG, "Executing tool: $name with args: $arguments")
        
        return try {
            val argsJson = JSONObject(arguments)
            toolExecutor.execute(name, argsJson)
        } catch (e: Exception) {
            Log.e(TAG, "Tool execution failed: $name", e)
            "Error executing tool $name: ${e.message}"
        }
    }

    /**
     * Get available tools from gateway
     */
    suspend fun getTools(): List<Map<String, Any>> = withContext(Dispatchers.IO) {
        try {
            val request = Request.Builder()
                .url("$baseUrl/v1/tools")
                .get()
                .build()

            client.newCall(request).execute().use { response ->
                if (response.isSuccessful) {
                    val body = response.body?.string() ?: "[]"
                    val jsonArray = JSONArray(body)
                    (0 until jsonArray.length()).map { i ->
                        val tool = jsonArray.getJSONObject(i)
                        mapOf(
                            "type" to "function",
                            "function" to mapOf(
                                "name" to tool.getString("name"),
                                "description" to tool.optString("description", ""),
                                "parameters" to tool.getJSONObject("parameters").toString()
                            )
                        )
                    }
                } else {
                    emptyList()
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to get tools: ${e.message}")
            getDefaultTools()
        }
    }

    /**
     * Default tools when gateway doesn't provide them
     */
    private fun getDefaultTools(): List<Map<String, Any>> {
        return listOf(
            mapOf(
                "type" to "function",
                "function" to mapOf(
                    "name" to "shell",
                    "description" to "Execute shell command",
                    "parameters" to mapOf(
                        "type" to "object",
                        "properties" to mapOf(
                            "command" to mapOf("type" to "string")
                        ),
                        "required" to listOf("command")
                    )
                )
            ),
            mapOf(
                "type" to "function",
                "function" to mapOf(
                    "name" to "read_file",
                    "description" to "Read file contents",
                    "parameters" to mapOf(
                        "type" to "object",
                        "properties" to mapOf(
                            "path" to mapOf("type" to "string"),
                            "limit" to mapOf("type" to "integer")
                        ),
                        "required" to listOf("path")
                    )
                )
            ),
            mapOf(
                "type" to "function",
                "function" to mapOf(
                    "name" to "write_file",
                    "description" to "Write content to file",
                    "parameters" to mapOf(
                        "type" to "object",
                        "properties" to mapOf(
                            "path" to mapOf("type" to "string"),
                            "content" to mapOf("type" to "string")
                        ),
                        "required" to listOf("path", "content")
                    )
                )
            ),
            mapOf(
                "type" to "function",
                "function" to mapOf(
                    "name" to "list_directory",
                    "description" to "List directory contents",
                    "parameters" to mapOf(
                        "type" to "object",
                        "properties" to mapOf(
                            "path" to mapOf("type" to "string")
                        ),
                        "required" to listOf("path")
                    )
                )
            )
        )
    }

    fun shutdown() {
        client.dispatcher.executorService.shutdown()
    }
}
