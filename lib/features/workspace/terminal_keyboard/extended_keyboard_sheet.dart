import 'package:flutter/material.dart';

import '../../../core/constants/spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/obsidian_colors.dart';
import '../../../services/snippet_repository.dart';
import 'terminal_key_catalog.dart';

enum ExtendedKeyboardPasteTarget { commandBar, terminal }

class ExtendedKeyboardSheet extends StatefulWidget {
  const ExtendedKeyboardSheet({
    super.key,
    required this.history,
    required this.snippets,
    required this.onKeyAction,
    required this.onRunCommand,
    required this.onPasteCommand,
    required this.onAddSnippet,
    required this.onDeleteSnippet,
    this.initialTabIndex = 0,
  });

  final List<String> history;
  final List<TerminalSnippet> snippets;
  final TerminalKeyHandler onKeyAction;
  final ValueChanged<String> onRunCommand;
  final ValueChanged<String> onPasteCommand;
  final Future<void> Function(String name, String script) onAddSnippet;
  final Future<void> Function(String id) onDeleteSnippet;

  /// 0 = Keys, 1 = History, 2 = Snippets.
  final int initialTabIndex;

  static Future<void> show(
    BuildContext context, {
    required List<String> history,
    required List<TerminalSnippet> snippets,
    required TerminalKeyHandler onKeyAction,
    required ValueChanged<String> onRunCommand,
    required ValueChanged<String> onPasteCommand,
    required Future<void> Function(String name, String script) onAddSnippet,
    required Future<void> Function(String id) onDeleteSnippet,
    int initialTabIndex = 0,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ObsidianColors.surfaceContainerHigh,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        minChildSize: 0.45,
        maxChildSize: 0.92,
        builder: (context, scrollController) => ExtendedKeyboardSheet(
          history: history,
          snippets: snippets,
          onKeyAction: onKeyAction,
          onRunCommand: onRunCommand,
          onPasteCommand: onPasteCommand,
          onAddSnippet: onAddSnippet,
          onDeleteSnippet: onDeleteSnippet,
          initialTabIndex: initialTabIndex,
        ),
      ),
    );
  }

  @override
  State<ExtendedKeyboardSheet> createState() => _ExtendedKeyboardSheetState();
}

class _ExtendedKeyboardSheetState extends State<ExtendedKeyboardSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 2),
    );
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.sm, 0),
            child: Row(
              children: [
                const Icon(Icons.keyboard, size: 18, color: ObsidianColors.primary),
                const SizedBox(width: AppSpacing.sm),
                Text('Terminal keyboard', style: AppTypography.inter(size: 16, weight: FontWeight.w600)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          TabBar(
            controller: _tabs,
            tabs: const [
              Tab(text: 'Keys'),
              Tab(text: 'History'),
              Tab(text: 'Snippets'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _KeysTab(onKeyAction: widget.onKeyAction),
                _HistoryTab(
                  history: widget.history,
                  onRun: widget.onRunCommand,
                  onPaste: widget.onPasteCommand,
                ),
                _SnippetsTab(
                  snippets: widget.snippets,
                  onRun: widget.onRunCommand,
                  onPaste: widget.onPasteCommand,
                  onAdd: widget.onAddSnippet,
                  onDelete: widget.onDeleteSnippet,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _KeysTab extends StatelessWidget {
  const _KeysTab({required this.onKeyAction});

  final TerminalKeyHandler onKeyAction;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        for (final entry in TerminalKeyCatalog.extendedSections.entries) ...[
          Text(entry.key, style: AppTypography.inter(size: 13, weight: FontWeight.w600)),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final key in entry.value)
                ActionChip(
                  label: Text(key.label, style: AppTypography.mono(size: 12)),
                  onPressed: () {
                    onKeyAction(key.action);
                    if (!TerminalKeyCatalog.isUiAction(key.action) &&
                        !TerminalKeyCatalog.isToggle(key.action)) {
                      Navigator.pop(context);
                    }
                  },
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
      ],
    );
  }
}

class _HistoryTab extends StatelessWidget {
  const _HistoryTab({
    required this.history,
    required this.onRun,
    required this.onPaste,
  });

  final List<String> history;
  final ValueChanged<String> onRun;
  final ValueChanged<String> onPaste;

  @override
  Widget build(BuildContext context) {
    if (history.isEmpty) {
      return Center(
        child: Text('No commands yet', style: AppTypography.inter(size: 14, color: ObsidianColors.outline)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.md),
      itemCount: history.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final command = history[index];
        return ListTile(
          title: Text(command, style: AppTypography.mono(size: 13), maxLines: 3, overflow: TextOverflow.ellipsis),
          onTap: () {
            Navigator.pop(context);
            onRun(command);
          },
          onLongPress: () {
            Navigator.pop(context);
            onPaste(command);
          },
          trailing: const Icon(Icons.play_arrow, size: 18),
          subtitle: const Text('Tap to run · hold to paste'),
        );
      },
    );
  }
}

class _SnippetsTab extends StatefulWidget {
  const _SnippetsTab({
    required this.snippets,
    required this.onRun,
    required this.onPaste,
    required this.onAdd,
    required this.onDelete,
  });

  final List<TerminalSnippet> snippets;
  final ValueChanged<String> onRun;
  final ValueChanged<String> onPaste;
  final Future<void> Function(String name, String script) onAdd;
  final Future<void> Function(String id) onDelete;

  @override
  State<_SnippetsTab> createState() => _SnippetsTabState();
}

class _SnippetsTabState extends State<_SnippetsTab> {
  Future<void> _promptAdd() async {
    final nameController = TextEditingController();
    final scriptController = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New snippet'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            TextField(
              controller: scriptController,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Script'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (saved != true) return;
    final name = nameController.text.trim();
    final script = scriptController.text.trim();
    nameController.dispose();
    scriptController.dispose();
    if (name.isEmpty || script.isEmpty) return;
    await widget.onAdd(name, script);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: widget.snippets.isEmpty
              ? Center(
                  child: Text(
                    'No snippets saved',
                    style: AppTypography.inter(size: 14, color: ObsidianColors.outline),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  itemCount: widget.snippets.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final snippet = widget.snippets[index];
                    return ListTile(
                      title: Text(snippet.name, style: AppTypography.inter(size: 14, weight: FontWeight.w500)),
                      subtitle: Text(
                        snippet.script,
                        style: AppTypography.mono(size: 12),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        widget.onRun(snippet.script);
                      },
                      onLongPress: () {
                        Navigator.pop(context);
                        widget.onPaste(snippet.script);
                      },
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18),
                        onPressed: () async {
                          await widget.onDelete(snippet.id);
                          if (mounted) setState(() {});
                        },
                      ),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: FilledButton.icon(
            onPressed: _promptAdd,
            icon: const Icon(Icons.add),
            label: const Text('Add snippet'),
          ),
        ),
      ],
    );
  }
}
