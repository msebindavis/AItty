import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/host.dart';
import 'secure_storage_service.dart';

class HostRepository {
  HostRepository(this._secure);

  final SecureStorageService _secure;
  static const _hostsKey = 'hosts_v1';
  static const _recentsKey = 'host_recents_v1';
  final _uuid = const Uuid();

  Future<List<Host>> getAllHosts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_hostsKey) ?? [];
    final recents = await _recentIds();
    return raw.map((e) {
      final host = Host.fromJson(jsonDecode(e) as Map<String, dynamic>);
      return host.copyWith(isRecent: recents.contains(host.id));
    }).toList();
  }

  Future<Host?> getHost(String id) async {
    final hosts = await getAllHosts();
    try {
      return hosts.firstWhere((h) => h.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<Host> saveHost({
    String? id,
    required String label,
    required String hostname,
    required String username,
    required HostGroup group,
    int port = 22,
    required HostAuthMethod authMethod,
    String? sshKeyId,
    String? password,
    String? privateKeyPem,
    HostTmuxMode tmuxMode = HostTmuxMode.inherit,
    String? tmuxSessionName,
    String? startupSnippet,
    int? keepAliveIntervalSeconds,
  }) async {
    final hostId = id ?? _uuid.v4();
    if (password != null && password.isNotEmpty) {
      await _secure.write(_secure.hostPasswordKey(hostId), password);
    }
    if (privateKeyPem != null && privateKeyPem.isNotEmpty) {
      await _secure.write(_secure.hostPasswordKey(hostId), privateKeyPem);
    }
    Host? existing;
    if (id != null) {
      existing = await getHost(hostId);
    }
    final host = Host(
      id: hostId,
      label: label,
      hostname: hostname,
      username: username,
      group: group,
      port: port,
      authMethod: authMethod,
      sshKeyId: sshKeyId,
      tmuxMode: tmuxMode,
      tmuxSessionName: tmuxSessionName ?? existing?.tmuxSessionName,
      startupSnippet: startupSnippet ?? existing?.startupSnippet,
      keepAliveIntervalSeconds: keepAliveIntervalSeconds ?? existing?.keepAliveIntervalSeconds,
    );
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_hostsKey) ?? [];
    final encoded = jsonEncode(host.toJson());
    final index = list.indexWhere((e) {
      final m = jsonDecode(e) as Map<String, dynamic>;
      return m['id'] == hostId;
    });
    if (index >= 0) {
      list[index] = encoded;
    } else {
      list.add(encoded);
    }
    await prefs.setStringList(_hostsKey, list);
    return host;
  }

  Future<String?> getHostPassword(Host host) async {
    if (host.authMethod != HostAuthMethod.password) return null;
    return _secure.read(_secure.hostPasswordKey(host.id));
  }

  Future<String?> getEmbeddedPrivateKey(Host host) async {
    if (host.authMethod != HostAuthMethod.keyPair || host.sshKeyId != null) return null;
    return _secure.read(_secure.hostPasswordKey(host.id));
  }

  Future<void> deleteHost(String id) async {
    await _secure.delete(_secure.hostPasswordKey(id));
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_hostsKey) ?? [];
    final updated = list.where((e) {
      final m = jsonDecode(e) as Map<String, dynamic>;
      return m['id'] != id;
    }).toList();
    await prefs.setStringList(_hostsKey, updated);
    await _removeRecent(id);
  }

  Future<void> recordRecent(String hostId) async {
    final prefs = await SharedPreferences.getInstance();
    final recents = prefs.getStringList(_recentsKey) ?? [];
    recents.remove(hostId);
    recents.insert(0, hostId);
    if (recents.length > 8) recents.removeRange(8, recents.length);
    await prefs.setStringList(_recentsKey, recents);
  }

  Future<List<String>> _recentIds() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_recentsKey) ?? [];
  }

  Future<void> _removeRecent(String hostId) async {
    final prefs = await SharedPreferences.getInstance();
    final recents = prefs.getStringList(_recentsKey) ?? [];
    recents.remove(hostId);
    await prefs.setStringList(_recentsKey, recents);
  }

}

// Forward declaration fix - HostRepository references SshKeyRepository in getHostPrivateKey
// I'll move getHostPrivateKey to ssh_connection instead
