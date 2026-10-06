import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/empty_state.dart';

/// History tab. Real history (search, filters, items) arrives in Phase 9.
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: AppSpacing.lg),
            Text('History', style: text.displaySmall),
            Expanded(
              child: EmptyState(
                icon: Icons.history,
                title: 'No scans yet',
                message:
                    'Codes you scan will appear here. Everything stays on your device.',
                actionLabel: 'Scan your first code',
                onAction: () => ref.read(navIndexProvider.notifier).set(0),
              ),
            ),
          ],
        ),
      ),
    );
  }
}