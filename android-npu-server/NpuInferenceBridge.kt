package com.google.mediapipe.examples.llminference

import android.content.Context
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

/**
 * Runs the app's LLM inference in a blocking way so the HTTP server can return the result.
 * Use this from HttpLlmServer's callback only when the model is already loaded (e.g. from ChatRoute).
 */
object NpuInferenceBridge {
    private const val TIMEOUT_SEC = 120
    private val executor = Executors.newSingleThreadExecutor()

    fun runBlockingInference(context: Context, prompt: String): String {
        val model = InferenceModel.getInstance(context)
        val resultHolder = AtomicReference<String>()
        val latch = CountDownLatch(1)
        val sb = StringBuilder()
        model.generateResponseAsync(prompt) { partialResult, done ->
            sb.append(partialResult)
            if (done) {
                resultHolder.set(sb.toString())
                latch.countDown()
            }
        }.addListener({ latch.countDown() }, executor)
        latch.await(TIMEOUT_SEC.toLong(), TimeUnit.SECONDS)
        return resultHolder.get() ?: sb.toString().ifEmpty { "timeout or no output" }
    }
}
