import '../models/host.dart';
import 'ssh_connection.dart';

class TmuxStartup {
  static final _namePattern = RegExp(r'^[a-zA-Z0-9_-]+$');

  static bool isValidSessionName(String name) =>
      name.isNotEmpty && name.length <= 64 && _namePattern.hasMatch(name);

  static String slugify(String input) {
    final slug = input
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return slug.isEmpty ? 'session' : slug.substring(0, slug.length.clamp(0, 64));
  }

  static String suggestName({
    required String hostLabel,
    String? hostDefault,
    int paneIndex = 0,
    Set<String> reserved = const {},
  }) {
    final base = hostDefault?.trim().isNotEmpty == true ? hostDefault!.trim() : slugify(hostLabel);
    final candidates = <String>[
      if (paneIndex <= 0) base else '$base-${paneIndex + 1}',
      base,
      for (var i = 2; i < 100; i++) '$base-$i',
    ];
    for (final candidate in candidates) {
      if (isValidSessionName(candidate) && !reserved.contains(candidate)) {
        return candidate;
      }
    }
    return '$base-${DateTime.now().millisecondsSinceEpoch % 100000}';
  }

  /// Lists remote tmux sessions with each session's working directory.
  ///
  /// `pane_current_path` is a pane format variable and is empty in
  /// `list-sessions`; resolve cwd per session via `display-message` instead.
  static const _listSessionsWithCwdScript = r'''
tmux list-sessions -F '#{session_name}' 2>/dev/null | while IFS= read -r name; do
  [ -z "$name" ] && continue
  cwd=$(tmux display-message -p -t "$name" '#{pane_current_path}' 2>/dev/null)
  [ -z "$cwd" ] && cwd=$(tmux display-message -p -t "$name" '#{session_path}' 2>/dev/null)
  printf '%s|%s\n' "$name" "$cwd"
done
''';

  static Future<List<({String name, String? cwd})>> listRemoteSessions(SshConnection connection) async {
    try {
      await connection.prepareForExec();
      final result = await connection.executeResult(
        '/bin/sh -lc ${_shellQuote(_listSessionsWithCwdScript.trim())}',
        timeout: const Duration(seconds: 12),
      );
      final sessions = <({String name, String? cwd})>[];
      for (final line in result.stdout.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        final parts = trimmed.split('|');
        final name = parts.first.trim();
        if (!isValidSessionName(name)) continue;
        final cwd = parts.length > 1 ? parts.sublist(1).join('|').trim() : null;
        sessions.add((name: name, cwd: cwd != null && cwd.isNotEmpty ? cwd : null));
      }
      return sessions;
    } catch (_) {
      return [];
    }
  }

  static Future<List<String>> listRemoteSessionNames(SshConnection connection) async {
    final sessions = await listRemoteSessions(connection);
    return sessions.map((s) => s.name).toList();
  }

  static String? _cwdFlag(String? cwd) {
    if (cwd == null || cwd.isEmpty || cwd == '~') return null;
    return ' -c ${_shellQuote(cwd)}';
  }

  static String attachOrCreate(String sessionName, {String? cwd}) =>
      "tmux attach -t ${_shellQuote(sessionName)} 2>/dev/null "
      '|| tmux new-session -s ${_shellQuote(sessionName)}${_cwdFlag(cwd) ?? ''}';

  static String attachOnly(String sessionName) => 'tmux attach -t ${_shellQuote(sessionName)}';

  static String createNew(String sessionName, {String? cwd}) =>
      'tmux new-session -s ${_shellQuote(sessionName)}${_cwdFlag(cwd) ?? ''}';

  static String detach() => 'tmux detach\n';

  static String killSession(String sessionName) => 'tmux kill-session -t ${_shellQuote(sessionName)}\n';

  static String commandForMode({
    required HostTmuxMode mode,
    required String sessionName,
    bool resumeOnly = false,
    String? cwd,
  }) {
    return switch (mode) {
      HostTmuxMode.off => '',
      HostTmuxMode.createNew => resumeOnly ? attachOnly(sessionName) : createNew(sessionName, cwd: cwd),
      HostTmuxMode.attachExisting || HostTmuxMode.inherit => resumeOnly
          ? attachOnly(sessionName)
          : attachOrCreate(sessionName, cwd: cwd),
    };
  }

  static String _shellQuote(String value) => "'${value.replaceAll("'", "'\\''")}'";

  static Future<void> runReliableCommand(SshConnection conn, String cmd) async {
    var result = await conn.executeResult(cmd);
    if (result.exitCode == 0) return;
    if (result.exitCode == 1 && result.stderr.contains("can't find session")) return;

    const shells = ['/bin/sh -lc', '/bin/bash -lc', '/bin/zsh -lc'];
    for (final shell in shells) {
      result = await conn.executeResult('$shell ${_shellQuote(cmd)}');
      if (result.exitCode == 0) return;
      if (result.exitCode == 1 && result.stderr.contains("can't find session")) return;
      
      final err = result.stderr.toLowerCase();
      if (result.exitCode != 127 && !err.contains('command not found') && !err.contains('not found')) {
        throw StateError(result.stderr.trim().isNotEmpty ? result.stderr.trim() : 'Unknown tmux error (code ${result.exitCode})');
      }
    }
    throw StateError('tmux command failed: executable not found in PATH');
  }

  static final _tmuxVersionLine = RegExp(r'^tmux\s+\d', caseSensitive: false);

  static bool _looksLikeTmuxPath(String line) =>
      line == 'tmux' || line.endsWith('/tmux');

  static bool _outputIndicatesTmux(String stdout, String stderr) {
    for (final line in '$stdout\n$stderr'.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final lower = trimmed.toLowerCase();
      if (lower.contains('not found') || lower.startsWith('which:') || lower.startsWith('sh:')) {
        continue;
      }
      if (_tmuxVersionLine.hasMatch(trimmed)) return true;
      if (_looksLikeTmuxPath(trimmed)) return true;
    }
    return false;
  }

  static Future<bool> isInstalled(SshConnection connection) async {
    const probeScript = r'''
tmux -V 2>/dev/null ||
/usr/bin/tmux -V 2>/dev/null ||
/usr/local/bin/tmux -V 2>/dev/null ||
command -v tmux 2>/dev/null ||
which tmux 2>/dev/null
''';

    const shells = [
      '/bin/sh -lc',
      '/bin/bash -lc',
      '/bin/sh -c',
    ];

    try {
      await connection.prepareForExec();

      for (final shell in shells) {
        final result = await connection.executeResult(
          '$shell ${_shellQuote(probeScript.trim())}',
          timeout: const Duration(seconds: 8),
        );
        if (_outputIndicatesTmux(result.stdout, result.stderr)) return true;
        if (result.exitCode == 0 && result.stdout.trim().isNotEmpty) return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}
