# Contributing to AItty

Thanks for your interest in AItty — a mobile-first terminal for coding. This guide covers setting up a dev environment, the architecture, the conventions to follow, and how to get a change merged.

> [Code of Conduct](CODE_OF_CONDUCT.md) applies to everyone participating in this project. Be excellent to each other.

## Table of contents

- [Quick start](#quick-start)
- [Development workflow](#development-workflow)
- [Architecture overview](#architecture-overview)
- [Vendored `xterm` fork](#vendored-xterm-fork)
- [Code style](#code-style)
- [Testing](#testing)
- [Commit & pull request conventions](#commit--pull-request-conventions)
- [Security](#security)
- [Releasing the website](#releasing-the-website)

## Quick start

### Prerequisites

- **Flutter** stable channel, **Dart `^3.12.0`** — [install Flutter](https://docs.flutter.dev/get-started/install)
- For Android/iOS work: the platform toolchain and a device or emulator
- For a quick start with no mobile toolchain: **Chrome** (web) or **macOS** (desktop)

### Run it

```bash
git clone https://github.com/msebindavis/AItty.git
cd AItty
flutter pub get
flutter run -d chrome        # web — quickest path with no toolchain
flutter run -d macos         # desktop
flutter run -d <device-id>   # Android / iOS device or emulator
```

Verify your environment:

```bash
flutter doctor
flutter analyze              # should be clean
flutter test                 # smoke + model tests
```

## Development workflow

1. **For anything bigger than a typo,** open an issue first to discuss the approach. This avoids duplicated work and big PRs that go in the wrong direction.
2. Fork the repo and create a branch off `main`: `git checkout -b feat/my-feature`.
3. Make focused changes. Keep `flutter analyze` clean and `flutter test` green.
4. Add tests for new behavior where practical (see [Testing](#testing)).
5. Open a pull request using the [PR template](.github/PULL_REQUEST_TEMPLATE.md) and link the issue.

## Architecture overview

AItty is a Flutter app using **Riverpod** for state and **go_router** for navigation.

```
lib/
  main.dart            # Entry point: WidgetsFlutterBinding, font preload, InteractionLogger, runApp(ProviderScope(...))
  app.dart             # MaterialApp.router with ObsidianTheme.dark(), wrapped in InteractionLogScope + SessionLifecycleScope
  core/
    theme/             # Obsidian Deep tokens: obsidian_colors.dart, obsidian_theme.dart, app_typography.dart
    constants/         # spacing.dart
  models/              # Plain Dart data classes with JSON ser/de: Host, Session, Workspace, WorkspaceTab, SshKey, AittyConfig, …
  services/            # Business / IO layer: ssh_connection.dart (dartssh2), repositories, workspace_manager.dart (orchestrator), secure_storage_service.dart, known_hosts_store.dart, local_port_forward.dart, tmux_startup.dart, …
  providers/           # Riverpod notifiers (e.g. HostsNotifier); many providers are declared inside their service files
  features/            # Screens grouped by area:
                       #   hosts/         (list, add, select host/path)
                       #   connections/   (live sessions dashboard)
                       #   workspace/     (workspace_screen, files_tab, browser_tab, git_manager_tab, git_diff_viewer, terminal_keyboard/)
                       #   settings/      (settings, key_manager, terminal_settings)
                       #   shell/         (app_shell — bottom-nav shell)
  router/              # app_router.dart — StatefulShellRoute.indexedStack bottom nav with nested routes (/hosts, /connections, /settings, /workspaces/:id, …)
  utils/               # Helpers: git_parsers, speech_dictation, terminal_input, source_language (syntax highlighting), interaction_logger, …
  widgets/             # Shared UI: connection_session_card, host_list_tile, status_chip, dialogs, session_lifecycle_scope
packages/
  xterm/               # Vendored, patched xterm.dart (see below)
test/                  # widget_test.dart, aitty_config_test.dart
```

### Layering

`models/` → `services/` → `providers/` → `features/` → `widgets/`. Models are plain data; services own IO and business logic (SSH, SFTP, secure storage, repositories, the `WorkspaceManager` orchestrator); providers expose state to the UI via Riverpod; features are screens; widgets are shared components. Dependency direction flows inward — screens depend on providers/services, services depend on models, not the reverse.

### Product context

The full product spec, feature list, and delivery roadmap live in [REQUIREMENTS.md](REQUIREMENTS.md). Read it for the "why" behind a feature before building the "how".

## Vendored `xterm` fork

AItty bundles a patched copy of [`xterm.dart`](https://github.com/TerminalStudio/xterm.dart) at [`packages/xterm`](packages/xterm), wired in via `dependency_overrides` in `pubspec.yaml`:

```yaml
dependency_overrides:
  xterm:
    path: packages/xterm
```

What this means for contributors:

- **Terminal-emulator changes happen in `packages/xterm`**, not via the published `xterm` package. `flutter pub get` resolves the local fork automatically.
- If you need to change terminal rendering, input handling, or ANSI parsing, edit under `packages/xterm/lib/src/` (core/, ui/, base/, utils/).
- **Keep the vendored package's own LICENSE intact** — it is third-party code with its own license terms.
- When upstream `xterm.dart` releases a fix you want, cherry-pick it into the fork rather than re-pointing the dependency, so local patches aren't lost.

## Code style

- Lint rules: `package:flutter_lints/flutter.yaml` (`flutter_lints: ^6.0.0`) via [analysis_options.yaml](analysis_options.yaml). No custom rules yet — the default Flutter set applies.
- **`flutter analyze` must be clean** before a PR is merged.
- **Reuse theme tokens, don't hardcode colors.** The Obsidian Deep palette lives in `lib/core/theme/obsidian_colors.dart` and `lib/core/theme/obsidian_theme.dart`. Use `ObsidianColors.primary`, `Theme.of(context)` extensions, etc. — never raw hex in widgets. Typography: Inter for UI, JetBrains Mono for terminal/code/data.
- Follow the existing feature-based folder layout. New screens go under `lib/features/<area>/`; new shared UI under `lib/widgets/`; new data types under `lib/models/`; new IO/business logic under `lib/services/`.
- Match the surrounding code's naming, comment density, and idioms.

## Testing

Coverage is intentionally minimal right now — `test/widget_test.dart` (a smoke test that pumps the app and asserts the Hosts tab renders) and `test/aitty_config_test.dart` (model JSON ser/de). There are no service, SSH, or integration tests yet.

Run:

```bash
flutter test
flutter test --coverage     # optional
```

Guidelines:

- **Add a test with your PR** where practical — especially for pure logic like `lib/utils/git_parsers.dart`, `lib/models/` ser/de, and `lib/services/` repository methods (mock the SSH layer).
- Don't break existing tests. If a behavior change invalidates a test, update the test and explain why in the PR description.
- Golden/screenshot tests are welcome but not required; the `stitchScreens/` HTML mockups are the visual source of truth.

## Commit & pull request conventions

- **Small, focused PRs.** One logical change per PR.
- **Conventional-ish commit messages**, e.g. `feat(workspace): add close-tab swipe gesture`, `fix(ssh): handle broken pipe on reconnect`, `docs: expand CONTRIBUTING`. Keep the subject line under ~72 chars.
- Write a clear PR description using the [PR template](.github/PULL_REQUEST_TEMPLATE.md): what changed, why, how to test it, and any screenshots for UI changes.
- Link the related issue (`Closes #123`).
- Rebase onto `main` before requesting review if there are merge conflicts.

## Security

AItty handles SSH credentials and private keys. **Never commit:**

- Real SSH private keys (`.pem`, `id_rsa`, `id_ed25519`, …) — `.gitignore` blocks these, but check anyway.
- Passwords, tokens, or API keys.
- `.env` files, Android keystores (`*.keystore` / `*.jks`), or Google service configs (`google-services.json` / `GoogleService-Info.plist`).

All credentials at runtime go through `lib/services/secure_storage_service.dart` (`flutter_secure_storage`) — route any new credential handling through it rather than plain `SharedPreferences` or committed files. If you find a committed secret, **do not push a fix that merely deletes it** — treat it as exposed and notify a maintainer so it can be rotated.

## Releasing the website

The marketing site is a static site in [`docs/`](docs) served by GitHub Pages from the `/docs` folder on `main`. To update it, edit `docs/index.html`, `docs/styles.css`, `docs/main.js`, or `docs/assets/**` and push to `main` — Pages republishes automatically. No build step. Preview locally with:

```bash
python3 -m http.server -d docs 8000
# open http://localhost:8000/
```

---

Questions? Open a [discussion](https://github.com/msebindavis/AItty/discussions) or an [issue](https://github.com/msebindavis/AItty/issues). Happy hacking.