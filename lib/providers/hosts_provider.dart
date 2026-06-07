import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/host.dart';
import '../services/workspace_manager.dart';

class HostsNotifier extends AsyncNotifier<List<Host>> {
  @override
  Future<List<Host>> build() async {
    return ref.read(hostRepositoryProvider).getAllHosts();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = AsyncData(await ref.read(hostRepositoryProvider).getAllHosts());
  }

  Future<Host> save({
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
    final host = await ref.read(hostRepositoryProvider).saveHost(
          id: id,
          label: label,
          hostname: hostname,
          username: username,
          group: group,
          port: port,
          authMethod: authMethod,
          sshKeyId: sshKeyId,
          password: password,
          privateKeyPem: privateKeyPem,
          tmuxMode: tmuxMode,
          tmuxSessionName: tmuxSessionName,
          startupSnippet: startupSnippet,
          keepAliveIntervalSeconds: keepAliveIntervalSeconds,
        );
    await refresh();
    return host;
  }

  Future<void> delete(String id) async {
    await ref.read(hostRepositoryProvider).deleteHost(id);
    await refresh();
  }
}

final hostsProvider = AsyncNotifierProvider<HostsNotifier, List<Host>>(HostsNotifier.new);
