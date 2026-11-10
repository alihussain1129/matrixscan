import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/storage/image_storage_service.dart';
import '../models/ocr_record.dart';
import '../../../core/config/data_directory_provider.dart';

/// Dedicated, offline repository for managing OCR records and document inspections.
///
/// Completely independent from the barcode/decoder history.
class OcrHistoryRepository {
  OcrHistoryRepository({
    Future<Directory> Function()? directoryProvider,
    ImageStorageService? imageStorageService,
    this.maxEntries = 5000,
  }) : _directoryProvider =
           directoryProvider ?? getApplicationDocumentsDirectory,
       _imageStorageService = imageStorageService ?? ImageStorageService();

  final Future<Directory> Function() _directoryProvider;
  final ImageStorageService _imageStorageService;
  final int maxEntries;

  Future<void> _queue = Future<void>.value();

  Future<T> _serialized<T>(Future<T> Function() action) {
    final result = _queue.then((_) => action());
    _queue = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  Future<File> _file() async {
    final dir = await _directoryProvider();
    return File('${dir.path}${Platform.pathSeparator}ocr_history.json');
  }

  Future<List<OcrRecord>> _read() async {
    final file = await _file();
    if (!await file.exists()) return <OcrRecord>[];
    try {
      final raw = jsonDecode(await file.readAsString());
      if (raw is! List) return <OcrRecord>[];
      final records = <OcrRecord>[];
      for (final item in raw) {
        final rec = OcrRecord.fromJson(item);
        if (rec != null) records.add(rec);
      }
      return records;
    } catch (_) {
      try {
        await file.copy('${file.path}.corrupt');
      } catch (_) {}
      return <OcrRecord>[];
    }
  }

  Future<void> _write(List<OcrRecord> records) async {
    final file = await _file();
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(
      jsonEncode([for (final r in records) r.toJson()]),
      flush: true,
    );
    await tmp.rename(file.path);
  }

  /// Loads all OCR records, newest first, pinned on top.
  Future<List<OcrRecord>> loadAll() => _serialized(_read);

  /// Saves a new OCR record to private history.
  Future<OcrRecord> addRecord(OcrRecord record) {
    return _serialized<OcrRecord>(() async {
      final records = await _read();
      // Insert newest at beginning (after pinned items if any, or at index 0)
      records.insert(0, record);

      // Trim oldest non-pinned records if over maxEntries
      if (records.length > maxEntries) {
        var extra = records.length - maxEntries;
        for (var i = records.length - 1; i >= 0 && extra > 0; i--) {
          if (!records[i].pinned) {
            records.removeAt(i);
            extra--;
          }
        }
      }

      await _write(records);
      return record;
    });
  }

  /// Updates an existing record (e.g. edited text or verification result).
  Future<bool> updateRecord(OcrRecord updated) {
    return _serialized<bool>(() async {
      final records = await _read();
      final index = records.indexWhere((r) => r.id == updated.id);
      if (index == -1) return false;
      records[index] = updated;
      await _write(records);
      return true;
    });
  }

  /// Toggles pinned status for quick access.
  Future<bool> togglePin(String id) {
    return _serialized<bool>(() async {
      final records = await _read();
      final index = records.indexWhere((r) => r.id == id);
      if (index == -1) return false;
      records[index] = records[index].copyWith(pinned: !records[index].pinned);
      await _write(records);
      return true;
    });
  }

  /// Deletes a specific record and optionally removes the associated image file.
  Future<bool> deleteRecord(String id, {bool deleteStoredImage = true}) {
    return _serialized<bool>(() async {
      final records = await _read();
      final index = records.indexWhere((r) => r.id == id);
      if (index == -1) return false;
      final removed = records.removeAt(index);
      await _write(records);

      if (deleteStoredImage && removed.imagePath.isNotEmpty) {
        await _imageStorageService.deleteImage(removed.imagePath);
      }
      return true;
    });
  }

  /// Clears all OCR history.
  Future<void> clearAll({bool deleteImages = false}) {
    return _serialized<void>(() async {
      if (deleteImages) {
        final records = await _read();
        for (final r in records) {
          if (r.imagePath.isNotEmpty) {
            await _imageStorageService.deleteImage(r.imagePath);
          }
        }
      }
      final file = await _file();
      if (await file.exists()) {
        await file.delete();
      }
    });
  }

  /// Searches and filters records.
  List<OcrRecord> filter(
    List<OcrRecord> records,
    String query, {
    String? language,
    bool? ocvPassed,
  }) {
    final q = query.trim().toLowerCase();
    return records.where((r) {
      if (language != null && language.isNotEmpty && r.language != language) {
        return false;
      }
      if (ocvPassed != null && r.ocvPassed != ocvPassed) {
        return false;
      }
      if (q.isEmpty) return true;
      return r.text.toLowerCase().contains(q) ||
          r.rawText.toLowerCase().contains(q) ||
          r.engine.toLowerCase().contains(q) ||
          (r.ocvPattern?.toLowerCase().contains(q) ?? false);
    }).toList();
  }
}

final ocrHistoryRepositoryProvider = Provider<OcrHistoryRepository>((ref) {
  final imageStorage = ref.watch(imageStorageServiceProvider);
  return OcrHistoryRepository(
    imageStorageService: imageStorage,
    directoryProvider: ref.watch(dataDirectoryProvider),
  );
});
