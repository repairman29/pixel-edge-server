package com.d6.jarvis

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Restarts JarvisService after device reboot if a token was previously configured.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return

        val prefs = context.getSharedPreferences("jarvis_prefs", Context.MODE_PRIVATE)
        val token = prefs.getString("telegram_token", "") ?: ""
        val modelPath = prefs.getString("model_path", LlmEngine.DEFAULT_MODEL_PATH)
            ?: LlmEngine.DEFAULT_MODEL_PATH

        // Only auto-start if we have a saved config
        if (modelPath.isNotEmpty()) {
            JarvisService.start(context, token, modelPath)
        }
    }
}
