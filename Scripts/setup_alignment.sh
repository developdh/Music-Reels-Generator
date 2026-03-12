#!/bin/bash
# Setup script for the advanced alignment pipeline
# Installs Python dependencies required for character-level forced alignment

set -e

echo "=== Music Reels Generator: Advanced Alignment Setup ==="
echo ""

# Check Python 3
if ! command -v python3 &> /dev/null; then
    echo "ERROR: python3 not found. Install with: brew install python3"
    exit 1
fi

PYTHON_VERSION=$(python3 --version 2>&1)
echo "Found: $PYTHON_VERSION"

# Check pip
if ! python3 -m pip --version &> /dev/null; then
    echo "ERROR: pip not found. Install with: python3 -m ensurepip"
    exit 1
fi

echo ""
echo "Installing required packages..."
python3 -m pip install --upgrade pip
python3 -m pip install openai-whisper numpy pykakasi

echo ""
echo "=== Required packages installed ==="
echo ""

# Optional: demucs for vocal separation
read -p "Install demucs for vocal separation? (recommended for Accurate/Maximum modes) [y/N] " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Installing demucs (this may take a while due to large model downloads)..."
    python3 -m pip install demucs
    echo "Demucs installed."
else
    echo "Skipping demucs. You can install later with: pip3 install demucs"
fi

echo ""
echo "=== Setup complete ==="
echo ""
echo "The advanced alignment pipeline is ready."
echo "Whisper models will be downloaded automatically on first use."
echo ""
echo "Available modes:"
echo "  Fast:    whisper base model, character-level DTW"
echo "  Balanced: whisper medium model, chunked alignment + global DP"
echo "  Accurate: whisper large-v3, vocal separation, collapse recovery"
echo "  Maximum:  all features + extended search + pitch priors"
