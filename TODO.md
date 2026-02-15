# TODO

## Prototype 2: LLM Integration

- [ ] Ollama integration for clipboard content summarization
- [ ] Display AI-generated summaries in menu history instead of raw truncation
- [ ] Configurable model selection and prompt

## Features

- [ ] Image clipboard support (screenshots, copied images)
- [ ] Rich text / HTML clipboard type handling
- [ ] File path clipboard detection
- [ ] Keyboard shortcut to open history (global hotkey)
- [ ] Search/filter clipboard history from menu bar
- [ ] Favorite/pin entries to prevent auto-deletion
- [ ] Categories or tags for clipboard entries
- [ ] Export history to file (JSON, CSV)

## UI

- [ ] SwiftUI popover instead of NSMenu for richer UI
- [ ] Dark/light mode theme support
- [ ] Configurable menu bar icon
- [ ] Preferences window (SwiftUI) instead of JSON config editing
- [ ] Notification when clipboard is wiped

## Security

- [ ] Sensitive content detection (passwords, API keys, credit cards)
- [ ] Per-entry wipe delay (shorter for detected secrets)
- [ ] Exclude specific apps from monitoring
- [ ] Biometric unlock for history access (Touch ID)
- [ ] Encrypted database at rest (SQLCipher or similar)

## Platform

- [ ] Universal binary (Intel + Apple Silicon)
- [ ] Homebrew cask distribution
- [ ] Notarized build for Gatekeeper
- [ ] Auto-update mechanism
- [ ] Proper Apple Developer code signing

## Quality

- [ ] Integration tests for daemon + IPC flow
- [ ] Swift UI tests
- [ ] CI pipeline (GitHub Actions)
- [ ] Memory and CPU profiling under sustained clipboard activity
- [ ] Graceful handling of very large clipboard content (>10MB)
