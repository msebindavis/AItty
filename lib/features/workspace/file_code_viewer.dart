import 'package:flutter/material.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:highlight/highlight.dart' show highlight;

import '../../core/theme/app_typography.dart';
import '../../core/theme/obsidian_colors.dart';

class FileCodeViewer extends StatefulWidget {
  const FileCodeViewer({
    super.key,
    required this.content,
    this.language,
  });

  final String content;
  final String? language;

  @override
  State<FileCodeViewer> createState() => _FileCodeViewerState();
}

class _FileCodeViewerState extends State<FileCodeViewer> {
  static const _baseFontSize = 13.0;
  static const _baseLineHeight = 20.0;
  static const _minScale = 0.5;
  static const _maxScale = 3.0;
  static const _verticalPadding = 8.0;
  static const _zoomStep = 1.25;

  final ScrollController _verticalScroll = ScrollController();
  final TextEditingController _findController = TextEditingController();
  final FocusNode _findFocus = FocusNode();

  bool _showFind = false;
  String _searchQuery = '';
  int _currentMatchIndex = 0;
  List<int> _matchLines = [];
  int? _focusedLine;
  double _fontScale = 1.0;
  double _pinchBaseScale = 1.0;

  List<String> get _lines => _splitLines(widget.content);

  double get _fontSize => _baseFontSize * _fontScale;

  double get _lineHeight => _baseLineHeight * _fontScale;

  TextStyle get _codeTextStyle => AppTypography.mono(size: _fontSize, lineHeight: _lineHeight);

  Map<String, TextStyle> get _codeTheme => _buildCodeTheme(_codeTextStyle);

  String? get _resolvedLanguage => _resolveLanguage(widget.content, widget.language);

  double get _gutterWidth {
    final digits = _lines.length.toString().length;
    return 12 + digits * _fontSize * 0.65;
  }

  @override
  void initState() {
    super.initState();
    _findController.addListener(_onFindChanged);
  }

