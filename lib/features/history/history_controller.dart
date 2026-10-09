import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/router/app_router.dart';
import 'history_entry.dart';
import 'history_repository.dart';

/// Pinned entries first, otherwise the repository order (newest first).
List<HistoryEntry> orderHistory(List<HistoryEntry> entries) => [
  ...entries.where((e) => e.pinned),
  ...entries.where((e) => !e.pinned),
];

/// Loads saved scans and applies pin and delete.
///
/// It watches the bottom-nav index, so the list is read again each time the
/// user switches tabs. That picks up scans made on the Scan tab.
class HistoryController extends AsyncNotifier<List<HistoryEntry>> {
  @override
  Future<List<HistoryEntry>> build() async {
    ref.watch(navIndexProvider);
    final entries = await ref.read(historyRepositoryProvider).loadAll();
    return orderHistory(entries);
  }

  Future<void> setPinned(String id, bool pinned) async {
    await ref.read(historyRepositoryProvider).setPinned(id, pinned);
    ref.invalidateSelf();
  }

  Future<void> clearAll() async {
    await ref.read(historyRepositoryProvider).clear();
    ref.invalidateSelf();
  }

  Future<void> delete(String id) async {
    await ref.read(historyRepositoryProvider).delete(id);
    ref.invalidateSelf();
  }
}

final historyControllerProvider =
    AsyncNotifierProvider<HistoryController, List<HistoryEntry>>(
      HistoryController.new,
    );
