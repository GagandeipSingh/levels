import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/native.dart';
import 'glass_chrome.dart';
import 'glass_surface.dart';
import 'motion.dart';

// ── Palette ──────────────────────────────────────────────────────────────
/// iOS system colours. Depth comes from the surface changing (grouped
/// background, then card, then raised), never from shadows. One accent,
/// never a gradient.
class Pal {
  const Pal._(this.dark);
  final bool dark;

  static Pal of(BuildContext context) =>
      Pal._(Theme.of(context).brightness == Brightness.dark);

  /// systemGroupedBackground.
  Color get bg => dark ? const Color(0xFF001219) : const Color(0xFFF5F3EE);

  /// secondarySystemGroupedBackground: cards and grouped rows.
  Color get card => dark ? const Color(0xFF1C1C1E) : const Color(0xFFFFFFFF);

  /// A control sitting on a card (raised chip, sheet).
  Color get raised => dark ? const Color(0xFF2C2C2E) : const Color(0xFFFFFFFF);
  Color get ink => dark ? const Color(0xFFFFFFFF) : const Color(0xFF000000);
  Color get sub => dark ? const Color(0xFF98989F) : const Color(0xFF8A8A8E);
  Color get faint => dark ? const Color(0xFF5A5A5F) : const Color(0xFFC4C4C7);

  /// The hairline separator.
  Color get line => dark ? const Color(0xFF38383A) : const Color(0xFFC6C6C8);

  /// tertiarySystemFill: tracks, wells, pressed rows.
  Color get fill => dark
      ? const Color(0xFF767680).withValues(alpha: 0.24)
      : const Color(0xFF767680).withValues(alpha: 0.12);
  Color get danger => dark ? const Color(0xFFFF453A) : const Color(0xFFFF3B30);
  Color get good => dark ? const Color(0xFF30D158) : const Color(0xFF34C759);

  /// The chosen accent (Settings, Appearance). Wheat by default.
  static Accent current = Accent.all.first;

  /// The main colour: one flat matte tone for fills, marks and icons.
  static Color get accent => current.fill;

  /// Text and glyphs drawn ON the accent: a deep tone of the same hue,
  /// about 7:1, without the hard edge of black.
  static Color get onAccent => current.on;

  /// The accent as TEXT: a deep tone on light (the fill vanishes on white),
  /// a light tone on dark.
  Color get accentText => dark ? current.textDark : current.textLight;

  /// The accent as a matte surface. Buttons.
  static LinearGradient get lit => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [current.fill, current.fill],
  );

  /// The accent along a level. Slider fills and level read-outs.
  static LinearGradient get level =>
      LinearGradient(colors: [current.fill, current.fill]);
}

/// One accent choice. Every one sits at wheat's level: light, soft and
/// matte (about the same lightness and chroma), so any of them suits the
/// app the way wheat does, and none turns loud or neon.
class Accent {
  const Accent(this.id, this.name, this.fill, this.on, this.textLight, this.textDark);
  final String id;
  final String name;
  final Color fill;
  final Color on;
  final Color textLight;
  final Color textDark;

  static const all = [
    Accent('wheat', 'Wheat', Color(0xFFE3CF9C), Color(0xFF4E3F1E), Color(0xFF6B5A35), Color(0xFFE9D8A6)),
    Accent('sage', 'Sage', Color(0xFFC3D5B0), Color(0xFF34452A), Color(0xFF4F6339), Color(0xFFCFE0BE)),
    Accent('seafoam', 'Seafoam', Color(0xFFA9D9C8), Color(0xFF0E4A3E), Color(0xFF2F6B5C), Color(0xFFB7E2D3)),
    Accent('mist', 'Mist', Color(0xFFB9CDE4), Color(0xFF23384F), Color(0xFF3F5B7A), Color(0xFFC6D7EB)),
    Accent('lilac', 'Lilac', Color(0xFFCFC2E5), Color(0xFF3B2E55), Color(0xFF5B4A7D), Color(0xFFDACFEC)),
    Accent('rose', 'Rose', Color(0xFFE9C1B9), Color(0xFF55302A), Color(0xFF7D4A42), Color(0xFFEFCDC6)),
    Accent('stone', 'Stone', Color(0xFFD8D4CB), Color(0xFF3A3833), Color(0xFF5E5A52), Color(0xFFE0DCD4)),
  ];

  static Accent byId(String? id) =>
      all.firstWhere((a) => a.id == id, orElse: () => all.first);
}

