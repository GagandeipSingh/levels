import 'package:flutter/cupertino.dart';

import '../core/model.dart';
import '../core/native.dart';
import '../ui/glass_chrome.dart';
import '../ui/kit.dart';
import '../ui/motion.dart';
import 'activity.dart';
import 'app_detail.dart';
import 'categories.dart';
import 'picker.dart';
import 'settings.dart';

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    model.watch(true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    model.watch(false);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    model.watch(state == AppLifecycleState.resumed);
    if (state == AppLifecycleState.resumed) {
      // Store first, so the commit below cannot write a stale copy back.
      model.reload().then((_) => Native.apps(refresh: true)).then((a) {
        model.apps = a;
        model.commit();
      });
    }
  }

  Future<void> _add() async {
    final pkg = await go<String>(context, const Picker());
    if (pkg == null || !mounted) return;
    model.ensureApp(pkg);
    model.commit(now: true);
    go(context, AppDetail(pkg));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) {
        final apps = model.managed;
        final wide = isWideLayout(context);
        final split = isSplitLayout(context);
        final hero = model.serviceOn
            ? _Now(wide: wide && !split, fill: split)
            : _Setup(wide: wide && !split, fill: split);
        // One line: the rows already show each app has its own level.
        final footer = model.get<String>('keyMode', 'remember') == 'remember'
            ? 'Change the volume in an app and Levels keeps it for next time.'
            : 'Media volume comes back when you leave an app.';
        final pay =
            model.serviceOn &&
            (!model.get<bool>('payTipSeen', false) ||
                (!model.notifOk && !model.get<bool>('notifCardHidden', false)));
        final battery =
            !pay &&
            model.serviceOn &&
            model.batteryStep != null &&
            !model.get<bool>('batteryHidden', false);
        final list = <Widget>[
          if (pay) const _PayCard(),
          if (battery) const _BatteryCard(),
          Section(
            title: 'Your apps',
            footer: apps.isEmpty ? null : footer,
            children: apps.isEmpty
                ? [_Empty(onAdd: _add)]
                : [
                    for (var i = 0; i < apps.length; i++)
                      EntranceIn(index: i, child: _AppRow(apps[i])),
                    _AddRow(onTap: _add),
                  ],
          ),
          _AutoTile(
            summary: _autoSummary(),
            onTap: () => go(context, const Categories()),
          ),
          // Always one tap away on Home too, for anyone without the
          // notification.
          if (model.serviceOn) const _PayRow(),
        ];
        return Screen(
          title: 'Levels',
          back: false,
          maxContentWidth: wide ? 860 : 640,
          actions: [
            RoundGlassButton(
              icon: CupertinoIcons.gear_alt,
              semanticLabel: 'Settings',
              size: 40,
              onPressed: () => go(context, const Settings()),
            ),
          ],
          // A wide screen (an open foldable, a tablet) keeps one centred
          // column and lays the hero card out sideways instead.
          side: split
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: hero),
                    const SizedBox(height: 16),
                    _Shortcuts(summary: _autoSummary()),
                  ],
                )
              : hero,
          main: split
              ? _AppsPanel(
                  apps: apps,
                  footer: footer,
                  onAdd: _add,
                  battery: battery,
                  pay: pay,
                )
              : null,
          children: list,
        );
      },
    );
  }

  String _autoSummary() {
    final on = Model.catKeys.where((k) => model.cat(k)['on'] == true).length;
    final g = model.groups.length;
    if (on == 0 && g == 0) return 'One level for games, video and more';
    final parts = <String>[
      if (g > 0) '$g ${g == 1 ? 'group' : 'groups'}',
      if (on > 0) '$on app ${on == 1 ? 'type' : 'types'} on',
    ];
    return parts.join(' · ');
  }
}

