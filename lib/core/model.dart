import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../ui/kit.dart';
import 'native.dart';

/// The whole app state: the store (which Kotlin owns and the service reads),
/// the live status of the service, and the installed apps.
///
/// One instance, [model]. The UI edits [s] through the helpers below and
/// calls [commit], which saves after a short pause so a slider drag is one
/// write, not sixty.
class Model extends ChangeNotifier {
  Map<String, dynamic> s = {};
  Map<String, dynamic> status = {};
  List<AppInfo> apps = const [];
  bool loaded = false;
  Timer? _save;
  Timer? _poll;

  Future<void> load() async {
    Native.onVolumeChanged(refreshStatus);
    s = await Native.state();
    Pal.current = Accent.byId(s['accent'] as String?);
    status = await Native.status();
    loaded = true;
    // The app list (labels, categories) can take a second on a phone with
    // many apps: fetch it after the first frame, never before it.
    Native.apps().then((a) {
      apps = a;
      notifyListeners();
    });
  }

  void commit({bool now = false}) {
    notifyListeners();
    _save?.cancel();
    if (now) {
      Native.save(s);
    } else {
      _save = Timer(const Duration(milliseconds: 260), () => Native.save(s));
    }
  }

  /// Re-reads the store. The pill writes to it while Levels is in the
  /// background (a level saved from the pill, its Off answer), and the next
  /// commit here would otherwise write the old copy back over that.
  Future<void> reload() async {
    if (_save?.isActive ?? false) return; // our own write is still pending
    final next = await Native.state();
    if (jsonEncode(next) != jsonEncode(s)) {
      s = next;
      Pal.current = Accent.byId(s['accent'] as String?);
      notifyListeners();
    }
  }

  Future<void> refreshStatus() async {
    final next = await Native.status();
    if (jsonEncode(next) != jsonEncode(status)) {
      status = next;
      notifyListeners();
    }
  }

  /// Polls the service's live status while a screen that shows it is open.
  void watch(bool on) {
    _poll?.cancel();
    if (on) {
      refreshStatus();
      _poll = Timer.periodic(
        const Duration(milliseconds: 1200),
        (_) => refreshStatus(),
      );
    }
  }

  // ── Status ───────────────────────────────────────────────────────────
  bool get serviceOn => status['service'] == true;

  /// False only when Android says battery saving may stop Levels. Unknown
  /// reads as fine, so no card shows on a guess.
  bool get batteryFree => status['battery'] != false;

  /// The Home dial moved: show it at once, before the next status poll.
  void setLiveLevel(int v) {
    final l = (status['live'] as Map?)?.cast<String, dynamic>();
    if (l == null) return;
    status['live'] = {...l, 'level': v};
    notifyListeners();
  }

  /// Levels switched itself off for a payment and is waiting to come back.
  bool get paidPause => status['paidPause'] == true;

  /// Levels' notification can show (its Pause for a payment button).
  bool get notifOk => status['notif'] != false;

  /// The phone maker's family when it runs its own battery manager.
  String get oem => status['oem'] as String? ?? '';

  /// What is left to keep Levels running: 'ask' (Android's switch),
  /// 'oem' (the maker's own switch, as in Go Echoo), or null when done.
  /// Asked once and still limited (Vivo keeps Android's switch off by its
  /// own) moves on to the maker's page instead of asking again in a loop.
  String? get batteryStep {
    final asked = get<bool>('batteryAsked', false);
    if (!batteryFree && !asked) return 'ask';
    if (oem.isNotEmpty && !get<bool>('batteryOemDone', false)) return 'oem';
    if (!batteryFree) return 'oem';
    return null;
  }

  static const oemBrand = {
    'xiaomi': 'Xiaomi',
    'huawei': 'Huawei',
    'oppo': 'Oppo',
    'vivo': 'Vivo',
    'samsung': 'Samsung',
    'transsion': 'Tecno',
  };

  /// The maker's own switch, as Go Echoo spells it.
  static const oemPath = {
    'xiaomi': 'Settings › Apps › Levels › Battery saver › No restrictions',
    'huawei': 'Settings › Battery › App launch › Levels › Manage manually',
    'oppo':
        'App info › Battery usage › Allow background activity and Allow '
        'auto-launch',
    'vivo':
        'Settings › Battery › Background power consumption management › '
        'Levels',
    'samsung':
        'Settings › Battery › Background usage limits › Never sleeping '
        'apps › Levels',
    'transsion': 'Settings › Battery › Background power consumption › Levels',
  };
  bool get enabled {
    if (s['enabled'] != false) return true;
    final until = pausedUntil;
    return until != null && DateTime.now().isAfter(until);
  }

  set enabled(bool v) {
    s['enabled'] = v;
    if (v) s.remove('pausedUntil');
    commit(now: true);
  }

  /// When a pause with an end runs out; null for "until turned back on".
  DateTime? get pausedUntil {
    final ms = (s['pausedUntil'] as num?)?.toInt() ?? 0;
    return ms > 0 ? DateTime.fromMillisecondsSinceEpoch(ms) : null;
  }

  /// Pause for [minutes] (0 = until turned back on). The choice is kept, so
  /// the shade's tile pauses for the same length.
  void pause(int minutes) {
    s['enabled'] = false;
    s['pauseFor'] = minutes;
    if (minutes > 0) {
      s['pausedUntil'] = DateTime.now()
          .add(Duration(minutes: minutes))
          .millisecondsSinceEpoch;
    } else {
      s.remove('pausedUntil');
    }
    commit(now: true);
  }

