package com.d6.jarvis

import android.content.Context
import android.util.Log
import com.google.mediapipe.tasks.genai.llminference.LlmInference
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.util.concurrent.Semaphore

/**
 * Wraps MediaPipe LlmInference with dual backend support (CPU & GPU/NPU).
 * Thread-safe: one inference at a time.
 * Auto-detects and uses GPU/NPU when available, falls back to CPU.
 */
class LlmEngine(private val context: Context) {

    companion object {
        private const val TAG = "LlmEngine"
        const val DEFAULT_MODEL_PATH = "/data/local/tmp/llm/model.task"
        const val MAX_TOKENS = 512
        
        enum class BackendPreference {
            AUTO,      // Try GPU first, fallback to CPU
            CPU,       // Force CPU only
            GPU        // Force GPU/NPU only
        }
    }

    private var llm: LlmInference? = null
    private val lock = Semaphore(1)

    @Volatile
    var isReady = false
        private set

    @Volatile
    var loadError: String? = null
        private set

    @Volatile
    var activeBackend: LlmInference.Backend? = null
        private set

    /**
     * Load the model with automatic backend detection.
     * Uses GPU/NPU if available, otherwise falls back to CPU.
     */
    suspend fun initialize(
        modelPath: String = DEFAULT_MODEL_PATH,
        preference: BackendPreference = BackendPreference.AUTO
    ) = withContext(Dispatchers.IO) {
        Log.d(TAG, "Loading model from $modelPath with preference: $preference")
        isReady = false
        loadError = null
        activeBackend = null

        when (preference) {
            BackendPreference.CPU -> initializeWithBackend(modelPath, LlmInference.Backend.CPU)
            BackendPreference.GPU -> initializeWithBackend(modelPath, LlmInference.Backend.GPU)
            BackendPreference.AUTO -> initializeAuto(modelPath)
        }
    }

    /**
     * Try GPU/NPU first, then fallback to CPU.
     */
    private fun initializeAuto(modelPath: String) {
        // Try GPU/NPU first
        try {
            Log.d(TAG, "Attempting to initialize with GPU/NPU backend...")
            initializeWithBackend(modelPath, LlmInference.Backend.GPU)
            Log.d(TAG, "Successfully initialized with GPU/NPU backend")
            return
        } catch (e: Exception) {
            Log.w(TAG, "GPU/NPU initialization failed: ${e.message}, falling back to CPU")
        }

        // Fallback to CPU
        try {
            Log.d(TAG, "Attempting to initialize with CPU backend...")
            initializeWithBackend(modelPath, LlmInference.Backend.CPU)
            Log.d(TAG, "Successfully initialized with CPU backend")
        } catch (e: Exception) {
            loadError = "Failed to initialize with both GPU and CPU: ${e.message}"
            Log.e(TAG, loadError!!, e)
            throw e
        }
    }

    /**
     * Initialize with specific backend.
     */
    private fun initializeWithBackend(modelPath: String, backend: LlmInference.Backend) {
        try {
            Log.d(TAG, "Configuring for ${if (backend == LlmInference.Backend.GPU) "GPU/NPU" else "CPU"} execution")

            val options = LlmInference.LlmInferenceOptions.builder()
                .setModelPath(modelPath)
                .setMaxTokens(MAX_TOKENS)
                .setPreferredBackend(backend)
                .build()

            llm?.close()
            llm = LlmInference.createFromOptions(context, options)
            activeBackend = backend
            isReady = true
            
            val backendName = when (backend) {
                LlmInference.Backend.GPU -> "GPU/NPU"
                LlmInference.Backend.CPU -> "CPU"
                else -> "UNKNOWN"
            }
            Log.d(TAG, "Model loaded successfully with $backendName backend")
            
        } catch (e: Exception) {
            loadError = "Failed to initialize with ${backend.name}: ${e.message}"
            Log.e(TAG, loadError!!, e)
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
            Log.d(TAG, "Generating for prompt (${prompt.length} chars) using ${activeBackend?.name ?: "unknown"} backend")
            val startTime = System.currentTimeMillis()
            val result = engine.generateResponse(prompt)
            val duration = System.currentTimeMillis() - startTime
            Log.d(TAG, "Generation done (${result.length} chars) in ${duration}ms")
            result
        } finally {
            lock.release()
        }
    }

    /**
     * Get current backend status for display.
     */
    fun getStatus(): String {
        return if (isReady) {
            val backend = when (activeBackend) {
                LlmInference.Backend.GPU -> "GPU/NPU (Tensor G3)"
                LlmInference.Backend.CPU -> "CPU"
                else -> "Unknown"
            }
            "Ready - Using $backend backend"
        } else {
            "Not ready${loadError?.let { ": $it" } ?: ""}"
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
        activeBackend = null
    }
}
