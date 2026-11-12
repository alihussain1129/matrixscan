import 'dart:convert';
import 'dart:io';

import 'package:exalted/features/history/history_entry.dart';
import 'package:exalted/features/history/history_repository.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('5,000-record history load benchmark', () async {
    final directory = await Directory.systemTemp.createTemp(
      'exalted_history_benchmark',
    );
    try {
      final now = DateTime.utc(2026, 11, 11);
      final encoded = jsonEncode([
        for (var i = 0; i < 5000; i++)
          HistoryEntry(
            id: 'benchmark-$i',
            kind: HistoryKind.barcode,
            source: HistorySource.live,
            text: 'EXALTED-DM-${i.toString().padLeft(8, '0')}',
            createdAt: now.subtract(Duration(seconds: i)),
            format: 'Data Matrix',
          ).toJson(),
      ]);
      await File('${directory.path}${Platform.pathSeparator}history.json')
          .writeAsString(encoded, flush: true);

      final repository = HistoryRepository(directory: () async => directory);
      final samples = <int>[];
      for (var run = 0; run < 5; run++) {
        final stopwatch = Stopwatch()..start();
        final records = await repository.loadAll();
        samples.add(stopwatch.elapsedMilliseconds);
        expect(records, hasLength(5000));
      }

      final ordered = [...samples]..sort();
      debugPrint(
        '[EXALTED][BENCHMARK] history_load_5000_ms '
        'runs=$samples median=${ordered[2]} p95=${ordered.last}',
      );
    } finally {
      await directory.delete(recursive: true);
    }
  });
}
