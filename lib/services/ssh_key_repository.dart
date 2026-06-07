import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/ssh_key.dart';
import 'secure_storage_service.dart';
import 'workspace_manager.dart';

class SshKeyRepository {
  SshKeyRepository(this._secure);

  final SecureStorageService _secure;
  static const _listKey = 'ssh_keys_v1';
  final _uuid = const Uuid();

  Future<List<SshKey>> listKeys() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_listKey) ?? [];
    return raw.map((e) => SshKey.fromJson(jsonDecode(e) as Map<String, dynamic>)).toList();
  }

  Future<SshKey> saveKey({required String name, required String privateKeyPem, String? comment}) async {
    final id = _uuid.v4();
    await _secure.write(_secure.sshPrivateKeyKey(id), privateKeyPem);
    final key = SshKey(id: id, name: name, comment: comment);
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_listKey) ?? [];
    list.add(jsonEncode(key.toJson()));
    await prefs.setStringList(_listKey, list);
    return key;
  }

  Future<String?> getPrivateKeyPem(String keyId) => _secure.read(_secure.sshPrivateKeyKey(keyId));

  Future<void> deleteKey(String keyId) async {
    await _secure.delete(_secure.sshPrivateKeyKey(keyId));
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_listKey) ?? [];
    final updated = <String>[];
    for (final entry in list) {
      final key = SshKey.fromJson(jsonDecode(entry) as Map<String, dynamic>);
      if (key.id != keyId) updated.add(entry);
    }
    await prefs.setStringList(_listKey, updated);
  }
}

final sshKeyRepositoryProvider = Provider<SshKeyRepository>((ref) {
  return SshKeyRepository(ref.watch(secureStorageProvider));
});

