import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/model.dart';
import '../core/native.dart';
import '../ui/kit.dart';
import '../ui/motion.dart';

/// Choose an app. Search first; then the apps most people set (video,
/// games, social, music) that are not set yet; then everything.
class Picker extends StatefulWidget {
  const Picker({
    super.key,
    this.multi = false,
    this.selected = const {},
    this.title,
    this.unsetOnly = false,
  });
  final bool multi;

  /// Overrides the bar title.
  final String? title;

  /// Only apps with no level in Levels (the pill's "Hidden in" list).
  final bool unsetOnly;
  final Set<String> selected;

  @override
  State<Picker> createState() => _PickerState();
}

class _PickerState extends State<Picker> {
  String _q = '';
  late final Set<String> _sel = {...widget.selected};
  List<AppInfo> _apps = model.apps;

  @override
  void initState() {
    super.initState();
    if (_apps.isEmpty) {
      Native.apps().then((a) {
        if (mounted) setState(() => _apps = a);
      });
    }
  }

  void _pick(String pkg) {
    if (widget.multi) {
      setState(() => _sel.contains(pkg) ? _sel.remove(pkg) : _sel.add(pkg));
    } else {
      Navigator.of(context).pop(pkg);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final q = _q.trim().toLowerCase();
    final managed = model.appMap.keys.toSet();
    final all = _apps
        .where((a) => q.isEmpty || a.label.toLowerCase().contains(q))
        .where((a) => !widget.unsetOnly || !managed.contains(a.pkg))
        .toList();
    final suggested = q.isEmpty && !widget.multi
        ? all
              .where(
                (a) =>
                    !managed.contains(a.pkg) &&
                    const {'video', 'game', 'social', 'audio'}.contains(a.cat),
              )
              .take(6)
              .toList()
        : <AppInfo>[];

    Widget row(AppInfo a) {
      final has = managed.contains(a.pkg);
      final picked = _sel.contains(a.pkg);
      return Tile(
        leading: AppIcon(a.pkg, size: 34),
        title: a.label,
        subtitle: widget.multi
            ? null
            : has
            ? 'Already set · ${levelText((model.app(a.pkg)?['vol'] as num?)?.toInt() ?? 50)}'
            : a.cat == null
            ? null
            : Model.catName(a.cat!),
        trailing: widget.multi
            ? AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                child: Icon(
                  picked
                      ? CupertinoIcons.checkmark_circle_fill
                      : CupertinoIcons.circle,
                  key: ValueKey(picked),
                  color: picked ? Pal.accent : p.faint,
                  size: 24,
                ),
              )
            : null,
        chevron: !widget.multi,
        onTap: () => _pick(a.pkg),
      );
    }

    final search = Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Plate(
        radius: 18,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            Icon(CupertinoIcons.search, size: 19, color: p.sub),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                onChanged: (v) => setState(() => _q = v),
                style: body(context, 16),
                decoration: InputDecoration(
                  hintText: 'Search apps',
                  hintStyle: body(context, 16, color: p.faint),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    final desk = isSplitLayout(context);

    // A desktop window lays each list out two across, so both columns
    // carry the same rows and end together.
    List<Widget> rows(List<AppInfo> list) {
      if (!desk) return [for (final a in list) row(a)];
      return [
        for (var i = 0; i < list.length; i += 2)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: row(list[i])),
                Container(width: 0.5, color: p.line),
                Expanded(
                  child: i + 1 < list.length
                      ? row(list[i + 1])
                      : const SizedBox(),
                ),
              ],
            ),
          ),
      ];
    }

    return Screen(
      title: widget.title ?? (widget.multi ? 'Choose apps' : 'Add an app'),
      actions: [
        if (widget.multi)
          TextAction('Done', onTap: () => Navigator.of(context).pop(_sel)),
      ],
      panel: true,
      panelWidth: 1200,
      children: [
        search,
        if (_apps.isEmpty)
          const Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: CupertinoActivityIndicator()),
          )
        else if (all.isEmpty)
          Padding(
            padding: const EdgeInsets.all(30),
            child: Center(
              child: Text(
                'No app called “$_q”',
                style: body(context, 15, color: p.sub),
              ),
            ),
          )
        else ...[
          if (suggested.isNotEmpty)
            Section(title: 'Suggested', children: rows(suggested)),
          Section(
            title: q.isEmpty ? 'All apps' : 'Results',
            children: rows(all),
          ),
        ],
      ],
    );
  }
}
