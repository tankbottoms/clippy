#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION=$(grep '"version"' package.json | head -1 | sed 's/.*: "\(.*\)".*/\1/')
DIST="dist"
APP="$DIST/Clippy.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

echo "==> Building Clippy v${VERSION}"

# Clean previous build
rm -rf "$APP"
mkdir -p "$MACOS" "$RESOURCES"

# Compile Bun binary
echo "==> Compiling Bun daemon..."
bun build src/index.ts --compile --target=bun-darwin-arm64 --outfile "$MACOS/clippy"

# Compile Swift binary
echo "==> Compiling Swift status bar..."
swiftc -O \
  -o "$MACOS/ClippyBar" \
  swift/ClippyBar.swift \
  -framework AppKit \
  -framework SwiftUI \
  -target arm64-apple-macosx14.0

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
