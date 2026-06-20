import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/obsidian_colors.dart';
import '../../models/git_models.dart';
import '../../services/workspace_manager.dart';
import '../../widgets/section_header.dart';
import 'git_diff_viewer.dart';

enum _GitSection { changes, history, branches }

class GitManagerTab extends ConsumerStatefulWidget {
  const GitManagerTab({
    super.key,
    required this.workspaceId,
    required this.cwd,
    this.onOpenTerminal,
  });

  final String workspaceId;
  final String cwd;
  final VoidCallback? onOpenTerminal;

  @override
  ConsumerState<GitManagerTab> createState() => _GitManagerTabState();
}

class _GitManagerTabState extends ConsumerState<GitManagerTab> {
  GitRepoSnapshot? _snapshot;
  List<GitCommitInfo>? _commits;
  String? _error;
  bool _loading = true;
  bool _busy = false;
  _GitSection _section = _GitSection.changes;

  final _summaryController = TextEditingController();
  final _descriptionController = TextEditingController();

  String? _selectedFile;
  bool _selectedStaged = false;
  String? _fileDiff;
  bool _diffLoading = false;

  String? _commitDetail;
  bool _commitDetailLoading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _summaryController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  WorkspaceManager get _manager => ref.read(workspaceManagerProvider);

  Future<void> _load({bool refreshHistory = true}) async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final snapshot = await _manager.loadGitSnapshot(widget.workspaceId, widget.cwd);
      List<GitCommitInfo>? commits = _commits;
      if (refreshHistory) {
        commits = await _manager.gitLog(widget.workspaceId, snapshot.repoRoot);
      }
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _commits = commits;
        _loading = false;
      });
      if (_selectedFile != null) {
        await _loadFileDiff(_selectedFile!, staged: _selectedStaged);
      }
    } on GitNotARepositoryException {
      if (!mounted) return;
      setState(() {
        _error = 'Not a git repository.\n\nOpen a directory that contains a .git folder, or initialize one from the Terminal tab.';
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

  Future<void> _runBusy(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? ObsidianColors.onError : null,
      ),
    );
  }

  Future<void> _loadFileDiff(String path, {required bool staged}) async {
    final repoRoot = _snapshot?.repoRoot;
    if (repoRoot == null) return;
    setState(() {
      _selectedFile = path;
      _selectedStaged = staged;
      _diffLoading = true;
      _fileDiff = null;
      _commitDetail = null;
    });
    try {
      final diff = await _manager.gitFileDiff(widget.workspaceId, repoRoot, path, staged: staged);
      if (!mounted) return;
      setState(() {
        _fileDiff = diff;
        _diffLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _fileDiff = e.toString();
        _diffLoading = false;
      });
    }
  }

  Future<void> _loadCommitDetail(GitCommitInfo commit) async {
    final repoRoot = _snapshot?.repoRoot;
    if (repoRoot == null) return;
    setState(() {
      _commitDetailLoading = true;
      _commitDetail = null;
      _selectedFile = null;
      _fileDiff = null;
    });
    try {
      final detail = await _manager.gitShowCommit(widget.workspaceId, repoRoot, commit.fullSha);
      if (!mounted) return;
      setState(() {
        _commitDetail = detail;
        _commitDetailLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _commitDetail = e.toString();
        _commitDetailLoading = false;
      });
    }
  }

  Future<void> _sync(Future<GitCommandResult> Function(String repoRoot) command) async {
    final repoRoot = _snapshot?.repoRoot;
    if (repoRoot == null) return;
    await _runBusy(() async {
      final result = await command(repoRoot);
      _snack(result.message, error: !result.success);
      if (result.success) await _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _snapshot == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _ErrorView(message: _error!, onRetry: _load);
    }

    final snapshot = _snapshot!;
    final showingDetail = _selectedFile != null || _commitDetail != null || _commitDetailLoading;

    return Column(
      children: [
        _StatusBar(
          snapshot: snapshot,
          busy: _busy,
          onRefresh: _load,
          onFetch: () => _sync((r) => _manager.gitFetch(widget.workspaceId, r)),
          onPull: () => _sync((r) => _manager.gitPull(widget.workspaceId, r)),
          onPush: () => _sync((r) => _manager.gitPush(widget.workspaceId, r)),
        ),
        if (snapshot.conflicted.isNotEmpty)
          _ConflictBanner(onOpenTerminal: widget.onOpenTerminal),
        if (showingDetail)
          Expanded(child: _buildDetailView(snapshot))
        else ...[
          _SectionTabs(section: _section, onChanged: (s) => setState(() => _section = s)),
          Expanded(child: _buildSection(snapshot)),
          if (_section == _GitSection.changes) _CommitBar(
            busy: _busy,
            stagedCount: snapshot.staged.length,
            summaryController: _summaryController,
            descriptionController: _descriptionController,
            onCommit: () => _runBusy(() async {
              final result = await _manager.gitCommit(
                widget.workspaceId,
                snapshot.repoRoot,
                _summaryController.text,
                description: _descriptionController.text,
              );
              _snack(result.message, error: !result.success);
              if (result.success) {
                _summaryController.clear();
                _descriptionController.clear();
                await _load();
              }
            }),
          ),
        ],
      ],
    );
  }

  Widget _buildDetailView(GitRepoSnapshot snapshot) {
    if (_commitDetailLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_commitDetail != null) {
      return Column(
        children: [
          _DetailHeader(
            title: 'Commit',
            onBack: () => setState(() => _commitDetail = null),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: SelectableText(
                _commitDetail!,
                style: AppTypography.mono(size: 11),
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        _DetailHeader(
          title: _selectedFile ?? '',
          onBack: () => setState(() {
            _selectedFile = null;
            _fileDiff = null;
          }),
          actions: [
            if (_selectedStaged)
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _runBusy(() async {
                          await _manager.gitUnstageFile(widget.workspaceId, snapshot.repoRoot, _selectedFile!);
                          await _load(refreshHistory: false);
                        }),
                child: const Text('Unstage'),
              )
            else
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _runBusy(() async {
                          await _manager.gitStageFile(widget.workspaceId, snapshot.repoRoot, _selectedFile!);
                          await _load(refreshHistory: false);
                        }),
                child: const Text('Stage'),
              ),
            PopupMenuButton<String>(
              enabled: !_busy,
              onSelected: (value) => _runBusy(() async {
                if (value == 'discard') {
                  final confirmed = await _confirmDiscard(_selectedFile!);
                  if (!confirmed) return;
                  await _manager.gitDiscardFile(widget.workspaceId, snapshot.repoRoot, _selectedFile!);
                  setState(() {
                    _selectedFile = null;
                    _fileDiff = null;
                  });
                  await _load(refreshHistory: false);
                }
              }),
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'discard', child: Text('Discard changes')),
              ],
            ),
          ],
        ),
        Expanded(
          child: _diffLoading
              ? const Center(child: CircularProgressIndicator())
              : GitDiffViewer(diff: _fileDiff ?? ''),
        ),
      ],
    );
  }

  Future<bool> _confirmDiscard(String path) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard changes?'),
        content: Text('Revert unstaged changes in\n$path'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Discard', style: TextStyle(color: ObsidianColors.error)),
          ),
        ],
      ),
    );
    return result == true;
  }

  Widget _buildSection(GitRepoSnapshot snapshot) {
    return switch (_section) {
      _GitSection.changes => _ChangesSection(
          snapshot: snapshot,
          busy: _busy,
          onFileTap: (path, staged) => _loadFileDiff(path, staged: staged),
          onStageAll: () => _runBusy(() async {
            await _manager.gitStageAll(widget.workspaceId, snapshot.repoRoot);
            await _load(refreshHistory: false);
          }),
          onUnstageAll: () => _runBusy(() async {
            await _manager.gitUnstageAll(widget.workspaceId, snapshot.repoRoot);
            await _load(refreshHistory: false);
          }),
          onStage: (path) => _runBusy(() async {
            await _manager.gitStageFile(widget.workspaceId, snapshot.repoRoot, path);
            await _load(refreshHistory: false);
          }),
          onUnstage: (path) => _runBusy(() async {
            await _manager.gitUnstageFile(widget.workspaceId, snapshot.repoRoot, path);
            await _load(refreshHistory: false);
          }),
          onDiscard: (path) => _runBusy(() async {
            final confirmed = await _confirmDiscard(path);
            if (!confirmed) return;
            await _manager.gitDiscardFile(widget.workspaceId, snapshot.repoRoot, path);
            await _load(refreshHistory: false);
          }),
        ),
      _GitSection.history => _HistorySection(
          commits: _commits ?? const [],
          onCommitTap: _loadCommitDetail,
        ),
      _GitSection.branches => _BranchesSection(
          snapshot: snapshot,
          busy: _busy,
          onCheckout: (branch) => _runBusy(() async {
            final result = await _manager.gitCheckoutBranch(widget.workspaceId, snapshot.repoRoot, branch);
            _snack(result.message, error: !result.success);
            if (result.success) await _load();
          }),
          onCreateBranch: () => _createBranch(snapshot.repoRoot),
        ),
    };
  }

  Future<void> _createBranch(String repoRoot) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create branch'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'branch-name'),
          style: AppTypography.mono(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    await _runBusy(() async {
      final result = await _manager.gitCreateBranch(widget.workspaceId, repoRoot, name);
      _snack(result.message, error: !result.success);
      if (result.success) await _load();
    });
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.folder_off_outlined, size: 48, color: ObsidianColors.onSurfaceVariant),
            const SizedBox(height: AppSpacing.md),
            Text(message, textAlign: TextAlign.center, style: AppTypography.inter(size: 14)),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({
    required this.snapshot,
    required this.busy,
    required this.onRefresh,
    required this.onFetch,
    required this.onPull,
    required this.onPush,
  });

  final GitRepoSnapshot snapshot;
  final bool busy;
  final VoidCallback onRefresh;
  final VoidCallback onFetch;
  final VoidCallback onPull;
  final VoidCallback onPush;

  @override
  Widget build(BuildContext context) {
    final syncLabel = StringBuffer();
    if (snapshot.hasUpstream) {
      if ((snapshot.ahead ?? 0) > 0) syncLabel.write('↑${snapshot.ahead} ');
      if ((snapshot.behind ?? 0) > 0) syncLabel.write('↓${snapshot.behind} ');
    }
    final statusColor = snapshot.isClean ? ObsidianColors.secondary : ObsidianColors.tertiary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: const BoxDecoration(
        color: ObsidianColors.surfaceContainer,
        border: Border(bottom: BorderSide(color: ObsidianColors.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                snapshot.detached ? Icons.link_off : Icons.call_split,
                size: 16,
                color: ObsidianColors.primary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  snapshot.branch,
                  style: AppTypography.mono(size: 13, weight: FontWeight.w600, color: ObsidianColors.primary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (syncLabel.isNotEmpty)
                Text(syncLabel.toString().trim(), style: AppTypography.mono(size: 11, color: ObsidianColors.onSurfaceVariant)),
              IconButton(
                icon: busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh, size: 18),
                onPressed: busy ? null : onRefresh,
                tooltip: 'Refresh',
              ),
              PopupMenuButton<String>(
                enabled: !busy,
                icon: const Icon(Icons.sync, size: 18),
                onSelected: (value) => switch (value) {
                  'fetch' => onFetch(),
                  'pull' => onPull(),
                  'push' => onPush(),
                  _ => null,
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'fetch', child: Text('Fetch')),
                  const PopupMenuItem(value: 'pull', child: Text('Pull')),
                  const PopupMenuItem(value: 'push', child: Text('Push')),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                snapshot.isClean ? 'Clean working tree' : 'Changes present',
                style: AppTypography.mono(size: 11, color: ObsidianColors.onSurfaceVariant),
              ),
              if (snapshot.remoteUrl != null) ...[
                const Spacer(),
                Icon(Icons.cloud_outlined, size: 14, color: ObsidianColors.onSurfaceVariant),
                const SizedBox(width: AppSpacing.xs),
                Flexible(
                  child: Text(
                    snapshot.remoteUrl!,
                    style: AppTypography.mono(size: 10, color: ObsidianColors.onSurfaceVariant),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
          if (snapshot.upstream != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                'Tracking ${snapshot.upstream}',
                style: AppTypography.mono(size: 10, color: ObsidianColors.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }
}

class _ConflictBanner extends StatelessWidget {
  const _ConflictBanner({this.onOpenTerminal});

  final VoidCallback? onOpenTerminal;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: ObsidianColors.error.withValues(alpha: 0.15),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, size: 18, color: ObsidianColors.error),
            const SizedBox(width: AppSpacing.sm),
            const Expanded(
              child: Text('Merge conflicts detected', style: TextStyle(color: ObsidianColors.error)),
            ),
            if (onOpenTerminal != null)
              TextButton(onPressed: onOpenTerminal, child: const Text('Terminal')),
          ],
        ),
      ),
    );
  }
}

class _SectionTabs extends StatelessWidget {
  const _SectionTabs({required this.section, required this.onChanged});

  final _GitSection section;
  final ValueChanged<_GitSection> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: SegmentedButton<_GitSection>(
        segments: const [
          ButtonSegment(value: _GitSection.changes, label: Text('Changes'), icon: Icon(Icons.difference_outlined, size: 16)),
          ButtonSegment(value: _GitSection.history, label: Text('History'), icon: Icon(Icons.history, size: 16)),
          ButtonSegment(value: _GitSection.branches, label: Text('Branches'), icon: Icon(Icons.call_split, size: 16)),
        ],
        selected: {section},
        onSelectionChanged: (s) => onChanged(s.first),
      ),
    );
  }
}

