import 'package:material_ui/material_ui.dart';

/// A scroll-only author/title bar does not reserve an empty toolbar row on Duo.
/// The scaffold overlays it when it becomes visible, keeping scroll geometry stable.
class RailFloatingAppBar extends StatelessWidget {
  const RailFloatingAppBar({
    super.key,
    required this.overlay,
    required this.visible,
    required this.child,
  });
  final bool overlay;
  final bool visible;
  final Widget child;
  @override
  Widget build(BuildContext context) => IgnorePointer(
    ignoring: overlay && !visible,
    child: AnimatedOpacity(
      opacity: !overlay || visible ? 1 : 0,
      duration: const Duration(milliseconds: 200),
      child: child,
    ),
  );
}
