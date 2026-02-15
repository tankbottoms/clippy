#!/usr/bin/env bash
# Generate Clippy .icns from the scissors SVG using a Swift helper
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT="${1:-AppIcon.icns}"
SVG="${2:-$PROJECT_DIR/assets/scissors.svg}"
TMPDIR=$(mktemp -d)
ICONSET="$TMPDIR/Clippy.iconset"
GEN_BINARY="$TMPDIR/GenIcon"

# Compile the Swift icon generator
swiftc -O -o "$GEN_BINARY" "$SCRIPT_DIR/GenIcon.swift" \
  -framework AppKit -target arm64-apple-macosx14.0

# Generate all icon sizes into the iconset
"$GEN_BINARY" "$ICONSET" "$SVG"

# Convert iconset to icns
iconutil -c icns "$ICONSET" -o "$OUTPUT"

# Cleanup
rm -rf "$TMPDIR"
echo "Icon written to $OUTPUT"
