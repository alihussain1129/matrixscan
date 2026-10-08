import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/router/app_router.dart';
import 'history_entry.dart';
import 'history_repository.dart';

/// Loads saved scans, newest first.
///
/// It watches the bottom-nav index, so the list is read again each time the
/// user switches tabs. That picks up scans made on the Scan tab.
class HistoryController extends AsyncNotifier<List<HistoryEntry>> {
  @override
  Future<List<HistoryEntry>> build() {
    ref.watch(navIndexProvider);
    return ref.read(historyRepositoryProvider).loadAll();
  }
}

final historyControllerProvider =
    AsyncNotifierProvider<HistoryController, List<HistoryEntry>>(
      HistoryController.new,
    );
