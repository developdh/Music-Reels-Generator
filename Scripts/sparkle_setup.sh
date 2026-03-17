#!/bin/bash
# One-time setup: Generate EdDSA key pair for Sparkle update signing
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
KEY_DIR="$HOME/Library/Application Support/MusicReelsGenerator"

# Find Sparkle's generate_keys tool
GENERATE_KEYS=$(find "$PROJECT_DIR/.build" -name "generate_keys" -type f 2>/dev/null | head -1)

if [ -z "$GENERATE_KEYS" ]; then
    echo "Sparkle generate_keys tool not found."
    echo "Run 'swift build' first to download Sparkle, then re-run this script."
    exit 1
fi

mkdir -p "$KEY_DIR"

echo "=== Generating Sparkle EdDSA Key Pair ==="
echo ""
echo "This will generate an Ed25519 key pair for signing app updates."
echo "The PRIVATE key is stored in your Keychain (keep it safe!)."
echo "The PUBLIC key will be saved to: $KEY_DIR/sparkle_eddsa_public.key"
echo ""

# generate_keys outputs the public key to stdout and stores private key in Keychain
PUBLIC_KEY=$("$GENERATE_KEYS" 2>&1 | grep -oE '[A-Za-z0-9+/=]{40,}' | head -1)

if [ -n "$PUBLIC_KEY" ]; then
    echo "$PUBLIC_KEY" > "$KEY_DIR/sparkle_eddsa_public.key"
    echo ""
    echo "=== Setup Complete ==="
    echo "Public key: $PUBLIC_KEY"
    echo "Saved to:   $KEY_DIR/sparkle_eddsa_public.key"
    echo ""
    echo "build.sh will automatically embed this key in Info.plist."
else
    echo "WARNING: Could not extract public key. Run generate_keys manually:"
    echo "  $GENERATE_KEYS"
fi
