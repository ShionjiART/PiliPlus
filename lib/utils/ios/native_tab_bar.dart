import 'dart:async' show scheduleMicrotask;
import 'dart:io' show Platform;
import 'dart:math' show max;

import 'package:PiliPlus/common/widgets/rail_page_view.dart';
import 'package:PiliPlus/models/common/nav_bar_config.dart';
import 'package:PiliPlus/utils/ios/foldable_helper.dart';
import 'package:PiliPlus/utils/ios/native_navigation_batch.dart';
import 'package:PiliPlus/utils/ios/native_navigation_observer.dart';
import 'package:PiliPlus/utils/ios/native_page_actions.dart';
import 'package:PiliPlus/utils/ios/native_tab_tools.dart';
import 'package:PiliPlus/utils/ios/vertical_bar_owner.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// iOS 26+ iPhone 上用系统液态玻璃标签栏作为主导航（见 ios/Runner/SceneDelegate.swift）。
///
/// 原生层不可用时（系统版本过低、非 iPhone）[attach] 返回 false，
/// 继续由 Flutter 绘制导航。
abstract final class IOSNativeTabBar {
  /// iOS 26 起，iPhone 的主导航由系统标签栏负责（iPhone Duo 上放在竖状态栏
  /// 里），与 SceneDelegate 创建原生标签栏的条件一致。需要至少两个导航项才会
  /// 真正接管，见 [attach]
  static bool get isAvailable =>
      Platform.isIOS &&
      IOSFoldableHelper.isIPhone &&
      IOSFoldableHelper.systemMajorVersion >= 26;

  static const _channel = MethodChannel('piliplus/native_tab_bar');

  static bool _enabled = false;
  static bool get enabled => _enabled;

  static ValueChanged<int>? _onSelect;

  /// 原生容器的安全区。Flutter 视图不是窗口根控制器时拿不到系统安全区，
  /// 由原生层转发；为 null 时使用 Flutter 自己的值
  static final safeArea = ValueNotifier<EdgeInsets?>(null);

  /// iPhone Duo 展开竖屏时状态栏只占顶部右上角，这一行其余的地方可以放
  /// 页面自己的顶栏（首页的头像、搜索和消息）。位置是系统给的：
  /// `UIView.edgeInsets(for: .bar(onEdge: .top, extent:))`，右边让开系统
  /// 保留的状态栏区域。其他时候为 null
  static final topBarRegion = ValueNotifier<TopBarRegion?>(null);

  /// 侧边安全区达到这个宽度（原生 pt）时就是竖状态栏，和 SceneDelegate 的
  /// 判断一致；普通 iPhone 横屏时灵动岛那一侧最多约 62pt
  static const double verticalBarMinInset = 72;

