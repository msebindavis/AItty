import '../models/git_models.dart';

const _delimiter = '---GITMGR---';

abstract final class GitParsers {
  static GitRepoSnapshot parseSnapshot(String stdout, String repoRoot) {
    final parts = stdout.split(_delimiter);
    final branchLine = parts.isNotEmpty ? parts[0].trim() : '';
    final upstream = parts.length > 1 ? _nullIfEmpty(parts[1].trim()) : null;
    final countsLine = parts.length > 2 ? parts[2].trim() : '';
    final remoteUrl = parts.length > 3 ? _nullIfEmpty(parts[3].trim()) : null;
    final porcelain = parts.length > 4 ? parts[4] : '';

    var branch = branchLine;
    var detached = false;
    if (branch.startsWith('DETACHED:')) {
      detached = true;
      branch = branch.substring('DETACHED:'.length);
    }

    int? ahead;
    int? behind;
    if (countsLine.isNotEmpty) {
      final counts = countsLine.split(RegExp(r'\s+'));
      if (counts.length >= 2) {
        behind = int.tryParse(counts[0]);
        ahead = int.tryParse(counts[1]);
      }
    }

    final staged = <GitFileChange>[];
    final unstaged = <GitFileChange>[];
    final untracked = <GitFileChange>[];
    final conflicted = <GitFileChange>[];

    for (final rawLine in porcelain.split('\n')) {
      final line = rawLine.trimRight();
      if (line.isEmpty) continue;
      final change = _parsePorcelainLine(line);
      if (change == null) continue;
      if (change.conflicted) {
        conflicted.add(change);
      }
      if (change.staged) staged.add(change);
      if (change.unstaged && change.kind != GitChangeKind.untracked) {
        unstaged.add(change);
      }
      if (change.kind == GitChangeKind.untracked) {
        untracked.add(change);
      }
    }

    return GitRepoSnapshot(
      repoRoot: repoRoot,
      branch: branch,
      detached: detached,
      staged: staged,
      unstaged: unstaged,
      untracked: untracked,
      conflicted: conflicted,
      ahead: ahead,
      behind: behind,
      upstream: upstream,
      remoteUrl: remoteUrl,
      branches: const [],
    );
  }

  static List<GitBranchInfo> parseBranches(String stdout, String currentBranch) {
    final branches = <GitBranchInfo>[];
    for (final raw in stdout.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      final current = line.startsWith('* ');
      final name = current ? line.substring(2).trim() : line.trim();
      if (name.isEmpty) continue;
      branches.add(
        GitBranchInfo(
          name: name,
          isCurrent: current || name == currentBranch,
          isRemote: name.startsWith('remotes/'),
        ),
      );
    }
    return branches;
  }

  static List<GitCommitInfo> parseLog(String stdout) {
    final commits = <GitCommitInfo>[];
    for (final line in stdout.split('\n')) {
      if (line.trim().isEmpty) continue;
      final fields = line.split('\x00');
      if (fields.length < 5) continue;
      commits.add(
        GitCommitInfo(
          fullSha: fields[0],
          shortSha: fields[1],
          subject: fields[2],
          author: fields[3],
          relativeDate: fields[4],
        ),
      );
    }
    return commits;
  }

  static List<DiffHunk> parseUnifiedDiff(String diff) {
    if (diff.trim().isEmpty) {
      return const [];
    }

    final hunks = <DiffHunk>[];
    var currentHeader = '';
    var currentLines = <DiffLine>[];

    void flush() {
      if (currentHeader.isNotEmpty || currentLines.isNotEmpty) {
        hunks.add(DiffHunk(header: currentHeader, lines: List.unmodifiable(currentLines)));
      }
      currentHeader = '';
      currentLines = [];
    }

    for (final raw in diff.split('\n')) {
      if (raw.startsWith('@@')) {
        flush();
        currentHeader = raw;
        continue;
      }
      if (raw.startsWith('diff --git') ||
          raw.startsWith('index ') ||
          raw.startsWith('--- ') ||
          raw.startsWith('+++ ') ||
          raw.startsWith('new file') ||
          raw.startsWith('deleted file') ||
          raw.startsWith('similarity index') ||
          raw.startsWith('rename from') ||
          raw.startsWith('rename to')) {
        continue;
      }
      if (raw.startsWith('+')) {
        currentLines.add(DiffLine(type: DiffLineType.add, text: raw.substring(1)));
      } else if (raw.startsWith('-')) {
        currentLines.add(DiffLine(type: DiffLineType.remove, text: raw.substring(1)));
      } else if (raw.startsWith(' ')) {
        currentLines.add(DiffLine(type: DiffLineType.context, text: raw.substring(1)));
      } else if (raw.startsWith(r'\ No newline')) {
        continue;
      } else if (raw.isNotEmpty) {
        currentLines.add(DiffLine(type: DiffLineType.context, text: raw));
      }
    }
    flush();
    return hunks;
  }

  static GitFileChange? _parsePorcelainLine(String line) {
    if (line.startsWith('??')) {
      final path = _parsePath(line.substring(3).trim());
      return GitFileChange(
        path: path,
        kind: GitChangeKind.untracked,
        staged: false,
        unstaged: true,
      );
    }
    if (line.length < 4) return null;

    final indexStatus = line[0];
    final worktreeStatus = line[1];
    var pathPart = line.substring(3).trim();
    String? oldPath;

    final arrow = pathPart.indexOf(' -> ');
    if (arrow >= 0) {
      oldPath = _parsePath(pathPart.substring(0, arrow));
      pathPart = pathPart.substring(arrow + 4);
    }
    final path = _parsePath(pathPart);

    final conflicted = indexStatus == 'U' ||
        worktreeStatus == 'U' ||
        (indexStatus == worktreeStatus && indexStatus == 'A') ||
        (indexStatus == worktreeStatus && indexStatus == 'D');

    final kind = conflicted
        ? GitChangeKind.conflict
        : _kindFromStatus(indexStatus != ' ' ? indexStatus : worktreeStatus);

    final staged = indexStatus != ' ' && indexStatus != '?';
    final unstaged = worktreeStatus != ' ' && worktreeStatus != '?';

    return GitFileChange(
      path: path,
      oldPath: oldPath,
      kind: kind,
      staged: staged,
      unstaged: unstaged,
    );
  }

  static GitChangeKind _kindFromStatus(String status) {
    return switch (status) {
      'M' => GitChangeKind.modified,
      'A' => GitChangeKind.added,
      'D' => GitChangeKind.deleted,
      'R' => GitChangeKind.renamed,
      'C' => GitChangeKind.copied,
      '?' => GitChangeKind.untracked,
      'U' => GitChangeKind.conflict,
      _ => GitChangeKind.unknown,
    };
  }

  static String _parsePath(String raw) {
    if (raw.startsWith('"') && raw.endsWith('"')) {
      return raw.substring(1, raw.length - 1).replaceAll(r'\"', '"').replaceAll(r'\\', r'\');
    }
    return raw;
  }

  static String? _nullIfEmpty(String value) => value.isEmpty ? null : value;
}
