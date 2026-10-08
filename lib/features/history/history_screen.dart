import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/empty_state.dart';
import 'history_controller.dart';
import 'history_item_tile.dart';

/// History tab: saved scans, newest first.
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final history = ref.watch(historyControllerProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: AppSpacing.lg),
            Text('History', style: text.displaySmall),
            Expanded(
              child: history.when(
                data: (entries) {
                  if (entries.isEmpty) {
                    return EmptyState(
                      icon: Icons.history,
                      title: 'No scans yet',
                      message:
                          'Codes you scan will appear here. '
                          'Everything stays on your device.',
                      actionLabel: 'Scan your first code',
                      onAction: () =>
                          ref.read(navIndexProvider.notifier).set(0),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.only(top: AppSpacing.md),
                    itemCount: entries.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                    itemBuilder: (context, index) =>
                        HistoryItemTile(entry: entries[index]),
                  );
                },
                loading: () {
                  // Keep showing the previous list while a reload runs.
                  final previous = history.value;
                  if (previous == null) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.only(top: AppSpacing.md),
                    itemCount: previous.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                    itemBuilder: (context, index) =>
                        HistoryItemTile(entry: previous[index]),
                  );
                },
                error: (error, stack) =>
                    const Center(child: Text('Could not load history.')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
