#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

APP="dist/Clippy.app"

if [ ! -d "$APP" ]; then
  echo "App bundle not found. Building first..."
  bash scripts/build-app.sh
fi

# Kill running instance if any
if [ -f ~/.clippy/clippy.pid ]; then
  PID=$(cat ~/.clippy/clippy.pid 2>/dev/null || true)
  if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
    echo "==> Stopping running Clippy (pid $PID)..."
    kill "$PID" 2>/dev/null || true
    sleep 1
  fi
fi

# Install to /Applications
echo "==> Installing to /Applications/Clippy.app..."
rm -rf /Applications/Clippy.app
cp -r "$APP" /Applications/Clippy.app

echo "==> Installed."
echo ""

# Ask about login item
read -rp "Start Clippy on login? [y/N] " REPLY
if [[ "$REPLY" =~ ^[Yy]$ ]]; then
  bash scripts/login-item.sh install
fi

echo ""
echo "Launch with: open /Applications/Clippy.app"