/// The continuous (squircle) corner every rounded surface uses.
ShapeBorder squircle(double r, {BorderSide side = BorderSide.none}) =>
    RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(r),
      side: side,
    );

TextStyle display(
  BuildContext c,
  double size, {
  FontWeight w = FontWeight.w700,
  Color? color,
}) => TextStyle(
  fontFamily: 'Inter',
  fontSize: size,
  fontWeight: w,
  letterSpacing: -0.02 * size,
  height: 1.1,
  color: color ?? Pal.of(c).ink,
);

TextStyle body(
  BuildContext c,
  double size, {
  FontWeight w = FontWeight.w400,
  Color? color,
}) => TextStyle(
  fontSize: size,
  fontWeight: w,
  letterSpacing: size >= 17 ? -0.4 : -0.1,
  height: 1.3,
  color: color ?? Pal.of(c).ink,
);

// ── Background ──────────────────────────────────────────────────────────
/// A quiet field of light behind the glass: a wide wash of the accent from
/// the top, a cooler one low on the other side. Without it glass has
/// nothing to refract and reads as a flat grey card.
class Backdrop extends StatelessWidget {
  const Backdrop({super.key});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(color: p.bg),
      child: CustomPaint(painter: _Field(p.dark), size: Size.infinite),
    );
  }
}

class _Field extends CustomPainter {
  _Field(this.dark);
  final bool dark;

  @override
  void paint(Canvas c, Size s) {
    void wash(Offset at, double r, Color color) {
      c.drawCircle(
        at,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: at, radius: r)),
      );
    }

    // Matte: the field is flat. Kept as a hook, drawn at zero.
    const a = 0.0;
    if (a == 0) return;
    wash(
      Offset(s.width * 0.15, -s.height * 0.05),
      s.longestSide * 0.75,
      const Color(0xFF0A9396).withValues(alpha: a),
    );
    wash(
      Offset(s.width * 1.05, s.height * 0.78),
      s.longestSide * 0.6,
      const Color(0xFFE9D8A6).withValues(alpha: a * 1.6),
    );
  }

  @override
  bool shouldRepaint(_Field o) => o.dark != dark;
}

/// A content surface in liquid glass. [color], when given, tints the glass.
class Plate extends StatelessWidget {
  const Plate({
    super.key,
    this.radius = 22,
    this.padding = EdgeInsets.zero,
    required this.child,
    this.color,
  });
  final double radius;
  final EdgeInsetsGeometry padding;
  final Widget child;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    // Inside a desktop panel a card is a flat cell, not glass on glass.
    if (PanelScope.inPanel(context) && color == null) {
      return DecoratedBox(
        decoration: ShapeDecoration(
          color: Pal.of(context).fill,
          shape: squircle(radius - 2),
        ),
        child: Padding(padding: padding, child: child),
      );
    }
    return GlassSurface(
      radius: radius,
      thick: color != null,
      tint: color?.withValues(alpha: 0.72),
      padding: padding,
      child: child,
    );
  }
}

/// Marks a subtree as sitting in a desktop panel.
class PanelScope extends InheritedWidget {
  const PanelScope({super.key, required super.child});

  static bool inPanel(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PanelScope>() != null;

  @override
  bool updateShouldNotify(PanelScope old) => false;
}

/// A full-height desktop panel: glass, with its own scrolling list.
class Panel extends StatelessWidget {
  const Panel({super.key, required this.children, this.empty});
  final List<Widget> children;

  /// Shown centred in the panel instead of [children].
  final Widget? empty;

  @override
  Widget build(BuildContext context) => GlassSurface(
    radius: 28,
    child: PanelScope(
      child: empty != null
          ? Center(
              child: Padding(padding: const EdgeInsets.all(24), child: empty),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(14, 16, 14, 8),
              children: children,
            ),
    ),
  );
}

// ── Grouped section (iOS inset grouped, in glass) ───────────────────────
class Section extends StatelessWidget {
  const Section({
    super.key,
    this.title,
    this.footer,
    this.trailing,
    required this.children,
  });
  final String? title;
  final String? footer;
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      rows.add(children[i]);
      if (i < children.length - 1) {
        rows.add(
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Container(height: 0.5, color: p.line),
          ),
        );
      }
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
              // One height for every header, with or without an action, so
              // headers in side-by-side panels sit on the same line.
              child: SizedBox(
                height: 30,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title!.toUpperCase(),
                        style: body(
                          context,
                          13,
                          color: p.sub,
                        ).copyWith(letterSpacing: 0.2),
                      ),
                    ),
                    ?trailing,
                  ],
                ),
              ),
            ),
          Plate(child: Column(children: rows)),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Text(footer!, style: body(context, 13, color: p.sub)),
            ),
        ],
      ),
    );
  }
}

