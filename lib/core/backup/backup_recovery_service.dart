import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../features/history/history_entry.dart';
import '../../features/history/history_repository.dart';
import '../../features/ocr/models/ocr_record.dart';
import '../../features/ocr/services/ocr_history_repository.dart';
import '../../features/ocv/models/ocv_rule.dart';
import '../../features/ocv/services/ocv_rules_repository.dart';
import '../storage/image_storage_service.dart';

/// Summary of a backup restoration operation.
class BackupRestoreSummary {
  const BackupRestoreSummary({
    required this.decoderRecordsRestored,
    required this.ocrRecordsRestored,
    required this.ocvRulesRestored,
    required this.missingImagesCount,
    this.error,
  });

  final int decoderRecordsRestored;
  final int ocrRecordsRestored;
  final int ocvRulesRestored;
  final int missingImagesCount;
  final String? error;

  bool get isSuccess => error == null;

  @override
  String toString() =>
      'Restored $decoderRecordsRestored barcodes, $ocrRecordsRestored OCR records, '
      '$ocvRulesRestored rules (missing images: $missingImagesCount)';
}

/// Service managing offline backup creation, data verification, and disaster recovery
/// across barcode history, OCR records, OCV recipes, and preserved inspection images.
class BackupRecoveryService {
  BackupRecoveryService({
    required this.historyRepo,
    required this.ocrRepo,
    required this.ocvRulesRepo,
    required this.imageStorage,
    Future<Directory> Function()? directoryProvider,
  }) : _directoryProvider =
           directoryProvider ?? getApplicationDocumentsDirectory;

  final HistoryRepository historyRepo;
  final OcrHistoryRepository ocrRepo;
  final OcvRulesRepository ocvRulesRepo;
  final ImageStorageService imageStorage;
  final Future<Directory> Function() _directoryProvider;

  static const int currentSchemaVersion = 1;

