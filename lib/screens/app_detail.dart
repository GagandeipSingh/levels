import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/model.dart';
import '../ui/kit.dart';
import '../ui/motion.dart';
import 'rule_sheet.dart';

class AppDetail extends StatelessWidget {
  const AppDetail(this.pkg, {super.key});
  final String pkg;

  static const keyModes = [
    ('', 'Default'),
    ('ignore', 'Ignore'),
    ('remember', 'Remember'),
    ('lock', 'Lock'),
  ];

  static String keyExplain(String mode, String app) => switch (mode) {
    'ignore' =>
      'Volume keys work as usual inside $app, but the change '
          'is not kept. Next time it opens at its level again.',
    'remember' =>
      'If you change the volume inside $app, that becomes '
          'its new level when you leave.',
    'lock' =>
      'The level stays put. Pressing the volume keys inside $app '
          'snaps straight back to it.',
    _ => switch (model.get<String>('keyMode', 'remember')) {
      'ignore' =>
        'Follows Settings, which is Ignore: changes inside $app are not kept.',
      'lock' =>
        'Follows Settings, which is Lock: the level stays put inside $app.',
      _ =>
        'Follows Settings, which is Remember: a change inside $app becomes its level.',
    },
  };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) {
        final p = Pal.of(context);
        final a = model.app(pkg);
        if (a == null) return const SizedBox.shrink();
        final name = model.labelOf(pkg);
        final on = a['on'] != false;
        final vol = (a['vol'] as num?)?.toInt() ?? 50;
        final keys = a['keyMode'] as String? ?? '';
        final rules = model.rules(pkg);

        final items = <Widget>[
          // The level, on the dial: drag around it.
          Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Dial(
                    value: vol,
                    size: 260,
                    enabled: on,
                    onChanged: (v) {
                      a['vol'] = v;
                      model.commit();
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Hero(tag: 'icon-$pkg', child: AppIcon(pkg, size: 48)),
                        const SizedBox(height: 6),
                        Text(
                          levelText(vol),
                          style: display(context, 30).copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  // Mute, and give the level back: the last level is kept.
                  Opacity(
                    opacity: on ? 1 : 0.4,
                    child: TextAction(
                      vol == 0 ? 'Unmute' : 'Mute',
                      icon: vol == 0
                          ? CupertinoIcons.speaker_2_fill
                          : CupertinoIcons.speaker_slash_fill,
                      onTap: () {
                        if (!on) return;
                        if (vol == 0) {
                          a['vol'] = (a['unmute'] as num?)?.toInt() ?? 50;
                        } else {
                          a['unmute'] = vol;
                          a['vol'] = 0;
                        }
                        model.commit(now: true);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          Section(
            children: [
              Tile(
                title: on ? 'Plays at this level' : 'Paused',
                subtitle: on
                    ? 'Every time $name opens'
                    : '$name plays at your level',
                trailing: Toggle(
                  value: on,
                  onChanged: (v) {
                    a['on'] = v;
                    model.commit(now: true);
                  },
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
            child: Text(
              'VOLUME KEYS INSIDE $name'.toUpperCase(),
              style: body(context, 13, color: p.sub),
            ),
          ),
          GridView(
            // A fixed height, so a wide screen gets wider tiles rather than
            // taller ones.
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              mainAxisExtent: 104,
            ),
            // No padding: a scroll view otherwise adds the status-bar and
            // gesture-bar insets above and below the tiles.
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (final (mode, label, icon) in const [
                ('', 'Default', CupertinoIcons.slider_horizontal_3),
                ('ignore', 'Ignore', CupertinoIcons.arrow_uturn_left),
                ('remember', 'Remember', CupertinoIcons.bookmark_fill),
                ('lock', 'Lock', CupertinoIcons.lock_fill),
              ])
                ChoiceTile(
                  icon: icon,
                  title: label,
                  selected: keys == mode,
                  onTap: () {
                    if (mode.isEmpty) {
                      a.remove('keyMode');
                    } else {
                      a['keyMode'] = mode;
                    }
                    model.commit(now: true);
                  },
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 22),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              layoutBuilder: (current, previous) => Stack(
                alignment: Alignment.topLeft,
                children: [...previous, ?current],
              ),
              child: Text(
                keyExplain(keys, name),
                key: ValueKey(keys),
                style: body(context, 14, color: p.sub),
              ),
            ),
          ),
          Section(
            title: 'Rules',
            trailing: TextAction(
              'Add',
              icon: CupertinoIcons.add,
              onTap: () async {
                final r = await showRuleSheet(context, base: vol);
                if (r != null) model.setRules(pkg, [...rules, r]);
              },
            ),
            footer: rules.isEmpty
                ? 'A different level on headphones, in the car or at night. '
                      'The first rule that fits wins.'
                : 'Checked when $name opens. The first rule that fits wins.',
            children: rules.isEmpty
                ? [
                    Tile(
                      leading: const _RuleGlyph(CupertinoIcons.headphones),
                      title: 'Quieter on headphones',
                      subtitle: 'Example: Bluetooth at ${(vol * 0.6).round()}%',
                      trailing: TextAction(
                        'Add',
                        onTap: () async {
                          final r = await showRuleSheet(
                            context,
                            base: vol,
                            initial: {
                              'device': 'bt',
                              'vol': (vol * 0.6).round(),
                            },
                          );
                          if (r != null) model.setRules(pkg, [...rules, r]);
                        },
                      ),
                    ),
                    Tile(
                      leading: const _RuleGlyph(CupertinoIcons.moon_fill),
                      title: 'Softer at night',
                      subtitle:
                          'Example: 22:00 – 07:00 at ${(vol * 0.5).round()}%',
                      trailing: TextAction(
                        'Add',
                        onTap: () async {
                          final r = await showRuleSheet(
                            context,
                            base: vol,
                            initial: {
                              'device': 'any',
                              'from': '22:00',
                              'to': '07:00',
                              'vol': (vol * 0.5).round(),
                            },
                          );
                          if (r != null) model.setRules(pkg, [...rules, r]);
                        },
                      ),
                    ),
                  ]
                : [
                    for (var i = 0; i < rules.length; i++)
                      Tile(
                        leading: _RuleGlyph(switch (rules[i]['device']) {
                          'bt' => CupertinoIcons.bluetooth,
                          'wired' => CupertinoIcons.headphones,
                          'speaker' => CupertinoIcons.speaker_2_fill,
                          _ => switch (rules[i]['when']) {
                            'charging' => CupertinoIcons.bolt_fill,
                            'quiet' => CupertinoIcons.bell_slash_fill,
                            'lowBattery' => CupertinoIcons.battery_25,
                            _ =>
                              rules[i]['days'] != null
                                  ? CupertinoIcons.calendar
                                  : CupertinoIcons.clock_fill,
                          },
                        }),
                        title: ruleText(rules[i]),
                        trailing: MiniLevel(
                          (rules[i]['vol'] as num?)?.toInt() ?? vol,
                        ),
                        chevron: true,
                        onTap: () async {
                          final r = await showRuleSheet(
                            context,
                            base: vol,
                            initial: rules[i],
                            editing: true,
                            canGoFirst: i > 0,
                          );
                          if (r == null) return;
                          final next = [...rules];
                          if (r.isEmpty) {
                            next.removeAt(i);
                          } else if (r.remove('_first') == true) {
                            next
                              ..removeAt(i)
                              ..insert(0, r);
                          } else {
                            next[i] = r;
                          }
                          model.setRules(pkg, next);
                        },
                      ),
                  ],
          ),
          Section(
            children: [
              Tile(
                title: 'Remove $name',
                danger: true,
                onTap: () async {
                  final ok = await _confirmRemove(context, name);
                  if (ok == true && context.mounted) {
                    Navigator.of(context).pop();
                    model.removeApp(pkg);
                  }
                },
              ),
            ],
          ),
        ];
        // A wide screen sets the dial beside the key choices, the two
        // centred against each other at about the same height; the rest
        // runs full width below. Never two ragged columns.
        final wide = isWideLayout(context);
        // A desktop window: the dial gets its own full-height pane, centred
        // in a card; everything else scrolls beside it.
        if (isSplitLayout(context)) {
          return Screen(
            title: name,
            side: Plate(radius: 28, child: Center(child: items[0])),
            main: Panel(
              children: [
                items[1],
                items[2],
                items[3],
                items[4],
                ...items.skip(5),
              ],
            ),
            children: const [],
          );
        }
        return Screen(
          title: name,
          maxContentWidth: wide ? 860 : 640,
          children: wide
              ? [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 22),
                    child: Row(
                      children: [
                        items[0],
                        const SizedBox(width: 40),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [items[2], items[3], items[4]],
                          ),
                        ),
                      ],
                    ),
                  ),
                  items[1],
                  ...items.skip(5),
                ]
              : items,
        );
      },
    );
  }
}

