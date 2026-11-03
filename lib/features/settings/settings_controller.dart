import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Holds the current theme mode and saves the choice.
///
/// Windows and Linux start dark. Phones keep their original light default.
class ThemeModeNotifier extends Notifier<ThemeMode> {
  static const String _key = 'exalted_theme_mode';

  bool _changedByUser = false;

  static ThemeMode get _default =>
      (Platform.isAndroid || Platform.isIOS) ? ThemeMode.light : ThemeMode.dark;

  @override
  ThemeMode build() {
    unawaited(_restore());
    return _default;
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_key);
      if (_changedByUser) return;
      for (final mode in ThemeMode.values) {
        if (mode.name == saved) {
          state = mode;
          return;
        }
      }
    } catch (_) {
      // Keep the default when storage is not available.
    }
  }

  void set(ThemeMode mode) {
    _changedByUser = true;
    state = mode;
    unawaited(_save(mode));
  }

  Future<void> _save(ThemeMode mode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, mode.name);
    } catch (_) {
      // The choice still applies for this session.
    }
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);
