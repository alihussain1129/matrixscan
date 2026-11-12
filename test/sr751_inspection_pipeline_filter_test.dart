import 'dart:async';
import 'dart:io';

import 'package:exalted/core/storage/image_storage_service.dart';
import 'package:exalted/features/devices/keyence/keyence_ftp_receiver.dart';
import 'package:exalted/features/devices/keyence/keyence_sr751_client.dart';
import 'package:exalted/features/devices/keyence/sr751_inspection_pipeline.dart';
import 'package:exalted/features/devices/keyence/sr751_message_classifier.dart';
import 'package:exalted/features/history/history_repository.dart';
import 'package:exalted/features/ocr/models/ocr_result.dart';
import 'package:exalted/features/ocr/services/ocr_engine.dart';
import 'package:exalted/features/ocr/services/ocr_history_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// Client whose scans are pushed by the test. No socket is ever opened.
class _FakeClient extends KeyenceSr751Client {
  _FakeClient() : super();

  final StreamController<KeyenceScanResult> _fake =
      StreamController<KeyenceScanResult>.broadcast();

  @override
  Stream<KeyenceScanResult> get scanStream => _fake.stream;

  @override
  Future<bool> triggerRead() async => true;

  void push(KeyenceScanResult result) => _fake.add(result);

  Future<void> closeFake() => _fake.close();
}

/// OCR engine that is never expected to run in these tests.
class _UnusedOcrEngine implements OcrEngine {
  @override
  String get name => 'unused';

  @override
  String get script => 'Latin';

  @override
  Future<OcrResult> recognizeFile(String imagePath) async =>
      throw UnimplementedError('OCR must not run in filter tests');

  @override
  Future<void> dispose() async {}
}

