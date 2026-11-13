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
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

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

  static Future<void> init() async {
    if (!Platform.isIOS) return;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'select':
          _onSelect?.call(call.arguments as int);
        case 'safeArea':
          _setSafeArea(call.arguments);
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

  /// 状态栏在竖状态栏中时（iPhone Duo）隐藏状态栏，让页面铺满竖状态栏的位置。
  /// 状态栏在顶部时不生效。
  ///
  /// 每次都发给原生层，不按上次的值去重：原生层可能漏掉或重置过状态，重发能让
  /// 两边重新一致。原生层回复当前是否已隐藏，用它校正 [verticalBarHidden]，
  /// 以防错过某次 `verticalBarHidden` 通知
  static void setHidesVerticalBar(bool hides) {
    if (!Platform.isIOS) return;
    _channel
        .invokeMethod<bool>('setHidesVerticalBar', hides)
        .then(
          (hidden) {
            if (hidden != null) verticalBarHidden.value = hidden;
          },
          onError: (_) {
            // 没有原生标签栏容器（iOS 26 以下）
          },
        );
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
    onCanGoBackChanged: (value) => _canGoBack = value,
    onTopRouteChanged: _pageActions.setTopPage,
  );

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
            insets: insets.right >= 72
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
