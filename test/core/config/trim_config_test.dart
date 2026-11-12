import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:exalted/core/config/app_config.dart';
import 'package:exalted/core/config/legacy_settings.dart';
import 'package:exalted/ffi/decode_result.dart';

void main() {
  test('known symbologies match BarcodeKind exactly', () {
    final real = BarcodeKind.values
        .where((k) => k != BarcodeKind.unknown)
        .map((k) => k.name)
        .toSet();
    expect(DecoderConfig.knownSymbologies.toSet(), real);
  });

  test('defaults validate and match the app', () {
    const c = AppConfig();
    expect(c.validate(), isEmpty);
    expect(c.decoder.symbologies, isEmpty);
    expect(c.decoder.ocrWithDecode, isTrue);
    expect(c.storage.keepImages, isFalse);
    expect(c.network.httpConnectTimeoutMs, 7000);
    expect(c.network.maxResponseBytes, 1048576);
  });

  test('unknown symbology is rejected', () {
    final i = const AppConfig(decoder: DecoderConfig(symbologies: ['qr']))
        .validate();
    expect(i.any((x) => x.path == 'decoder.symbologies'), isTrue);
  });

  test('bad network values are rejected', () {
    final i = const AppConfig(network: NetworkConfig(httpMaxAttempts: 0))
        .validate();
    expect(i.any((x) => x.path == 'network.httpMaxAttempts'), isTrue);
  });

  test('json round trip keeps decoder, storage and network', () {
    const c = AppConfig(
      decoder: DecoderConfig(symbologies: ['dataMatrix'], ocrWithDecode: false),
      storage: StorageConfig(keepImages: true),
      network: NetworkConfig(httpMaxAttempts: 3),
    );
    final issues = <ConfigIssue>[];
    final back = AppConfig.fromJson(c.toJson(), issues);
    expect(issues, isEmpty);
    expect(back.decoder.symbologies, ['dataMatrix']);
    expect(back.decoder.ocrWithDecode, isFalse);
    expect(back.storage.keepImages, isTrue);
    expect(back.network.httpMaxAttempts, 3);
  });

  test('saved inspector and camera values are carried over', () async {
    SharedPreferences.setMockInitialValues({
      'exalted_ocr_with_decode': false,
      'exalted_keep_images': true,
      'exalted_camera_quality': 'high',
    });
    final l = await readLegacySettings();
    expect(l.decoderJson(), {'ocrWithDecode': false});
    expect(l.storageJson(), {'keepImages': true});
    expect(l.cameraJson(), {'quality': 'high'});
  });
}
