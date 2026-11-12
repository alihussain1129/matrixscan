import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'link_models.dart';

/// Android notification delivery for authenticated companion activity.
/// Notification bodies deliberately avoid scan text and inspection payloads.
class CompanionNotifications {
  CompanionNotifications._();

  static const MethodChannel _channel = MethodChannel(
    'com.exaltedcoding.exalted/notifications',
  );
  static const _enabled = 'companion.notifications.enabled';
  static const _inspections = 'companion.notifications.inspections';
  static const _operations = 'companion.notifications.operations';
  static const _sync = 'companion.notifications.sync';
  static const _commands = 'companion.notifications.commands';
  static const _seen = 'companion.notifications.seen';
  static Future<void> _queue = Future<void>.value();

  static Future<void> initialize({required VoidCallback openActivity}) async {
    if (!Platform.isAndroid) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'notificationTapped' && call.arguments == 'activity') {
        openActivity();
      }
    });
    final target = await _channel.invokeMethod<String>('getLaunchTarget');
    if (target == 'activity') openActivity();
  }

  static Future<bool> enabled() async =>
      (await SharedPreferences.getInstance()).getBool(_enabled) ?? false;

  static Future<bool> preference(String key) async =>
      (await SharedPreferences.getInstance()).getBool(key) ?? (key != _enabled);

  static Future<bool> setPreference(String key, bool value) async {
    if (value && Platform.isAndroid) {
      final permission = await Permission.notification.request();
      if (!permission.isGranted) return false;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
    if (key == _enabled && !value) return true;
    return true;
  }

  static Future<List<CompanionActivityEvent>> observeSnapshot(
    String desktopId,
    DateTime pairedAt,
    Iterable<CompanionActivityEvent> events,
  ) async {
    if (!Platform.isAndroid) return const <CompanionActivityEvent>[];
    final prefs = await SharedPreferences.getInstance();
    final key = 'companion.notifications.snapshot.$desktopId';
    final known = (prefs.getStringList(key) ?? <String>[]).toSet();
    final isFirst = prefs.getBool('$key.ready') != true;
    final fresh = <CompanionActivityEvent>[];
    for (final event in events) {
      if (isFirst && !event.createdAt.isAfter(pairedAt)) {
        known.add(event.id);
      } else if (!known.contains(event.id)) {
        fresh.add(event);
        known.add(event.id);
      }
    }
    await prefs.setStringList(key, known.toList().take(500).toList());
    await prefs.setBool('$key.ready', true);
    return fresh;
  }

  static Future<void> activity(CompanionActivityEvent event) async {
    if (!Platform.isAndroid || !await enabled()) return;
    if (event.type != 'inspection' || !await preference(_inspections)) return;
    await _showOnce(
      event.id,
      'Inspection update',
      'A new inspection event was recorded on the linked desktop.',
    );
  }

  static Future<void> connectionTransition(
    String desktopId,
    bool connected,
  ) async {
    if (!Platform.isAndroid ||
        !await enabled() ||
        !await preference(_operations)) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final key = 'companion.connection.$desktopId';
    final previous = prefs.getBool(key);
    await prefs.setBool(key, connected);
    if (previous == null || previous == connected) return;
    final counterKey = '$key.transitions';
    final counter = (prefs.getInt(counterKey) ?? 0) + 1;
    await prefs.setInt(counterKey, counter);
    await _showOnce(
      'connection:$desktopId:$counter',
      connected ? 'Desktop reconnected' : 'Desktop disconnected',
      connected
          ? 'The paired desktop connection is available again.'
          : 'The paired desktop connection was lost.',
    );
  }

  static Future<void> syncResult(String id, {required bool success}) async {
    if (!Platform.isAndroid || !await enabled() || !await preference(_sync)) {
      return;
    }
    await _showOnce(
      id,
      success ? 'Sync complete' : 'Sync failed',
      success
          ? 'Desktop synchronization completed.'
          : 'Desktop synchronization failed. Open Exalted to retry.',
    );
  }

  static Future<void> commandResult(RemoteCommandResult result) async {
    if (!Platform.isAndroid ||
        !await enabled() ||
        !await preference(_commands)) {
      return;
    }
    await _showOnce(
      'remote-command:${result.commandId}',
      'Remote scanner command',
      result.message,
    );
  }

  static Future<void> hardwareTransition(
    String desktopId,
    String component,
    String status,
  ) async {
    if (!Platform.isAndroid ||
        !await enabled() ||
        !await preference(_operations)) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final key = 'companion.hardware.$desktopId.$component';
    final previous = prefs.getString(key);
    await prefs.setString(key, status);
    if (previous == null || previous == status) return;
    final wasDown = _hardwareDown(previous);
    final isDown = _hardwareDown(status);
    if (wasDown == isDown) return;
    final counterKey = '$key.transitions';
    final counter = (prefs.getInt(counterKey) ?? 0) + 1;
    await prefs.setInt(counterKey, counter);
    await _showOnce(
      'hardware:$desktopId:$component:$counter',
      isDown ? 'Scanner disconnected' : 'Scanner reconnected',
      isDown
          ? 'The $component scanner on the desktop is unavailable.'
          : 'The $component scanner on the desktop is available again.',
    );
  }

  static bool _hardwareDown(String value) => const {
    'error',
    'disconnected',
    'offline',
    'permissionDenied',
  }.contains(value);

  static Future<void> _showOnce(String id, String title, String body) async {
    final next = _queue.then((_) => _postOnce(id, title, body));
    _queue = next.catchError((Object _) {});
    return next;
  }

  static Future<void> _postOnce(String id, String title, String body) async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getStringList(_seen) ?? <String>[];
    if (seen.contains(id)) return;
    final next = <String>[...seen, id];
    try {
      await _channel.invokeMethod<void>('show', {
        'id': id,
        'title': title,
        'body': body,
        'route': 'activity',
      });
      await prefs.setStringList(
        _seen,
        next.length > 500 ? next.sublist(next.length - 500) : next,
      );
    } on PlatformException {
      // Permission may have been revoked in Android settings while the app ran.
    }
  }
}

