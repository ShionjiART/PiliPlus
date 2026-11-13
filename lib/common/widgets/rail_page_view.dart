import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

/// 竖状态栏（iPhone Duo）占用的左右安全区和窗口宽度，由 [NativeSafeArea]
/// 提供。页面会把安全区从 [MediaQuery] 里去掉，这里保留一份给
/// [RailPageViewport] 用
class RailViewportScope extends InheritedWidget {
  const RailViewportScope({
    super.key,
    required this.insets,
    required this.windowWidth,
    required super.child,
  });

  final EdgeInsets insets;
  final double windowWidth;

  static RailViewportScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RailViewportScope>();

  @override
  bool updateShouldNotify(RailViewportScope oldWidget) =>
      insets != oldWidget.insets || windowWidth != oldWidget.windowWidth;
}

/// 让左右滑动的页面延伸到竖状态栏下面：切换时下一页从屏幕边缘滑入、
/// 从竖状态栏下面经过；每一页仍留出竖状态栏的宽度，停下后内容位置不变。
///
/// 只在宽度正好让出竖状态栏（页面占满竖状态栏以外的宽度）时生效，
/// 弹窗、分栏等较窄的区域保持原样
class RailPageViewport extends StatelessWidget {
  const RailPageViewport({
    super.key,
    required this.axis,
    required this.builder,
    this.allowExtension = true,
  });

  final Axis axis;
  final bool allowExtension;
  final Widget Function(double rightInset) builder;

  @override
  Widget build(BuildContext context) {
    final scope = RailViewportScope.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        var right = 0.0;
        if (scope != null &&
            allowExtension &&
            axis == Axis.horizontal &&
            constraints.hasBoundedWidth &&
            constraints.hasBoundedHeight) {
          final inset = scope.insets.right;
          final gap = scope.windowWidth - constraints.maxWidth;
          if (inset > 0 &&
              gap >= inset - 1 &&
              gap <= scope.insets.horizontal + 1) {
            right = inset;
          }
        }
        // 开合、全屏时 right 会在 0 和非 0 之间变化，始终用同一套结构，
        // 页面状态不会丢失
        final width = constraints.maxWidth + right;
        return OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: width,
          maxWidth: width,
          minHeight: constraints.minHeight,
          maxHeight: constraints.maxHeight,
          child: builder(right),
        );
      },
    );
  }
}

/// 见 [RailPageViewport]
class RailPageView extends StatelessWidget {
  const RailPageView({
    super.key,
    this.children = const [],
    this.controller,
    this.physics,
    this.onPageChanged,
    this.horizontalDragGestureRecognizer = HorizontalDragGestureRecognizer.new,
  }) : itemBuilder = null,
       itemCount = null;

  const RailPageView.builder({
    super.key,
    required this.itemBuilder,
    this.itemCount,
    this.controller,
    this.physics,
    this.onPageChanged,
    this.horizontalDragGestureRecognizer = HorizontalDragGestureRecognizer.new,
  }) : children = const [];

  final List<Widget> children;
  final NullableIndexedWidgetBuilder? itemBuilder;
  final int? itemCount;
  final PageController? controller;
  final ScrollPhysics? physics;
  final ValueChanged<int>? onPageChanged;
  final ValueGetter<HorizontalDragGestureRecognizer>
  horizontalDragGestureRecognizer;

  @override
  Widget build(BuildContext context) => RailPageViewport(
    axis: Axis.horizontal,
    allowExtension: (controller?.viewportFraction ?? 1) == 1,
    builder: (right) => PageView.builder(
      controller: controller,
      physics: physics,
      onPageChanged: onPageChanged,
      horizontalDragGestureRecognizer: horizontalDragGestureRecognizer,
      itemCount: itemBuilder == null ? children.length : itemCount,
      itemBuilder: (context, index) {
        final child = itemBuilder == null
            ? children[index]
            : itemBuilder!(context, index);
        return child == null
            ? null
            : Padding(
                padding: EdgeInsets.only(right: right),
                child: child,
              );
      },
    ),
  );
}

/// 见 [RailPageViewport]
class RailTabBarView extends StatelessWidget {
  const RailTabBarView({
    super.key,
    required this.children,
    this.controller,
    this.physics,
    this.hitTestBehavior = HitTestBehavior.opaque,
    this.horizontalDragGestureRecognizer = HorizontalDragGestureRecognizer.new,
  });

  final List<Widget> children;
  final TabController? controller;
  final ScrollPhysics? physics;
  final HitTestBehavior hitTestBehavior;
  final ValueGetter<HorizontalDragGestureRecognizer>
  horizontalDragGestureRecognizer;

  @override
  Widget build(BuildContext context) => RailPageViewport(
    axis: Axis.horizontal,
    builder: (right) => TabBarView(
      controller: controller,
      physics: physics,
      hitTestBehavior: hitTestBehavior,
      horizontalDragGestureRecognizer: horizontalDragGestureRecognizer,
      children: [
        for (final child in children)
          Padding(
            padding: EdgeInsets.only(right: right),
            child: child,
          ),
      ],
    ),
  );
}
