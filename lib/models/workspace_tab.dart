enum WorkspaceTabType { terminal, files, browser, gitDiff }

class WorkspaceTab {
  const WorkspaceTab({
    required this.id,
    required this.type,
    required this.title,
    this.path,
    this.url,
    this.remotePort = 3000,
  });

  final String id;
  final WorkspaceTabType type;
  final String title;
  final String? path;
  final String? url;
  final int remotePort;

  WorkspaceTab copyWith({
    String? title,
    String? path,
    String? url,
    int? remotePort,
  }) {
    return WorkspaceTab(
      id: id,
      type: type,
      title: title ?? this.title,
      path: path ?? this.path,
      url: url ?? this.url,
      remotePort: remotePort ?? this.remotePort,
    );
  }
}
