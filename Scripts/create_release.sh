#!/bin/bash
# Build, package, sign, and create a GitHub release with Sparkle appcast
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

APP_NAME="Music Reels Generator"
EXECUTABLE="MusicReelsGenerator"
BUILD_DIR=".build"
APP_DIR="$BUILD_DIR/${APP_NAME}.app"
GITHUB_REPO="developdh/Music-Reels-Generator"

VERSION=$(cat VERSION | tr -d '[:space:]')
TAG="v${VERSION}"

echo "=== Creating Release ${TAG} ==="

# Check for uncommitted changes
if ! git diff --quiet HEAD; then
    echo "ERROR: Uncommitted changes. Commit first."
    exit 1
fi

# Check tag doesn't already exist
if git rev-parse "$TAG" >/dev/null 2>&1; then
    echo "ERROR: Tag $TAG already exists. Update VERSION file first."
    exit 1
fi

# Build release
echo ""
echo "--- Building ---"
swift build -c release 2>&1 | grep -v "^warning: could not determine XCTest"

# Create .app bundle (release config)
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
mkdir -p "$APP_DIR/Contents/Frameworks"

cp "$BUILD_DIR/release/$EXECUTABLE" "$APP_DIR/Contents/MacOS/$EXECUTABLE"

# Embed Sparkle.framework
SPARKLE_FRAMEWORK=$(find "$BUILD_DIR" -name "Sparkle.framework" -path "*/macos*" -type d 2>/dev/null | head -1)
if [ -z "$SPARKLE_FRAMEWORK" ]; then
    SPARKLE_FRAMEWORK=$(find "$BUILD_DIR" -name "Sparkle.framework" -type d 2>/dev/null | head -1)
fi
if [ -n "$SPARKLE_FRAMEWORK" ]; then
    cp -R "$SPARKLE_FRAMEWORK" "$APP_DIR/Contents/Frameworks/"
    install_name_tool -add_rpath @executable_path/../Frameworks "$APP_DIR/Contents/MacOS/$EXECUTABLE" 2>/dev/null || true
else
    echo "WARNING: Sparkle.framework not found"
fi

if [ -f "AppIcon.icns" ]; then
    cp AppIcon.icns "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

# Build number
BUILD_NUMBER=$(date +%s)
APPCAST_URL="https://raw.githubusercontent.com/${GITHUB_REPO}/main/appcast.xml"

# EdDSA public key
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
    <string>com.musicreels.generator</string>
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

# Create ZIP archive
echo ""
# Sign the entire .app bundle
codesign --force --sign - --deep "$APP_DIR"

echo "--- Packaging ---"
RELEASE_DIR="$BUILD_DIR/release-package"
rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"

ZIP_NAME="MusicReelsGenerator-${VERSION}.zip"
cd "$BUILD_DIR"
ditto -c -k --keepParent "${APP_NAME}.app" "release-package/${ZIP_NAME}"
cd "$PROJECT_DIR"

ZIP_PATH="$RELEASE_DIR/$ZIP_NAME"
ZIP_SIZE=$(stat -f%z "$ZIP_PATH")
echo "Archive: $ZIP_PATH ($ZIP_SIZE bytes)"

# Sign with EdDSA
echo ""
echo "--- Signing ---"
SIGN_UPDATE=$(find "$BUILD_DIR" -name "sign_update" -type f 2>/dev/null | head -1)

SIGNATURE=""
if [ -n "$SIGN_UPDATE" ]; then
    SIGN_OUTPUT=$("$SIGN_UPDATE" "$ZIP_PATH" 2>&1) || true
    # Extract edSignature and length from output
    ED_SIGNATURE=$(echo "$SIGN_OUTPUT" | grep -oP 'sparkle:edSignature="\K[^"]+' 2>/dev/null || echo "$SIGN_OUTPUT" | grep -oE 'edSignature="[^"]+"' | sed 's/edSignature="//;s/"//' || true)
    if [ -n "$ED_SIGNATURE" ]; then
        SIGNATURE="sparkle:edSignature=\"${ED_SIGNATURE}\" length=\"${ZIP_SIZE}\""
        echo "Signature: $ED_SIGNATURE"
    else
        echo "sign_update output: $SIGN_OUTPUT"
        echo "WARNING: Could not parse signature. Add it manually to appcast.xml"
    fi
else
    echo "WARNING: sign_update tool not found. Run sparkle_setup.sh first."
    echo "You'll need to sign the archive manually and update appcast.xml."
fi

# Generate/update appcast.xml
echo ""
echo "--- Generating appcast.xml ---"
DOWNLOAD_URL="https://github.com/${GITHUB_REPO}/releases/download/${TAG}/${ZIP_NAME}"
PUB_DATE=$(date -R)

cat > appcast.xml << APPCAST
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
    <channel>
        <title>${APP_NAME}</title>
        <link>https://github.com/${GITHUB_REPO}</link>
        <description>Most recent changes with links to updates.</description>
        <language>en</language>
        <item>
            <title>Version ${VERSION}</title>
            <pubDate>${PUB_DATE}</pubDate>
            <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
            <enclosure
                url="${DOWNLOAD_URL}"
                ${SIGNATURE}
                type="application/octet-stream"
            />
        </item>
    </channel>
</rss>
APPCAST

echo "appcast.xml updated for version $VERSION"

# Create git tag
echo ""
echo "--- Creating tag ${TAG} ---"
git tag -a "$TAG" -m "Release ${VERSION}"

echo ""
echo "=== Release Package Ready ==="
echo ""
echo "Next steps:"
echo "  1. git push origin main --tags"
echo "  2. Upload the ZIP to GitHub release:"
echo "     gh release create $TAG $ZIP_PATH --title \"$TAG\" --generate-notes"
echo "  3. Commit and push appcast.xml:"
echo "     git add appcast.xml && git commit -m 'Update appcast for $TAG' && git push"
