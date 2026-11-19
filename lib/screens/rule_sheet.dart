import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../ui/glass_chrome.dart';
import '../ui/kit.dart';

/// Add or edit a rule. Returns the rule, `{}` to delete it, or null when the
/// sheet is dismissed.
Future<Map<String, dynamic>?> showRuleSheet(
  BuildContext context, {
  required int base,
  Map<String, dynamic>? initial,
  bool editing = false,
  bool canGoFirst = false,
}) {
  return showGlassSheet<Map<String, dynamic>>(
    context,
    builder: (ctx) => _RuleSheet(
      base: base,
      initial: initial,
      editing: editing,
      canGoFirst: canGoFirst,
    ),
  );
}

class _RuleSheet extends StatefulWidget {
  const _RuleSheet({
    required this.base,
    this.initial,
    required this.editing,
    this.canGoFirst = false,
  });
  final int base;
  final Map<String, dynamic>? initial;
  final bool editing;

  /// Offer to move this rule to the top: when several match, the first wins.
  final bool canGoFirst;

  @override
  State<_RuleSheet> createState() => _RuleSheetState();
}

class _RuleSheetState extends State<_RuleSheet> {
  late int _vol = (widget.initial?['vol'] as num?)?.toInt() ?? widget.base;
  late String _device = widget.initial?['device'] as String? ?? 'any';
  late String _from = widget.initial?['from'] as String? ?? '';
  late String _to = widget.initial?['to'] as String? ?? '';
  late bool _timed = _from.isNotEmpty && _to.isNotEmpty;
  late String _when = widget.initial?['when'] as String? ?? '';
  late final Set<int> _days = {
    ...((widget.initial?['days'] as List?)?.cast<int>() ?? const []),
  };
  String? _editing; // 'from' | 'to'

  bool get _someDays => _days.isNotEmpty && _days.length < 7;
  bool get _valid =>
      _device != 'any' || _timed || _when.isNotEmpty || _someDays;

  DateTime _asTime(String hm, String fallback) {
    final parts = (hm.isEmpty ? fallback : hm).split(':');
    return DateTime(2000, 1, 1, int.parse(parts[0]), int.parse(parts[1]));
  }

  String _fmt(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Widget _dayChip(BuildContext context, int d) {
    final p = Pal.of(context);
    const names = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    const full = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    final on = _days.contains(d);
    return Semantics(
      button: true,
      selected: on,
      label: full[d - 1],
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () => setState(() => on ? _days.remove(d) : _days.add(d)),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 40,
          alignment: Alignment.center,
          decoration: ShapeDecoration(
            color: on ? Pal.accent : p.fill,
            shape: const StadiumBorder(),
          ),
          child: Text(
            names[d - 1],
            style: body(
              context,
              14,
              w: FontWeight.w600,
              color: on ? Pal.onAccent : p.sub,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    Widget label(String t) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
      child: Text(
        t.toUpperCase(),
        style: body(
          context,
          12.5,
          w: FontWeight.w600,
          color: p.sub,
        ).copyWith(letterSpacing: 0.6),
      ),
    );

    Widget timeChip(String which, String value) {
      final selected = _editing == which;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _editing = selected ? null : which),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: selected ? Pal.accent.withValues(alpha: 0.14) : p.fill,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? Pal.accent : Colors.transparent,
                width: 1.2,
              ),
            ),
            child: Column(
              children: [
                Text(
                  which == 'from' ? 'From' : 'Until',
                  style: body(context, 12.5, color: p.sub),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style:
                      display(
                        context,
                        22,
                        color: selected ? p.accentText : p.ink,
                      ).copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.editing ? 'Edit rule' : 'New rule',
            style: display(context, 24),
          ),
          label('Level'),
          LevelSlider(value: _vol, onChanged: (v) => setState(() => _vol = v)),
          label('When sound plays through'),
          Segmented<String>(
            value: _device,
            items: const [
              ('any', 'Any'),
              ('speaker', 'Speaker'),
              ('wired', 'Wired'),
              ('bt', 'Bluetooth'),
            ],
            onChanged: (v) => setState(() => _device = v),
          ),
          label('Time of day'),
          Segmented<bool>(
            value: _timed,
            items: const [(false, 'All day'), (true, 'Between')],
            onChanged: (v) => setState(() {
              _timed = v;
              if (v && _from.isEmpty) {
                _from = '22:00';
                _to = '07:00';
              }
              if (!v) _editing = null;
            }),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: !_timed
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            timeChip('from', _from),
                            const SizedBox(width: 10),
                            timeChip('to', _to),
                          ],
                        ),
                        if (_editing != null)
                          SizedBox(
                            height: 170,
                            child: CupertinoTheme(
                              data: CupertinoThemeData(
                                brightness: p.dark
                                    ? Brightness.dark
                                    : Brightness.light,
                              ),
                              child: CupertinoDatePicker(
                                key: ValueKey(_editing),
                                mode: CupertinoDatePickerMode.time,
                                use24hFormat: true,
                                minuteInterval: 5,
                                initialDateTime: _asTime(
                                  _editing == 'from' ? _from : _to,
                                  _editing == 'from' ? '22:00' : '07:00',
                                ),
                                onDateTimeChanged: (t) => setState(() {
                                  if (_editing == 'from') {
                                    _from = _fmt(t);
                                  } else {
                                    _to = _fmt(t);
                                  }
                                }),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
          label('Only while'),
          Segmented<String>(
            value: _when,
            items: const [
              ('', 'Always'),
              ('charging', 'Charging'),
              ('quiet', 'Silent'),
              ('lowBattery', 'Low battery'),
            ],
            onChanged: (v) => setState(() => _when = v),
          ),
          label('Days'),
          Row(
            children: [
              for (var d = 1; d <= 7; d++) ...[
                if (d > 1) const SizedBox(width: 6),
                Expanded(child: _dayChip(context, d)),
              ],
            ],
          ),
          const SizedBox(height: 10),
          AnimatedOpacity(
            opacity: _valid ? 0 : 1,
            duration: const Duration(milliseconds: 160),
            child: Text(
              'Pick at least one condition, or the rule would always win.',
              textAlign: TextAlign.center,
              style: body(context, 13, color: p.sub),
            ),
          ),
          const SizedBox(height: 12),
          AnimatedOpacity(
            opacity: _valid ? 1 : 0.4,
            duration: const Duration(milliseconds: 160),
            child: IgnorePointer(
              ignoring: !_valid,
              child: PrimaryButton(
                widget.editing ? 'Save' : 'Add rule',
                onTap: () => Navigator.of(context).pop(<String, dynamic>{
                  'vol': _vol,
                  'device': _device,
                  if (_timed) 'from': _from,
                  if (_timed) 'to': _to,
                  if (_when.isNotEmpty) 'when': _when,
                  if (_someDays) 'days': (_days.toList()..sort()),
                }),
              ),
            ),
          ),
          if (widget.canGoFirst) ...[
            const SizedBox(height: 6),
            Center(
              child: TextAction(
                'Check this rule first',
                icon: CupertinoIcons.arrow_up_to_line,
                onTap: () => Navigator.of(
                  context,
                ).pop(<String, dynamic>{...?widget.initial, '_first': true}),
              ),
            ),
          ],
          if (widget.editing) ...[
            const SizedBox(height: 6),
            Center(
              child: TextAction(
                'Delete rule',
                color: p.danger,
                onTap: () => Navigator.of(context).pop(<String, dynamic>{}),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
