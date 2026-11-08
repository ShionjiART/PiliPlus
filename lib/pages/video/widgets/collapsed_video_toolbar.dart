import 'package:PiliPlus/pages/video/widgets/video_detail_body_insets.dart';
import 'package:material_ui/material_ui.dart';

/// The video canvas can reach behind the rail, but the collapsed toolbar's
/// interactive controls must stay inside the same safe bounds as the details.
class CollapsedVideoToolbar extends StatelessWidget {
  const CollapsedVideoToolbar({
    super.key,
    required this.leading,
    required this.title,
    required this.trailing,
    required this.fullScreen,
  });

  final Widget leading;
  final Widget title;
  final Widget trailing;
  final bool fullScreen;

  @override
  Widget build(BuildContext context) => VideoDetailBodyInsets(
    extendRight: false,
    fullScreen: fullScreen,
    child: SizedBox(
      height: kToolbarHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Align(alignment: Alignment.centerLeft, child: leading),
          Center(child: title),
          Align(alignment: Alignment.centerRight, child: trailing),
        ],
      ),
    ),
  );
}