  /// Creates a complete JSON backup payload string containing all inspection
  /// records, OCR results, and OCV inspection rules.
  Future<String> exportBackupJson() async {
    final decoderEntries = await historyRepo.loadAll();
    final ocrRecords = await ocrRepo.loadAll();
    final ocvRules = await ocvRulesRepo.loadRules();

    final payload = {
      'exalted_schema_version': currentSchemaVersion,
      'exported_at': DateTime.now().toIso8601String(),
      'platform': Platform.operatingSystem,
      'decoder_history': [for (final e in decoderEntries) e.toJson()],
      'ocr_history': [for (final r in ocrRecords) r.toJson()],
      'ocv_rules': [for (final r in ocvRules) r.toJson()],
    };

    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  /// Writes a timestamped backup file to the documents or target directory.
  Future<File> createBackupFile({String? customPath}) async {
    final jsonString = await exportBackupJson();
    final String filePath;

    if (customPath != null) {
      filePath = customPath;
    } else {
      final dir = await _directoryProvider();
      final now = DateTime.now();
      final timestamp =
          '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_'
          '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
      filePath =
          '${dir.path}${Platform.pathSeparator}exalted_backup_$timestamp.json';
    }

    final file = File(filePath);
    await file.writeAsString(jsonString, flush: true);
    debugPrint('[BACKUP] Created backup archive at $filePath');
    return file;
  }

  /// Restores records from a JSON string, optionally merging with existing entries.
  Future<BackupRestoreSummary> restoreBackupJson(
    String jsonString, {
    bool merge = true,
  }) async {
    try {
      final raw = jsonDecode(jsonString);
      if (raw is! Map) {
        return const BackupRestoreSummary(
          decoderRecordsRestored: 0,
          ocrRecordsRestored: 0,
          ocvRulesRestored: 0,
          missingImagesCount: 0,
          error: 'Invalid backup file format: root object is not a JSON map.',
        );
      }

      final schemaVersion = raw['exalted_schema_version'] as int? ?? 1;
      if (schemaVersion > currentSchemaVersion) {
        return BackupRestoreSummary(
          decoderRecordsRestored: 0,
          ocrRecordsRestored: 0,
          ocvRulesRestored: 0,
          missingImagesCount: 0,
          error:
              'Backup file schema version ($schemaVersion) is newer than supported version ($currentSchemaVersion). Upgrade Exalted.',
        );
      }

      int restoredDecoder = 0;
      int restoredOcr = 0;
      int restoredRules = 0;
      int missingImages = 0;

      // 1. Restore Decoder History
      if (raw['decoder_history'] is List) {
        final existingEntries = merge
            ? await historyRepo.loadAll()
            : <HistoryEntry>[];
        final existingIds = existingEntries.map((e) => e.id).toSet();

        for (final item in raw['decoder_history'] as List) {
          final entry = HistoryEntry.fromJson(item);
          if (entry != null && !existingIds.contains(entry.id)) {
            if (entry.imagePath != null &&
                !File(entry.imagePath!).existsSync()) {
              missingImages++;
            }
            await historyRepo.add(
              kind: entry.kind,
              source: entry.source,
              text: entry.text,
              format: entry.format,
              imagePath: entry.imagePath,
              processingDurationMs: entry.processingDurationMs,
            );
            restoredDecoder++;
          }
        }
      }

      // 2. Restore OCR History
      if (raw['ocr_history'] is List) {
        final existingOcr = merge ? await ocrRepo.loadAll() : <OcrRecord>[];
        final existingOcrIds = existingOcr.map((r) => r.id).toSet();

        for (final item in raw['ocr_history'] as List) {
          final rec = OcrRecord.fromJson(item);
          if (rec != null && !existingOcrIds.contains(rec.id)) {
            if (rec.imagePath.isNotEmpty && !File(rec.imagePath).existsSync()) {
              missingImages++;
            }
            await ocrRepo.addRecord(rec);
            restoredOcr++;
          }
        }
      }

      // 3. Restore OCV Rules
      if (raw['ocv_rules'] is List) {
        for (final item in raw['ocv_rules'] as List) {
          final rule = OcvRule.fromJson(item);
          if (rule != null) {
            await ocvRulesRepo.upsertRule(rule);
            restoredRules++;
          }
        }
      }

      return BackupRestoreSummary(
        decoderRecordsRestored: restoredDecoder,
        ocrRecordsRestored: restoredOcr,
        ocvRulesRestored: restoredRules,
        missingImagesCount: missingImages,
      );
    } catch (e) {
      return BackupRestoreSummary(
        decoderRecordsRestored: 0,
        ocrRecordsRestored: 0,
        ocvRulesRestored: 0,
        missingImagesCount: 0,
        error: 'Backup restoration failed: $e',
      );
    }
  }

  /// Checks integrity of all preserved image references on the device.
  Future<Map<String, dynamic>> checkStorageIntegrity() async {
    final decoderEntries = await historyRepo.loadAll();
    final ocrRecords = await ocrRepo.loadAll();

    int totalImages = 0;
    int validImages = 0;
    final missingImagePaths = <String>[];

    for (final e in decoderEntries) {
      if (e.imagePath != null && e.imagePath!.isNotEmpty) {
        totalImages++;
        if (File(e.imagePath!).existsSync()) {
          validImages++;
        } else {
          missingImagePaths.add(e.imagePath!);
        }
      }
    }

    for (final r in ocrRecords) {
      if (r.imagePath.isNotEmpty) {
        totalImages++;
        if (File(r.imagePath).existsSync()) {
          validImages++;
        } else {
          missingImagePaths.add(r.imagePath);
        }
      }
    }

    final totalStorageBytes = await imageStorage.calculateStorageSizeBytes();

    return {
      'totalImagesTracked': totalImages,
      'validImages': validImages,
      'missingImages': missingImagePaths.length,
      'missingPaths': missingImagePaths,
      'totalStorageBytes': totalStorageBytes,
      'isHealthy': missingImagePaths.isEmpty,
    };
  }
}

final backupRecoveryServiceProvider = Provider<BackupRecoveryService>((ref) {
  final historyRepo = ref.watch(historyRepositoryProvider);
  final ocrRepo = ref.watch(ocrHistoryRepositoryProvider);
  final ocvRulesRepo = ref.watch(ocvRulesRepositoryProvider);
  final imageStorage = ref.watch(imageStorageServiceProvider);

  return BackupRecoveryService(
    historyRepo: historyRepo,
    ocrRepo: ocrRepo,
    ocvRulesRepo: ocvRulesRepo,
    imageStorage: imageStorage,
  );
});
