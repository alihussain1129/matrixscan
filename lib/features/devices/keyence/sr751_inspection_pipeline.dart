import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/image_storage_service.dart';
import '../../history/history_entry.dart';
import '../../history/history_repository.dart';
import '../../ocr/controllers/ocr_controller.dart';
import '../../ocr/models/ocr_record.dart';
import '../../ocr/models/ocr_result.dart';
import '../../ocr/services/ocr_engine.dart';
import '../../ocr/services/ocr_history_repository.dart';
import '../../ocv/models/ocv_evaluation_result.dart';
import '../../ocv/models/ocv_rule.dart';
import '../../ocv/services/ocv_engine.dart';
import 'keyence_ftp_receiver.dart';
import 'keyence_sr751_client.dart';

enum InspectionStatus {
  idle,
  acquiring,
  processing,
  pass,
  fail,
  noRead,
}

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

/// Coordinates Keyence SR-751 communication, FTP image transfer, offline OCR,
/// and verification into an automated industrial inspection pipeline.
class Sr751InspectionPipeline extends ChangeNotifier {
  Sr751InspectionPipeline({
    required this.client,
    required this.ftpReceiver,
    required this.ocrEngine,
    required this.ocrHistory,
    required this.historyRepo,
    required this.imageStorage,
    this.ocvEngine = const OcvEngine(),
  }) {
    _initListeners();
  }

  final KeyenceSr751Client client;
  final KeyenceFtpReceiver ftpReceiver;
  final OcrEngine ocrEngine;
  final OcrHistoryRepository ocrHistory;
  final HistoryRepository historyRepo;
  final ImageStorageService imageStorage;
  final OcvEngine ocvEngine;

  StreamSubscription? _scanSub;
  StreamSubscription? _ftpSub;

  final List<IndustrialInspectionRecord> _inspections = [];
  List<IndustrialInspectionRecord> get inspections => List.unmodifiable(_inspections);

  InspectionStatus _currentStatus = InspectionStatus.idle;
  InspectionStatus get currentStatus => _currentStatus;

  String? _expectedOcvPattern;
  String? get expectedOcvPattern => _expectedOcvPattern;
  set expectedOcvPattern(String? pattern) {
    _expectedOcvPattern = pattern;
    notifyListeners();
  }

  bool _autoOcr = true;
  bool get autoOcr => _autoOcr;
  set autoOcr(bool val) {
    _autoOcr = val;
    notifyListeners();
  }

  void _initListeners() {
    _scanSub = client.scanStream.listen(_onKeyenceBarcode);
    _ftpSub = ftpReceiver.onImageReceived.listen(_onFtpImageReceived);
  }

  /// Triggers a hardware inspection by issuing 'LON' and requesting FTP image.
  Future<void> triggerInspection() async {
    _currentStatus = InspectionStatus.acquiring;
    notifyListeners();

    final sent = await client.triggerRead();
    if (!sent) {
      _currentStatus = InspectionStatus.fail;
      notifyListeners();
    }
  }

  Future<void> _onKeyenceBarcode(KeyenceScanResult result) async {
    final stopwatch = Stopwatch()..start();
    final now = DateTime.now();
    final id = 'insp_${now.microsecondsSinceEpoch}';

    if (result.isError) {
      final rec = IndustrialInspectionRecord(
        id: id,
        timestamp: now,
        status: InspectionStatus.noRead,
        message: result.errorMessage ?? 'No Read',
      );
      _inspections.insert(0, rec);
      _currentStatus = InspectionStatus.noRead;
      notifyListeners();
      return;
    }

    _currentStatus = InspectionStatus.processing;
    notifyListeners();

    // Save barcode to history
    await historyRepo.add(
      kind: HistoryKind.barcode,
      source: HistorySource.live,
      text: result.data,
      format: 'Keyence SR-751',
    );

    var inspection = IndustrialInspectionRecord(
      id: id,
      timestamp: now,
      status: InspectionStatus.pass,
      barcode: result.data,
      barcodeFormat: 'Industrial Code',
      processingTimeMs: stopwatch.elapsedMilliseconds,
    );

    _inspections.insert(0, inspection);
    _currentStatus = InspectionStatus.pass;
    notifyListeners();
  }

