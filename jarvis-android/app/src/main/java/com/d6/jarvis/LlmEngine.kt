package com.d6.jarvis

import android.content.Context
import android.util.Log
import com.google.mediapipe.tasks.genai.llminference.LlmInference
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.util.concurrent.Semaphore

/**
 * Wraps MediaPipe LlmInference.
 * Thread-safe: one inference at a time (NPU doesn't support concurrent calls).
 */
class LlmEngine(private val context: Context) {

    companion object {
        private const val TAG = "LlmEngine"
        const val DEFAULT_MODEL_PATH = "/data/local/tmp/llm/model.task"
        const val MAX_TOKENS = 512
    }

    private var llm: LlmInference? = null
    private val lock = Semaphore(1) // One inference at a time

    @Volatile
    var isReady = false
        private set

    @Volatile
    var loadError: String? = null
        private set

    /**
     * Load the model. Call once from a background thread / coroutine.
     */
    suspend fun initialize(modelPath: String) = withContext(Dispatchers.IO) {
        Log.d(TAG, "Loading model from $modelPath")
        isReady = false
        loadError = null

        try {
            val options = LlmInference.LlmInferenceOptions.builder()
                .setModelPath(modelPath)
                .setMaxTokens(MAX_TOKENS)
                .setPreferredBackend(LlmInference.Backend.CPU)
                .build()

            llm?.close()
            llm = LlmInference.createFromOptions(context, options)
            isReady = true
            Log.d(TAG, "Model loaded OK")
        } catch (e: Exception) {
            loadError = e.message ?: "Unknown error"
            Log.e(TAG, "Failed to load model", e)
            throw e
        }
    }

    /**
     * Generate a response for [prompt]. Suspends until complete.
     * Serialized — concurrent callers queue up.
     */
    suspend fun generate(prompt: String): String = withContext(Dispatchers.IO) {
        val engine = llm ?: throw IllegalStateException("LLM not initialized")

        lock.acquire()
        try {
            Log.d(TAG, "Generating for prompt (${prompt.length} chars)")
            val result = engine.generateResponse(prompt)
            Log.d(TAG, "Generation done (${result.length} chars)")
            result
        } finally {
            lock.release()
        }
    }

    /**
     * Build a simple chat-style prompt from a list of messages.
     * Works with Gemma instruct models.
     */
    fun buildChatPrompt(messages: List<Pair<String, String>>): String {
        val sb = StringBuilder()
        for ((role, content) in messages) {
            when (role) {
                "system" -> sb.append("<start_of_turn>user\n[System: $content]\n<end_of_turn>\n")
                "user"   -> sb.append("<start_of_turn>user\n$content\n<end_of_turn>\n")
                "assistant" -> sb.append("<start_of_turn>model\n$content\n<end_of_turn>\n")
            }
        }
        sb.append("<start_of_turn>model\n")
        return sb.toString()
    }

    fun shutdown() {
        llm?.close()
        llm = null
        isReady = false
    }
}
