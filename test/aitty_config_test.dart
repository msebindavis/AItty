import 'package:flutter_test/flutter_test.dart';
import 'package:ai_tty/models/aitty_config.dart';
import 'package:ai_tty/models/workspace_template.dart';
import 'package:ai_tty/models/workspace_tab.dart';

void main() {
  group('AittyConfig Serialization & Deserialization Tests', () {
    test('Deserializes new flat format correctly', () {
      final newJson = {
        "id": "uuid-2",
        "name": "New Workspace",
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
      };

      final config = AittyConfig.fromJson(newJson);
      expect(config.name, "New Workspace");
      expect(config.id, "uuid-2");
      expect(config.terminals.first.useTmux, false);
      expect(config.terminals.first.tmuxSessionName, "shell-abc");
    });

    test('Serializes to new flat format correctly', () {
      final config = AittyConfig(
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

      final jsonMap = config.toJson();

      expect(jsonMap["id"], "uuid-3");
      expect(jsonMap["name"], "Serialized Workspace");
      expect(jsonMap["terminals"].first["useTmux"], true);
    });
  });
}
