import 'dart:convert';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists trusted SSH host key fingerprints (host:port -> base64 fingerprint).
class KnownHostsStore {
  static const _prefsKey = 'known_hosts_v1';

  Future<Map<String, String>> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return {};
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return decoded.map((k, v) => MapEntry(k, v as String));
  }

  Future<void> _save(Map<String, String> hosts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(hosts));
  }

  String keyFor(String host, int port) => '$host:$port';

  Future<bool> isTrusted(String host, int port, String fingerprint) async {
    final hosts = await _load();
    final k = keyFor(host, port);
    final existing = hosts[k];
    if (existing == null) return false;
    return existing == fingerprint;
  }

  Future<void> trust(String host, int port, String fingerprint) async {
    final hosts = await _load();
    hosts[keyFor(host, port)] = fingerprint;
    await _save(hosts);
  }

  Future<String> filePath() async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/known_hosts';
  }
}
