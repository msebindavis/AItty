import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import 'package:xterm/xterm.dart';

import '../../core/constants/spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/obsidian_colors.dart';
import '../../models/host.dart';
import '../../models/session.dart';
import '../../models/workspace.dart';
import '../../models/workspace_tab.dart';
import '../../services/snippet_repository.dart';
import '../../services/workspace_repository.dart';
import '../../services/workspace_manager.dart';
import '../../utils/command_history.dart';
import '../../utils/route_transition.dart';
import '../../utils/speech_dictation.dart';
import '../../utils/terminal_input.dart';
import '../../utils/open_workspace.dart';
import '../../widgets/section_header.dart';
import '../../widgets/session_name_dialog.dart';
import '../../widgets/tmux_missing_dialog.dart';
import 'browser_tab.dart';
import 'command_editor_sheet.dart';
import 'files_tab.dart';
import 'git_manager_tab.dart';
import 'terminal_keyboard/extended_keyboard_sheet.dart';
import 'terminal_keyboard/terminal_gesture_layer.dart';
import 'terminal_keyboard/terminal_key_catalog.dart';
import 'terminal_keyboard/terminal_keyboard_panel.dart';
import 'terminal_theme.dart';
import 'scrolly.dart';

class WorkspaceScreen extends ConsumerStatefulWidget {
  const WorkspaceScreen({super.key, required this.workspaceId});

  final String workspaceId;

