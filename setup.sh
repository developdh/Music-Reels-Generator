#!/bin/bash
set -e

echo "=== Music Reels Generator - Setup ==="
echo ""

# Check for Homebrew
if ! command -v brew &> /dev/null; then
    echo "ERROR: Homebrew not found. Install from https://brew.sh"
    exit 1
fi
echo "✓ Homebrew found"

# Install FFmpeg
if command -v ffmpeg &> /dev/null; then
    echo "✓ FFmpeg found: $(which ffmpeg)"
else
    echo "Installing FFmpeg..."
    brew install ffmpeg
    echo "✓ FFmpeg installed"
fi

# Install whisper-cpp
if command -v whisper-cpp &> /dev/null; then
    echo "✓ whisper-cpp found: $(which whisper-cpp)"
else
    echo "Installing whisper-cpp..."
    brew install whisper-cpp
    echo "✓ whisper-cpp installed"
fi

# Download whisper model if not present
MODEL_DIR="$HOME/.local/share/whisper-cpp/models"
MODEL_FILE="$MODEL_DIR/ggml-medium.bin"

if [ -f "$MODEL_FILE" ]; then
    echo "✓ Whisper model found: $MODEL_FILE"
else
    echo "Downloading whisper medium model (1.5 GB)..."
    mkdir -p "$MODEL_DIR"

    # Try using whisper-cpp's download script if available
    if command -v whisper-cpp-download-ggml-model &> /dev/null; then
        whisper-cpp-download-ggml-model medium "$MODEL_DIR"
    else
        # Direct download
        curl -L "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin" \
            -o "$MODEL_FILE" \
            --progress-bar
    fi

    if [ -f "$MODEL_FILE" ]; then
        echo "✓ Whisper model downloaded"
    else
        echo "WARNING: Could not download model. You'll need to manually download ggml-medium.bin to $MODEL_DIR"
    fi
fi

echo ""
echo "=== Setup Complete ==="
echo ""
echo "To build and run:"
echo "  Option 1 (Xcode):   open MusicReelsGenerator.xcodeproj"
echo "  Option 2 (CLI):     swift build && .build/debug/MusicReelsGenerator"
echo ""
