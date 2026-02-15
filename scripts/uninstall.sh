#!/usr/bin/env bash
set -euo pipefail

echo "==> Uninstalling Clippy..."

# Stop running instance
if [ -f ~/.clippy/clippy.pid ]; then
  PID=$(cat ~/.clippy/clippy.pid 2>/dev/null || true)
  if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
    echo "    Stopping daemon (pid $PID)..."
    kill "$PID" 2>/dev/null || true
    sleep 1
  fi
fi

# Remove login item
if [ -f "$(dirname "$0")/login-item.sh" ]; then
  bash "$(dirname "$0")/login-item.sh" uninstall 2>/dev/null || true
fi

# Remove app bundle
if [ -d /Applications/Clippy.app ]; then
  echo "    Removing /Applications/Clippy.app..."
  rm -rf /Applications/Clippy.app
fi

# Remove Keychain entry
echo "    Removing Keychain entry..."
security delete-generic-password -s com.clippy.encryption -a clippy-aes-key 2>/dev/null || true

# Ask about data
read -rp "Remove clipboard history and config (~/.clippy/)? [y/N] " REPLY
if [[ "$REPLY" =~ ^[Yy]$ ]]; then
  echo "    Removing ~/.clippy/..."
  rm -rf ~/.clippy
else
  # Clean up runtime files but keep data
  rm -f ~/.clippy/clippy.pid ~/.clippy/clippy.sock ~/.clippy/ClippyBar
fi

echo "==> Clippy uninstalled."