/// One row in a [Section].
class Tile extends StatelessWidget {
  const Tile({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.chevron = false,
    this.danger = false,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool chevron;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final row = ConstrainedBox(
      // 48dp: Material's touch floor, which Android users expect.
      constraints: const BoxConstraints(minHeight: 48),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 13)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: body(context, 17, color: danger ? p.danger : p.ink),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, style: body(context, 15, color: p.sub)),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 10), trailing!],
            if (chevron) ...[
              const SizedBox(width: 6),
              Icon(CupertinoIcons.chevron_forward, size: 16, color: p.faint),
            ],
          ],
        ),
      ),
    );
    if (onTap == null) return row;
    return _Pressable(onTap: onTap!, child: row);
  }
}

class _Pressable extends StatefulWidget {
  const _Pressable({required this.onTap, required this.child});
  final VoidCallback onTap;
  final Widget child;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        color: _down ? p.fill : Colors.transparent,
        child: widget.child,
      ),
    );
  }
}

/// iOS switch, in the accent.
class Toggle extends StatelessWidget {
  const Toggle({super.key, required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => CupertinoSwitch(
    value: value,
    activeTrackColor: Pal.accent,
    onChanged: (v) {
      HapticFeedback.selectionClick();
      onChanged(v);
    },
  );
}

// ── App icon ────────────────────────────────────────────────────────────
class AppIcon extends StatelessWidget {
  const AppIcon(this.pkg, {super.key, this.size = 36});
  final String pkg;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: FutureBuilder<Uint8List?>(
        future: Native.icon(pkg),
        builder: (context, snap) {
          final b = snap.data;
          if (b == null) {
            return DecoratedBox(
              decoration: BoxDecoration(
                color: Pal.of(context).fill,
                borderRadius: BorderRadius.circular(size * 0.28),
              ),
            );
          }
          return Image.memory(
            b,
            width: size,
            height: size,
            gaplessPlayback: true,
          );
        },
      ),
    );
  }
}

// ── The level slider ────────────────────────────────────────────────────
/// A tall, direct slider: drag anywhere on it. Detents at 0, 25, 50, 75 and
/// 100 give a firmer tick; every 5% gives a light one.
class LevelSlider extends StatefulWidget {
  const LevelSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.onDone,
    this.height = 54,
    this.enabled = true,
    this.icon = true,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final ValueChanged<int>? onDone;
  final double height;
  final bool enabled;

  /// The speaker inside the track. Off where a mute button already sits
  /// beside it, so the row never shows the same glyph twice.
  final bool icon;

  @override
  State<LevelSlider> createState() => _LevelSliderState();
}

class _LevelSliderState extends State<LevelSlider> {
  bool _held = false;
  int _last = -1;

