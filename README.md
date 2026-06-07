# llmshell (Obsidian SSH)

Mobile SSH client for VPS management. See [REQUIREMENTS.md](REQUIREMENTS.md) for the full product spec.

## Run

```bash
flutter pub get
flutter run -d chrome    # web
flutter run -d macos     # desktop
# Android device/emulator when available
```

## Project structure

```
lib/
  core/theme/          # Obsidian Deep design tokens
  models/              # Host, Session, WorkspaceTab, SshKey
  services/            # SSH, SFTP, sessions, secure storage
  providers/           # Riverpod (hosts list)
  features/            # Screens (hosts, connections, workspace, settings)
  router/              # go_router navigation
  widgets/             # Shared UI components
```

## Features implemented

- **Hosts:** CRUD with secure password/key storage, search, groups, recents
- **SSH connect:** `dartssh2` shell + PTY, known-host fingerprints
- **Terminal:** `xterm` with live output, modifier keys (ESC/CTRL/ALT/TAB/arrows), command bar, expanded editor
- **Sessions:** Live Connections dashboard with state + output preview
- **Workspace tabs:** Terminal, SFTP file browser, WebView via local port forward, `git diff`
- **Settings:** SSH key import (`.pem` / private key files)

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
