import 'ocr_history_detail_screen.dart';

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/empty_state.dart';
import '../ocr/models/ocr_record.dart';
import '../ocr/services/ocr_history_repository.dart';
import 'history_controller.dart';
import 'history_detail_screen.dart';
import 'history_entry.dart';
import 'history_export.dart';
import 'history_item_tile.dart';

/// History screen providing separate, dedicated tabs for Decoder History and OCR Records.
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _confirmClearDecoder() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete all history?'),
        content: const Text(
          'Every saved scan, including pinned ones, will be removed from '
          'this device. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete all'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(historyControllerProvider.notifier).clearAll();
    if (!mounted) return;
    _search.clear();
    setState(() => _query = '');
  }

  Future<void> _confirmClearOcr() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete all OCR history?'),
        content: const Text(
          'Every saved OCR document inspection, including preserved images, '
          'will be removed from this device. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete all'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(ocrHistoryRepositoryProvider).clearAll(deleteImages: true);
    if (!mounted) return;
    _search.clear();
    setState(() => _query = '');
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

  Widget _decoderList(List<HistoryEntry> entries) {
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

  Widget _ocrList(List<OcrRecord> records, OcrHistoryRepository repo) {
    final shown = repo.filter(records, _query);
    if (shown.isEmpty) {
      return Center(child: Text('No OCR records match "${_query.trim()}"'));
    }
    return ListView.separated(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      itemCount: shown.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = shown[index];
        final hasImage =
            item.imagePath.isNotEmpty && File(item.imagePath).existsSync();

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 0,
            vertical: AppSpacing.xs,
          ),
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => OcrHistoryDetailScreen(record: item),
              ),
            );
            if (mounted) setState(() {});
          },
          leading: hasImage
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    File(item.imagePath),
                    width: 44,
                    height: 44,
                    fit: BoxFit.cover,
                  ),
                )
              : Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.document_scanner_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
          title: Text(
            item.text.replaceAll('\n', ' '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              '${item.engine} • ${formatHistoryTime(item.createdAt, DateTime.now())}'
              '${item.ocvPassed != null ? (item.ocvPassed! ? ' • PASS' : ' • FAIL') : ''}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline, size: 20),
            onPressed: () async {
              await repo.deleteRecord(item.id);
              setState(() {});
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final theme = Theme.of(context);

    final history = ref.watch(historyControllerProvider);
    final allDecoder = history.value ?? const <HistoryEntry>[];
    final shownDecoder = filterHistory(allDecoder, _query);

    final ocrRepo = ref.watch(ocrHistoryRepositoryProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'History & Traceability',
                    style: text.displaySmall,
                  ),
                ),
                IconButton(
                  tooltip: 'Export CSV',
                  icon: const Icon(Icons.ios_share),
                  onPressed: shownDecoder.isEmpty
                      ? null
                      : () => _export(shownDecoder),
                ),
                IconButton(
                  tooltip: 'Delete all history',
                  icon: const Icon(Icons.delete_sweep_outlined),
                  onPressed: () {
                    if (_tabController.index == 0) {
                      if (allDecoder.isNotEmpty) _confirmClearDecoder();
                    } else {
                      _confirmClearOcr();
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),

            TabBar(
              controller: _tabController,
              labelColor: theme.colorScheme.primary,
              unselectedLabelColor: theme.textTheme.bodyMedium?.color
                  ?.withAlpha(160),
              indicatorColor: theme.colorScheme.primary,
              tabs: const [
                Tab(text: 'DECODER LOGS'),
                Tab(text: 'OCR DOCUMENTS'),
              ],
            ),

            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                hintText: 'Search history records...',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
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
            const SizedBox(height: AppSpacing.sm),

            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Tab 0: Decoder Records
                  history.when(
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
                              ref.read(navIndexProvider.notifier).set(kScanTab),
                        );
                      }
                      return _decoderList(entries);
                    },
                    loading: () {
                      final previous = history.value;
                      if (previous == null) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      return _decoderList(previous);
                    },
                    error: (error, stack) =>
                        const Center(child: Text('Could not load history.')),
                  ),

                  // Tab 1: OCR Records
                  FutureBuilder<List<OcrRecord>>(
                    future: ocrRepo.loadAll(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final ocrRecords = snapshot.data!;
                      if (ocrRecords.isEmpty) {
                        return const EmptyState(
                          icon: Icons.document_scanner_outlined,
                          title: 'No OCR records saved yet',
                          message:
                              'Extracted document text and inspection records '
                              'will appear here.',
                        );
                      }
                      return _ocrList(ocrRecords, ocrRepo);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