class _ChangesSection extends StatelessWidget {
  const _ChangesSection({
    required this.snapshot,
    required this.busy,
    required this.onFileTap,
    required this.onStageAll,
    required this.onUnstageAll,
    required this.onStage,
    required this.onUnstage,
    required this.onDiscard,
  });

  final GitRepoSnapshot snapshot;
  final bool busy;
  final void Function(String path, bool staged) onFileTap;
  final VoidCallback onStageAll;
  final VoidCallback onUnstageAll;
  final ValueChanged<String> onStage;
  final ValueChanged<String> onUnstage;
  final ValueChanged<String> onDiscard;

  @override
  Widget build(BuildContext context) {
    if (snapshot.isClean) {
      return Center(
        child: Text('No local changes', style: AppTypography.mono(color: ObsidianColors.onSurfaceVariant)),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      children: [
        if (snapshot.conflicted.isNotEmpty) ...[
          SectionHeader('CONFLICTED (${snapshot.conflicted.length})'),
          ...snapshot.conflicted.map(
            (f) => _FileTile(
              change: f,
              staged: f.staged,
              busy: busy,
              onTap: () => onFileTap(f.path, f.staged),
              onStage: f.staged ? null : () => onStage(f.path),
              onUnstage: f.staged ? () => onUnstage(f.path) : null,
              onDiscard: null,
            ),
          ),
        ],
        if (snapshot.staged.isNotEmpty) ...[
          _SectionRow(
            title: 'STAGED (${snapshot.staged.length})',
            actionLabel: 'Unstage all',
            onAction: busy ? null : onUnstageAll,
          ),
          ...snapshot.staged.map(
            (f) => _FileTile(
              change: f,
              staged: true,
              busy: busy,
              onTap: () => onFileTap(f.path, true),
              onStage: null,
              onUnstage: () => onUnstage(f.path),
              onDiscard: null,
            ),
          ),
        ],
        if (snapshot.unstaged.isNotEmpty) ...[
          _SectionRow(
            title: 'UNSTAGED (${snapshot.unstaged.length})',
            actionLabel: 'Stage all',
            onAction: busy ? null : onStageAll,
          ),
          ...snapshot.unstaged.map(
            (f) => _FileTile(
              change: f,
              staged: false,
              busy: busy,
              onTap: () => onFileTap(f.path, false),
              onStage: () => onStage(f.path),
              onUnstage: null,
              onDiscard: () => onDiscard(f.path),
            ),
          ),
        ],
        if (snapshot.untracked.isNotEmpty) ...[
          SectionHeader('UNTRACKED (${snapshot.untracked.length})'),
          ...snapshot.untracked.map(
            (f) => _FileTile(
              change: f,
              staged: false,
              busy: busy,
              onTap: () => onFileTap(f.path, false),
              onStage: () => onStage(f.path),
              onUnstage: null,
              onDiscard: null,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
      ],
    );
  }
}

class _SectionRow extends StatelessWidget {
  const _SectionRow({required this.title, required this.actionLabel, this.onAction});

  final String title;
  final String actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: AppTypography.mono(size: 11, weight: FontWeight.w500, color: ObsidianColors.onSurfaceVariant)
                  .copyWith(letterSpacing: 1.1),
            ),
          ),
          if (onAction != null)
            TextButton(onPressed: onAction, child: Text(actionLabel, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }
}

class _FileTile extends StatelessWidget {
  const _FileTile({
    required this.change,
    required this.staged,
    required this.busy,
    required this.onTap,
    this.onStage,
    this.onUnstage,
    this.onDiscard,
  });

  final GitFileChange change;
  final bool staged;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback? onStage;
  final VoidCallback? onUnstage;
  final VoidCallback? onDiscard;

  @override
  Widget build(BuildContext context) {
    final color = change.conflicted
        ? ObsidianColors.error
        : change.kind == GitChangeKind.added
            ? ObsidianColors.secondary
            : ObsidianColors.primary;

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 24,
        alignment: Alignment.center,
        child: Text(change.statusLabel, style: AppTypography.mono(size: 12, weight: FontWeight.w700, color: color)),
      ),
      title: Text(change.path, style: AppTypography.mono(size: 12), overflow: TextOverflow.ellipsis),
      subtitle: change.oldPath != null ? Text('← ${change.oldPath}', style: AppTypography.mono(size: 10)) : null,
      onTap: busy ? null : onTap,
      trailing: PopupMenuButton<String>(
        enabled: !busy,
        icon: const Icon(Icons.more_horiz, size: 18),
        onSelected: (value) {
          switch (value) {
            case 'stage':
              onStage?.call();
            case 'unstage':
              onUnstage?.call();
            case 'discard':
              onDiscard?.call();
          }
        },
        itemBuilder: (context) => [
          if (onStage != null) const PopupMenuItem(value: 'stage', child: Text('Stage')),
          if (onUnstage != null) const PopupMenuItem(value: 'unstage', child: Text('Unstage')),
          if (onDiscard != null)
            const PopupMenuItem(value: 'discard', child: Text('Discard', style: TextStyle(color: ObsidianColors.error))),
        ],
      ),
    );
  }
}

class _HistorySection extends StatelessWidget {
  const _HistorySection({required this.commits, required this.onCommitTap});