  Future<void> _onFtpImageReceived(KeyenceFtpImageReceived event) async {
    final stopwatch = Stopwatch()..start();
    debugPrint('[INSPECTION] CMOS Frame received from SR-751: ${event.file.path}');

    if (_inspections.isNotEmpty && _inspections.first.imagePath == null) {
      // Correlate with recent trigger
      var latest = _inspections.first;
      _inspections.removeAt(0);

      String? ocrText;
      bool? ocvPassed;

      if (_autoOcr) {
        _currentStatus = InspectionStatus.processing;
        notifyListeners();

        try {
          final ocrResult = await ocrEngine.recognizeFile(event.file.path);
          if (ocrResult.error == null) {
            ocrText = ocrResult.fullText;

            // Perform OCV Verification if pattern provided
            if (_expectedOcvPattern != null &&
                _expectedOcvPattern!.isNotEmpty &&
                ocrText.isNotEmpty) {
              final eval = ocvEngine.evaluate(
                ocrText,
                OcvRule(
                  id: 'sr751_ocv',
                  name: 'Keyence CMOS OCV',
                  type: OcvRuleType.regex,
                  pattern: _expectedOcvPattern!,
                ),
                confidence: ocrResult.confidence ?? 1.0,
              );
              ocvPassed = eval.isPass;
            }

            // Save to dedicated OCR History
            await ocrHistory.addRecord(
              OcrRecord(
                id: 'ocr_${DateTime.now().microsecondsSinceEpoch}',
                imagePath: event.file.path,
                text: ocrText,
                rawText: ocrText,
                createdAt: DateTime.now(),
                confidence: ocrResult.confidence ?? 0.0,
                engine: 'Keyence Vision Pipeline',
                ocvPattern: _expectedOcvPattern,
                ocvPassed: ocvPassed,
              ),
            );
          }
        } catch (e) {
          debugPrint('[INSPECTION] OCR error on CMOS frame: $e');
        }
      }

      final status = (ocvPassed == false) ? InspectionStatus.fail : InspectionStatus.pass;
      latest = latest.copyWith(
        imagePath: event.file.path,
        ocrText: ocrText,
        ocvPattern: _expectedOcvPattern,
        ocvPassed: ocvPassed,
        status: status,
        processingTimeMs: stopwatch.elapsedMilliseconds,
      );

      _inspections.insert(0, latest);
      _currentStatus = status;
      notifyListeners();
    } else {
      // Standalone image acquisition
      final now = DateTime.now();
      String? ocrText;
      bool? ocvPassed;

      if (_autoOcr) {
        try {
          final ocrResult = await ocrEngine.recognizeFile(event.file.path);
          if (ocrResult.error == null) {
            ocrText = ocrResult.fullText;
            if (_expectedOcvPattern != null &&
                _expectedOcvPattern!.isNotEmpty &&
                ocrText.isNotEmpty) {
              final reg = RegExp(_expectedOcvPattern!, caseSensitive: false);
              ocvPassed = reg.hasMatch(ocrText);
            }
          }
        } catch (_) {}
      }

      final rec = IndustrialInspectionRecord(
        id: 'insp_${now.microsecondsSinceEpoch}',
        timestamp: now,
        status: (ocvPassed == false) ? InspectionStatus.fail : InspectionStatus.pass,
        imagePath: event.file.path,
        ocrText: ocrText,
        ocvPattern: _expectedOcvPattern,
        ocvPassed: ocvPassed,
        processingTimeMs: stopwatch.elapsedMilliseconds,
      );

      _inspections.insert(0, rec);
      _currentStatus = rec.status;
      notifyListeners();
    }
  }

  void clearInspections() {
    _inspections.clear();
    _currentStatus = InspectionStatus.idle;
    notifyListeners();
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _ftpSub?.cancel();
    super.dispose();
  }
}

final sr751InspectionPipelineProvider =
    Provider<Sr751InspectionPipeline>((ref) {
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