/// Battery saving can stop Levels without a word, and then every app plays
/// at your level. Shown only while Android says Levels may be stopped. The
/// first tap asks Android; if the phone still limits Levels after that (Vivo,
/// Xiaomi and friends keep their own switch), the next opens the maker's page
/// instead of asking again in a loop. As in Go Echoo.
/// One quiet card on Home: a mark, what is wrong, and one thing to do.
/// The phone's card, or a single line atop the desktop apps panel.
class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.title,
    required this.text,
    required this.action,
    required this.onAction,
    required this.dismiss,
    required this.onDismiss,
    this.strip = false,
  });
  final IconData icon;
  final String title;
  final String text;
  final String action;
  final VoidCallback onAction;
  final String dismiss;
  final VoidCallback onDismiss;
  final bool strip;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final mark = Container(
      width: 36,
      height: 36,
      decoration: ShapeDecoration(color: Pal.accent, shape: squircle(11)),
      child: Icon(icon, size: 20, color: Pal.onAccent),
    );
    final words = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: body(context, 16, w: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(text, style: body(context, 13.5, color: p.sub)),
      ],
    );
    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (dismiss.isNotEmpty) ...[
          TextAction(dismiss, color: p.sub, onTap: onDismiss),
          const SizedBox(width: 14),
        ],
        _Pill(action, onTap: onAction),
      ],
    );
    if (strip) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: DecoratedBox(
          decoration: ShapeDecoration(color: p.fill, shape: squircle(20)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(
              children: [
                mark,
                const SizedBox(width: 12),
                Expanded(child: words),
                const SizedBox(width: 12),
                actions,
              ],
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Plate(
        padding: const EdgeInsets.fromLTRB(16, 14, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                mark,
                const SizedBox(width: 12),
                Expanded(child: words),
              ],
            ),
            const SizedBox(height: 10),
            Align(alignment: Alignment.centerRight, child: actions),
          ],
        ),
      ),
    );
  }
}

/// Banks and UPI apps refuse payments while any accessibility switch is on,
/// and the way out is Levels' notification ("Pause for a payment"). Said
/// once after setup; and while notifications are off, said until they are
/// allowed or the user says not now, because without them Android hides
/// that button and the only fix is here.
class _PayCard extends StatelessWidget {
  const _PayCard({this.strip = false});
  final bool strip;

  @override
  Widget build(BuildContext context) {
    if (!model.notifOk) {
      return _Notice(
        strip: strip,
        icon: CupertinoIcons.bell_fill,
        title: "Allow Levels' notification",
        text:
            'Its Pause for a payment button is how you pay with Google Pay '
            'or a bank app. Android hides it until you allow notifications.',
        action: 'Allow',
        onAction: () async {
          await Native.askNotif();
          await model.refreshStatus();
        },
        dismiss: 'Not now',
        onDismiss: () {
          model.put('payTipSeen', true);
          model.put('notifCardHidden', true);
        },
      );
    }
    return _Notice(
      strip: strip,
      icon: CupertinoIcons.creditcard_fill,
      title: 'Paying with a bank app?',
      text:
          'Banks may block payments while Levels is on. Pull down the shade '
          "and tap Pause for a payment in Levels' notification.",
      action: 'Got it',
      onAction: () => model.put('payTipSeen', true),
      dismiss: '',
      onDismiss: () {},
    );
  }
}

class _BatteryCard extends StatelessWidget {
  const _BatteryCard({this.strip = false});

  /// One line at the top of the desktop apps panel.
  final bool strip;

  @override
  Widget build(BuildContext context) {
    // 'ask': Android's own switch. 'oem': the phone maker's switch, which
    // on these brands stops Levels even with Android's switch on.
    final oem = model.batteryStep == 'oem';
    final brand = Model.oemBrand[model.oem] ?? 'this phone';
    return _Notice(
      strip: strip,
      icon: CupertinoIcons.battery_25,
      title: oem ? 'One more switch on $brand' : 'Keep Levels running',
      text: oem
          ? Model.oemPath[model.oem] ??
                'Settings › Battery › Levels › allow background use'
          : 'Your phone may stop Levels to save battery, and then every app '
                'plays at media volume.',
      action: oem ? 'Open settings' : 'Allow',
      onAction: () {
        if (oem) {
          Native.batteryOem();
        } else {
          model.put('batteryAsked', true);
          Native.batteryAsk();
        }
      },
      dismiss: oem ? 'Done' : 'Not now',
      onDismiss: () =>
          model.put(oem ? 'batteryOemDone' : 'batteryHidden', true),
    );
  }
}

