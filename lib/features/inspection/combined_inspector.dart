import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/image_storage_service.dart';
import '../ocr/controllers/ocr_controller.dart';
import '../ocr/models/ocr_result.dart';
import '../scanner/captured_frame.dart';
import '../scanner/scanner_controller.dart';
import 'inspection_log.dart';
import 'inspection_row.dart';
import '../../core/config/config_controller.dart';

@immutable
class CombinedSettings {
  const CombinedSettings({this.ocrWithDecode = true, this.keepImages = false});

  final bool ocrWithDecode;
  final bool keepImages;

  CombinedSettings copyWith({bool? ocrWithDecode, bool? keepImages}) =>
      CombinedSettings(
        ocrWithDecode: ocrWithDecode ?? this.ocrWithDecode,
        keepImages: keepImages ?? this.keepImages,
      );
}

class CombinedSettingsNotifier extends Notifier<CombinedSettings> {
  @override
  CombinedSettings build() {
    final c = ref.read(configControllerProvider);
    return CombinedSettings(
      ocrWithDecode: c.decoder.ocrWithDecode,
      keepImages: c.storage.keepImages,
    );
  }

  void setOcrWithDecode(bool v) {
    state = state.copyWith(ocrWithDecode: v);
    unawaited(_save());
  }

  void setKeepImages(bool v) {
    state = state.copyWith(keepImages: v);
    unawaited(_save());
  }

  Future<void> _save() async {
    try {
      await ref.read(configControllerProvider.notifier).patch({
        'decoder': {'ocrWithDecode': state.ocrWithDecode},
        'storage': {'keepImages': state.keepImages},
      });
    } catch (_) {}
  }
}

final combinedSettingsProvider =
    NotifierProvider<CombinedSettingsNotifier, CombinedSettings>(
      CombinedSettingsNotifier.new,
    );

@immutable
class InspectorState {
  const InspectorState({this.latest, this.ocrBusy = false, this.count = 0});

  final InspectionRow? latest;
  final bool ocrBusy;

  /// Rows recorded since the app started. Screens reload when it changes.
  final int count;

  InspectorState copyWith({InspectionRow? latest, bool? ocrBusy, int? count}) =>
      InspectorState(
        latest: latest ?? this.latest,
        ocrBusy: ocrBusy ?? this.ocrBusy,
        count: count ?? this.count,
      );
}

/// Turns every decoder event into one inspection row. When enabled it reads
/// the printed text from the same live camera frame and compares it with the
/// decoded data. Only one OCR job runs at a time; an event that arrives while
/// OCR is busy is still recorded, without OCR.
class CombinedInspector extends Notifier<InspectorState> {
  bool _ocrBusy = false;

  @override
  InspectorState build() => const InspectorState();

  Future<void> record({
    required String raw,
    required String symbology,
    required String source,
    required double decodeMs,
  }) async {
    final settings = ref.read(combinedSettingsProvider);
    String? ocrText;
    double? ocrMs;
    String? note;
    String? imagePath;

    if (settings.ocrWithDecode && source == 'live') {
      if (_ocrBusy) {
        note = 'OCR skipped: the previous text read was still running';
      } else {
        _ocrBusy = true;
        state = state.copyWith(ocrBusy: true);
        try {
          final read = await _readPrintedText(keepImage: settings.keepImages);
          ocrText = read.text;
          ocrMs = read.ms;
          note = read.note;
          imagePath = read.imagePath;
        } catch (e) {
          note = 'OCR failed: $e';
        } finally {
          _ocrBusy = false;
          if (ref.mounted) state = state.copyWith(ocrBusy: false);
        }
      }
    }

    if (!ref.mounted) return;
    final row = await ref
        .read(inspectionLogProvider)
        .recordDecode(
          raw: raw,
          symbology: symbology,
          source: source,
          decodeMs: decodeMs,
          ocrText: ocrText,
          ocrMs: ocrMs,
          ocrNote: note,
          imagePath: imagePath,
        );
    if (row != null && ref.mounted) {
      state = state.copyWith(latest: row, count: state.count + 1);
    }
  }

  Future<({String? text, double? ms, String? note, String? imagePath})>
  _readPrintedText({required bool keepImage}) async {
    final frame = await ref
        .read(scannerControllerProvider.notifier)
        .grabFrame();
    if (frame == null) {
      return (
        text: null,
        ms: null,
        note: 'OCR skipped: no camera frame arrived',
        imagePath: null,
      );
    }
    final encoded = await encodeFrame(frame);
    if (encoded == null) {
      return (
        text: null,
        ms: null,
        note: 'OCR skipped: the frame could not be converted',
        imagePath: null,
      );
    }
    String? imagePath;
    debugPrint('[exalted] keepImage=$keepImage');
    if (keepImage) {
      try {
        imagePath = await ref
            .read(imageStorageServiceProvider)
            .saveImageBytes(encoded.png, prefix: 'inspection', ext: 'png');
        debugPrint('[exalted] image saved: $imagePath');
      } catch (e, st) {
        debugPrint('[exalted] image save FAILED: $e\n$st');
      }
    }
    final dir = await Directory.systemTemp.createTemp('exalted_live_ocr_');
    try {
      final file = File('${dir.path}${Platform.pathSeparator}frame.png');
      await file.writeAsBytes(encoded.png, flush: true);
      final sw = Stopwatch()..start();
      final result = await ref.read(ocrEngineProvider).recognizeFile(file.path);
      final ms = sw.elapsedMicroseconds / 1000;
      if (result.success) {
        return (
          text: result.fullText,
          ms: ms,
          note: null,
          imagePath: imagePath,
        );
      }
      if (result.error?.type == OcrErrorType.noTextFound) {
        return (text: '', ms: ms, note: null, imagePath: imagePath);
      }
      return (
        text: null,
        ms: ms,
        note: 'OCR unavailable: ${result.error?.message ?? 'unknown error'}',
        imagePath: imagePath,
      );
    } finally {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    }
  }
}

final combinedInspectorProvider =
    NotifierProvider<CombinedInspector, InspectorState>(CombinedInspector.new);
