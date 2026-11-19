import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'motion.dart';

/// The liquid glass lens shader (`shaders/lens.frag`), loaded once at
/// startup. It needs Impeller's shader image filters; where they are
/// missing, or the load fails, every surface falls back to frost.
class GlassLens {
  GlassLens._();

  static ui.FragmentProgram? _program;

  static Future<void> load() async {
    if (!ImageFilter.isShaderFilterSupported) return;
    try {
      _program = await ui.FragmentProgram.fromAsset('shaders/lens.frag');
    } catch (_) {
      _program = null;
    }
  }

  static bool get ready => _program != null;
}

/// Breeze's glass, after iOS 26 Liquid Glass.
///
/// Two materials, as on iOS:
/// * The FLOATING layer ([thick]: bars, round buttons, the + button, the
///   toolbar, sheets, toasts) is a lens. Its curved edge bends the content
///   behind it inward, a specular rim catches the light from the top left,
///   and colour is lifted through the frost. Drawn by [GlassLens].
/// * Everything else (cards in a list) is frost: blur, a clear body and a
///   lit hairline. iOS does not refract list rows either, and a lens per
///   card would cost a backdrop pass each while scrolling.
///
/// Glass inside glass is frost: a lens samples the screen, and inside
/// another glass layer the screen it would sample is that layer's.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    required this.radius,
    this.padding = EdgeInsets.zero,
    this.tint,
    this.gradient,
    this.thick = false,
    this.lit = false,
    this.blur,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final Color? tint;

  /// A fill in place of [tint]: e.g., the accent buttons' gradient.
  final Gradient? gradient;
  final bool thick;
  final bool lit;

  /// Blur strength, overriding the default frost.
  final double? blur;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final shape = BorderRadius.circular(radius);

    if (MediaQuery.highContrastOf(context)) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7),
          borderRadius: shape,
          border: Border.all(
            color: dark ? Colors.white70 : Colors.black54,
            width: 1.2,
          ),
        ),
        child: Padding(padding: padding, child: child),
      );
    }

    final nested = _GlassNest.inside(context);
    if (!nested && GlassLens.ready) {
      return _lens(context, dark, shape);
    }
    return _frost(dark, shape);
  }

  /// The floating material: a lens over the screen.
  Widget _lens(BuildContext context, bool dark, BorderRadius shape) {
    // iOS 26: light glass is a pale, clear white; dark glass a smoky
    // clear with the body shaded down. A caller's tint replaces the colour.
    // A filled control (the + button, a selected chip) is TINTED glass,
    // as iOS draws a prominent button: its colour goes into the lens, deep
    // enough to read as solid, so the rim still catches the light over it
    // instead of a flat gradient painted on top hiding it.
    final fill = gradient;
    final Color glass = fill != null && fill.colors.isNotEmpty
        ? Color.lerp(
            Color.lerp(fill.colors.first, fill.colors.last, 0.5)!,
            Colors.black,
            0.12,
          )!.withValues(alpha: 0.9)
        : tint ??
              // The sheets' own colour, a little weaker: one family of
              // glass, the sheet a shade deeper so it sits above the rest.
              // (Blending white with that grey was tried and LIGHTENED it.)
              (dark
                  ? const Color(0xFF3C3F46).withValues(alpha: 0.38)
                  : const Color(0xFFF8F9FB).withValues(alpha: 0.42));
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: shape,
        // Light glass lifts off the page on a faint, even halo, as iOS
        // light glass does: centred, so it never shows as a grey ledge
        // under the card. On dark it reads as banding, so none.
        boxShadow: dark
            ? const []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.035),
                  blurRadius: 22,
                  offset: const Offset(0, 2),
                  blurStyle: BlurStyle.outer,
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: shape,
        child: _Lens(
          radius: radius,
          dark: dark,
          lit: lit,
          floating: thick,
          tint: glass,
          blur: blur ?? 5.5,
          child: _GlassNest(
            child: DecoratedBox(
              // Tinted glass is a shade lighter at the top, where the light
              // falls on it; plain glass needs nothing on top.
              decoration: BoxDecoration(
                gradient: fill == null
                    ? null
                    : LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white.withValues(alpha: 0.09),
                          Colors.white.withValues(alpha: 0.0),
                        ],
                      ),
              ),
              child: _TouchGlow(
                glow: PressGlow.of(context),
                dark: dark,
                // Only this glass glows: anything glass inside it is shielded.
                child: PressGlow(
                  point: null,
                  strength: 0,
                  child: Padding(padding: padding, child: child),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The quiet material: frost, for cards and glass inside glass.
  Widget _frost(bool dark, BorderRadius shape) {
    final fill = dark
        ? (tint ?? const Color(0xFF222634)).withValues(
            alpha: lit ? 0.36 : (thick ? 0.28 : 0.20),
          )
        : (tint ?? Colors.white).withValues(
            alpha: lit ? 0.80 : (thick ? 0.70 : 0.58),
          );

    // Light mode uses BlurStyle.outer so nothing darkens the glass from
    // behind; dark mode has none, so the raster cache never flickers.
    final shadows = dark
        ? const <BoxShadow>[]
        : [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.07),
              blurRadius: thick ? 18 : 12,
              blurStyle: BlurStyle.outer,
            ),
          ];

    final sigma = blur ?? (thick ? 12.0 : 10.0);

    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: shape, boxShadow: shadows),
      child: ClipRRect(
        borderRadius: shape,
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: sigma,
            sigmaY: sigma,
            tileMode: TileMode.clamp,
          ),
          child: CustomPaint(
            foregroundPainter: _FrostRim(
              radius: radius,
              dark: dark,
              lit: lit,
              hasCustomFill: gradient != null,
            ),
            child: _GlassNest(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  color: gradient == null ? fill : null,
                  gradient: gradient,
                  borderRadius: shape,
                ),
                padding: padding,
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Marks a subtree as already inside glass.
class _GlassNest extends InheritedWidget {
  const _GlassNest({required super.child});

  static bool inside(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_GlassNest>() != null;

  @override
  bool updateShouldNotify(_GlassNest old) => false;
}

class _Lens extends SingleChildRenderObjectWidget {
  const _Lens({
    required this.radius,
    required this.dark,
    required this.lit,
    required this.floating,
    required this.tint,
    required this.blur,
    super.child,
  });

  /// A floating control (deeper bevel, stronger bend) or a card in a list.
  final bool floating;

  final double radius;
  final bool dark;
  final bool lit;
  final Color tint;
  final double blur;

  /// Everything that can move the glass without repainting it: the
  /// scrollables it sits in and its screen's transitions. A scroll moves the glass on
  /// screen without repainting it, and the shader must follow in the same
  /// frame or its rim is drawn where the card was a frame ago (a trail).
  static Listenable? _scrolls(BuildContext context) {
    final positions = <Listenable>[];
    var ctx = context;
    while (true) {
      final s = Scrollable.maybeOf(ctx);
      if (s == null) break;
      positions.add(s.position);
      ctx = s.context;
    }
    // A screen sliding in or out (and the one under it, sliding aside)
    // moves its glass without repainting it too.
    final route = ModalRoute.of(context);
    if (route?.animation != null) positions.add(route!.animation!);
    if (route?.secondaryAnimation != null) {
      positions.add(route!.secondaryAnimation!);
    }
    return positions.isEmpty ? null : Listenable.merge(positions);
  }

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderLens()
    ..scrolls = _scrolls(context)
    ..pixelRatio = View.of(context).devicePixelRatio
    ..radius = radius
    ..dark = dark
    ..lit = lit
    ..floating = floating
    ..tint = tint
    ..blur = blur;

  @override
  void updateRenderObject(BuildContext context, _RenderLens r) {
    r
      ..scrolls = _scrolls(context)
      ..pixelRatio = View.of(context).devicePixelRatio
      ..radius = radius
      ..dark = dark
      ..lit = lit
      ..floating = floating
      ..tint = tint
      ..blur = blur;
  }
}

/// Pushes the lens as a backdrop filter: blur first, then the shader
/// bends, lifts and lights the blurred screen inside the clip.
///
/// The shader works in screen pixels, so it is told where the glass is on
/// screen. A surface can move without repainting (a sheet sliding up, a
/// page transition), so after every frame it checks where it is and
/// repaints if it moved.
class _RenderLens extends RenderProxyBox {
  _RenderLens() : _shader = GlassLens._program!.fragmentShader();

  final ui.FragmentShader _shader;
  final LayerHandle<BackdropFilterLayer> _layer =
      LayerHandle<BackdropFilterLayer>();
  Rect? _painted;
  bool _watching = false;

  Listenable? _scrolls;
  set scrolls(Listenable? v) {
    if (identical(v, _scrolls)) return;
    if (attached) _scrolls?.removeListener(markNeedsPaint);
    _scrolls = v;
    if (attached) _scrolls?.addListener(markNeedsPaint);
  }

  double _pixelRatio = 1;
  set pixelRatio(double v) => _set(_pixelRatio != v, () => _pixelRatio = v);
  double _radius = 0;
  set radius(double v) => _set(_radius != v, () => _radius = v);
  bool _dark = false;
  set dark(bool v) => _set(_dark != v, () => _dark = v);
  bool _lit = false;
  set lit(bool v) => _set(_lit != v, () => _lit = v);
  bool _floating = true;
  set floating(bool v) => _set(_floating != v, () => _floating = v);
  Color _tint = Colors.transparent;
  set tint(Color v) => _set(_tint != v, () => _tint = v);
  double _blur = 7;
  set blur(double v) => _set(_blur != v, () => _blur = v);

  void _set(bool changed, VoidCallback apply) {
    if (!changed) return;
    apply();
    markNeedsPaint();
  }

  @override
  bool get alwaysNeedsCompositing => true;

  /// Where [box] is, in physical pixels: global logical coordinates (the
  /// app's scaling included) times the screen's real pixel ratio.
  Rect _physical(RenderBox box) {
    final r = MatrixUtils.transformRect(
      box.getTransformTo(null),
      Offset.zero & box.size,
    );
    return Rect.fromLTWH(
      r.left * _pixelRatio,
      r.top * _pixelRatio,
      r.width * _pixelRatio,
      r.height * _pixelRatio,
    );
  }

  /// The backdrop the shader sees is the nearest offscreen pass: the screen,
  /// or an ancestor that draws into a layer of its own (a fade mask, a
  /// translucent fade, another backdrop). Its coordinates start at that
  /// layer's corner, so the glass is placed relative to it.
  Offset _passOrigin() {
    for (var node = parent; node != null; node = node.parent) {
      final passes =
          node is RenderShaderMask ||
          node is RenderBackdropFilter ||
          (node is RenderOpacity && node.opacity < 1) ||
          (node is RenderAnimatedOpacity && node.opacity.value < 1);
      if (passes && node is RenderBox && node.hasSize) {
        return _physical(node).topLeft;
      }
    }
    return Offset.zero;
  }

  Rect _onScreen() => _physical(this).shift(-_passOrigin());

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _scrolls?.addListener(markNeedsPaint);
    _watching = true;
    _watch();
  }

  @override
  void detach() {
    _watching = false;
    _scrolls?.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void dispose() {
    _layer.layer = null;
    _shader.dispose();
    super.dispose();
  }

  // Runs only when a frame is drawn anyway, so an idle screen costs nothing.
  void _watch() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!_watching || !attached) return;
      if (hasSize && _painted != null && _onScreen() != _painted) {
        markNeedsPaint();
      } else if (_fadedLast != _inFade()) {
        markNeedsPaint();
      }
      _watch();
    });
  }

  bool _fadedLast = false;

  /// Inside a fade (a cross-fade between list layouts, a fading page) the
  /// backdrop is the fade's own empty layer, and glass over it flashes
  /// white. Fading glass is drawn as a plain fill until the fade ends.
  bool _inFade() {
    for (var node = parent; node != null; node = node.parent) {
      if (node is RenderAnimatedOpacity && node.opacity.value < 1) return true;
      if (node is RenderOpacity && node.opacity < 1) return true;
    }
    return false;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (!hasSize || size.isEmpty) {
      super.paint(context, offset);
      return;
    }
    _fadedLast = _inFade();
    if (_fadedLast) {
      _layer.layer = null;
      _painted = null;
      context.canvas.drawRRect(
        RRect.fromRectAndRadius(offset & size, Radius.circular(_radius)),
        Paint()
          ..color = _dark ? const Color(0x1AFFFFFF) : const Color(0xB3FFFFFF),
      );
      super.paint(context, offset);
      return;
    }
    final rect = _onScreen();
    _painted = rect;
    final px = rect.width / size.width;

    // A card is thinner glass than a floating control: a shallower edge
    // that bends less, so a screen of them stays calm.
    final bevel = math.min(_floating ? 12.0 : 9.0, _radius * 0.5) * px;
    final boost = _lit ? 1.35 : 1.0;
    final tintAlpha = (_tint.a + (_lit ? 0.08 : 0.0)).clamp(0.0, 1.0);

    _shader
      ..setFloat(2, rect.left)
      ..setFloat(3, rect.top)
      ..setFloat(4, rect.width)
      ..setFloat(5, rect.height)
      ..setFloat(6, _radius * px)
      ..setFloat(7, bevel)
      ..setFloat(8, _floating ? 0.24 : 0.16)
      ..setFloat(9, _tint.r)
      ..setFloat(10, _tint.g)
      ..setFloat(11, _tint.b)
      ..setFloat(12, tintAlpha)
      ..setFloat(13, _dark ? 0.10 : 0.0)
      ..setFloat(14, _dark ? 1.6 : 1.25)
      ..setFloat(15, (_dark ? 1.1 : 1.0) * boost)
      ..setFloat(16, px)
      ..setFloat(17, _dark ? 1.0 : 0.0);

    final filter = ImageFilter.compose(
      outer: ImageFilter.shader(_shader),
      inner: ImageFilter.blur(
        sigmaX: _blur,
        sigmaY: _blur,
        tileMode: TileMode.clamp,
      ),
    );
    final layer = _layer.layer ??= BackdropFilterLayer();
    layer.filter = filter;
    context.pushLayer(layer, super.paint, offset);
  }
}

