import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/obsidian_colors.dart';
import '../../models/remote_file_entry.dart';
import '../../models/workspace_tab.dart';
import '../../services/workspace_manager.dart';
import '../../utils/source_language.dart';
import '../../widgets/new_folder_dialog.dart';
import 'file_code_viewer.dart';

class FilesTab extends ConsumerStatefulWidget {
  const FilesTab({super.key, required this.workspaceId, required this.tab});

  final String workspaceId;
  final WorkspaceTab tab;

  @override
  ConsumerState<FilesTab> createState() => _FilesTabState();
}

class _EditorTab {
  _EditorTab({required this.path});

  final String path;
  String? content;
  String? error;
  bool loading = false;

  String get fileName {
    final parts = path.split('/');
    return parts.isEmpty ? path : parts.last;
  }
}

class _FilesTabState extends ConsumerState<FilesTab> {
  late String _path;
  List<RemoteFileEntry>? _entries;
  String? _error;
  bool _loading = true;
  bool _busy = false;
  bool _ideView = false;
  bool _sidebarVisible = true;
  final List<_EditorTab> _openTabs = [];
  String? _activeTabPath;
  int _treeGeneration = 0;

  String _joinPath(String name) => _path.endsWith('/') ? '$_path$name' : '$_path/$name';

  void _openEntry(RemoteFileEntry entry) {
    if (entry.name == '..') {
      _open(entry);
      return;
    }
    if (entry.isDirectory) {
      _open(entry);
      return;
    }
    setState(() => _ideView = true);
    _openFile(_joinPath(entry.name));
  }

  String get _pathBasename {
    final trimmed = _path.replaceAll(RegExp(r'/+$'), '');
    if (trimmed.isEmpty) return '/';
    final parts = trimmed.split('/');
    return parts.last;
  }

  @override
  void initState() {
    super.initState();
    _path = widget.tab.path ?? '/';
    _load();
  }

