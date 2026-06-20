import 'workspace_tab.dart';
import 'workspace_template.dart';

class AittyWorkspaceConfig {
  const AittyWorkspaceConfig({
    required this.id,
    required this.name,
    required this.terminals,
    required this.auxTabs,
  });

  final String id;
  final String name;
  final List<WorkspaceTemplateEntry> terminals;
  final List<WorkspaceTab> auxTabs;

  Map<String, dynamic> toJson() => {
        'id': id,
        'terminals': terminals.map((e) => e.toJson()).toList(),
        'auxTabs': auxTabs.map((e) => e.toJson()).toList(),
      };

  factory AittyWorkspaceConfig.fromJson(String name, Map<String, dynamic> json) => AittyWorkspaceConfig(
        id: json['id'] as String,
        name: name,
        terminals: (json['terminals'] as List<dynamic>?)
                ?.map((e) => WorkspaceTemplateEntry.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        auxTabs: (json['auxTabs'] as List<dynamic>?)
                ?.map((e) => WorkspaceTab.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
      );
}

class AittyConfig {
  const AittyConfig({
    required this.workspaces,
  });

  final List<AittyWorkspaceConfig> workspaces;

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    for (final w in workspaces) {
      map[w.name] = w.toJson();
    }
    return map;
  }

  factory AittyConfig.fromJson(Map<String, dynamic> json) {
    final workspaces = <AittyWorkspaceConfig>[];
    json.forEach((key, value) {
      if (value is Map<String, dynamic>) {
        workspaces.add(AittyWorkspaceConfig.fromJson(key, value));
      }
    });
    return AittyConfig(workspaces: workspaces);
  }
}