  final List<GitCommitInfo> commits;
  final ValueChanged<GitCommitInfo> onCommitTap;

  @override
  Widget build(BuildContext context) {
    if (commits.isEmpty) {
      return Center(
        child: Text('No commits', style: AppTypography.mono(color: ObsidianColors.onSurfaceVariant)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.md),
      itemCount: commits.length,
      separatorBuilder: (_, _) => const Divider(height: 1, color: ObsidianColors.outlineVariant),
      itemBuilder: (context, index) {
        final c = commits[index];
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Text(c.shortSha, style: AppTypography.mono(size: 11, color: ObsidianColors.primary)),
          title: Text(c.subject, style: AppTypography.mono(size: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text('${c.author} · ${c.relativeDate}', style: AppTypography.mono(size: 10)),
          onTap: () => onCommitTap(c),
        );
      },
    );
  }
}

class _BranchesSection extends StatelessWidget {
  const _BranchesSection({
    required this.snapshot,
    required this.busy,
    required this.onCheckout,
    required this.onCreateBranch,
  });

  final GitRepoSnapshot snapshot;
  final bool busy;
  final ValueChanged<String> onCheckout;
  final VoidCallback onCreateBranch;

  @override
  Widget build(BuildContext context) {
    final local = snapshot.branches.where((b) => !b.isRemote).toList();
    final remote = snapshot.branches.where((b) => b.isRemote).toList();

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.tonalIcon(
            onPressed: busy ? null : onCreateBranch,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('New branch'),
          ),
        ),
        SectionHeader('LOCAL'),
        ...local.map((b) => _BranchTile(branch: b, busy: busy, onCheckout: onCheckout)),
        if (remote.isNotEmpty) ...[
          SectionHeader('REMOTE'),
          ...remote.map((b) => _BranchTile(branch: b, busy: busy, onCheckout: onCheckout)),
        ],
      ],
    );
  }
}

