import 'package:flutter/widgets.dart';
import 'package:PiliPlus/main.dart';
import 'package:PiliPlus/common/widgets/view_safe_area.dart';
import 'package:get/get.dart';

extension GetExt on GetInterface {
  /// Direct routes need the same side-inset protection as named routes.
  /// Preserve the original route name so duplicate prevention stays unchanged.
  Future<T?>? toSafe<T>(
    dynamic page, {
    int? id,
    String? routeName,
    dynamic arguments,
    Bindings? binding,
    bool preventDuplicates = true,
  }) {
    final GetPageBuilder builder;
    if (page is GetPageBuilder) {
      builder = page;
    } else if (page is Widget) {
      builder = () => page;
    } else {
      throw ArgumentError.value(page, 'page', 'Expected a widget or builder');
    }
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
