# llmshell.AI — Product & Screen Requirements

**Product:** A native cross-platform (Flutter) SSH client for connecting to and managing remote Linux VPS hosts from a mobile device.
**Codename:** Obsidian SSH
**Design system:** "Obsidian Deep" (dark, developer-focused, Material 3 tonal layering)
**Primary platform:** Flutter (iOS + Android phones first; tablet/desktop layouts described where the source screens define them).

---

## 1. Overview & Vision

llmshell.AI is a premium, mobile-first SSH terminal client aimed at developers and infrastructure engineers who manage VPS / cloud servers on the go. It moves beyond a bare terminal emulator and treats each remote host as a workspace that can hold multiple concurrent **tabs**: terminal sessions, SFTP file browsers, in-app web previews (e.g. `localhost:3000`), and git diff views.

The experience is designed to make typing real shell commands on a phone genuinely usable through:

- A **custom command input bar** with terminal modifier keys (ESC, CTRL, ALT, TAB, arrows).
- An **expandable multi-line command editor** for composing long commands.
- **Multimodal input** affordances (image upload, voice/mic) on the command bar, reflecting the "`.AI`" assistant ambition of the product.

The brand personality is **reliable, focused, and sophisticated** — infrastructure management as a calm, premium experience rather than a neon "hacker" aesthetic.

---

## 2. Goals & Non-Goals

### Goals
- Securely store, organize, and connect to SSH hosts (password and key-pair auth).
- Provide a fast, legible mobile terminal with mobile-friendly key entry.
- Support multiple simultaneous sessions and a dashboard to monitor their live state.
- Per-host multi-tab workspace: terminal, file browser, web browser, git diff.
- A live "Connections" dashboard showing the latest output / status of every active session.

### Non-Goals (initial release)
- Full desktop IDE parity.
- Team sharing / collaboration / multi-user accounts.
- Server provisioning or cloud-provider API integration.
- The keyboard rendered inside several mockups is illustrative — the app should rely on the OS keyboard plus the custom modifier accessory bar, not ship its own full soft keyboard.

---

## 3. Design System ("Obsidian Deep")

Source of truth: `stitchScreens/obsidian_deep/DESIGN.md`. Implement as a Flutter `ThemeData` / Material 3 color scheme.

### Color palette (dark theme)
| Token | Hex |
|---|---|
| background / surface | `#10141A` |
| surface-container-lowest | `#0A0E14` |
| surface-container-low | `#181C22` |
| surface-container | `#1C2026` |
| surface-container-high | `#262A31` |
| surface-container-highest | `#31353C` |
| on-surface | `#DFE2EB` |
| on-surface-variant | `#C0C7D4` |
| outline | `#8B919D` |
| outline-variant | `#414752` |
| primary | `#A2C9FF` |
| on-primary | `#00315C` |
| primary-container | `#58A6FF` |
| secondary (success/online) | `#67DF70` |
| tertiary (accent) | `#D5BBFF` |
| error / awaiting-input | `#FFB4AB` |

Depth is communicated through **tonal layers** (surfaces get lighter as they rise) plus 1px low-contrast outlines, not heavy shadows. Avoid pure black and high-glow neon.

### Typography (dual-font)
- **Inter** — all UI text, headings, buttons, body. Sizes: headline-lg 32, headline-md 24, headline-sm 20, body-lg 16, body-md 14.
- **JetBrains Mono** — all technical data: IP addresses, ports, terminal output, file metadata, command chips. Sizes: label-mono-md 14, label-mono-sm 12.

### Shape & spacing
- Corner radius: cards/inputs `8px` (lg), containers `12px` (xl), pills/status chips `full`.
- 4px baseline grid; vertical rhythm of 16px (md) / 24px (lg); 16px mobile side margins.

### Component conventions
- **Status chips:** rounded-full, low-opacity tint of functional color (e.g. 10–20% green for "Connected", coral for "Awaiting Input", grey for "Idle/Offline").
- **Inputs:** etched look — darker `background` fill inside lighter `surface-container` cards; focus = 2px primary ring.
- **Terminal view:** dedicated `#0D1117`/background container, all monospace; teal for success lines, blue for commands/links.
- Material Symbols (Outlined) icon set.

