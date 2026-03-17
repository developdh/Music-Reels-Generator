#!/bin/bash
set -e

APP_NAME="Music Reels Generator"
BUNDLE_ID="com.musicreels.generator"
EXECUTABLE="MusicReelsGenerator"
BUILD_DIR=".build"
APP_DIR="$BUILD_DIR/${APP_NAME}.app"

# Read version from VERSION file
VERSION=$(cat VERSION | tr -d '[:space:]')
# Build number: seconds since epoch for unique monotonic builds
BUILD_NUMBER=$(date +%s)

APPCAST_URL="https://raw.githubusercontent.com/developdh/Music-Reels-Generator/main/appcast.xml"

echo "=== Building $APP_NAME v${VERSION} (${BUILD_NUMBER}) ==="

# Build the executable
swift build 2>&1 | grep -v "^warning: could not determine XCTest"

# Create .app bundle structure
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
mkdir -p "$APP_DIR/Contents/Frameworks"

# Copy executable
cp "$BUILD_DIR/debug/$EXECUTABLE" "$APP_DIR/Contents/MacOS/$EXECUTABLE"

# Embed Sparkle.framework
SPARKLE_FRAMEWORK=$(find "$BUILD_DIR" -name "Sparkle.framework" -path "*/macos*" -type d 2>/dev/null | head -1)
if [ -z "$SPARKLE_FRAMEWORK" ]; then
    # Fallback: search all artifacts
    SPARKLE_FRAMEWORK=$(find "$BUILD_DIR" -name "Sparkle.framework" -type d 2>/dev/null | head -1)
fi

if [ -n "$SPARKLE_FRAMEWORK" ]; then
    echo "Embedding Sparkle.framework from: $SPARKLE_FRAMEWORK"
    cp -R "$SPARKLE_FRAMEWORK" "$APP_DIR/Contents/Frameworks/"
    # Add rpath so the executable can find the framework at runtime
    install_name_tool -add_rpath @executable_path/../Frameworks "$APP_DIR/Contents/MacOS/$EXECUTABLE" 2>/dev/null || true
else
    echo "WARNING: Sparkle.framework not found — auto-update will not work"
fi

# Copy app icon
if [ -f "AppIcon.icns" ]; then
    cp AppIcon.icns "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

# Read EdDSA public key if available
ED_KEY_FILE="$HOME/Library/Application Support/MusicReelsGenerator/sparkle_eddsa_public.key"
SUPublicEDKey=""
if [ -f "$ED_KEY_FILE" ]; then
    SUPublicEDKey=$(cat "$ED_KEY_FILE" | tr -d '[:space:]')
fi

# Generate Info.plist
cat > "$APP_DIR/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleExecutable</key>
    <string>${EXECUTABLE}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.video</string>
    <key>SUFeedURL</key>
    <string>${APPCAST_URL}</string>
    <key>SUPublicEDKey</key>
    <string>${SUPublicEDKey}</string>
    <key>SUEnableAutomaticChecks</key>
    <true/>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>Music Reels Project</string>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>mreels</string>
            </array>
            <key>CFBundleTypeRole</key>
            <string>Editor</string>
        </dict>
    </array>
</dict>
</plist>
PLIST

echo ""
echo "=== Build Complete ==="
echo "Version: $VERSION (build $BUILD_NUMBER)"
echo "App bundle: $APP_DIR"
echo ""
echo "Run with:  open \"$APP_DIR\""
