import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/model.dart';
import '../ui/kit.dart';
import '../ui/motion.dart';
import '../core/native.dart';
import 'app_detail.dart' show AppDetail, showGlassConfirm;
import 'picker.dart';

IconData catIcon(String k) => switch (k) {
  'game' => CupertinoIcons.game_controller_solid,
  'video' => CupertinoIcons.film_fill,
  'social' => CupertinoIcons.chat_bubble_2_fill,
  'audio' => CupertinoIcons.music_note_2,
  'news' => CupertinoIcons.news_solid,
  'maps' => CupertinoIcons.map_fill,
  'image' => CupertinoIcons.photo_fill,
  _ => CupertinoIcons.briefcase_fill,
};

/// The installed apps Android files under [k], by name.
List<AppInfo> appsOfType(String k) {
  final list = model.apps.where((a) => a.cat == k).toList();
  list.sort((x, y) => x.label.toLowerCase().compareTo(y.label.toLowerCase()));
  return list;
}

/// A type's mark: matte, wheat while the type has a level, plain when off.
class CatGlyph extends StatelessWidget {
  const CatGlyph(this.k, {super.key, this.on = false});
  final String k;
  final bool on;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      width: 36,
      height: 36,
      decoration: ShapeDecoration(
        color: on ? Pal.accent : p.fill,
        shape: squircle(11),
      ),
      child: Icon(catIcon(k), size: 18, color: on ? Pal.onAccent : p.sub),
    );
  }
}

class Categories extends StatelessWidget {
  const Categories({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) {
        final groups = model.groups;
        return Screen(
          title: 'Automatic',
          panes: [
            [
              Section(
                title: 'Your groups',
                trailing: TextAction(
                  'New',
                  icon: CupertinoIcons.add,
                  onTap: () {
                    go(context, const GroupEditor());
                  },
                ),
                footer:
                    'Put apps together, such as Work or Kids, and give them one level.',
                children: groups.isEmpty
                    ? [
                        Tile(
                          leading: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: Pal.of(context).fill,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              CupertinoIcons.folder_fill,
                              size: 18,
                              color: Pal.of(context).sub,
                            ),
                          ),
                          title: 'No groups yet',
                          subtitle: 'Tap New to make one',
                        ),
                      ]
                    : [
                        for (var i = 0; i < groups.length; i++)
                          Tile(
                            leading: _Stack(
                              (groups[i]['apps'] as List?)?.cast<String>() ??
                                  const [],
                            ),
                            title: groups[i]['name'] as String? ?? 'Group',
                            subtitle:
                                '${(groups[i]['apps'] as List?)?.length ?? 0} apps${groups[i]['on'] == false ? ' · paused' : ''}',
                            trailing: MiniLevel(
                              (groups[i]['vol'] as num?)?.toInt() ?? 50,
                              dim: groups[i]['on'] == false,
                            ),
                            chevron: true,
                            onTap: () => go(context, GroupEditor(index: i)),
                          ),
                      ],
              ),
              const _Presets(),
            ],
            [
              Section(
                title: 'By app type',
                footer:
                    'For apps with no level of their own, including ones you '
                    'install later. Some apps do not say what type they are; add those yourself.',
                children: [for (final k in Model.catKeys) _CatRow(k)],
              ),
            ],
          ],
          children: const [],
        );
      },
    );
  }
}

class _Stack extends StatelessWidget {
  const _Stack(this.pkgs, {this.size = 34});
  final List<String> pkgs;
  final double size;

  @override
  Widget build(BuildContext context) {
    final shown = pkgs.take(5).toList();
    final step = size * 0.62;
    if (shown.isEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Pal.of(context).fill,
          borderRadius: BorderRadius.circular(size * 0.3),
        ),
      );
    }
    return SizedBox(
      width: size + (shown.length - 1) * step,
      height: size,
      child: Stack(
        children: [
          for (var i = shown.length - 1; i >= 0; i--)
            Positioned(
              left: i * step,
              child: AppIcon(shown[i], size: size),
            ),
        ],
      ),
    );
  }
}

