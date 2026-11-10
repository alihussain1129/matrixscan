import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'gs1_fields.dart';
import 'inspection_row.dart';
import '../../core/config/data_directory_provider.dart';

/// Appends one row per inspection event to `inspection_rows.jsonl` (one JSON
/// object per line). Appending never rewrites earlier rows, so saving stays
/// cheap however many rows exist, and it never throws into the scanner.
class InspectionLog {
  InspectionLog({
    Future<Directory> Function()? directory,
    DateTime Function()? clock,
  }) : _directory = directory ?? getApplicationDocumentsDirectory,
       _clock = clock ?? DateTime.now;

  final Future<Directory> Function() _directory;
  final DateTime Function() _clock;

  bool _loaded = false;
  int _counter = 0;
  final Map<String, String> _serialOwner = <String, String>{};
  final Set<String> _lotsSeen = <String>{};
  String? _lastLot;

  Future<void> _queue = Future<void>.value();

  Future<T> _serialized<T>(Future<T> Function() action) {
    final result = _queue.then((_) => action());
    _queue = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  Future<File> _file() async {
    final dir = await _directory();
    return File('${dir.path}${Platform.pathSeparator}inspection_rows.jsonl');
  }

  /// Oldest first.
  Future<List<InspectionRow>> _readAll() async {
    final file = await _file();
    if (!await file.exists()) return <InspectionRow>[];
    final rows = <InspectionRow>[];
    for (final line in await file.readAsLines()) {
      if (line.trim().isEmpty) continue;
      try {
        final row = InspectionRow.fromJson(jsonDecode(line));
        if (row != null) rows.add(row);
      } catch (_) {}
    }
    return rows;
  }

  String _serialKey(InspectionRow r) => '${r.gtin ?? ''}|${r.serial}';

  void _register(InspectionRow r) {
    if (r.serial != null) _serialOwner.putIfAbsent(_serialKey(r), () => r.id);
    final lot = r.lot;
    if (lot != null) {
      _lotsSeen.add(lot);
      _lastLot = lot;
    }
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    for (final r in await _readAll()) {
      _register(r);
    }
  }

  /// Newest first.
  Future<List<InspectionRow>> loadAll() => _serialized(() async {
    return (await _readAll()).reversed.toList();
  });

  Future<void> clear() => _serialized<void>(() async {
    final file = await _file();
    if (await file.exists()) await file.delete();
    _serialOwner.clear();
    _lotsSeen.clear();
    _lastLot = null;
    _loaded = true;
  });

  static String _norm(String s) =>
      s.toUpperCase().replaceAll(RegExp(r'\s'), '');

  /// True when [value] appears in [ocrText] (case and spaces ignored).
  static bool ocrContains(String ocrText, String value) =>
      _norm(ocrText).contains(_norm(value));

  /// Labels of decoded fields whose value is not found in [ocrText].
  static List<String> ocrMissing(Map<String, String> fields, String ocrText) {
    return [
      for (final e in fields.entries)
        if (e.value.isNotEmpty && !ocrContains(ocrText, e.value))
          Gs1Fields.labels[e.key] ?? 'AI ${e.key}',
    ];
  }

  /// Evaluates and stores one inspection event. Returns the row, or null when
  /// nothing was stored.
  Future<InspectionRow?> recordDecode({
    required String raw,
    required String symbology,
    required String source,
    double? decodeMs,
    String? ocrText,
    double? ocrMs,
    String? ocrNote,
    String? imagePath,
  }) {
    return _serialized<InspectionRow?>(() async {
      if (raw.isEmpty) return null;
      try {
        await _ensureLoaded();
        final now = _clock();
        final fields = <String, String>{
          for (final f in Gs1Fields.parse(raw)) f.ai: f.value,
        };
        final reasons = <String>[];
        var fail = false;
        var review = false;
        String? duplicateOf;

        final gtin = fields['01'];
        if (gtin != null && !Gs1Fields.gtinIsValid(gtin)) {
          fail = true;
          reasons.add('GTIN $gtin has an invalid check digit');
        }

        final serial = fields['21'];
        if (serial != null) {
          final owner = _serialOwner['${gtin ?? ''}|$serial'];
          if (owner != null) {
            fail = true;
            duplicateOf = owner;
            reasons.add(
              'Duplicate serial $serial (first recorded in row $owner)',
            );
          }
        }

        final lot = fields['10'];
        if (lot != null && lot != _lastLot && _lotsSeen.contains(lot)) {
          review = true;
          reasons.add(
            'Batch / lot $lot was seen earlier; the line returned to a previous lot',
          );
        }

        final expiry = fields['17'];
        if (expiry != null) {
          final d = Gs1Fields.parseDate(expiry, now: now);
          if (d != null && d.isBefore(DateTime(now.year, now.month, now.day))) {
            review = true;
            reasons.add('Expired on ${Gs1Fields.formatDate(expiry, now: now)}');
          }
        }

        if (ocrText != null) {
          if (ocrText.trim().isEmpty) {
            review = true;
            reasons.add('OCR read no text');
          } else if (fields.isNotEmpty) {
            final missing = ocrMissing(fields, ocrText);
            if (missing.length == fields.length) {
              // Nothing matched: the label was probably not legible.
              review = true;
              reasons.add('Printed text could not be matched to the code');
            } else if (missing.isNotEmpty) {
              fail = true;
              reasons.add(
                'Printed text does not match the code: ${missing.join(', ')}',
              );
            }
          }
        }

        final row = InspectionRow(
          id: '${now.microsecondsSinceEpoch}-${_counter++}',
          createdAt: now,
          source: source,
          symbology: symbology,
          raw: raw,
          fields: fields,
          status: fail
              ? RowStatus.fail
              : (review ? RowStatus.review : RowStatus.pass),
          reasons: reasons,
          decodeMs: decodeMs,
          ocrText: ocrText,
          ocrMs: ocrMs,
          ocrNote: ocrNote,
          imagePath: imagePath,
          duplicateOf: duplicateOf,
        );
        _register(row);
        final file = await _file();
        await file.writeAsString(
          '${jsonEncode(row.toJson())}\n',
          mode: FileMode.append,
          flush: true,
        );
        return row;
      } catch (_) {
        return null;
      }
    });
  }
}

/// CSV with one line per row: the fields in their own columns.
String inspectionRowsToCsv(List<InspectionRow> rows) {
  String q(String? v) {
    final s = v ?? '';
    return s.contains(RegExp(r'[",\n\r]')) ? '"${s.replaceAll('"', '""')}"' : s;
  }

  final b = StringBuffer(
    'time,status,symbology,source,gtin,batch_lot,expiry,serial,raw,ocr_text,ocr_note,reasons,decode_ms,ocr_ms,image\n',
  );
  for (final r in rows) {
    b.writeln(
      [
        r.createdAt.toIso8601String(),
        r.status.name.toUpperCase(),
        r.symbology,
        r.source,
        r.gtin,
        r.lot,
        r.expiryDisplay,
        r.serial,
        r.raw,
        r.ocrText?.replaceAll('\n', ' | '),
        r.ocrNote,
        r.reasons.join('; '),
        r.decodeMs?.toStringAsFixed(1),
        r.ocrMs?.toStringAsFixed(1),
        r.imagePath,
      ].map(q).join(','),
    );
  }
  return b.toString();
}

final inspectionLogProvider = Provider<InspectionLog>(
  (ref) => InspectionLog(directory: ref.watch(dataDirectoryProvider)),
);
