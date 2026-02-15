#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION=$(grep '"version"' package.json | head -1 | sed 's/.*: "\(.*\)".*/\1/')
APP="dist/Clippy.app"
DMG="dist/Clippy-${VERSION}.dmg"
STAGING="dist/dmg-staging"
ICNS="$APP/Contents/Resources/AppIcon.icns"

if [ ! -d "$APP" ]; then
  echo "App bundle not found. Run scripts/build-app.sh first."
  exit 1
fi

echo "==> Creating DMG..."

# Clean
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"

# Stage app and symlink
cp -r "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

# Copy app icon as DMG volume icon
if [ -f "$ICNS" ]; then
  cp "$ICNS" "$STAGING/.VolumeIcon.icns"
fi

# Create read-write DMG first (needed to set volume icon flag)
RW_DMG="dist/.Clippy-rw.dmg"
hdiutil create -volname "Clippy" \
  -srcfolder "$STAGING" \
  -ov -format UDRW \
  "$RW_DMG"

# Mount, set volume icon flag, unmount
MOUNT_DIR=$(hdiutil attach -readwrite -noverify "$RW_DMG" | grep '/Volumes/' | awk -F'\t' '{print $NF}')
if [ -f "$MOUNT_DIR/.VolumeIcon.icns" ]; then
  SetFile -a C "$MOUNT_DIR" 2>/dev/null || true
fi
hdiutil detach "$MOUNT_DIR" -quiet

# Convert to compressed read-only DMG
hdiutil convert "$RW_DMG" -format UDZO -o "$DMG"
rm -f "$RW_DMG"
rm -rf "$STAGING"

DMG_SIZE=$(du -sh "$DMG" | cut -f1)
echo "==> DMG created: $DMG ($DMG_SIZE)"
