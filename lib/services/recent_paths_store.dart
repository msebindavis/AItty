import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class RecentPathsStore {
  static const _key = 'path_recents_v1';
  static const _maxPerHost = 8;

  Future<List<String>> getRecentPaths(String hostId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    final map = jsonDecode(raw) as Map<String, dynamic>;
    final list = map[hostId];
    if (list is! List) return [];
    return list.cast<String>();
  }

  Future<void> recordRecentPath(String hostId, String path) async {
    if (path.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    final map = raw != null ? Map<String, dynamic>.from(jsonDecode(raw) as Map) : <String, dynamic>{};
    final recents = (map[hostId] as List<dynamic>?)?.cast<String>().toList() ?? <String>[];
    recents.remove(path);
    recents.insert(0, path);
    if (recents.length > _maxPerHost) {
      recents.removeRange(_maxPerHost, recents.length);
    }
    map[hostId] = recents;
    await prefs.setString(_key, jsonEncode(map));
  }
}
