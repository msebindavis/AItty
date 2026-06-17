import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:xterm/xterm.dart';

import '../models/app_settings.dart';
import '../models/git_models.dart';
import '../models/host.dart';
import '../models/remote_file_entry.dart';
import '../models/resumable_session.dart';
import '../models/session.dart';
import '../models/workspace.dart';
import '../models/workspace_tab.dart';
import '../models/workspace_template.dart';
import '../utils/git_parsers.dart';
import '../utils/session_state_detector.dart';
import 'app_settings_repository.dart';
import 'host_repository.dart';
import 'known_hosts_store.dart';
import 'recent_paths_store.dart';
import 'resumable_session_store.dart';
import 'secure_storage_service.dart';
import 'session_foreground.dart';
import 'ssh_connection.dart';
import 'ssh_key_repository.dart';
import 'tmux_startup.dart';
import 'workspace_repository.dart';

class RemoteTmuxSession {
  const RemoteTmuxSession({
    required this.name,
    this.cwd,
  });

  final String name;
  final String? cwd;
}

class WorkspaceSummary {
  const WorkspaceSummary({
    required this.id,
    required this.hostId,
    required this.title,
    required this.connectionString,
    required this.state,
    required this.terminalCount,
    required this.lastOutputLine,
  });

  final String id;
  final String hostId;
  final String title;
  final String connectionString;
  final SessionState state;
  final int terminalCount;
  final String lastOutputLine;
}

class WorkspaceManager extends ChangeNotifier {
  WorkspaceManager(this._ref);

  final Ref _ref;
  final _uuid = const Uuid();
  final Map<String, Workspace> _workspaces = {};

  List<Workspace> get workspaces => _workspaces.values.toList();

  List<WorkspaceSummary> get workspaceSummaries => _workspaces.values
      .map(
        (w) => WorkspaceSummary(
          id: w.id,
          hostId: w.hostId,
          title: w.name,
          connectionString: w.hostId,
          state: w.aggregateState,
          terminalCount: w.terminals.length,
          lastOutputLine: w.terminals.isNotEmpty ? w.terminals.last.lastOutputPreview : '',
        ),
      )
      .toList();

  Workspace? getWorkspace(String id) => _workspaces[id];

  Workspace? findWorkspaceByTmuxSession(String hostId, String tmuxSessionName) {
    for (final workspace in _workspaces.values) {
      if (workspace.hostId != hostId) continue;
      for (final pane in workspace.terminals) {
        if (pane.useTmux && pane.tmuxSessionName == tmuxSessionName) {
          return workspace;
        }
      }
    }
    return null;
  }

  void focusTmuxSession(String workspaceId, String tmuxSessionName) {
    final workspace = _workspaces[workspaceId];
    if (workspace == null) return;
    final index = workspace.terminals.indexWhere(
      (p) => p.useTmux && p.tmuxSessionName == tmuxSessionName,
    );
    if (index >= 0) {
      workspace.activeTabIndex = index;
      _syncPrimaryFilesTabPath(workspace, workspace.terminals[index].cwd);
    }
    notifyListeners();
  }

  /// Keep the default Files tab aligned with the active terminal's working directory.
  void _syncPrimaryFilesTabPath(Workspace workspace, String cwd) {
    final index = workspace.auxTabs.indexWhere((t) => t.type == WorkspaceTabType.files);
    if (index < 0) return;
    final tab = workspace.auxTabs[index];
    if (tab.path == cwd) return;
    workspace.auxTabs[index] = tab.copyWith(path: cwd);
  }