  @override
  void didUpdateWidget(covariant FileCodeViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.content != widget.content || oldWidget.language != widget.language) {
      _updateMatches(resetIndex: true);
      _focusedLine = null;
    }
  }

  @override
  void dispose() {
    _verticalScroll.dispose();
    _findController.dispose();
    _findFocus.dispose();
    super.dispose();
  }

  void _setFontScale(double scale) {
    setState(() => _fontScale = scale.clamp(_minScale, _maxScale));
  }

  void _zoomIn() => _setFontScale(_fontScale * _zoomStep);

  void _zoomOut() => _setFontScale(_fontScale / _zoomStep);

  void _resetZoom() => _setFontScale(1.0);

  List<String> _splitLines(String content) {
    if (content.isEmpty) return [''];
    return content.split('\n');
  }

  String? _resolveLanguage(String content, String? language) {
    if (language != null) return language;
    try {
      final detected = highlight.parse(content, autoDetection: true);
      return detected.language;
    } catch (_) {
      return 'plaintext';
    }
  }

  Map<String, TextStyle> _buildCodeTheme(TextStyle base) {
    final root = atomOneDarkTheme['root']!.copyWith(
      backgroundColor: ObsidianColors.terminalBackground,
      color: atomOneDarkTheme['root']!.color,
    );
    return {
      for (final entry in atomOneDarkTheme.entries)
        entry.key: entry.key == 'root' ? base.merge(root) : entry.value,
    };
  }

  void _onFindChanged() {
    final query = _findController.text;
    if (query == _searchQuery) return;
    setState(() {
      _searchQuery = query;
      _updateMatches(resetIndex: true);
      _focusedLine = _matchLines.isEmpty ? null : _matchLines.first;
    });
    if (_matchLines.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToLineIndex(_matchLines.first));
    }
  }

  void _updateMatches({required bool resetIndex}) {
    if (_searchQuery.isEmpty) {
      _matchLines = [];
      _currentMatchIndex = 0;
      return;
    }
    final lower = _searchQuery.toLowerCase();
    _matchLines = [
      for (var i = 0; i < _lines.length; i++)
        if (_lines[i].toLowerCase().contains(lower)) i,
    ];
    if (resetIndex) {
      _currentMatchIndex = 0;
    } else if (_matchLines.isNotEmpty && _currentMatchIndex >= _matchLines.length) {
      _currentMatchIndex = _matchLines.length - 1;
    }
  }

  int? get _activeHighlightLine {
    if (_focusedLine != null) return _focusedLine;
    if (_searchQuery.isNotEmpty && _matchLines.isNotEmpty) {
      return _matchLines[_currentMatchIndex];
    }
    return null;
  }

  Future<void> _showGoToLineDialog() async {
    final controller = TextEditingController();
    final line = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ObsidianColors.surfaceContainer,
        title: Text('Go to line', style: AppTypography.inter(size: 16, weight: FontWeight.w600)),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          style: AppTypography.mono(size: 14),
          decoration: InputDecoration(
            hintText: '1–${_lines.length}',
            hintStyle: AppTypography.mono(size: 14, color: ObsidianColors.outline),
          ),
          onSubmitted: (value) {
            final parsed = int.tryParse(value.trim());
            Navigator.pop(ctx, parsed);
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final parsed = int.tryParse(controller.text.trim());
              Navigator.pop(ctx, parsed);
            },
            child: const Text('Go'),
          ),
        ],
      ),
    );
    if (!mounted || line == null) return;
    _goToLine(line);
  }

  void _goToLine(int line) {
    if (line < 1 || line > _lines.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Line must be between 1 and ${_lines.length}')),
      );
      return;
    }
    setState(() => _focusedLine = line - 1);
    _scrollToLineIndex(line - 1);
  }

  void _scrollToLineIndex(int index) {
    if (!_verticalScroll.hasClients) return;
    final target = _verticalPadding + index * _lineHeight;
    _verticalScroll.animateTo(
      target.clamp(0, _verticalScroll.position.maxScrollExtent),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  void _findNext() {
    if (_matchLines.isEmpty) return;
    setState(() {
      _currentMatchIndex = (_currentMatchIndex + 1) % _matchLines.length;
      _focusedLine = _matchLines[_currentMatchIndex];
    });
    _scrollToLineIndex(_focusedLine!);
  }

  void _findPrevious() {
    if (_matchLines.isEmpty) return;
    setState(() {
      _currentMatchIndex = (_currentMatchIndex - 1 + _matchLines.length) % _matchLines.length;
      _focusedLine = _matchLines[_currentMatchIndex];
    });
    _scrollToLineIndex(_focusedLine!);
  }

  void _toggleFind() {
    setState(() {
      _showFind = !_showFind;
      if (_showFind) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _findFocus.requestFocus());
      } else {
        _searchQuery = '';
        _findController.clear();
        _matchLines = [];
        _currentMatchIndex = 0;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildToolbar(),
        if (_showFind) _buildFindBar(),
        Expanded(child: _buildCodeArea()),
      ],
    );
  }

  Widget _buildToolbar() {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 2),
      color: ObsidianColors.surfaceContainerLow,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 300;
          return Row(
            children: [
              _toolbarIconButton(
                icon: Icons.search,
                tooltip: 'Find',
                active: _showFind,
                onPressed: _toggleFind,
              ),
              _toolbarIconButton(
                icon: Icons.format_list_numbered,
                tooltip: 'Go to line',
                onPressed: _showGoToLineDialog,
              ),
              if (!compact) ...[
                _toolbarIconButton(
                  icon: Icons.zoom_out,
                  tooltip: 'Zoom out',
                  onPressed: _fontScale <= _minScale ? null : _zoomOut,
                ),
                _toolbarIconButton(
                  icon: Icons.zoom_in,
                  tooltip: 'Zoom in',
                  onPressed: _fontScale >= _maxScale ? null : _zoomIn,
                ),
                if ((_fontScale - 1.0).abs() > 0.01)
                  _toolbarIconButton(
                    icon: Icons.fit_screen,
                    tooltip: 'Reset zoom',
                    iconSize: 16,
                    onPressed: _resetZoom,
                  ),
              ],
              Expanded(
                child: Text(
                  compact
                      ? '${(_fontScale * 100).round()}%'
                      : '${_lines.length} lines · ${(_fontScale * 100).round()}%',
                  style: AppTypography.mono(size: 10, color: ObsidianColors.outline),
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (compact) _buildZoomMenu(),
              const SizedBox(width: 2),
            ],
          );
        },
      ),
    );
  }

  Widget _toolbarIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
    bool active = false,
    double iconSize = 18,
  }) {
    return IconButton(
      icon: Icon(icon, size: iconSize, color: active ? ObsidianColors.primary : ObsidianColors.outline),
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      onPressed: onPressed,
    );
  }

  Widget _buildZoomMenu() {
    return PopupMenuButton<String>(
      padding: EdgeInsets.zero,
      tooltip: 'Zoom',
      icon: Icon(Icons.zoom_in_map, size: 18, color: ObsidianColors.outline),
      onSelected: (value) {
        switch (value) {
          case 'in':
            _zoomIn();
          case 'out':
            _zoomOut();
          case 'reset':
            _resetZoom();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'out',
          enabled: _fontScale > _minScale,
          height: 36,
          child: Text('Zoom out', style: AppTypography.mono(size: 12)),
        ),
        PopupMenuItem(
          value: 'in',
          enabled: _fontScale < _maxScale,
          height: 36,
          child: Text('Zoom in', style: AppTypography.mono(size: 12)),
        ),
        if ((_fontScale - 1.0).abs() > 0.01)
          PopupMenuItem(
            value: 'reset',
            height: 36,
            child: Text('Reset zoom', style: AppTypography.mono(size: 12)),
          ),
      ],
    );
  }

  Widget _buildFindBar() {
    return Material(
      color: ObsidianColors.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _findController,
                focusNode: _findFocus,
                style: AppTypography.mono(size: 12),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Find in file…',
                  hintStyle: AppTypography.mono(size: 12, color: ObsidianColors.outline),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                ),
                onSubmitted: (_) => _findNext(),
              ),
            ),
            if (_searchQuery.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text(
                  '${_matchLines.isEmpty ? 0 : _currentMatchIndex + 1}/${_matchLines.length}',
                  style: AppTypography.mono(size: 11, color: ObsidianColors.outline),
                ),
              ),
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_up, size: 20),
              tooltip: 'Previous match',
              color: ObsidianColors.outline,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              onPressed: _matchLines.isEmpty ? null : _findPrevious,
            ),
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_down, size: 20),
              tooltip: 'Next match',
              color: ObsidianColors.outline,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              onPressed: _matchLines.isEmpty ? null : _findNext,
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              tooltip: 'Close find',
              color: ObsidianColors.outline,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              onPressed: _toggleFind,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCodeArea() {
    final highlightLine = _activeHighlightLine;
    final isCurrentMatch = _searchQuery.isNotEmpty &&
        _matchLines.isNotEmpty &&
        highlightLine == _matchLines[_currentMatchIndex];

    return ColoredBox(
      color: ObsidianColors.terminalBackground,
      child: GestureDetector(
        onScaleStart: (_) => _pinchBaseScale = _fontScale,
        onScaleUpdate: (details) => _setFontScale(_pinchBaseScale * details.scale),
        child: Scrollbar(
          controller: _verticalScroll,
          child: SingleChildScrollView(
            controller: _verticalScroll,
            padding: const EdgeInsets.symmetric(vertical: _verticalPadding),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  if (highlightLine != null)
                    Positioned(
                      left: 0,
                      right: 0,
                      top: highlightLine * _lineHeight,
                      height: _lineHeight,
                      child: ColoredBox(
                        color: isCurrentMatch
                            ? ObsidianColors.primary.withValues(alpha: 0.18)
                            : ObsidianColors.surfaceContainerHigh.withValues(alpha: 0.55),
                      ),
                    ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _LineNumberGutter(
                        lineCount: _lines.length,
                        lineHeight: _lineHeight,
                        fontSize: _fontSize,
                        gutterWidth: _gutterWidth,
                        activeLine: highlightLine,
                      ),
                      HighlightView(
                        widget.content,
                        language: _resolvedLanguage,
                        theme: _codeTheme,
                        padding: EdgeInsets.zero,
                        textStyle: _codeTextStyle,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LineNumberGutter extends StatelessWidget {
  const _LineNumberGutter({
    required this.lineCount,
    required this.lineHeight,
    required this.fontSize,
    required this.gutterWidth,
    required this.activeLine,
  });

  final int lineCount;
  final double lineHeight;
  final double fontSize;
  final double gutterWidth;
  final int? activeLine;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: gutterWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < lineCount; i++)
            SizedBox(
              height: lineHeight,
              child: Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Text(
                    '${i + 1}',
                    style: AppTypography.mono(
                      size: fontSize,
                      lineHeight: lineHeight,
                      color: activeLine == i ? ObsidianColors.primary : ObsidianColors.outline,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
