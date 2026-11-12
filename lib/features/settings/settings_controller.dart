import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/config_controller.dart';

/// Holds the current theme mode and saves the choice.
///
/// Windows and Linux start dark. Phones keep their original light default.
class ThemeModeNotifier extends Notifier<ThemeMode> {
  static ThemeMode get _default =>
      (Platform.isAndroid || Platform.isIOS) ? ThemeMode.light : ThemeMode.dark;

  @override
  ThemeMode build() {
    final saved = ref.read(configControllerProvider).appearance.themeMode;
    for (final mode in ThemeMode.values) {
      if (mode.name == saved) return mode;
    }
    return _default;
  }

  void set(ThemeMode mode) {
    state = mode;
    unawaited(_save(mode));
  }

  Future<void> _save(ThemeMode mode) async {
    try {
      await ref.read(configControllerProvider.notifier).patch({
        'appearance': {'themeMode': mode.name},
      });
    } catch (_) {
      // The choice still applies for this session.
    }
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);