---

## 4. Information Architecture & Navigation

Three-tab bottom navigation is the app's root shell:

1. **Hosts** — manage saved host definitions (the SSH address book).
2. **Connections** — live dashboard of active/running sessions.
3. **Settings** — app config, key manager, preferences (referenced by nav + "Keys can be managed in Settings").

Entering a host/session opens the **Workspace** (full-screen, outside the bottom nav) which contains the per-host tab bar (Terminal / Files / Browser / Git Diff) with a back arrow to return.

```
Root (bottom nav)
├─ Hosts ───────────► Add/Edit Host (modal)
│                     └─► Host context menu (⋮)
├─ Connections ─────► Active Sessions Dashboard
│                     └─► "+" Add Session menu
└─ Settings ────────► Key Manager, preferences

New session flow:
  Select Host (for new terminal) ─► Select Path (start dir) ─► Workspace

Workspace (per host, tabbed)
├─ Terminal tab ──► enhanced command input ─► expanded editor / image upload
├─ Files tab (SFTP browser)
├─ Browser tab (in-app web preview)
└─ Git Diff tab
   └─ tab bar "+" ─► New Terminal / File Browser / Browser / Git Diff
```

---

## 5. Screen-by-Screen Requirements

There are **13 screen mockups** (HTML + PNG) plus the design spec. Each below maps a source folder to functional requirements.

### 5.1 Hosts — Host Management (`host_management`)
The SSH address book / landing screen of the Hosts tab.

- App bar titled **"Terminal Hosts"** with a `+` action to add a host.
- **Filter/search field**: "Filter hosts by name or IP…".
- Hosts grouped by user-defined **category** headers (e.g. PRODUCTION, STAGING).
- Each host row: type icon, **label** (Inter), **hostname/IP** (mono), an **Online/Offline status chip**, and a `⋮` overflow menu (edit, delete, duplicate, connect).
- Tapping a host initiates/opens a connection; the `⋮` exposes management actions.
- Bottom nav with Hosts active.

**Requirements:** CRUD on hosts; persistent grouping; live or last-known reachability indicator; client-side filtering by name/IP.

### 5.2 Add / Edit Host (`add_host`)
Transactional modal form for creating or editing a host definition.

- Header: **Cancel** (left), **"Add Host"** title (center), sticky bottom **"Save Host"** primary button.
- **Identity section:** Label/Alias (required), Group/Category (select: Production, Staging, Development, Personal).
- **Connection section:** Hostname or IP (required), Port (number, default `22`, range 1–65535).
- **Authentication section:**
  - Method **segmented control**: Password ↔ Key Pair.
  - Username (required, default hint `root`).
  - Password field (when Password selected).
  - Saved private-key dropdown (when Key Pair selected) with hint "Keys can be managed in Settings."
- Required-field validation before save.

**Requirements:** Form validation; toggle auth UI by method; persist to the host store; secure handling of secrets (see §7).

### 5.3 Select Host for New Terminal (`select_host_for_new_terminal`)
Host picker used when starting a brand-new terminal session.

- App bar **"Terminal Hosts"** + search ("Search hosts or groups…").
- **Recent** section: rich cards showing icon, status chip, label, IP, and quick-detail mono chips (e.g. `ubuntu`, `ssh -i key.pem`, `port 2222`).
- **All Hosts** section: grouped compact list (PRODUCTION / STAGING) with small status dots.
- Selecting a host advances to the path picker (§5.4).

**Requirements:** Surface recently used hosts; show connection-detail chips; feed selection into the new-session flow.

### 5.4 Select Path for New Terminal (`select_path_for_new_terminal`)
Choose the starting working directory for the new session (remote directory browse).

- Back arrow + title **"Select Path"**.
- **Breadcrumb** of the current path (e.g. `home / ubuntu / projects / api-service`) with a home icon; segments are tappable to jump up.
- Directory list: folders are navigable (chevron, item count + "Modified …" metadata); files and hidden files are shown but visually de-emphasized/non-selectable as a target.
- Sticky primary action: **"Select '<dir>'"** confirming the chosen directory.

**Requirements:** Remote directory listing over SFTP/SSH before the shell opens; breadcrumb navigation; confirm-directory action launches the terminal in that cwd.

