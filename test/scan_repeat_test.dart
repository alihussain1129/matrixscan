import 'dart:io';

import 'package:exalted/features/history/history_repository.dart';
import 'package:exalted/features/inspection/inspection_log.dart';
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
  late InspectionLog log;
  late ProviderContainer container;
  late ScannerAnalyzer analyzer;
  late ScannerController controller;

  String? shown() => container.read(scannerControllerProvider).result?.text;

  Future<void> settle() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await repo.loadAll();
    await log.loadAll();
  }

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async => null,
        );
    dir = Directory.systemTemp.createTempSync('exalted_repeat_test');
    repo = HistoryRepository(directory: () async => dir);
    log = InspectionLog(directory: () async => dir);
    container = ProviderContainer(
      overrides: [
        historyRepositoryProvider.overrideWithValue(repo),
        inspectionLogProvider.overrideWithValue(log),
      ],
    );
    analyzer = container.read(scannerAnalyzerProvider);
    controller = container.read(scannerControllerProvider.notifier);
  });

  tearDown(() async {
    await settle();
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

  test(
    'continuous mode records one event for a code that stays in view',
    () async {
      controller.toggleContinuous();
      for (var i = 0; i < 5; i++) {
        analyzer.onDecoded!(_barcode('SAME-CODE'));
      }
      expect(shown(), 'SAME-CODE');
      await settle();
      expect((await repo.loadAll()).length, 1);
      expect((await log.loadAll()).length, 1);
    },
  );

  test('continuous mode never ignores a different code', () async {
    controller.toggleContinuous();
    analyzer.onDecoded!(_barcode('CODE-ONE'));
    analyzer.onDecoded!(_barcode('CODE-TWO'));
    expect(shown(), 'CODE-TWO');
    await settle();
    expect((await log.loadAll()).length, 2);
  });

  test('switching from Single to Continuous resumes scanning by itself', () {
    analyzer.onDecoded!(_barcode('A'));
    var s = container.read(scannerControllerProvider);
    expect(s.paused, isTrue);
    expect(s.result?.text, 'A');

    controller.toggleContinuous();
    s = container.read(scannerControllerProvider);
    expect(s.continuous, isTrue);
    expect(s.paused, isFalse);
    expect(s.result, isNull);
  });
}