  @override
  ConsumerState<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends ConsumerState<WorkspaceScreen> {
  final _commandController = TextEditingController();
  final _uuid = const Uuid();
  bool _ctrl = false;
  bool _alt = false;
  String? _chromeSnapshot;
  bool _terminalReady = false;
  bool _commandBarReady = false;
  final _commandFocusNode = FocusNode();
  final _terminalFocusNode = FocusNode();
  final _terminalViewKey = GlobalKey<TerminalViewState>();
  final _commandHistoryByPaneId = <String, CommandHistory>{};
  String? _trackedInputPaneId;
  final _speechDictation = SpeechDictation();
  String _dictationPrefix = '';
  bool _dictationListening = false;
  double _terminalFontScale = 1;
  List<TerminalSnippet> _snippets = const [];
  late final WorkspaceManager _workspaceManager;

  @override
  void initState() {
    super.initState();
    _workspaceManager = ref.read(workspaceManagerProvider);
    _workspaceManager.addListener(_onWorkspaceManagerChanged);
    _commandFocusNode.addListener(_onCommandFocusChanged);
    _terminalFocusNode.addListener(_onTerminalFocusChanged);
    _commandFocusNode.onKeyEvent = _handleCommandFocusKey;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncCommandInputPane();
      _scheduleContentMount();
    });
    _loadSnippets();
  }

  @override
  void didUpdateWidget(covariant WorkspaceScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspaceId == widget.workspaceId) return;
    _commandHistoryByPaneId.clear();
    _trackedInputPaneId = null;
    _commandController.clear();
    _dictationPrefix = '';
    _dictationListening = false;
    _syncCommandInputPane();
  }

  void _onCommandFocusChanged() {
    if (mounted) setState(() {});
  }

  void _onTerminalFocusChanged() {
    if (mounted) setState(() {});
  }

  bool get _useTerminalSoftKeyboard => Platform.isAndroid || Platform.isIOS;

  bool get _terminalInputActive => _terminalFocusNode.hasFocus && !_commandFocusNode.hasFocus;

  void _focusTerminal({bool showSoftKeyboard = false}) {
    _commandFocusNode.unfocus();
    final terminal = _terminalViewKey.currentState;
    if (terminal != null) {
      terminal.focusForInput(showSoftKeyboard: showSoftKeyboard && _useTerminalSoftKeyboard);
      return;
    }
    _terminalFocusNode.requestFocus();
  }

  void _dismissTerminalInput() {
    _terminalViewKey.currentState?.dismissInput();
    if (!_terminalFocusNode.hasFocus) return;
    _terminalFocusNode.unfocus();
  }

  CommandHistory get _commandHistory {
    final paneId = _activePane?.id;
    if (paneId == null) return CommandHistory();
    return _commandHistoryByPaneId.putIfAbsent(paneId, CommandHistory.new);
  }

  /// Clears draft input when the active tmux pane changes (tab switch, attach, resume).
  void _syncCommandInputPane() {
    final paneId = _activePane?.id;
    if (paneId == _trackedInputPaneId) return;
    _trackedInputPaneId = paneId;
    _commandController.clear();
    _commandHistory.resetBrowse();
    _dictationPrefix = '';
    if (_dictationListening) {
      unawaited(_speechDictation.stop());
      _dictationListening = false;
    }
    if (mounted) setState(() {});
  }

  Future<void> _loadSnippets() async {
    final snippets = await ref.read(snippetRepositoryProvider).loadAll();
    if (mounted) setState(() => _snippets = snippets);
  }

  KeyEventResult _handleCommandFocusKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _navigateCommandHistoryOlder();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _navigateCommandHistoryNewer();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _scheduleContentMount() {
    FocusManager.instance.primaryFocus?.unfocus();
    Future<void>.delayed(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      setState(() => _terminalReady = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _commandBarReady = true);
        _focusTerminal();
      });
    });
  }

  /// Only rebuild workspace chrome when tabs, state, or pending images change —
  /// not on every SSH stdout chunk (which would thrash [TerminalView]).
  void _onWorkspaceManagerChanged() {
    if (!mounted) return;
    final workspace = _workspaceManager.getWorkspace(widget.workspaceId);
    final next = _snapshotChrome(workspace);
    if (next == _chromeSnapshot) return;
    _chromeSnapshot = next;
    _syncCommandInputPane();
    _scheduleChromeRebuild();
  }

  void _scheduleChromeRebuild() {
    if (!mounted) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle || phase == SchedulerPhase.postFrameCallbacks) {
      setState(() {});
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  void _syncChromeFromWorkspace() {
    _chromeSnapshot = _snapshotChrome(_workspace);
    _scheduleChromeRebuild();
  }

  String _snapshotChrome(Workspace? workspace) {
    if (workspace == null) return 'ended';
    final terminalIds = workspace.terminals.map((p) => p.id).join(',');
    final terminalNames = workspace.terminals.map((p) => p.tmuxSessionName).join(',');
    final auxMeta = workspace.auxTabs
        .map((t) => '${t.id}:${t.type.name}:${t.title}:${t.path ?? ''}:${t.remotePort}')
        .join(',');
    return '${workspace.aggregateState.index}|${workspace.state.index}|$terminalIds|$terminalNames|'
        '${workspace.auxTabs.length}|$auxMeta|${workspace.activeTabIndex}|${workspace.pendingImagePaths.length}';
  }

  @override
  void dispose() {
    _workspaceManager.removeListener(_onWorkspaceManagerChanged);
    _speechDictation.dispose();
    _commandController.dispose();
    _commandFocusNode.dispose();
    _terminalFocusNode.dispose();
    super.dispose();
  }

  bool get _commandBarFocused => _commandFocusNode.hasFocus;

  bool get _terminalShortcutsEnabled {
    final workspace = _workspace;
    if (workspace == null || !workspace.isTerminalTabActive) return false;
    return !_commandBarFocused;
  }

  void _sendTerminalBytes(Uint8List bytes, {bool clearModifiers = true}) {
    _sendRaw(bytes);
    if (clearModifiers && (_ctrl || _alt) && mounted) {
      setState(() {
        _ctrl = false;
        _alt = false;
      });
    }
  }

  void _sendArrow(TerminalArrowDirection direction) {
    if (_ctrl && _alt) {
      _sendTerminalBytes(TerminalInput.modifiedArrow(direction: direction, modifier: 7));
      return;
    }
    if (_ctrl) {
      _sendTerminalBytes(TerminalInput.ctrlArrow(direction));
      return;
    }
    if (_alt) {
      _sendTerminalBytes(TerminalInput.altArrow(direction));
      return;
    }
    _sendTerminalBytes(TerminalInput.arrow(direction), clearModifiers: false);
  }

  void _exitWorkspace() {
    FocusManager.instance.primaryFocus?.unfocus();
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go('/connections');
  }

  Workspace? get _workspace => _workspaceManager.getWorkspace(widget.workspaceId);

  TerminalPane? get _activePane {
    final workspace = _workspace;
    if (workspace == null || !workspace.isTerminalTabActive) return null;
    return workspace.activeTerminal;
  }

  void _sendRaw(Uint8List bytes) {
    final paneId = _activePane?.id;
    _workspaceManager.sendBytes(widget.workspaceId, bytes, paneId: paneId);
  }

  void _sendCommand(String command) {
    if (command.trim().isEmpty) return;
    final paneId = _activePane?.id;
    _workspaceManager.sendCommand(widget.workspaceId, command, paneId: paneId);
    _commandHistory.add(command);
    _commandController.clear();
    _commandHistory.resetBrowse();
    if (mounted) {
      setState(() {});
      _focusTerminal();
    }
  }

  void _setCommandText(String text) {
    _commandController.text = text;
    _commandController.selection = TextSelection.collapsed(offset: text.length);
  }

  void _selectHistoryCommand(String text) {
    _commandHistory.resetBrowse();
    _setCommandText(text);
  }

  void _navigateCommandHistoryOlder() {
    final entry = _commandHistory.older(_commandController.text);
    if (entry != null) _setCommandText(entry);
  }

  void _navigateCommandHistoryNewer() {
    final entry = _commandHistory.newer();
    if (entry != null) _setCommandText(entry);
  }

  Future<void> _toggleVoiceDictation() async {
    if (_dictationListening) {
      await _speechDictation.stop();
      if (mounted) setState(() => _dictationListening = false);
      return;
    }

    _dictationPrefix = _commandController.text;
    if (_dictationPrefix.isNotEmpty) _dictationPrefix = '$_dictationPrefix ';

    await _speechDictation.toggle(
      onResult: (words) {
        if (!mounted) return;
        _setCommandText('$_dictationPrefix$words');
        if (!_speechDictation.listening && _dictationListening) {
          setState(() => _dictationListening = false);
        }
      },
      onError: (message) {
        if (!mounted) return;
        setState(() => _dictationListening = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      },
    );

    if (!mounted) return;
    setState(() => _dictationListening = _speechDictation.listening);
  }

  void _handleTerminalKeyAction(TerminalKeyAction action) {
    switch (action) {
      case TerminalKeyAction.openExtended:
        _openExtendedKeyboard();
        return;
      case TerminalKeyAction.hideKeyboard:
        if (_terminalInputActive) {
          _dismissTerminalInput();
        } else {
          _focusTerminal(showSoftKeyboard: _useTerminalSoftKeyboard);
        }
        return;
      case TerminalKeyAction.toggleCtrl:
        setState(() => _ctrl = !_ctrl);
        return;
      case TerminalKeyAction.toggleAlt:
        setState(() => _alt = !_alt);
        return;
      default:
        break;
    }
    final bytes = TerminalKeyCatalog.bytesFor(action);
    if (bytes != null) _sendTerminalBytes(bytes);
  }

  Future<void> _openExtendedKeyboard() async {
    await ExtendedKeyboardSheet.show(
      context,
      history: _commandHistory.recent(limit: 50),
      snippets: _snippets,
      onKeyAction: _handleTerminalKeyAction,
      onRunCommand: _sendCommand,
      onPasteCommand: _selectHistoryCommand,
      onAddSnippet: (name, script) async {
        await ref.read(snippetRepositoryProvider).add(name: name, script: script);
        await _loadSnippets();
      },
      onDeleteSnippet: (id) async {
        await ref.read(snippetRepositoryProvider).delete(id);
        await _loadSnippets();
      },
    );
    if (mounted) await _loadSnippets();
  }

  Future<void> _pickImage(Workspace workspace) async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      _workspaceManager.addPendingImage(widget.workspaceId, image.path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final workspace = _workspace;
    _chromeSnapshot ??= _snapshotChrome(workspace);
    if (workspace == null) {
      return Scaffold(
        appBar: AppBar(leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: _exitWorkspace)),
        body: Center(child: Text('Workspace ended', style: AppTypography.inter(size: 16))),
      );
    }

    if (workspace.terminals.isEmpty) {
      return _HostSessionHub(
        workspaceId: widget.workspaceId,
        workspace: workspace,
        onBack: _exitWorkspace,
        onEndWorkspace: _endWorkspace,
      );
    }

    final totalTabs = workspace.terminals.length + workspace.auxTabs.length;
    if (totalTabs == 0) {
      return Scaffold(
        appBar: AppBar(leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: _exitWorkspace)),
        body: Center(child: Text('No tabs open', style: AppTypography.inter(size: 16))),
      );
    }

    final activeIndex = workspace.activeTabIndex.clamp(0, totalTabs - 1);
    final isTerminalActive = activeIndex < workspace.terminals.length;

    return Shortcuts(
      shortcuts: _workspaceTerminalShortcuts,
      child: Actions(
        actions: {
          _TerminalBytesIntent: CallbackAction<_TerminalBytesIntent>(
            onInvoke: (intent) {
              if (!_terminalShortcutsEnabled) return null;
              _sendRaw(intent.bytes);
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: false,
          child: Scaffold(
      backgroundColor: isTerminalActive ? hostTerminalTheme.background : ObsidianColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _WorkspaceTabBar(
              workspace: workspace,
              activeIndex: activeIndex,
              onSelect: (i) => _setActiveTab(i),
              onCloseTerminal: (pane) => _closeTerminalTab(pane),
              onCloseAux: (auxIndex) => _closeAuxTab(auxIndex),
              onPaneOverflow: (pane) => _showPaneOverflow(pane),
              onBack: _exitWorkspace,
              onEndWorkspace: _endWorkspace,
              onAdd: () => _showAddTabMenu(workspace),
            ),
            if (workspace.pendingImagePaths.isNotEmpty)
              _ImagePreviewStrip(
                paths: workspace.pendingImagePaths,
                onRemove: (i) => _workspaceManager.removePendingImage(widget.workspaceId, i),
              ),
            if (workspace.aggregateState == SessionState.disconnected)
              Material(
                color: ObsidianColors.surfaceContainerHigh,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                  child: Row(
                    children: [
                      const Icon(Icons.cloud_off, size: 18, color: ObsidianColors.error),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          'Connection lost.',
                          style: AppTypography.inter(size: 13, color: ObsidianColors.error),
                        ),
                      ),
                      TextButton(
                        onPressed: () => _workspaceManager.reconnect(widget.workspaceId),
                        child: const Text('Reconnect'),
                      ),
                    ],
                  ),
                ),
              ),
            if (workspace.state == SessionState.reconnecting)
              Material(
                color: ObsidianColors.surfaceContainerHigh,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: ObsidianColors.primary),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        'Reconnecting…',
                        style: AppTypography.inter(size: 13, color: ObsidianColors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: _terminalReady
                  ? IndexedStack(
                      index: activeIndex,
                      sizing: StackFit.expand,
                      children: List<Widget>.generate(
                        totalTabs,
                        (i) => _buildTab(workspace, i, isActive: i == activeIndex),
                      ),
                    )
                  : ColoredBox(
                      color: isTerminalActive ? hostTerminalTheme.background : ObsidianColors.background,
                      child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                    ),
            ),
            if (_commandBarReady && isTerminalActive) ...[
              _CommandInputBar(
                controller: _commandController,
                focusNode: _commandFocusNode,
                listening: _dictationListening,
                recentCommands: _commandHistory.recent(),
                onSend: () => _sendCommand(_commandController.text),
                onExpand: () async {
                  final text = await CommandEditorSheet.show(context, initial: _commandController.text);
                  if (text != null && text.isNotEmpty) _sendCommand(text);
                },
                onImage: () => _pickImage(workspace),
                onMic: _toggleVoiceDictation,
                onSelectHistory: _selectHistoryCommand,
              ),
              TerminalKeyboardPanel(
                ctrlActive: _ctrl,
                altActive: _alt,
                keyboardActive: _terminalInputActive,
                onKeyAction: _handleTerminalKeyAction,
                onArrow: _sendArrow,
              ),
            ],
          ],
        ),
      ),
    ),
        ),
      ),
    );
  }

  Future<void> _endWorkspace() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('End workspace?'),
        content: const Text('This will disconnect from the host.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('End workspace')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _workspaceManager.closeWorkspace(widget.workspaceId);
    if (!mounted) return;
    _exitWorkspace();
  }

  Widget _buildTab(Workspace workspace, int index, {required bool isActive}) {
    if (index < workspace.terminals.length) {
      final pane = workspace.terminals[index];
      return _SessionTerminalPanel(
        key: ValueKey('terminal-${pane.id}'),
        terminal: pane.terminal,
        controller: pane.controller,
        fontScale: _terminalFontScale,
        isActive: isActive,
        isTmux: pane.useTmux,
        simulateScroll: true, // Always true to prevent xterm from sending arrow keys to bash
        terminalViewKey: isActive ? _terminalViewKey : null,
        terminalFocusNode: isActive ? _terminalFocusNode : null,
        onGestureArrow: _sendArrow,
        onGestureTab: () => _sendTerminalBytes(TerminalInput.tab()),
        onSendBytes: _sendTerminalBytes,
        onFontScaleChanged: (scale) => setState(() => _terminalFontScale = scale),
      );
    }

    final aux = workspace.auxTabs[index - workspace.terminals.length];
    return switch (aux.type) {
      WorkspaceTabType.files => FilesTab(
          key: ValueKey('files-${aux.id}'),
          workspaceId: widget.workspaceId,
          tab: aux,
        ),
      WorkspaceTabType.browser => BrowserTab(
          key: ValueKey('browser-${aux.id}'),
          workspaceId: widget.workspaceId,
          tab: aux,
        ),
      WorkspaceTabType.gitDiff => GitManagerTab(
          key: ValueKey('git-${aux.id}'),
          workspaceId: widget.workspaceId,
          cwd: aux.path ?? (workspace.terminals.isNotEmpty ? workspace.terminals.first.cwd : '~'),
          onOpenTerminal: workspace.terminals.isNotEmpty ? () => _setActiveTab(0) : null,
        ),
      WorkspaceTabType.terminal => const SizedBox.shrink(),
    };
  }

  void _setActiveTab(int index) {
    _workspaceManager.updateWorkspaceUi(widget.workspaceId, activeTabIndex: index);
    _syncCommandInputPane();
    final workspace = _workspace;
    if (workspace != null && index < workspace.terminals.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusTerminal();
      });
    }
  }

  Future<void> _closeTerminalTab(TerminalPane pane) async {
    if (workspaceHasOnlyOneTab) return;
    await _workspaceManager.detachPane(widget.workspaceId, pane.id);
    if (!mounted) return;
    if (_workspace == null) _exitWorkspace();
  }

  bool get workspaceHasOnlyOneTab {
    final w = _workspace;
    if (w == null) return true;
    return w.terminals.length + w.auxTabs.length <= 1;
  }

  Future<void> _closeAuxTab(int auxIndex) async {
    if (workspaceHasOnlyOneTab) return;
    await _workspaceManager.removeAuxTab(widget.workspaceId, auxIndex);
  }

  Future<void> _showPaneOverflow(TerminalPane pane) async {
    final action = await showModalBottomSheet<_PaneOverflowAction>(
      context: context,
      backgroundColor: ObsidianColors.surfaceContainerHigh,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (pane.useTmux)
              _AddTabTile(Icons.drive_file_rename_outline, ObsidianColors.primary, 'Rename session', () {
                Navigator.pop(ctx, _PaneOverflowAction.rename);
              }),
            if (pane.useTmux)
              _AddTabTile(Icons.stop_circle_outlined, ObsidianColors.error, 'End tmux session', () {
                Navigator.pop(ctx, _PaneOverflowAction.end);
              }),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    await waitForRouteTransition();

    switch (action) {
      case _PaneOverflowAction.rename:
        final renameCtrl = TextEditingController(text: pane.tmuxSessionName);
        final name = await showDialog<String>(
          context: context,
          builder: (dctx) => AlertDialog(
            title: const Text('Rename session'),
            content: TextField(
              controller: renameCtrl,
              decoration: const InputDecoration(labelText: 'tmux session name'),
              autofocus: true,
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('Cancel')),
              FilledButton(
                onPressed: () => Navigator.pop(dctx, renameCtrl.text.trim()),
                child: const Text('Save'),
              ),
            ],
          ),
        );
        if (name == null || name.isEmpty || !mounted) return;
        try {
          await _workspaceManager.renamePaneSession(widget.workspaceId, pane.id, name);
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
          }
        }
      case _PaneOverflowAction.end:
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dctx) => AlertDialog(
            title: const Text('End tmux session?'),
            content: Text('Kill "${pane.tmuxSessionName}" on the remote host?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(dctx, true), child: const Text('End session')),
            ],
          ),
        );
        if (confirmed != true || !mounted) return;
        await _workspaceManager.endPaneSession(widget.workspaceId, pane.id);
        if (!mounted) return;
        if (_workspace == null) _exitWorkspace();
    }
  }

  Future<void> _showAddTabMenu(Workspace workspace) async {
    final choice = await showModalBottomSheet<_AddTabAction>(
      context: context,
      backgroundColor: ObsidianColors.surfaceContainerHigh,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _AddTabTile(Icons.terminal, ObsidianColors.primary, 'New Terminal', () {
              Navigator.pop(ctx, _AddTabAction.terminal);
            }),
            _AddTabTile(Icons.folder_outlined, ObsidianColors.tertiary, 'New File Browser', () {
              Navigator.pop(ctx, _AddTabAction.files);
            }),
            _AddTabTile(Icons.language, ObsidianColors.secondary, 'New Browser', () {
              Navigator.pop(ctx, _AddTabAction.browser);
            }),
            _AddTabTile(Icons.difference_outlined, ObsidianColors.error, 'Git Manager', () {
              Navigator.pop(ctx, _AddTabAction.git);
            }),
            _AddTabTile(Icons.drive_file_rename_outline, ObsidianColors.primary, 'Rename workspace', () {
              Navigator.pop(ctx, _AddTabAction.rename);
            }),
            _AddTabTile(Icons.bookmark_add_outlined, ObsidianColors.primary, 'Save as template', () {
              Navigator.pop(ctx, _AddTabAction.template);
            }),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (kDebugMode) debugPrint('[WORKSPACE] add-tab choice: $choice');
    await waitForRouteTransition();
    if (!mounted) return;

    switch (choice) {
      case _AddTabAction.terminal:
        await _addTerminal(workspace);
      case _AddTabAction.files:
        _addAuxTab(
          workspace,
          WorkspaceTabType.files,
          'Files',
          path: workspace.activeTerminal?.cwd ??
              (workspace.terminals.isNotEmpty ? workspace.terminals.first.cwd : '~'),
        );
      case _AddTabAction.browser:
        await _addBrowserTab(workspace);
      case _AddTabAction.git:
        _addAuxTab(workspace, WorkspaceTabType.gitDiff, 'Git Manager');
      case _AddTabAction.rename:
        await _renameWorkspace(workspace);
      case _AddTabAction.template:
        await _saveTemplate();
    }
  }

  Future<void> _renameWorkspace(Workspace workspace) async {
    final nameCtrl = TextEditingController(text: workspace.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename workspace'),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(labelText: 'Workspace name'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, nameCtrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    try {
      await _workspaceManager.renameWorkspace(widget.workspaceId, name);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Rename failed: $e')));
      }
    }
  }

  Future<void> _saveTemplate() async {
    final nameCtrl = TextEditingController(text: _workspace?.name ?? 'Workspace');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save template'),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(labelText: 'Template name'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, nameCtrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    await _workspaceManager.saveAsTemplate(widget.workspaceId, name);
    ref.invalidate(workspaceTemplatesProvider);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Template saved')));
    }
  }

  Future<void> _addTerminal(Workspace workspace) async {
    final host = await ref.read(hostRepositoryProvider).getHost(workspace.hostId);
    if (host == null || !mounted) return;
    final choice = await SessionNameDialog.show(
      context,
      title: 'New terminal',
      initialName: await _workspaceManager.suggestSessionName(
            host,
            paneIndex: workspace.terminals.length,
          ),
    );
    if (choice == null || !mounted) return;

    var useTmux = choice.useTmux;
    if (choice.useTmux) {
      final resolved = await TmuxAvailability.resolve(
        context: context,
        connection: workspace.connection,
        wantsTmux: true,
      );
      if (!mounted || resolved == null) return;
      useTmux = resolved.useTmux;
    }

    await _workspaceManager.addTerminal(
          widget.workspaceId,
          tmuxSessionName: choice.sessionName,
          useTmux: useTmux,
        );
    if (mounted) _syncChromeFromWorkspace();
  }

  void _addAuxTab(Workspace workspace, WorkspaceTabType type, String title, {String? path}) {
    _workspaceManager.addAuxTab(
          widget.workspaceId,
          WorkspaceTab(
            id: _uuid.v4(),
            type: type,
            title: title,
            path: path ?? (workspace.terminals.isNotEmpty ? workspace.terminals.first.cwd : '~'),
          ),
        );
    _syncChromeFromWorkspace();
  }

  Future<void> _addBrowserTab(Workspace workspace) async {
    final setup = await showBrowserUrlDialog(
      context,
      subtitle: 'Preview a dev server running on the remote host.',
    );
    if (setup == null || !mounted) return;
    _workspaceManager.addAuxTab(
      widget.workspaceId,
      WorkspaceTab(
        id: _uuid.v4(),
        type: WorkspaceTabType.browser,
        title: ':${setup.remotePort}',
        remotePort: setup.remotePort,
        url: setup.displayUrl,
      ),
    );
    if (mounted) _syncChromeFromWorkspace();
  }
}