### 5.5 Connections — Active Sessions Dashboard (`connections_active_sessions_dashboard`)
Live overview of all running sessions (Connections tab home).

- Title **"Connections"** (mobile); on wide layouts a 280px sidebar (Terminal Sessions, File Browser, Web Views, Key Manager) + "New Connection" action.
- One **card per active session** with a colored left accent bar by state:
  - **Awaiting Input** (coral) — shows the blocking prompt, e.g. `$ sudo apt-get upgrade -y [Y/n]? _`.
  - **Connected** (green) — shows latest output line, e.g. `tail -f /var/log/...`.
  - **Processing** (blue/tertiary) — shows progress output, e.g. `Epoch 45/100 [====>] 55%`.
  - **Idle** (grey).
- Each card: host icon, name (Inter), `user@host` (mono), status chip, and a **live preview line** of the most recent terminal output (mono, truncated).
- Floating **`+`** button to add a new session.
- Tapping a card opens that session's workspace.

**Requirements:** Track session state machine (connected / processing / awaiting-input / idle / disconnected); stream and cache the latest output line per session for the preview; reflect prompts that need user attention.

### 5.6 Connections — Add Session Menu (`connections_add_session_menu`)
The `+` / add-session entry point from the Connections dashboard (menu overlay over the sessions list).

- Lists existing active sessions ("Active Sessions" — "Manage your current secure connections") and exposes the path to create a new connection.

**Requirements:** Quick access to spin up a new connection from the dashboard.

### 5.7 Workspace — Multi-Tab Manager (`connections_multi_tab_manager`)
The per-host workspace shell with its tab bar and the **add-tab** popover.

- Top tab bar: back arrow + horizontally scrollable tabs, each with type icon, label (e.g. `web-prod-01`, `db-backup-dir`) and a close (`×`) control.
- `+` opens a popover menu to add a tab of type:
  - **New Terminal** (terminal icon)
  - **New File Browser** (folder icon)
  - **New Browser** (globe icon)
  - **New Git Diff** (diff icon)
- Behind the popover, an active terminal pane (login banner, `ls -l` output, running `tail -f`).

**Requirements:** Multiple heterogeneous tabs per host; create/close/switch tabs; tabs persist for the session's lifetime; horizontal scroll when overflowing.

### 5.8 Workspace — Terminal Tab (`connections_terminal_tabs`)
The core terminal emulator view.

- Tab bar (Terminal active, Files, Browser).
- Full terminal output rendered in JetBrains Mono with ANSI-style coloring: blue prompt (`ubuntu@hq:~/fun/cmuxterm$`), greyed wrapped log lines, teal success (`✓ Ready in 729ms`), links/URLs highlighted, blinking cursor.
- Output area is scrollable; long lines wrap (`break-all`).

**Requirements:** Real PTY/SSH shell channel; ANSI color + control-sequence parsing; selectable/scrollable buffer; correct line wrapping; auto-scroll to bottom on new output with scroll-lock when the user scrolls up.

### 5.9 Workspace — Enhanced Chat/Command Input (`active_terminal_enhanced_chat_input`)
The signature mobile command-entry bar shown beneath the terminal.

- Input row: **image upload** button, **mic / voice** button, free-text field ("Type a command…"), **expand** button (→ §5.10), **send** button.
- **Modifier accessory bar** above the OS keyboard: `ESC`, `CTRL`, `ALT`, `TAB` plus arrow keys (←↑↓→). (The full QWERTY rows in the mockup represent the OS keyboard and are not custom-built.)
- CTRL/ALT act as sticky modifiers combined with the next keypress (e.g. Ctrl+C); ESC/TAB/arrows send the corresponding control sequences to the PTY.

**Requirements:** Send typed command on Enter/send; transmit raw control sequences for modifier + arrow keys; image and voice buttons feed the multimodal/AI input pipeline (attach image, transcribe voice to command); command history navigable via up/down arrows.

### 5.10 Workspace — Expanded Command Editor (`active_terminal_expanded_input_popup`)
Full-screen multi-line editor for composing long/complex commands.

