enum GitChangeKind { modified, added, deleted, renamed, copied, untracked, conflict, unknown }

class GitFileChange {
  const GitFileChange({
    required this.path,
    required this.kind,
    required this.staged,
    required this.unstaged,
    this.oldPath,
  });

  final String path;
  final String? oldPath;
  final GitChangeKind kind;
  final bool staged;
  final bool unstaged;

  bool get conflicted => kind == GitChangeKind.conflict;

  String get statusLabel {
    return switch (kind) {
      GitChangeKind.modified => 'M',
      GitChangeKind.added => 'A',
      GitChangeKind.deleted => 'D',
      GitChangeKind.renamed => 'R',
      GitChangeKind.copied => 'C',
      GitChangeKind.untracked => '?',
      GitChangeKind.conflict => '!',
      GitChangeKind.unknown => '?',
    };
  }
}

class GitBranchInfo {
  const GitBranchInfo({
    required this.name,
    required this.isCurrent,
    required this.isRemote,
  });

  final String name;
  final bool isCurrent;
  final bool isRemote;
}

class GitCommitInfo {
  const GitCommitInfo({
    required this.fullSha,
    required this.shortSha,
    required this.subject,
    required this.author,
    required this.relativeDate,
  });

  final String fullSha;
  final String shortSha;
  final String subject;
  final String author;
  final String relativeDate;
}

class GitRepoSnapshot {
  const GitRepoSnapshot({
    required this.repoRoot,
    required this.branch,
    required this.detached,
    required this.staged,
    required this.unstaged,
    required this.untracked,
    required this.conflicted,
    required this.ahead,
    required this.behind,
    required this.upstream,
    required this.remoteUrl,
    required this.branches,
  });

  final String repoRoot;
  final String branch;
  final bool detached;
  final List<GitFileChange> staged;
  final List<GitFileChange> unstaged;
  final List<GitFileChange> untracked;
  final List<GitFileChange> conflicted;
  final int? ahead;
  final int? behind;
  final String? upstream;
  final String? remoteUrl;
  final List<GitBranchInfo> branches;

  bool get isClean =>
      staged.isEmpty && unstaged.isEmpty && untracked.isEmpty && conflicted.isEmpty;

  bool get hasUpstream => upstream != null && upstream!.isNotEmpty;
}

enum DiffLineType { header, context, add, remove }

class DiffLine {
  const DiffLine({required this.type, required this.text});

  final DiffLineType type;
  final String text;
}

class DiffHunk {
  const DiffHunk({required this.header, required this.lines});

  final String header;
  final List<DiffLine> lines;
}

class GitCommandResult {
  const GitCommandResult({
    required this.success,
    required this.message,
  });

  final bool success;
  final String message;
}

class GitNotARepositoryException implements Exception {
  @override
  String toString() => 'Not a git repository';
}