/// Paying, without the notification: banks refuse while Levels is on, so this
/// steps it aside after one confirm. Coming back is the Home card's
/// Turn back on.
class _PayRow extends StatelessWidget {
  const _PayRow();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 22),
    child: Plate(
      child: Tile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: ShapeDecoration(color: Pal.accent, shape: squircle(12)),
          child: Icon(
            CupertinoIcons.creditcard_fill,
            size: 20,
            color: Pal.onAccent,
          ),
        ),
        title: 'Paying with a bank app?',
        subtitle: 'Turn Levels off before you pay',
        chevron: true,
        onTap: () async {
          final ok = await showGlassConfirm(
            context,
            title: 'Turn off for a payment?',
            text: 'Banks may block payments while Levels is on.',
            action: 'Turn off',
          );
          if (ok == true) await Native.payPause();
        },
      ),
    ),
  );
}

/// The last row of Your apps: add another. In the list, where the eye
/// already is, instead of a floating button over the content.
class _AddRow extends StatelessWidget {
  const _AddRow({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tile(
    leading: Container(
      width: 30,
      height: 30,
      decoration: ShapeDecoration(
        color: Pal.accent,
        shape: CircleBorder(),
      ),
      child: Icon(CupertinoIcons.add, size: 17, color: Pal.onAccent),
    ),
    title: 'Add an app',
    onTap: onTap,
  );
}

/// A small matte accent pill for a card's one action.
class _Pill extends StatelessWidget {
  const _Pill(this.label, {required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        alignment: Alignment.center,
        decoration: ShapeDecoration(
          color: Pal.accent,
          shape: StadiumBorder(),
        ),
        child: Text(
          label,
          style: body(context, 14.5, w: FontWeight.w600, color: Pal.onAccent),
        ),
      ),
    ),
  );
}

/// Groups and app types: one wide tile under the list.
class _AutoTile extends StatelessWidget {
  const _AutoTile({required this.summary, required this.onTap});
  final String summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Plate(
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: ShapeDecoration(
                  color: Pal.accent,
                  shape: squircle(12),
                ),
                child: Icon(
                  CupertinoIcons.square_grid_2x2_fill,
                  size: 20,
                  color: Pal.onAccent,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Groups and app types',
                      style: body(context, 17, w: FontWeight.w600),
                    ),
                    Text(summary, style: body(context, 14, color: p.sub)),
                  ],
                ),
              ),
              Icon(CupertinoIcons.chevron_forward, size: 16, color: p.faint),
            ],
          ),
        ),
      ),
    );
  }
}

/// The service is off: the dial sits empty, and the one thing to do is
/// said plainly under it.
class _Setup extends StatelessWidget {
  const _Setup({this.wide = false, this.fill = false});
  final bool wide;

