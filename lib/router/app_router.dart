import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/connections/connections_screen.dart';
import '../features/hosts/add_host_screen.dart';
import '../features/settings/key_manager_screen.dart';
import '../features/hosts/hosts_screen.dart';
import '../features/hosts/select_host_screen.dart';
import '../features/hosts/select_path_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/settings/terminal_settings_screen.dart';
import '../features/shell/app_shell.dart';
import '../features/workspace/workspace_screen.dart';
import '../utils/interaction_logger.dart';
import '../utils/interaction_route_observer.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();
final _rootNavigatorKey = rootNavigatorKey;
final _routeObserver = InteractionRouteObserver();

final appRouterProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/hosts',
    observers: [_routeObserver],
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return AppShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/hosts',
                builder: (context, state) => const HostsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/connections',
                builder: (context, state) => const ConnectionsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                builder: (context, state) => const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/hosts/add',
        builder: (context, state) => AddHostScreen(hostId: state.uri.queryParameters['hostId']),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/settings/keys',
        builder: (context, state) => const KeyManagerScreen(),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/settings/terminal',
        builder: (context, state) => const TerminalSettingsScreen(),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/sessions/new/host',
        builder: (context, state) => const SelectHostScreen(),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/sessions/new/path',
        builder: (context, state) => SelectPathScreen(hostId: state.uri.queryParameters['host']),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/workspaces/:workspaceId',
        pageBuilder: (context, state) {
          final id = state.pathParameters['workspaceId']!;
          return NoTransitionPage<void>(
            key: state.pageKey,
            child: WorkspaceScreen(workspaceId: id),
          );
        },
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/workspace/:sessionId',
        redirect: (context, state) {
          final id = state.pathParameters['sessionId'];
          return '/workspaces/$id';
        },
      ),
    ],
  );

  void logRoute() {
    InteractionLogger.logScreen(router.routeInformationProvider.value.uri.toString());
  }

  router.routeInformationProvider.addListener(logRoute);
  logRoute();
  ref.onDispose(() => router.routeInformationProvider.removeListener(logRoute));
  return router;
});
