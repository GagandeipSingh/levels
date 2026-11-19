import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/model.dart';
import '../core/native.dart';
import '../ui/kit.dart';
import 'activity.dart';
import 'app_detail.dart' show AppDetail, showGlassConfirm;
import 'picker.dart';

class Settings extends StatelessWidget {
  const Settings({super.key});

  String _hiddenText(Object? hide) {
    final l = [for (final x in (hide as List? ?? const [])) model.labelOf('$x')];
    if (l.isEmpty) return 'No apps';
    if (l.length <= 2) return l.join(', ');
    return '${l.take(2).join(', ')} and ${l.length - 2} more';
  }

  void _toast(BuildContext context, String text) {
    final p = Pal.of(context);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: p.dark
              ? const Color(0xFF2C2C30)
              : const Color(0xFF1C1C1E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          content: Text(text, style: body(context, 14.5, color: Colors.white)),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) {
        final p = Pal.of(context);
        final n = model.notice;
        final keys = model.get<String>('keyMode', 'remember');
        final cap = model.s['cap'];
        return Screen(
          title: 'Settings',
          panes: [
            [
              Section(
                title: 'Running',
                children: [
                  Tile(
                    title: 'Accessibility switch',
                    subtitle: model.serviceOn
                        ? 'On · Levels can see which app is in front'
                        : 'Off · nothing changes until it is on',
                    trailing: Text(
                      model.serviceOn ? 'On' : 'Turn on',
                      style: body(
                        context,
                        15,
                        w: FontWeight.w600,
                        color: model.serviceOn ? p.good : p.accentText,
                      ),
                    ),
                    onTap: Native.openAccessibility,
                  ),
                  // Battery saving can stop the service; always reachable
                  // here, even after the Home card was put away.
                  Tile(
                    title: 'Battery',
                    subtitle: switch (model.batteryStep) {
                      'ask' => 'Limited · your phone may stop Levels',
                      'oem' =>
                        Model.oemPath[model.oem] ??
                            'Allow Levels to run in the background',
                      _ => 'Not limited · Levels keeps running',
                    },
                    trailing: Text(
                      model.batteryStep == null ? 'OK' : 'Allow',
                      style: body(
                        context,
                        15,
                        w: FontWeight.w600,
                        color: model.batteryStep == null
                            ? p.good
                            : p.accentText,
                      ),
                    ),
                    onTap: () {
                      if (model.batteryStep == 'ask') {
                        model.put('batteryAsked', true);
                        Native.batteryAsk();
                      } else {
                        Native.batteryOem();
                      }
                    },
                  ),
                  // Banks and UPI apps refuse payments while any
                  // accessibility switch is on (as Go Echoo found).
                  // Banks and UPI apps refuse payments while any
                  // accessibility switch is on. The row says which way the
                  // next tap goes: off before paying, on after.
                  Tile(
                    title: model.serviceOn
                        ? 'Paying with a bank app?'
                        : 'Paid? Turn Levels back on',
                    subtitle: model.serviceOn
                        ? 'Turn Levels off before you pay'
                        : 'Levels, On, Allow',
                    chevron: true,
                    onTap: () async {
                      if (!model.serviceOn) {
                        Native.openAccessibility();
                        return;
                      }
                      final ok = await showGlassConfirm(
                        context,
                        title: 'Turn off for a payment?',
                        text: 'Banks may block payments while Levels is on.',
                        action: 'Turn off',
                      );
                      if (ok == true) await Native.payPause();
                    },
                  ),
                  Tile(
                    title: 'Pause from notification',
                    subtitle: model.notifOk
                        ? 'In the shade: Pause for a payment'
                        : 'Allow notifications to show it',
                    chevron: !model.notifOk,
                    onTap: () async {
                      if (model.notifOk) return;
                      await Native.askNotif();
                      await model.refreshStatus();
                    },
                  ),
                  Tile(
                    title: 'Paying icon',
                    subtitle: 'On your home screen, one tap',
                    chevron: true,
                    onTap: () async {
                      final ok = await Native.pinPay();
                      if (!ok && context.mounted) {
                        _toast(context, 'This home screen cannot add icons.');
                      }
                    },
                  ),
                  Tile(
                    title: 'Pause Levels',
                    subtitle: 'Every app plays at your level',
                    trailing: Toggle(
                      value: !model.enabled,
                      onChanged: (v) => model.enabled = !v,
                    ),
                  ),
                  Tile(
                    title: 'Quick Settings tile',
                    subtitle: 'Pause or resume from the notification shade',
                    chevron: true,
                    onTap: () async {
                      final ok = await Native.addTile();
                      if (!ok && context.mounted) {
                        _toast(
                          context,
                          'Pull down the shade twice, tap the pencil, and drag Levels in.',
                        );
                      }
                    },
                  ),
                ],
              ),
              Section(
                title: 'Changing levels',
                children: [
                  Tile(
                    title: 'Fade between levels',
                    subtitle: 'Moves smoothly instead of jumping',
                    trailing: Toggle(
                      value: model.get<bool>('ramp', true),
                      onChanged: (v) => model.put('ramp', v),
                    ),
                  ),
                  Tile(
                    title: 'Offer to save a level',
                    subtitle:
                        'When you change the volume in an app with no level',
                    trailing: Toggle(
                      value: model.get<bool>('offer', true),
                      onChanged: (v) => model.put('offer', v),
                    ),
                  ),
                  Tile(
                    title: 'Headphone limit',
                    subtitle: cap == null
                        ? 'Off'
                        : 'Never above ${(cap as num).toInt()}% on headphones',
                    trailing: Toggle(
                      value: cap != null,
                      onChanged: (v) => model.put('cap', v ? 70 : null),
                    ),
                  ),
                  if (cap != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                      child: LevelSlider(
                        value: (cap as num).toInt(),
                        height: 46,
                        onChanged: (v) {
                          model.s['cap'] = v.clamp(10, 100);
                          model.commit();
                        },
                      ),
                    ),
                ],
              ),
              Section(
                title: 'Volume keys inside an app',
                footer: AppDetail.keyExplain(keys, 'the app'),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Segmented<String>(
                      value: keys,
                      items: const [
                        ('ignore', 'Ignore'),
                        ('remember', 'Remember'),
                        ('lock', 'Lock'),
                      ],
                      onChanged: (v) => model.put('keyMode', v),
                    ),
                  ),
                ],
              ),
            ],
            [
              Section(
                title: 'The on-screen pill',
                footer:
                    'Drag the pill to change the level; letting go saves it for that app. '
                    'Tap it for more. Hold and drag to move it up or down.',
                children: [
                  Tile(
                    title: 'Show the pill',
                    subtitle: 'The level, as you open an app',
                    trailing: Toggle(
                      value: n['show'] != false,
                      onChanged: (v) {
                        n['show'] = v;
                        model.commit(now: true);
                      },
                    ),
                  ),
                  if (n['show'] != false) ...[
                    // Which apps: only the ones given a level, or media apps
                    // too, where it shows the volume so it can be kept.
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Show in',
                            style: body(context, 13, color: Pal.of(context).sub),
                          ),
                          const SizedBox(height: 8),
                          Segmented<bool>(
                            value: n['unset'] != false,
                            items: const [
                              (false, 'My apps'),
                              (true, 'My apps + media'),
                            ],
                            onChanged: (v) {
                              n['unset'] = v;
                              model.commit(now: true);
                            },
                          ),
                          const SizedBox(height: 8),
                          Text(
                            n['unset'] != false
                                ? 'Media apps show the volume. Drag to keep it.'
                                : 'Only apps you gave a level.',
                            style: body(
                              context,
                              12.5,
                              color: Pal.of(context).sub,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // One app at a time: for a user who wants it in most
                    // media apps but not in, say, a game.
                    if (n['unset'] != false)
                      Tile(
                        title: 'Hidden in',
                        subtitle: _hiddenText(n['hide']),
                        chevron: true,
                        onTap: () async {
                          final cur = {
                            for (final x in (n['hide'] as List? ?? const []))
                              '$x',
                          };
                          final got = await go<Set<String>>(
                            context,
                            Picker(
                              multi: true,
                              selected: cur,
                              unsetOnly: true,
                              title: 'Hidden in',
                            ),
                          );
                          if (got == null) return;
                          n['hide'] = got.toList();
                          model.commit(now: true);
                        },
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
                      child: Segmented<String>(
                        value: n['side'] as String? ?? 'right',
                        items: const [
                          ('right', 'Right'),
                          ('left', 'Left'),
                          ('top', 'Top'),
                        ],
                        onChanged: (v) {
                          n['side'] = v;
                          model.commit(now: true);
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
                      child: Segmented<String>(
                        value: n['style'] as String? ?? 'detail',
                        items: const [
                          ('detail', 'Icon and number'),
                          ('bar', 'Bar only'),
                        ],
                        onChanged: (v) {
                          n['style'] = v;
                          model.commit(now: true);
                        },
                      ),
                    ),
                  ],
                ],
              ),
              Section(
                title: 'Appearance',
                children: [
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Segmented<ThemeMode>(
                      value: model.theme,
                      items: const [
                        (ThemeMode.system, 'System'),
                        (ThemeMode.light, 'Light'),
                        (ThemeMode.dark, 'Dark'),
                      ],
                      onChanged: (m) => model.theme = m,
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(14, 2, 14, 16),
                    child: _AccentRow(),
                  ),
                ],
              ),
              Section(
                title: 'History and backup',
                children: [
                  Tile(
                    leading: Icon(
                      CupertinoIcons.clock,
                      color: Pal.accent,
                      size: 22,
                    ),
                    title: 'Activity',
                    subtitle: 'Every level change, and why',
                    chevron: true,
                    onTap: () => go(context, const Activity()),
                  ),
                  Tile(
                    leading: Icon(
                      CupertinoIcons.square_arrow_up,
                      color: Pal.accent,
                      size: 22,
                    ),
                    title: 'Export settings',
                    subtitle: 'Save your levels, rules and groups to a file',
                    onTap: () async {
                      final r = await Native.export();
                      if (r == 'saved' && context.mounted) {
                        _toast(context, 'Saved');
                      }
                    },
                  ),
                  Tile(
                    leading: Icon(
                      CupertinoIcons.square_arrow_down,
                      color: Pal.accent,
                      size: 22,
                    ),
                    title: 'Import settings',
                    subtitle: 'Replace them with a saved file',
                    onTap: () async {
                      final r = await Native.import();
                      if (r == null || !context.mounted) return;
                      if (r == 'invalid') {
                        _toast(context, 'That file is not a Levels backup.');
                        return;
                      }
                      final keep = {'onboarded': model.s['onboarded']};
                      model.s = {
                        ...(jsonDecode(r) as Map).cast<String, dynamic>(),
                        ...keep,
                      };
                      model.commit(now: true);
                      _toast(context, 'Imported');
                    },
                  ),
                ],
              ),
              Section(
                title: 'About',
                footer:
                    'Levels sees only the name of the app in front, never what '
                    'is on screen. It has no internet access, so nothing leaves your phone.',
                children: const [Tile(title: 'Levels', trailing: _Version())],
              ),
            ],
          ],
          children: const [],
        );
      },
    );
  }
}