  /// Fill a full-height side pane, content centred in it.
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return _HeroFrame(
      fill: fill,
      padding: wide || fill
          ? const EdgeInsets.fromLTRB(20, 22, 20, 20)
          : const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Builder(
        builder: (context) {
          final dial = Dial(
            value: 0,
            size: fill
                ? _HeroSpace.dial(context, reserve: 200)
                : (wide ? 190 : 132),
            enabled: false,
            child: Icon(CupertinoIcons.power, size: 34, color: p.sub),
          );
          final words = [
            Text(
              'Levels is off',
              style: display(context, wide ? 24 : 21),
            ),
            const SizedBox(height: 6),
            Text(
              'Tap Turn on, then Levels, On, Allow.',
              textAlign: wide ? TextAlign.start : TextAlign.center,
              style: body(context, 15, color: p.sub),
            ),
            SizedBox(height: wide ? 18 : 12),
            _Fit(
              true,
              PrimaryButton(
                'Turn on',
                onTap: Native.openAccessibility,
              ),
            ),
            SizedBox(height: wide ? 10 : 4),
            // Android 13+ greys the switch out for an app installed outside
            // Play ("Restricted setting"); say how to lift it.
            TextAction(
              'Switch greyed out?',
              color: p.sub,
              onTap: () async {
                final ok = await showGlassConfirm(
                  context,
                  title: 'Switch greyed out?',
                  text:
                      'Android locks this switch for apps installed outside '
                      'Play. Open App info, tap the three dots at the top, '
                      'then Allow restricted settings. Then turn Levels on.',
                  action: 'Open App info',
                );
                if (ok == true) Native.appInfo();
              },
            ),
          ];
          if (!wide) {
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [dial, const SizedBox(height: 8), ...words],
            );
          }
          return Row(
            children: [
              dial,
              const SizedBox(width: 32),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: words,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// What is happening right now: the app in front on the dial, at its level,
/// and why. A switch pauses Levels for every app.
class _Now extends StatelessWidget {
  const _Now({this.wide = false, this.fill = false});
  final bool wide;

  /// Fill a full-height side pane, content centred in it.
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final live = model.live;
    final pkg = live['pkg'] as String?;
    final managed = live['managed'] == true;
    final level = (live['level'] as num?)?.toInt() ?? 0;
    final paused = !model.enabled;
    final self = pkg == null || pkg == 'com.blessing.levels';

    final device = switch (model.device) {
      'bt' => model.btName ?? 'Bluetooth',
      'wired' => 'Wired headphones',
      _ => 'Phone speaker',
    };

    final String caption;
    final String why;
    if (paused) {
      final until = model.pausedUntil;
      caption = until == null ? 'Paused' : 'Paused until ${hm(until)}';
      why = 'Every app plays at your level';
    } else if (self) {
      // "Your level" read as jargon: say what it is.
      caption = 'Media volume';
      why = 'What apps with no level of their own play at';
    } else {
      caption = live['label'] as String? ?? pkg;
      why = managed
          ? '${live['why'] ?? 'Its own level'}'
          : 'No level set · plays at yours';
    }

    final dial = Builder(
      builder: (context) => Dial(
        value: paused ? 0 : level,
        size: fill ? _HeroSpace.dial(context) : (wide ? 200 : 140),
        enabled: !paused,
        // Drag to change the volume now. On an app with its own level the
        // new one is kept for that app.
        onChanged: paused
            ? null
            : (v) {
                model.setLiveLevel(v);
                Native.volume(v);
              },
        onDone: paused || self || !managed || model.app(pkg) == null
            ? null
            : (v) {
                model.app(pkg)!['vol'] = v;
                model.commit(now: true);
              },
        child: AnimatedSwitcher(
          duration: motion(context, 280),
          child: Column(
            key: ValueKey('$pkg$paused'),
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!self && !paused)
                AppIcon(pkg, size: 40)
              else
                Icon(
                  paused
                      ? CupertinoIcons.pause_fill
                      : CupertinoIcons.house_fill,
                  size: 28,
                  color: p.sub,
                ),
              const SizedBox(height: 6),
              Text(
                paused ? '—' : levelText(level),
                style: display(
                  context,
                  26,
                ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ],
          ),
        ),
      ),
    );
    final words = <Widget>[
      Text(caption, style: display(context, wide || fill ? 21 : 18)),
      const SizedBox(height: 2),
      Text(
        why,
        textAlign: wide ? TextAlign.start : TextAlign.center,
        style: body(context, wide || fill ? 14 : 13, color: p.sub),
      ),
      if (!self && !paused && !managed) ...[
        SizedBox(height: wide ? 14 : 10),
        _Fit(
          wide,
          PrimaryButton(
            'Give it a level',
            onTap: () {
              model.ensureApp(pkg);
              model.commit(now: true);
              go(context, AppDetail(pkg));
            },
          ),
        ),
      ],
    ];

    return _HeroFrame(
      fill: fill,
      padding: wide || fill
          ? const EdgeInsets.fromLTRB(20, 16, 16, 20)
          : const EdgeInsets.fromLTRB(16, 12, 14, 14),
      child: Column(
        // Filling a pane: the status line stays at the top and the dial sits
        // in the middle of what is left, with the same space under it.
        mainAxisAlignment: fill
            ? MainAxisAlignment.spaceBetween
            : MainAxisAlignment.start,
        children: [
          Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: paused ? p.faint : p.good,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${paused ? 'Paused' : 'Running'}  ·  $device',
                  style: body(context, 13.5, color: p.sub),
                ),
              ),
              // A size down on a phone, to match the rows below.
              Transform.scale(
                scale: wide || fill ? 1 : 0.85,
                alignment: Alignment.centerRight,
                child: Toggle(
                  value: model.enabled,
                  onChanged: (v) async {
                    if (v) {
                      model.enabled = true;
                      return;
                    }
                    final m = await showPauseSheet(context);
                    if (m != null) model.pause(m);
                  },
                ),
              ),
            ],
          ),
          SizedBox(height: fill ? 0 : (wide ? 14 : 4)),
          if (fill)
            Column(children: [dial, const SizedBox(height: 10), ...words])
          else if (wide)
            Row(
              children: [
                dial,
                const SizedBox(width: 32),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: words,
                  ),
                ),
              ],
            )
          else ...[
            dial,
            const SizedBox(height: 14),
            ...words,
          ],
          if (fill) const SizedBox(height: 16),
        ],
      ),
    );
  }
}

