import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/image_storage_service.dart';
import '../../history/history_entry.dart';
import '../../history/history_repository.dart';
import '../../ocr/controllers/ocr_controller.dart';
import '../../ocr/models/ocr_record.dart';
import '../../ocr/services/ocr_engine.dart';
import '../../ocr/services/ocr_history_repository.dart';
import '../../ocv/models/ocv_rule.dart';
import '../../ocv/services/ocv_engine.dart';
import '../core/pairing_window.dart';
import 'keyence_ftp_receiver.dart';
import 'keyence_sr751_client.dart';
import 'sr751_message_classifier.dart';

enum InspectionStatus { idle, acquiring, processing, pass, fail, noRead }

/// A comprehensive industrial machine-vision inspection record combining optical
/// barcode reading, CMOS image acquisition, and offline OCR/OCV verification.
class IndustrialInspectionRecord {
  const IndustrialInspectionRecord({
    required this.id,
    required this.timestamp,
    required this.status,
    this.barcode,
    this.barcodeFormat,
    this.imagePath,
    this.ocrText,
    this.ocvPattern,
    this.ocvPassed,
    this.processingTimeMs = 0,
    this.message,
  });

  final String id;
  final DateTime timestamp;
  final InspectionStatus status;
  final String? barcode;
  final String? barcodeFormat;
  final String? imagePath;
  final String? ocrText;
  final String? ocvPattern;
  final bool? ocvPassed;
  final int processingTimeMs;
  final String? message;

  IndustrialInspectionRecord copyWith({
    InspectionStatus? status,
    String? barcode,
    String? barcodeFormat,
    String? imagePath,
    String? ocrText,
    String? ocvPattern,
    bool? ocvPassed,
    int? processingTimeMs,
    String? message,
  }) {
    return IndustrialInspectionRecord(
      id: id,
      timestamp: timestamp,
      status: status ?? this.status,
      barcode: barcode ?? this.barcode,
      barcodeFormat: barcodeFormat ?? this.barcodeFormat,
      imagePath: imagePath ?? this.imagePath,
      ocrText: ocrText ?? this.ocrText,
      ocvPattern: ocvPattern ?? this.ocvPattern,
      ocvPassed: ocvPassed ?? this.ocvPassed,
      processingTimeMs: processingTimeMs ?? this.processingTimeMs,
      message: message ?? this.message,
    );
  }
}

class _OcrOutcome {
  const _OcrOutcome({this.text, this.ocvPassed});

  final String? text;
  final bool? ocvPassed;
}

/// Coordinates Keyence SR-751 communication, FTP image transfer, offline OCR,
/// and verification into an automated industrial inspection pipeline.
///
/// The barcode (TCP) and the image (FTP) arrive on separate channels in either
/// order. The first to arrive creates a record that waits up to [pairWindow]
/// for the other; a later arrival outside that window starts a new record.
class Sr751InspectionPipeline extends ChangeNotifier {
  Sr751InspectionPipeline({
    required this.client,
    required this.ftpReceiver,
    required this.ocrEngine,
    required this.ocrHistory,
    required this.historyRepo,
    required this.imageStorage,
    this.ocvEngine = const OcvEngine(),
    this.pairWindow = const Duration(seconds: 5),
    this.acquireTimeout = const Duration(seconds: 10),
    this.maxInspections = 500,
    Sr751MessageClassifier? classifier,
  }) : _pairing = PairingWindow(window: pairWindow),
       _classifier = classifier ?? Sr751MessageClassifier() {
    _initListeners();
  }

  final KeyenceSr751Client client;
  final KeyenceFtpReceiver ftpReceiver;
  final OcrEngine ocrEngine;
  final OcrHistoryRepository ocrHistory;
  final HistoryRepository historyRepo;
  final ImageStorageService imageStorage;
  final OcvEngine ocvEngine;

  /// How long a record waits for its barcode or image.
  final Duration pairWindow;

  /// How long to wait for any reply after [triggerInspection].
  final Duration acquireTimeout;

  /// Most records kept in memory; the oldest are dropped.
  final int maxInspections;

  final PairingWindow _pairing;

  /// Decides which incoming lines are barcodes. Lines that are neither a
  /// barcode nor a reader error are ignored, never stored as scans.
  final Sr751MessageClassifier _classifier;

  StreamSubscription<KeyenceScanResult>? _scanSub;
  StreamSubscription<KeyenceFtpImageReceived>? _ftpSub;
  Timer? _acquireTimer;
  Future<void> _queue = Future<void>.value();
  bool _disposed = false;

