import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/exalted_card.dart';
import '../scanner/scanner_controller.dart';
import 'settings_controller.dart';

/// Settings tab.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = theme.extension<ExaltedColors>()!;
    final text = theme.textTheme;

    final mode = ref.watch(themeModeProvider);
    final ui = ref.watch(scannerControllerProvider);
    final scanner = ref.read(scannerControllerProvider.notifier);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        children: [
          Text('Settings', style: text.displaySmall),
          const SizedBox(height: AppSpacing.xl),
          Text('SCANNING', style: text.labelSmall),
          const SizedBox(height: AppSpacing.md),
          ExaltedCard(
            child: Column(
              children: [
                _SwitchRow(
                  title: 'Auto scan',
                  subtitle: 'Detect and decode as soon as a code is in view',
                  value: ui.autoScan,
                  onChanged: (_) => scanner.toggleAuto(),
                ),
                Divider(color: colors.outline, height: AppSpacing.xl),
                _SwitchRow(
                  title: 'Continuous scanning',
                  subtitle: 'Keep scanning several codes without stopping',
                  value: ui.continuous,
                  onChanged: (_) => scanner.toggleContinuous(),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text('APPEARANCE', style: text.labelSmall),
          const SizedBox(height: AppSpacing.md),
          ExaltedCard(
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<ThemeMode>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: ThemeMode.system, label: Text('System')),
                  ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                  ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
                ],
                selected: {mode},
                onSelectionChanged: (s) =>
                    ref.read(themeModeProvider.notifier).set(s.first),
                style: SegmentedButton.styleFrom(
                  selectedBackgroundColor: scheme.primary,
                  selectedForegroundColor: scheme.onPrimary,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text('ABOUT', style: text.labelSmall),
          const SizedBox(height: AppSpacing.md),
          ExaltedCard(
            child: Column(
              children: [
                const _InfoRow(label: 'Version', value: '1.0.0'),
                Divider(color: colors.outline, height: AppSpacing.xl),
                const _InfoRow(label: 'Decoder', value: 'Not installed yet'),
                Divider(color: colors.outline, height: AppSpacing.xl),
                const _InfoRow(label: 'Privacy', value: 'Data stays on device'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: text.bodyLarge),
              const SizedBox(height: 2),
              Text(subtitle, style: text.bodySmall),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Expanded(child: Text(label, style: theme.textTheme.bodyLarge)),
        Text(
          value,
          style: AppTypography.mono(
            size: 13,
            color: theme.colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}