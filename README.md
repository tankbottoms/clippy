# Clippy

Clipboard security monitor for macOS. Watches your clipboard, encrypts and stores history in SQLite, and auto-wipes the clipboard after a configurable countdown.

Lives in the menu bar as `✂` with a countdown timer.

## Features

- **Clipboard monitoring** -- polls `pbpaste` at 500ms intervals with SHA-256 change detection
- **Encrypted storage** -- AES-256-GCM via Web Crypto API, key stored in macOS Keychain
- **Auto-wipe** -- configurable countdown (default 5s), clears clipboard when timer reaches zero
- **Menu bar UI** -- native Swift status bar app showing countdown, history, and controls
- **Deduplication** -- identical clipboard content is stored once, `accessed_at` updated on re-copy
- **Auto-cleanup** -- prunes history by entry count (1000) and age (30 days)
- **IPC** -- Unix domain socket with NDJSON framing between daemon and UI

## Install

### From DMG

Download `Clippy-x.x.x.dmg` from releases, open it, drag Clippy to Applications.

### From source

```bash
git clone https://github.com/user/clippy.git
cd clippy
bun install
bun run build:app
bun run install
```

## Usage

Launch from Applications or run directly:

```bash
# From app bundle
open /Applications/Clippy.app

# Development mode (auto-reload)
bun run dev

# Direct run
bun run start
```

The scissors icon `✂` appears in the menu bar. When you copy text:

1. Content is encrypted and stored in `~/.clippy/clippy.db`
2. Countdown appears: `✂ 5s` ... `✂ 4s` ... `✂ 1s`
3. Clipboard is cleared when the timer hits zero

Click the menu bar icon to:

- View clipboard history (click an item to copy it back)
- Pause/resume the countdown
- Clear clipboard immediately
- Clear all history
- Quit

## Configuration

Config lives at `~/.clippy/config.json`:

```json
{
  "wipeDelay": 5,
  "maxContentLength": 10000,
  "maxHistoryEntries": 1000,
  "maxHistoryAge": 30,
  "pollInterval": 500,
  "historyDisplayCount": 20,
  "previewLength": 50
}
```

| Field | Default | Description |
|-------|---------|-------------|
| `wipeDelay` | `5` | Seconds before clipboard auto-wipe |
| `maxContentLength` | `10000` | Truncate content beyond this length |
| `maxHistoryEntries` | `1000` | Maximum stored entries |
| `maxHistoryAge` | `30` | Days before entries are pruned |
| `pollInterval` | `500` | Clipboard polling interval (ms) |
| `historyDisplayCount` | `20` | Entries shown in menu |
| `previewLength` | `50` | Characters shown per history item |

## Architecture

```
┌─────────────────────────────────┐
│  ClippyBar.swift (menu bar UI)  │
│  NSStatusBar + Unix socket      │
└──────────┬──────────────────────┘
           │ NDJSON over Unix socket
┌──────────┴──────────────────────┐
│  Bun/TypeScript daemon          │
│  ┌──────────┐ ┌──────────────┐  │
│  │clipboard │ │  ipc-server  │  │
│  │ monitor  │ │  (Bun.listen)│  │
│  └────┬─────┘ └──────────────┘  │
│       │                         │
│  ┌────┴─────┐ ┌──────────────┐  │
│  │  crypto  │ │    wiper     │  │
│  │ AES-256  │ │  countdown   │  │
│  └────┬─────┘ └──────────────┘  │
│       │                         │
│  ┌────┴─────┐ ┌──────────────┐  │
│  │   db     │ │   cleanup    │  │
│  │ bun:sqlite│ │  prune timer │  │
│  └──────────┘ └──────────────┘  │
└─────────────────────────────────┘
```

- **Daemon** (Bun/TypeScript) handles all logic: clipboard polling, encryption, SQLite, IPC
- **UI** (Swift/AppKit) is a thin client: receives state updates, sends commands
- **IPC** uses `~/.clippy/clippy.sock` with newline-delimited JSON
- **Encryption key** stored in macOS Keychain as `com.clippy.encryption`

## Development

```bash
bun install              # Install dependencies
bun test                 # Run tests (31 tests across 6 files)
bun run dev              # Run with auto-reload
bun run build:app        # Build .app bundle to dist/
bun run build:dmg        # Create distributable DMG
```

### Scripts

| Command | Description |
|---------|-------------|
| `bun run start` | Run daemon + UI |
| `bun run dev` | Run with `--watch` |
| `bun run build:app` | Build `dist/Clippy.app` |
| `bun run build:dmg` | Create `dist/Clippy-x.x.x.dmg` |
| `bun run install` | Build and install to `/Applications` |
| `bun run uninstall` | Remove app, Keychain entry, optionally data |
| `bun run test` | Run unit tests |
| `bun run clean` | Remove build artifacts and runtime files |

### Project structure

```
src/
  index.ts          Entry point, PID lock, Swift compilation, process management
  daemon.ts         Orchestrator wiring all modules
  clipboard.ts      pbpaste polling, SHA-256 change detection
  db.ts             bun:sqlite schema, CRUD, dedup, pruning
  crypto.ts         AES-256-GCM encrypt/decrypt, Keychain key management
  config.ts         Load/save ~/.clippy/config.json
  wiper.ts          Auto-wipe countdown timer
  cleanup.ts        Periodic history pruning
  ipc-server.ts     Unix domain socket server
  ipc-protocol.ts   NDJSON message types and framing
swift/
  ClippyBar.swift   macOS status bar app
scripts/
  build-app.sh      Build .app bundle
  create-dmg.sh     Create DMG installer
  install.sh        Install to /Applications
  uninstall.sh      Full uninstall
  login-item.sh     Manage start-on-login LaunchAgent
  gen-icon.sh       Generate .icns from scissors glyph
  GenIcon.swift      Icon renderer (AppKit)
test/
  crypto.test.ts    Encryption round-trip tests
  db.test.ts        Database CRUD and pruning tests
  config.test.ts    Config merge and defaults tests
  ipc-protocol.test.ts  NDJSON framer tests
  wiper.test.ts     Countdown timer tests
  cleanup.test.ts   Cleanup scheduler tests
```

## Runtime files

All runtime data lives in `~/.clippy/`:

| File | Purpose |
|------|---------|
| `config.json` | User configuration |
| `clippy.db` | Encrypted clipboard history (SQLite, WAL mode) |
| `clippy.sock` | Unix domain socket for IPC |
| `clippy.pid` | PID lock file |
| `ClippyBar` | Compiled Swift binary (dev mode only) |

## Requirements

- macOS 14.0+
- ARM64 (Apple Silicon)
- [Bun](https://bun.sh) 1.0+ (for development)

## License

MIT
