import 'dart:io';

import 'package:exalted/features/history/history_entry.dart';
import 'package:exalted/features/history/history_repository.dart';
import 'package:exalted/features/scanner/detection_events.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DetectionEventTracker', () {
    test('frames of one visible code are a single event', () {
      final t = DetectionEventTracker();
      expect(t.observe('A', 0, 1000), isTrue);
      for (var ms = 90; ms < 5000; ms += 90) {
        expect(t.observe('A', ms, 1000), isFalse);
      }
    });

    test('a different code starts its own event with no gap', () {
      final t = DetectionEventTracker();
      expect(t.observe('A', 0, 1000), isTrue);
      expect(t.observe('B', 100, 1000), isTrue);
    });

    test('two codes in view together do not restart each other', () {
      final t = DetectionEventTracker();
      var events = 0;
      for (var ms = 0; ms < 3000; ms += 100) {
        if (t.observe(ms.isEven ? 'A' : 'B', ms, 1000)) events++;
        if (t.observe(ms.isEven ? 'B' : 'A', ms + 50, 1000)) events++;
      }
      expect(events, 2);
    });

    test('the same payload is a new event after the code left view', () {
      final t = DetectionEventTracker();
      expect(t.observe('A', 0, 1000), isTrue);
      expect(t.observe('A', 500, 1000), isFalse);
      expect(t.observe('A', 1700, 1000), isTrue);
    });

    test('reset makes the next decode a new event', () {
      final t = DetectionEventTracker();
      t.observe('A', 0, 1000);
      t.reset();
      expect(t.observe('A', 50, 1000), isTrue);
    });
  });

  test('allowRepeat stores the same text twice, default does not', () async {
    final dir = await Directory.systemTemp.createTemp('exalted_hist_');
    final repo = HistoryRepository(directory: () async => dir);
    final a = await repo.add(
      kind: HistoryKind.barcode,
      source: HistorySource.live,
      text: 'X',
    );
    final b = await repo.add(
      kind: HistoryKind.barcode,
      source: HistorySource.live,
      text: 'X',
    );
    expect(b?.id, a?.id);
    final c = await repo.add(
      kind: HistoryKind.barcode,
      source: HistorySource.live,
      text: 'X',
      allowRepeat: true,
    );
    expect(c?.id, isNot(a?.id));
    expect((await repo.loadAll()).length, 2);
    await dir.delete(recursive: true);
  });
}