  @override
  void didUpdateWidget(covariant FilesTab oldWidget) {
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
        _treeGeneration++;
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

  Future<void> _openFile(String filePath) async {
    final existing = _openTabs.where((t) => t.path == filePath).firstOrNull;
    if (existing != null) {
      setState(() => _activeTabPath = filePath);
      return;
    }

    final tab = _EditorTab(path: filePath);
    setState(() {
      _openTabs.add(tab);
      _activeTabPath = filePath;
      if (!SourceLanguage.isPreviewable(filePath)) {
        tab.error = 'Binary files cannot be previewed';
      } else {
        tab.loading = true;
      }
    });

    if (tab.error != null) return;

    try {
      final text = await ref.read(workspaceManagerProvider).readFileText(widget.workspaceId, filePath);
      if (!mounted) return;
      setState(() {
        tab.content = text;
        tab.loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        tab.error = e.toString();
        tab.loading = false;
      });
    }
  }

  void _selectTab(String path) {
    if (_activeTabPath == path) return;
    setState(() => _activeTabPath = path);
  }

  void _closeTab(String path) {
    final index = _openTabs.indexWhere((t) => t.path == path);
    if (index < 0) return;

    setState(() {
      _openTabs.removeAt(index);
      if (_activeTabPath == path) {
        if (_openTabs.isEmpty) {
          _activeTabPath = null;
        } else {
          final nextIndex = index >= _openTabs.length ? _openTabs.length - 1 : index;
          _activeTabPath = _openTabs[nextIndex].path;
        }
      }
    });
  }

  void _toggleIdeView() {
    setState(() => _ideView = !_ideView);
  }

  void _toggleSidebar() {
    setState(() => _sidebarVisible = !_sidebarVisible);
  }

  Future<void> _showFullPathDialog() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ObsidianColors.surfaceContainer,
        title: Text('Current path', style: AppTypography.inter(size: 16, weight: FontWeight.w600)),
        content: SelectableText(_path, style: AppTypography.mono(size: 13)),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _path));
              Navigator.pop(ctx);
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Path copied')),
              );
            },
            child: const Text('Copy'),
          ),
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  Widget _buildPathChip({required String label, required String tooltip}) {
    return Expanded(
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: _showFullPathDialog,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: AppTypography.mono(size: 12, color: ObsidianColors.onSurfaceVariant),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(Icons.info_outline, size: 14, color: ObsidianColors.outline),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: ObsidianColors.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildToolbar(),
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          if (!_ideView) const Divider(height: 1),
          if (_loading) const Expanded(child: Center(child: CircularProgressIndicator())),
          if (_error != null)
            Expanded(
              child: Center(
                child: Text(_error!, style: AppTypography.mono(size: 12, color: ObsidianColors.error)),
              ),
            ),
          if (!_loading && _error == null)
            Expanded(child: _ideView ? _buildIdeLayout() : _buildListLayout()),
        ],
      ),
    );
  }

  Widget _buildToolbar() => _ideView ? _buildIdeToolbar() : _buildListToolbar();

  Widget _buildIdeToolbar() {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: const BoxDecoration(
        color: ObsidianColors.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: ObsidianColors.outlineVariant)),
      ),
      child: Row(
        children: [
          Tooltip(
            message: '$_path\nTap to view full path',
            child: InkWell(
              onTap: _showFullPathDialog,
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Text(
                  _pathBasename,
                  style: AppTypography.mono(size: 11, color: ObsidianColors.onSurfaceVariant),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
          const Spacer(),
          _filesIconButton(
            icon: _sidebarVisible ? Icons.chevron_left : Icons.folder_outlined,
            tooltip: _sidebarVisible ? 'Hide explorer' : 'Show explorer',
            onPressed: _toggleSidebar,
          ),
          _filesIconButton(
            icon: Icons.view_list,
            tooltip: 'List view',
            onPressed: _loading || _busy ? null : _toggleIdeView,
          ),
          _buildFilesActionsMenu(),
        ],
      ),
    );
  }

  Widget _buildListToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: ObsidianColors.outlineVariant)),
      ),
      child: Row(
        children: [
          const Icon(Icons.folder_outlined, color: ObsidianColors.primary, size: 18),
          const SizedBox(width: 4),
          _buildPathChip(label: _path, tooltip: 'Tap to view full path'),
          _filesIconButton(
            icon: Icons.view_sidebar_outlined,
            tooltip: 'IDE view',
            onPressed: _loading || _busy ? null : _toggleIdeView,
          ),
          _filesIconButton(
            icon: Icons.upload_file,
            tooltip: 'Upload files',
            onPressed: _loading || _busy ? null : _uploadFiles,
          ),
          _filesIconButton(
            icon: Icons.create_new_folder_outlined,
            tooltip: 'New folder',
            onPressed: _loading || _busy ? null : _createFolder,
          ),
          _filesIconButton(
            icon: Icons.refresh,
            tooltip: 'Refresh',
            onPressed: _loading || _busy ? null : _load,
          ),
        ],
      ),
    );
  }

  Widget _filesIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    return IconButton(
      icon: Icon(icon, size: 18, color: ObsidianColors.outline),
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      onPressed: onPressed,
    );
  }

  Widget _buildFilesActionsMenu() {
    return PopupMenuButton<String>(
      padding: EdgeInsets.zero,
      tooltip: 'File actions',
      icon: const Icon(Icons.more_vert, size: 18, color: ObsidianColors.outline),
      onSelected: (value) {
        switch (value) {
          case 'upload':
            _uploadFiles();
          case 'folder':
            _createFolder();
          case 'refresh':
            _load();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'upload',
          enabled: !_loading && !_busy,
          height: 36,
          child: Text('Upload files', style: AppTypography.mono(size: 12)),
        ),
        PopupMenuItem(
          value: 'folder',
          enabled: !_loading && !_busy,
          height: 36,
          child: Text('New folder', style: AppTypography.mono(size: 12)),
        ),
        PopupMenuItem(
          value: 'refresh',
          enabled: !_loading && !_busy,
          height: 36,
          child: Text('Refresh', style: AppTypography.mono(size: 12)),
        ),
      ],
    );
  }

  Widget _buildListLayout() {
    return Material(
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
            onTap: () => _openEntry(e),
          );
        },
      ),
    );
  }

  Widget _buildIdeLayout() {
    final treeWidth = (MediaQuery.sizeOf(context).width * 0.36).clamp(200.0, 300.0);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Visibility(
          visible: _sidebarVisible,
          maintainState: true,
          maintainAnimation: true,
          maintainSize: false,
          child: SizedBox(
            width: treeWidth,
            child: ColoredBox(
              color: ObsidianColors.surfaceContainerLow,
              child: _FileTreePane(
                workspaceId: widget.workspaceId,
                rootPath: _path,
                refreshGeneration: _treeGeneration,
                selectedFilePath: _activeTabPath,
                onFileSelected: _openFile,
                onHide: _toggleSidebar,
              ),
            ),
          ),
        ),
        if (_sidebarVisible) const VerticalDivider(width: 1, thickness: 1),
        Expanded(
          child: _FileEditorPane(
            tabs: _openTabs,
            activePath: _activeTabPath,
            sidebarVisible: _sidebarVisible,
            onSelect: _selectTab,
            onClose: _closeTab,
            onShowSidebar: _toggleSidebar,
          ),
        ),
      ],
    );
  }
}

