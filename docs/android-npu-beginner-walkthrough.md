# Android NPU server — step-by-step (beginner)

Use this if you’re new to Android. It gets the MediaPipe LLM Inference sample running on your Pixel and adds a small HTTP server so your VM can call the phone’s NPU.

---

## Before you start

- **Pixel** (or compatible device) with USB cable.
- **Mac** with Android Studio and `adb` (comes with Android Studio).
- You’ll **clone a Google sample**, add **one dependency**, add **two Kotlin files**, and add **a few lines** in one screen.

---

## Part 1: Install Android Studio and enable USB debugging

### 1.1 Install Android Studio

1. Go to [developer.android.com/studio](https://developer.android.com/studio) and download **Android Studio** for Mac.
2. Install it (drag to Applications, open it).
3. Run through the setup wizard (install SDK, create virtual device is optional).
4. You don’t need to create an app yet.

### 1.2 Enable developer options on the Pixel

1. On the phone: **Settings → About phone**.
2. Find **Build number**.
3. Tap **Build number** 7 times. You’ll see “You are now a developer.”

### 1.3 Turn on USB debugging

1. **Settings → System → Developer options** (or search “Developer options” in Settings).
2. Turn **Developer options** on.
3. Turn **USB debugging** on.
4. Plug the Pixel into the Mac with USB.
5. On the phone, when it asks “Allow USB debugging?” tap **Allow** (and optionally “Always allow from this computer”).

### 1.4 Check the connection

On the Mac, in Terminal:

```bash
adb devices
```

You should see your device listed. If it says “unauthorized”, check the phone for the USB debugging prompt again.

---

## Part 2: Get the sample app and run it

### 2.1 Clone the sample

In Terminal on your Mac:

```bash
cd ~/Projects
git clone https://github.com/google-ai-edge/mediapipe-samples
```

(Use another folder if you prefer; remember it for the next step.)

### 2.2 Open the project in Android Studio

1. Open **Android Studio**.
2. **File → Open**.
3. Go to the folder you used above and open:
   - **`mediapipe-samples/examples/llm_inference/android`**
   - Important: open the **`android`** folder inside `llm_inference`, not the repo root.
4. Click **Open**. Android Studio will index and sync (Gradle). Wait until the bottom status says “Gradle sync finished” (may take a few minutes the first time).

### 2.3 Run the app on the Pixel

1. Make sure the Pixel is plugged in and **adb devices** shows it.
2. At the top of Android Studio, in the device dropdown, select your **Pixel** (not an emulator).
3. Click the green **Run** (play) button.
4. The app will build, install, and open on the phone.
5. In the app: accept any licenses, pick a small model (e.g. **Gemma 2B** or **GEMMA_3_1B_IT_GPU**), download it if asked, and send one test message so you see a reply. Once that works, the in-app LLM is working.

### 2.4 If models won’t download in the app

The sample’s **GPU** model is **GEMMA_3_1B_IT_GPU** (Gemma 3 1B). It’s hosted on Hugging Face and is gated (you must accept the Gemma license once at [litert-community/Gemma3-1B-IT](https://huggingface.co/litert-community/Gemma3-1B-IT)).

**Option A — In-app download:** Accept the license at the link above, then in the app sign in with a [Hugging Face token](https://huggingface.co/settings/tokens). Retry the model download.

**Option B — Download on your Mac and push to the phone:** From the `pixel-edge-server` project (or wherever you have the scripts):

```bash
cd ~/Projects
# If the model is gated, set your Hugging Face token (create at https://huggingface.co/settings/tokens):
export HF_TOKEN="hf_xxxx"
./scripts/download-and-push-gpu-model.sh
```

That downloads the GPU model file and pushes it to the Pixel at `/data/local/tmp/`. Then in the app, select **GEMMA_3_1B_IT_GPU**; it should find the file and load without downloading. If `adb push` fails (e.g. permission denied on your device), use Option A or try `adb root` if your build allows it.

---

## Part 3: Add the HTTP server (so the VM can call the NPU)

We’ll add a tiny HTTP server inside the app that answers `POST /infer` with generated text. You’ll add **one dependency**, **two Kotlin files**, and **a few lines** in the chat screen.

### 3.1 Add the NanoHTTPD dependency

1. In Android Studio, in the **Project** view (left), expand:
   - **app**
2. Double‑click **build.gradle.kts** (under **app**).
3. Find the `dependencies { }` block (around the middle of the file).
4. Inside that block, add this line (you can add it after the existing `implementation(...)` lines):

   ```kotlin
   implementation("org.nanohttpd:nanohttpd:2.3.1")
   ```

5. Click **Sync Now** in the bar that appears (or **File → Sync Project with Gradle Files**).

### 3.2 Add the first Kotlin file: `HttpLlmServer.kt`

1. In the Project view, expand:
   - **app → src → main → java → com.google.mediapipe.examples.llminference**
2. Right‑click **llminference** → **New → Kotlin Class/File**.
3. Name it **HttpLlmServer** (leave “File” selected). Click **OK**.
4. Replace the entire contents of the new file with the code from **this repo’s** file:
   - **`android-npu-server/HttpLlmServer.kt`**
   - Path from your **pixel-edge-server** project: e.g. `~/Projects/android-npu-server/HttpLlmServer.kt` (or wherever you have the repo).
5. Save.

### 3.3 Add the second Kotlin file: `NpuInferenceBridge.kt`

The sample app’s LLM runs **asynchronously**. We need a small helper that runs it and **waits** for the result so the HTTP server can return it.

1. Right‑click **llminference** again → **New → Kotlin Class/File**.
2. Name it **NpuInferenceBridge**. Click **OK**.
3. Paste in the contents of **`android-npu-server/NpuInferenceBridge.kt`** from this repo (same place as `HttpLlmServer.kt`).
4. Save.

### 3.4 Start the server when the chat screen is open

We start the HTTP server only when the user is on the **chat** screen (model is already loaded).

1. Open **ChatScreen.kt** (under **app → src → main → java → … → llminference**).
2. Find **ChatRoute** (the `@Composable` that starts with `internal fun ChatRoute(`).
3. Right after the existing `LaunchedEffect(Unit) { ... }` that resets the inference model (the block that calls `chatViewModel.resetInferenceModel`), add a **second** `LaunchedEffect` and a `remember` to hold the server:

   - At the top of `ChatRoute`, with the other declarations (e.g. right after `val chatViewModel`), add:
     ```kotlin
     var llmServer by remember { mutableStateOf<HttpLlmServer?>(null) }
     ```
   - Add these imports at the top of the file if Android Studio doesn’t add them:
     ```kotlin
     import androidx.compose.runtime.mutableStateOf
     import androidx.compose.runtime.remember
     ```
   - Then add this block right after the first `LaunchedEffect(Unit) { ... }`:
     ```kotlin
     LaunchedEffect(Unit) {
         llmServer = HttpLlmServer(9090) { prompt ->
             NpuInferenceBridge.runBlockingInference(context, prompt)
         }
         llmServer?.start()
     }
     ```

4. Save and do **Build → Rebuild Project**. Fix any red underlines (imports or typo).

### 3.5 Run the app again and test from the Mac

1. Run the app on the Pixel again (green Run button). Open the chat screen (model loaded, you can type in the app).
2. On your Mac, in Terminal (Pixel still plugged in):

   ```bash
   adb shell "curl -sS -X POST http://127.0.0.1:9090/infer -H 'Content-Type: application/json' -d '{\"prompt\":\"Say hello in one word.\"}'"
   ```

3. You should get a JSON response with generated text, e.g. `{"text":"Hello"}`. If you do, the Android side is done.

---

## Part 4: Wire the VM (Phase 2)

Once the app is serving HTTP on port 9090:

1. From your Mac (with Tailscale or USB to the Pixel’s VM):
   ```bash
   cd ~/Projects
   ./scripts/setup-npu-openclaw.sh
   ```
2. In OpenClaw Mission Control you can then use the **npu-bridge/pixel-npu** model.

---

## Troubleshooting

| Problem | What to try |
|--------|------------------|
| **adb devices** shows nothing | Replug USB, unlock phone, tap “Allow” on the USB debugging dialog. Try another cable/port. |
| Gradle sync fails | **File → Invalidate Caches → Invalidate and Restart**. Check internet. |
| “Unresolved reference: HttpLlmServer” | Ensure `HttpLlmServer.kt` is in `app/.../llminference/` and the package at the top is `com.google.mediapipe.examples.llminference`. |
| “Unresolved reference: NanoHTTPD” | Add `implementation("org.nanohttpd:nanohttpd:2.3.1")` and sync Gradle again. |
| curl returns empty or connection refused | Make sure the app is **open on the phone** and you’re on the **chat** screen (model loaded). Keep the app in foreground for the test. |
| App crashes when sending a message from the app | Check that you didn’t remove or break the existing `LaunchedEffect` or ViewModel usage in `ChatRoute`. |

For more detail on what the scripts do, see **docs/npu-setup-checklist.md**.
