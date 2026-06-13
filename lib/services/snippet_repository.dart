import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class TerminalSnippet {
  const TerminalSnippet({required this.id, required this.name, required this.script});

  final String id;
  final String name;
  final String script;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'script': script};

  factory TerminalSnippet.fromJson(Map<String, dynamic> json) => TerminalSnippet(
        id: json['id'] as String,
        name: json['name'] as String,
        script: json['script'] as String,
      );
}

class SnippetRepository {
  static const _key = 'terminal_snippets_v1';
  final _uuid = const Uuid();

  Future<List<TerminalSnippet>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key);
    if (raw == null) return const [];
    return raw
        .map((entry) => TerminalSnippet.fromJson(jsonDecode(entry) as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<void> saveAll(List<TerminalSnippet> snippets) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _key,
      snippets.map((s) => jsonEncode(s.toJson())).toList(growable: false),
    );
  }

  Future<TerminalSnippet> add({required String name, required String script}) async {
    final snippets = await loadAll();
    final snippet = TerminalSnippet(id: _uuid.v4(), name: name, script: script);
    snippets.add(snippet);
    await saveAll(snippets);
    return snippet;
  }

  Future<void> delete(String id) async {
    final snippets = await loadAll();
    snippets.removeWhere((s) => s.id == id);
    await saveAll(snippets);
  }
}

final snippetRepositoryProvider = Provider<SnippetRepository>((ref) => SnippetRepository());
