import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:exalted/core/config/app_config.dart';
import 'package:exalted/core/config/config_controller.dart';
import 'package:exalted/core/config/config_provider.dart';
import 'package:exalted/features/scanner/scanner_controller.dart';
import 'package:exalted/features/scanner/scanner_analyzer.dart';
import 'package:exalted/ffi/decode_result.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 50));

  test('saved config quality is applied at startup', () async {
    final c = ProviderContainer(
      overrides: [
        configProvider.overrideWithValue(
          const AppConfig(camera: CameraConfig(quality: 'ultra')),
        ),
      ],
    );
    addTearDown(c.dispose);
    c.read(scannerControllerProvider);
    await settle();
    expect(c.read(scannerControllerProvider).quality, CameraQuality.ultra);
  });

  test('setQuality is saved into the config', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(scannerControllerProvider.notifier).setQuality(CameraQuality.high);
    await settle();
    expect(c.read(configControllerProvider).camera.quality, 'high');
  });

  test('saved symbology choices update the live analyzer mask', () async {
    final c = ProviderContainer(
      overrides: [configProvider.overrideWithValue(const AppConfig())],
    );
    addTearDown(c.dispose);
    c.read(scannerControllerProvider);
    final analyzer = c.read(scannerAnalyzerProvider);
    expect(analyzer.formatsMask, 0);

    await c.read(configControllerProvider.notifier).patch({
      'decoder': {
        'symbologies': ['qrCode', 'dataMatrix'],
      },
    });
    expect(
      analyzer.formatsMask,
      BarcodeKind.qrCode.flag | BarcodeKind.dataMatrix.flag,
    );

    await c.read(configControllerProvider.notifier).patch({
      'decoder': {'symbologies': <String>[]},
    });
    expect(analyzer.formatsMask, 0);
  });
}