void main() {
  late Directory dir;
  late _FakeClient client;
  late HistoryRepository history;
  late Sr751InspectionPipeline pipeline;
  var flushes = 0;

  Sr751InspectionPipeline build({
    Sr751MessageClassifier? classifier,
    Duration acquireTimeout = const Duration(seconds: 10),
  }) {
    final storage = ImageStorageService(directoryProvider: () async => dir);
    return Sr751InspectionPipeline(
      client: client,
      ftpReceiver: KeyenceFtpReceiver(imageStorage: storage),
      ocrEngine: _UnusedOcrEngine(),
      ocrHistory: OcrHistoryRepository(
        directoryProvider: () async => dir,
        imageStorageService: storage,
      ),
      historyRepo: history,
      imageStorage: storage,
      acquireTimeout: acquireTimeout,
      classifier: classifier,
    );
  }

  KeyenceScanResult line(String text, {String raw = ''}) => KeyenceScanResult(
    data: text,
    timestamp: DateTime.now(),
    rawResponse: raw.isNotEmpty ? raw : text,
  );

  Future<void> waitFor(
    bool Function() condition, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final end = DateTime.now().add(timeout);
    while (!condition()) {
      if (DateTime.now().isAfter(end)) fail('Timed out waiting for condition');
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  /// Events are handled strictly in order, so once this error line has been
  /// processed, every line pushed before it has been processed too.
  Future<void> flush() async {
    flushes++;
    final marker = 'SENTINEL-$flushes';
    client.push(
      KeyenceScanResult(
        data: '',
        timestamp: DateTime.now(),
        rawResponse: 'ERROR,$marker',
        isError: true,
        errorMessage: marker,
      ),
    );
    await waitFor(() => pipeline.inspections.any((r) => r.message == marker));
  }

  List<IndustrialInspectionRecord> real() => pipeline.inspections
      .where((r) => !(r.message ?? '').startsWith('SENTINEL-'))
      .toList();

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('exalted_pipeline_filter_');
    client = _FakeClient();
    history = HistoryRepository(directory: () async => dir);
    pipeline = build();
  });

  tearDown(() async {
    pipeline.dispose();
    await client.closeFake();
    await dir.delete(recursive: true);
  });

  test('a barcode line becomes one record and one history entry', () async {
    client.push(line('LOT-A1'));
    await waitFor(() => pipeline.inspections.isNotEmpty);
    await flush();

    final records = real();
    expect(records, hasLength(1));
    expect(records.single.barcode, 'LOT-A1');
    expect(records.single.status, InspectionStatus.pass);
    expect(await history.loadAll(), hasLength(1));
  });

  test('blank and whitespace-only lines are dropped', () async {
    client.push(line(''));
    client.push(line('   '));
    await flush();

    expect(real(), isEmpty);
    expect(await history.loadAll(), isEmpty);
  });

  test(
    'a reader error still becomes a noRead record, with no history',
    () async {
      client.push(
        KeyenceScanResult(
          data: '',
          timestamp: DateTime.now(),
          rawResponse: 'ERROR,71',
          isError: true,
          errorMessage: 'ERROR,71',
        ),
      );
      await flush();

      final records = real();
      expect(records, hasLength(1));
      expect(records.single.status, InspectionStatus.noRead);
      expect(records.single.message, 'ERROR,71');
      expect(records.single.barcode, isNull);
      expect(await history.loadAll(), isEmpty);
    },
  );

  test('with the guide profile, an OK reply is dropped', () async {
    pipeline.dispose();
    pipeline = build(
      classifier: Sr751MessageClassifier(
        profile: const Sr751ReplyProfile.guideDocumented(),
      ),
    );

    client.push(line('OK'));
    await flush();

    expect(real(), isEmpty);
    expect(await history.loadAll(), isEmpty);
  });

  test(
    'KNOWN LIMIT: the default profile still treats OK as a barcode',
    () async {
      // Pins today's behaviour until real SR-751 replies are captured. If you
      // change the default profile, update this test on purpose.
      client.push(line('OK'));
      await waitFor(() => pipeline.inspections.isNotEmpty);
      await flush();

      expect(real(), hasLength(1));
      expect(real().single.barcode, 'OK');
    },
  );

  test(
    'with a header profile, only lines with the header are barcodes',
    () async {
      pipeline.dispose();
      pipeline = build(
        classifier: Sr751MessageClassifier(
          profile: const Sr751ReplyProfile(name: 'header', barcodePrefix: 'D:'),
        ),
      );

      client.push(line('ABC', raw: 'D:ABC'));
      await waitFor(() => pipeline.inspections.isNotEmpty);
      client.push(line('STATUS READY'));
      await flush();

      final records = real();
      expect(records, hasLength(1));
      expect(records.single.barcode, 'ABC');
      expect(await history.loadAll(), hasLength(1));
    },
  );

  test('a dropped line does not cancel the acquire timer', () async {
    pipeline.dispose();
    pipeline = build(
      classifier: Sr751MessageClassifier(
        profile: const Sr751ReplyProfile.guideDocumented(),
      ),
      acquireTimeout: const Duration(milliseconds: 400),
    );

    await pipeline.triggerInspection();
    expect(pipeline.currentStatus, InspectionStatus.acquiring);

    client.push(line('OK'));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(pipeline.currentStatus, InspectionStatus.acquiring);
    expect(pipeline.inspections, isEmpty);

    await waitFor(() => pipeline.inspections.isNotEmpty);
    expect(pipeline.currentStatus, InspectionStatus.noRead);
    expect(pipeline.inspections.single.message, 'No response from reader');
  });

  test('a barcode followed by an OK reply leaves exactly one record', () async {
    pipeline.dispose();
    pipeline = build(
      classifier: Sr751MessageClassifier(
        profile: const Sr751ReplyProfile.guideDocumented(),
      ),
    );

    client.push(line('LOT-B2'));
    await waitFor(() => pipeline.inspections.isNotEmpty);
    client.push(line('OK'));
    await flush();

    final records = real();
    expect(records, hasLength(1));
    expect(records.single.barcode, 'LOT-B2');
    expect(await history.loadAll(), hasLength(1));
  });
}
