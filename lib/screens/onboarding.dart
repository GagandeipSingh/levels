import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/model.dart';
import '../core/native.dart';
import '../ui/glass_chrome.dart';
import '../ui/kit.dart';
import '../ui/motion.dart';
import 'home.dart';

/// Three pages: what it does (shown, not told), what it touches, and the one
/// permission it needs, with the disclosure Play asks for in plain words.
/// Once the switch is on, a fourth: banks refuse to pay while it is on, and
/// how to step out of the way and back, so a blocked payment is never a
/// surprise.
///
/// Each page leads with a picture and puts the words under it. Moving on is
/// one round button whose ring fills as you go, the dial from the icon.
class Onboarding extends StatefulWidget {
  const Onboarding({super.key, this.startAt = 0});
  final int startAt;

  @override
  State<Onboarding> createState() => _OnboardingState();
}

class _OnboardingState extends State<Onboarding> with WidgetsBindingObserver {
  late final PageController _pages = PageController(
    initialPage: widget.startAt,
  );
  late int _page = widget.startAt;

  /// Levels' notification can show. Re-read on every return, since it can
  /// be allowed from Settings.
  bool _notifOk = true;

  Future<void> _readNotif() async {
    final ok = await Native.notifOk();
    if (mounted && ok != _notifOk) setState(() => _notifOk = ok);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _readNotif();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pages.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Every return checks the switch, however it was turned on: from the
    // list we opened, the notification, or Android's own settings.
    if (state == AppLifecycleState.resumed) _readNotif();
    if (state == AppLifecycleState.resumed && _page >= 2) {
      model.refreshStatus().then((_) {
        // On: before Home, the one thing to know about paying.
        if (model.serviceOn && mounted && _page == 2) {
          setState(() {});
          WidgetsBinding.instance.addPostFrameCallback((_) => _go(3));
        }
      });
    }
  }

  void _go(int page) => _pages.animateToPage(
    page,
    duration: motion(context, 420),
    curve: Curves.easeOutCubic,
  );