  static Future<void> init() async {
    if (!Platform.isIOS) return;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'select':
          _onSelect?.call(call.arguments as int);
        case 'safeArea':
          _setSafeArea(call.arguments);
        case 'topBarRegion':
          topBarRegion.value = TopBarRegion.fromMap(call.arguments);
        case 'verticalBarHidden':
          verticalBarHidden.value = call.arguments as bool;
        case 'back':
          await onBack?.call();
        case 'backButtonVisible':
          backButtonVisible.value = call.arguments as bool;
        case 'pageAction':
          final args = Map<Object?, Object?>.from(call.arguments as Map);
          await _pageActions.handle(
            owner: args['owner'] as int,
            id: args['id'] as String,
          );
        case 'pageActionsVisible':
          pageActionsVisible.value = call.arguments as bool;
        case 'toolAction':
          await onToolAction?.call(call.arguments as String);
        case 'toolsShown':
          toolsShown.value = call.arguments as bool;
        case 'backAvailable':
          backAvailable.value = call.arguments as bool;
      }
    });
    try {
      _setSafeArea(await _channel.invokeMethod('getSafeArea'));
      topBarRegion.value = TopBarRegion.fromMap(
        await _channel.invokeMethod('getTopBarRegion'),
      );
      // 原生层在 Flutter 准备好之前可能已经发过通知
      backAvailable.value =
          await _channel.invokeMethod<bool>('getBackAvailable') ?? false;
    } on MissingPluginException {
      // 没有原生标签栏容器
    }
  }

  static void _setSafeArea(Object? value) {
    if (value is! Map) return;
    double side(String key) => (value[key] as num?)?.toDouble() ?? 0;
    safeArea.value = EdgeInsets.fromLTRB(
      side('left'),
      side('top'),
      side('right'),
      side('bottom'),
    );
  }

  static Future<bool> attach({
    required List<NavigationBarType> tabs,
    required int selected,
    required ValueChanged<int> onSelect,
  }) async {
    if (!Platform.isIOS || tabs.length < 2) return false;
    _onSelect = onSelect;
    try {
      _enabled =
          await _channel.invokeMethod<bool>('setTabs', {
            'tabs': [
              for (final e in tabs) {'id': e.name, 'title': e.label},
            ],
            'selected': selected,
          }) ??
          false;
    } on MissingPluginException {
      _enabled = false;
    }
    // 接管之前可能已经打开了二级页面（例如从链接启动）
    if (_enabled && _canGoBack) setHidden(true);
    return _enabled;
  }

  static void setSelected(int index) {
    if (_enabled) _channel.invokeMethod('setSelected', index);
  }

  /// [value] 为 null 时隐藏角标，为空字符串时显示红点
  static void setBadge(int index, String? value) {
    if (_enabled) {
      _channel.invokeMethod('setBadge', {'index': index, 'value': value});
    }
  }

  /// 由 [navigationObserver] 调用：根页面之上有页面时隐藏，回到根页面时恢复，
  /// 见 [_onCanGoBackChanged]
  static void setHidden(bool hidden) {
    if (_enabled) _channel.invokeMethod('setHidden', hidden);
  }

  /// 竖状态栏顶部的搜索、消息、头像按钮（iPhone Duo 的一级页面）。原生层只在
  /// 有竖状态栏时显示，其他设备上不显示
  static void setTools(List<NativeTabTool> tools) {
    if (_enabled) {
      _channel
          .invokeMethod('setTools', [for (final e in tools) e.toMap()])
          .catchError((_) {
            // 没有原生导航容器（iOS 27.1 以下或非 iPhone）
          });
    }
  }

  /// 点击 [setTools] 里的按钮，参数为按钮的 id
  static Future<void> Function(String id)? onToolAction;

  /// 竖状态栏里是否有 [setTools] 的按钮（由原生层告知）。为 true 时页面里
  /// 重复的入口（首页顶部的头像）可以去掉
  static final toolsShown = ValueNotifier(false);

  /// 竖状态栏是否已按 [setHidesVerticalBar] 隐藏。隐藏后竖状态栏的安全区仍然
  /// 存在（摄像头在其中），页面内容可以忽略它铺满
  static final verticalBarHidden = ValueNotifier(false);

  /// 底部弹窗的 `useSafeArea`。竖状态栏隐藏时（视频页）弹窗和页面内容一样
  /// 铺满竖状态栏的位置，不再按它的安全区在一侧留出空白
  static bool get sheetUseSafeArea => !verticalBarHidden.value;

  /// 去掉 [child] 看到的左右安全区。
  ///
  /// 弹窗不让开左右安全区时（竖状态栏隐藏），安全区仍留在 MediaQuery 里，
  /// 弹窗里的 [ListTile]、[SafeArea] 等会自己再让开一次，内容整体偏向一侧。
  /// 已经让开时左右安全区本来就是 0，去掉也没有影响
  static Widget removeSideInsets(BuildContext context, Widget child) =>
      MediaQuery.removePadding(
        context: context,
        removeLeft: true,
        removeRight: true,
        child: child,
      );

  /// [showModalBottomSheet]，`useSafeArea` 用 [sheetUseSafeArea]，弹窗内容看到的
  /// 左右安全区和弹窗自己让开的一致（见 [removeSideInsets]）
  static Future<T?> showSheet<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    bool isScrollControlled = false,
    bool enableDrag = true,
    BoxConstraints? constraints,
  }) => showModalBottomSheet<T>(
    context: context,
    useSafeArea: sheetUseSafeArea,
    isScrollControlled: isScrollControlled,
    enableDrag: enableDrag,
    constraints: constraints,
    builder: (context) => removeSideInsets(context, Builder(builder: builder)),
  );

  /// 对话框的安全区，替换 [DialogRoute] 默认的 [SafeArea]（见
  /// `lib/scripts/material/dialog_safe_area.patch`）。
  ///
  /// 竖状态栏隐藏时（视频页）页面铺满竖状态栏的位置，对话框也不再偏向一侧，
  /// 在整个屏幕里水平居中。摄像头在竖状态栏的一端，所以对话框左右两边都至少
  /// 留出竖状态栏的宽度，碰不到摄像头；上下只让开顶部和底部的安全区，高度和
  /// 展开竖屏时一样铺满。横屏时对话框比屏幕窄得多，两边的边距本来就够
  static Widget dialogSafeArea(BuildContext context, Widget dialog) =>
      ValueListenableBuilder<bool>(
        valueListenable: verticalBarHidden,
        builder: (context, hidden, dialog) {
          if (!hidden) return SafeArea(child: dialog!);
          final padding = MediaQuery.paddingOf(context);
          // 对话框自己还会在左右各留 [_dialogSideInset]
          final side = max(padding.left, padding.right) - _dialogSideInset;
          return removeSideInsets(
            context,
            SafeArea(
              minimum: EdgeInsets.symmetric(horizontal: max(0.0, side)),
              child: dialog!,
            ),
          );
        },
        child: dialog,
      );

  /// [Dialog] 默认的左右边距（`insetPadding`）
  static const _dialogSideInset = 40.0;

  /// 状态栏在竖状态栏中时（iPhone Duo）隐藏状态栏，让页面铺满竖状态栏的位置。
  /// 状态栏在顶部时不生效，此时用 [statusBar] 隐藏顶部的状态栏（iPhone Duo
  /// 展开竖屏时的视频页）。
  ///
  /// 每次都发给原生层，不按上次的值去重：原生层可能漏掉或重置过状态，重发能让
  /// 两边重新一致。原生层回复当前是否已隐藏，用它校正 [verticalBarHidden]，
  /// 以防错过某次 `verticalBarHidden` 通知。
  ///
  /// 这是全局状态，以最后一次调用为准。页面不要直接调用，用
  /// [claimVerticalBar] 和 [releaseVerticalBar]
  static void setHidesVerticalBar(bool hides, {bool statusBar = false}) {
    if (!Platform.isIOS) return;
    _channel
        .invokeMethod<bool>('setHidesVerticalBar', {
          'hides': hides,
          'statusBar': statusBar,
        })
        .then(
          (hidden) {
            if (hidden != null) verticalBarHidden.value = hidden;
          },
          onError: (_) {
            // 没有原生标签栏容器（iOS 26 以下）
          },
        );
  }

  static final _verticalBarOwner = VerticalBarOwner(
    onChanged: (hides) =>
        setHidesVerticalBar(hides, statusBar: hides && _ownerHidesStatusBar),
    schedule: (callback) {
      WidgetsBinding.instance.addPostFrameCallback((_) => callback());
      WidgetsBinding.instance.ensureVisualUpdate();
    },
  );

  /// 最后接管竖状态栏的页面是否还要隐藏顶部的状态栏
  static bool _ownerHidesStatusBar = false;

  /// [page] 在最上层、要隐藏竖状态栏时调用（视频页），见 [VerticalBarOwner]。
  /// [statusBar] 同 [setHidesVerticalBar]
  static void claimVerticalBar(Object page, {bool statusBar = false}) {
    _ownerHidesStatusBar = statusBar;
    _verticalBarOwner.claim(page);
  }

  /// [page] 被弹出、被盖住或销毁时调用。只有它仍在隐藏竖状态栏、且这一帧之后
  /// 没有别的页面接着隐藏时，才恢复显示（顶部的状态栏也一起恢复）
  static void releaseVerticalBar(Object page) =>
      _verticalBarOwner.release(page);

  static bool? _mainHidesStatusBar;

  /// 首页顶栏收起时隐藏顶部的状态栏（iPhone Duo 展开竖屏）。和
  /// [setHidesVerticalBar] 的状态分开保存，其他页面打开或返回时不会互相覆盖。
  /// 滚动时每帧都会调用，值没变就不发；打开、返回页面和切换布局时用 [force]
  /// 重发，以防两边不一致
  static void setMainHidesStatusBar(bool hides, {bool force = false}) {
    if (!Platform.isIOS || (!force && hides == _mainHidesStatusBar)) return;
    _mainHidesStatusBar = hides;
    _channel.invokeMethod('setMainHidesStatusBar', hides).ignore();
  }

  // ---------------------------------------------------------------------------
  // 竖状态栏里的页面按钮（iPhone Duo）：二级页面的返回键，以及页面自己注册的按钮。
  // 原生层只在有竖状态栏、且它没被隐藏时显示这些按钮；其他设备上不显示。
  // 有竖状态栏时，页面左上角由 AppBar 自动加的返回键去掉（见 [backAvailable]）。

  /// 点击竖状态栏里的返回键
  static Future<void> Function()? onBack;

  /// 竖状态栏里当前是否显示返回键（由原生层告知）
  static final backButtonVisible = ValueNotifier(false);

  /// 二级页面的返回键是否在竖状态栏里（由原生层告知）：有竖状态栏时为 true，
  /// 开合时变化。只看有没有竖状态栏，不看视频页是否把它隐藏，免得视频页下面
  /// 的页面在进出视频页时跟着变布局；视频页用的是自己的返回键
  static final backAvailable = ValueNotifier(false);

  /// iPhone Duo 展开竖屏：页面的标题栏放进状态栏那一行，和系统的导航栏一样
  /// （见 `lib/scripts/material/app_bar_status_bar_row.patch`）。位置用系统给
  /// 的 [topBarRegion]：标题栏在这一行里垂直居中，左边避开圆角，右边让开
  /// 状态栏。只用于贴着屏幕顶边、顶部安全区还没被用掉的标题栏；其他姿态和
  /// 普通 iPhone 返回 null，标题栏照常放在顶部安全区下面
  static EdgeInsets? statusBarRowPadding(
    BuildContext context,
    double toolbarHeight,
  ) {
    final region = context
        .dependOnInheritedWidgetOfExactType<TopBarRegionScope>()
        ?.notifier
        ?.value;
    if (region == null) return null;
    final size = MediaQuery.sizeOf(context);
    if (size.height <= size.width || size.shortestSide < 600) return null;
    // 顶部安全区已被外层用掉（不在屏幕顶边），或状态栏已隐藏
    if (MediaQuery.paddingOf(context).top < region.height - 0.5) return null;
    return EdgeInsets.only(
      top: region.topFor(toolbarHeight),
      left: region.padding.left,
      right: region.padding.right,
    );
  }

  /// 主标题栏（高 [toolbarHeight]）离屏幕顶边的距离：展开竖屏时它放在状态栏
  /// 那一行里（见 [statusBarRowPadding]），其他时候在顶部安全区 [safeTop]
  /// 下面。自己按「顶部安全区 + 标题栏高度」排版的页面（可折叠头部的高度、
  /// 头部背景里内容的位置）用它代替顶部安全区，和标题栏对齐
  static double appBarTop(
    BuildContext context, {
    double toolbarHeight = 56,
    double? safeTop,
  }) =>
      statusBarRowPadding(context, toolbarHeight)?.top ??
      safeTop ??
      MediaQuery.paddingOf(context).top;

  /// [context] 所在页面左上角的返回键是否由竖状态栏里的返回键代替。弹窗等
  /// 不是页面的路由不算，竖状态栏的返回键不对应它们。
  ///
  /// 在 build 中调用，依赖 [NativeBackScope]，开合时会重建
  static bool hidesPageBackButton(BuildContext context) {
    final available =
        context
            .dependOnInheritedWidgetOfExactType<NativeBackScope>()
            ?.notifier
            ?.value ??
        false;
    return available && ModalRoute.of(context) is PageRoute;
  }

  /// 竖状态栏里当前是否显示页面按钮（由原生层告知）
  static final pageActionsVisible = ValueNotifier(false);

  static bool _canGoBack = false;

  /// 加到根 Navigator 的 navigatorObservers 上，跟踪当前最上层的页面
  static final navigationObserver = NativeNavigationObserver(
    onCanGoBackChanged: _onCanGoBackChanged,
    onTopRouteChanged: _pageActions.setTopPage,
  );

  /// 根页面（主页）之上有任何页面时隐藏系统标签栏，回到根页面时恢复。
  /// 包括不经过 GetX 打开的页面，例如图片查看器（HeroDialogRoute）。
  /// 弹窗、底部弹出框等不是页面，不隐藏，见 [NativeNavigationObserver]
  static void _onCanGoBackChanged(bool value) {
    if (value == _canGoBack) return;
    _canGoBack = value;
    setHidden(value);
  }

  static final _pageActions = NativePageActionRegistry(
    onChanged: (state) =>
        _navigationBatch.submit('page', {...state, 'canGoBack': _canGoBack}),
  );

  /// 注册 [route] 页面在竖状态栏里的按钮，该页面在最上层时显示
  static void setPageActions({
    required Route<dynamic> route,
    required List<NativePageAction> actions,
    required NativePageActionHandler onAction,
  }) => _pageActions.register(page: route, actions: actions, handler: onAction);

  static void removePageActions(Route<dynamic> route) =>
      _pageActions.unregister(route);

  static final _navigationBatch = NativeNavigationBatch(
    schedule: (flush) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => scheduleMicrotask(flush),
      );
      WidgetsBinding.instance.ensureVisualUpdate();
    },
    onChanged: (changes) {
      if (!Platform.isIOS) return;
      _channel.invokeMethod<void>('setNavigationState', changes).catchError(
        (_) {
          // 没有原生导航容器（iOS 27.1 以下或非 iPhone）
        },
      );
    },
  );
}

