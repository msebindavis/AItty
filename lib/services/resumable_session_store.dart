import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/resumable_session.dart';

class ResumableSessionStore {
  static const _key = 'resumable_sessions_v1';
  static const _maxEntries = 20;

  Future<List<ResumableSession>> list() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    final list = (jsonDecode(raw) as List<dynamic>)
        .map((e) => ResumableSession.fromJson(e as Map<String, dynamic>))
        .toList();
    list.sort((a, b) => b.lastActiveAt.compareTo(a.lastActiveAt));
    return list;
  }

  Future<void> upsert(ResumableSession session) async {
    await merge([session]);
  }

  /// Atomically merges sessions by host + tmux name (updates or inserts each).
  Future<void> merge(Iterable<ResumableSession> sessions) async {
    if (sessions.isEmpty) return;
    final all = await list();
    for (final session in sessions) {
      final index = all.indexWhere(
        (s) => s.hostId == session.hostId && s.tmuxSessionName == session.tmuxSessionName,
      );
      if (index >= 0) {
        all[index] = session;
      } else {
        all.insert(0, session);
      }
    }
    all.sort((a, b) => b.lastActiveAt.compareTo(a.lastActiveAt));
    if (all.length > _maxEntries) {
      all.removeRange(_maxEntries, all.length);
    }
    await _save(all);
  }

  Future<void> remove(String id) async {
    final all = await list();
    all.removeWhere((s) => s.id == id);
    await _save(all);
  }

  Future<void> removeByName(String hostId, String tmuxSessionName) async {
    final all = await list();
    all.removeWhere((s) => s.hostId == hostId && s.tmuxSessionName == tmuxSessionName);
    await _save(all);
  }

  Future<void> _save(List<ResumableSession> sessions) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(sessions.map((s) => s.toJson()).toList()),
    );
  }
}

final resumableSessionStoreProvider = Provider<ResumableSessionStore>((ref) => ResumableSessionStore());

final resumableSessionsProvider = FutureProvider<List<ResumableSession>>((ref) async {
  return ref.watch(resumableSessionStoreProvider).list();
});
