import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/exalted_button.dart';
import '../../core/widgets/exalted_logo.dart';
import '../gallery/gallery_import_service.dart';
import '../history/history_entry.dart';
import '../history/history_repository.dart';
import '../ocr/ocr_entry.dart';

/// Home: scan a code, read text (OCR) on its own, and see recent scans.
/// Recent scans come from the real history; nothing here is made up.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late Future<List<HistoryEntry>> _recent;
  bool _picking = false;

  @override
  void initState() {
    super.initState();
    _recent = _load();
  }

  Future<List<HistoryEntry>> _load() async {
    final all = await ref.read(historyRepositoryProvider).loadAll();
    return all.take(5).toList();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
      );
  }

  /// OCR on its own: pick an image, then open the existing OCR screen.
  /// The barcode camera is not involved.
  Future<void> _readText() async {
    if (_picking) return;
    _picking = true;
    try {
      HapticFeedback.selectionClick();
      final picked = await GalleryImportService().pickImage();
      if (!mounted) return;
      if (picked.error != null) {
        _snack(picked.error!);
        return;
      }
      final path = picked.path;
      if (path == null) return;
      await openOcr(context, ref, path);
    } finally {
      _picking = false;
    }
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  static String _when(DateTime t) {
    final now = DateTime.now();
    final time = '${_two(t.hour)}:${_two(t.minute)}';
    final sameDay =
        t.year == now.year && t.month == now.month && t.day == now.day;
    return sameDay ? 'Today $time' : '${_two(t.day)}/${_two(t.month)} $time';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<ExaltedColors>()!;
    final text = theme.textTheme;

    // Refresh the recent list each time the user comes back to Home.
    ref.listen<int>(navIndexProvider, (previous, next) {
      if (next == kHomeTab && mounted) {
        setState(() => _recent = _load());
      }
    });

    return Scaffold(
      body: SafeArea(
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: 1),
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
          builder: (context, t, child) => Opacity(
            opacity: t,
            child: Transform.translate(
              offset: Offset(0, (1 - t) * 14),
              child: child,
            ),
          ),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.lg,
              AppSpacing.xl,
              AppSpacing.xl,
            ),
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: ExaltedLogo(width: 140),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text('Scan or read', style: text.headlineSmall),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Everything runs on this device. Nothing is uploaded.',
                style: text.bodyMedium!.copyWith(color: colors.muted),
              ),
              const SizedBox(height: AppSpacing.xl),
              ExaltedButton(
                label: 'Scan barcode / QR',
                icon: Icons.qr_code_scanner,
                expand: true,
                onPressed: () =>
                    ref.read(navIndexProvider.notifier).set(kScanTab),
              ),
              const SizedBox(height: AppSpacing.md),
              ExaltedButton(
                label: 'Text scanner (OCR)',
                icon: Icons.text_fields,
                outlined: true,
                expand: true,
                onPressed: _readText,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Pick a photo and read the text in it. This does not open the '
                'barcode camera.',
                style: text.bodySmall!.copyWith(color: colors.muted),
              ),
              const SizedBox(height: AppSpacing.xl),
              Row(
                children: [
                  Expanded(
                    child: Text('Recent scans', style: text.titleMedium),
                  ),
                  TextButton(
                    onPressed: () =>
                        ref.read(navIndexProvider.notifier).set(kHistoryTab),
                    child: const Text('View all'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              FutureBuilder<List<HistoryEntry>>(
                future: _recent,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.all(AppSpacing.lg),
                      child: Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    );
                  }
                  final items = snapshot.data ?? const <HistoryEntry>[];
                  if (items.isEmpty) {
                    return Container(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      decoration: BoxDecoration(
                        color: colors.surfaceRaised,
                        borderRadius: BorderRadius.circular(AppRadius.card),
                        border: Border.all(color: colors.outline),
                      ),
                      child: Text(
                        'No scans yet. Scan a code and it will appear here.',
                        style: text.bodyMedium!.copyWith(color: colors.muted),
                      ),
                    );
                  }
                  return Column(
                    children: [
                      for (final e in items)
                        _RecentTile(
                          entry: e,
                          subtitle: [
                            e.format ?? e.kind.name,
                            _when(e.createdAt),
                          ].join('  ·  '),
                          onTap: () => ref
                              .read(navIndexProvider.notifier)
                              .set(kHistoryTab),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentTile extends StatelessWidget {
  const _RecentTile({
    required this.entry,
    required this.subtitle,
    required this.onTap,
  });

  final HistoryEntry entry;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<ExaltedColors>()!;
    final text = theme.textTheme;
    final preview = entry.text.replaceAll(RegExp(r'\s+'), ' ').trim();

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Material(
        color: colors.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.card),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: colors.outline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyLarge,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall!.copyWith(color: colors.muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
