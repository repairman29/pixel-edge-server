package com.d6.jarvis

import android.content.*
import android.os.Bundle
import android.view.View
import android.widget.*
import androidx.appcompat.app.AppCompatActivity
import java.text.SimpleDateFormat
import java.util.*

/**
 * Main UI:
 *  - Telegram bot token input
 *  - Model path input
 *  - Start / Stop button
 *  - Live scrolling status log
 */
class MainActivity : AppCompatActivity() {

    companion object {
        private const val PREFS = "jarvis_prefs"
        private const val PREF_TOKEN = "telegram_token"
        private const val PREF_MODEL_PATH = "model_path"
    }

    private val prefs by lazy { getSharedPreferences(PREFS, Context.MODE_PRIVATE) }
    private val timeFormat = SimpleDateFormat("HH:mm:ss", Locale.US)

    // Views (using direct findViewById for zero dependencies)
    private lateinit var tokenInput: EditText
    private lateinit var modelPathInput: EditText
    private lateinit var startStopButton: Button
    private lateinit var statusLog: TextView
    private lateinit var scrollView: ScrollView
    private lateinit var statusDot: View

    private var isRunning = false

    // Receive status broadcasts from JarvisService
    private val statusReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val status = intent.getStringExtra(JarvisService.STATUS_KEY) ?: return
            appendLog(status)

            // Update running state from status messages
            when {
                status.contains("Stopped") -> setRunningState(false)
                status.contains("Running") || status.contains("✓") -> {
                    // Don't flip state on every ✓ but ensure dot is green while running
                    if (isRunning) updateDot(true)
                }
            }
        }
    }

    // ------------------------------------------------------------------
    // Lifecycle
    // ------------------------------------------------------------------

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        tokenInput = findViewById(R.id.tokenInput)
        modelPathInput = findViewById(R.id.modelPathInput)
        startStopButton = findViewById(R.id.startStopButton)
        statusLog = findViewById(R.id.statusLog)
        scrollView = findViewById(R.id.scrollView)
        statusDot = findViewById(R.id.statusDot)

        // Restore saved values (or use defaults)
        val defaultToken = BuildConfig.TELEGRAM_BOT_TOKEN
        tokenInput.setText(prefs.getString(PREF_TOKEN, defaultToken))
        modelPathInput.setText(
            prefs.getString(PREF_MODEL_PATH, LlmEngine.DEFAULT_MODEL_PATH)
        )

        startStopButton.setOnClickListener { onStartStopClicked() }

        appendLog("Jarvis ready. Configure token + model path, then tap Start.")
    }

    override fun onResume() {
        super.onResume()
        val filter = IntentFilter(JarvisService.BROADCAST_STATUS)
        registerReceiver(statusReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
    }

    override fun onPause() {
        super.onPause()
        unregisterReceiver(statusReceiver)
    }

    // ------------------------------------------------------------------
    // Start / Stop
    // ------------------------------------------------------------------

    private fun onStartStopClicked() {
        if (isRunning) {
            // Stop
            JarvisService.stop(this)
            setRunningState(false)
            appendLog("Stop requested…")
        } else {
            // Validate + start
            val token = tokenInput.text.toString().trim()
            val modelPath = modelPathInput.text.toString().trim()

            if (modelPath.isEmpty()) {
                appendLog("⚠️ Model path is required")
                return
            }

            // Save settings
            prefs.edit()
                .putString(PREF_TOKEN, token)
                .putString(PREF_MODEL_PATH, modelPath)
                .apply()

            if (token.isEmpty()) {
                appendLog("ℹ️ No Telegram token — will run HTTP API only")
            }

            JarvisService.start(this, token, modelPath)
            setRunningState(true)
            appendLog("Starting Jarvis…")
        }
    }

    // ------------------------------------------------------------------
    // UI helpers
    // ------------------------------------------------------------------

    private fun setRunningState(running: Boolean) {
        isRunning = running
        startStopButton.text = if (running) "STOP JARVIS" else "START JARVIS"
        startStopButton.setBackgroundColor(
            if (running)
                getColor(android.R.color.holo_red_dark)
            else
                getColor(android.R.color.holo_green_dark)
        )
        updateDot(running)
        tokenInput.isEnabled = !running
        modelPathInput.isEnabled = !running
    }

    private fun updateDot(active: Boolean) {
        statusDot.setBackgroundColor(
            if (active) getColor(android.R.color.holo_green_light)
            else getColor(android.R.color.darker_gray)
        )
    }

    private fun appendLog(message: String) {
        val time = timeFormat.format(Date())
        val line = "[$time] $message\n"
        statusLog.append(line)
        scrollView.post { scrollView.fullScroll(ScrollView.FOCUS_DOWN) }
    }
}