class _BranchTile extends StatelessWidget {
  const _BranchTile({required this.branch, required this.busy, required this.onCheckout});

  final GitBranchInfo branch;
  final bool busy;
  final ValueChanged<String> onCheckout;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        branch.isCurrent ? Icons.check_circle : Icons.radio_button_unchecked,
        size: 18,
        color: branch.isCurrent ? ObsidianColors.secondary : ObsidianColors.onSurfaceVariant,
      ),
      title: Text(branch.name, style: AppTypography.mono(size: 12)),
      onTap: branch.isCurrent || busy ? null : () => onCheckout(branch.name),
    );
  }
}

class _CommitBar extends StatelessWidget {
  const _CommitBar({
    required this.busy,
    required this.stagedCount,
    required this.summaryController,
    required this.descriptionController,
    required this.onCommit,
  });

  final bool busy;
  final int stagedCount;
  final TextEditingController summaryController;
  final TextEditingController descriptionController;
  final VoidCallback onCommit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: const BoxDecoration(
        color: ObsidianColors.surfaceContainer,
        border: Border(top: BorderSide(color: ObsidianColors.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: summaryController,
              enabled: !busy,
              decoration: InputDecoration(
                hintText: 'Commit summary',
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.radiusLg)),
              ),
              style: AppTypography.mono(size: 13),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: descriptionController,
              enabled: !busy,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: 'Description (optional)',
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.radiusLg)),
              ),
              style: AppTypography.mono(size: 12),
            ),
            const SizedBox(height: AppSpacing.sm),
            FilledButton(
              onPressed: busy || stagedCount == 0 ? null : onCommit,
              child: Text(stagedCount == 0 ? 'Nothing staged' : 'Commit $stagedCount file${stagedCount == 1 ? '' : 's'}'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailHeader extends StatelessWidget {
  const _DetailHeader({required this.title, required this.onBack, this.actions = const []});

  final String title;
  final VoidCallback onBack;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: ObsidianColors.outlineVariant)),
      ),
      child: Row(
        children: [
          IconButton(icon: const Icon(Icons.arrow_back, size: 20), onPressed: onBack),
          Expanded(
            child: Text(title, style: AppTypography.mono(size: 12), overflow: TextOverflow.ellipsis),
          ),
          ...actions,
        ],
      ),
    );
  }
}