/// 用原生层转发的安全区覆盖 [MediaQuery] 的内边距
class NativeSafeArea extends StatelessWidget {
  const NativeSafeArea({super.key, required this.scale, required this.child});

  final double scale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<EdgeInsets?>(
      valueListenable: IOSNativeTabBar.safeArea,
      builder: (context, insets, child) {
        if (insets == null) return child!;
        final mediaQuery = MediaQuery.of(context);
        final viewPadding = insets / scale;
        return MediaQuery(
          data: mediaQuery.copyWith(
            viewPadding: viewPadding,
            padding: viewPadding.copyWith(
              bottom: max(0, viewPadding.bottom - mediaQuery.viewInsets.bottom),
            ),
          ),
          // 竖状态栏（右侧安全区 ≥72，和 SceneDelegate 的判断一致；普通
          // iPhone 横屏时的刘海不到 72）的位置，供左右滑动的页面延伸到它下面
          child: RailViewportScope(
            insets: insets.right >= IOSNativeTabBar.verticalBarMinInset
                ? EdgeInsets.only(right: viewPadding.right)
                : EdgeInsets.zero,
            windowWidth: mediaQuery.size.width,
            child: child!,
          ),
        );
      },
      child: child,
    );
  }
}

/// 把 [IOSNativeTabBar.backAvailable] 提供给页面，让依赖它的返回键在开合时
/// 重建，见 [IOSNativeTabBar.hidesPageBackButton]
class NativeBackScope extends InheritedNotifier<ValueNotifier<bool>> {
  NativeBackScope({super.key, required super.child})
    : super(notifier: IOSNativeTabBar.backAvailable);
}

