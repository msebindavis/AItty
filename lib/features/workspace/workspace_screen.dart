import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:xterm/xterm.dart';

import '../../core/constants/spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/obsidian_colors.dart';
import '../../models/host.dart';
import '../../models/remote_file_entry.dart';
import '../../models/session.dart';
import '../../models/workspace.dart';
import '../../models/workspace_tab.dart';
import '../../services/workspace_repository.dart';
import '../../services/workspace_manager.dart';
import '../../utils/terminal_input.dart';
import '../../utils/open_workspace.dart';
import '../../widgets/new_folder_dialog.dart';
import '../../widgets/section_header.dart';
import '../../widgets/session_name_dialog.dart';
import '../../widgets/tmux_missing_dialog.dart';
import 'command_editor_sheet.dart';
import 'git_manager_tab.dart';
import 'terminal_theme.dart';
import 'tmux_scroll_capture.dart';

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
  bool _tmuxScrollMode = false;
  String? _chromeSnapshot;
  bool _terminalReady = false;
  bool _commandBarReady = false;
  late final WorkspaceManager _workspaceManager;

  @override
  void initState() {
    super.initState();
    _workspaceManager = ref.read(workspaceManagerProvider);
    _workspaceManager.addListener(_onWorkspaceManagerChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scheduleContentMount());
  }

  void _scheduleContentMount() {
    FocusManager.instance.primaryFocus?.unfocus();
    Future<void>.delayed(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      setState(() => _terminalReady = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _commandBarReady = true);
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
    if (mounted) setState(() {});
  }

  String _snapshotChrome(Workspace? workspace) {
    if (workspace == null) return 'ended';
    final terminalIds = workspace.terminals.map((p) => p.id).join(',');
    final terminalNames = workspace.terminals.map((p) => p.tmuxSessionName).join(',');
    final auxMeta = workspace.auxTabs.map((t) => '${t.id}:${t.path ?? ''}').join(',');
    return '${workspace.aggregateState.index}|${workspace.state.index}|$terminalIds|$terminalNames|$auxMeta|'
        '${workspace.activeTabIndex}|${workspace.pendingImagePaths.length}';
  }

  @override
  void dispose() {
    if (_tmuxScrollMode) {
      final pane = _workspaceManager.getWorkspace(widget.workspaceId)?.activeTerminal;
      pane?.controller.setSuspendPointerInput(false);
      _tmuxScrollMode = false;
    }
    _workspaceManager.removeListener(_onWorkspaceManagerChanged);
    _commandController.dispose();
    super.dispose();
  }

  void _toggleTmuxScrollMode() {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _tmuxScrollMode = !_tmuxScrollMode);
    _activePane?.controller.setSuspendPointerInput(_tmuxScrollMode);
    _sendRaw(_tmuxScrollMode ? TerminalInput.tmuxCopyModeEnter() : TerminalInput.tmuxCopyModeExit());
  }

  void _deactivateTmuxScrollMode({bool sendExit = true}) {
    if (!_tmuxScrollMode) return;
    if (sendExit) _sendRaw(TerminalInput.tmuxCopyModeExit());
    _activePane?.controller.setSuspendPointerInput(false);
    if (mounted) setState(() => _tmuxScrollMode = false);
  }

  void _sendModifierArrow(Uint8List bytes) {
    _sendRaw(bytes);
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
    _commandController.clear();
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
    final activePane = isTerminalActive ? workspace.terminals[activeIndex] : null;
    final showTmuxScroll = activePane?.useTmux ?? false;

    return Scaffold(
      backgroundColor: ObsidianColors.terminalBackground,
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
                  ? _buildTab(workspace, activeIndex)
                  : const ColoredBox(
                      color: ObsidianColors.terminalBackground,
                      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                    ),
            ),
            if (_tmuxScrollMode && showTmuxScroll)
              Material(
                color: ObsidianColors.primary.withValues(alpha: 0.12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 6),
                  child: Row(
                    children: [
                      Icon(Icons.swipe_vertical, size: 16, color: ObsidianColors.primary),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          'Scroll mode — drag the terminal to move through output',
                          style: AppTypography.inter(size: 12, color: ObsidianColors.primary),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (_commandBarReady && isTerminalActive) ...[
              _CommandInputBar(
                controller: _commandController,
                onSend: () => _sendCommand(_commandController.text),
                onExpand: () async {
                  final text = await CommandEditorSheet.show(context, initial: _commandController.text);
                  if (text != null && text.isNotEmpty) _sendCommand(text);
                },
                onImage: () => _pickImage(workspace),
                onMic: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Voice input: wire speech_to_text to enable.')),
                  );
                },
              ),
              _ModifierBar(
                ctrlActive: _ctrl,
                altActive: _alt,
                tmuxScrollActive: _tmuxScrollMode,
                showTmuxScroll: showTmuxScroll,
                onEsc: () => _sendRaw(TerminalInput.esc()),
                onCtrl: () => setState(() => _ctrl = !_ctrl),
                onAlt: () => setState(() => _alt = !_alt),
                onTab: () => _sendRaw(TerminalInput.tab()),
                onTmuxScroll: _toggleTmuxScrollMode,
                onArrow: _sendModifierArrow,
              ),
            ],
          ],
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

  Widget _buildTab(Workspace workspace, int activeIndex) {
    if (activeIndex < workspace.terminals.length) {
      final pane = workspace.terminals[activeIndex];
      return _SessionTerminalPanel(
        key: ValueKey('terminal-${pane.id}'),
        terminal: pane.terminal,
        controller: pane.controller,
        tmuxScrollMode: _tmuxScrollMode && pane.useTmux,
        onScrollStep: _sendRaw,
      );
    }

    final aux = workspace.auxTabs[activeIndex - workspace.terminals.length];
    return switch (aux.type) {
      WorkspaceTabType.files => _FilesTab(workspaceId: widget.workspaceId, tab: aux),
      WorkspaceTabType.browser => _BrowserTab(workspaceId: widget.workspaceId, tab: aux),
      WorkspaceTabType.gitDiff => GitManagerTab(
          workspaceId: widget.workspaceId,
          cwd: aux.path ?? (workspace.terminals.isNotEmpty ? workspace.terminals.first.cwd : '~'),
          onOpenTerminal: workspace.terminals.isNotEmpty ? () => _setActiveTab(0) : null,
        ),
      WorkspaceTabType.terminal => const SizedBox.shrink(),
    };
  }

  void _setActiveTab(int index) {
    _deactivateTmuxScrollMode();
    _workspaceManager.updateWorkspaceUi(widget.workspaceId, activeTabIndex: index);
  }

  Future<void> _closeTerminalTab(TerminalPane pane) async {
    if (workspaceHasOnlyOneTab) return;
    _deactivateTmuxScrollMode();
    await _workspaceManager.detachPane(widget.workspaceId, pane.id);
    if (!mounted) return;
    if (_workspace == null) _exitWorkspace();
  }

  bool get workspaceHasOnlyOneTab {
    final w = _workspace;
    if (w == null) return true;
    return w.terminals.length + w.auxTabs.length <= 1;
  }

  void _closeAuxTab(int auxIndex) {
    if (workspaceHasOnlyOneTab) return;
    _workspaceManager.removeAuxTab(widget.workspaceId, auxIndex);
  }

  Future<void> _showPaneOverflow(TerminalPane pane) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: ObsidianColors.surfaceContainerHigh,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (pane.useTmux)
              _AddTabTile(Icons.drive_file_rename_outline, ObsidianColors.primary, 'Rename session', () async {
              Navigator.pop(ctx);
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
              }),
            if (pane.useTmux)
              _AddTabTile(Icons.stop_circle_outlined, ObsidianColors.error, 'End tmux session', () async {
                Navigator.pop(ctx);
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
              }),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
  }

  void _showAddTabMenu(Workspace workspace) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: ObsidianColors.surfaceContainerHigh,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _AddTabTile(Icons.terminal, ObsidianColors.primary, 'New Terminal', () {
              Navigator.pop(ctx);
              _addTerminal(workspace);
            }),
            _AddTabTile(Icons.folder_outlined, ObsidianColors.tertiary, 'New File Browser', () {
              Navigator.pop(ctx);
              _addAuxTab(
                workspace,
                WorkspaceTabType.files,
                'Files',
                path: workspace.activeTerminal?.cwd ??
                    (workspace.terminals.isNotEmpty ? workspace.terminals.first.cwd : '~'),
              );
            }),
            _AddTabTile(Icons.language, ObsidianColors.secondary, 'New Browser', () {
              Navigator.pop(ctx);
              _addAuxTab(workspace, WorkspaceTabType.browser, 'Browser');
            }),
            _AddTabTile(Icons.difference_outlined, ObsidianColors.error, 'Git Manager', () {
              Navigator.pop(ctx);
              _addAuxTab(workspace, WorkspaceTabType.gitDiff, 'Git Manager');
            }),
            _AddTabTile(Icons.drive_file_rename_outline, ObsidianColors.primary, 'Rename workspace', () {
              Navigator.pop(ctx);
              _renameWorkspace(workspace);
            }),
            _AddTabTile(Icons.bookmark_add_outlined, ObsidianColors.primary, 'Save as template', () {
              Navigator.pop(ctx);
              _saveTemplate();
            }),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
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
  }
}