class _RuleGlyph extends StatelessWidget {
  const _RuleGlyph(this.icon);
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    width: 32,
    height: 32,
    decoration: BoxDecoration(
      color: Pal.accent.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(9),
    ),
    child: Icon(icon, size: 17, color: Pal.accent),
  );
}

Future<bool?> _confirmRemove(BuildContext context, String name) {
  return showGlassConfirm(
    context,
    title: 'Remove $name?',
    text: '$name will play at your level again. Its rules go too.',
    action: 'Remove',
  );
}

/// A small glass confirm sheet: one destructive action and Cancel.
Future<bool?> showGlassConfirm(
  BuildContext context, {
  required String title,
  required String text,
  required String action,
}) {
  final p = Pal.of(context);
  return showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: p.dark ? 0.4 : 0.2),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Plate(
          radius: 26,
          color: p.raised,
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: display(ctx, 21), textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(
                text,
                textAlign: TextAlign.center,
                style: body(ctx, 15, color: p.sub),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: GestureDetector(
                  onTap: () => Navigator.of(ctx).pop(true),
                  child: Container(
                    height: 52,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: p.danger,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      action,
                      style: body(
                        ctx,
                        16.5,
                        w: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              TextAction(
                'Cancel',
                color: p.sub,
                onTap: () => Navigator.of(ctx).pop(false),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