/// One app in the list: who it is on top, its level right under it.
///
/// The level is set here, in the list, without opening anything: drag the
/// slider, or tap the speaker to mute and tap again for the level it had.
/// The name opens the app's full page (rules, volume keys).
class _AppRow extends StatelessWidget {
  const _AppRow(this.pkg);
  final String pkg;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final a = model.ensureApp(pkg);
    final on = a['on'] != false;
    final vol = (a['vol'] as num?)?.toInt() ?? 50;
    final rules = model.rules(pkg).length;
    final sub = !on
        ? 'Paused'
        : rules == 0
        ? 'Plays at this level'
        : 'Plays at this level · $rules ${rules == 1 ? 'rule' : 'rules'}';
    final muted = vol == 0;

    void set(int v) {
      a['vol'] = v;
      model.commit();
    }

    final name = model.labelOf(pkg);
    final row = Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            label: '${model.labelOf(pkg)}, more settings',
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => go(context, AppDetail(pkg)),
              child: Row(
                children: [
                  Opacity(
                    opacity: on ? 1 : 0.45,
                    child: AppIcon(pkg, size: 30),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(model.labelOf(pkg), style: body(context, 17)),
                        Text(sub, style: body(context, 13.5, color: p.sub)),
                      ],
                    ),
                  ),
                  Icon(
                    CupertinoIcons.chevron_forward,
                    size: 16,
                    color: p.faint,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _MuteButton(
                muted: muted,
                enabled: on,
                onTap: () {
                  if (muted) {
                    set((a['unmute'] as num?)?.toInt() ?? 50);
                  } else {
                    a['unmute'] = vol;
                    set(0);
                  }
                },
              ),
              const SizedBox(width: 10),
              Expanded(
                child: LevelSlider(
                  value: vol,
                  icon: false,
                  height: 32,
                  enabled: on,
                  onChanged: set,
                ),
              ),
              const SizedBox(width: 10),
              // On or off for this app, right in the list; a size down so
              // the row stays light beside its slim bar.
              Transform.scale(
                scale: 0.85,
                child: Toggle(
                  value: on,
                  onChanged: (v) {
                    a['on'] = v;
                    model.commit(now: true);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
    // Swipe left to remove, after asking.
    return Dismissible(
      key: ValueKey('row-$pkg'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(CupertinoIcons.trash, size: 18, color: p.danger),
            const SizedBox(width: 8),
            Text(
              'Remove',
              style: body(context, 15, w: FontWeight.w600, color: p.danger),
            ),
          ],
        ),
      ),
      confirmDismiss: (_) => showGlassConfirm(
        context,
        title: 'Remove $name?',
        text: '$name will play at your level again. Its rules go too.',
        action: 'Remove',
      ),
      onDismissed: (_) => model.removeApp(pkg),
      child: row,
    );
  }
}

/// A round glass button with the speaker: mutes the app's level, or gives
/// it back.
class _MuteButton extends StatelessWidget {
  const _MuteButton({
    required this.muted,
    required this.enabled,
    required this.onTap,
  });
  final bool muted;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Semantics(
      button: true,
      label: muted ? 'Unmute' : 'Mute',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: motion(context, 200),
          curve: Curves.easeOutCubic,
          width: 32,
          height: 32,
          decoration: ShapeDecoration(
            // Clear, not wheat: on this screen wheat means the level.
            shape: CircleBorder(side: BorderSide(color: p.line)),
            color: muted ? p.fill : null,
          ),
          child: Icon(
            muted
                ? CupertinoIcons.speaker_slash_fill
                : CupertinoIcons.speaker_2_fill,
            size: 15,
            color: muted ? p.faint : p.sub,
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    // No button here: the round + below is the one way to add, so the
    // empty list only points to it.
    return Semantics(
      button: true,
      label: 'Add an app',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onAdd,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          child: Row(
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: motion(context, 900),
                builder: (context, t, _) => BarsMark(size: 44, t: t),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'No apps yet',
                      style: body(context, 17, w: FontWeight.w600),
                    ),
                    Text(
                      'Tap to add the apps that are always too loud, or '
                      'too quiet.',
                      style: body(context, 14, color: p.sub),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Beside the dial on a wide screen a button keeps a natural width instead
/// of stretching across the card.
class _Fit extends StatelessWidget {
  const _Fit(this.wide, this.child);
  final bool wide;
  final Widget child;

  @override
  Widget build(BuildContext context) => wide
      ? ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: child,
        )
      : child;
}

/// How tall the full-height hero pane is, so its dial can fit the space.
class _HeroSpace extends InheritedWidget {
  const _HeroSpace({required this.height, required super.child});
  final double height;

  /// The dial's size in a pane: what is left after the status line, the
  /// words and the button, between 150 and 250.
  static double dial(BuildContext context, {double reserve = 210}) {
    final h = context.dependOnInheritedWidgetOfExactType<_HeroSpace>()?.height;
    if (h == null) return 250;
    return (h - reserve).clamp(150.0, 250.0);
  }

  @override
  bool updateShouldNotify(_HeroSpace old) => old.height != height;
}

/// The hero card: in the list, or filling a side pane with its content
/// centred (scrolling only if the window is too short for it).
class _HeroFrame extends StatelessWidget {
  const _HeroFrame({
    required this.fill,
    required this.padding,
    required this.child,
  });
  final bool fill;
  final EdgeInsets padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!fill) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 22),
        child: Plate(radius: 28, padding: padding, child: child),
      );
    }
    // Never scrolls: the dial takes what height is left after the words
    // (_HeroSpace), and only on a very short window does the card scale.
    const natural = 420.0;
    return Plate(
      radius: 28,
      child: LayoutBuilder(
        builder: (context, box) => _HeroSpace(
          height: box.maxHeight,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: SizedBox(
              width: box.maxWidth,
              height: box.maxHeight < natural ? natural : box.maxHeight,
              child: Padding(padding: padding, child: child),
            ),
          ),
        ),
      ),
    );
  }
}

