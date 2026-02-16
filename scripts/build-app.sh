#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

ARCH="${1:-arm64}"
VERSION=$(grep '"version"' package.json | head -1 | sed 's/.*: "\(.*\)".*/\1/')
DIST="dist"

case "$ARCH" in
  arm64)
    BUN_TARGET="bun-darwin-arm64"
    SWIFT_TARGET="arm64-apple-macosx14.0"
    APP="$DIST/Clippy.app"
    ;;
  x86_64|x64|intel)
    ARCH="x86_64"
    BUN_TARGET="bun-darwin-x64"
    SWIFT_TARGET="x86_64-apple-macosx14.0"
    APP="$DIST/Clippy-x86_64.app"
    ;;
  *)
    echo "Usage: $0 [arm64|x86_64]" >&2
    exit 1
    ;;
esac

CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

echo "==> Building Clippy v${VERSION} ($ARCH)"

# Clean previous build
rm -rf "$APP"
mkdir -p "$MACOS" "$RESOURCES"

# Compile Bun binary
echo "==> Compiling Bun daemon ($BUN_TARGET)..."
bun build src/index.ts --compile --target="$BUN_TARGET" --outfile "$MACOS/clippy"

# Compile Swift binary
echo "==> Compiling Swift status bar ($SWIFT_TARGET)..."
swiftc -O \
  -o "$MACOS/ClippyBar" \
  swift/ClippyBar.swift \
  -framework AppKit \
  -framework SwiftUI \
  -target "$SWIFT_TARGET"

# Create Info.plist
cat > "$CONTENTS/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>clippy</string>
    <key>CFBundleIdentifier</key>
    <string>com.clippy.app</string>
    <key>CFBundleName</key>
    <string>Clippy</string>
    <key>CFBundleDisplayName</key>
    <string>Clippy</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleSignature</key>
    <string>CLIP</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# Copy app icon
if [ -f "assets/AppIcon.icns" ]; then
  cp assets/AppIcon.icns "$RESOURCES/AppIcon.icns"
  echo "==> Icon copied"
fi

# Ad-hoc code sign
echo "==> Code signing..."
codesign --force --deep --sign - "$APP"

# Print summary
APP_SIZE=$(du -sh "$APP" | cut -f1)
echo ""
echo "==> Build complete: $APP ($APP_SIZE)"
echo "    Install:   cp -r $APP /Applications/"
echo "    Or run:    open $APP"