  Map<String, dynamic> get live =>
      (status['live'] as Map?)?.cast<String, dynamic>() ?? const {};
  String get device => status['device'] as String? ?? 'speaker';
  String? get btName => status['bt'] as String?;

  bool get onboarded => s['onboarded'] == true;
  set onboarded(bool v) {
    s['onboarded'] = v;
    commit(now: true);
  }

  String get accent => Accent.byId(s['accent'] as String?).id;
  set accent(String id) {
    s['accent'] = id;
    Pal.current = Accent.byId(id);
    commit(now: true);
  }

  ThemeMode get theme => switch (s['theme']) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };
  set theme(ThemeMode m) {
    s['theme'] = m.name;
    commit(now: true);
  }

  // ── Apps ─────────────────────────────────────────────────────────────
  Map<String, dynamic> get appMap =>
      (s['apps'] ??= <String, dynamic>{}) as Map<String, dynamic>;

  List<String> get managed {
    final list = appMap.keys.toList();
    list.sort(
      (a, b) => labelOf(a).toLowerCase().compareTo(labelOf(b).toLowerCase()),
    );
    return list;
  }

  Map<String, dynamic>? app(String pkg) =>
      (appMap[pkg] as Map?)?.cast<String, dynamic>();

  Map<String, dynamic> ensureApp(String pkg, {int vol = 50}) {
    final existing = appMap[pkg];
    if (existing is Map<String, dynamic>) return existing;
    final a = <String, dynamic>{'on': true, 'vol': vol, 'rules': <dynamic>[]};
    appMap[pkg] = a;
    return a;
  }

  void removeApp(String pkg) {
    appMap.remove(pkg);
    commit(now: true);
  }

  String labelOf(String pkg) {
    for (final a in apps) {
      if (a.pkg == pkg) return a.label;
    }
    return pkg.split('.').last;
  }

  AppInfo? info(String pkg) {
    for (final a in apps) {
      if (a.pkg == pkg) return a;
    }
    return null;
  }

  List<Map<String, dynamic>> rules(String pkg) {
    final a = app(pkg);
    final r = a?['rules'];
    if (r is List) {
      return r.cast<Map>().map((m) => m.cast<String, dynamic>()).toList();
    }
    return [];
  }

  void setRules(String pkg, List<Map<String, dynamic>> r) {
    ensureApp(pkg)['rules'] = r;
    commit(now: true);
  }

  // ── Categories ───────────────────────────────────────────────────────
  static const catKeys = [
    'video',
    'game',
    'social',
    'audio',
    'news',
    'maps',
    'image',
    'productivity',
  ];

  static String catName(String k) => switch (k) {
    'game' => 'Games',
    'video' => 'Video',
    'social' => 'Social',
    'audio' => 'Music & audio',
    'news' => 'News',
    'maps' => 'Maps & navigation',
    'image' => 'Photos',
    'productivity' => 'Productivity',
    _ => k,
  };

  Map<String, dynamic> cat(String k) {
    final cats = (s['cats'] ??= <String, dynamic>{}) as Map<String, dynamic>;
    final c = cats[k];
    if (c is Map<String, dynamic>) return c;
    final made = <String, dynamic>{'on': false, 'vol': 50};
    cats[k] = made;
    return made;
  }

  int appsIn(String k) => apps.where((a) => a.cat == k).length;

  List<Map<String, dynamic>> get groups {
    final g = s['custom'];
    if (g is List) {
      return g.cast<Map>().map((m) => m.cast<String, dynamic>()).toList();
    }
    return [];
  }

  void setGroups(List<Map<String, dynamic>> g) {
    s['custom'] = g;
    commit(now: true);
  }

  /// Why [pkg] gets the level it gets, for rows that are not per-app.
  String? groupOf(String pkg) {
    for (final g in groups) {
      if (g['on'] == false) continue;
      final list = (g['apps'] as List?)?.cast<String>() ?? const [];
      if (list.contains(pkg)) return g['name'] as String?;
    }
    return null;
  }

  // ── Settings ─────────────────────────────────────────────────────────
  Map<String, dynamic> get notice =>
      (s['notice'] ??= <String, dynamic>{}) as Map<String, dynamic>;

  T get<T>(String key, T fallback) {
    final v = s[key];
    return v is T ? v : fallback;
  }

  void put(String key, Object? value) {
    s[key] = value;
    commit(now: true);
  }
}

final model = Model();

String ruleText(Map<String, dynamic> r) {
  final dev = switch (r['device']) {
    'speaker' => 'Speaker',
    'wired' => 'Wired headphones',
    'bt' => 'Bluetooth',
    _ => null,
  };
  final cond = switch (r['when']) {
    'charging' => 'Charging',
    'quiet' => 'Silent mode',
    'lowBattery' => 'Low battery',
    _ => null,
  };
  final from = r['from'] as String? ?? '';
  final to = r['to'] as String? ?? '';
  final time = from.isNotEmpty && to.isNotEmpty ? '$from – $to' : null;
  return [
    dev,
    cond,
    daysText((r['days'] as List?)?.cast<int>()),
    time,
  ].whereType<String>().join(' · ').ifEmpty('Always');
}

/// Days of the week, 1 = Monday. Null for every day.
String? daysText(List<int>? d) {
  if (d == null || d.isEmpty || d.length == 7) return null;
  final l = [...d]..sort();
  if (l.join() == '12345') return 'Weekdays';
  if (l.join() == '67') return 'Weekends';
  const n = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return l.map((i) => n[i - 1]).join(' ');
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}
