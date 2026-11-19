import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

export 'package:flutter_screenutil/flutter_screenutil.dart' show SizeExtension;

/// Sizing comes from flutter_screenutil, running INSIDE [ScaleToWidth] with
/// the same design size, so `.dp` is ~1 and the tree scale does the work. `.sp` is screenutil's font size; `.dp` is a length scaled
/// the same way (screenutil's `.r`, the smaller of the width/height ratios,
/// so a tall or wide screen never stretches a shape).
extension Dp on num {
  double get dp => r;
}

/// The compass app's whole-tree scaling: the app is laid out for a
/// [designWidth]-dp screen (the Motorola Edge 60 it was tuned on) and the
/// result is scaled to the real one, so every phone shows the same
/// proportions. One scale for everything, the glass library's own controls
/// included, clamped so a small phone does not shrink text past reading and
/// a tablet does not balloon it.
class ScaleToWidth extends StatelessWidget {
  const ScaleToWidth({super.key, required this.child});
  final Widget child;

  static const designWidth = 418.0;
  static const designHeight = 860.0;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    // The SHORTER side, never the width: in landscape the width is the long
    // side, and scaling by it zoomed the whole UI up to the clamp. The short
    // side is the same in both orientations, so rotating keeps sizes.
    //
    // The LONGER side bounds it too: the design is a tall phone (418 x ~860),
    // and a nearly square unfolded foldable zoomed by its short side alone
    // (1.3x) left the controls huge and the content cramped.
    //
    // The cap grows with the screen: up to ~1380 wide (tablets, a desktop
    // window) it stays 1.15x, as 1.3x looked oversized in a tablet window;
    // a 1920-wide desktop gets ~1.6x so it is not left small in the middle
    // of empty space. The same rule as the Dates and Compass apps.
    final f = math
        .min(
          mq.size.shortestSide / designWidth,
          mq.size.longestSide / designHeight,
        )
        .clamp(0.8, (mq.size.longestSide / 1200).clamp(1.15, 2.0));
    if ((f - 1).abs() < 0.01) return child;
    final size = mq.size / f;
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.fill,
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: MediaQuery(
            data: mq.copyWith(
              size: size,
              devicePixelRatio: mq.devicePixelRatio * f,
              padding: mq.padding / f,
              viewPadding: mq.viewPadding / f,
              viewInsets: mq.viewInsets / f,
              systemGestureInsets: mq.systemGestureInsets / f,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Configures screenutil from the INHERITED (already scaled) MediaQuery.
/// ScreenUtilInit reads the physical View, which is the real screen, so
/// under [ScaleToWidth] it scaled `.sp`/`.dp` a second time: 0.86 x 0.86 on
/// a 360 dp phone. Its `useInheritedMediaQuery` flag is ignored in 5.9.3.
///
/// Two rules, each a bug seen on the phone:
/// * Nothing builds until the size is real. The first frame can arrive
///   with an empty size; screenutil then scales by 0, and widgets built in
///   that frame drew at zero size (titles and cards missing until a tab
///   switch rebuilt them).
/// * When the size changes (rotation, split screen), every descendant is
///   rebuilt, because `.sp`/`.dp` are read at build time and nothing else
///   tells a widget they changed.
class ScreenUtilScope extends StatefulWidget {
  const ScreenUtilScope({super.key, required this.child});
  final Widget child;

  @override
  State<ScreenUtilScope> createState() => _ScreenUtilScopeState();
}

class _ScreenUtilScopeState extends State<ScreenUtilScope> {
  Size? _configured;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    if (mq.size.isEmpty) return const SizedBox.shrink();
    if (_configured != mq.size) {
      final first = _configured == null;
      ScreenUtil.configure(
        data: mq,
        // The design's SHORT side is designWidth in either orientation, the
        // same axis ScaleToWidth scales by. splitScreenMode stays OFF: it
        // treats any height under 700 as 700, and a landscape phone's short
        // height (~420) then scaled every .dp/.sp up about 1.7x.
        designSize: mq.size.width > mq.size.height
            ? Size(mq.size.width, ScaleToWidth.designWidth)
            : Size(ScaleToWidth.designWidth, mq.size.height),
        minTextAdapt: true,
        splitScreenMode: false,
      );
      _configured = mq.size;
      if (!first) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          void rebuild(Element e) {
            e.markNeedsBuild();
            e.visitChildren(rebuild);
          }

          (context as Element).visitChildren(rebuild);
        });
      }
    }
    return widget.child;
  }
}
