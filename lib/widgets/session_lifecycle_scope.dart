import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/session_focus_provider.dart';
import '../services/workspace_manager.dart';

class SessionLifecycleScope extends ConsumerStatefulWidget {
  const SessionLifecycleScope({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<SessionLifecycleScope> createState() => _SessionLifecycleScopeState();
}

class _SessionLifecycleScopeState extends ConsumerState<SessionLifecycleScope> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final inForeground = state == AppLifecycleState.resumed;
    ref.read(appInForegroundProvider.notifier).state = inForeground;

    final manager = ref.read(workspaceManagerProvider);
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      manager.saveAllBookmarks();
      return;
    }

    if (!inForeground) return;
    manager.refreshConnectionHealth().then((_) => manager.reconnectAllDisconnected());
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
