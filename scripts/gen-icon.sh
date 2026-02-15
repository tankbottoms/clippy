#!/usr/bin/env bash
# Generate Clippy .icns using a Swift helper that renders scissors via AppKit
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT="${1:-AppIcon.icns}"
TMPDIR=$(mktemp -d)
ICONSET="$TMPDIR/Clippy.iconset"
GEN_BINARY="$TMPDIR/GenIcon"

# Compile the Swift icon generator
swiftc -O -o "$GEN_BINARY" "$SCRIPT_DIR/GenIcon.swift" \
  -framework AppKit -target arm64-apple-macosx14.0

# Generate all icon sizes into the iconset
"$GEN_BINARY" "$ICONSET"

# Convert iconset to icns
iconutil -c icns "$ICONSET" -o "$OUTPUT"

# Cleanup
rm -rf "$TMPDIR"
echo "Icon written to $OUTPUT"
