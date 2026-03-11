#!/bin/bash
set -e

APP_NAME="Music Reels Generator"
BUNDLE_ID="com.musicreels.generator"
EXECUTABLE="MusicReelsGenerator"
BUILD_DIR=".build"
APP_DIR="$BUILD_DIR/${APP_NAME}.app"

echo "=== Building $APP_NAME ==="

# Build the executable
swift build 2>&1 | grep -v "^warning: could not determine XCTest"

# Create .app bundle structure
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# Copy executable
cp "$BUILD_DIR/debug/$EXECUTABLE" "$APP_DIR/Contents/MacOS/$EXECUTABLE"

# Copy app icon
if [ -f "AppIcon.icns" ]; then
    cp AppIcon.icns "$APP_DIR/Contents/Resources/AppIcon.icns"
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
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
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
echo "App bundle: $APP_DIR"
echo ""
echo "Run with:  open \"$APP_DIR\""
