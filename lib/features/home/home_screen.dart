import '../../design/exalted_shimmer.dart';
import '../../design/exalted_hero_card.dart';
import '../../design/exalted_stagger.dart';
import '../../design/exalted_press_scale.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/navigation/desktop_chrome.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/exalted_logo.dart';
import '../../core/widgets/metric_card.dart';
import '../../core/widgets/section_header.dart';
import '../../core/widgets/status_badge.dart';
import '../devices/keyence/keyence_scanner_coordinator.dart';
import '../gallery/gallery_import_service.dart';
import '../history/history_entry.dart';
import '../history/history_repository.dart';
import '../inspection/inspection_log.dart';
import '../inspection/inspection_row.dart';
import '../ocr/ocr_entry.dart';

class _DashboardData {
  const _DashboardData({
    required this.recent,
    required this.totalScans,
    required this.totalInspections,
  });

  final List<HistoryEntry> recent;
  final int totalScans;
  final int totalInspections;
}

/// Operational Industrial Dashboard: Real-time telemetry, active hardware status,
/// operational statistics, workspace access, and inspection audit trail.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late Future<_DashboardData> _dashboardFuture;
  bool _picking = false;
  bool _telemetryReady = false;

  @override
  void initState() {
    super.initState();
    _refreshData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _telemetryReady = true);
    });
  }

  void _refreshData() {
    _dashboardFuture = _loadDashboardData();
  }

  Future<_DashboardData> _loadDashboardData() async {
    final historyFuture = ref.read(historyRepositoryProvider).loadAll();
    final inspectionsFuture = ref
        .read(inspectionLogProvider)
        .loadAll()
        .catchError((Object _) => <InspectionRow>[]);
    final history = await historyFuture;
    final inspections = await inspectionsFuture;
    return _DashboardData(
      recent: history.take(8).toList(growable: false),
      totalScans: history.length,
      totalInspections: inspections.length,
    );
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
    final isDesktop = MediaQuery.sizeOf(context).width >= 720;
    if (isDesktop) {
      _navigateTo(kOcrTab);
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
    final colors = context.exalted;
    final text = theme.textTheme;
    final keyence = _telemetryReady
        ? ref.watch(keyenceScannerCoordinatorProvider)
        : const KeyenceCoordinatorState();
    final coordNotifier = _telemetryReady
        ? ref.read(keyenceScannerCoordinatorProvider.notifier)
        : null;
    final ocrAsync = _telemetryReady
        ? ref.watch(ocrAvailabilityProvider)
        : const AsyncLoading<OcrAvailability>();
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= 1024;
    final isTablet = width >= 640 && width < 1024;

    // Refresh when navigating back to Home
    ref.listen<int>(navIndexProvider, (prev, next) {
      if (next == kHomeTab && mounted) {
        setState(_refreshData);
      }
    });

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            setState(_refreshData);
            await _dashboardFuture;
          },
          child: ListView(
            padding: EdgeInsets.symmetric(
              horizontal: isDesktop ? AppSpacing.xxl : AppSpacing.lg,
              vertical: AppSpacing.lg,
            ),
            children: [
              // Top Brand and System Status Header
              _buildHeader(colors, text, keyence, _telemetryReady),
              const SizedBox(height: AppSpacing.xl),
              ExaltedStagger(
                index: 0,
                child: FutureBuilder<_DashboardData>(
                  future: _dashboardFuture,
                  builder: (context, snap) {
                    final d = snap.data;
                    return ExaltedHeroCard(
                      title: 'Total scans',
                      value: d?.totalScans ?? 0,
                      loading: d == null,
                      footnote: d == null
                          ? null
                          : '${d.totalInspections} inspections logged',
                      onTap: () => _navigateTo(kHistoryTab),
                    );
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.xl),

              // KPI Metric Cards (Real Database Data)
              ExaltedStagger(
                index: 1,
                child: _buildMetricCardsGrid(
                  keyence,
                  ocrAsync,
                  isDesktop,
                  isTablet,
                  _telemetryReady,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),

              // Main operational body: 2 columns on wide screens, 1 on mobile
              if (isDesktop)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Left Column: Active Hardware & Workspaces
                    Expanded(
                      flex: 6,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildHardwareCard(
                            keyence,
                            coordNotifier,
                            colors,
                            text,
                            _telemetryReady,
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          _buildWorkspacesSection(colors, text),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xl),
                    // Right Column: Recent Traceability Audit Feed
                    Expanded(
                      flex: 4,
                      child: _buildRecentActivityFeed(colors, text),
                    ),
                  ],
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHardwareCard(
                      keyence,
                      coordNotifier,
                      colors,
                      text,
                      _telemetryReady,
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    _buildWorkspacesSection(colors, text),
                    const SizedBox(height: AppSpacing.xl),
                    _buildRecentActivityFeed(colors, text),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(
    ExaltedColors colors,
    TextTheme text,
    KeyenceCoordinatorState keyence,
    bool telemetryReady,
  ) {
    return Row(
      children: [
        const ExaltedLogo(width: 140),
        const Spacer(),
        StatusBadge(
          label: 'LOCAL FIRST',
          sublabel: 'ONLINE LOOKUPS OPT-IN',
          variant: StatusBadgeVariant.neutral,
          icon: Icons.shield_outlined,
          compact: true,
        ),
        const SizedBox(width: AppSpacing.sm),
        StatusBadge(
          label: !telemetryReady
              ? 'CHECKING'
              : keyence.isConnected
              ? 'KEYENCE ${keyence.model}'
              : keyence.isDiscovering
              ? 'DISCOVERING SCANNER'
              : 'KEYENCE OFFLINE',
          variant: !telemetryReady
              ? StatusBadgeVariant.processing
              : keyence.isConnected
              ? StatusBadgeVariant.success
              : (keyence.isDiscovering
                    ? StatusBadgeVariant.processing
                    : StatusBadgeVariant.neutral),
          icon: Icons.router_outlined,
          compact: true,
        ),
      ],
    );
  }

  Widget _buildMetricCardsGrid(
    KeyenceCoordinatorState keyence,
    AsyncValue<OcrAvailability> ocrAsync,
    bool isDesktop,
    bool isTablet,
    bool telemetryReady,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = isDesktop ? 4 : (isTablet ? 2 : 1);
        final gap = AppSpacing.md;

        return Column(
          children: [
            FutureBuilder<_DashboardData>(
              future: _dashboardFuture,
              builder: (context, snap) {
                final totalScans = snap.data?.totalScans ?? 0;
                final totalInspections = snap.data?.totalInspections ?? 0;

                final ocrLabel = ocrAsync.maybeWhen(
                  data: (o) => o.ok ? 'Tesseract Ready' : 'Install Needed',
                  orElse: () => 'Detecting...',
                );

                final cards = [
                  MetricCard(
                    title: 'Total Scans',
                    value: '$totalScans',
                    subtitle: 'Local audit journal',
                    icon: Icons.qr_code_2_rounded,
                    iconColor: Theme.of(context).colorScheme.primary,
                    onTap: () => _navigateTo(kHistoryTab),
                  ),
                  MetricCard(
                    title: 'Inspection Records',
                    value: '$totalInspections',
                    subtitle: 'GS1 & OCV validation',
                    icon: Icons.fact_check_outlined,
                    iconColor: AppColors.aqua,
                    onTap: () => _navigateTo(kInspectionTab),
                  ),
                  MetricCard(
                    title: 'Industrial Scanner',
                    value: !telemetryReady
                        ? 'Checking…'
                        : keyence.isConnected
                        ? keyence.model
                        : 'Offline',
                    subtitle: !telemetryReady
                        ? 'Connection status'
                        : keyence.isConnected
                        ? '${keyence.host} (${keyence.totalConnectionTimeMs}ms)'
                        : 'Standby for ethernet',
                    icon: Icons.router_outlined,
                    iconColor: telemetryReady && keyence.isConnected
                        ? AppColors.successGreen
                        : AppColors.slate400,
                    onTap: () => _navigateTo(kDevicesTab),
                  ),
                  MetricCard(
                    title: 'OCR / OCV Engine',
                    value: ocrAsync.maybeWhen(
                      data: (o) => o.ok ? 'Active' : 'Standby',
                      orElse: () => 'Checking',
                    ),
                    subtitle: ocrLabel,
                    icon: Icons.text_snippet_outlined,
                    iconColor: AppColors.infoBlue,
                    onTap: () => _navigateTo(kOcrTab),
                  ),
                ];

                if (cols == 4) {
                  return Row(
                    children: [
                      for (var i = 0; i < cards.length; i++) ...[
                        if (i > 0) SizedBox(width: gap),
                        Expanded(child: cards[i]),
                      ],
                    ],
                  );
                } else if (cols == 2) {
                  return Column(
                    children: [
                      Row(
                        children: [
                          Expanded(child: cards[0]),
                          SizedBox(width: gap),
                          Expanded(child: cards[1]),
                        ],
                      ),
                      SizedBox(height: gap),
                      Row(
                        children: [
                          Expanded(child: cards[2]),
                          SizedBox(width: gap),
                          Expanded(child: cards[3]),
                        ],
                      ),
                    ],
                  );
                }

                return Column(
                  children: [
                    for (var i = 0; i < cards.length; i++) ...[
                      if (i > 0) SizedBox(height: gap),
                      cards[i],
                    ],
                  ],
                );
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildHardwareCard(
    KeyenceCoordinatorState keyence,
    KeyenceScannerCoordinator? coordNotifier,
    ExaltedColors colors,
    TextTheme text,
    bool telemetryReady,
  ) {
    final isConnected = keyence.isConnected;

    return Card(
      color: colors.surfaceRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(
          color: isConnected ? colors.valid.withAlpha(120) : colors.outline,
          width: isConnected ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isConnected
                        ? colors.valid.withAlpha(25)
                        : colors.muted.withAlpha(25),
                    borderRadius: BorderRadius.circular(AppRadius.button),
                  ),
                  child: Icon(
                    Icons.router_outlined,
                    size: 24,
                    color: isConnected ? colors.valid : colors.muted,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'KEYENCE ${keyence.model} Industrial 2D Reader',
                        style: text.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isConnected
                            ? 'Connected to ${keyence.host}:${keyence.port} · Verified in ${keyence.totalConnectionTimeMs}ms'
                            : !telemetryReady
                            ? 'Checking saved connection…'
                            : (keyence.isDiscovering
                                  ? 'Auto-discovering active scanners on network...'
                                  : 'Not connected · Plug ethernet to auto-discover or tap Connect'),
                        style: text.bodySmall?.copyWith(color: colors.muted),
                      ),
                    ],
                  ),
                ),
                StatusBadge(
                  label: isConnected
                      ? 'CONNECTED'
                      : !telemetryReady
                      ? 'CHECKING'
                      : (keyence.isDiscovering ? 'SCANNING' : 'OFFLINE'),
                  variant: isConnected
                      ? StatusBadgeVariant.success
                      : !telemetryReady
                      ? StatusBadgeVariant.processing
                      : (keyence.isDiscovering
                            ? StatusBadgeVariant.processing
                            : StatusBadgeVariant.neutral),
                  compact: true,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            const Divider(),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                if (isConnected) ...[
                  OutlinedButton.icon(
                    icon: const Icon(Icons.flash_on_outlined, size: 16),
                    label: const Text('Trigger Read'),
                    onPressed: coordNotifier == null
                        ? null
                        : () => coordNotifier.triggerRead(),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.volume_up_outlined, size: 16),
                    label: const Text('Beep'),
                    onPressed: coordNotifier == null
                        ? null
                        : () => coordNotifier.beep(),
                  ),
                ] else ...[
                  ElevatedButton.icon(
                    icon: const Icon(Icons.search_rounded, size: 16),
                    label: const Text('Auto-Discover'),
                    onPressed: coordNotifier == null || keyence.isDiscovering
                        ? null
                        : () => coordNotifier.discoverScanners(),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.bolt, size: 16),
                    label: const Text('Fast Connect'),
                    onPressed: coordNotifier == null
                        ? null
                        : () => coordNotifier.connect(),
                  ),
                ],
                const Spacer(),
                TextButton.icon(
                  icon: const Icon(Icons.settings_outlined, size: 16),
                  label: const Text('Device Manager'),
                  onPressed: () => _navigateTo(kDevicesTab),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkspacesSection(ExaltedColors colors, TextTheme text) {
    return ExaltedStagger(index: 2, child: _workspacesBody(colors, text));
  }

  Widget _workspacesBody(ExaltedColors colors, TextTheme text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(
          title: 'Primary Workspaces',
          subtitle: 'Launch high-speed scanning, text recognition, or hardware tuning',
        ),
        Row(
          children: [
            Expanded(
              child: _WorkspaceCard(
                title: 'Decoder Workspace',
                subtitle: 'High-speed 2D/1D code engine with live camera & GS1 breakdown',
                icon: Icons.qr_code_scanner_rounded,
                primary: true,
                onTap: () => _navigateTo(kScanTab),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _WorkspaceCard(
                title: 'OCR & OCV Workspace',
                subtitle: 'Optical character verification for expiration dates & lot stamps',
                icon: Icons.document_scanner_outlined,
                primary: false,
                onTap: _readText,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRecentActivityFeed(ExaltedColors colors, TextTheme text) {
    return ExaltedStagger(index: 3, child: _recentBody(colors, text));
  }

  Widget _recentBody(ExaltedColors colors, TextTheme text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Recent Activity',
          subtitle: 'Live decoded barcodes & inspections',
          trailing: TextButton(
            onPressed: () => _navigateTo(kHistoryTab),
            child: const Text('View All'),
          ),
        ),
        FutureBuilder<_DashboardData>(
          future: _dashboardFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return ExaltedShimmer(
                child: Column(
                  children: [
                    for (var i = 0; i < 4; i++)
                      const Padding(
                        padding: EdgeInsets.only(bottom: AppSpacing.sm),
                        child: ExaltedSkeletonBox(
                          height: 52,
                          radius: AppRadius.card,
                        ),
                      ),
                  ],
                ),
              );
            }

            final items = snapshot.data?.recent ?? const <HistoryEntry>[];
            if (items.isEmpty) {
              return EmptyState(
                icon: Icons.history_outlined,
                title: 'No Scans Recorded',
                message: 'Barcodes scanned via KEYENCE or camera will appear in this real-time audit feed.',
                actionLabel: 'Open Decoder',
                onAction: () => _navigateTo(kScanTab),
              );
            }

            return Column(
              children: [
                for (final e in items)
                  _RecentScanTile(
                    entry: e,
                    formattedTime: _when(e.createdAt),
                    onCopy: () {
                      Clipboard.setData(ClipboardData(text: e.text));
                      _snack('Copied barcode to clipboard');
                    },
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _WorkspaceCard extends StatefulWidget {
  const _WorkspaceCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.primary,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool primary;
  final VoidCallback onTap;

  @override
  State<_WorkspaceCard> createState() => _WorkspaceCardState();
}

class _WorkspaceCardState extends State<_WorkspaceCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.exalted;
    final theme = Theme.of(context);

    final borderColor = widget.primary
        ? (_hovered ? theme.colorScheme.primary : colors.teal.withAlpha(120))
        : (_hovered ? colors.outline.withAlpha(200) : colors.outline);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: ExaltedPressScale(
        onTap: widget.onTap,
        child: Card(
          color: widget.primary
              ? (theme.brightness == Brightness.dark
                    ? colors.surfaceRaised
                    : AppColors.neutralWhite)
              : colors.surfaceRaised,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.card),
            side: BorderSide(
              color: borderColor,
              width: widget.primary ? 1.5 : 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: widget.primary
                        ? theme.colorScheme.primary.withAlpha(30)
                        : colors.muted.withAlpha(25),
                    borderRadius: BorderRadius.circular(AppRadius.button),
                  ),
                  child: Icon(
                    widget.icon,
                    size: 22,
                    color: widget.primary
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  widget.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  widget.subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.muted,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecentScanTile extends StatelessWidget {
  const _RecentScanTile({
    required this.entry,
    required this.formattedTime,
    required this.onCopy,
  });

  final HistoryEntry entry;
  final String formattedTime;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final colors = context.exalted;
    final theme = Theme.of(context);
    final text = theme.textTheme;

    final isBarcode = entry.kind == HistoryKind.barcode;
    final formatLabel =
        entry.format ?? (isBarcode ? 'Data Matrix' : 'OCR Text');

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
            Container(
              padding: const EdgeInsets.all(AppSpacing.xs),
              decoration: BoxDecoration(
                color: colors.muted.withAlpha(25),
                borderRadius: BorderRadius.circular(AppRadius.chip),
              ),
              child: Icon(
                isBarcode ? Icons.qr_code_2 : Icons.text_snippet_outlined,
                color: isBarcode
                    ? theme.colorScheme.primary
                    : AppColors.infoBlue,
                size: 18,
              ),
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
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        formatLabel,
                        style: text.labelSmall?.copyWith(
                          color: colors.muted,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        '· $formattedTime',
                        style: text.bodySmall?.copyWith(
                          color: colors.muted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Copy data',
              icon: const Icon(Icons.copy_rounded, size: 16),
              onPressed: onCopy,
            ),
          ],
        ),
      ),
    );
  }
}
