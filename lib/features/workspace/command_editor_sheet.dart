import 'package:flutter/material.dart';

import '../../core/constants/spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/obsidian_colors.dart';

class CommandEditorSheet extends StatefulWidget {
  const CommandEditorSheet({super.key, required this.initialText});

  final String initialText;

  static Future<String?> show(BuildContext context, {String initial = ''}) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ObsidianColors.surfaceContainerHigh,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: CommandEditorSheet(initialText: initial),
      ),
    );
  }

  @override
  State<CommandEditorSheet> createState() => _CommandEditorSheetState();
}

class _CommandEditorSheetState extends State<CommandEditorSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                const Icon(Icons.terminal, color: ObsidianColors.primary, size: 18),
                const SizedBox(width: AppSpacing.sm),
                Text('Command Editor', style: AppTypography.inter(size: 16, weight: FontWeight.w600)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close_fullscreen, color: ObsidianColors.outline),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: TextField(
              controller: _controller,
              maxLines: 12,
              style: AppTypography.mono(size: 14),
              decoration: InputDecoration(
                hintText: 'Enter command…',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                  borderSide: const BorderSide(color: ObsidianColors.primary),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                _SymbolKey('|', onTap: () => _insert('|')),
                _SymbolKey(r'\', onTap: () => _insert(r'\')),
                _SymbolKey('Tab', onTap: () => _insert('\t')),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, _controller.text),
                    child: const Text(
                      'Send to terminal',
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _insert(String s) {
    final text = _controller.text;
    final sel = _controller.selection;
    final start = sel.start >= 0 ? sel.start : text.length;
    final newText = text.replaceRange(start, sel.end >= 0 ? sel.end : start, s);
    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + s.length),
    );
  }
}

class _SymbolKey extends StatelessWidget {
  const _SymbolKey(this.label, {required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.xs),
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        onPressed: onTap,
        child: Text(label, style: AppTypography.mono(size: 12)),
      ),
    );
  }
}