/// Full terminal input; tap the terminal to type. Command bar is for longer entry.
class _SessionTerminalPanel extends StatefulWidget {
  const _SessionTerminalPanel({
    super.key,
    required this.terminal,
    required this.controller,
    required this.tmuxScrollMode,
    required this.onScrollStep,
  });

  final Terminal terminal;
  final TerminalController controller;
  final bool tmuxScrollMode;
  final void Function(Uint8List bytes) onScrollStep;

  @override
  State<_SessionTerminalPanel> createState() => _SessionTerminalPanelState();
}

class _SessionTerminalPanelState extends State<_SessionTerminalPanel> {
  @override
  void initState() {
    super.initState();
    widget.controller.setSuspendPointerInput(widget.tmuxScrollMode);
  }

  @override
  void didUpdateWidget(covariant _SessionTerminalPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tmuxScrollMode != widget.tmuxScrollMode) {
      widget.controller.setSuspendPointerInput(widget.tmuxScrollMode);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mobile = Platform.isAndroid || Platform.isIOS;
    return RepaintBoundary(
      child: Stack(
        children: [
          TerminalView(
            widget.terminal,
            controller: widget.controller,
            theme: obsidianTerminalTheme,
            textStyle: obsidianTerminalTextStyle,
            autofocus: false,
            deleteDetection: mobile,
            simulateScroll: !widget.tmuxScrollMode,
          ),
          if (widget.tmuxScrollMode)
            Positioned.fill(
              child: TmuxScrollCapture(
                pixelsPerLine: tmuxScrollPixelsPerLine(context),
                onScrollLine: ({required up}) => dispatchTmuxScrollLine(widget.onScrollStep, up: up),
              ),
            ),
        ],
      ),
    );
  }
}

