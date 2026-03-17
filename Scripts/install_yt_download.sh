#!/bin/bash
# Install yt_download.sh to enable YouTube download in Music Reels Generator
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEST_DIR="$HOME/Library/Application Support/MusicReelsGenerator/Scripts"

mkdir -p "$DEST_DIR"
cp "$SCRIPT_DIR/yt_download.sh" "$DEST_DIR/yt_download.sh"
chmod +x "$DEST_DIR/yt_download.sh"

echo "Installed to: $DEST_DIR/yt_download.sh"
echo ""

# Check yt-dlp
if command -v yt-dlp &>/dev/null; then
    echo "yt-dlp found: $(which yt-dlp)"
else
    echo "WARNING: yt-dlp not found. Install with: brew install yt-dlp"
fi

echo ""
echo "Done! Restart the app to enable URL Import."
