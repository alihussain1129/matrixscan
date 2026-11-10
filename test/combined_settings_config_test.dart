import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:exalted/core/config/app_config.dart';
import 'package:exalted/core/config/config_controller.dart';
import 'package:exalted/core/config/config_provider.dart';
import 'package:exalted/features/inspection/combined_inspector.dart';

void main() {
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 50));

  test('defaults match the old behaviour', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final s = c.read(combinedSettingsProvider);
    expect(s.ocrWithDecode, isTrue);
    expect(s.keepImages, isFalse);
  });

  test('config values are there on the very first read', () {
    final c = ProviderContainer(
      overrides: [
        configProvider.overrideWithValue(
          const AppConfig(
            decoder: DecoderConfig(ocrWithDecode: false),
            storage: StorageConfig(keepImages: true),
          ),
        ),
      ],
    );
    addTearDown(c.dispose);
    final s = c.read(combinedSettingsProvider);
    expect(s.ocrWithDecode, isFalse);
    expect(s.keepImages, isTrue);
  });

  test('setters update the state and are saved into the config', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(combinedSettingsProvider.notifier);
    n.setOcrWithDecode(false);
    n.setKeepImages(true);
    await settle();
    expect(c.read(combinedSettingsProvider).ocrWithDecode, isFalse);
    expect(c.read(combinedSettingsProvider).keepImages, isTrue);
    final cfg = c.read(configControllerProvider);
    expect(cfg.decoder.ocrWithDecode, isFalse);
    expect(cfg.storage.keepImages, isTrue);
  });
}
