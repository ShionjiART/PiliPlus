import 'dart:io' show Platform;

import 'package:PiliPlus/utils/ios/native_tab_bar.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:material_ui/material_ui.dart';

/// Keeps the original callback and non-native fallback, while UIKit places the
/// visible comment affordance at the bottom of the system's right rail.
class NativeCommentButton extends StatefulWidget {
  const NativeCommentButton({super.key, required this.child});
  final FloatingActionButton child;
  @override
  State<NativeCommentButton> createState() => _NativeCommentButtonState();
}

class _NativeCommentButtonState extends State<NativeCommentButton> {
  final _anchor = GlobalKey();
  int _owner = 0;
  bool _handedOff = false;

  @override
  void initState() {
    super.initState();
    IOSNativeTabBar.rightRailDevice.addListener(_register);
    IOSNativeTabBar.commentOwnerVisible.addListener(_onAcknowledged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _register();
  }

  @override
  void didUpdateWidget(covariant NativeCommentButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    _register();
  }

  void _register() {
    if (!mounted) return;
    final page = ModalRoute.of(context);
    if (Platform.isIOS &&
        IOSNativeTabBar.rightRailDevice.value &&
        page != null) {
      final owner = IOSNativeTabBar.registerCommentButton(
        source: this,
        route: page,
        isVisible: _isVisible,
        onPressed: () => widget.child.onPressed?.call(),
        label: widget.child.tooltip ?? '发表评论',
      );
      if (_owner != owner) {
        _owner = owner;
        _handedOff = false;
      }
    } else {
      IOSNativeTabBar.unregisterCommentButton(this);
      _owner = 0;
      _handedOff = false;
    }
  }

  void _onAcknowledged() {
    if (!mounted ||
        _owner == 0 ||
        IOSNativeTabBar.commentOwnerVisible.value != _owner) {
      return;
    }
    if (!_handedOff) setState(() => _handedOff = true);
  }

  bool _isVisible() {
    if (!mounted ||
        widget.child.onPressed == null ||
        !(ModalRoute.of(context)?.isCurrent ?? false) ||
        !TickerMode.valuesOf(context).enabled ||
        SmartDialog.checkExist() ||
        MediaQuery.viewInsetsOf(context).bottom > 0) {
      return false;
    }
    final box = _anchor.currentContext?.findRenderObject();
    if (box is! RenderBox ||
        !box.attached ||
        !box.hasSize ||
        box.size.isEmpty) {
      return false;
    }
    return isCommentAnchorVisible(box);
  }

  @override
  void dispose() {
    IOSNativeTabBar.rightRailDevice.removeListener(_register);
    IOSNativeTabBar.commentOwnerVisible.removeListener(_onAcknowledged);
    IOSNativeTabBar.unregisterCommentButton(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: IOSNativeTabBar.commentButtonsAvailable,
    builder: (context, available, child) {
      final native = _handedOff || (available && _owner != 0);
      return SizedBox(
        key: _anchor,
        child: IgnorePointer(
          ignoring: native,
          child: ExcludeSemantics(
            excluding: native,
            child: Opacity(opacity: native ? 0 : 1, child: widget.child),
          ),
        ),
      );
    },
  );
}

/// Follow paint clips as well as transforms: an offscreen PageView tab can still
/// have coordinates inside the window's other pane on an unfolded display.
bool isCommentAnchorVisible(RenderBox box) {
  if (!box.attached || !box.hasSize || box.size.isEmpty) return false;
  final rect = box.localToGlobal(Offset.zero) & box.size;
  var visible = rect;
  RenderObject root = box;
  while (root.parent != null) {
    final child = root;
    root = root.parent!;
    if (root is RenderOffstage && root.offstage) return false;
    if (root is RenderOpacity && root.opacity <= 0.01) return false;
    if (root is RenderAnimatedOpacity && root.opacity.value <= 0.01) {
      return false;
    }
    if (root is RenderSliver && (root.geometry?.paintExtent ?? 0) <= 0) {
      return false;
    }
    final clip = root.describeApproximatePaintClip(child);
    if (clip != null) {
      visible = visible.intersect(
        MatrixUtils.transformRect(root.getTransformTo(null), clip),
      );
    }
  }
  if (root is! RenderView) return false;
  visible = visible.intersect(Offset.zero & root.size);
  return visible.width >= rect.width / 2 && visible.height >= rect.height / 2;
}

/// A compose affordance remains present on its active tab while scrolling.
class CommentFabTransition extends StatelessWidget {
  const CommentFabTransition({
    super.key,
    required this.position,
    required this.child,
  });
  final Animation<Offset> position;
  final Widget child;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: IOSNativeTabBar.rightRailDevice,
    builder: (context, native, child) => SlideTransition(
      position: native ? const AlwaysStoppedAnimation(Offset.zero) : position,
      child: child,
    ),
    child: child,
  );
}
