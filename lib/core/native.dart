import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

/// An installed app with a launcher icon.
class AppInfo {
  const AppInfo(this.pkg, this.label, this.cat);
  final String pkg;
  final String label;
  final String? cat;
}

/// The bridge to the Kotlin side, which owns the store and the service.
class Native {
  Native._();
  static const _c = MethodChannel('levels');

  /// Called when the media volume changes while Levels is open.
  static void onVolumeChanged(void Function() f) {
    _c.setMethodCallHandler((call) async {
      if (call.method == 'volumeChanged') f();
    });
  }

  static Future<Map<String, dynamic>> state() async {
    try {
      final raw = await _c.invokeMethod<String>('getState');
      return (jsonDecode(raw ?? '{}') as Map).cast<String, dynamic>();
    } catch (_) {
      return {};
    }
  }

  static Future<void> save(Map<String, dynamic> s) async {
    try {
      await _c.invokeMethod('setState', jsonEncode(s));
    } catch (_) {}
  }

  static Future<Map<String, dynamic>> status() async {
    try {
      final raw = await _c.invokeMethod<String>('status');
      return (jsonDecode(raw ?? '{}') as Map).cast<String, dynamic>();
    } catch (_) {
      return {};
    }
  }

  static List<AppInfo>? _apps;
  static Future<List<AppInfo>> apps({bool refresh = false}) async {
    if (_apps != null && !refresh) return _apps!;
    try {
      final raw = await _c.invokeMethod<String>('apps');
      final list =
          (jsonDecode(raw ?? '[]') as List)
              .cast<Map>()
              .map(
                (m) => AppInfo(
                  m['pkg'] as String,
                  m['label'] as String,
                  m['cat'] as String?,
                ),
              )
              .toList()
            ..sort(
              (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()),
            );
      _apps = list;
      return list;
    } catch (_) {
      return const [];
    }
  }

  static final Map<String, Future<Uint8List?>> _icons = {};
  static Future<Uint8List?> icon(String pkg) =>
      _icons.putIfAbsent(pkg, () async {
        try {
          return await _c.invokeMethod<Uint8List>('icon', pkg);
        } catch (_) {
          return null;
        }
      });

  static Future<void> openAccessibility() async {
    try {
      await _c.invokeMethod('openA11y');
    } catch (_) {}
  }

  /// Sets the media volume now, 0 to 100.
  static Future<void> volume(int v) async {
    try {
      await _c.invokeMethod('volume', v);
    } catch (_) {}
  }

  /// Turns Levels' accessibility switch off for a bank or UPI payment.
  /// False when it was not on.
  static Future<bool> payPause() async {
    try {
      return await _c.invokeMethod<bool>('payPause') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Levels' App info page.
  static Future<void> appInfo() async {
    try {
      await _c.invokeMethod('appInfo');
    } catch (_) {}
  }

  /// Android's "don't optimise" dialog for Levels.
  static Future<void> batteryAsk() async {
    try {
      await _c.invokeMethod('batteryAsk');
    } catch (_) {}
  }

  /// The phone maker's own battery page, or Levels' App info.
  static Future<void> batteryOem() async {
    try {
      await _c.invokeMethod('batteryOem');
    } catch (_) {}
  }

  static Future<List<Map<String, dynamic>>> log() async {
    try {
      final raw = await _c.invokeMethod<String>('log');
      return (jsonDecode(raw ?? '[]') as List)
          .cast<Map>()
          .map((m) => m.cast<String, dynamic>())
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> clearLog() async {
    try {
      await _c.invokeMethod('clearLog');
    } catch (_) {}
  }

  /// 'saved', or null when the user backed out.
  static Future<String?> export() async {
    try {
      return await _c.invokeMethod<String>('export');
    } catch (_) {
      return null;
    }
  }

  /// The file's JSON, 'invalid', or null when the user backed out.
  static Future<String?> import() async {
    try {
      return await _c.invokeMethod<String>('import');
    } catch (_) {
      return null;
    }
  }

  /// Asks the launcher to pin a "Paying" icon to the home screen. False
  /// when the launcher cannot pin.
  /// Asks the launcher to add the 1x1 Levels widget (on or off in one
  /// tap). False when the launcher cannot.
  static Future<bool> pinWidget() async {
    try {
      return await _c.invokeMethod<bool>('pinWidget') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> pinPay() async {
    try {
      return await _c.invokeMethod<bool>('pinPay') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Whether Levels' notification can show (Android 13+ asks first). Its
  /// "Pause for a payment" button is the way to step aside before paying.
  static Future<bool> notifOk() async {
    try {
      return await _c.invokeMethod<bool>('notifOk') ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Asks for notifications. Once refused for good, opens Levels'
  /// notification settings instead. True when they are allowed now.
  static Future<bool> askNotif() async {
    try {
      return await _c.invokeMethod<bool>('askNotif') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Asks Android to add the Quick Settings tile (Android 13+). False when
  /// the phone cannot, so the caller explains the manual way instead.
  static Future<bool> addTile() async {
    try {
      return await _c.invokeMethod<bool>('addTile') ?? false;
    } catch (_) {
      return false;
    }
  }
}