class CompanionNotificationSettings extends StatefulWidget {
  const CompanionNotificationSettings({super.key});

  @override
  State<CompanionNotificationSettings> createState() =>
      _CompanionNotificationSettingsState();
}

class _CompanionNotificationSettingsState
    extends State<CompanionNotificationSettings> {
  final Map<String, bool> _values = <String, bool>{};
  bool _loaded = false;
  String? _message;

  static const _items = <(String, String, String)>[
    (
      'companion.notifications.enabled',
      'Desktop notifications',
      'Show companion updates on this Android device.',
    ),
    (
      'companion.notifications.inspections',
      'Inspection events',
      'Notify when the desktop records an inspection.',
    ),
    (
      'companion.notifications.operations',
      'Desktop activity',
      'Notify about authenticated desktop activity.',
    ),
    (
      'companion.notifications.sync',
      'Synchronization',
      'Notify when a sync completes or fails.',
    ),
    (
      'companion.notifications.commands',
      'Remote commands',
      'Notify when the desktop confirms a scanner command.',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    for (final item in _items) {
      _values[item.$1] = await CompanionNotifications.preference(item.$1);
    }
    if (mounted) setState(() => _loaded = true);
  }

  Future<void> _set(String key, bool value) async {
    final granted = await CompanionNotifications.setPreference(key, value);
    if (!mounted) return;
    setState(() {
      if (granted) _values[key] = value;
      _message = granted
          ? null
          : 'Allow notifications in Android settings to enable this option.';
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    return Column(
      children: [
        for (final item in _items)
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(item.$2),
            subtitle: Text(item.$3),
            value: _values[item.$1] ?? true,
            onChanged: (value) => _set(item.$1, value),
          ),
        if (_message != null)
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _message!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }
}
