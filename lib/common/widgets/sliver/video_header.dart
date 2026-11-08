import 'package:PiliPlus/common/widgets/sliver/sliver_pinned_dynamic_header.dart';
import 'package:PiliPlus/utils/extension/num_ext.dart';
import 'package:flutter/foundation.dart' show clampDouble;
import 'package:material_ui/material_ui.dart';

class VideoHeader extends SliverPinnedDynamicHeader {
  const VideoHeader({
    super.key,
    required super.minExtent,
    required super.maxExtent,
    required this.minVideoHeight,
    required this.onScrollRatioChanged,
    this.onCollapsedChanged,
    required super.child,
  });

  final double minVideoHeight;
  final ValueChanged<double> onScrollRatioChanged;
  final ValueChanged<bool>? onCollapsedChanged;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderVideoHeader(
      minExtent: minExtent,
      maxExtent: maxExtent,
      minVideoHeight: minVideoHeight,
      onScrollRatioChanged: onScrollRatioChanged,
      onCollapsedChanged: onCollapsedChanged,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderVideoHeader renderObject,
  ) {
    super.updateRenderObject(context, renderObject);
    renderObject
      ..minVideoHeight = minVideoHeight
      ..onCollapsedChanged = onCollapsedChanged;
  }
}

class RenderVideoHeader extends RenderSliverPinnedDynamicHeader {
  RenderVideoHeader({
    required super.minExtent,
    required super.maxExtent,
    required this.minVideoHeight,
    required this.onScrollRatioChanged,
    this.onCollapsedChanged,
  });

  double? _scrollRatio;
  bool? _collapsed;
  double minVideoHeight;
  final ValueChanged<double> onScrollRatioChanged;
  ValueChanged<bool>? onCollapsedChanged;

  @override
  void performLayout() {
    super.performLayout();
    // Use the laid-out header height: pause/resume and animation can alter its
    // pinned extent independently of the player's control-bar visibility.
    final collapsed = child!.size.height <= minExtent + 0.5;
    if (_collapsed != collapsed) {
      _collapsed = collapsed;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        onCollapsedChanged?.call(collapsed);
      });
    }
    final scrollOffset = constraints.scrollOffset;
    final offset = scrollOffset - (maxExtent - minVideoHeight);
    final scrollRatio = clampDouble(
      offset.toPrecision(2) / (minVideoHeight - kToolbarHeight).toPrecision(2),
      0.0,
      1.0,
    );
    if (_scrollRatio != scrollRatio) {
      _scrollRatio = scrollRatio;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        onScrollRatioChanged(scrollRatio);
      });
    }
  }
}
