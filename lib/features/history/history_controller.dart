import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/link/link_providers.dart';
import 'history_entry.dart';
import 'history_repository.dart';

/// Pinned entries first, otherwise the repository order (newest first).
List<HistoryEntry> orderHistory(List<HistoryEntry> entries) => [
  ...entries.where((e) => e.pinned),
  ...entries.where((e) => !e.pinned),
];

/// Loads saved scans and applies pin and delete.
///
/// It watches the bottom-nav index and the sync journal change stream, so new
/// events arriving from linked devices appear live without a manual refresh.
class HistoryController extends AsyncNotifier<List<HistoryEntry>> {
  @override
  Future<List<HistoryEntry>> build() async {
    final entries = await ref.read(historyRepositoryProvider).loadAll();

    // Listen to sync journal changes so newly synced records refresh the UI.
    ref.listen(syncChangeStreamProvider, (previous, next) {
      ref.invalidateSelf();
    });

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
