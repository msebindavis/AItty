import 'package:xterm/xterm.dart';

import 'session.dart';
import 'workspace_tab.dart';
import '../services/ssh_connection.dart';

enum WorkspaceViewMode { focus, split }

class TerminalPane {
  TerminalPane({
    required this.id,
    required this.channelId,
    required this.cwd,
    required this.tmuxSessionName,
    required this.terminal,
    required this.controller,
    this.useTmux = true,
    this.state = SessionState.connected,
    this.lastOutputPreview = '',
  });

  final String id;
  final String channelId;
  String cwd;
  String tmuxSessionName;
  bool useTmux;
  SessionState state;
  String lastOutputPreview;
  final Terminal terminal;
  final TerminalController controller;

  String get displayTitle => useTmux ? tmuxSessionName : 'Shell';
}

class Workspace {
  Workspace({
    required this.id,
    required this.name,
    required this.hostId,
    required this.connection,
    required this.terminals,
    required this.auxTabs,
    this.activeTabIndex = 0,
    this.viewMode = WorkspaceViewMode.focus,
    this.state = SessionState.connected,
    this.pendingImagePaths = const [],
  });

  final String id;
  String name;
  final String hostId;
  SshConnection connection;
  List<TerminalPane> terminals;
  List<WorkspaceTab> auxTabs;
  int activeTabIndex;
  WorkspaceViewMode viewMode;
  SessionState state;
  List<String> pendingImagePaths;
  final Map<String, int> portForwardsByTabId = {};

  SessionState get aggregateState {
    if (terminals.any((t) => t.state == SessionState.awaitingInput)) {
      return SessionState.awaitingInput;
    }
    if (!connection.isConnected || terminals.any((t) => t.state == SessionState.disconnected)) {
      return SessionState.disconnected;
    }
    if (state == SessionState.reconnecting) return SessionState.reconnecting;
    if (terminals.any((t) => t.state == SessionState.processing)) {
      return SessionState.processing;
    }
    if (terminals.every((t) => t.state == SessionState.idle)) return SessionState.idle;
    return SessionState.connected;
  }

  int get terminalTabCount => terminals.length;

  bool get isTerminalTabActive => activeTabIndex < terminals.length;

  TerminalPane? get activeTerminal =>
      isTerminalTabActive ? terminals[activeTabIndex] : null;

  WorkspaceTab? get activeAuxTab {
    final auxIndex = activeTabIndex - terminals.length;
    if (auxIndex < 0 || auxIndex >= auxTabs.length) return null;
    return auxTabs[auxIndex];
  }
}
