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

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'title': title,
        if (path != null) 'path': path,
        if (url != null) 'url': url,
        'remotePort': remotePort,
      };

  factory WorkspaceTab.fromJson(Map<String, dynamic> json) => WorkspaceTab(
        id: json['id'] as String,
        type: WorkspaceTabType.values.firstWhere(
          (e) => e.name == json['type'],
          orElse: () => WorkspaceTabType.terminal,
        ),
        title: json['title'] as String,
        path: json['path'] as String?,
        url: json['url'] as String?,
        remotePort: json['remotePort'] as int? ?? 3000,
      );
}
