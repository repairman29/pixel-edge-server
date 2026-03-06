#!/data/data/com.termux/files/usr/bin/bash
# Build Jarvis Android APK on Pixel

echo "=== Building Jarvis Android APK on Pixel ==="

# Setup directories
BUILD_DIR="$HOME/jarvis-build"
EXTRACT_DIR="$BUILD_DIR/source"
APK_OUTPUT="$BUILD_DIR/app-debug.apk"

echo "Creating build directory..."
mkdir -p "$BUILD_DIR"

echo "Extracting source code..."
if [ -f /sdcard/jarvis-android.tar.gz ]; then
    cd "$BUILD_DIR"
    tar xzf /sdcard/jarvis-android.tar.gz
    echo "✓ Source extracted"
else
    echo "✗ Source archive not found at /sdcard/jarvis-android.tar.gz"
    exit 1
fi

echo "Checking Java installation..."
if ! command -v java &> /dev/null; then
    echo "Installing OpenJDK..."
    pkg install -y openjdk-17
fi

echo "Java version: $(java -version 2>&1 | head -1)"

echo "Checking Gradle..."
if ! command -v gradle &> /dev/null; then
    echo "Installing Gradle..."
    pkg install -y gradle
fi

echo "Building APK..."
cd "$BUILD_DIR/jarvis-android"
export JAVA_HOME="/data/data/com.termux/files/usr/lib/jvm/java-17"
export ANDROID_HOME="$HOME/android-sdk"

# Build
echo "Running Gradle build..."
./gradlew clean assembleDebug 2>&1 | tee "$BUILD_DIR/build.log"

if [ -f app/build/outputs/apk/debug/app-debug.apk ]; then
    echo "✓ Build successful!"
    cp app/build/outputs/apk/debug/app-debug.apk "$APK_OUTPUT"
    echo "APK location: $APK_OUTPUT"
    
    echo ""
    echo "=== To install, run: ==="
    echo "adb install -r $APK_OUTPUT"
else
    echo "✗ Build failed. Check $BUILD_DIR/build.log"
    exit 1
fi
