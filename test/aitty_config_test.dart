import 'package:flutter_test/flutter_test.dart';
import 'package:ai_tty/models/aitty_config.dart';
import 'package:ai_tty/models/workspace_template.dart';
import 'package:ai_tty/models/workspace_tab.dart';

void main() {
  group('AittyConfig Serialization & Deserialization Tests', () {
    test('Deserializes new dictionary format correctly', () {
      final newJson = {
        "New Workspace": {
          "id": "uuid-2",
          "terminals": [
            {
              "cwd": "/path/to/new",
              "tmuxSessionName": "shell-abc",
              "useTmux": false
            }
          ],
          "auxTabs": [
            {
              "id": "tab-2",
              "type": "files",
              "title": "Files",
              "path": "/path/to/new"
            }
          ]
        }
      };

      final config = AittyConfig.fromJson(newJson);
      expect(config.workspaces, hasLength(1));
      expect(config.workspaces.first.name, "New Workspace");
      expect(config.workspaces.first.id, "uuid-2");
      expect(config.workspaces.first.terminals.first.useTmux, false);
      expect(config.workspaces.first.terminals.first.tmuxSessionName, "shell-abc");
    });

    test('Serializes to new dictionary format correctly', () {
      final ws = AittyWorkspaceConfig(
        id: "uuid-3",
        name: "Serialized Workspace",
        terminals: [
          WorkspaceTemplateEntry(
            cwd: "/path/to/ser",
            tmuxSessionName: "ser-session",
            useTmux: true,
          )
        ],
        auxTabs: [
          WorkspaceTab(
            id: "tab-3",
            type: WorkspaceTabType.files,
            title: "Files",
            path: "/path/to/ser",
          )
        ],
      );

      final config = AittyConfig(workspaces: [ws]);
      final jsonMap = config.toJson();

      expect(jsonMap.containsKey("workspaces"), isFalse);
      expect(jsonMap.containsKey("Serialized Workspace"), isTrue);
      
      final inner = jsonMap["Serialized Workspace"] as Map<String, dynamic>;
      expect(inner["id"], "uuid-3");
      expect(inner.containsKey("name"), isFalse); // Verify name is key, not duplicated inside
      expect(inner["terminals"].first["useTmux"], true);
    });
  });
}
