import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:exalted/core/config/app_config.dart';
import 'package:exalted/core/config/config_controller.dart';
import 'package:exalted/core/config/config_provider.dart';
import 'package:exalted/core/config/legacy_settings.dart';
import 'package:exalted/core/config/migrate.dart';
import 'package:exalted/features/settings/settings_controller.dart';

void main() {
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 50));

  test('no saved theme falls back to the platform default', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(themeModeProvider), ThemeMode.dark); // Linux test host
    expect(const AppConfig().validate(), isEmpty);
  });

  test('config theme is there on the first read', () {
    final c = ProviderContainer(
      overrides: [
        configProvider.overrideWithValue(
          const AppConfig(appearance: AppearanceConfig(themeMode: 'light')),
        ),
      ],
    );
    addTearDown(c.dispose);
    expect(c.read(themeModeProvider), ThemeMode.light);
  });

  test('set is saved into the config', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(themeModeProvider.notifier).set(ThemeMode.system);
    await settle();
    expect(c.read(themeModeProvider), ThemeMode.system);
    expect(c.read(configControllerProvider).appearance.themeMode, 'system');
  });

  test('unknown theme name is rejected', () {
    final i = const AppConfig(appearance: AppearanceConfig(themeMode: 'neon'))
        .validate();
    expect(i.any((x) => x.path == 'appearance.themeMode'), isTrue);
  });

  test('saved theme is carried over; junk is dropped', () async {
    SharedPreferences.setMockInitialValues({'exalted_theme_mode': 'light'});
    var c = migrateFromLegacy(await readLegacySettings());
    expect(c.appearance.themeMode, 'light');
    SharedPreferences.setMockInitialValues({'exalted_theme_mode': 'neon'});
    c = migrateFromLegacy(await readLegacySettings());
    expect(c.appearance.themeMode, isNull);
    expect(c.validate(), isEmpty);
  });

  test('a config.json without an appearance section still parses', () {
    final issues = <ConfigIssue>[];
    final c = AppConfig.fromJson({'version': 1}, issues);
    expect(c.appearance.themeMode, isNull);
  });
}
