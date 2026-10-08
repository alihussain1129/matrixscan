import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/exalted_button.dart';
import '../../core/widgets/exalted_card.dart';
import '../../core/widgets/exalted_logo.dart';
import '../../core/widgets/format_chip.dart';
import 'settings_controller.dart';

/// Temporary screen to preview the design system. Removed in Phase 3.
class DesignPreviewScreen extends ConsumerWidget {
  const DesignPreviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.extension<ExaltedColors>()!;
    final scheme = theme.colorScheme;
    final text = theme.textTheme;
    final isDark = theme.brightness == Brightness.dark;

    final swatches = <MapEntry<String, Color>>[
      MapEntry('Primary', scheme.primary),
      MapEntry('Pressed', colors.primaryPressed),
      MapEntry('Surface', scheme.surface),
      MapEntry('Outline', colors.outline),
      MapEntry('Muted', colors.muted),
      MapEntry('Valid', colors.valid),
    ];

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          children: [
            const Center(child: ExaltedLogo()),
            const SizedBox(height: AppSpacing.xl),
            Row(
              children: [
                Expanded(child: Text('Dark mode', style: text.titleMedium)),
                Switch(
                  value: isDark,
                  onChanged: (v) => ref
                      .read(themeModeProvider.notifier)
                      .set(v ? ThemeMode.dark : ThemeMode.light),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            Text('COLORS', style: text.labelSmall),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.md,
              children: [
                for (final s in swatches)
                  Column(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: s.value,
                          borderRadius: BorderRadius.circular(AppRadius.button),
                          border: Border.all(color: colors.outline),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(s.key, style: text.bodySmall),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            Text('TYPOGRAPHY', style: text.labelSmall),
            const SizedBox(height: AppSpacing.md),
            Text('Display 28', style: text.displaySmall),
            Text('Title 20', style: text.titleLarge),
            Text('Body 15 - clear and readable', style: text.bodyMedium),
            Text(
              'MONO 0123456789 ABCDEF',
              style: AppTypography.mono(size: 14, color: scheme.onSurface),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text('BUTTONS', style: text.labelSmall),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.md,
              children: [
                ExaltedButton(
                  label: 'Scan',
                  icon: Icons.qr_code_scanner,
                  onPressed: () {},
                ),
                ExaltedButton(
                  label: 'Gallery',
                  icon: Icons.photo_library_outlined,
                  outlined: true,
                  onPressed: () {},
                ),
                const ExaltedButton(label: 'Disabled', onPressed: null),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            Text('RESULT CARD', style: text.labelSmall),
            const SizedBox(height: AppSpacing.md),
            ExaltedCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.check_circle, color: colors.valid, size: 20),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        'DECODED',
                        style: text.labelLarge!.copyWith(color: colors.valid),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const FormatChip('Data Matrix - ECC 200'),
                  const SizedBox(height: AppSpacing.md),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: colors.surfaceRaised,
                      borderRadius: BorderRadius.circular(AppRadius.button),
                    ),
                    child: SelectableText(
                      '(01)09876543210123(17)280630(10)B6789',
                      style: AppTypography.mono(
                        size: 14,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text('ERROR STATE', style: text.labelSmall),
            const SizedBox(height: AppSpacing.md),
            ExaltedCard(
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: scheme.error),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      "Couldn't find a supported code.",
                      style: text.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),
          ],
        ),
      ),
    );
  }
}
