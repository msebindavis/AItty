import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/obsidian_colors.dart';
import '../../models/host.dart';
import '../../models/remote_file_entry.dart';
import '../../providers/hosts_provider.dart';
import '../../services/workspace_manager.dart';
import '../../widgets/session_name_dialog.dart';
import '../../widgets/tmux_missing_dialog.dart';
import '../../services/ssh_connection.dart';
import '../../services/ssh_key_repository.dart';
import '../../utils/open_workspace.dart';
import '../../widgets/new_folder_dialog.dart';
import '../../widgets/section_header.dart';

enum _PathView { recents, browse }

class SelectPathScreen extends ConsumerStatefulWidget {
  const SelectPathScreen({super.key, this.hostId});

  final String? hostId;

  @override
  ConsumerState<SelectPathScreen> createState() => _SelectPathScreenState();
}

class _SelectPathScreenState extends ConsumerState<SelectPathScreen> {
  SshConnection? _connection;
  Host? _host;
  String _path = '/';
  String _selectedDir = '/';
  List<RemoteFileEntry> _entries = [];
  List<String> _recentPaths = [];
  String _query = '';
  bool _loading = true;
  String? _error;
  bool _connecting = false;
  _PathView _view = _PathView.recents;

  List<RemoteFileEntry> get _displayEntries {
    if (_query.isEmpty) return _entries;
    final q = _query.toLowerCase();
    return _entries.where((e) => e.name == '..' || e.name.toLowerCase().contains(q)).toList();
  }

  /// Leaf segment for the confirm button; full path stays in the breadcrumb.
  String get _selectedDirName {
    if (_selectedDir == '/') return '/';
    final trimmed = _selectedDir.endsWith('/') ? _selectedDir.substring(0, _selectedDir.length - 1) : _selectedDir;
    final idx = trimmed.lastIndexOf('/');
    if (idx < 0) return trimmed;
    final name = trimmed.substring(idx + 1);
    return name.isEmpty ? '/' : name;
  }

