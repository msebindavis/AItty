import 'workspace_tab.dart';
import 'workspace_template.dart';

class AittyConfig {
  const AittyConfig({
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
        'name': name,
        'terminals': terminals.map((e) => e.toJson()).toList(),
        'auxTabs': auxTabs.map((e) => e.toJson()).toList(),
      };

  factory AittyConfig.fromJson(Map<String, dynamic> json) => AittyConfig(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'Workspace',
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
