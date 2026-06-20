class WorkspaceTemplateEntry {
  const WorkspaceTemplateEntry({
    required this.cwd,
    required this.tmuxSessionName,
    this.useTmux = true,
    this.label,
  });

  final String cwd;
  final String tmuxSessionName;
  final bool useTmux;
  final String? label;

  Map<String, dynamic> toJson() => {
        'cwd': cwd,
        'tmuxSessionName': tmuxSessionName,
        'useTmux': useTmux,
        if (label != null) 'label': label,
      };

  factory WorkspaceTemplateEntry.fromJson(Map<String, dynamic> json) => WorkspaceTemplateEntry(
        cwd: json['cwd'] as String,
        tmuxSessionName: json['tmuxSessionName'] as String,
        useTmux: json['useTmux'] as bool? ?? true,
        label: json['label'] as String?,
      );
}

class WorkspaceTemplate {
  const WorkspaceTemplate({
    required this.id,
    required this.name,
    required this.hostId,
    required this.entries,
  });

  final String id;
  final String name;
  final String hostId;
  final List<WorkspaceTemplateEntry> entries;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'hostId': hostId,
        'entries': entries.map((e) => e.toJson()).toList(),
      };

  factory WorkspaceTemplate.fromJson(Map<String, dynamic> json) => WorkspaceTemplate(
        id: json['id'] as String,
        name: json['name'] as String,
        hostId: json['hostId'] as String,
        entries: (json['entries'] as List<dynamic>)
            .map((e) => WorkspaceTemplateEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
