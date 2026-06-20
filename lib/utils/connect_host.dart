import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/host.dart';
import '../services/workspace_manager.dart';
import 'open_workspace.dart';

String connectionErrorMessage(Host host, Object error) {
  final target = '${host.hostname}:${host.port}';
  final detail = error.toString();
  if (detail.contains('No route to host')) {
    return 'Cannot reach $target. Check VPN/firewall, or use the host IPv4 address if the server is IPv6-only.';
  }
  return 'Connection to $target failed: $error';
}

Future<void> connectHostAndOpen(
  BuildContext context,
  WidgetRef ref,
  Host host, {
  bool replace = true,
}) async {
  if (!context.mounted) return;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (ctx) => AlertDialog(
      content: Row(
        children: [
          const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 16),
          Expanded(child: Text('Connecting to ${host.connectionString}...')),
        ],
      ),
    ),
  );

  try {
    final ws = await ref.read(workspaceManagerProvider).connectHostWorkspace(host: host, workspacePath: '/home/${host.username}');
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      openWorkspace(context, ws.id, replace: replace);
    }
  } catch (e) {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(connectionErrorMessage(host, e))),
      );
    }
  }
}
