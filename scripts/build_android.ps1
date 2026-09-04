$ErrorActionPreference = "Stop"

# Configuration
$NDK_PATH = $env:ANDROID_NDK_HOME
if (-not $NDK_PATH) {
    Write-Error "ANDROID_NDK_HOME environment variable is not set."
}

$BUILD_DIR = "build-android-arm64"
$ARTIFACTS_DIR = "artifacts/android/arm64-v8a"

# Clean build directory
if (Test-Path $BUILD_DIR) {
    Remove-Item -Recurse -Force $BUILD_DIR
}
New-Item -ItemType Directory -Force $BUILD_DIR | Out-Null

# Configure CMake
Write-Host "Configuring CMake..."
cmake -G "Ninja" -S . -B $BUILD_DIR `
    -DCMAKE_TOOLCHAIN_FILE="$NDK_PATH/build/cmake/android.toolchain.cmake" `
    -DANDROID_ABI="arm64-v8a" `
    -DANDROID_PLATFORM="android-21" `
    -DCMAKE_BUILD_TYPE="Release"

# Build Release
Write-Host "Building Release..."
cmake --build $BUILD_DIR --config Release

# Copy Release Artifact
$RELEASE_DIR = "$ARTIFACTS_DIR/release"
New-Item -ItemType Directory -Force $RELEASE_DIR | Out-Null
Copy-Item "$BUILD_DIR/libllama.so" $RELEASE_DIR
Write-Host "Release artifact copied to $RELEASE_DIR"

# Re-configure for Debug (optional, or just build debug in separate dir)
# For simplicity, let's just build Release first as per primary requirement.
# The task asks for both. Let's do Debug in a separate dir.

$BUILD_DIR_DEBUG = "build-android-arm64-debug"
if (Test-Path $BUILD_DIR_DEBUG) {
    Remove-Item -Recurse -Force $BUILD_DIR_DEBUG
}
New-Item -ItemType Directory -Force $BUILD_DIR_DEBUG | Out-Null

Write-Host "Configuring CMake (Debug)..."
cmake -G "Ninja" -S . -B $BUILD_DIR_DEBUG `
    -DCMAKE_TOOLCHAIN_FILE="$NDK_PATH/build/cmake/android.toolchain.cmake" `
    -DANDROID_ABI="arm64-v8a" `
    -DANDROID_PLATFORM="android-21" `
    -DCMAKE_BUILD_TYPE="Debug"

Write-Host "Building Debug..."
cmake --build $BUILD_DIR_DEBUG --config Debug

# Copy Debug Artifact
$DEBUG_DIR = "$ARTIFACTS_DIR/debug"
New-Item -ItemType Directory -Force $DEBUG_DIR | Out-Null
Copy-Item "$BUILD_DIR_DEBUG/libllama.so" $DEBUG_DIR
Write-Host "Debug artifact copied to $DEBUG_DIR"

# Copy libomp.so (OpenMP runtime)
$LIBOMP_PATH = "$NDK_PATH/toolchains/llvm/prebuilt/windows-x86_64/lib/clang/21/lib/linux/aarch64/libomp.so"
if (-not (Test-Path $LIBOMP_PATH)) {
    Write-Warning "libomp.so not found at $LIBOMP_PATH. Trying to find it dynamically..."
    $LIBOMP_PATH = Get-ChildItem -Path "$NDK_PATH" -Recurse -Filter "libomp.so" | Where-Object { $_.FullName -like "*aarch64*" } | Select-Object -ExpandProperty FullName | Select-Object -First 1
}

if ($LIBOMP_PATH -and (Test-Path $LIBOMP_PATH)) {
    Write-Host "Found libomp.so at $LIBOMP_PATH"
    
    # Copy to artifacts
    Copy-Item $LIBOMP_PATH "$ARTIFACTS_DIR/release/" -Force
    Copy-Item $LIBOMP_PATH "$ARTIFACTS_DIR/debug/" -Force
    
    # Copy to App jniLibs
    $APP_JNI_DIR = "app/android/app/src/main/jniLibs/arm64-v8a"
    if (-not (Test-Path $APP_JNI_DIR)) {
        New-Item -ItemType Directory -Force $APP_JNI_DIR | Out-Null
    }
    Copy-Item $LIBOMP_PATH $APP_JNI_DIR -Force
    Write-Host "libomp.so copied to $APP_JNI_DIR"
} else {
    Write-Error "Could not find libomp.so in NDK. Please check NDK installation."
}

Write-Host "Build complete."