- Sheet titled **"Command Editor"** with a collapse/minimize control.
- Large monospace multi-line text area (example shows a multi-line `docker run …` with `\` continuations) and a caret.
- Helper toolbar: touch/cursor tool, **`{}`** snippet/braces insert, folder/path insert, **shift+tab**, settings, overflow (`…`).
- Extended key row: arrows, `Alt`, `Tab`, `Ins`, `Del`, and a symbols row (`Home PgUp PgDn End | \ ? -`).
- Sits above the standard OS keyboard area.

**Requirements:** Multi-line editing with preserved indentation; insert special characters/symbols hard to reach on mobile; send the full buffer to the terminal on confirm; collapse returns to the inline input.

### 5.11 Workspace — Image Upload Preview (`active_terminal_image_upload_preview`)
Attachment state of the command input when images have been added.

- A horizontal strip of **image thumbnails** with per-item remove (`×`) appears between the terminal output and the input bar.
- Input bar (image, field, expand, send) remains available so a prompt/command can accompany the attachments.

**Requirements:** Attach one or more images (camera/gallery); preview + remove before sending; bundle images with the text prompt to the AI/assistant pipeline (multimodal command interpretation).

### 5.12 Workspace — File Browser Tab (`connections_file_browser_tabs`)
SFTP-style remote file manager as a workspace tab.

- Tab bar with **Files** active.
- **Current path** header (e.g. `/home/ubuntu/fun/cmuxterm`).
- `..` parent navigation entry.
- File/folder rows: type icon (folder, generic file, markdown, code), name (mono), **Unix permission string** (`drwxr-xr-x`), and **size** (bytes).
- Tapping a folder navigates in; files open/preview.

**Requirements:** SFTP listing with permissions + size; navigate directories; (target features) open/preview, upload, download, rename, delete, chmod.

### 5.13 Workspace — Browser Tab (`connections_browser_tabs`)
In-app web browser for previewing services running on the remote host (e.g. dev servers via tunneled ports).

- Tab bar with a browser tab active (e.g. `web-prod-01`, `db-backup-di…`).
- **URL/address bar** with lock icon (`localhost:3000/docs`) and a **reload** button.
- Renders the remote/forwarded web page (documentation/dev-server preview shown).

**Requirements:** WebView pointed at a port on the connected host (via SSH local port forwarding/tunnel); address bar navigation; reload; lock/secure indicator.

### Git Diff tab (referenced, no standalone mockup)
The add-tab menu (§5.7) includes **New Git Diff**. Provide a tab that renders `git diff` output for the session's working directory with syntax/diff coloring (added/removed lines). Treat as a defined feature even though no dedicated screen PNG exists.

---

## 6. Functional Requirements Summary

| Area | Requirement |
|---|---|
| Host management | Create/read/update/delete hosts; group by category; search/filter; recents. |
| Authentication | Password and SSH key-pair; key manager in Settings; default port 22. |
| SSH terminal | Interactive PTY shell; ANSI parsing; resize to viewport; scrollback. |
| Mobile input | Modifier bar (ESC/CTRL/ALT/TAB/arrows); expanded multi-line editor; command history; special-character inserts. |
| Multimodal / AI | Image attachment + voice input on the command bar feeding an assistant pipeline. |
| Sessions | Multiple concurrent sessions; live dashboard with state + last-output preview; awaiting-input detection. |
| Per-host tabs | Terminal, File Browser (SFTP), Browser (WebView/tunnel), Git Diff; add/close/switch. |
| File browser | SFTP listing with permissions/size; directory navigation; path breadcrumb; start-dir picker. |
| Web preview | In-app WebView over forwarded ports; URL bar + reload. |

---

## 7. Non-Functional Requirements

- **Security**
  - Store credentials and private keys in the OS secure enclave / Keychain / Android Keystore (`flutter_secure_storage`), never in plain prefs.
  - Verify and pin host keys (known-hosts); warn on key mismatch.
  - Support biometric/app-lock gate before exposing saved secrets.
- **Performance:** smooth 60fps terminal rendering and scrolling; efficient handling of high-throughput output (e.g. `tail -f`) without UI jank; lazy-render scrollback.
- **Reliability:** graceful reconnect handling; keep-alive; clear disconnect/error states reflected in the dashboard.
- **Accessibility:** legible mono sizes, sufficient contrast (palette already tuned for low eye strain), respect dynamic type where feasible.
- **Responsiveness:** mobile single-column first; sidebar/desktop layouts as defined in the dashboard mockup for tablet/large screens.
- **Theming:** dark theme is primary (Obsidian Deep); architecture should not hard-code colors (use theme tokens).

---

## 8. Suggested Flutter Architecture (non-binding)

- **SSH/SFTP:** `dartssh2` (pure-Dart SSH2 + SFTP client) for shell channels, port forwarding, and file transfer.
- **Terminal:** `xterm` (xterm.dart) for the terminal widget + ANSI/VT parsing, wired to the SSH shell stream.
- **WebView:** `webview_flutter` for the Browser tab (pointed at forwarded localhost ports).
- **Secure storage:** `flutter_secure_storage`; biometrics via `local_auth`.
- **State management:** Riverpod or Bloc — model `Host`, `Session` (with state enum), and `Tab` (sealed type: Terminal/Files/Browser/GitDiff).
- **Persistence:** local DB (Drift/Isar/sqflite) for hosts, groups, and recents; secrets in secure storage only.
- **Fonts:** bundle Inter + JetBrains Mono; central Material 3 `ThemeData` from the §3 tokens.

### Core data model (sketch)
```
Host { id, label, group, hostname, port=22, username, authMethod(password|key), keyRef?, lastSeenOnline }
Session { id, hostId, state(connected|processing|awaitingInput|idle|disconnected), cwd, lastOutputLine, tabs[] }
Tab { id, type(terminal|files|browser|gitdiff), title, state }
SshKey { id, name, publicKey, privateKeyRef(secure) }
```

---

## 9. Screen Inventory (mockup → status)

| # | Screen | Source folder | Has PNG | Notes |
|---|---|---|---|---|
| 1 | Host Management | `host_management` | ✔ | Hosts tab home |
| 2 | Add / Edit Host | `add_host` | ✔ | Form has working auth toggle JS |
| 3 | Select Host (new terminal) | `select_host_for_new_terminal` | ✔ | Recents + grouped list |
| 4 | Select Path (new terminal) | `select_path_for_new_terminal` | ✔ | Breadcrumb dir picker |
| 5 | Active Sessions Dashboard | `connections_active_sessions_dashboard` | ✔ | Connections tab home |
| 6 | Add Session Menu | `connections_add_session_menu` | ✔ | Overlay on dashboard |
| 7 | Multi-Tab Manager | `connections_multi_tab_manager` | ✔ | Add-tab popover (4 tab types) |
| 8 | Terminal Tab | `connections_terminal_tabs` | ✔ | Core terminal view |
| 9 | Enhanced Chat/Command Input | `active_terminal_enhanced_chat_input` | ✔ | Modifier bar + image/mic |
| 10 | Expanded Command Editor | `active_terminal_expanded_input_popup` | ✔ | Multi-line editor |
| 11 | Image Upload Preview | `active_terminal_image_upload_preview` | ✔ | Attachment thumbnails |
| 12 | File Browser Tab | `connections_file_browser_tabs` | ✔ | SFTP listing |
| 13 | Browser Tab | `connections_browser_tabs` | ✔ | In-app WebView |
| — | Git Diff Tab | _(referenced in #7 menu)_ | ✘ | Build per add-tab menu |
| — | Design System | `obsidian_deep/DESIGN.md` | — | Theme spec |

---

## 10. Suggested Delivery Phases

1. **Foundation:** theme/tokens, fonts, bottom-nav shell, data model, secure storage.
2. **Hosts:** Host Management + Add/Edit Host (CRUD, validation, key manager stub).
3. **Connect:** Select Host → Select Path → live SSH terminal (xterm + dartssh2) with the enhanced command input + modifier bar.
4. **Sessions:** Connections dashboard with live state + output previews; awaiting-input detection.
5. **Workspace tabs:** multi-tab manager; SFTP File Browser; in-app Browser (port forwarding); Git Diff.
6. **Power input & AI:** expanded command editor, image upload preview, voice input, assistant pipeline.
7. **Hardening:** host-key verification, biometrics, reconnect, performance tuning.
