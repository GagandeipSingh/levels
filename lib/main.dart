import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/model.dart';
import 'screens/home.dart';
import 'screens/onboarding.dart';
import 'ui/glass_surface.dart' show GlassLens;
import 'ui/kit.dart';
import 'ui/scale.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false,
    ),
  );
  final view = WidgetsBinding.instance.platformDispatcher.views.firstOrNull;
  final large =
      view != null &&
      view.physicalSize.shortestSide / view.devicePixelRatio >= 600;
  if (!large) {
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
    ]);
  }
  await GlassLens.load();
  await model.load();
  runApp(const LevelsApp());
}

ThemeData _theme(Brightness b) {
  final dark = b == Brightness.dark;
  return ThemeData(
    brightness: b,
    fontFamily: 'Inter',
    scaffoldBackgroundColor: dark
        ? const Color(0xFF001219)
        : const Color(0xFFF5F3EE),
    colorScheme: ColorScheme.fromSeed(seedColor: Pal.accent, brightness: b),
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    textSelectionTheme: TextSelectionThemeData(cursorColor: Pal.accent),
  );
}

class LevelsApp extends StatelessWidget {
  const LevelsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) => MaterialApp(
        title: 'Levels',
        debugShowCheckedModeBanner: false,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        themeMode: model.theme,
        scrollBehavior: const _Scroll(),
        builder: (context, child) {
          final mq = MediaQuery.of(context);
          return MediaQuery(
            data: mq.copyWith(
              textScaler: mq.textScaler.clamp(
                minScaleFactor: 1,
                maxScaleFactor: 1.3,
              ),
            ),
            child: ScaleToWidth(child: ScreenUtilScope(child: child!)),
          );
        },
        home: const Intro(),
      ),
    );
  }
}

class _Scroll extends MaterialScrollBehavior {
  const _Scroll();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());

  @override
  Widget buildOverscrollIndicator(
    BuildContext c,
    Widget child,
    ScrollableDetails d,
  ) => child;
}

/// The opening: three bars rise on a spring into the mark, the name settles
/// in beside them, and the app fades up. About a second, and none of it with
/// reduce-motion on.
class Intro extends StatefulWidget {
  const Intro({super.key});

  @override
  State<Intro> createState() => _IntroState();
}

class _IntroState extends State<Intro> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1250),
  );
  bool _left = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (MediaQuery.disableAnimationsOf(context)) {
        _next();
      } else {
        _c.forward().whenComplete(_next);
      }
    });
  }

  void _next() {
    if (_left || !mounted) return;
    _left = true;
    final page = model.onboarded ? const Home() : const Onboarding();
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 420),
        pageBuilder: (_, _, _) => page,
        transitionsBuilder: (_, a, _, child) => FadeTransition(
          opacity: CurvedAnimation(parent: a, curve: Curves.easeOutCubic),
          child: ScaleTransition(
            scale: Tween(
              begin: 1.03,
              end: 1.0,
            ).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
            child: child,
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Scaffold(
      backgroundColor: p.bg,
      body: Center(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final t = _c.value;
            final bars = (t / 0.6).clamp(0.0, 1.0);
            final word = Curves.easeOutCubic.transform(
              ((t - 0.38) / 0.4).clamp(0.0, 1.0),
            );
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                BarsMark(size: 64, t: bars, tile: true),
                ClipRect(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    widthFactor: word,
                    child: Opacity(
                      opacity: word,
                      child: Transform.translate(
                        offset: Offset(-10 * (1 - word), 0),
                        child: Padding(
                          padding: const EdgeInsets.only(left: 14),
                          child: Text('Levels', style: display(context, 40)),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