/// 让依赖 [IOSNativeTabBar.topBarRegion] 的组件（标题栏）在它变化时重建。
/// 系统给的位置要等原生层布局完成才到，可能晚于开合、旋转后的第一次构建
class TopBarRegionScope
    extends InheritedNotifier<ValueNotifier<TopBarRegion?>> {
  TopBarRegionScope({super.key, required super.child})
    : super(notifier: IOSNativeTabBar.topBarRegion);
}

/// 状态栏那一行里能放顶栏的位置，见 [IOSNativeTabBar.topBarRegion]
@immutable
class TopBarRegion {
  const TopBarRegion({
    required this.height,
    required this.padding,
    required this.extent,
    required this.center,
    required this.minTop,
  });

  /// 状态栏那一行的高度（状态栏显示时的顶部安全区）
  final double height;

  /// 顶栏在这一行里的位置：上边距，以及左右避开圆角和状态栏的距离
  final EdgeInsets padding;

  /// 顶栏的高度
  final double extent;

  /// 系统让顶栏在这一行里垂直居中的中线位置（距屏幕顶边）
  final double center;

  /// 顶栏离屏幕顶边的最小距离
  final double minTop;

  /// 高度为 [barHeight] 的顶栏离屏幕顶边的距离，和系统放顶栏的方式一致：
  /// 以 [center] 居中，但不小于 [minTop]
  double topFor(double barHeight) => max(minTop, center - barHeight / 2);

  /// 原生层的值是原生 pt，按界面缩放换算成 Flutter 的逻辑像素，和
  /// [NativeSafeArea] 一样
  static TopBarRegion? fromMap(Object? value) {
    if (value is! Map) return null;
    final scale = Pref.uiScale;
    double get(String key) => ((value[key] as num?)?.toDouble() ?? 0) / scale;
    return TopBarRegion(
      height: get('height'),
      padding: EdgeInsets.only(
        top: get('top'),
        left: get('left'),
        right: get('right'),
      ),
      extent: get('extent'),
      center: get('center'),
      minTop: get('minTop'),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TopBarRegion &&
      other.height == height &&
      other.padding == padding &&
      other.extent == extent &&
      other.center == center &&
      other.minTop == minTop;

  @override
  int get hashCode => Object.hash(height, padding, extent, center, minTop);
}