class _Version extends StatelessWidget {
  const _Version();

  @override
  Widget build(BuildContext context) =>
      Text('1.0', style: body(context, 15, color: Pal.of(context).sub));
}


/// Accent swatches. Each one is tuned to wheat's level (light, soft,
/// matte), so whichever is chosen the app still looks like itself.
class _AccentRow extends StatelessWidget {
  const _AccentRow();

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final cur = model.accent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Accent', style: body(context, 13, color: p.sub)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final a in Accent.all)
              Semantics(
                button: true,
                selected: a.id == cur,
                label: a.name,
                child: GestureDetector(
                  onTap: () {
                    if (a.id == cur) return;
                    HapticFeedback.selectionClick();
                    model.accent = a.id;
                    // The accent is read straight from Pal everywhere, so
                    // every element rebuilds, const ones included.
                    void mark(Element e) {
                      e.markNeedsBuild();
                      e.visitChildren(mark);
                    }

                    WidgetsBinding.instance.rootElement?.visitChildren(mark);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    width: 40,
                    height: 40,
                    padding: const EdgeInsets.all(3),
                    decoration: ShapeDecoration(
                      shape: CircleBorder(
                        side: BorderSide(
                          color: a.id == cur ? p.ink : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                    child: DecoratedBox(
                      decoration: ShapeDecoration(
                        color: a.fill,
                        shape: const CircleBorder(),
                      ),
                      child: a.id == cur
                          ? Icon(Icons.check_rounded, size: 18, color: a.on)
                          : null,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(Accent.byId(cur).name, style: body(context, 12.5, color: p.sub)),
      ],
    );
  }
}