class _FileTreePane extends ConsumerStatefulWidget {
  const _FileTreePane({
    required this.workspaceId,
    required this.rootPath,
    required this.refreshGeneration,
    required this.selectedFilePath,
    required this.onFileSelected,
    required this.onHide,
  });

  final String workspaceId;
  final String rootPath;
  final int refreshGeneration;
  final String? selectedFilePath;
  final ValueChanged<String> onFileSelected;
  final VoidCallback onHide;

  @override
  ConsumerState<_FileTreePane> createState() => _FileTreePaneState();
}

class _FileTreePaneState extends ConsumerState<_FileTreePane> {
  final Set<String> _expandedDirs = {};
  final Map<String, List<RemoteFileEntry>> _cache = {};
  final Set<String> _loadingDirs = {};
  String? _error;
  final ScrollController _scrollController = ScrollController();
  final ScrollController _horizontalScrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    _horizontalScrollController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _expandedDirs.add(widget.rootPath);
    _loadDirectory(widget.rootPath);
  }

  @override
  void didUpdateWidget(covariant _FileTreePane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshGeneration != widget.refreshGeneration) {
      final expanded = Set<String>.from(_expandedDirs)..add(widget.rootPath);
      _cache.clear();
      for (final path in expanded) {
        _loadDirectory(path, force: true);
      }
      return;
    }
    if (oldWidget.rootPath != widget.rootPath) {
      _expandedDirs.add(widget.rootPath);
      _loadDirectory(widget.rootPath);
    }
  }

  String _join(String dir, String name) => dir.endsWith('/') ? '$dir$name' : '$dir/$name';

  Future<void> _loadDirectory(String path, {bool force = false}) async {
    if (!force && (_cache.containsKey(path) || _loadingDirs.contains(path))) return;
    setState(() {
      _loadingDirs.add(path);
      _error = null;
    });
    try {
      final raw = await ref.read(workspaceManagerProvider).listDirectory(widget.workspaceId, path);
      if (!mounted) return;
      final children = raw.where((e) => e.name != '.' && e.name != '..').toList()
        ..sort((a, b) {
          if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
      setState(() => _cache[path] = children);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _loadingDirs.remove(path));
      }
    }
  }

  void _toggleDirectory(String path) {
    setState(() {
      if (_expandedDirs.contains(path)) {
        _expandedDirs.remove(path);
      } else {
        _expandedDirs.add(path);
        _loadDirectory(path);
      }
    });
  }

  List<Widget> _buildNodes(String dirPath, int depth) {
    final entries = _cache[dirPath];
    if (entries == null) {
      if (_loadingDirs.contains(dirPath)) {
        return [
          Padding(
            padding: EdgeInsets.only(left: 12 + depth * 16.0, top: 4, bottom: 4),
            child: const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ];
      }
      return [];
    }

    return [
      for (final entry in entries)
        ...[
          _buildNodeTile(entry, dirPath, depth),
          if (entry.isDirectory && _expandedDirs.contains(_join(dirPath, entry.name)))
            ..._buildNodes(_join(dirPath, entry.name), depth + 1),
        ],
    ];
  }

  Widget _buildNodeTile(RemoteFileEntry entry, String parentPath, int depth) {
    final fullPath = _join(parentPath, entry.name);
    final isSelected = !entry.isDirectory && widget.selectedFilePath == fullPath;
    final isExpanded = entry.isDirectory && _expandedDirs.contains(fullPath);

    return Material(
      color: isSelected ? ObsidianColors.surfaceContainerHigh : Colors.transparent,
      child: InkWell(
        onTap: () {
          if (entry.isDirectory) {
            _toggleDirectory(fullPath);
          } else {
            widget.onFileSelected(fullPath);
          }
        },
        child: Padding(
          padding: EdgeInsets.only(left: 8 + depth * 16.0, right: 8, top: 2, bottom: 2),
          child: Row(
            children: [
              if (entry.isDirectory)
                Icon(
                  isExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
                  size: 18,
                  color: ObsidianColors.outline,
                )
              else
                const SizedBox(width: 18),
              const SizedBox(width: 4),
              Icon(
                entry.isDirectory
                    ? (isExpanded ? Icons.folder_open : Icons.folder)
                    : _fileIcon(entry.name),
                size: 16,
                color: entry.isDirectory ? ObsidianColors.primary : ObsidianColors.outline,
              ),
              const SizedBox(width: 6),
              Text(
                entry.name,
                style: AppTypography.mono(
                  size: 12,
                  color: isSelected ? ObsidianColors.primary : ObsidianColors.onSurface,
                ),
                softWrap: false,
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _fileIcon(String name) {
    return switch (SourceLanguage.extension(name)) {
      'dart' => Icons.code,
      'js' || 'jsx' || 'ts' || 'tsx' => Icons.javascript,
      'py' => Icons.terminal,
      'json' || 'yaml' || 'yml' || 'toml' => Icons.data_object,
      'md' => Icons.article_outlined,
      _ => Icons.description_outlined,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 4, 6),
          child: Row(
            children: [
              Expanded(
                child: Text('EXPLORER', style: AppTypography.mono(size: 10, color: ObsidianColors.outline)),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_left, size: 18),
                tooltip: 'Hide explorer',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                color: ObsidianColors.outline,
                onPressed: widget.onHide,
              ),
            ],
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(_error!, style: AppTypography.mono(size: 11, color: ObsidianColors.error)),
          ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Scrollbar(
                controller: _scrollController,
                child: Scrollbar(
                  controller: _horizontalScrollController,
                  notificationPredicate: (notification) => notification.depth == 1,
                  child: SingleChildScrollView(
                    controller: _horizontalScrollController,
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minWidth: constraints.maxWidth),
                      child: SingleChildScrollView(
                        controller: _scrollController,
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: _buildNodes(widget.rootPath, 0),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _FileEditorPane extends StatelessWidget {
  const _FileEditorPane({
    required this.tabs,
    required this.activePath,
    required this.sidebarVisible,
    required this.onSelect,
    required this.onClose,
    required this.onShowSidebar,
  });

  final List<_EditorTab> tabs;
  final String? activePath;
  final bool sidebarVisible;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onClose;
  final VoidCallback onShowSidebar;

  _EditorTab? get _activeTab {
    if (activePath == null) return null;
    for (final tab in tabs) {
      if (tab.path == activePath) return tab;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final active = _activeTab;

    return ColoredBox(
      color: ObsidianColors.terminalBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _EditorTabBar(
            tabs: tabs,
            activePath: activePath,
            sidebarVisible: sidebarVisible,
            onSelect: onSelect,
            onClose: onClose,
            onShowSidebar: onShowSidebar,
          ),
          const Divider(height: 1),
          Expanded(
            child: active == null
                ? _EmptyEditorHint(sidebarVisible: sidebarVisible, onShowSidebar: onShowSidebar)
                : _FilePreviewBody(tab: active),
          ),
        ],
      ),
    );
  }
}

class _EditorTabBar extends StatelessWidget {
  const _EditorTabBar({
    required this.tabs,
    required this.activePath,
    required this.sidebarVisible,
    required this.onSelect,
    required this.onClose,
    required this.onShowSidebar,
  });

  final List<_EditorTab> tabs;
  final String? activePath;
  final bool sidebarVisible;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onClose;
  final VoidCallback onShowSidebar;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      color: ObsidianColors.surfaceContainer,
      child: Row(
        children: [
          if (!sidebarVisible)
            IconButton(
              icon: const Icon(Icons.folder_outlined, size: 18),
              tooltip: 'Show explorer',
              padding: const EdgeInsets.symmetric(horizontal: 8),
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              color: ObsidianColors.outline,
              onPressed: onShowSidebar,
            ),
          Expanded(
            child: tabs.isEmpty
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: Text(
                        'No open files',
                        style: AppTypography.mono(size: 11, color: ObsidianColors.outline),
                      ),
                    ),
                  )
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    itemCount: tabs.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 2),
                    itemBuilder: (context, index) {
                      final tab = tabs[index];
                      final active = tab.path == activePath;
                      return _EditorTabChip(
                        tab: tab,
                        active: active,
                        onSelect: () => onSelect(tab.path),
                        onClose: () => onClose(tab.path),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _EditorTabChip extends StatelessWidget {
  const _EditorTabChip({
    required this.tab,
    required this.active,
    required this.onSelect,
    required this.onClose,
  });

  final _EditorTab tab;
  final bool active;
  final VoidCallback onSelect;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? ObsidianColors.surfaceContainerHigh : ObsidianColors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      child: InkWell(
        onTap: onSelect,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        child: Padding(
          padding: const EdgeInsets.only(left: 10, right: 4, top: 4, bottom: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.description_outlined,
                size: 14,
                color: active ? ObsidianColors.primary : ObsidianColors.outline,
              ),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140),
                child: Text(
                  tab.fileName,
                  style: AppTypography.mono(
                    size: 11,
                    color: active ? ObsidianColors.primary : ObsidianColors.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              InkWell(
                onTap: onClose,
                customBorder: const CircleBorder(),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.close,
                    size: 14,
                    color: active ? ObsidianColors.onSurfaceVariant : ObsidianColors.outline,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyEditorHint extends StatelessWidget {
  const _EmptyEditorHint({required this.sidebarVisible, required this.onShowSidebar});

  final bool sidebarVisible;
  final VoidCallback onShowSidebar;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Select a file to preview',
            style: AppTypography.mono(size: 12, color: ObsidianColors.outline),
          ),
          if (!sidebarVisible) ...[
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: onShowSidebar,
              icon: const Icon(Icons.folder_outlined, size: 16),
              label: Text('Show explorer', style: AppTypography.mono(size: 12)),
            ),
          ],
        ],
      ),
    );
  }
}

class _FilePreviewBody extends StatelessWidget {
  const _FilePreviewBody({required this.tab});

  final _EditorTab tab;

  @override
  Widget build(BuildContext context) {
    if (tab.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (tab.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            tab.error!,
            style: AppTypography.mono(size: 12, color: ObsidianColors.error),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (tab.content == null) return const SizedBox.shrink();

    return FileCodeViewer(
      content: tab.content!,
      language: SourceLanguage.forPath(tab.path),
    );
  }
}
