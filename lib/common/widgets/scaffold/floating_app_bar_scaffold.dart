import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

/// 顶栏可以改为浮在内容上面的 [SimpleScaffold]，用于动态详情、音乐等页面。
///
/// iPhone Duo 上返回键在竖状态栏里时（[floating] 为 true），顶栏浮在内容上面、
/// 平时隐藏，只在 [showFloatingAppBar] 为 true 时淡入；内容只空出状态栏的高度。
/// 否则顶栏照常占住页面顶部。
///
/// [floating] 会在开合时变化。两种状态下组件树的结构完全相同，只改数值和
/// 是否显示，内容（滚动列表等）不会被卸载重建，滚动位置也就不会丢：
/// - 普通顶栏一直在 [SimpleScaffold] 的顶栏位置，浮动时用 [Offstage] 隐藏，
///   高度为 0、不绘制、不响应点击；
/// - 浮动顶栏一直在 [Stack] 里，不浮动时用 [Offstage] 隐藏；
/// - 内容一直包在同一层 [Padding] 里，只改顶部内边距的数值。
class FloatingAppBarScaffold extends StatelessWidget {
  const FloatingAppBarScaffold({
    super.key,
    required this.floating,
    required this.showFloatingAppBar,
    required this.appBarBuilder,
    required this.body,
    this.fab,
  });

  /// 顶栏是否浮在内容上面
  final bool floating;

  /// 浮动时顶栏是否显示
  final RxBool showFloatingAppBar;

  /// 普通顶栏和浮动顶栏各用一份，所以传构造函数而不是组件
  final PreferredSizeWidget Function() appBarBuilder;

  final Widget body;
  final Widget? fab;

  @override
  Widget build(BuildContext context) {
    return SimpleScaffold(
      appBar: Offstage(offstage: floating, child: appBarBuilder()),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Padding(
            padding: EdgeInsets.only(
              top: floating ? MediaQuery.paddingOf(context).top : 0,
            ),
            child: body,
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Offstage(
              offstage: !floating,
              child: Obx(() {
                final show = showFloatingAppBar.value;
                return IgnorePointer(
                  ignoring: !show,
                  child: AnimatedOpacity(
                    opacity: show ? 1 : 0,
                    duration: const Duration(milliseconds: 300),
                    child: appBarBuilder(),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
      fab: fab,
    );
  }
}
