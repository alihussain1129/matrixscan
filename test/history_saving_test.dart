import 'dart:io';

import 'package:exalted/features/history/history_entry.dart';
import 'package:exalted/features/history/history_repository.dart';
import 'package:exalted/features/scanner/scanner_analyzer.dart';
import 'package:exalted/features/scanner/scanner_controller.dart';
import 'package:exalted/ffi/decode_result.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

DecodedBarcode _barcode(String text, BarcodeKind kind) => DecodedBarcode(
  text: text,
  kind: kind,
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

  setUp(() {
    // Haptics have no platform side in tests.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async => null,
        );
    dir = Directory.systemTemp.createTempSync('exalted_history_test');
    repo = HistoryRepository(directory: () async => dir);
    container = ProviderContainer(
      overrides: [historyRepositoryProvider.overrideWithValue(repo)],
    );
  });

  tearDown(() {
    container.dispose();
    dir.deleteSync(recursive: true);
  });

  test('a live decode is saved with text, type and source', () async {
    final analyzer = container.read(scannerAnalyzerProvider);
    container.read(scannerControllerProvider);

    analyzer.onDecoded!(_barcode('HELLO-DM', BarcodeKind.dataMatrix));

    final entries = await repo.loadAll();
    expect(entries.length, 1);
    expect(entries.first.text, 'HELLO-DM');
    expect(entries.first.format, 'Data Matrix');
    expect(entries.first.kind, HistoryKind.barcode);
    expect(entries.first.source, HistorySource.live);
  });

  test('a gallery scan is saved with the gallery source', () async {
    final controller = container.read(scannerControllerProvider.notifier);

    controller.presentImported(
      _barcode('https://example.com', BarcodeKind.qrCode),
    );

    final entries = await repo.loadAll();
    expect(entries.length, 1);
    expect(entries.first.text, 'https://example.com');
    expect(entries.first.format, 'QR Code');
    expect(entries.first.source, HistorySource.gallery);
  });

  test('the same live code twice in a row is stored once', () async {
    final analyzer = container.read(scannerAnalyzerProvider);
    container.read(scannerControllerProvider.notifier).toggleContinuous();

    analyzer.onDecoded!(_barcode('SAME', BarcodeKind.qrCode));
    analyzer.onDecoded!(_barcode('SAME', BarcodeKind.qrCode));

    final entries = await repo.loadAll();
    expect(entries.length, 1);
  });
}