  List<RemoteFileEntry> _sortEntries(List<RemoteFileEntry> entries) {
    final sorted = [...entries];
    sorted.sort((a, b) {
      if (a.isDirectory != b.isDirectory) {
        return a.isDirectory ? -1 : 1;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return sorted;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _connect());
  }

  @override
  void dispose() {
    _connection?.disconnect();
    super.dispose();
  }

  Future<void> _connect() async {
    final hostId = widget.hostId;
    if (hostId == null) {
      if (mounted) {
        setState(() {
          _error = 'No host selected';
          _loading = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _connecting = true;
        _error = null;
      });
    }

    try {
      final hosts = await ref.read(hostsProvider.future);
      if (!mounted) return;
      Host? host;
      for (final h in hosts) {
        if (h.id == hostId) {
          host = h;
          break;
        }
      }
      if (host == null) throw StateError('Host not found');
      final conn = await SshConnection.connect(
        host: host,
        hosts: ref.read(hostRepositoryProvider),
        keys: ref.read(sshKeyRepositoryProvider),
        knownHosts: ref.read(knownHostsStoreProvider),
      );
      if (!mounted) {
        await conn.disconnect();
        return;
      }
      final recents = await ref.read(recentPathsStoreProvider).getRecentPaths(hostId);
      if (!mounted) return;
      _connection = conn;
      _host = host;
      _recentPaths = recents;
      _path = '/home/${host.username}';
      if (recents.isNotEmpty) {
        _selectedDir = recents.first;
        setState(() {
          _view = _PathView.recents;
          _loading = false;
          _connecting = false;
        });
      } else {
        _selectedDir = _path;
        await _enterBrowseMode();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
          _connecting = false;
        });
      }
    }
  }

  Future<void> _enterBrowseMode({String? startPath}) async {
    if (_host != null) {
      _path = startPath ?? '/home/${_host!.username}';
      _selectedDir = _path;
    }
    if (mounted) {
      setState(() => _view = _PathView.browse);
    }
    await _loadDir();
  }

  Future<void> _loadDir() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      var entries = await _connection!.listDirectory(_path);
      if (!mounted) return;
      final children = _sortEntries(entries.where((e) => e.name != '.' && e.name != '..').toList());
      entries = [
        const RemoteFileEntry(name: '..', isDirectory: true, permissions: 'drwxr-xr-x'),
        ...children,
      ];
      setState(() {
        _entries = entries;
        _selectedDir = _path;
        _query = '';
        _loading = false;
        _connecting = false;
      });
    } catch (e) {
      if (_path != '/') {
        _path = '/';
        _selectedDir = '/';
        await _loadDir();
        return;
      }
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
          _connecting = false;
        });
      }
    }
  }

  void _open(RemoteFileEntry entry) {
    if (entry.name == '..') {
      if (_path == '/') return;
      final trimmed = _path.endsWith('/') ? _path.substring(0, _path.length - 1) : _path;
      final idx = trimmed.lastIndexOf('/');
      _path = idx <= 0 ? '/' : trimmed.substring(0, idx);
      _selectedDir = _path;
      _loadDir();
      return;
    }
    if (!entry.isDirectory) return;
    _path = _path.endsWith('/') ? '$_path${entry.name}' : '$_path/${entry.name}';
    _selectedDir = _path;
    _loadDir();
  }

  Future<void> _createFolder() async {
    final name = await NewFolderDialog.show(context);
    if (name == null || name.isEmpty || _connection == null) return;

    final newPath = _path.endsWith('/') ? '$_path$name' : '$_path/$name';
    try {
      await _connection!.createDirectory(newPath);
      if (!mounted) return;
      _selectedDir = newPath;
      await _loadDir();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not create folder: $e')));
      }
    }
  }

  Future<void> _startSession() async {
    final hostId = widget.hostId;
    if (hostId == null || _connection == null) return;

    if (mounted) setState(() => _connecting = true);
    try {
      final hosts = await ref.read(hostsProvider.future);
      if (!mounted) return;
      Host? host;
      for (final h in hosts) {
        if (h.id == hostId) {
          host = h;
          break;
        }
      }
      if (host == null) throw StateError('Host not found');
      final choice = await SessionNameDialog.show(
        context,
        title: 'Start terminal',
        initialName: await ref.read(workspaceManagerProvider).suggestSessionName(host),
      );
      if (!mounted || choice == null) {
        if (mounted) setState(() => _connecting = false);
        return;
      }

      var useTmux = choice.useTmux;
      if (choice.useTmux) {
        if (mounted) setState(() => _connecting = false);
        final resolved = await TmuxAvailability.resolve(
          context: context,
          connection: _connection!,
          wantsTmux: true,
        );
        if (!mounted) return;
        if (resolved == null) return;
        useTmux = resolved.useTmux;
        if (mounted) setState(() => _connecting = true);
      }

      await ref.read(recentPathsStoreProvider).recordRecentPath(hostId, _selectedDir);
      final workspace = await ref.read(workspaceManagerProvider).createWorkspace(
            host: host,
            cwd: _selectedDir,
            tmuxSessionName: choice.sessionName,
            name: useTmux ? choice.sessionName : host.label,
            useTmux: useTmux,
            existing: _connection,
          );
      if (!mounted) return;
      _connection = null;
      if (mounted) openWorkspace(context, workspace.id, replace: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Connection failed: $e')));
        setState(() => _connecting = false);
      }
    }
  }

  void _onBack() {
    if (_view == _PathView.browse && _recentPaths.isNotEmpty) {
      setState(() {
        _view = _PathView.recents;
        _query = '';
        _error = null;
      });
      return;
    }
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final inBrowse = _view == _PathView.browse;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: _onBack),
        title: const Text('Select Path'),
        actions: [
          if (inBrowse && _connection != null && !_loading && _error == null)
            IconButton(
              icon: const Icon(Icons.create_new_folder_outlined),
              tooltip: 'New folder',
              onPressed: _connecting ? null : _createFolder,
            ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (inBrowse)
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.marginMobile, AppSpacing.marginMobile, AppSpacing.marginMobile, 0),
              child: Row(
                children: [
                  const Icon(Icons.home_outlined, color: ObsidianColors.primary, size: 18),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(_path, style: AppTypography.mono(size: 14, color: ObsidianColors.primary), overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
          if (inBrowse)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.marginMobile),
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search, color: ObsidianColors.outline),
                  hintText: 'Search folders and files...',
                ),
              ),
            ),
          if (_connecting && _loading) const LinearProgressIndicator(),
          Expanded(child: _buildBody()),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.marginMobile, AppSpacing.sm, AppSpacing.marginMobile, AppSpacing.md),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _connection == null || _connecting ? null : _startSession,
              style: FilledButton.styleFrom(
                backgroundColor: ObsidianColors.primary,
                foregroundColor: ObsidianColors.onPrimary,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.check_circle_outline),
                  const SizedBox(width: AppSpacing.sm),
                  Flexible(
                    child: Text(
                      "Select '$_selectedDirName'",
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: AppTypography.mono(size: 14, weight: FontWeight.w700, color: ObsidianColors.onPrimary),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Text(_error!, style: AppTypography.mono(size: 12, color: ObsidianColors.error)),
        ),
      );
    }
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_view == _PathView.recents) {
      return _buildRecentsView();
    }
    return _buildBrowseView();
  }

  Widget _buildRecentsView() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.marginMobile),
      children: [
        const SectionHeader('RECENT PATHS'),
        ..._recentPaths.map(
          (path) => Card(
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: ListTile(
              leading: Icon(
                Icons.history,
                color: _selectedDir == path ? ObsidianColors.primary : ObsidianColors.outline,
              ),
              title: Text(path, style: AppTypography.mono(size: 14)),
              selected: _selectedDir == path,
              trailing: IconButton(
                icon: const Icon(Icons.folder_open_outlined, color: ObsidianColors.outline),
                tooltip: 'Open in browser',
                onPressed: () => _enterBrowseMode(startPath: path),
              ),
              onTap: () => setState(() => _selectedDir = path),
            ),
          ),
        ),
        const SectionHeader('BROWSE'),
        Card(
          child: ListTile(
            leading: const Icon(Icons.folder_outlined, color: ObsidianColors.primary),
            title: Text('Browse directories', style: AppTypography.inter(size: 16, weight: FontWeight.w500)),
            subtitle: Text(
              _host != null ? '/home/${_host!.username}' : 'Remote filesystem',
              style: AppTypography.mono(size: 12, color: ObsidianColors.onSurfaceVariant),
            ),
            trailing: const Icon(Icons.chevron_right, color: ObsidianColors.outline),
            onTap: _enterBrowseMode,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
      ],
    );
  }

  Widget _buildBrowseView() {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.marginMobile),
      child: ListView.separated(
        itemCount: _displayEntries.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final e = _displayEntries[index];
          final isCurrentDir = _path == _selectedDir;
          return ListTile(
            leading: Icon(
              e.isDirectory ? Icons.folder : Icons.description_outlined,
              color: e.isDirectory && isCurrentDir ? ObsidianColors.primary : ObsidianColors.outline,
            ),
            title: Text(e.name, style: AppTypography.mono(size: 14)),
            subtitle: e.size != null
                ? Text('${e.size} bytes', style: AppTypography.inter(size: 12, color: ObsidianColors.onSurfaceVariant))
                : null,
            trailing: e.isDirectory ? const Icon(Icons.chevron_right, color: ObsidianColors.outline) : null,
            selected: e.isDirectory && isCurrentDir && e.name != '..',
            onTap: () {
              if (!e.isDirectory) return;
              if (e.name != '..') {
                _selectedDir = _path.endsWith('/') ? '$_path${e.name}' : '$_path/${e.name}';
              }
              _open(e);
            },
          );
        },
      ),
    );
  }
}