String hm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// How long to pause, in minutes; 0 is until turned back on. The choice is
/// also what the shade's tile uses.
Future<int?> showPauseSheet(BuildContext context) {
  final now = DateTime.now();
  var morning = DateTime(now.year, now.month, now.day, 7);
  if (!morning.isAfter(now)) morning = morning.add(const Duration(days: 1));
  final toMorning = morning.difference(now).inMinutes;
  final options = <(int, String, String)>[
    (
      15,
      '15 minutes',
      'Back on at ${hm(now.add(const Duration(minutes: 15)))}',
    ),
    (60, '1 hour', 'Back on at ${hm(now.add(const Duration(hours: 1)))}'),
    (toMorning, 'Until morning', 'Back on at 07:00'),
    (0, 'Until I turn it on', 'Stays paused'),
  ];
  return showGlassSheet<int>(
    context,
    builder: (ctx) {
      final p = Pal.of(ctx);
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Pause Levels', style: display(ctx, 24)),
            const SizedBox(height: 4),
            Text(
              'Every app plays at your level until then.',
              style: body(ctx, 14.5, color: p.sub),
            ),
            const SizedBox(height: 14),
            Section(
              children: [
                for (final (m, title, sub) in options)
                  Tile(
                    title: title,
                    subtitle: sub,
                    onTap: () => Navigator.of(ctx).pop(m),
                  ),
              ],
            ),
          ],
        ),
      );
    },
  );
}