  void _finish() {
    model.onboarded = true;
    if (model.serviceOn) model.put('payTipSeen', true);
    Navigator.of(context).pushAndRemoveUntil(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 380),
        pageBuilder: (_, _, _) => const Home(),
        transitionsBuilder: (_, a, _, child) =>
            FadeTransition(opacity: a, child: child),
      ),
      (_) => false,
    );
  }

  Future<void> _primary() async {
    if (_page < 2) return _go(_page + 1);
    if (_page == 2) {
      if (model.serviceOn) return _go(3);
      Native.openAccessibility();
      return;
    }
    // The pause lives in Levels' notification, which Android 13+ shows
    // only once notifications are allowed. Asked here, on the tap, after
    // the page has said why.
    if (!_notifOk) {
      final ok = await Native.askNotif();
      if (!mounted) return;
      setState(() => _notifOk = ok);
      if (!ok) return;
    }
    _finish();
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final mq = MediaQuery.of(context);
    // The paying page exists only once the switch is on.
    final pages = model.serviceOn ? 4 : 3;
    final last = _page >= 2;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final overlay = dark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark;
    // Same system bars as every other screen (GlassScaffold): clear bars,
    // nav buttons following the status icons. Without it this screen kept
    // a solid black nav bar on 3-button phones.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false,
        systemNavigationBarIconBrightness: overlay.statusBarIconBrightness,
      ),
      child: Scaffold(
        backgroundColor: p.bg,
        body: Stack(
          children: [
            const Positioned.fill(child: Backdrop()),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: PageView(
                  controller: _pages,
                  onPageChanged: (i) => setState(() => _page = i),
                  children: [
                    const _What(),
                    const _Touches(),
                    const _Permission(),
                    if (model.serviceOn) const _Paying(),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 20,
              bottom: mq.padding.bottom + 20,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Row(
                    children: [
                      // Notifications already allowed: Done is the only way on.
                      if (!(_page == 3 && _notifOk))
                        TextAction(
                          last ? 'Not now' : 'Skip',
                          color: p.sub,
                          onTap: last ? _finish : () => _go(2),
                        ),
                      const Spacer(),
                      _Advance(
                        progress: (_page + 1) / pages,
                        label: _page == 3
                            ? (_notifOk ? 'Done' : 'Allow notifications')
                            : last
                            ? (model.serviceOn ? 'Next' : 'Agree and turn on')
                            : null,
                        onTap: _primary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const NavButtonBacking(),
          ],
        ),
      ),
    );
  }
}

/// The way forward: a round sand button inside a ring that fills a third
/// per page. On the last page it opens out into a labelled pill.
class _Advance extends StatelessWidget {
  const _Advance({required this.progress, required this.onTap, this.label});
  final double progress;
  final String? label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final wide = label != null;
    return Semantics(
      button: true,
      label: label ?? 'Next',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: progress),
          duration: motion(context, 420),
          curve: Curves.easeOutCubic,
          builder: (context, f, child) => CustomPaint(
            painter: wide ? null : _Ring(f, p.fill),
            child: child,
          ),
          child: AnimatedContainer(
            duration: motion(context, 320),
            curve: Curves.easeOutCubic,
            height: 64,
            width: wide ? 230 : 64,
            padding: const EdgeInsets.all(7),
            child: DecoratedBox(
              decoration: ShapeDecoration(
                gradient: Pal.lit,
                shape: StadiumBorder(),
              ),
              child: Center(
                child: AnimatedSwitcher(
                  duration: motion(context, 200),
                  child: wide
                      ? Text(
                          label!,
                          key: ValueKey(label),
                          maxLines: 1,
                          softWrap: false,
                          style: body(
                            context,
                            16,
                            w: FontWeight.w600,
                            color: Pal.onAccent,
                          ),
                        )
                      : Icon(
                          CupertinoIcons.arrow_right,
                          key: ValueKey('arrow'),
                          color: Pal.onAccent,
                          size: 22,
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Ring extends CustomPainter {
  _Ring(this.f, this.track);
  final double f;
  final Color track;

  @override
  void paint(Canvas c, Size s) {
    final rect = Rect.fromCircle(
      center: s.center(Offset.zero),
      radius: s.shortestSide / 2 - 1.5,
    );
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    c.drawArc(rect, 0, math.pi * 2, false, stroke..color = track);
    c.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * f,
      false,
      stroke..color = Pal.accent,
    );
  }

  @override
  bool shouldRepaint(_Ring o) => o.f != f || o.track != track;
}

/// A page: the picture fills the top, the words sit under it.
class _PageBody extends StatelessWidget {
  const _PageBody({
    required this.title,
    required this.text,
    required this.child,
  });
  final String title;
  final String text;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final mq = MediaQuery.of(context);
    final words = [
      Text(title, style: display(context, 32)),
      const SizedBox(height: 10),
      Text(text, style: body(context, 16, color: p.sub)),
    ];
    final picture = Center(
      child: FittedBox(fit: BoxFit.scaleDown, child: child),
    );
    // A wide screen (an open foldable, a tablet, a desktop window) puts the
    // picture beside the words, the way a page spread reads.
    final wide = isWideLayout(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        wide ? 48 : 24,
        mq.padding.top + 28,
        wide ? 48 : 24,
        mq.padding.bottom + 112,
      ),
      child: wide
          ? Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1040),
                child: Row(
                  children: [
                    Expanded(flex: 5, child: picture),
                    const SizedBox(width: 48),
                    Expanded(
                      flex: 4,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: words,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: picture),
                const SizedBox(height: 24),
                ...words,
              ],
            ),
    );
  }
}

// ── Page 1: shown, not told ─────────────────────────────────────────────
class _What extends StatelessWidget {
  const _What();

  @override
  Widget build(BuildContext context) => const _PageBody(
    title: 'A level for every app',
    text:
        'Set it once. When the app opens, the volume moves to its level. '
        'When you leave, yours comes back.',
    child: _Demo(),
  );
}

/// The dial, playing out what Levels does: home at your level, an app at
/// its own, back to yours when you leave.
class _Demo extends StatefulWidget {
  const _Demo();

  @override
  State<_Demo> createState() => _DemoState();
}

class _DemoState extends State<_Demo> {
  // (glyph, caption, level, package, caption if not installed, tint).
  // Each app wears its own matte colour on the dial; home is wheat.
  static List<(IconData, String, int, String?, String?, Color)> get _steps => [
    (
      CupertinoIcons.play_fill,
      'YouTube · its level',
      30,
      'com.google.android.youtube',
      'A video app · its level',
      Color(0xFFC0494E), // matte ruby
    ),
    (
      CupertinoIcons.music_note_2,
      'Spotify · its level',
      80,
      'com.spotify.music',
      'A music app · its level',
      Color(0xFF47AB7C), // matte green
    ),
    (
      CupertinoIcons.house_fill,
      'You leave · yours is back',
      60,
      null,
      null,
      Pal.accent,
    ),
    (
      CupertinoIcons.house_fill,
      'Home · your level',
      60,
      null,
      null,
      Pal.accent,
    ),
  ];
  int _i = 0;
  Timer? _t;

  /// False until the page has settled: the dial holds at 0 so the first
  /// thing the eye catches is the level rising, not a number already there.
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    // Let the page arrive (the intro's fade, then a breath), then rise.
    _t = Timer(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      setState(() => _ready = true);
      _t = Timer(const Duration(milliseconds: 2200), () {
        _step();
        _t = Timer.periodic(const Duration(milliseconds: 1800), (_) => _step());
      });
    });
  }

  void _step() {
    if (mounted) setState(() => _i = (_i + 1) % _steps.length);
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final s = _steps[_i];
    // The real icon when the app is on this phone; otherwise a plain tile,
    // never an imitation of someone's logo.
    final real = s.$4 != null && model.info(s.$4!) != null;
    final caption = s.$4 == null || real ? s.$2 : s.$5!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox.square(
          dimension: 250,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: _ready ? s.$3 / 100 : 0),
            duration: motion(context, 900),
            curve: Curves.easeOutCubic,
            builder: (context, f, _) => TweenAnimationBuilder<Color?>(
              tween: ColorTween(end: s.$6),
              duration: motion(context, 600),
              curve: Curves.easeOutCubic,
              builder: (context, tint, child) => CustomPaint(
                painter: _Arc(f, p.fill, tint ?? Pal.accent, p.bg),
                child: child,
              ),
              child: Center(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: motion(context, 520),
                  curve: Curves.easeOutCubic,
                  builder: (context, k, child) => Opacity(
                    opacity: k,
                    child: Transform.scale(
                      scale: 0.85 + 0.15 * k,
                      child: child,
                    ),
                  ),
                  child: Plate(
                    radius: 70,
                    child: SizedBox.square(
                      dimension: 140,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AnimatedSwitcher(
                            duration: motion(context, 300),
                            child: real
                                ? AppIcon(s.$4!, key: ValueKey(s.$4), size: 46)
                                : Icon(
                                    s.$1,
                                    key: ValueKey(_i),
                                    color: p.ink,
                                    size: 32,
                                  ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${(f * 100).round()}%',
                            style: display(context, 26).copyWith(
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        AnimatedSwitcher(
          duration: motion(context, 300),
          child: Text(
            caption,
            key: ValueKey(caption),
            style: body(context, 15, w: FontWeight.w600, color: p.sub),
          ),
        ),
      ],
    );
  }
}

/// The level arc around the demo dial: 270 degrees, in the app's own matte
/// colour where the level is, with a knob at the end ringed in the
/// background so it reads as a separate part.
class _Arc extends CustomPainter {
  _Arc(this.f, this.track, this.tint, this.bg);
  final double f;
  final Color track;
  final Color tint;
  final Color bg;

  static const _start = 135 * math.pi / 180;
  static const _sweep = 270 * math.pi / 180;

  @override
  void paint(Canvas c, Size s) {
    const th = 16.0;
    final centre = s.center(Offset.zero);
    final r = s.shortestSide / 2 - th;
    final rect = Rect.fromCircle(center: centre, radius: r);
    // Two paints: a paint's colour alpha also scales its shader, so the
    // faint track colour must never be on the paint that draws the level.
    Paint stroke(Color color) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = th
      ..strokeCap = StrokeCap.round
      ..color = color;
    final v = f.clamp(0.0, 1.0);
    c.drawArc(rect, _start, _sweep, false, stroke(track));
    if (v > 0.002) c.drawArc(rect, _start, _sweep * v, false, stroke(tint));
    final a = _start + _sweep * v;
    final at = centre + Offset(math.cos(a), math.sin(a)) * r;
    c.drawCircle(at, th * 0.95, Paint()..color = bg);
    c.drawCircle(at, th * 0.72, Paint()..color = tint);
  }

  @override
  bool shouldRepaint(_Arc o) =>
      o.f != f || o.track != track || o.tint != tint || o.bg != bg;
}

// ── Page 2: what it touches ─────────────────────────────────────────────
class _Touches extends StatelessWidget {
  const _Touches();

  @override
  Widget build(BuildContext context) {
    Widget tile(IconData icon, String name, String note, bool changes) =>
        _Kind(icon: icon, name: name, note: note, changes: changes);
    return _PageBody(
      title: 'Only what you hear',
      text:
          'Levels moves the media volume and nothing else. Calls, alarms '
          'and notifications stay exactly where you put them.',
      child: SizedBox(
        width: 320,
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: tile(
                    CupertinoIcons.play_fill,
                    'Media',
                    'Follows the app',
                    true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: tile(
                    CupertinoIcons.phone_fill,
                    'Ringtone',
                    'Stays',
                    false,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: tile(
                    CupertinoIcons.bell_fill,
                    'Notifications',
                    'Stays',
                    false,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: tile(
                    CupertinoIcons.alarm_fill,
                    'Alarms',
                    'Stays',
                    false,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One kind of sound. The one Levels moves is solid sand; the ones it
/// leaves alone are clear glass.
class _Kind extends StatelessWidget {
  const _Kind({
    required this.icon,
    required this.name,
    required this.note,
    required this.changes,
  });
  final IconData icon;
  final String name;
  final String note;
  final bool changes;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final ink = changes ? Pal.onAccent : p.ink;
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 24, color: changes ? ink : p.sub),
          const SizedBox(height: 26),
          Text(
            name,
            style: body(context, 16, w: FontWeight.w600, color: ink),
          ),
          Text(
            note,
            style: body(
              context,
              13.5,
              color: changes ? ink.withValues(alpha: 0.7) : p.sub,
            ),
          ),
        ],
      ),
    );
    if (!changes) return Plate(radius: 22, child: content);
    return DecoratedBox(
      decoration: ShapeDecoration(gradient: Pal.lit, shape: squircle(22)),
      child: content,
    );
  }
}

// ── Page 3: the permission ──────────────────────────────────────────────
class _Permission extends StatelessWidget {
  const _Permission();

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    Widget line(IconData icon, String text, {bool no = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: no ? p.sub : p.accentText),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: body(context, 15))),
        ],
      ),
    );
    return _PageBody(
      title: 'One switch to turn on',
      text:
          'Levels uses Android’s accessibility service only to know which '
          'app is in front. In the list that opens, find Levels (some phones '
          'keep it under Downloaded apps or Installed apps), tap it, then '
          'turn it on.',
      child: SizedBox(
        width: 330,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // What the user is about to look for in Settings.
            Plate(
              radius: 22,
              padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
              child: Row(
                children: [
                  const BarsMark(size: 40, tile: true),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Levels',
                      style: body(context, 17, w: FontWeight.w600),
                    ),
                  ),
                  IgnorePointer(
                    child: CupertinoSwitch(
                      value: true,
                      activeTrackColor: Pal.accent,
                      onChanged: (_) {},
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Plate(
              radius: 22,
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  line(
                    CupertinoIcons.rectangle_stack,
                    'Sees only the name of the app that opened',
                  ),
                  line(
                    CupertinoIcons.eye_slash,
                    'Never what is on your screen or what you type',
                    no: true,
                  ),
                  line(
                    CupertinoIcons.wifi_slash,
                    'No internet access, so nothing leaves your phone',
                    no: true,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Page 4: paying, once the switch is on ───────────────────────────────
/// Banks and UPI apps refuse to pay while any accessibility switch is on.
/// Said here, at setup, because a blocked payment is a bad moment to learn
/// it, and nobody reads Settings first. The way out is Levels' own
/// notification, drawn here as it will look in the shade, so the user
/// knows it on sight. Go Echoo says the same thing the same way.
class _Paying extends StatelessWidget {
  const _Paying();

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    Widget step(String n, String head, String text) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: ShapeDecoration(
              color: Pal.accent,
              shape: CircleBorder(),
            ),
            child: Text(
              n,
              style: body(context, 14, w: FontWeight.w700, color: Pal.onAccent),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(head, style: body(context, 15.5, w: FontWeight.w600)),
                Text(text, style: body(context, 14, color: p.sub)),
              ],
            ),
          ),
        ],
      ),
    );
    return _PageBody(
      title: 'Before you pay',
      text:
          'Google Pay, PhonePe, Paytm and many banks block payments while '
          'Levels is on. Pause it in one tap from its notification.',
      child: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The notification as it looks in the shade: the app's own
            // background, like the real one.
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              decoration: ShapeDecoration(
                color: p.bg,
                shape: squircle(22),
                shadows: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const BarsMark(size: 22, tile: true),
                      const SizedBox(width: 8),
                      Text('Levels', style: body(context, 12.5, color: p.sub)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Levels is on',
                    style: body(context, 15, w: FontWeight.w600),
                  ),
                  Text(
                    'Every app plays at the volume you set',
                    style: body(context, 13.5, color: p.sub),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Pause for a payment',
                    style: body(
                      context,
                      14,
                      w: FontWeight.w600,
                      color: p.accentText,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Plate(
              radius: 22,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Column(
                children: [
                  step(
                    '1',
                    'Before you pay',
                    'Tap Pause for a payment in the notification, or tap '
                        'the Levels widget, or Paying in the app.',
                  ),
                  step(
                    '2',
                    'After you pay',
                    'Tap the Levels note to turn it back on. Still blocked? '
                        'Restart your phone; the note waits for you.',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            // The widget is the fastest of the three, so it is offered here
            // rather than left for the user to find in the launcher.
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              minimumSize: const Size(44, 44),
              color: p.fill,
              borderRadius: BorderRadius.circular(22),
              onPressed: () async {
                if (!await Native.pinWidget()) await Native.pinPay();
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    CupertinoIcons.add_circled,
                    size: 18,
                    color: p.accentText,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Add the Levels widget',
                    style: body(
                      context,
                      14.5,
                      w: FontWeight.w600,
                      color: p.accentText,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
