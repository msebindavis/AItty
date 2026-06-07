import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/obsidian_theme.dart';
import 'router/app_router.dart';
import 'utils/interaction_logger.dart';
import 'widgets/session_lifecycle_scope.dart';

class AiTtyApp extends ConsumerWidget {
  const AiTtyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    return InteractionLogScope(
      child: SessionLifecycleScope(
        child: MaterialApp.router(
          title: 'AItty',
          debugShowCheckedModeBanner: false,
          theme: ObsidianTheme.dark(),
          routerConfig: router,
        ),
      ),
    );
  }
}