class _FilesTab extends ConsumerStatefulWidget {
  const _FilesTab({required this.workspaceId, required this.tab});

  final String workspaceId;
  final WorkspaceTab tab;

  @override
  ConsumerState<_FilesTab> createState() => _FilesTabState();
}

class _FilesTabState extends ConsumerState<_FilesTab> {
  late String _path;
  List<RemoteFileEntry>? _entries;
  String? _error;
  bool _loading = true;
  bool _busy = false;

  String _joinPath(String name) => _path.endsWith('/') ? '$_path$name' : '$_path/$name';

  @override
  void initState() {
    super.initState();
    _path = widget.tab.path ?? '/';
    _load();
  }

  @override
  void didUpdateWidget(covariant _FilesTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextPath = widget.tab.path;
    if (nextPath != null && nextPath != oldWidget.tab.path) {
      _path = nextPath;
      _load();
    }
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = await ref.read(workspaceManagerProvider).listDirectory(widget.workspaceId, _path);
      if (!mounted) return;
      final children = raw.where((e) => e.name != '.' && e.name != '..').toList()
        ..sort((a, b) {
          if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
      setState(() {
        _entries = [
          const RemoteFileEntry(name: '..', isDirectory: true, permissions: 'drwxr-xr-x'),
          ...children,
        ];
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

  Future<void> _createFolder() async {
    if (_busy) return;
    final name = await NewFolderDialog.show(context);
    if (name == null || name.isEmpty) return;

    setState(() => _busy = true);
    try {
      await ref.read(workspaceManagerProvider).createDirectory(widget.workspaceId, _joinPath(name));
      if (!mounted) return;
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not create folder: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _uploadFiles() async {
    if (_busy) return;
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (!mounted) return;
    await ref.read(workspaceManagerProvider).refreshConnectionHealth();
    if (result == null || result.files.isEmpty) return;

    setState(() => _busy = true);
    final manager = ref.read(workspaceManagerProvider);
    var uploaded = 0;
    try {
      for (final file in result.files) {
        final remotePath = _joinPath(file.name);
        if (file.path != null) {
          await manager.uploadFile(widget.workspaceId, file.path!, remotePath);
        } else if (file.bytes != null) {
          await manager.uploadBytes(widget.workspaceId, file.bytes!, remotePath);
        } else {
          continue;
        }
        uploaded++;
      }
      if (!mounted) return;
      if (uploaded > 0) {
        await _load();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Uploaded $uploaded file${uploaded == 1 ? '' : 's'}')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not read selected files')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _open(RemoteFileEntry entry) {
    if (entry.name == '..') {
      final parent = _path.replaceAll(RegExp(r'/+$'), '');
      final idx = parent.lastIndexOf('/');
      _path = idx <= 0 ? '/' : parent.substring(0, idx);
      _load();
      return;
    }
    if (!entry.isDirectory) return;
    _path = _path.endsWith('/') ? '$_path${entry.name}' : '$_path/${entry.name}';
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: ObsidianColors.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                const Icon(Icons.folder_outlined, color: ObsidianColors.primary, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(_path, style: AppTypography.mono(size: 12))),
                IconButton(
                  icon: const Icon(Icons.upload_file, size: 20),
                  tooltip: 'Upload files',
                  onPressed: _loading || _busy ? null : _uploadFiles,
                ),
                IconButton(
                  icon: const Icon(Icons.create_new_folder_outlined, size: 20),
                  tooltip: 'New folder',
                  onPressed: _loading || _busy ? null : _createFolder,
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  onPressed: _loading || _busy ? null : _load,
                ),
              ],
            ),
          ),
          if (_busy) const LinearProgressIndicator(),
          const Divider(height: 1),
          if (_loading) const Expanded(child: Center(child: CircularProgressIndicator())),
          if (_error != null)
            Expanded(
              child: Center(
                child: Text(_error!, style: AppTypography.mono(size: 12, color: ObsidianColors.error)),
              ),
            ),
          if (!_loading && _error == null)
            Expanded(
              child: Material(
                color: ObsidianColors.surface,
                child: ListView.separated(
                  itemCount: _entries!.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final e = _entries![i];
                    return ListTile(
                      tileColor: ObsidianColors.surface,
                      leading: Icon(
                        e.isDirectory ? Icons.folder : Icons.description_outlined,
                        color: e.isDirectory ? ObsidianColors.primary : ObsidianColors.outline,
                      ),
                      title: Text(e.name, style: AppTypography.mono(size: 14)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(e.permissions, style: AppTypography.mono(size: 11, color: ObsidianColors.outline)),
                          if (e.size != null) ...[
                            const SizedBox(width: 8),
                            Text('${e.size}', style: AppTypography.mono(size: 11, color: ObsidianColors.outline)),
                          ],
                        ],
                      ),
                      onTap: e.isDirectory ? () => _open(e) : null,
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BrowserTab extends ConsumerStatefulWidget {
  const _BrowserTab({required this.workspaceId, required this.tab});

  final String workspaceId;
  final WorkspaceTab tab;

  @override
  ConsumerState<_BrowserTab> createState() => _BrowserTabState();
}

class _BrowserTabState extends ConsumerState<_BrowserTab> {
  WebViewController? _controller;
  String _url = '';
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final port = await ref.read(workspaceManagerProvider).ensureBrowserForward(
            widget.workspaceId,
            widget.tab.id,
            widget.tab.remotePort,
          );
      _url = widget.tab.url ?? 'http://127.0.0.1:$port/';
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(ObsidianColors.background)
        ..loadRequest(Uri.parse(_url));
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Text(_error!, style: AppTypography.mono(size: 12, color: ObsidianColors.error)),
        ),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Row(
            children: [
              const Icon(Icons.lock_outline, size: 16, color: ObsidianColors.secondary),
              const SizedBox(width: 8),
              Expanded(child: Text(_url, style: AppTypography.mono(size: 12))),
              IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: () => _controller?.loadRequest(Uri.parse(_url)),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(child: WebViewWidget(controller: _controller!)),
      ],
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
    required this.onSend,
    required this.onExpand,
    required this.onImage,
    required this.onMic,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onExpand;
  final VoidCallback onImage;
  final VoidCallback onMic;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
      color: ObsidianColors.surfaceContainerLow,
      child: Row(
        children: [
          IconButton(icon: const Icon(Icons.image_outlined, size: 20), onPressed: onImage),
          IconButton(icon: const Icon(Icons.mic_none, size: 20), onPressed: onMic),
          Expanded(
            child: TextField(
              controller: controller,
              autofocus: false,
              style: AppTypography.inter(size: 14),
              onSubmitted: (_) => onSend(),
              decoration: InputDecoration(
                hintText: 'Use me for long commands or prompts',
                filled: true,
                fillColor: ObsidianColors.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
            ),
          ),
          IconButton(icon: const Icon(Icons.open_in_full, size: 20), onPressed: onExpand),
          IconButton(
            icon: const Icon(Icons.send, size: 20),
            style: IconButton.styleFrom(
              backgroundColor: ObsidianColors.primary,
              foregroundColor: ObsidianColors.onPrimary,
            ),
            onPressed: onSend,
          ),
        ],
      ),
    );
  }
}

class _ModifierBar extends StatelessWidget {
  const _ModifierBar({
    required this.ctrlActive,
    required this.altActive,
    required this.tmuxScrollActive,
    required this.showTmuxScroll,
    required this.onEsc,
    required this.onCtrl,
    required this.onAlt,
    required this.onTab,
    required this.onTmuxScroll,
    required this.onArrow,
  });

  final bool ctrlActive;
  final bool altActive;
  final bool tmuxScrollActive;
  final bool showTmuxScroll;
  final VoidCallback onEsc;
  final VoidCallback onCtrl;
  final VoidCallback onAlt;
  final VoidCallback onTab;
  final VoidCallback onTmuxScroll;
  final void Function(Uint8List) onArrow;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: ObsidianColors.surfaceContainerLowest,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _ModKey('ESC', onTap: onEsc),
                  _ModKey('CTRL', active: ctrlActive, onTap: onCtrl),
                  _ModKey('ALT', active: altActive, onTap: onAlt),
                  _ModKey('TAB', onTap: onTab),
                  if (showTmuxScroll) _ModKey('SCR', active: tmuxScrollActive, onTap: onTmuxScroll),
                ],
              ),
            ),
          ),
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            icon: const Icon(Icons.keyboard_arrow_left, size: 20),
            onPressed: () => onArrow(TerminalInput.arrowLeft()),
          ),
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            icon: const Icon(Icons.keyboard_arrow_up, size: 20),
            onPressed: () => onArrow(TerminalInput.arrowUp()),
          ),
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            icon: const Icon(Icons.keyboard_arrow_down, size: 20),
            onPressed: () => onArrow(TerminalInput.arrowDown()),
          ),
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            icon: const Icon(Icons.keyboard_arrow_right, size: 20),
            onPressed: () => onArrow(TerminalInput.arrowRight()),
          ),
        ],
      ),
    );
  }
}

class _ModKey extends StatelessWidget {
  const _ModKey(this.label, {required this.onTap, this.active = false});

  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Material(
        color: active ? ObsidianColors.primary.withValues(alpha: 0.25) : ObsidianColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Text(label, style: AppTypography.mono(size: 12, color: active ? ObsidianColors.primary : null)),
          ),
        ),
      ),
    );
  }
}

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