/// Full terminal input; tap the terminal to type. Command bar is for longer entry.
class _SessionTerminalPanel extends StatefulWidget {
  const _SessionTerminalPanel({
    super.key,
    required this.terminal,
    required this.controller,
    required this.fontScale,
    required this.isActive,
    required this.isTmux,
    required this.simulateScroll,
    required this.terminalViewKey,
    required this.terminalFocusNode,
    required this.onGestureArrow,
    required this.onGestureTab,
    required this.onSendBytes,
    required this.onFontScaleChanged,
  });

  final Terminal terminal;
  final TerminalController controller;
  final double fontScale;
  final bool isActive;
  final bool isTmux;
  final bool simulateScroll;
  final GlobalKey<TerminalViewState>? terminalViewKey;
  final FocusNode? terminalFocusNode;
  final ValueChanged<TerminalArrowDirection> onGestureArrow;
  final VoidCallback onGestureTab;
  final ValueChanged<Uint8List> onSendBytes;
  final ValueChanged<double> onFontScaleChanged;

  @override
  State<_SessionTerminalPanel> createState() => _SessionTerminalPanelState();
}

class _SessionTerminalPanelState extends State<_SessionTerminalPanel> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _SessionTerminalPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
  }

  bool _showScrolly = false;
  double _scrollAccumulator = 0.0;
  
  void _triggerScrolly() {
    if (!widget.isTmux) return; // Not tmux
    if (!_showScrolly) {
      // Send standard tmux prefix (Ctrl+B) then '[' to enter copy mode, 
      // immediately followed by Ctrl+Up to jump to [1/...] instantly
      final enterCopyMode = <int>[0x02, 0x5b];
      final ctrlUp = TerminalInput.ctrlArrow(TerminalArrowDirection.up);
      widget.onSendBytes(Uint8List.fromList([...enterCopyMode, ...ctrlUp])); 
      
      if (mounted) setState(() => _showScrolly = true);
    }
  }

  void _checkAndExitCopyModeIfAtBottom() {
    if (!widget.isTmux) return;
    
    // Tmux copy mode displays the current line index at the top right, e.g. "[0/1990]"
    final topText = widget.terminal.buffer.lines[0].getText().trimRight();
    if (RegExp(r'\[0/\d+\]$').hasMatch(topText)) {
      widget.onSendBytes(Uint8List.fromList([113])); // 'q' to exit copy mode
    }
  }

  void _handleScroll(double deltaY) {
    if (!widget.isTmux) return;
    if (deltaY == 0) return;

    if (!_showScrolly) {
      _triggerScrolly();
    }

    _scrollAccumulator += deltaY;
    
    // Roughly 20 pixels of scroll delta per line
    const double lineThreshold = 20.0;
    
    while (_scrollAccumulator <= -lineThreshold) {
      widget.onSendBytes(TerminalInput.ctrlArrow(TerminalArrowDirection.up));
      _scrollAccumulator += lineThreshold;
    }
    
    while (_scrollAccumulator >= lineThreshold) {
      widget.onSendBytes(TerminalInput.ctrlArrow(TerminalArrowDirection.down));
      _scrollAccumulator -= lineThreshold;
    }
  }

  void _onControllerChanged() {
    if (!mounted) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle || phase == SchedulerPhase.postFrameCallbacks) {
      setState(() {});
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _copySelection() async {
    final selection = widget.controller.selection;
    if (selection == null) return;
    final text = widget.terminal.buffer.getText(selection);
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied to clipboard'), duration: Duration(seconds: 1)),
    );
  }

  void _showCopyMenu(TapUpDetails details) {
    if (widget.controller.selection == null) return;
    final position = details.globalPosition;
    showMenu<void>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
      items: [
        PopupMenuItem<void>(
          onTap: _copySelection,
          child: const Text('Copy'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final mobile = Platform.isAndroid || Platform.isIOS;
    final hasSelection = widget.controller.selection != null;
    final terminalStyle = hostTerminalTextStyle.copyWith(
      fontSize: hostTerminalTextStyle.fontSize * widget.fontScale,
    );
    final terminalBody = TerminalView(
      widget.terminal,
      key: widget.terminalViewKey,
      controller: widget.controller,
      focusNode: widget.terminalFocusNode,
      theme: hostTerminalTheme,
      textStyle: terminalStyle,
      autofocus: widget.isActive,
      hardwareKeyboardOnly: !mobile,
      keyboardType: TextInputType.text,
      deleteDetection: mobile,
      simulateScroll: widget.simulateScroll,
      onSecondaryTapDown: (_, _) {},
      onSecondaryTapUp: (details, _) => _showCopyMenu(details),
    );
    return Listener(
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) {
          _handleScroll(event.scrollDelta.dy);
        }
      },
      onPointerMove: (event) {
        // Touch drag moves in the opposite coordinate direction to mouse scroll
        _handleScroll(-event.delta.dy);
      },
      child: RepaintBoundary(
        child: Stack(
          children: [
            TerminalGestureLayer(
              enabled: true,
              fontScale: widget.fontScale,
              onArrow: widget.onGestureArrow,
              onTab: widget.onGestureTab,
              onFontScaleChanged: widget.onFontScaleChanged,
              child: terminalBody,
            ),
            if (hasSelection)
              Positioned(
                top: 8,
                right: 8,
                child: Material(
                  elevation: 2,
                  borderRadius: BorderRadius.circular(4),
                  color: hostTerminalTheme.background.withValues(alpha: 0.92),
                  child: IconButton(
                    icon: Icon(Icons.copy, size: 18, color: hostTerminalTheme.foreground),
                    tooltip: 'Copy',
                    onPressed: _copySelection,
                  ),
                ),
              ),
            if (_showScrolly)
              Positioned(
                top: 16,
                right: 16,
                child: Scrolly(
                  onHide: () {
                    setState(() => _showScrolly = false);
                    _checkAndExitCopyModeIfAtBottom();
                  },
                  onLineUp: () => widget.onSendBytes(TerminalInput.ctrlArrow(TerminalArrowDirection.up)),
                  onLineDown: () => widget.onSendBytes(TerminalInput.ctrlArrow(TerminalArrowDirection.down)),
                  onPageUp: () => widget.onSendBytes(TerminalInput.pageUp()),
                  onPageDown: () => widget.onSendBytes(TerminalInput.pageDown()),
                  onTop: () => widget.onSendBytes(TerminalInput.alt('<')),
                  onLive: () => widget.onSendBytes(TerminalInput.alt('>')),
                  onDone: () {
                    widget.onSendBytes(Uint8List.fromList([113])); // 'q'
                    if (mounted) setState(() => _showScrolly = false);
                  },
                  onThumbDrag: (deltaY) {
                    if (deltaY < -2) {
                      widget.onSendBytes(TerminalInput.ctrlArrow(TerminalArrowDirection.up));
                    } else if (deltaY > 2) {
                      widget.onSendBytes(TerminalInput.ctrlArrow(TerminalArrowDirection.down));
                    }
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _WorkspaceTabBar extends StatelessWidget {
  const _WorkspaceTabBar({
    required this.workspace,
    required this.activeIndex,
    required this.onSelect,
    required this.onCloseTerminal,
    required this.onCloseAux,
    required this.onPaneOverflow,
    required this.onBack,
    required this.onEndWorkspace,
    required this.onAdd,
  });

  final Workspace workspace;
  final int activeIndex;
  final ValueChanged<int> onSelect;
  final ValueChanged<TerminalPane> onCloseTerminal;
  final ValueChanged<int> onCloseAux;
  final ValueChanged<TerminalPane> onPaneOverflow;
  final VoidCallback onBack;
  final VoidCallback onEndWorkspace;
  final VoidCallback onAdd;

  int get _totalTabs => workspace.terminals.length + workspace.auxTabs.length;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: const BoxDecoration(
        color: ObsidianColors.surfaceContainer,
        border: Border(bottom: BorderSide(color: ObsidianColors.outlineVariant)),
      ),
      child: Row(
        children: [
          IconButton(icon: const Icon(Icons.arrow_back, color: ObsidianColors.primary, size: 20), onPressed: onBack),
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _totalTabs,
              itemBuilder: (context, index) {
                final active = index == activeIndex;
                final isTerminal = index < workspace.terminals.length;
                final label = isTerminal
                    ? workspace.terminals[index].displayTitle
                    : workspace.auxTabs[index - workspace.terminals.length].title;
                final icon = isTerminal
                    ? Icons.terminal
                    : _iconFor(workspace.auxTabs[index - workspace.terminals.length].type);

                return Padding(
                  padding: const EdgeInsets.only(right: 4, top: 6, bottom: 6),
                  child: Material(
                    color: active ? ObsidianColors.surfaceContainerHigh : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                    child: InkWell(
                      onTap: () => onSelect(index),
                      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(icon, size: 16, color: ObsidianColors.primary),
                            const SizedBox(width: 6),
                            Text(
                              label.toUpperCase(),
                              style: AppTypography.mono(
                                size: 12,
                                color: active ? ObsidianColors.primary : ObsidianColors.onSurfaceVariant,
                              ),
                            ),
                            if (active) ...[
                              if (isTerminal && workspace.terminals[index].useTmux) ...[
                                const SizedBox(width: 4),
                                GestureDetector(
                                  onTap: () => onPaneOverflow(workspace.terminals[index]),
                                  child: const Icon(Icons.more_vert, size: 14, color: ObsidianColors.outline),
                                ),
                              ],
                              if (_totalTabs > 1) ...[
                                const SizedBox(width: 4),
                                GestureDetector(
                                  onTap: () {
                                    if (isTerminal) {
                                      onCloseTerminal(workspace.terminals[index]);
                                    } else {
                                      onCloseAux(index - workspace.terminals.length);
                                    }
                                  },
                                  child: const Icon(Icons.close, size: 14, color: ObsidianColors.outline),
                                ),
                              ],
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.power_settings_new, color: ObsidianColors.error, size: 20),
            tooltip: 'End workspace',
            onPressed: onEndWorkspace,
          ),
          IconButton(icon: const Icon(Icons.add, color: ObsidianColors.primary), onPressed: onAdd),
        ],
      ),
    );
  }

  IconData _iconFor(WorkspaceTabType type) => switch (type) {
        WorkspaceTabType.terminal => Icons.terminal,
        WorkspaceTabType.files => Icons.folder_outlined,
        WorkspaceTabType.browser => Icons.language,
        WorkspaceTabType.gitDiff => Icons.difference_outlined,
      };
}

class _CommandInputBar extends StatelessWidget {
  const _CommandInputBar({
    required this.controller,
    required this.focusNode,
    required this.listening,
    required this.recentCommands,
    required this.onSend,
    required this.onExpand,
    required this.onImage,
    required this.onMic,
    required this.onSelectHistory,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool listening;
  final List<String> recentCommands;
  final VoidCallback onSend;
  final VoidCallback onExpand;
  final VoidCallback onImage;
  final VoidCallback onMic;
  final ValueChanged<String> onSelectHistory;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
      decoration: const BoxDecoration(
        color: Colors.transparent,
        border: Border(top: BorderSide(color: ObsidianColors.outlineVariant, width: 0.5)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.image_outlined, size: 20),
            color: ObsidianColors.onSurfaceVariant,
            tooltip: 'Attach image',
            onPressed: onImage,
          ),
          IconButton(
            icon: Icon(listening ? Icons.mic : Icons.mic_none, size: 20),
            color: listening ? ObsidianColors.error : ObsidianColors.onSurfaceVariant,
            tooltip: listening ? 'Stop dictation' : 'Dictate command',
            onPressed: onMic,
          ),
          if (recentCommands.isNotEmpty)
            PopupMenuButton<String>(
              tooltip: 'Command history',
              icon: const Icon(Icons.history, size: 20, color: ObsidianColors.onSurfaceVariant),
              onSelected: onSelectHistory,
              itemBuilder: (context) => [
                for (final command in recentCommands)
                  PopupMenuItem(
                    value: command,
                    child: Text(
                      command,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.mono(size: 12),
                    ),
                  ),
              ],
            ),
          Expanded(
            child: TextField(
              focusNode: focusNode,
              controller: controller,
              autofocus: false,
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.send,
              autocorrect: false,
              enableSuggestions: false,
              enableIMEPersonalizedLearning: true,
              style: AppTypography.inter(size: 14, color: ObsidianColors.onSurface),
              onSubmitted: (_) => onSend(),
              decoration: InputDecoration(
                hintText: listening ? 'Listening…' : 'Type a command…',
                hintStyle: AppTypography.inter(size: 14, color: ObsidianColors.onSurfaceVariant.withValues(alpha: 0.55)),
                filled: true,
                fillColor: ObsidianColors.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
                  borderSide: const BorderSide(color: ObsidianColors.primary, width: 1),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.open_in_full, size: 20),
            color: ObsidianColors.onSurfaceVariant,
            tooltip: 'Expand editor',
            onPressed: onExpand,
          ),
          IconButton(
            icon: const Icon(Icons.send, size: 20),
            tooltip: 'Send command',
            style: IconButton.styleFrom(
              backgroundColor: ObsidianColors.primary,
              foregroundColor: ObsidianColors.onPrimary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.radiusXl)),
            ),
            onPressed: onSend,
          ),
        ],
      ),
    );
  }
}

class _TerminalBytesIntent extends Intent {
  const _TerminalBytesIntent(this.bytes);
  final Uint8List bytes;
}

final Map<ShortcutActivator, Intent> _workspaceTerminalShortcuts = {
  SingleActivator(LogicalKeyboardKey.keyC, control: true): _TerminalBytesIntent(TerminalInput.ctrl('c')),
  SingleActivator(LogicalKeyboardKey.keyZ, control: true): _TerminalBytesIntent(TerminalInput.ctrl('z')),
  SingleActivator(LogicalKeyboardKey.keyD, control: true): _TerminalBytesIntent(TerminalInput.ctrl('d')),
  SingleActivator(LogicalKeyboardKey.keyL, control: true): _TerminalBytesIntent(TerminalInput.ctrl('l')),
  SingleActivator(LogicalKeyboardKey.keyA, control: true): _TerminalBytesIntent(TerminalInput.ctrl('a')),
  SingleActivator(LogicalKeyboardKey.keyE, control: true): _TerminalBytesIntent(TerminalInput.ctrl('e')),
  SingleActivator(LogicalKeyboardKey.keyU, control: true): _TerminalBytesIntent(TerminalInput.ctrl('u')),
  SingleActivator(LogicalKeyboardKey.keyW, control: true): _TerminalBytesIntent(TerminalInput.ctrl('w')),
  SingleActivator(LogicalKeyboardKey.keyR, control: true): _TerminalBytesIntent(TerminalInput.ctrl('r')),
  SingleActivator(LogicalKeyboardKey.keyK, control: true): _TerminalBytesIntent(TerminalInput.ctrl('k')),
  SingleActivator(LogicalKeyboardKey.bracketLeft, control: true): _TerminalBytesIntent(TerminalInput.ctrl('[')),
  SingleActivator(LogicalKeyboardKey.bracketRight, control: true): _TerminalBytesIntent(TerminalInput.ctrl(']')),
  SingleActivator(LogicalKeyboardKey.arrowUp, control: true):
      _TerminalBytesIntent(TerminalInput.ctrlArrow(TerminalArrowDirection.up)),
  SingleActivator(LogicalKeyboardKey.arrowDown, control: true):
      _TerminalBytesIntent(TerminalInput.ctrlArrow(TerminalArrowDirection.down)),
  SingleActivator(LogicalKeyboardKey.arrowLeft, control: true):
      _TerminalBytesIntent(TerminalInput.ctrlArrow(TerminalArrowDirection.left)),
  SingleActivator(LogicalKeyboardKey.arrowRight, control: true):
      _TerminalBytesIntent(TerminalInput.ctrlArrow(TerminalArrowDirection.right)),
  SingleActivator(LogicalKeyboardKey.tab, shift: true): _TerminalBytesIntent(TerminalInput.shiftTab()),
  SingleActivator(LogicalKeyboardKey.f1): _TerminalBytesIntent(TerminalInput.functionKey(1)),
  SingleActivator(LogicalKeyboardKey.f2): _TerminalBytesIntent(TerminalInput.functionKey(2)),
  SingleActivator(LogicalKeyboardKey.f3): _TerminalBytesIntent(TerminalInput.functionKey(3)),
  SingleActivator(LogicalKeyboardKey.f4): _TerminalBytesIntent(TerminalInput.functionKey(4)),
  SingleActivator(LogicalKeyboardKey.f5): _TerminalBytesIntent(TerminalInput.functionKey(5)),
  SingleActivator(LogicalKeyboardKey.f6): _TerminalBytesIntent(TerminalInput.functionKey(6)),
  SingleActivator(LogicalKeyboardKey.f7): _TerminalBytesIntent(TerminalInput.functionKey(7)),
  SingleActivator(LogicalKeyboardKey.f8): _TerminalBytesIntent(TerminalInput.functionKey(8)),
  SingleActivator(LogicalKeyboardKey.f9): _TerminalBytesIntent(TerminalInput.functionKey(9)),
  SingleActivator(LogicalKeyboardKey.f10): _TerminalBytesIntent(TerminalInput.functionKey(10)),
  SingleActivator(LogicalKeyboardKey.f11): _TerminalBytesIntent(TerminalInput.functionKey(11)),
  SingleActivator(LogicalKeyboardKey.f12): _TerminalBytesIntent(TerminalInput.functionKey(12)),
  SingleActivator(LogicalKeyboardKey.pageUp): _TerminalBytesIntent(TerminalInput.pageUp()),
  SingleActivator(LogicalKeyboardKey.pageDown): _TerminalBytesIntent(TerminalInput.pageDown()),
  SingleActivator(LogicalKeyboardKey.home): _TerminalBytesIntent(TerminalInput.home()),
  SingleActivator(LogicalKeyboardKey.end): _TerminalBytesIntent(TerminalInput.end()),
};

class _ImagePreviewStrip extends StatelessWidget {
  const _ImagePreviewStrip({required this.paths, required this.onRemove});

  final List<String> paths;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 72,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        itemCount: paths.length,
        itemBuilder: (context, i) {
          return Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(4),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(File(paths[i]), width: 64, height: 64, fit: BoxFit.cover),
                ),
              ),
              Positioned(
                right: 0,
                top: 0,
                child: IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: () => onRemove(i),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

enum _AddTabAction { terminal, files, browser, git, rename, template }

enum _PaneOverflowAction { rename, end }

class _AddTabTile extends StatelessWidget {
  const _AddTabTile(this.icon, this.color, this.label, this.onTap);

  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(leading: Icon(icon, color: color), title: Text(label), onTap: onTap);
  }
}

class _HostSessionHub extends ConsumerStatefulWidget {
  const _HostSessionHub({
    required this.workspaceId,
    required this.workspace,
    required this.onBack,
    required this.onEndWorkspace,
  });

  final String workspaceId;
  final Workspace workspace;
  final VoidCallback onBack;
  final Future<void> Function() onEndWorkspace;

  @override
  ConsumerState<_HostSessionHub> createState() => _HostSessionHubState();
}

class _HostSessionHubState extends ConsumerState<_HostSessionHub> {
  List<RemoteTmuxSession>? _sessions;
  String? _error;
  bool _loading = true;
  bool _attaching = false;
  Host? _host;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final host = await ref.read(hostRepositoryProvider).getHost(widget.workspace.hostId);
      if (!mounted) return;
      _host = host;
      if (!widget.workspace.connection.isConnected) {
        setState(() {
          _sessions = [];
          _loading = false;
        });
        return;
      }
      final sessions = await ref.read(workspaceManagerProvider).listRemoteTmuxSessions(widget.workspaceId);
      if (!mounted) return;
      setState(() {
        _sessions = sessions;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _attachSession(RemoteTmuxSession session) async {
    if (_attaching) return;
    setState(() => _attaching = true);
    try {
      final resolved = await TmuxAvailability.resolve(
        context: context,
        connection: widget.workspace.connection,
        wantsTmux: true,
      );
      if (!mounted || resolved == null) return;
      if (!resolved.useTmux) {
        await _openPlainShell(cwd: session.cwd ?? '~');
        return;
      }
      final result = await ref.read(workspaceManagerProvider).attachToTmuxSession(
            widget.workspaceId,
            session.name,
            cwd: session.cwd,
          );
      if (mounted && result.workspaceId != widget.workspaceId) {
        openWorkspace(context, result.workspaceId);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Attach failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _attaching = false);
    }
  }

  Future<void> _openPlainShell({String cwd = '~'}) async {
    if (_attaching) return;
    setState(() => _attaching = true);
    try {
      await ref.read(workspaceManagerProvider).addTerminal(
            widget.workspaceId,
            cwd: cwd,
            useTmux: false,
          );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open shell: $e')));
      }
    } finally {
      if (mounted) setState(() => _attaching = false);
    }
  }

  void _openNewTerminal() {
    context.push('/sessions/new/path?host=${widget.workspace.hostId}&workspace=${widget.workspaceId}');
  }

  @override
  Widget build(BuildContext context) {
    final host = _host;
    final connected = widget.workspace.connection.isConnected;
    final state = widget.workspace.aggregateState;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: widget.onBack),
        title: Text(host?.label ?? widget.workspace.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.power_settings_new, color: ObsidianColors.error),
            tooltip: 'End workspace',
            onPressed: widget.onEndWorkspace,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(AppSpacing.marginMobile),
          children: [
            Row(
              children: [
                Icon(
                  connected ? Icons.link : Icons.link_off,
                  size: 18,
                  color: connected ? ObsidianColors.secondary : ObsidianColors.error,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    host?.connectionString ?? widget.workspace.hostId,
                    style: AppTypography.mono(size: 13, color: ObsidianColors.onSurfaceVariant),
                  ),
                ),
                if (state == SessionState.reconnecting)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            if (!connected) ...[
              const SizedBox(height: AppSpacing.md),
              Material(
                color: ObsidianColors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Row(
                    children: [
                      const Icon(Icons.cloud_off, size: 18, color: ObsidianColors.error),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          'Connection lost.',
                          style: AppTypography.inter(size: 13, color: ObsidianColors.error),
                        ),
                      ),
                      TextButton(
                        onPressed: () => ref.read(workspaceManagerProvider).reconnect(widget.workspaceId),
                        child: const Text('Reconnect'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            const SectionHeader('ACTIVE TMUX SESSIONS'),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Text(_error!, style: AppTypography.mono(size: 12, color: ObsidianColors.error)),
              )
            else if (_sessions == null || _sessions!.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Text(
                  connected ? 'No tmux sessions running on this host.' : 'Connect to list tmux sessions.',
                  style: AppTypography.inter(size: 14, color: ObsidianColors.onSurfaceVariant),
                ),
              )
            else
              ..._sessions!.map(
                (session) => Card(
                  margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: ListTile(
                    leading: const Icon(Icons.terminal, color: ObsidianColors.primary),
                    title: Text(session.name, style: AppTypography.mono(size: 14)),
                    subtitle: session.cwd != null
                        ? Text(session.cwd!, style: AppTypography.mono(size: 12, color: ObsidianColors.onSurfaceVariant))
                        : null,
                    trailing: _attaching
                        ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                        : FilledButton(
                            onPressed: connected && !_attaching ? () => _attachSession(session) : null,
                            child: const Text('Attach'),
                          ),
                  ),
                ),
              ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: connected && !_attaching ? _openNewTerminal : null,
              icon: const Icon(Icons.add),
              label: const Text('New terminal'),
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              onPressed: connected && !_attaching ? () => _openPlainShell() : null,
              icon: const Icon(Icons.terminal_outlined),
              label: const Text('Plain shell'),
            ),
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }
}
