import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// A text the user saved after OCR.
class SavedOcrText {
  const SavedOcrText({
    required this.id,
    required this.createdAt,
    required this.text,
  });

  final String id;
  final DateTime createdAt;
  final String text;

  Map<String, Object?> toJson() => {
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'text': text,
  };

  static SavedOcrText? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final created = json['createdAt'];
    final text = json['text'];
    if (id is! String || created is! String || text is! String) return null;
    final date = DateTime.tryParse(created);
    if (date == null) return null;
    return SavedOcrText(id: id, createdAt: date, text: text);
  }
}

/// Saves OCR text in the app's private storage. It never leaves the device.
/// These items will show up in History in a later phase.
class OcrRepository {
  OcrRepository({Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationDocumentsDirectory;

  final Future<Directory> Function() _directory;

  Future<File> _file() async {
    final dir = await _directory();
    return File('${dir.path}${Platform.pathSeparator}ocr_saved.json');
  }

  Future<List<SavedOcrText>> loadAll() async {
    final file = await _file();
    if (!await file.exists()) return <SavedOcrText>[];
    try {
      final raw = jsonDecode(await file.readAsString());
      if (raw is! List) return <SavedOcrText>[];
      return [for (final item in raw) ?SavedOcrText.fromJson(item)];
    } catch (_) {
      return <SavedOcrText>[];
    }
  }

  Future<SavedOcrText> save(String text) async {
    final items = await loadAll();
    final now = DateTime.now();
    final item = SavedOcrText(
      id: now.microsecondsSinceEpoch.toString(),
      createdAt: now,
      text: text,
    );
    items.add(item);
    final file = await _file();
    await file.writeAsString(
      jsonEncode([for (final i in items) i.toJson()]),
      flush: true,
    );
    return item;
  }
}

final ocrRepositoryProvider = Provider<OcrRepository>((ref) {
  return OcrRepository();
});
