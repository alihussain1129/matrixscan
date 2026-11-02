import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/brand.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'exalted_logo.dart';
import '../../features/devices/keyence/keyence_sr751_client.dart';
import '../../features/gallery/gallery_import_service.dart';
import '../../features/ocr/ocr_entry.dart';

/// Professional industrial desktop shell with sidebar navigation and a persistent
/// hardware/engine status bar.
class DesktopAppShell extends ConsumerWidget {
  const DesktopAppShell({
    super.key,
    required this.index,
    required this.onChanged,
    required this.children,
  });

  final int index;
  final ValueChanged<int> onChanged;
  final List<Widget> children;

  Future<void> _quickOcr(BuildContext context, WidgetRef ref) async {
    final picked = await GalleryImportService().pickImage();
    if (picked.path != null && context.mounted) {
      await openOcr(context, ref, picked.path!);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.extension<ExaltedColors>()!;
    final text = theme.textTheme;

    final keyenceClient = ref.watch(keyenceSr751ClientProvider);
    final isKeyenceConnected =
        keyenceClient.status == KeyenceConnectionStatus.connected;

    final platformName = Platform.isLinux
        ? 'Linux Desktop (x86_64)'
        : (Platform.isWindows ? 'Windows Desktop (x64)' : Platform.operatingSystem);

    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                // ---- Left-hand Navigation Sidebar --------------------------
                Container(
                  width: 250,
                  decoration: BoxDecoration(
                    color: colors.surfaceRaised,
                    border: Border(right: BorderSide(color: colors.outline)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.lg,
                          AppSpacing.xl,
                          AppSpacing.lg,
                          AppSpacing.md,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const ExaltedLogo(width: 130),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary.withAlpha(25),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: theme.colorScheme.primary.withAlpha(60),
                                ),
                              ),
                              child: Text(
                                'INDUSTRIAL PLATFORM',
                                style: text.labelSmall!.copyWith(
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      const SizedBox(height: AppSpacing.sm),

                      // Navigation items
                      _NavItem(
                        icon: Icons.dashboard_outlined,
                        activeIcon: Icons.dashboard,
                        label: 'Dashboard',
                        selected: index == 0,
                        onTap: () => onChanged(0),
                      ),
                      _NavItem(
                        icon: Icons.qr_code_scanner_outlined,
                        activeIcon: Icons.qr_code_scanner,
                        label: 'Decoder Workspace',
                        selected: index == 1,
                        onTap: () => onChanged(1),
                      ),
                      _NavItem(
                        icon: Icons.document_scanner_outlined,
                        activeIcon: Icons.document_scanner,
                        label: 'OCR Workspace',
                        selected: index == 2,
                        onTap: () => onChanged(2),
                      ),
                      _NavItem(
                        icon: Icons.router_outlined,
                        activeIcon: Icons.router,
                        label: 'Keyence SR-751',
                        selected: index == 3,
                        onTap: () => onChanged(3),
                      ),
                      _NavItem(
                        icon: Icons.history_outlined,
                        activeIcon: Icons.history,
                        label: 'History & Traceability',
                        selected: index == 4,
                        onTap: () => onChanged(4),
                      ),
                      _NavItem(
                        icon: Icons.tune_outlined,
                        activeIcon: Icons.tune,
                        label: 'System Settings',
                        selected: index == 5,
                        onTap: () => onChanged(5),
                      ),

                      const Spacer(),

                      // Quick Action Button
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.sm,
                        ),
                        child: OutlinedButton.icon(
                          onPressed: () => _quickOcr(context, ref),
                          icon: const Icon(Icons.file_open_outlined, size: 18),
                          label: const Text('Open Image File'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppRadius.button),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: AppSpacing.sm),
                    ],
                  ),
                ),

                // ---- Central Active Workspace ------------------------------
                Expanded(
                  child: IndexedStack(
                    index: index < children.length ? index : 0,
                    children: children,
                  ),
                ),
              ],
            ),
          ),

          // ---- Industrial Bottom Status Bar --------------------------------
          Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            decoration: BoxDecoration(
              color: colors.surfaceRaised,
              border: Border(top: BorderSide(color: colors.outline)),
            ),
            child: Row(
              children: [
                // Ready indicator
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Color(0xFF22C55E), // green
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'READY',
                  style: text.labelSmall!.copyWith(
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF22C55E),
                  ),
                ),
                const _StatusDivider(),
                const Icon(Icons.cloud_off_outlined, size: 14),
                const SizedBox(width: 4),
                Text('Offline Operation', style: text.labelSmall),
                const _StatusDivider(),
                const Icon(Icons.memory_outlined, size: 14),
                const SizedBox(width: 4),
                Text('Native C++20 Core (ZXing + DotPeen)', style: text.labelSmall),
                const _StatusDivider(),
                const Icon(Icons.text_fields_outlined, size: 14),
                const SizedBox(width: 4),
                Text('OCR: Offline Tesseract TSV', style: text.labelSmall),
                const _StatusDivider(),
                Icon(
                  Icons.router_outlined,
                  size: 14,
                  color: isKeyenceConnected ? const Color(0xFF22C55E) : colors.muted,
                ),
                const SizedBox(width: 4),
                Text(
                  isKeyenceConnected ? 'Keyence SR-751 Online' : 'Keyence Standby',
                  style: text.labelSmall!.copyWith(
                    color: isKeyenceConnected ? const Color(0xFF22C55E) : colors.muted,
                  ),
                ),
                const Spacer(),
                Text(platformName, style: text.labelSmall!.copyWith(color: colors.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusDivider extends StatelessWidget {
  const _StatusDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Container(
        width: 1,
        height: 14,
        color: Theme.of(context).extension<ExaltedColors>()!.outline,
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = theme.extension<ExaltedColors>()!;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
      child: Material(
        color: selected ? scheme.primary.withAlpha(30) : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.card),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Icon(
                  selected ? activeIcon : icon,
                  size: 20,
                  color: selected ? scheme.primary : colors.muted,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.bodyMedium!.copyWith(
                      fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                      color: selected ? scheme.primary : theme.textTheme.bodyMedium!.color,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