  final List<IndustrialInspectionRecord> _inspections = [];
  List<IndustrialInspectionRecord> get inspections =>
      List.unmodifiable(_inspections);

  InspectionStatus _currentStatus = InspectionStatus.idle;
  InspectionStatus get currentStatus => _currentStatus;

  String? _expectedOcvPattern;
  String? get expectedOcvPattern => _expectedOcvPattern;
  set expectedOcvPattern(String? pattern) {
    _expectedOcvPattern = pattern;
    _notify();
  }

  bool _autoOcr = true;
  bool get autoOcr => _autoOcr;
  set autoOcr(bool val) {
    _autoOcr = val;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _initListeners() {
    _scanSub = client.scanStream.listen(
      (result) => _enqueue(() => _onKeyenceBarcode(result)),
    );
    _ftpSub = ftpReceiver.onImageReceived.listen(
      (event) => _enqueue(() => _onFtpImageReceived(event)),
    );
  }

  /// Runs events strictly one after another, so a slow OCR pass can never
  /// interleave with the next barcode or image.
  void _enqueue(Future<void> Function() task) {
    _queue = _queue.then((_) => task()).catchError((Object e) {
      debugPrint('[INSPECTION] Event error: $e');
    });
  }

  void _startAcquireTimer() {
    _acquireTimer?.cancel();
    _acquireTimer = Timer(acquireTimeout, () {
      if (_disposed || _currentStatus != InspectionStatus.acquiring) return;
      final now = DateTime.now();
      _addRecord(
        IndustrialInspectionRecord(
          id: 'insp_${now.microsecondsSinceEpoch}',
          timestamp: now,
          status: InspectionStatus.noRead,
          message: 'No response from reader',
        ),
      );
      _currentStatus = InspectionStatus.noRead;
      _notify();
    });
  }

  void _cancelAcquireTimer() {
    _acquireTimer?.cancel();
    _acquireTimer = null;
  }

  void _addRecord(IndustrialInspectionRecord record) {
    _inspections.insert(0, record);
    if (_inspections.length > maxInspections) {
      _inspections.removeRange(maxInspections, _inspections.length);
    }
  }

  int _indexOf(String? id) =>
      id == null ? -1 : _inspections.indexWhere((r) => r.id == id);

  /// Triggers a hardware inspection by issuing 'LON'.
  Future<void> triggerInspection() async {
    _currentStatus = InspectionStatus.acquiring;
    _notify();
    _startAcquireTimer();

    final sent = await client.triggerRead();
    if (!sent) {
      _cancelAcquireTimer();
      _currentStatus = InspectionStatus.fail;
      _notify();
    }
  }

  Future<void> _onKeyenceBarcode(KeyenceScanResult result) async {
    if (_disposed) return;
    final stopwatch = Stopwatch()..start();
    final now = DateTime.now();
    final id = 'insp_${now.microsecondsSinceEpoch}';
    if (!result.isError) {
      final raw = result.rawResponse.isNotEmpty
          ? result.rawResponse
          : result.data;
      if (_classifier.classify(raw).kind != Sr751MessageKind.barcode) {
        debugPrint('[INSPECTION] Ignored non-barcode line');
        return;
      }
    }
    _cancelAcquireTimer();

    if (result.isError) {
      _addRecord(
        IndustrialInspectionRecord(
          id: id,
          timestamp: now,
          status: InspectionStatus.noRead,
          message: result.errorMessage ?? 'No Read',
        ),
      );
      _currentStatus = InspectionStatus.noRead;
      _notify();
      return;
    }

    // Decide at arrival time whether an earlier image is waiting for this.
    final waitingId = _pairing.claim(PairSide.barcode);

    _currentStatus = InspectionStatus.processing;
    _notify();

    await historyRepo.add(
      kind: HistoryKind.barcode,
      source: HistorySource.live,
      text: result.data,
      format: 'Keyence SR-751',
    );
    if (_disposed) return;

    final index = _indexOf(waitingId);
    if (index >= 0) {
      final merged = _inspections[index].copyWith(
        barcode: result.data,
        barcodeFormat: 'Industrial Code',
      );
      final status = merged.ocvPassed == false
          ? InspectionStatus.fail
          : InspectionStatus.pass;
      _inspections[index] = merged.copyWith(status: status);
      _currentStatus = status;
    } else {
      final record = IndustrialInspectionRecord(
        id: id,
        timestamp: now,
        status: InspectionStatus.pass,
        barcode: result.data,
        barcodeFormat: 'Industrial Code',
        processingTimeMs: stopwatch.elapsedMilliseconds,
      );
      _addRecord(record);
      _pairing.open(id, missing: PairSide.image);
      _currentStatus = InspectionStatus.pass;
    }
    _notify();
  }

  Future<void> _onFtpImageReceived(KeyenceFtpImageReceived event) async {
    if (_disposed) return;
    final stopwatch = Stopwatch()..start();
    debugPrint(
      '[INSPECTION] CMOS Frame received from SR-751: ${event.file.path}',
    );
    _cancelAcquireTimer();

    // Decide at arrival time whether an earlier barcode is waiting for this.
    final waitingId = _pairing.claim(PairSide.image);

    if (_autoOcr) {
      _currentStatus = InspectionStatus.processing;
      _notify();
    }

    final ocr = await _runOcr(event.file.path);
    if (_disposed) return;

    final pattern = _expectedOcvPattern;
    final status = ocr.ocvPassed == false
        ? InspectionStatus.fail
        : InspectionStatus.pass;

    final index = _indexOf(waitingId);
    if (index >= 0) {
      _inspections[index] = _inspections[index].copyWith(
        imagePath: event.file.path,
        ocrText: ocr.text,
        ocvPattern: pattern,
        ocvPassed: ocr.ocvPassed,
        status: status,
        processingTimeMs: stopwatch.elapsedMilliseconds,
      );
    } else {
      final now = DateTime.now();
      final id = 'insp_${now.microsecondsSinceEpoch}';
      _addRecord(
        IndustrialInspectionRecord(
          id: id,
          timestamp: now,
          status: status,
          imagePath: event.file.path,
          ocrText: ocr.text,
          ocvPattern: pattern,
          ocvPassed: ocr.ocvPassed,
          processingTimeMs: stopwatch.elapsedMilliseconds,
        ),
      );
      _pairing.open(id, missing: PairSide.barcode);
    }
    _currentStatus = status;
    _notify();
  }

  /// OCR plus OCV check, shared by every image path so the same text always
  /// gets the same verdict.
  Future<_OcrOutcome> _runOcr(String imagePath) async {
    if (!_autoOcr) return const _OcrOutcome();
    try {
      final ocrResult = await ocrEngine.recognizeFile(imagePath);
      if (ocrResult.error != null) return const _OcrOutcome();

      final ocrText = ocrResult.fullText;
      final pattern = _expectedOcvPattern;
      bool? ocvPassed;

      if (pattern != null && pattern.isNotEmpty && ocrText.isNotEmpty) {
        final eval = ocvEngine.evaluate(
          ocrText,
          OcvRule(
            id: 'sr751_ocv',
            name: 'Keyence CMOS OCV',
            type: OcvRuleType.regex,
            pattern: pattern,
          ),
          confidence: ocrResult.confidence ?? 1.0,
        );
        ocvPassed = eval.isPass;
      }

      await ocrHistory.addRecord(
        OcrRecord(
          id: 'ocr_${DateTime.now().microsecondsSinceEpoch}',
          imagePath: imagePath,
          text: ocrText,
          rawText: ocrText,
          createdAt: DateTime.now(),
          confidence: ocrResult.confidence ?? 0.0,
          engine: 'Keyence Vision Pipeline',
          ocvPattern: pattern,
          ocvPassed: ocvPassed,
        ),
      );
      return _OcrOutcome(text: ocrText, ocvPassed: ocvPassed);
    } catch (e) {
      debugPrint('[INSPECTION] OCR error on CMOS frame: $e');
      return const _OcrOutcome();
    }
  }

  void clearInspections() {
    _inspections.clear();
    _pairing.clear();
    _cancelAcquireTimer();
    _currentStatus = InspectionStatus.idle;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelAcquireTimer();
    _scanSub?.cancel();
    _ftpSub?.cancel();
    super.dispose();
  }
}

final sr751InspectionPipelineProvider = Provider<Sr751InspectionPipeline>((
  ref,
) {
  final client = ref.watch(keyenceSr751ClientProvider);
  final ftp = ref.watch(keyenceFtpReceiverProvider);
  final ocrEngine = ref.watch(ocrEngineProvider);
  final ocrHistory = ref.watch(ocrHistoryRepositoryProvider);
  final historyRepo = ref.watch(historyRepositoryProvider);
  final imageStorage = ref.watch(imageStorageServiceProvider);

  final ocvEngine = ref.watch(ocvEngineProvider);

  final pipeline = Sr751InspectionPipeline(
    client: client,
    ftpReceiver: ftp,
    ocrEngine: ocrEngine,
    ocrHistory: ocrHistory,
    historyRepo: historyRepo,
    imageStorage: imageStorage,
    ocvEngine: ocvEngine,
  );
  ref.onDispose(pipeline.dispose);
  return pipeline;
});
