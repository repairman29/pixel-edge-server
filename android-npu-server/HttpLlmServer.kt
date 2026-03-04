package com.google.mediapipe.examples.llminference

import fi.iki.elonen.NanoHTTPD
import org.json.JSONObject
import java.util.*

/**
 * Minimal HTTP server on the Android host so the Debian VM can call NPU inference via:
 *   adb shell "curl -sS -X POST http://127.0.0.1:9090/infer -H 'Content-Type: application/json' -d '{\"prompt\":\"...\"}'"
 *
 * Add to your MediaPipe LLM Inference app:
 * 1. implementation("org.nanohttpd:nanohttpd:2.3.1") in app/build.gradle.kts
 * 2. In MainActivity (after LLM is loaded), start the server:
 *    llmServer = HttpLlmServer(9090) { prompt -> yourLlmInference.generateResponse(prompt) }
 *    llmServer.start()
 */
class HttpLlmServer(
    port: Int,
    private val generate: (String) -> String
) : NanoHTTPD(port) {

    override fun serve(session: IHTTPSession): Response {
        if (session.method != Method.POST) {
            return newFixedLengthResponse(Response.Status.METHOD_NOT_ALLOWED, "text/plain", "POST only")
        }
        if (!"/infer".equals(session.uri, ignoreCase = true)) {
            return newFixedLengthResponse(Response.Status.NOT_FOUND, "text/plain", "Use POST /infer")
        }
        val body = HashMap<String, String>()
        try {
            session.parseBody(body)
        } catch (e: Exception) {
            return newFixedLengthResponse(Response.Status.BAD_REQUEST, "application/json",
                """{"error":"parseBody: ${e.message}"}""")
        }
        val postData = body["postData"] ?: ""
        if (postData.isEmpty()) {
            return newFixedLengthResponse(Response.Status.BAD_REQUEST, "application/json",
                """{"error":"missing body"}""")
        }
        val prompt = try {
            JSONObject(postData).optString("prompt", "").takeIf { it.isNotBlank() }
        } catch (e: Exception) {
            null
        } ?: run {
            return newFixedLengthResponse(Response.Status.BAD_REQUEST, "application/json",
                """{"error":"missing or invalid prompt"}""")
        }
        return try {
            val text = generate(prompt)
            newChunkedResponse(Response.Status.OK, "application/json",
                """{"text":"${text.replace("\"", "\\\"").replace("\n", "\\n")}"}""")
        } catch (e: Exception) {
            newChunkedResponse(Response.Status.INTERNAL_ERROR, "application/json",
                """{"error":"inference: ${e.message}"}""")
        }
    }
}
