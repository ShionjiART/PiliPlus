import 'package:flutter/widgets.dart';

/// Observes both named and direct routes, including modal overlays.
class NativeNavigationObserver extends NavigatorObserver {
  NativeNavigationObserver({
    required this.onCanGoBackChanged,
    this.onTopRouteChanged,
  });

  final ValueChanged<bool> onCanGoBackChanged;
  final ValueChanged<Route<dynamic>?>? onTopRouteChanged;
  final List<Route<dynamic>> _routes = [];

  bool get canGoBack => _routes.isNotEmpty && !_routes.last.isFirst;

  /// Global rail tabs return to the root, respecting dialogs and PopScope.
  /// maybePop can report handled without removing a guarded/unsaved page.
  Future<bool> returnToRoot() async {
    while (canGoBack) {
      final route = _routes.last;
      final navigator = route.navigator;
      if (navigator == null || !await navigator.maybePop() || route.isActive) {
        return false;
      }
    }
    return true;
  }

  void _notify() {
    onCanGoBackChanged(canGoBack);
    onTopRouteChanged?.call(_routes.isEmpty ? null : _routes.last);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.add(route);
    _notify();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _notify();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _notify();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (index != -1) {
      if (newRoute == null) {
        _routes.removeAt(index);
      } else {
        _routes[index] = newRoute;
      }
    }
    _notify();
  }
}
