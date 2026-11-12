import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:exalted/core/config/app_config.dart';
import 'package:exalted/core/config/config_controller.dart';
import 'package:exalted/core/config/config_provider.dart';
import 'package:exalted/core/config/legacy_settings.dart';
import 'package:exalted/core/config/migrate.dart';
import 'package:exalted/features/scanner/detection_events.dart';

void main() {
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 50));

  test('default is the old 1000 ms', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(rearmGapProvider), 1000);
    expect(const AppConfig().validate(), isEmpty);
  });

  test('config value is there on the first read', () {
    final c = ProviderContainer(
      overrides: [
        configProvider.overrideWithValue(
          const AppConfig(decoder: DecoderConfig(rearmGapMs: 2500)),
        ),
      ],
    );
    addTearDown(c.dispose);
    expect(c.read(rearmGapProvider), 2500);
  });

  test('set clamps and is saved into the config', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(rearmGapProvider.notifier).set(99999);
    await settle();
    expect(c.read(rearmGapProvider), 5000);
    expect(c.read(configControllerProvider).decoder.rearmGapMs, 5000);
  });

  test('out-of-range config value is rejected by validation', () {
    final i = const AppConfig(decoder: DecoderConfig(rearmGapMs: 10))
        .validate();
    expect(i.any((x) => x.path == 'decoder.rearmGapMs'), isTrue);
  });

  test('saved gap is carried over and clamped by migration', () async {
    SharedPreferences.setMockInitialValues({'exalted_rearm_gap_ms': 1500});
    var c = migrateFromLegacy(await readLegacySettings());
    expect(c.decoder.rearmGapMs, 1500);
    SharedPreferences.setMockInitialValues({'exalted_rearm_gap_ms': 90000});
    c = migrateFromLegacy(await readLegacySettings());
    expect(c.decoder.rearmGapMs, 5000);
    expect(c.validate(), isEmpty);
  });
}
