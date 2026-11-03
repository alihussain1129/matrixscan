import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/exalted_button.dart';
import '../../core/widgets/exalted_logo.dart';
import '../devices/keyence/keyence_sr751_client.dart';
import '../gallery/gallery_import_service.dart';
import '../history/history_entry.dart';
import '../history/history_repository.dart';
import '../ocr/ocr_entry.dart';

/// Industrial Dashboard: quick actions into Decoder, OCR Workspace, Keyence Machine Vision,
/// and recent traceability history.
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

  void _navigateTo(int tab) {
    ref.read(navIndexProvider.notifier).set(tab);
  }

  Future<void> _readText() async {
    final isDesktop = context.layout != ExaltedLayout.compact;

    if (isDesktop) {
      _navigateTo(kOcrTab); // Switch to the OCR workspace
      return;
    }

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

    final keyence = ref.watch(keyenceSr751ClientProvider);
    final isDesktop = context.layout != ExaltedLayout.compact;

    // Refresh recent list on tab switches
    ref.listen<int>(navIndexProvider, (previous, next) {
      if (next == kHomeTab && mounted) {
        setState(() {
          _recent = _load();
        });
      }
    });

    return Scaffold(
      body: SafeArea(
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: 1),
          duration: const Duration(milliseconds: 350),
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
              Row(
                children: [
                  const ExaltedLogo(width: 140),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: colors.valid.withAlpha(25),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: colors.valid),
                    ),
                    child: Text(
                      'OFFLINE SYSTEM READY',
                      style: text.labelSmall!.copyWith(
                        color: colors.valid,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              Text(
                isDesktop
                    ? 'Industrial Machine Vision & Inspection'
                    : 'Scan or read',
                style: text.headlineSmall,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'High-performance offline 2D code decoding, optical character verification (OCV), '
                'and Keyence SR-751 hardware control.',
                style: text.bodyMedium!.copyWith(color: colors.muted),
              ),
              const SizedBox(height: AppSpacing.xl),

              // Action Buttons Grid / Column
              Row(
                children: [
                  Expanded(
                    child: ExaltedButton(
                      label: 'Decoder Workspace',
                      icon: Icons.qr_code_scanner,
                      expand: true,
                      onPressed: () => _navigateTo(kScanTab),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: ExaltedButton(
                      label: 'OCR Workspace',
                      icon: Icons.document_scanner_outlined,
                      outlined: true,
                      expand: true,
                      onPressed: _readText,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),

              // Hardware Card for Keyence SR-751
              Card(
                color: colors.surfaceRaised,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: colors.outline),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color:
                              keyence.status ==
                                  KeyenceConnectionStatus.connected
                              ? colors.valid.withAlpha(30)
                              : Colors.grey.withAlpha(30),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.router_outlined,
                          color:
                              keyence.status ==
                                  KeyenceConnectionStatus.connected
                              ? colors.valid
                              : colors.muted,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'KEYENCE SR-751 Industrial Reader',
                              style: text.bodyLarge,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              keyence.status ==
                                      KeyenceConnectionStatus.connected
                                  ? 'Connected at ${keyence.host}:${keyence.port} (FTP receiver active)'
                                  : 'Disconnected · Standby for automated line triggers',
                              style: text.bodySmall!.copyWith(
                                color: colors.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: () => _navigateTo(kDevicesTab),
                        child: const Text('Open Hardware'),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: AppSpacing.xl),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Recent Inspections & Scans',
                      style: text.titleMedium,
                    ),
                  ),
                  TextButton(
                    onPressed: () => _navigateTo(kHistoryTab),
                    child: const Text('View all history'),
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
                          ].join(' · '),
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
  const _RecentTile({required this.entry, required this.subtitle});

  final HistoryEntry entry;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ExaltedColors>()!;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: colors.surfaceRaised,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: colors.outline),
        ),
        child: Row(
          children: [
            Icon(
              entry.kind == HistoryKind.ocr
                  ? Icons.text_snippet_outlined
                  : Icons.qr_code_2,
              color: colors.muted,
              size: 20,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodyMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: text.bodySmall!.copyWith(color: colors.muted),
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
