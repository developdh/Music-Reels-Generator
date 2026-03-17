#!/bin/bash
# yt_download.sh — External YouTube download script for Music Reels Generator
#
# Installation:
#   mkdir -p ~/Library/Application\ Support/MusicReelsGenerator/Scripts
#   cp yt_download.sh ~/Library/Application\ Support/MusicReelsGenerator/Scripts/
#   chmod +x ~/Library/Application\ Support/MusicReelsGenerator/Scripts/yt_download.sh
#
# Requirements:
#   brew install yt-dlp
#
# Usage (called by the app automatically):
#   yt_download.sh <URL> <OUTPUT_DIR>
#
# Protocol:
#   - Progress lines to stderr: PROGRESS:<percent>:<status text>
#   - Final file path to stdout
#   - Exit 0 on success, non-zero on failure

set -euo pipefail

URL="${1:?Usage: yt_download.sh <URL> <OUTPUT_DIR>}"
OUTPUT_DIR="${2:?Usage: yt_download.sh <URL> <OUTPUT_DIR>}"

# Find yt-dlp
YTDLP=""
for p in /opt/homebrew/bin/yt-dlp /usr/local/bin/yt-dlp; do
    if [ -x "$p" ]; then
        YTDLP="$p"
        break
    fi
done
if [ -z "$YTDLP" ]; then
    YTDLP=$(which yt-dlp 2>/dev/null || true)
fi
if [ -z "$YTDLP" ] || [ ! -x "$YTDLP" ]; then
    echo "yt-dlp not found. Install with: brew install yt-dlp" >&2
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

# Download with progress parsing
"$YTDLP" \
    "$URL" \
    -f "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best" \
    --merge-output-format mp4 \
    -o "${OUTPUT_DIR}/%(title)s.%(ext)s" \
    --newline \
    --no-playlist \
    2>&1 | while IFS= read -r line; do
        if echo "$line" | grep -q '\[download\]'; then
            pct=$(echo "$line" | grep -oE '[0-9]+\.?[0-9]*%' | head -1 | tr -d '%')
            if [ -n "$pct" ]; then
                echo "PROGRESS:${pct}:${line}" >&2
            fi
        fi
    done

# Find the downloaded file
DOWNLOADED=$(find "$OUTPUT_DIR" -type f \( -name "*.mp4" -o -name "*.mkv" -o -name "*.webm" -o -name "*.mov" \) | head -1)

if [ -z "$DOWNLOADED" ]; then
    echo "No output file found" >&2
    exit 1
fi

echo "$DOWNLOADED"
