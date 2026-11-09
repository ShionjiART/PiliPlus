import 'package:PiliPlus/common/widgets/view_safe_area.dart';
import 'package:PiliPlus/main.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

extension GetExt on GetInterface {
  /// [to] that keeps the page clear of the left and right insets, such as
  /// iPhone Duo's vertical status bar, like the named routes in `AppPages`.
  ///
  /// The default route name is the one [to] would use, so duplicate
  /// prevention behaves the same.
  Future<T?>? toSafe<T>(
    dynamic page, {
    int? id,
    String? routeName,
    dynamic arguments,
    Bindings? binding,
    bool preventDuplicates = true,
  }) {
    final GetPageBuilder builder = switch (page) {
      final GetPageBuilder builder => builder,
      final Widget widget => () => widget,
      _ => throw ArgumentError.value(
        page,
        'page',
        'Expected a widget or builder',
      ),
    };
    return to<T>(
      () => SideSafeArea(child: builder()),
      id: id,
      routeName: routeName ?? '/${page.runtimeType}',
      arguments: arguments,
      binding: binding,
      preventDuplicates: preventDuplicates,
    );
  }

  S putOrFind<S>(InstanceBuilderCallback<S> dep, {String? tag}) =>
      GetInstance().putOrFind(dep, tag: tag);

  void updateMyAppTheme() {
    final (light, dark) = MyApp.getAllTheme();
    rootController
      ..theme = light
      ..darkTheme = dark
      ..update();
  }

  Future<T?>? offOrToNamed<T>(
    String page, {
    dynamic arguments,
    int? id,
    bool preventDuplicates = true,
    Map<String, String>? parameters,
    bool off = false,
  }) => (off ? offNamed : toNamed)(
    page,
    arguments: arguments,
    id: id,
    preventDuplicates: preventDuplicates,
    parameters: parameters,
  );
}