class _CatRow extends StatelessWidget {
  const _CatRow(this.k);
  final String k;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final c = model.cat(k);
    final on = c['on'] == true;
    final vol = (c['vol'] as num?)?.toInt() ?? 50;
    final apps = appsOfType(k);
    final n = apps.length;
    // A desktop pane: the app icons sit beside the switch, so every type is
    // one row and the list ends level with the column beside it.
    final desk = isSplitLayout(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Tile(
          leading: CatGlyph(k, on: on),
          title: Model.catName(k),
          onTap: desk && n > 0 ? () => go(context, TypeApps(k)) : null,
          subtitle: n == 0
              ? 'No apps of this type on this phone'
              : '$n ${n == 1 ? 'app' : 'apps'}${on ? ' · ${levelText(vol)}' : ''}',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (desk && n > 0) ...[
                _Stack(apps.take(4).map((a) => a.pkg).toList(), size: 24),
                const SizedBox(width: 16),
              ],
              Toggle(
                value: on,
                onChanged: (v) {
                  c['on'] = v;
                  model.commit(now: true);
                },
              ),
            ],
          ),
        ),
        // Which apps Android put here, so it is never a guess.
        if (n > 0 && !desk)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => go(context, TypeApps(k)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(65, 0, 14, 12),
              child: Row(
                children: [
                  _Stack(apps.take(5).map((a) => a.pkg).toList(), size: 26),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      n > 5 ? '+${n - 5} more · See all' : 'See all',
                      style: body(
                        context,
                        13.5,
                        w: FontWeight.w600,
                        color: p.accentText,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        AnimatedSize(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          child: on
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                  child: LevelSlider(
                    value: vol,
                    height: 46,
                    onChanged: (v) {
                      c['vol'] = v;
                      model.commit();
                    },
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

/// Every app on the phone that Android files under one type. An app with
/// its own level keeps it; the type only covers the rest.
class TypeApps extends StatelessWidget {
  const TypeApps(this.k, {super.key});
  final String k;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) {
        final apps = appsOfType(k);
        final c = model.cat(k);
        final on = c['on'] == true;
        final vol = (c['vol'] as num?)?.toInt() ?? 50;
        return Screen(
          title: Model.catName(k),
          panel: true,
          children: [
            Section(
              footer:
                  'Android says these apps are ${Model.catName(k).toLowerCase()}. '
                  'An app with its own level keeps it; this type covers the rest. '
                  'An app missing here did not say its type; add it in Your apps.',
              children: [
                for (final a in apps)
                  Tile(
                    leading: AppIcon(a.pkg, size: 34),
                    title: a.label,
                    subtitle: model.app(a.pkg) != null
                        ? 'Own level · ${levelText((model.app(a.pkg)!['vol'] as num?)?.toInt() ?? 50)}'
                        : on
                        ? 'Plays at ${levelText(vol)}'
                        : 'Type is off · plays at your level',
                    chevron: true,
                    onTap: () {
                      model.ensureApp(a.pkg, vol: on ? vol : 50);
                      model.commit(now: true);
                      go(context, AppDetail(a.pkg));
                    },
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// Make or edit a group: a name, a level, the apps in it.
class GroupEditor extends StatefulWidget {
  const GroupEditor({super.key, this.index});
  final int? index;

  @override
  State<GroupEditor> createState() => _GroupEditorState();
}

class _GroupEditorState extends State<GroupEditor> {
  late final Map<String, dynamic> _g = widget.index == null
      ? {
          'id': DateTime.now().millisecondsSinceEpoch.toString(),
          'name': '',
          'vol': 40,
          'on': true,
          'apps': <String>[],
        }
      : Map<String, dynamic>.from(model.groups[widget.index!]);
  late final TextEditingController _name = TextEditingController(
    text: _g['name'] as String,
  );

  List<String> get _apps => (_g['apps'] as List).cast<String>();

  void _save() {
    _g['name'] = _name.text.trim().isEmpty ? 'Group' : _name.text.trim();
    final list = model.groups;
    if (widget.index == null) {
      list.add(_g);
    } else {
      list[widget.index!] = _g;
    }
    model.setGroups(list);
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final vol = (_g['vol'] as num).toInt();
    return Screen(
      title: widget.index == null ? 'New group' : 'Edit group',
      panel: true,
      actions: [TextAction('Save', onTap: _save)],
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 22),
          child: Plate(
            radius: 18,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _name,
              maxLength: 24,
              style: body(context, 17, w: FontWeight.w400),
              decoration: InputDecoration(
                hintText: 'Name, such as Work',
                hintStyle: body(context, 17, color: p.faint),
                border: InputBorder.none,
                counterText: '',
                contentPadding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
        ),
        Section(
          title: 'Level',
          children: [
            Tile(
              title: 'On',
              trailing: Toggle(
                value: _g['on'] != false,
                onChanged: (v) => setState(() => _g['on'] = v),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 16),
              child: LevelSlider(
                value: vol,
                onChanged: (v) => setState(() => _g['vol'] = v),
              ),
            ),
          ],
        ),
        Section(
          title: 'Apps',
          trailing: TextAction(
            'Choose',
            onTap: () async {
              final sel = await go<Set<String>>(
                context,
                Picker(multi: true, selected: _apps.toSet()),
              );
              if (sel != null) setState(() => _g['apps'] = sel.toList());
            },
          ),
          footer:
              'An app with its own level keeps it; the group level is for the rest.',
          children: _apps.isEmpty
              ? [
                  const Tile(
                    title: 'No apps yet',
                    subtitle: 'Tap Choose to add some',
                  ),
                ]
              : [
                  for (final a in _apps)
                    Tile(
                      leading: AppIcon(a, size: 32),
                      title: model.labelOf(a),
                      trailing: GestureDetector(
                        onTap: () => setState(() => _apps.remove(a)),
                        child: Icon(
                          CupertinoIcons.minus_circle_fill,
                          color: p.danger,
                          size: 22,
                        ),
                      ),
                    ),
                ],
        ),
        if (widget.index != null)
          Section(
            children: [
              Tile(
                title: 'Delete group',
                danger: true,
                onTap: () async {
                  final ok = await showGlassConfirm(
                    context,
                    title: 'Delete this group?',
                    text:
                        'Its apps play at your level again, unless they have their own.',
                    action: 'Delete',
                  );
                  if (ok == true && context.mounted) {
                    final list = model.groups..removeAt(widget.index!);
                    model.setGroups(list);
                    Navigator.of(context).pop();
                  }
                },
              ),
            ],
          ),
      ],
    );
  }
}

/// Recommended one-tap setups for app types. Each disappears once it is in
/// place, so the list only ever offers what is not set yet.
class _Presets extends StatelessWidget {
  const _Presets();

  static const _all = [
    ('game', 20, 'Games at 20%', 'Game sound stays in the background'),
    ('social', 0, 'Mute social apps', 'Feeds and reels play silently'),
    ('video', 70, 'Video at 70%', 'Films and shows a little louder'),
    ('audio', 60, 'Music at 60%', 'One steady level for every player'),
  ];

  @override
  Widget build(BuildContext context) {
    final left = [
      for (final x in _all)
        if (!(model.cat(x.$1)['on'] == true &&
            (model.cat(x.$1)['vol'] as num?)?.toInt() == x.$2))
          x,
    ];
    if (left.isEmpty) return const SizedBox.shrink();
    return Section(
      title: 'Recommended',
      footer: 'One tap turns it on. Change it any time under By app type.',
      children: [
        for (final (k, vol, title, line) in left)
          Tile(
            leading: CatGlyph(k),
            title: title,
            subtitle:
                '$line · ${appsOfType(k).length} ${appsOfType(k).length == 1 ? 'app' : 'apps'}',
            trailing: TextAction(
              'Turn on',
              onTap: () {
                final c = model.cat(k);
                c['on'] = true;
                c['vol'] = vol;
                model.commit(now: true);
              },
            ),
          ),
      ],
    );
  }
}
