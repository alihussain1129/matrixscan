import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Small pill showing a code format, for example "QR Code" or "Data Matrix".
class FormatChip extends StatelessWidget {
  const FormatChip(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<ExaltedColors>()!;
    final primary = theme.colorScheme.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.chip),
        border: Border.all(color: primary.withValues(alpha: 0.5)),
      ),
      child: Text(
        label.toUpperCase(),
        style: theme.textTheme.labelLarge!.copyWith(
          color: colors.primaryText,
          fontSize: 12,
        ),
      ),
    );
  }
}
