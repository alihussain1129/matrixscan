import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'history_entry.dart';
import 'history_item_tile.dart';

/// Entries whose value, type or source contains [query] (case-insensitive).
/// An empty query returns everything.
List<HistoryEntry> filterHistory(List<HistoryEntry> entries, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return entries;
  return [
    for (final e in entries)
      if ('${e.text} ${historyTypeLabel(e)} ${historySourceLabel(e.source)}'
          .toLowerCase()
          .contains(q))
        e,
  ];
}

String _cell(String value) {
  var s = value;
  // Scanned text is untrusted: stop spreadsheets from running it as a formula.
  if (s.isNotEmpty && '=+-@\t\r'.contains(s[0])) s = "'$s";
  if (s.contains(RegExp(r'[",\r\n]'))) {
    s = '"${s.replaceAll('"', '""')}"';
  }
  return s;
}

/// CSV text for [entries]: time, type, source, value, pinned.
String historyToCsv(List<HistoryEntry> entries) {
  final lines = <String>['time,type,source,value,pinned'];
  for (final e in entries) {
    lines.add(
      [
        e.createdAt.toIso8601String(),
        historyTypeLabel(e),
        historySourceLabel(e.source),
        e.text,
        e.pinned.toString(),
      ].map(_cell).join(','),
    );
  }
  return '${lines.join('\r\n')}\r\n';
}

/// Writes [entries] to a CSV file and opens the system share sheet.
Future<void> shareHistoryCsv(List<HistoryEntry> entries) async {
  final dir = await getTemporaryDirectory();
  final now = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  final name =
      'exalted_history_${now.year}${two(now.month)}${two(now.day)}'
      '_${two(now.hour)}${two(now.minute)}${two(now.second)}.csv';
  final file = File('${dir.path}${Platform.pathSeparator}$name');
  // The BOM lets Excel read non-English text correctly.
  await file.writeAsString('\uFEFF${historyToCsv(entries)}', flush: true);
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, mimeType: 'text/csv')],
      subject: 'Exalted scan history',
    ),
  );
}

/// The export action. Tests replace it.
final historyExporterProvider =
    Provider<Future<void> Function(List<HistoryEntry>)>((ref) {
      return shareHistoryCsv;
    });
