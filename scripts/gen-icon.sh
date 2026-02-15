#!/usr/bin/env bash
# Generate Clippy .icns from barber-scissors PNG using ImageMagick
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT="${1:-$PROJECT_DIR/assets/AppIcon.icns}"
SRC="${2:-$PROJECT_DIR/assets/barber-scissors/barber-scissors-fill-100.png}"
TMPDIR=$(mktemp -d)
ICONSET="$TMPDIR/Clippy.iconset"
mkdir -p "$ICONSET"

if [ ! -f "$SRC" ]; then
  echo "Source image not found: $SRC" >&2
  exit 1
fi

# Generate all required icon sizes: white background, scissors centered at 65%
for spec in \
  "icon_16x16:16" \
  "icon_16x16@2x:32" \
  "icon_32x32:32" \
  "icon_32x32@2x:64" \
  "icon_128x128:128" \
  "icon_128x128@2x:256" \
  "icon_256x256:256" \
  "icon_256x256@2x:512" \
  "icon_512x512:512" \
  "icon_512x512@2x:1024"; do

  name="${spec%%:*}"
  px="${spec##*:}"
  inner=$(echo "$px * 65 / 100" | bc)

  magick -size "${px}x${px}" xc:white \
    \( "$SRC" -resize "${inner}x${inner}" \) \
    -gravity center -composite \
    -depth 8 "$ICONSET/${name}.png"
done

# Convert iconset to icns
iconutil -c icns "$ICONSET" -o "$OUTPUT"

# Cleanup
rm -rf "$TMPDIR"
echo "Icon written to $OUTPUT"