/// The frost's rim: a lit hairline, brightest along the top.
class _FrostRim extends CustomPainter {
  const _FrostRim({
    required this.radius,
    required this.dark,
    this.lit = false,
    this.hasCustomFill = false,
  });

  final double radius;
  final bool dark;
  final bool lit;
  final bool hasCustomFill;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final rect = Offset.zero & size;
    final r = math.min(radius, math.min(size.width, size.height) / 2);
    final rr = RRect.fromRectAndRadius(
      rect.deflate(0.4),
      Radius.circular(math.max(0, r - 0.4)),
    );

    final boost = lit ? 1.25 : 1.0;
    double a(double light, double darkA, double custom) =>
        ((dark ? darkA : light) * (hasCustomFill ? custom : 1.0) * boost).clamp(
          0.0,
          1.0,
        );

    final shader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Colors.white.withValues(alpha: a(0.60, 0.22, 0.7)),
        Colors.white.withValues(alpha: a(0.35, 0.12, 0.5)),
        Colors.white.withValues(alpha: a(0.22, 0.08, 0.4)),
      ],
      stops: const [0.0, 0.35, 1.0],
    ).createShader(rect);

    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..shader = shader,
    );
  }

  @override
  bool shouldRepaint(_FrostRim old) =>
      old.radius != radius ||
      old.dark != dark ||
      old.lit != lit ||
      old.hasCustomFill != hasCustomFill;
}

/// The light a finger makes in iOS glass: a soft bright pool where it
/// presses, fading out toward the edges, growing as the glass swells.
class _TouchGlow extends StatelessWidget {
  const _TouchGlow({
    required this.glow,
    required this.dark,
    required this.child,
  });
  final PressGlow? glow;
  final bool dark;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final g = glow;
    if (g == null || g.point == null || g.strength <= 0.001) return child;
    return CustomPaint(
      foregroundPainter: _GlowPainter(g.point!, g.strength, dark),
      child: child,
    );
  }
}

class _GlowPainter extends CustomPainter {
  _GlowPainter(this.at, this.strength, this.dark);
  final Offset at;
  final double strength;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final r = math.max(size.shortestSide * 1.1, 60.0);
    final a = (dark ? 0.16 : 0.32) * strength;
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withValues(alpha: a),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: at, radius: r)),
    );
  }

  @override
  bool shouldRepaint(_GlowPainter old) =>
      old.at != at || old.strength != strength || old.dark != dark;
}
