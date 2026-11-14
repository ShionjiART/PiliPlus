import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
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
/// 从竖状态栏下面经过；每一页仍留出竖状态栏的宽度（用 [RailPagePadding]
/// 包住每一页），停下后内容位置不变。
///
/// 只在宽度正好让出竖状态栏（页面占满竖状态栏以外的宽度）时生效，
/// 弹窗、分栏等较窄的区域保持原样。
///
/// 是否延伸要看实际宽度，在布局时才知道；但页面必须在构建阶段就更新，
/// 不能放进 [LayoutBuilder]：否则开合时旧页面会先用旧配置重建，
/// 把带 GlobalKey 的组件从新位置抢回去（例如展开后视频页左下的简介消失）。
/// 所以宽度在 [_RenderRailViewport] 里算，页面右边距由 [RailPagePadding]
/// 在布局时读取
class RailPageViewport extends StatelessWidget {
  const RailPageViewport({
    super.key,
    required this.axis,
    required this.child,
    this.allowExtension = true,
  });

  final Axis axis;
  final bool allowExtension;

  /// 左右滑动的页面，每一页用 [RailPagePadding] 包住
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scope = RailViewportScope.of(context);
    final enabled = scope != null && allowExtension && axis == Axis.horizontal;
    return _RailViewport(
      insets: enabled ? scope.insets : EdgeInsets.zero,
      windowWidth: scope?.windowWidth ?? 0,
      child: child,
    );
  }
}

class _RailViewport extends SingleChildRenderObjectWidget {
  const _RailViewport({
    required this.insets,
    required this.windowWidth,
    super.child,
  });

  final EdgeInsets insets;
  final double windowWidth;

  @override
  _RenderRailViewport createRenderObject(BuildContext context) =>
      _RenderRailViewport(insets, windowWidth);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderRailViewport renderObject,
  ) {
    renderObject
      ..insets = insets
      ..windowWidth = windowWidth;
  }
}

class _RenderRailViewport extends RenderProxyBox {
  _RenderRailViewport(this._insets, this._windowWidth);

  EdgeInsets _insets;
  set insets(EdgeInsets value) {
    if (_insets == value) return;
    _insets = value;
    markNeedsLayout();
  }

  double _windowWidth;
  set windowWidth(double value) {
    if (_windowWidth == value) return;
    _windowWidth = value;
    markNeedsLayout();
  }

  /// 延伸到竖状态栏下面的宽度，每一页的右边距
  double _right = 0;

  final Set<_RenderRailPagePadding> _pages = {};

  double _rightFor(BoxConstraints constraints) {
    final inset = _insets.right;
    if (inset > 0 &&
        constraints.hasBoundedWidth &&
        constraints.hasBoundedHeight) {
      final gap = _windowWidth - constraints.maxWidth;
      if (gap >= inset - 1 && gap <= _insets.horizontal + 1) {
        return inset;
      }
    }
    return 0;
  }

  BoxConstraints _childConstraints(BoxConstraints constraints, double right) {
    if (right == 0) return constraints;
    final width = constraints.maxWidth + right;
    return BoxConstraints(
      minWidth: width,
      maxWidth: width,
      minHeight: constraints.minHeight,
      maxHeight: constraints.maxHeight,
    );
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    final right = _rightFor(constraints);
    final childSize =
        child?.getDryLayout(_childConstraints(constraints, right)) ?? Size.zero;
    return constraints.constrain(
      Size(childSize.width - right, childSize.height),
    );
  }

  @override
  void performLayout() {
    final right = _rightFor(constraints);
    if (right != _right) {
      _right = right;
      // 页面宽度可能刚好没变（例如窗口同时变窄），这时页面不会重新布局，
      // 要主动通知它们更新右边距
      if (_pages.isNotEmpty) {
        invokeLayoutCallback<BoxConstraints>((_) {
          for (final page in _pages) {
            page.markNeedsLayout();
          }
        });
      }
    }
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    child.layout(_childConstraints(constraints, right), parentUsesSize: true);
    size = constraints.constrain(
      Size(child.size.width - right, child.size.height),
    );
  }
}

/// 包住 [RailPageViewport] 里的每一页，留出竖状态栏的宽度
class RailPagePadding extends SingleChildRenderObjectWidget {
  const RailPagePadding({super.key, super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderRailPagePadding();
}

class _RenderRailPagePadding extends RenderShiftedBox {
  _RenderRailPagePadding() : super(null);

  _RenderRailViewport? _viewport;

  double get _right => _viewport?._right ?? 0;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    RenderObject? node = parent;
    while (node != null && node is! _RenderRailViewport) {
      node = node.parent;
    }
    _viewport = node as _RenderRailViewport?;
    _viewport?._pages.add(this);
  }

  @override
  void detach() {
    _viewport?._pages.remove(this);
    _viewport = null;
    super.detach();
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      (child?.getMinIntrinsicWidth(height) ?? 0) + _right;

  @override
  double computeMaxIntrinsicWidth(double height) =>
      (child?.getMaxIntrinsicWidth(height) ?? 0) + _right;

  @override
  double computeMinIntrinsicHeight(double width) =>
      child?.getMinIntrinsicHeight(
        (width - _right).clamp(0, double.infinity),
      ) ??
      0;

  @override
  double computeMaxIntrinsicHeight(double width) =>
      child?.getMaxIntrinsicHeight(
        (width - _right).clamp(0, double.infinity),
      ) ??
      0;

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    final right = _right;
    final child = this.child;
    if (child == null) return constraints.constrain(Size(right, 0));
    final childSize = child.getDryLayout(
      constraints.deflate(EdgeInsets.only(right: right)),
    );
    return constraints.constrain(
      Size(childSize.width + right, childSize.height),
    );
  }

  @override
  void performLayout() {
    final right = _right;
    final child = this.child;
    if (child == null) {
      size = constraints.constrain(Size(right, 0));
      return;
    }
    child.layout(
      constraints.deflate(EdgeInsets.only(right: right)),
      parentUsesSize: true,
    );
    (child.parentData! as BoxParentData).offset = Offset.zero;
    size = constraints.constrain(
      Size(child.size.width + right, child.size.height),
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
    child: PageView.builder(
      controller: controller,
      physics: physics,
      onPageChanged: onPageChanged,
      horizontalDragGestureRecognizer: horizontalDragGestureRecognizer,
      itemCount: itemBuilder == null ? children.length : itemCount,
      itemBuilder: (context, index) {
        final child = itemBuilder == null
            ? children[index]
            : itemBuilder!(context, index);
        return child == null ? null : RailPagePadding(child: child);
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
    child: TabBarView(
      controller: controller,
      physics: physics,
      hitTestBehavior: hitTestBehavior,
      horizontalDragGestureRecognizer: horizontalDragGestureRecognizer,
      children: [
        for (final child in children) RailPagePadding(child: child),
      ],
    ),
  );
}
