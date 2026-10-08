import 'dart:io';

import 'package:exalted/features/history/history_repository.dart';
import 'package:exalted/features/scanner/scanner_analyzer.dart';
import 'package:exalted/features/scanner/scanner_controller.dart';
import 'package:exalted/ffi/decode_result.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

DecodedBarcode _barcode(String text) => DecodedBarcode(
  text: text,
  kind: BarcodeKind.qrCode,
  corners: const [Offset.zero, Offset.zero, Offset.zero, Offset.zero],
  decodeMicros: 1000,
  frameWidth: 640,
  frameHeight: 480,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late HistoryRepository repo;
  late ProviderContainer container;
  late ScannerAnalyzer analyzer;
  late ScannerController controller;

  String? shown() => container.read(scannerControllerProvider).result?.text;

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async => null,
        );
    dir = Directory.systemTemp.createTempSync('exalted_repeat_test');
    repo = HistoryRepository(directory: () async => dir);
    container = ProviderContainer(
      overrides: [historyRepositoryProvider.overrideWithValue(repo)],
    );
    analyzer = container.read(scannerAnalyzerProvider);
    controller = container.read(scannerControllerProvider.notifier);
  });

  tearDown(() async {
    await repo.loadAll();
    container.dispose();
    dir.deleteSync(recursive: true);
  });

  test('Scan again shows the same code again straight away', () async {
    analyzer.onDecoded!(_barcode('SAME-CODE'));
    expect(shown(), 'SAME-CODE');

    await controller.resumeScanning();
    expect(shown(), isNull);

    analyzer.onDecoded!(_barcode('SAME-CODE'));
    expect(shown(), 'SAME-CODE');
  });

  test('continuous mode still ignores a repeat of the same code', () async {
    controller.toggleContinuous();

    analyzer.onDecoded!(_barcode('SAME-CODE'));
    expect(shown(), 'SAME-CODE');

    await controller.resumeScanning();
    analyzer.onDecoded!(_barcode('SAME-CODE'));
    expect(shown(), isNull);
  });

  test('continuous mode never ignores a different code', () async {
    controller.toggleContinuous();

    analyzer.onDecoded!(_barcode('CODE-ONE'));
    await controller.resumeScanning();
    analyzer.onDecoded!(_barcode('CODE-TWO'));

    expect(shown(), 'CODE-TWO');
  });
}
