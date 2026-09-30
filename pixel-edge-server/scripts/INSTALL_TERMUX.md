# Install Termux when `adb install` doesn’t finish

If `adb install` hangs (waiting for a prompt on the phone), install from the device instead.

## 1. Push APK to the Pixel

From your Mac (Pixel connected via USB):

```bash
cd pixel-edge-server
adb push scripts/apks/termux_arm64.apk /sdcard/Download/termux_arm64.apk
```

## 2. On the Pixel

1. Open **Files** (or your file manager).
2. Go to **Download**.
3. Tap **termux_arm64.apk**.
4. If asked “Allow from this source?”, enable it and confirm.
5. Tap **Install**, then **Open**.

Termux should now be installed. Open it and run `pkg update -y && pkg install -y termux-api`, then `termux-battery-status` to verify Phase 1.
