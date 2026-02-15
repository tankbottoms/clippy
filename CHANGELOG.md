# Changelog

## [0.1.0] - 2026-02-15

Initial prototype. Text-only clipboard monitoring with encrypted storage and auto-wipe.

### Added

- Clipboard monitoring via `pbpaste` polling with SHA-256 change detection
- AES-256-GCM encryption with key stored in macOS Keychain
- SQLite storage with WAL mode, content deduplication by hash
- Configurable auto-wipe countdown (default 5 seconds)
- Native Swift menu bar app (`✂` icon with countdown display)
- Clipboard history menu with click-to-copy
- Pause/resume countdown controls
- Unix domain socket IPC with NDJSON framing
- Periodic history pruning by entry count and age
- PID lock to prevent multiple instances
- `.app` bundle build with ad-hoc code signing
- DMG installer with scissors volume icon
- Start-on-login via LaunchAgent
- Install/uninstall scripts
- 31 unit tests covering crypto, db, config, IPC protocol, wiper, cleanup