  Future<void> renameWorkspace(String workspaceId, String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) throw ArgumentError('Workspace name cannot be empty');
    final workspace = _workspaces[workspaceId];
    if (workspace == null) return;
    workspace.name = trimmed;
    notifyListeners();
  }

  void _invalidateResumeList() => _ref.invalidate(resumableSessionsProvider);

  Future<Set<String>> reservedTmuxNames(String hostId) async {
    final reserved = <String>{};
    final bookmarks = await _ref.read(resumableSessionStoreProvider).list();
    for (final bookmark in bookmarks) {
      if (bookmark.hostId == hostId) reserved.add(bookmark.tmuxSessionName);
    }
    for (final workspace in _workspaces.values) {
      if (workspace.hostId != hostId) continue;
      for (final pane in workspace.terminals) {
        if (pane.useTmux) reserved.add(pane.tmuxSessionName);
      }
    }
    return reserved;
  }

  Future<String> suggestSessionName(
    Host host, {
    int paneIndex = 0,
  }) async {
    final reserved = await reservedTmuxNames(host.id);
    return TmuxStartup.suggestName(
      hostLabel: host.label,
      hostDefault: host.tmuxSessionName,
      paneIndex: paneIndex,
      reserved: reserved,
    );
  }

  ResumableSession _bookmarkFromPane(Workspace workspace, TerminalPane pane) {
    return ResumableSession(
      id: '${workspace.hostId}:${pane.tmuxSessionName}',
      hostId: workspace.hostId,
      tmuxSessionName: pane.tmuxSessionName,
      cwd: pane.cwd,
      label: pane.tmuxSessionName,
      useTmux: true,
      lastActiveAt: DateTime.now(),
    );
  }

  Future<void> refreshResumeBookmarks() async {
    final store = _ref.read(resumableSessionStoreProvider);
    final existing = await store.list();
    final byKey = <String, ResumableSession>{
      for (final bookmark in existing) '${bookmark.hostId}:${bookmark.tmuxSessionName}': bookmark,
    };

    for (final workspace in _workspaces.values) {
      for (final pane in workspace.terminals) {
        if (!pane.useTmux) continue;
        final key = '${workspace.hostId}:${pane.tmuxSessionName}';
        byKey[key] = _bookmarkFromPane(workspace, pane);
      }

      if (!workspace.connection.isConnected) continue;
      try {
        final remoteSessions = await TmuxStartup.listRemoteSessions(workspace.connection);
        for (final session in remoteSessions) {
          final key = '${workspace.hostId}:${session.name}';
          final previous = byKey[key];
          byKey[key] = ResumableSession(
            id: key,
            hostId: workspace.hostId,
            tmuxSessionName: session.name,
            cwd: _preferSessionCwd(session.cwd, previous?.cwd) ?? '~',
            label: session.name,
            useTmux: true,
            lastActiveAt: DateTime.now(),
          );
        }
      } catch (_) {}
    }

    await store.merge(byKey.values);
    _invalidateResumeList();
  }

  Future<AppSettings> _settings() => _ref.read(appSettingsRepositoryProvider).load();

  HostTmuxMode _resolveTmuxMode(Host host, AppSettings settings) {
    if (host.tmuxMode == HostTmuxMode.inherit) return settings.defaultTmuxMode;
    return host.tmuxMode;
  }

  Duration? _resolveKeepAlive(Host host, AppSettings settings) {
    if (host.keepAliveIntervalSeconds != null) {
      if (host.keepAliveIntervalSeconds! <= 0) return null;
      return Duration(seconds: host.keepAliveIntervalSeconds!);
    }
    return settings.keepAliveInterval;
  }

  String _shellQuote(String path) => "'${path.replaceAll("'", "'\\''")}'";

  Future<Host> _requireHost(String hostId) async {
    final host = await _ref.read(hostRepositoryProvider).getHost(hostId);
    if (host == null) throw StateError('Host not found');
    return host;
  }

  Future<SshConnection> _connectHost(Host host, {SshConnection? existing}) async {
    if (existing != null && existing.isConnected) return existing;
    final settings = await _settings();
    return SshConnection.connect(
      host: host,
      hosts: _ref.read(hostRepositoryProvider),
      keys: _ref.read(sshKeyRepositoryProvider),
      knownHosts: _ref.read(knownHostsStoreProvider),
      keepAliveInterval: _resolveKeepAlive(host, settings),
    );
  }

  Future<void> _runPaneStartup({
    required Workspace workspace,
    required TerminalPane pane,
    required Host host,
    required HostTmuxMode tmuxMode,
    bool resumeOnly = false,
  }) async {
    final conn = workspace.connection;
    final attachingTmux = pane.useTmux && resumeOnly;
    final tmuxCwd = pane.cwd.isNotEmpty && pane.cwd != '~' ? pane.cwd : null;

    // Attach/resume reuses the tmux session's own working directory — skip cd.
    // New tmux sessions receive cwd via `tmux new-session -c`.
    if (!pane.useTmux && pane.cwd.isNotEmpty && pane.cwd != '~') {
      conn.write(pane.channelId, 'cd ${_shellQuote(pane.cwd)}\n');
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }

    if (pane.useTmux) {
      final effectiveMode = tmuxMode == HostTmuxMode.off ? HostTmuxMode.attachExisting : tmuxMode;
      if (await TmuxStartup.isInstalled(conn)) {
        final tmuxCmd = TmuxStartup.commandForMode(
          mode: effectiveMode,
          sessionName: pane.tmuxSessionName,
          resumeOnly: resumeOnly,
          cwd: attachingTmux ? null : tmuxCwd,
        );
        if (tmuxCmd.isNotEmpty) {
          conn.write(pane.channelId, '$tmuxCmd\n');
        }
      } else {
        conn.write(
          pane.channelId,
          'echo "[AItty] tmux not found — using plain shell."\n',
        );
      }
    }

    final snippet = host.startupSnippet?.trim();
    if (!resumeOnly && snippet != null && snippet.isNotEmpty) {
      conn.write(pane.channelId, '$snippet\n');
    }
  }

  void _bindPane(Workspace workspace, TerminalPane pane) {
    final conn = workspace.connection;
    pane.terminal.onOutput = (data) {
      conn.write(pane.channelId, data);
      if (pane.state == SessionState.idle) {
        pane.state = SessionState.connected;
        notifyListeners();
      }
    };

    conn.attachOutput(
      pane.channelId,
      onStdout: (chunk) {
        pane.terminal.write(chunk);
        final preview = SessionStateDetector.lastLinePreview(pane.terminal);
        pane.lastOutputPreview = preview;
        pane.state = SessionStateDetector.detect(preview, chunk);
        notifyListeners();
      },
      onStderr: (chunk) => pane.terminal.write(chunk),
    );

    pane.terminal.onResize = (w, h, _, __) {
      conn.resizeTerminal(pane.channelId, w, h);
    };
  }

  Future<Workspace> connectHostWorkspace({
    required Host host,
    SshConnection? existing,
  }) async {
    final connection = await _connectHost(host, existing: existing);
    final workspaceId = _uuid.v4();
    final homePath = '/home/${host.username}';
    final workspace = Workspace(
      id: workspaceId,
      name: host.label,
      hostId: host.id,
      connection: connection,
      terminals: [],
      auxTabs: [
        WorkspaceTab(id: _uuid.v4(), type: WorkspaceTabType.files, title: 'Files', path: homePath),
      ],
    );

    connection.onDisconnected = () => _markWorkspaceDisconnected(workspaceId);
    await _ref.read(hostRepositoryProvider).recordRecent(host.id);
    _workspaces[workspaceId] = workspace;
    _syncForegroundService();
    notifyListeners();
    return workspace;
  }

  Future<List<RemoteTmuxSession>> listRemoteTmuxSessions(String workspaceId) async {
    final workspace = _workspaces[workspaceId];
    if (workspace == null || !workspace.connection.isConnected) {
      throw StateError('Connection lost');
    }

    final remoteSessions = await TmuxStartup.listRemoteSessions(workspace.connection);
    final bookmarks = await _ref.read(resumableSessionStoreProvider).list();
    final cwdByName = <String, String>{};
    for (final bookmark in bookmarks) {
      if (bookmark.hostId == workspace.hostId) {
        cwdByName[bookmark.tmuxSessionName] = bookmark.cwd;
      }
    }

    return remoteSessions
        .map(
          (session) => RemoteTmuxSession(
            name: session.name,
            cwd: _preferSessionCwd(session.cwd, cwdByName[session.name]),
          ),
        )
        .toList();
  }

  /// Prefer the most useful path for display and post-attach navigation.
  String? _preferSessionCwd(String? tmuxCwd, String? bookmarkCwd) {
    final tmux = _normalizePath(tmuxCwd);
    final bookmark = _normalizePath(bookmarkCwd);
    if (bookmark != null &&
        tmux != null &&
        _looksLikeHomePath(tmux) &&
        bookmark.length > tmux.length) {
      return bookmark;
    }
    if (tmux != null && tmux.isNotEmpty) return tmux;
    if (bookmark != null && bookmark.isNotEmpty) return bookmark;
    return null;
  }

  String? _normalizePath(String? path) {
    if (path == null) return null;
    final trimmed = path.trim();
    if (trimmed.isEmpty || trimmed == '~') return null;
    return trimmed;
  }

  bool _looksLikeHomePath(String path) {
    return RegExp(r'^/home/[^/]+$').hasMatch(path) || RegExp(r'^/Users/[^/]+$').hasMatch(path);
  }

  Future<({String workspaceId, TerminalPane pane})> attachToTmuxSession(
    String workspaceId,
    String sessionName, {
    String? cwd,
  }) async {
    final workspace = _workspaces[workspaceId];
    if (workspace == null) throw StateError('Workspace not found');

    final open = findWorkspaceByTmuxSession(workspace.hostId, sessionName);
    if (open != null) {
      focusTmuxSession(open.id, sessionName);
      return (
        workspaceId: open.id,
        pane: open.terminals.firstWhere(
          (p) => p.useTmux && p.tmuxSessionName == sessionName,
        ),
      );
    }

    final pane = await addTerminal(
      workspaceId,
      cwd: _preferSessionCwd(cwd, null) ?? '~',
      tmuxSessionName: sessionName,
      useTmux: true,
      resumeOnly: true,
      tmuxModeOverride: HostTmuxMode.attachExisting,
    );
    return (workspaceId: workspaceId, pane: pane);
  }

  Future<Workspace> createWorkspace({
    required Host host,
    required String cwd,
    String? tmuxSessionName,
    String? name,
    bool useTmux = true,
    bool startupResumeOnly = false,
    SshConnection? existing,
    int cols = 80,
    int rows = 24,
  }) async {
    final sessionName = useTmux
        ? (tmuxSessionName ?? TmuxStartup.suggestName(hostLabel: host.label, hostDefault: host.tmuxSessionName))
        : null;

    if (useTmux && sessionName != null) {
      final open = findWorkspaceByTmuxSession(host.id, sessionName);
      if (open != null) {
        if (existing != null && existing.isConnected) {
          try {
            await existing.disconnect();
          } catch (_) {}
        }
        focusTmuxSession(open.id, sessionName);
        return open;
      }
    }

    final settings = await _settings();
    final connection = await _connectHost(host, existing: existing);
    final paneId = _uuid.v4();
    final channelId = _uuid.v4();
    final resolvedSessionName = useTmux
        ? sessionName!
        : 'shell-${paneId.substring(0, 8)}';

    await connection.openShell(channelId: channelId, width: cols, height: rows);

    final pane = TerminalPane(
      id: paneId,
      channelId: channelId,
      cwd: cwd,
      tmuxSessionName: resolvedSessionName,
      useTmux: useTmux,
      terminal: Terminal(maxLines: 2000),
      controller: TerminalController(),
    );

    final workspaceName = name?.trim().isNotEmpty == true
        ? name!.trim()
        : (useTmux ? resolvedSessionName : host.label);

    final workspaceId = _uuid.v4();
    final workspace = Workspace(
      id: workspaceId,
      name: workspaceName,
      hostId: host.id,
      connection: connection,
      terminals: [pane],
      auxTabs: [
        WorkspaceTab(id: _uuid.v4(), type: WorkspaceTabType.files, title: 'Files', path: cwd),
      ],
    );

    connection.onDisconnected = () => _markWorkspaceDisconnected(workspaceId);
    _bindPane(workspace, pane);

    await _runPaneStartup(
      workspace: workspace,
      pane: pane,
      host: host,
      tmuxMode: pane.useTmux ? _resolveTmuxMode(host, settings) : HostTmuxMode.off,
      resumeOnly: startupResumeOnly,
    );

    await _saveBookmark(workspace, pane, host);
    await _ref.read(hostRepositoryProvider).recordRecent(host.id);
    _workspaces[workspaceId] = workspace;
    _syncForegroundService();
    notifyListeners();
    return workspace;
  }

  Future<Workspace> resumeSession(
    ResumableSession bookmark, {
    bool? useTmux,
    SshConnection? existing,
  }) async {
    final effectiveUseTmux = useTmux ?? bookmark.useTmux;
    if (effectiveUseTmux) {
      final open = findWorkspaceByTmuxSession(bookmark.hostId, bookmark.tmuxSessionName);
      if (open != null) {
        if (existing != null && existing.isConnected) {
          try {
            await existing.disconnect();
          } catch (_) {}
        }
        focusTmuxSession(open.id, bookmark.tmuxSessionName);
        return open;
      }
    }

    final host = await _requireHost(bookmark.hostId);
    final workspace = await createWorkspace(
      host: host,
      cwd: bookmark.cwd,
      tmuxSessionName: bookmark.tmuxSessionName,
      name: bookmark.tmuxSessionName,
      useTmux: effectiveUseTmux,
      startupResumeOnly: effectiveUseTmux,
      existing: existing,
    );
    notifyListeners();
    return workspace;
  }

  Future<TerminalPane> addTerminal(
    String workspaceId, {
    String? cwd,
    String? tmuxSessionName,
    bool useTmux = true,
    bool resumeOnly = false,
    HostTmuxMode? tmuxModeOverride,
  }) async {
    final workspace = _workspaces[workspaceId];
    if (workspace == null) throw StateError('Workspace not found');
    final host = await _requireHost(workspace.hostId);
    final settings = await _settings();

    final paneId = _uuid.v4();
    final channelId = _uuid.v4();
    final paneCwd = cwd ??
        (workspace.terminals.isNotEmpty ? workspace.terminals.first.cwd : '~');
    final name = useTmux
        ? (tmuxSessionName ??
            TmuxStartup.suggestName(
              hostLabel: host.label,
              hostDefault: host.tmuxSessionName,
              paneIndex: workspace.terminals.length,
            ))
        : 'shell-${paneId.substring(0, 8)}';

    if (useTmux) {
      final open = findWorkspaceByTmuxSession(workspace.hostId, name);
      if (open != null) {
        focusTmuxSession(open.id, name);
        return open.terminals.firstWhere(
          (p) => p.useTmux && p.tmuxSessionName == name,
        );
      }
    }

    await workspace.connection.openShell(channelId: channelId);
    final pane = TerminalPane(
      id: paneId,
      channelId: channelId,
      cwd: paneCwd,
      tmuxSessionName: name,
      useTmux: useTmux,
      terminal: Terminal(maxLines: 2000),
      controller: TerminalController(),
    );

    workspace.terminals.add(pane);
    _bindPane(workspace, pane);
    final tmuxMode = pane.useTmux
        ? (tmuxModeOverride ?? _resolveTmuxMode(host, settings))
        : HostTmuxMode.off;
    await _runPaneStartup(
      workspace: workspace,
      pane: pane,
      host: host,
      tmuxMode: tmuxMode,
      resumeOnly: resumeOnly,
    );
    await _saveBookmark(workspace, pane, host);
    workspace.activeTabIndex = workspace.terminals.length - 1;
    _syncPrimaryFilesTabPath(workspace, pane.cwd);
    notifyListeners();
    return pane;
  }

  Future<void> _saveBookmark(Workspace workspace, TerminalPane pane, Host host) async {
    if (!pane.useTmux) return;
    await _ref.read(resumableSessionStoreProvider).upsert(_bookmarkFromPane(workspace, pane));
    _invalidateResumeList();
  }

  Future<void> saveAllBookmarks() async {
    await refreshResumeBookmarks();
  }

  Future<void> detachPane(String workspaceId, String paneId, {bool keepBookmark = true}) async {
    final workspace = _workspaces[workspaceId];
    if (workspace == null) return;
    final pane = workspace.terminals.firstWhere((p) => p.id == paneId);
    if (pane.useTmux) {
      workspace.connection.write(pane.channelId, TmuxStartup.detach());
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    await workspace.connection.closeShell(pane.channelId);
    workspace.terminals.removeWhere((p) => p.id == paneId);
    if (workspace.activeTabIndex >= workspace.terminals.length + workspace.auxTabs.length) {
      workspace.activeTabIndex = 0;
    }
    if (keepBookmark) {
      final host = await _requireHost(workspace.hostId);
      await _saveBookmark(workspace, pane, host);
    }
    if (workspace.terminals.isEmpty) {
      workspace.activeTabIndex = 0;
    }
    notifyListeners();
  }

  Future<void> endPaneSession(String workspaceId, String paneId) async {
    final workspace = _workspaces[workspaceId];
    if (workspace == null) return;
    final pane = workspace.terminals.firstWhere((p) => p.id == paneId);
    if (pane.useTmux) {
      workspace.connection.write(pane.channelId, TmuxStartup.killSession(pane.tmuxSessionName));
      await _ref.read(resumableSessionStoreProvider).removeByName(workspace.hostId, pane.tmuxSessionName);
      _invalidateResumeList();
    }
    await detachPane(workspaceId, paneId, keepBookmark: false);
  }

  Future<void> renamePaneSession(String workspaceId, String paneId, String newName) async {
    if (!TmuxStartup.isValidSessionName(newName)) {
      throw ArgumentError('Invalid session name');
    }
    final workspace = _workspaces[workspaceId];
    if (workspace == null) return;
    final pane = workspace.terminals.firstWhere((p) => p.id == paneId);
    if (!pane.useTmux) {
      throw StateError('Cannot rename a plain shell tab');
    }
    final oldName = pane.tmuxSessionName;
    workspace.connection.write(
      pane.channelId,
      "tmux rename-session -t ${_shellQuote(oldName)} ${_shellQuote(newName)}\n",
    );
    pane.tmuxSessionName = newName;
    if (workspace.terminals.length == 1 && workspace.name == oldName) {
      workspace.name = newName;
    }
    await _ref.read(resumableSessionStoreProvider).removeByName(workspace.hostId, oldName);
    _invalidateResumeList();
    final host = await _requireHost(workspace.hostId);
    await _saveBookmark(workspace, pane, host);
    notifyListeners();
  }

  Future<void> closeWorkspace(String workspaceId, {bool endSessions = false}) async {
    final workspace = _workspaces.remove(workspaceId);
    if (workspace == null) return;

    final settings = await _settings();
    for (final pane in workspace.terminals) {
      if (!pane.useTmux) continue;
      if (endSessions) {
        workspace.connection.write(pane.channelId, TmuxStartup.killSession(pane.tmuxSessionName));
        await _ref.read(resumableSessionStoreProvider).removeByName(workspace.hostId, pane.tmuxSessionName);
        _invalidateResumeList();
      } else if (settings.detachOnAppClose) {
        workspace.connection.write(pane.channelId, TmuxStartup.detach());
        final host = await _requireHost(workspace.hostId);
        await _saveBookmark(workspace, pane, host);
      }
    }
    if (!endSessions && settings.detachOnAppClose) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    await workspace.connection.disconnect();
    _syncForegroundService();
    notifyListeners();
  }

  Future<bool> reconnect(String workspaceId) async {
    final workspace = _workspaces[workspaceId];
    if (workspace == null) return false;
    if (workspace.connection.isConnected) return true;
    if (workspace.state == SessionState.reconnecting) return false;

    workspace.state = SessionState.reconnecting;
    notifyListeners();

    try {
      final host = await _requireHost(workspace.hostId);
      final settings = await _settings();
      final savedPanes = workspace.terminals
          .map(
            (p) => (
              cwd: p.cwd,
              name: p.tmuxSessionName,
              useTmux: p.useTmux,
              terminal: p.terminal,
              controller: p.controller,
            ),
          )
          .toList();

      try {
        await workspace.connection.disconnect();
      } catch (_) {}

      final connection = await _connectHost(host);
      workspace.connection = connection;
      connection.onDisconnected = () => _markWorkspaceDisconnected(workspaceId);

      workspace.terminals.clear();
      for (final saved in savedPanes) {
        final paneId = _uuid.v4();
        final channelId = _uuid.v4();
        await connection.openShell(
          channelId: channelId,
          width: saved.terminal.viewWidth,
          height: saved.terminal.viewHeight,
        );
        final pane = TerminalPane(
          id: paneId,
          channelId: channelId,
          cwd: saved.cwd,
          tmuxSessionName: saved.name,
          useTmux: saved.useTmux,
          terminal: saved.terminal,
          controller: saved.controller,
        );
        workspace.terminals.add(pane);
        _bindPane(workspace, pane);
        await _runPaneStartup(
          workspace: workspace,
          pane: pane,
          host: host,
          tmuxMode: saved.useTmux ? _resolveTmuxMode(host, settings) : HostTmuxMode.off,
          resumeOnly: saved.useTmux,
        );
      }

      workspace.state = SessionState.connected;
      _syncForegroundService();
      notifyListeners();
      return true;
    } catch (_) {
      workspace.state = SessionState.disconnected;
      for (final p in workspace.terminals) {
        p.state = SessionState.disconnected;
      }
      _syncForegroundService();
      notifyListeners();
      return false;
    }
  }

  Future<void> reconnectAllDisconnected() async {
    for (final w in _workspaces.values.toList()) {
      if (w.aggregateState == SessionState.disconnected) {
        await reconnect(w.id);
      }
    }
  }

  void _markWorkspaceDisconnected(String workspaceId) {
    final w = _workspaces[workspaceId];
    if (w == null) return;
    w.state = SessionState.disconnected;
    for (final p in w.terminals) {
      p.state = SessionState.disconnected;
    }
    _syncForegroundService();
    notifyListeners();
  }

  void sendCommand(String workspaceId, String command, {String? paneId}) {
    final workspace = _workspaces[workspaceId];
    if (workspace == null || !workspace.connection.isConnected) return;
    final pane = paneId != null
        ? workspace.terminals.firstWhere((p) => p.id == paneId)
        : workspace.activeTerminal;
    if (pane == null) return;
    workspace.connection.write(pane.channelId, '$command\n');
    pane.state = SessionState.processing;
    notifyListeners();
  }

  void sendBytes(String workspaceId, Uint8List bytes, {String? paneId}) {
    final workspace = _workspaces[workspaceId];
    if (workspace == null || !workspace.connection.isConnected) return;
    final pane = paneId != null
        ? workspace.terminals.firstWhere((p) => p.id == paneId)
        : workspace.activeTerminal;
    if (pane == null) return;
    workspace.connection.writeBytes(pane.channelId, bytes);
  }

  Future<List<RemoteFileEntry>> listDirectory(String workspaceId, String path) async {
    final w = _workspaces[workspaceId];
    if (w == null || !w.connection.isConnected) throw StateError('Connection lost');
    return w.connection.listDirectory(path);
  }

  Future<void> createDirectory(String workspaceId, String path) async {
    final w = _workspaces[workspaceId];
    if (w == null || !w.connection.isConnected) throw StateError('Connection lost');
    await w.connection.createDirectory(path);
  }

  Future<void> uploadFile(String workspaceId, String localPath, String remotePath) async {
    final w = _workspaces[workspaceId];
    if (w == null || !w.connection.isConnected) throw StateError('Connection lost');
    await w.connection.uploadFile(localPath, remotePath);
  }

  Future<void> uploadBytes(String workspaceId, Uint8List data, String remotePath) async {
    final w = _workspaces[workspaceId];
    if (w == null || !w.connection.isConnected) throw StateError('Connection lost');
    await w.connection.uploadBytes(data, remotePath);
  }

  Future<String> readFileText(String workspaceId, String remotePath) async {
    final w = _workspaces[workspaceId];
    if (w == null || !w.connection.isConnected) throw StateError('Connection lost');
    return w.connection.readFileText(remotePath);
  }

  Future<SshConnection> _requireConnection(String workspaceId) async {
    final w = _workspaces[workspaceId];
    if (w == null || !w.connection.isConnected) throw StateError('Connection lost');
    return w.connection;
  }

  String _gitInRepo(String repoRoot, String args) => 'cd ${_shellQuote(repoRoot)} && git $args';

  Future<String?> resolveGitRepoRoot(String workspaceId, String cwd) async {
    final conn = await _requireConnection(workspaceId);
    final result = await conn.executeResult(
      'cd ${_shellQuote(cwd)} && git rev-parse --show-toplevel 2>/dev/null',
      timeout: const Duration(seconds: 10),
    );
    if (result.exitCode != 0) return null;
    return result.stdout.trim();
  }

  Future<GitRepoSnapshot> loadGitSnapshot(String workspaceId, String cwd) async {
    final conn = await _requireConnection(workspaceId);
    final repoRoot = await resolveGitRepoRoot(workspaceId, cwd);
    if (repoRoot == null) throw GitNotARepositoryException();

    const delimiter = '---GITMGR---';
    final script = '''
cd ${_shellQuote(repoRoot)} && \\
BR=\$(git branch --show-current 2>/dev/null) && \\
if [ -z "\$BR" ]; then echo "DETACHED:\$(git rev-parse --short HEAD)"; else echo "\$BR"; fi && \\
echo '$delimiter' && \\
git rev-parse --abbrev-ref @{u} 2>/dev/null || true && \\
echo '$delimiter' && \\
git rev-list --left-right --count @{u}...HEAD 2>/dev/null || true && \\
echo '$delimiter' && \\
git remote get-url origin 2>/dev/null || true && \\
echo '$delimiter' && \\
git status --porcelain
''';

    final result = await conn.executeResult(script.trim(), timeout: const Duration(seconds: 20));
    final snapshot = GitParsers.parseSnapshot(result.stdout, repoRoot);

    final branchResult = await conn.executeCapture(
      _gitInRepo(repoRoot, 'branch -a --no-color'),
      timeout: const Duration(seconds: 15),
    );
    final branches = GitParsers.parseBranches(branchResult, snapshot.branch);

    return GitRepoSnapshot(
      repoRoot: snapshot.repoRoot,
      branch: snapshot.branch,
      detached: snapshot.detached,
      staged: snapshot.staged,
      unstaged: snapshot.unstaged,
      untracked: snapshot.untracked,
      conflicted: snapshot.conflicted,
      ahead: snapshot.ahead,
      behind: snapshot.behind,
      upstream: snapshot.upstream,
      remoteUrl: snapshot.remoteUrl,
      branches: branches,
    );
  }

  Future<String> gitFileDiff(
    String workspaceId,
    String repoRoot,
    String path, {
    bool staged = false,
  }) async {
    final conn = await _requireConnection(workspaceId);
    final flag = staged ? '--cached' : '';
    final result = await conn.executeResult(
      _gitInRepo(repoRoot, 'diff $flag -- ${_shellQuote(path)}'),
      timeout: const Duration(seconds: 30),
    );
    return result.stdout;
  }

  Future<void> gitStageFile(String workspaceId, String repoRoot, String path) async {
    final conn = await _requireConnection(workspaceId);
    final ok = await conn.executeSuccess(_gitInRepo(repoRoot, 'add -- ${_shellQuote(path)}'));
    if (!ok) throw StateError('Failed to stage file');
  }

  Future<void> gitUnstageFile(String workspaceId, String repoRoot, String path) async {
    final conn = await _requireConnection(workspaceId);
    final ok = await conn.executeSuccess(
      _gitInRepo(repoRoot, 'restore --staged -- ${_shellQuote(path)}'),
    );
    if (!ok) throw StateError('Failed to unstage file');
  }

  Future<void> gitStageAll(String workspaceId, String repoRoot) async {
    final conn = await _requireConnection(workspaceId);
    final ok = await conn.executeSuccess(_gitInRepo(repoRoot, 'add -A'));
    if (!ok) throw StateError('Failed to stage all');
  }

  Future<void> gitUnstageAll(String workspaceId, String repoRoot) async {
    final conn = await _requireConnection(workspaceId);
    final ok = await conn.executeSuccess(_gitInRepo(repoRoot, 'reset HEAD'));
    if (!ok) throw StateError('Failed to unstage all');
  }

  Future<void> gitDiscardFile(String workspaceId, String repoRoot, String path) async {
    final conn = await _requireConnection(workspaceId);
    final ok = await conn.executeSuccess(
      _gitInRepo(repoRoot, 'restore --worktree -- ${_shellQuote(path)}'),
    );
    if (!ok) throw StateError('Failed to discard changes');
  }

  Future<GitCommandResult> gitCommit(
    String workspaceId,
    String repoRoot,
    String summary, {
    String? description,
  }) async {
    final conn = await _requireConnection(workspaceId);
    final trimmed = summary.trim();
    if (trimmed.isEmpty) {
      return const GitCommandResult(success: false, message: 'Commit summary is required');
    }
    var cmd = _gitInRepo(repoRoot, 'commit -m ${_shellQuote(trimmed)}');
    final body = description?.trim();
    if (body != null && body.isNotEmpty) {
      cmd = _gitInRepo(repoRoot, 'commit -m ${_shellQuote(trimmed)} -m ${_shellQuote(body)}');
    }
    final result = await conn.executeResult(cmd, timeout: const Duration(seconds: 30));
    final message = result.stderr.trim().isNotEmpty ? result.stderr.trim() : result.stdout.trim();
    return GitCommandResult(
      success: result.exitCode == 0,
      message: message.isEmpty ? (result.exitCode == 0 ? 'Committed' : 'Commit failed') : message,
    );
  }

  Future<GitCommandResult> gitFetch(String workspaceId, String repoRoot) async {
    final conn = await _requireConnection(workspaceId);
    final result = await conn.executeResult(
      _gitInRepo(repoRoot, 'fetch'),
      timeout: const Duration(seconds: 60),
    );
    return _gitResult(result.stdout, result.stderr, result.exitCode);
  }

  Future<GitCommandResult> gitPull(String workspaceId, String repoRoot) async {
    final conn = await _requireConnection(workspaceId);
    final result = await conn.executeResult(
      _gitInRepo(repoRoot, 'pull --ff-only'),
      timeout: const Duration(seconds: 60),
    );
    if (result.exitCode != 0 && result.stderr.contains('Not possible to fast-forward')) {
      final mergeResult = await conn.executeResult(
        _gitInRepo(repoRoot, 'pull'),
        timeout: const Duration(seconds: 60),
      );
      return _gitResult(mergeResult.stdout, mergeResult.stderr, mergeResult.exitCode);
    }
    return _gitResult(result.stdout, result.stderr, result.exitCode);
  }

  Future<GitCommandResult> gitPush(String workspaceId, String repoRoot) async {
    final conn = await _requireConnection(workspaceId);
    final result = await conn.executeResult(
      _gitInRepo(repoRoot, 'push'),
      timeout: const Duration(seconds: 60),
    );
    return _gitResult(result.stdout, result.stderr, result.exitCode);
  }

  Future<GitCommandResult> gitCheckoutBranch(String workspaceId, String repoRoot, String branch) async {
    final conn = await _requireConnection(workspaceId);
    final localBranch = branch.startsWith('remotes/') ? branch.split('/').skip(2).join('/') : branch;
    final result = await conn.executeResult(
      _gitInRepo(repoRoot, 'switch ${_shellQuote(localBranch)}'),
      timeout: const Duration(seconds: 30),
    );
    if (result.exitCode != 0) {
      final fallback = await conn.executeResult(
        _gitInRepo(repoRoot, 'checkout ${_shellQuote(localBranch)}'),
        timeout: const Duration(seconds: 30),
      );
      return _gitResult(fallback.stdout, fallback.stderr, fallback.exitCode);
    }
    return _gitResult(result.stdout, result.stderr, result.exitCode);
  }

  Future<GitCommandResult> gitCreateBranch(
    String workspaceId,
    String repoRoot,
    String name, {
    bool checkout = true,
  }) async {
    final conn = await _requireConnection(workspaceId);
    final branchName = name.trim();
    final cmd = checkout
        ? _gitInRepo(repoRoot, 'switch -c ${_shellQuote(branchName)}')
        : _gitInRepo(repoRoot, 'branch ${_shellQuote(branchName)}');
    final result = await conn.executeResult(cmd, timeout: const Duration(seconds: 30));
    if (result.exitCode != 0 && checkout) {
      final fallback = await conn.executeResult(
        _gitInRepo(repoRoot, 'checkout -b ${_shellQuote(branchName)}'),
        timeout: const Duration(seconds: 30),
      );
      return _gitResult(fallback.stdout, fallback.stderr, fallback.exitCode);
    }
    return _gitResult(result.stdout, result.stderr, result.exitCode);
  }

  Future<List<GitCommitInfo>> gitLog(String workspaceId, String repoRoot, {int limit = 50}) async {
    final conn = await _requireConnection(workspaceId);
    final output = await conn.executeCapture(
      _gitInRepo(
        repoRoot,
        "log -n $limit --format='%H%x00%h%x00%s%x00%an%x00%ar'",
      ),
      timeout: const Duration(seconds: 20),
    );
    return GitParsers.parseLog(output);
  }

  Future<String> gitShowCommit(String workspaceId, String repoRoot, String sha) async {
    final conn = await _requireConnection(workspaceId);
    final result = await conn.executeResult(
      _gitInRepo(repoRoot, 'show --format=fuller ${_shellQuote(sha)}'),
      timeout: const Duration(seconds: 30),
    );
    if (result.exitCode != 0) {
      throw StateError(result.stderr.trim().isNotEmpty ? result.stderr.trim() : 'Could not load commit');
    }
    return result.stdout;
  }

  GitCommandResult _gitResult(String stdout, String stderr, int? exitCode) {
    final message = stderr.trim().isNotEmpty ? stderr.trim() : stdout.trim();
    return GitCommandResult(
      success: exitCode == 0,
      message: message.isEmpty ? (exitCode == 0 ? 'OK' : 'Command failed') : message,
    );
  }

  Future<int> ensureBrowserForward(String workspaceId, String tabId, int remotePort) async {
    final w = _workspaces[workspaceId]!;
    final existing = w.browserForwardsByTabId[tabId];
    if (existing != null) return existing.localPort;
    final forward = await w.connection.forwardRemotePort(remotePort);
    w.browserForwardsByTabId[tabId] = forward;
    return forward.localPort;
  }

  Future<void> reconfigureBrowserForward(String workspaceId, String tabId, int remotePort) async {
    final w = _workspaces[workspaceId];
    if (w == null) return;
    final existing = w.browserForwardsByTabId.remove(tabId);
    if (existing != null) {
      await w.connection.closeForward(existing);
    }
    await ensureBrowserForward(workspaceId, tabId, remotePort);
  }

  void updateAuxTab(
    String workspaceId,
    String tabId,
    WorkspaceTab Function(WorkspaceTab tab) update, {
    bool notify = true,
  }) {
    final w = _workspaces[workspaceId];
    if (w == null) return;
    final index = w.auxTabs.indexWhere((t) => t.id == tabId);
    if (index < 0) return;
    w.auxTabs[index] = update(w.auxTabs[index]);
    if (notify) notifyListeners();
  }

  void updateWorkspaceUi(
    String workspaceId, {
    int? activeTabIndex,
    WorkspaceViewMode? viewMode,
    List<WorkspaceTab>? auxTabs,
  }) {
    final w = _workspaces[workspaceId];
    if (w == null) return;
    if (activeTabIndex != null) {
      w.activeTabIndex = activeTabIndex;
      if (activeTabIndex < w.terminals.length) {
        _syncPrimaryFilesTabPath(w, w.terminals[activeTabIndex].cwd);
      }
    }
    if (viewMode != null) w.viewMode = viewMode;
    if (auxTabs != null) w.auxTabs = auxTabs;
    notifyListeners();
  }

  void addAuxTab(String workspaceId, WorkspaceTab tab) {
    final w = _workspaces[workspaceId];
    if (w == null) return;
    w.auxTabs.add(tab);
    w.activeTabIndex = w.terminals.length + w.auxTabs.length - 1;
    notifyListeners();
  }

  Future<void> removeAuxTab(String workspaceId, int auxIndex) async {
    final w = _workspaces[workspaceId];
    if (w == null) return;
    final tab = w.auxTabs[auxIndex];
    final forward = w.browserForwardsByTabId.remove(tab.id);
    w.auxTabs.removeAt(auxIndex);
    if (w.activeTabIndex >= w.terminals.length + w.auxTabs.length) {
      w.activeTabIndex = w.terminals.length + w.auxTabs.length - 1;
    }
    notifyListeners();
    if (forward != null) {
      await w.connection.closeForward(forward);
    }
  }

  void addPendingImage(String workspaceId, String path) {
    _workspaces[workspaceId]?.pendingImagePaths.add(path);
    notifyListeners();
  }

  void removePendingImage(String workspaceId, int index) {
    _workspaces[workspaceId]?.pendingImagePaths.removeAt(index);
    notifyListeners();
  }

  Future<void> refreshConnectionHealth() async {
    var changed = false;
    for (final w in _workspaces.values) {
      if (!w.connection.isConnected) {
        if (w.state != SessionState.disconnected) {
          w.state = SessionState.disconnected;
          changed = true;
        }
        continue;
      }
      try {
        await w.connection.ping();
      } catch (_) {
        if (w.state != SessionState.disconnected) {
          w.state = SessionState.disconnected;
          changed = true;
        }
      }
    }
    if (changed) {
      _syncForegroundService();
      notifyListeners();
    }
  }

  void _syncForegroundService() {
    final count = _workspaces.values.where((w) => w.connection.isConnected).length;
    if (count > 0) {
      SessionForeground.start(count);
    } else {
      SessionForeground.stop();
    }
  }

  Future<WorkspaceTemplate> saveAsTemplate(String workspaceId, String name) async {
    final w = _workspaces[workspaceId];
    if (w == null) throw StateError('Workspace not found');
    final template = WorkspaceTemplate(
      id: _uuid.v4(),
      name: name,
      hostId: w.hostId,
      entries: w.terminals
          .map(
            (p) => WorkspaceTemplateEntry(
              cwd: p.cwd,
              tmuxSessionName: p.tmuxSessionName,
              label: p.tmuxSessionName,
            ),
          )
          .toList(),
    );
    await _ref.read(workspaceRepositoryProvider).save(template);
    return template;
  }

  Future<Workspace> openTemplate(
    WorkspaceTemplate template, {
    bool useTmux = true,
    SshConnection? existing,
  }) async {
    final host = await _requireHost(template.hostId);
    if (template.entries.isEmpty) {
      return createWorkspace(host: host, cwd: '~', useTmux: useTmux, existing: existing);
    }

    final first = template.entries.first;
    final workspace = await createWorkspace(
      host: host,
      cwd: first.cwd,
      tmuxSessionName: first.tmuxSessionName,
      name: template.name,
      useTmux: useTmux,
      existing: existing,
    );

    for (var i = 1; i < template.entries.length; i++) {
      final entry = template.entries[i];
      await addTerminal(
        workspace.id,
        cwd: entry.cwd,
        tmuxSessionName: entry.tmuxSessionName,
        useTmux: useTmux,
      );
    }
    return workspace;
  }

  Future<void> disposeAll() async {
    for (final id in _workspaces.keys.toList()) {
      await closeWorkspace(id);
    }
  }
}

final secureStorageProvider = Provider<SecureStorageService>((ref) => SecureStorageService());

final knownHostsStoreProvider = Provider<KnownHostsStore>((ref) => KnownHostsStore());

final recentPathsStoreProvider = Provider<RecentPathsStore>((ref) => RecentPathsStore());

final hostRepositoryProvider = Provider<HostRepository>((ref) {
  return HostRepository(ref.watch(secureStorageProvider));
});

final workspaceManagerProvider = ChangeNotifierProvider<WorkspaceManager>((ref) {
  ref.keepAlive();
  final manager = WorkspaceManager(ref);
  ref.onDispose(() => manager.disposeAll());
  return manager;
});
