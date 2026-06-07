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

  static Future<List<String>> listRemoteSessionNames(SshConnection connection) async {
    try {
      await connection.prepareForExec();
      final result = await connection.executeResult(
        '/bin/sh -lc ${_shellQuote("tmux list-sessions -F '#{session_name}' 2>/dev/null")}',
        timeout: const Duration(seconds: 8),
      );
      return result.stdout
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty && isValidSessionName(line))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static String attachOrCreate(String sessionName) =>
      "tmux attach -t ${_shellQuote(sessionName)} 2>/dev/null "
      "|| tmux new-session -s ${_shellQuote(sessionName)}";

  static String attachOnly(String sessionName) => 'tmux attach -t ${_shellQuote(sessionName)}';

  static String createNew(String sessionName) => 'tmux new-session -s ${_shellQuote(sessionName)}';

  static String detach() => 'tmux detach\n';

  static String killSession(String sessionName) => 'tmux kill-session -t ${_shellQuote(sessionName)}\n';

  static String commandForMode({
    required HostTmuxMode mode,
    required String sessionName,
    bool resumeOnly = false,
  }) {
    return switch (mode) {
      HostTmuxMode.off => '',
      HostTmuxMode.createNew => resumeOnly ? attachOnly(sessionName) : createNew(sessionName),
      HostTmuxMode.attachExisting || HostTmuxMode.inherit => resumeOnly
          ? attachOnly(sessionName)
          : attachOrCreate(sessionName),
    };
  }

  static String _shellQuote(String value) => "'${value.replaceAll("'", "'\\''")}'";

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
