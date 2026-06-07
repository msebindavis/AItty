import 'package:flutter/material.dart';

import '../utils/interaction_logger.dart';

/// Logs route pushes/replaces/pops alongside go_router location updates.
class InteractionRouteObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _log('push', route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _log('pop', route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    if (newRoute != null) _log('replace', newRoute);
  }

  void _log(String action, Route<dynamic> route) {
    final name = route.settings.name;
    final detail = name ?? route.settings.toString();
    InteractionLogger.logNavigation(action, detail: detail);
  }
}
