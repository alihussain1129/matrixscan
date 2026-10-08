import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/empty_state.dart';
import 'history_controller.dart';
import 'history_detail_screen.dart';
import 'history_entry.dart';
import 'history_export.dart';
import 'history_item_tile.dart';

/// History tab: saved scans, pinned first, then newest first.
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _export(List<HistoryEntry> shown) async {
    try {
      await ref.read(historyExporterProvider)(shown);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text("Couldn't export history")),
        );
    }
  }

  Widget _list(List<HistoryEntry> entries) {
    final shown = filterHistory(entries, _query);
    if (shown.isEmpty) {
      return Center(child: Text('No scans match "${_query.trim()}"'));
    }
    return ListView.separated(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      itemCount: shown.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final entry = shown[index];
        return HistoryItemTile(
          entry: entry,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => HistoryDetailScreen(entry: entry),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final history = ref.watch(historyControllerProvider);
    final all = history.value ?? const <HistoryEntry>[];
    final shown = filterHistory(all, _query);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(child: Text('History', style: text.displaySmall)),
                IconButton(
                  tooltip: 'Export CSV',
                  icon: const Icon(Icons.ios_share),
                  onPressed: shown.isEmpty ? null : () => _export(shown),
                ),
              ],
            ),
            if (all.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _search,
                textInputAction: TextInputAction.search,
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText: 'Search scans',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            _search.clear();
                            setState(() => _query = '');
                          },
                        ),
                ),
              ),
            ],
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
                  return _list(entries);
                },
                loading: () {
                  // Keep showing the previous list while a reload runs.
                  final previous = history.value;
                  if (previous == null) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return _list(previous);
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