/// The last cell of the apps panel: laid out like an app card, so it is the
/// same height, with a button where an app has its slider.
class _AddCell extends StatelessWidget {
  const _AddCell({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Semantics(
      button: true,
      label: 'Add an app',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: ShapeDecoration(
                      color: Pal.accent,
                      shape: CircleBorder(),
                    ),
                    child: Icon(
                      CupertinoIcons.add,
                      size: 18,
                      color: Pal.onAccent,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Add an app', style: body(context, 17)),
                        Text(
                          'Give another app its own level',
                          style: body(context, 13.5, color: p.sub),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                height: 38,
                alignment: Alignment.center,
                decoration: ShapeDecoration(
                  shape: StadiumBorder(side: BorderSide(color: p.line)),
                ),
                child: Text(
                  'Choose an app',
                  style: body(
                    context,
                    14.5,
                    w: FontWeight.w600,
                    color: p.accentText,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Desktop, under the dial: four quiet shortcuts, two by two, at a fixed
/// height so the left pane always ends where the right one does.
class _Shortcuts extends StatelessWidget {
  const _Shortcuts({required this.summary});
  final String summary;

  // Two only: Settings is the gear up top and Pause is the card's switch.
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 64,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _Shortcut(
            icon: CupertinoIcons.square_grid_2x2_fill,
            title: 'Groups',
            onTap: () => go(context, const Categories()),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _Shortcut(
            icon: CupertinoIcons.clock_fill,
            title: 'Activity',
            onTap: () => go(context, const Activity()),
          ),
        ),
      ],
    ),
  );
}

class _Shortcut extends StatelessWidget {
  const _Shortcut({
    required this.icon,
    required this.title,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: title,
    excludeSemantics: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Plate(
        radius: 18,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: ShapeDecoration(
                color: Pal.accent,
                shape: squircle(10),
              ),
              child: Icon(icon, size: 16, color: Pal.onAccent),
            ),
            const SizedBox(width: 12),
            Text(title, style: body(context, 15.5, w: FontWeight.w600)),
          ],
        ),
      ),
    ),
  );
}

/// Desktop, right: your apps in one full-height panel. The frame never
/// changes with the number of apps; the cards inside fill it two across
/// and scroll within it.
class _AppsPanel extends StatelessWidget {
  const _AppsPanel({
    required this.apps,
    required this.footer,
    required this.onAdd,
    this.battery = false,
    this.pay = false,
  });
  final List<String> apps;
  final String footer;
  final VoidCallback onAdd;
  final bool battery;
  final bool pay;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    Widget cell(Widget child) => DecoratedBox(
      decoration: ShapeDecoration(color: p.fill, shape: squircle(20)),
      child: child,
    );
    final cells = <Widget>[
      for (var i = 0; i < apps.length; i++)
        EntranceIn(index: i, child: cell(_AppRow(apps[i]))),
      cell(_AddCell(onTap: onAdd)),
    ];
    return Plate(
      radius: 28,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('Your apps', style: display(context, 22)),
              const SizedBox(width: 10),
              if (apps.isNotEmpty)
                Text('${apps.length}', style: body(context, 15, color: p.sub)),
              const Spacer(),
              TextAction('Add', icon: CupertinoIcons.add, onTap: onAdd),
            ],
          ),
          const SizedBox(height: 14),
          if (pay) const _PayCard(strip: true),
          if (battery) const _BatteryCard(strip: true),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                for (var i = 0; i < cells.length; i += 2)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: cells[i]),
                        const SizedBox(width: 12),
                        Expanded(
                          child: i + 1 < cells.length
                              ? cells[i + 1]
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(footer, style: body(context, 13, color: p.sub)),
        ],
      ),
    );
  }
}