  void _at(double x, double w) {
    final v = (x / w * 100).round().clamp(0, 100);
    if (v == widget.value) return;
    final detent = v % 25 == 0;
    if (detent && v != _last) {
      HapticFeedback.mediumImpact();
    } else if (v ~/ 5 != _last ~/ 5) {
      HapticFeedback.selectionClick();
    }
    _last = v;
    widget.onChanged(v);
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final v = widget.value;
    return Semantics(
      slider: true,
      value: levelLabel(v),
      increasedValue: levelLabel((v + 5).clamp(0, 100)),
      decreasedValue: levelLabel((v - 5).clamp(0, 100)),
      onIncrease: () {
        widget.onChanged((v + 5).clamp(0, 100));
        widget.onDone?.call((v + 5).clamp(0, 100));
      },
      onDecrease: () {
        widget.onChanged((v - 5).clamp(0, 100));
        widget.onDone?.call((v - 5).clamp(0, 100));
      },
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth;
          final num = Text(
            levelText(v),
            style: display(
              context,
              widget.height < 40 ? 14.5 : 17,
              color: v > 55 ? Pal.onAccent : Pal.of(context).ink,
            ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
          );
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: widget.enabled
                ? (d) {
                    setState(() => _held = true);
                    _at(d.localPosition.dx, w);
                  }
                : null,
            onHorizontalDragUpdate: widget.enabled
                ? (d) => _at(d.localPosition.dx, w)
                : null,
            onHorizontalDragEnd: widget.enabled
                ? (_) {
                    setState(() => _held = false);
                    widget.onDone?.call(widget.value);
                  }
                : null,
            onTapUp: widget.enabled
                ? (d) {
                    _at(d.localPosition.dx, w);
                    widget.onDone?.call(
                      (d.localPosition.dx / w * 100).round().clamp(0, 100),
                    );
                  }
                : null,
            child: AnimatedScale(
              scale: _held ? 1.01 : 1,
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              child: Opacity(
                opacity: widget.enabled ? 1 : 0.45,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ClipRSuperellipse(
                      borderRadius: BorderRadius.circular(widget.height / 2.6),
                      child: SizedBox(
                        width: double.infinity,
                        height: widget.height,
                        child: Stack(
                          children: [
                            Positioned.fill(child: ColoredBox(color: p.fill)),
                            SpringValue(
                              value: v / 100,
                              stiffness: 520,
                              dampingRatio: 0.9,
                              builder: (context, f, _) => FractionallySizedBox(
                                widthFactor: f.clamp(0.0, 1.0),
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: Pal.level,
                                  ),
                                  child: SizedBox.expand(),
                                ),
                              ),
                            ),
                            Positioned.fill(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                ),
                                child: Row(
                                  children: [
                                    if (widget.icon)
                                      Icon(
                                        v == 0
                                            ? CupertinoIcons.speaker_slash_fill
                                            : v < 50
                                            ? CupertinoIcons.speaker_1_fill
                                            : CupertinoIcons.speaker_3_fill,
                                        size: widget.height < 40 ? 16 : 19,
                                        color: v > 8 ? Pal.onAccent : p.sub,
                                      ),
                                    // The number sits on the side away
                                    // from the knob, so the knob never
                                    // covers it, at rest or held.
                                    if (v > 55) ...[
                                      if (widget.icon)
                                        const SizedBox(width: 10),
                                      num,
                                      const Spacer(),
                                    ] else ...[
                                      const Spacer(),
                                      num,
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // The knob: a slim mark at rest that swells into a lens of
                    // Liquid Glass while a finger holds it, as system sliders do.
                    SpringValue(
                      value: v / 100,
                      stiffness: 520,
                      dampingRatio: 0.9,
                      builder: (context, f, _) {
                        final kw = _held ? 34.0 : 5.0;
                        final kh = _held
                            ? widget.height + 14
                            : widget.height * 0.46;
                        final x =
                            (f.clamp(0.0, 1.0) * w - (_held ? kw / 2 : 12))
                                .clamp(
                                  _held ? -kw / 2 : 6.0,
                                  w - (_held ? kw / 2 : 11),
                                );
                        return AnimatedPositioned(
                          duration: motion(context, 200),
                          curve: Curves.easeOutCubic,
                          left: x,
                          top: (widget.height - kh) / 2,
                          width: kw,
                          height: kh,
                          child: _Knob(held: _held),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Knob extends StatelessWidget {
  const _Knob({required this.held});
  final bool held;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(40);
    if (!held) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.95),
          borderRadius: r,
        ),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: r,
      ),
    );
  }
}

String levelText(int v) => v <= 0 ? 'Muted' : '$v%';
String levelLabel(int v) => v <= 0 ? 'Muted' : '$v percent';

/// The small level read-out in a row: a short track and the number.
class MiniLevel extends StatelessWidget {
  const MiniLevel(this.value, {super.key, this.dim = false});
  final int value;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Opacity(
      opacity: dim ? 0.4 : 1,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 44,
            height: 5,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: Stack(
                children: [
                  Positioned.fill(child: ColoredBox(color: p.fill)),
                  FractionallySizedBox(
                    widthFactor: (value / 100).clamp(0.0, 1.0),
                    child: DecoratedBox(
                      decoration: BoxDecoration(gradient: Pal.level),
                      child: SizedBox.expand(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 52,
            child: Text(
              levelText(value),
              textAlign: TextAlign.right,
              style: body(
                context,
                15,
                w: FontWeight.w600,
              ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Segmented control ───────────────────────────────────────────────────
class Segmented<T> extends StatelessWidget {
  const Segmented({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
  });
  final T value;
  final List<(T, String)> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final i = math.max(0, items.indexWhere((e) => e.$1 == value));
    return Container(
      height: 36,
      padding: const EdgeInsets.all(2),
      decoration: ShapeDecoration(color: p.fill, shape: squircle(11)),
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth / items.length;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: motion(context, 260),
                curve: Curves.easeOutCubic,
                left: w * i,
                top: 0,
                bottom: 0,
                width: w,
                child: DecoratedBox(
                  decoration: ShapeDecoration(
                    color: p.dark
                        ? Colors.white.withValues(alpha: 0.16)
                        : Colors.white,
                    shape: squircle(9),
                  ),
                ),
              ),
              Row(
                children: [
                  for (final e in items)
                    Expanded(
                      child: Semantics(
                        button: true,
                        selected: e.$1 == value,
                        label: e.$2,
                        excludeSemantics: true,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            if (e.$1 == value) return;
                            HapticFeedback.selectionClick();
                            onChanged(e.$1);
                          },
                          child: Center(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                child: Text(
                                  e.$2,
                                  style: body(
                                    context,
                                    13.5,
                                    w: e.$1 == value
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                    color: p.ink,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Buttons ─────────────────────────────────────────────────────────────
class PrimaryButton extends StatefulWidget {
  const PrimaryButton(this.label, {super.key, required this.onTap, this.icon});
  final String label;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  State<PrimaryButton> createState() => _PrimaryButtonState();
}

/// A matte pill in the accent. Presses to 0.97.
class _PrimaryButtonState extends State<PrimaryButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.label,
      excludeSemantics: true,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: () {
          HapticFeedback.lightImpact();
          widget.onTap();
        },
        child: AnimatedScale(
          scale: _down ? 0.97 : 1,
          duration: motion(context, 160),
          curve: Curves.easeOutCubic,
          child: AnimatedOpacity(
            opacity: _down ? 0.85 : 1,
            duration: motion(context, 160),
            child: Container(
              height: 52,
              decoration: ShapeDecoration(
                gradient: Pal.lit,
                shape: StadiumBorder(),
              ),
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.icon != null) ...[
                    Icon(widget.icon, color: Pal.onAccent, size: 19),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    widget.label,
                    style: body(
                      context,
                      17,
                      w: FontWeight.w600,
                      color: Pal.onAccent,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class TextAction extends StatelessWidget {
  const TextAction(
    this.label, {
    super.key,
    required this.onTap,
    this.icon,
    this.color,
  });
  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Pal.of(context).accentText;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 17, color: c),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: body(context, 15, w: FontWeight.w600, color: c),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── The mark: the dial ─────────────────────────────────────────────────
/// Levels' mark, the dial from the app icon: a knob with an amber arc
/// showing the level. [t] runs 0 to 1 as the arc sweeps up to [level] and
/// the pointer turns with it. With [tile] it is the icon itself, on its
/// graphite squircle.
class BarsMark extends StatelessWidget {
  const BarsMark({
    super.key,
    this.size = 64,
    this.t = 1,
    this.level = 0.68,
    this.tile = false,
  });
  final double size;
  final double t;
  final double level;
  final bool tile;

  @override
  Widget build(BuildContext context) {
    final dial = CustomPaint(
      size: Size.square(size),
      painter: _DialPainter(
        t,
        level,
        tile ? 0.315 : 0.40,
        Pal.of(context).dark && !tile
            ? Colors.white.withValues(alpha: 0.13)
            : const Color(0xFF001219).withValues(alpha: 0.10),
        Pal.of(context).dark && !tile ? Colors.white : const Color(0xFF001219),
      ),
    );
    if (!tile) return dial;
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: squircle(size * 0.225),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFCF9F2), Color(0xFFECE1C5)],
        ),
        shadows: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: size * 0.25,
            offset: Offset(0, size * 0.08),
          ),
        ],
      ),
      child: dial,
    );
  }
}

class _DialPainter extends CustomPainter {
  _DialPainter(this.t, this.level, this.radius, this.track, this.knob);
  final double t;
  final double level;
  final double radius;
  final Color track;
  final Color knob;

  static const _start = 135 * math.pi / 180;
  static const _sweep = 270 * math.pi / 180;

  @override
  void paint(Canvas c, Size s) {
    final centre = s.center(Offset.zero);
    final th = s.width * radius * 0.22;
    final r = s.width * radius - th / 2;
    final rect = Rect.fromCircle(center: centre, radius: r);
    final lvl = (level * kSpring.transform(t.clamp(0.0, 1.0))).clamp(0.0, 1.02);

    c.drawArc(
      rect,
      _start,
      _sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = th
        ..strokeCap = StrokeCap.round
        ..color = track,
    );
    if (lvl > 0.005) {
      final shader = const SweepGradient(
        colors: [Color(0xFF14AAA8), Color(0xFF005F73), Color(0xFF005F73)],
        stops: [0, 0.75, 1],
        transform: GradientRotation(_start),
      ).createShader(rect);
      final arc = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = th
        ..strokeCap = StrokeCap.round
        ..shader = shader;
      c.drawArc(rect, _start, _sweep * lvl, false, arc);
    }

    // The knob, with a pointer at the level.
    // The knob: a ring with a tick at the level, as in the icon.
    final kw = th * 0.95;
    final kr = (r + th / 2) * 0.56 - kw / 2;
    final ink = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = kw
      ..strokeCap = StrokeCap.round
      ..color = knob;
    c.drawCircle(centre, kr, ink);
    final a = _start + _sweep * lvl;
    final dir = Offset(math.cos(a), math.sin(a));
    final inner = kr - kw / 2;
    c.drawLine(
      centre + dir * inner * 0.95,
      centre + dir * inner * 0.45,
      ink..strokeWidth = kw * 0.85,
    );
  }

  @override
  bool shouldRepaint(_DialPainter o) =>
      o.t != t || o.level != level || o.track != track || o.knob != knob;
}

// ── The dial: Levels' own control ───────────────────────────────────────
/// A rotary level control, the dial from the icon: a 270 degree track with
/// the level in wheat and a knob at its end. Drag around it to set the
/// level; detents at 0, 25, 50, 75 and 100. [child] sits in the middle, in
/// a disc of glass. Without [onChanged] it only shows the level.
class Dial extends StatefulWidget {
  const Dial({
    super.key,
    required this.value,
    required this.child,
    this.size = 240,
    this.onChanged,
    this.onDone,
    this.enabled = true,
  });

  final int value;
  final Widget child;
  final double size;
  final ValueChanged<int>? onChanged;
  final ValueChanged<int>? onDone;
  final bool enabled;

  @override
  State<Dial> createState() => _DialState();
}

class _DialState extends State<Dial> {
  static const _start = 135 * math.pi / 180;
  static const _sweep = 270 * math.pi / 180;
  int _last = -1;
  bool _held = false;

  bool get _live => widget.enabled && widget.onChanged != null;

  void _at(Offset local) {
    final c = Offset(widget.size / 2, widget.size / 2);
    final d = local - c;
    var a = math.atan2(d.dy, d.dx) - _start;
    while (a < 0) {
      a += math.pi * 2;
    }
    // In the gap at the bottom: snap to whichever end is nearer.
    if (a > _sweep) a = a - _sweep < (math.pi * 2 - _sweep) / 2 ? _sweep : 0;
    final v = (a / _sweep * 100).round().clamp(0, 100);
    if (v == widget.value) return;
    if (v % 25 == 0 && v != _last) {
      HapticFeedback.mediumImpact();
    } else if (v ~/ 5 != _last ~/ 5) {
      HapticFeedback.selectionClick();
    }
    _last = v;
    widget.onChanged!(v);
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final v = widget.value;
    final s = widget.size;
    final dial = SizedBox.square(
      dimension: s,
      child: SpringValue(
        value: v / 100,
        stiffness: 420,
        dampingRatio: 0.85,
        builder: (context, f, _) => CustomPaint(
          painter: _DialArc(
            f.clamp(0.0, 1.0),
            p.fill,
            widget.enabled ? Pal.accent : p.faint,
            _held,
            p.bg,
          ),
          child: Center(
            child: SizedBox.square(
              dimension: s * 0.58,
              child: Plate(
                radius: s * 0.29,
                child: Center(child: widget.child),
              ),
            ),
          ),
        ),
      ),
    );
    if (!_live) return dial;
    return Semantics(
      slider: true,
      value: levelLabel(v),
      increasedValue: levelLabel((v + 5).clamp(0, 100)),
      decreasedValue: levelLabel((v - 5).clamp(0, 100)),
      onIncrease: () {
        widget.onChanged!((v + 5).clamp(0, 100));
        widget.onDone?.call((v + 5).clamp(0, 100));
      },
      onDecrease: () {
        widget.onChanged!((v - 5).clamp(0, 100));
        widget.onDone?.call((v - 5).clamp(0, 100));
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (d) {
          setState(() => _held = true);
          _at(d.localPosition);
        },
        onPanUpdate: (d) => _at(d.localPosition),
        onPanEnd: (_) {
          setState(() => _held = false);
          widget.onDone?.call(widget.value);
        },
        onTapUp: (d) {
          _at(d.localPosition);
          widget.onDone?.call(widget.value);
        },
        child: dial,
      ),
    );
  }
}

class _DialArc extends CustomPainter {
  _DialArc(this.f, this.track, this.fill, this.held, this.bg);
  final double f;
  final Color track;
  final Color fill;
  final bool held;
  final Color bg;

  static const _start = 135 * math.pi / 180;
  static const _sweep = 270 * math.pi / 180;

  @override
  void paint(Canvas c, Size s) {
    final th = s.width * 0.065;
    final r = s.width / 2 - th;
    final centre = s.center(Offset.zero);
    final rect = Rect.fromCircle(center: centre, radius: r);
    Paint stroke(Color color) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = th
      ..strokeCap = StrokeCap.round
      ..color = color;
    c.drawArc(rect, _start, _sweep, false, stroke(track));
    if (f > 0.002) c.drawArc(rect, _start, _sweep * f, false, stroke(fill));
    // The knob at the level: a disc ringed in the background colour, so it
    // reads as a separate part. Larger while a finger holds it.
    final a = _start + _sweep * f;
    final at = centre + Offset(math.cos(a), math.sin(a)) * r;
    final kr = th * (held ? 1.0 : 0.78);
    c.drawCircle(at, kr + th * 0.22, Paint()..color = bg);
    c.drawCircle(at, kr, Paint()..color = fill);
  }

  @override
  bool shouldRepaint(_DialArc o) =>
      o.f != f ||
      o.track != track ||
      o.fill != fill ||
      o.held != held ||
      o.bg != bg;
}

/// A choice shown as a tile: an icon, a name, a line. The chosen one is
/// solid wheat; the rest are clear glass.
class ChoiceTile extends StatelessWidget {
  const ChoiceTile({
    super.key,
    required this.icon,
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final ink = selected ? Pal.onAccent : p.ink;
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 21, color: selected ? ink : p.sub),
          const SizedBox(height: 16),
          Text(
            title,
            style: body(context, 15.5, w: FontWeight.w600, color: ink),
          ),
          if (subtitle != null)
            Text(
              subtitle!,
              style: body(
                context,
                13,
                color: selected ? ink.withValues(alpha: 0.7) : p.sub,
              ),
            ),
        ],
      ),
    );
    return Semantics(
      button: true,
      selected: selected,
      label: title,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (selected) return;
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedSwitcher(
          duration: motion(context, 200),
          // Fill the cell: the default layout centres the tile and lets it
          // shrink to its words.
          layoutBuilder: (current, previous) =>
              Stack(fit: StackFit.expand, children: [...previous, ?current]),
          child: selected
              ? DecoratedBox(
                  key: const ValueKey(true),
                  decoration: ShapeDecoration(
                    color: Pal.accent,
                    shape: squircle(20),
                  ),
                  child: content,
                )
              : Plate(key: const ValueKey(false), radius: 20, child: content),
        ),
      ),
    );
  }
}

/// The round wheat button that floats bottom right: add, go on.
class RoundAction extends StatelessWidget {
  const RoundAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    excludeSemantics: true,
    child: GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        width: 60,
        height: 60,
        decoration: ShapeDecoration(
          color: Pal.accent,
          shape: CircleBorder(),
        ),
        child: Icon(icon, color: Pal.onAccent, size: 26),
      ),
    ),
  );
}

/// A page with the glass chrome, the backdrop and a large title.
class Screen extends StatelessWidget {
  const Screen({
    super.key,
    required this.title,
    required this.children,
    this.actions = const [],
    this.back = true,
    this.bottom,
    this.maxContentWidth = 640,
    this.side,
    this.main,
    this.panes,
    this.empty,
    this.panel = false,
    this.panelWidth = 760,
  });

  /// Width of the one centred desktop panel.
  final double panelWidth;

  final String title;
  final List<Widget> children;
  final List<Widget> actions;
  final bool back;
  final Widget? bottom;

  /// How wide the content may grow before it is centred. Wider for a
  /// screen that lays out side by side on a big display.
  final double maxContentWidth;

  /// On a wide, short window (a desktop window, a tablet or a phone on its
  /// side) this stands in its own full-height pane on the left while the
  /// list scrolls on the right: two panes of equal height, never ragged.
  /// Elsewhere it is simply the first item of the list.
  final Widget? side;

  /// With [side] on a wide, short window: the right pane as one full-height
  /// widget instead of a scrolling list of [children].
  final Widget? main;

  /// On a desktop window: these lists as side-by-side full-height panels,
  /// all ending at the same line. Elsewhere they run one after another.
  final List<List<Widget>>? panes;

  /// An empty state, centred in the space under the title (on a desktop
  /// window, centred in one panel).
  final Widget? empty;

  /// On a desktop window: [children] in one centred full-height panel.
  final bool panel;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final mq = MediaQuery.of(context);
    final desk = isSplitLayout(context);
    final split = side != null && desk;
    final paned = panes != null && desk;
    final all = [...?panes?.expand((l) => l), ...children];
    final top = GlassAppBar.bottomOf(context) + 4;
    final bottomPad = mq.padding.bottom + (bottom != null ? 110 : 28);
    final heading = Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 18),
      child: Text(title, style: display(context, 34)),
    );
    final Widget scroll = split
        ? Padding(
            padding: EdgeInsets.fromLTRB(24, top, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                heading,
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: 380,
                        child: Padding(
                          padding: EdgeInsets.only(
                            bottom: mq.padding.bottom + 24,
                          ),
                          child: side,
                        ),
                      ),
                      const SizedBox(width: 24),
                      Expanded(
                        child: main != null
                            ? Padding(
                                padding: EdgeInsets.only(
                                  bottom: mq.padding.bottom + 24,
                                ),
                                child: main,
                              )
                            : ListView(
                                padding: EdgeInsets.only(bottom: bottomPad),
                                children: children,
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          )
        : !paned && (empty != null || panel) && desk
        // One panel: the title sits on the panel's own left edge.
        ? Padding(
            padding: EdgeInsets.fromLTRB(24, top, 24, mq.padding.bottom + 24),
            child: Center(
              child: SizedBox(
                width: panelWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    heading,
                    Expanded(
                      child: Panel(empty: empty, children: children),
                    ),
                  ],
                ),
              ),
            ),
          )
        : paned
        ? Padding(
            padding: EdgeInsets.fromLTRB(24, top, 24, mq.padding.bottom + 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                heading,
                Expanded(
                  child: !paned
                      ? Align(
                          alignment: Alignment.topCenter,
                          child: SizedBox(
                            width: 760,
                            child: Panel(empty: empty, children: children),
                          ),
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (var i = 0; i < panes!.length; i++) ...[
                              if (i > 0) const SizedBox(width: 20),
                              Expanded(child: Panel(children: panes![i])),
                            ],
                          ],
                        ),
                ),
              ],
            ),
          )
        : empty != null
        ? LayoutBuilder(
            builder: (context, box) => SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(16, top, 16, bottomPad),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: box.maxHeight - top - bottomPad,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    heading,
                    ?side,
                    ...children,
                    // The empty state takes the middle of what is left.
                    SizedBox(
                      height: (box.maxHeight - top - bottomPad - 140).clamp(
                        220.0,
                        2000.0,
                      ),
                      child: Center(child: empty),
                    ),
                  ],
                ),
              ),
            ),
          )
        : ListView(
            padding: EdgeInsets.fromLTRB(16, top, 16, bottomPad),
            children: [heading, ?side, ...all],
          );
    return GlassScaffold(
      maxContentWidth: split || paned || ((empty != null || panel) && desk)
          ? 1200
          : maxContentWidth,
      statusBarStyle: p.dark
          ? GlassStatusBarStyle.light
          : GlassStatusBarStyle.dark,
      background: const Backdrop(),
      appBar: GlassAppBar(
        leading: back
            ? Padding(
                padding: const EdgeInsets.only(left: 12),
                child: RoundGlassButton(
                  icon: CupertinoIcons.chevron_back,
                  semanticLabel: 'Back',
                  size: 40,
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              )
            : null,
        actions: [...actions, const SizedBox(width: 12)],
      ),
      body: Stack(
        children: [
          scroll,
          if (bottom != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: mq.padding.bottom + 16,
              child: bottom!,
            ),
        ],
      ),
    );
  }
}

/// Push with the iOS-style slide.
Future<T?> go<T>(BuildContext context, Widget page) =>
    Navigator.of(context).push<T>(CupertinoPageRoute(builder: (_) => page));
