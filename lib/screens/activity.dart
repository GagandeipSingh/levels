import 'package:flutter/cupertino.dart';

import '../core/native.dart';
import '../ui/kit.dart';
import 'app_detail.dart' show showGlassConfirm;

/// Every change Levels made, newest first, so a surprise has an answer.
class Activity extends StatefulWidget {
  const Activity({super.key});

  @override
  State<Activity> createState() => _ActivityState();
}

class _ActivityState extends State<Activity> {
  List<Map<String, dynamic>>? _log;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final l = await Native.log();
    if (mounted) setState(() => _log = l.reversed.toList());
  }

  String _day(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(d.year, d.month, d.day);
    final diff = today.difference(that).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    const m = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${d.day} ${m[d.month - 1]}';
  }

  String _time(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final log = _log;
    final byDay = <String, List<Map<String, dynamic>>>{};
    for (final e in log ?? const <Map<String, dynamic>>[]) {
      final d = DateTime.fromMillisecondsSinceEpoch((e['t'] as num).toInt());
      byDay.putIfAbsent(_day(d), () => []).add(e);
    }
    return Screen(
      title: 'Activity',
      panel: true,
      empty: log != null && log.isEmpty ? const _EmptyActivity() : null,
      actions: [
        if (log != null && log.isNotEmpty)
          TextAction(
            'Clear',
            onTap: () async {
              final ok = await showGlassConfirm(
                context,
                title: 'Clear activity?',
                text: 'Your levels and rules stay. Only this list is cleared.',
                action: 'Clear',
              );
              if (ok == true) {
                await Native.clearLog();
                _load();
              }
            },
          ),
      ],
      children: [
        if (log == null)
          const Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: CupertinoActivityIndicator()),
          )
        else if (log.isNotEmpty)
          for (final day in byDay.entries)
            Section(
              title: day.key,
              children: [
                for (final e in day.value)
                  Tile(
                    leading: AppIcon(e['pkg'] as String, size: 32),
                    title:
                        '${e['label']}  ${e['kind'] == 'restore' ? '↩' : '→'}  ${levelText((e['level'] as num).toInt())}',
                    subtitle:
                        '${_time(DateTime.fromMillisecondsSinceEpoch((e['t'] as num).toInt()))} · ${switch (e['kind']) {
                          'restore' => 'Your level, back',
                          'saved' => 'Saved from the pill',
                          _ => e['why'] ?? 'Its level',
                        }}',
                  ),
              ],
            ),
      ],
    );
  }
}

/// Nothing logged yet: a faded sample of what the list will hold, so the
/// space says what it is for instead of sitting empty.
class _EmptyActivity extends StatelessWidget {
  const _EmptyActivity();

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    Widget sample(IconData icon, String title, String sub, double fade) =>
        Opacity(
          opacity: fade,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: ShapeDecoration(
                    color: p.line,
                    shape: squircle(10),
                  ),
                  child: Icon(icon, size: 16, color: p.sub),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: body(context, 15.5)),
                      Text(sub, style: body(context, 13, color: p.sub)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: ShapeDecoration(
              color: Pal.accent,
              shape: CircleBorder(),
            ),
            child: Icon(
              CupertinoIcons.clock_fill,
              size: 30,
              color: Pal.onAccent,
            ),
          ),
          const SizedBox(height: 16),
          Text('Nothing yet', style: display(context, 22)),
          const SizedBox(height: 6),
          Text(
            "Each time Levels sets an app's level, or gives yours back, it "
            'is noted here with the reason.',
            textAlign: TextAlign.center,
            style: body(context, 14.5, color: p.sub),
          ),
          const SizedBox(height: 24),
          DecoratedBox(
            decoration: ShapeDecoration(color: p.fill, shape: squircle(20)),
            child: Column(
              children: [
                sample(
                  CupertinoIcons.play_rectangle_fill,
                  'YouTube  →  70%',
                  '09:41 · Its level',
                  0.75,
                ),
                sample(
                  CupertinoIcons.game_controller_solid,
                  'A game  →  20%',
                  '09:12 · Games',
                  0.5,
                ),
                sample(
                  CupertinoIcons.house_fill,
                  'Your level, back  ↩  45%',
                  '09:05 · When you left',
                  0.28,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
