/// Per-session command history with shell-style up/down navigation.
class CommandHistory {
  CommandHistory({this.maxEntries = 100});

  final int maxEntries;
  final List<String> _entries = <String>[];
  int _browseIndex = -1;
  String? _draft;

  /// Most recent commands first (up to [limit]).
  List<String> recent({int limit = 20}) =>
      _entries.reversed.take(limit).toList(growable: false);

  void add(String command) {
    final trimmed = command.trim();
    if (trimmed.isEmpty) return;
    if (_entries.isNotEmpty && _entries.last == trimmed) {
      resetBrowse();
      return;
    }
    _entries.add(trimmed);
    if (_entries.length > maxEntries) {
      _entries.removeAt(0);
    }
    resetBrowse();
  }

  /// Move to an older entry; returns text to show in the input field.
  String? older(String currentText) {
    if (_entries.isEmpty) return null;
    if (_browseIndex == -1) {
      _draft = currentText;
      _browseIndex = _entries.length - 1;
    } else if (_browseIndex > 0) {
      _browseIndex--;
    }
    return _entries[_browseIndex];
  }

  /// Move to a newer entry; returns text to show in the input field.
  String? newer() {
    if (_browseIndex < 0) return null;
    if (_browseIndex >= _entries.length - 1) {
      final restored = _draft ?? '';
      resetBrowse();
      return restored;
    }
    _browseIndex++;
    return _entries[_browseIndex];
  }

  void resetBrowse() {
    _browseIndex = -1;
    _draft = null;
  }
}
