import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/workspace_template.dart';

class WorkspaceRepository {
  static const _key = 'workspace_templates_v1';

  Future<List<WorkspaceTemplate>> list() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    return (jsonDecode(raw) as List<dynamic>)
        .map((e) => WorkspaceTemplate.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> save(WorkspaceTemplate template) async {
    final all = await list();
    all.removeWhere((t) => t.id == template.id);
    all.add(template);
    await _persist(all);
  }

  Future<void> delete(String id) async {
    final all = await list();
    all.removeWhere((t) => t.id == id);
    await _persist(all);
  }

  Future<void> _persist(List<WorkspaceTemplate> templates) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(templates.map((t) => t.toJson()).toList()),
    );
  }
}

final workspaceRepositoryProvider = Provider<WorkspaceRepository>((ref) => WorkspaceRepository());

final workspaceTemplatesProvider = FutureProvider<List<WorkspaceTemplate>>((ref) async {
  return ref.watch(workspaceRepositoryProvider).list();
});
