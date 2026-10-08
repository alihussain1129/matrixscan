import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/exalted_button.dart';

enum GalleryAction { scanCode, extractText }

/// Shows the picked image and asks what to do with it.
Future<GalleryAction?> showImageActionSheet(
  BuildContext context,
  String imagePath,
) {
  return showModalBottomSheet<GalleryAction>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetContext) => Theme(
      data: AppTheme.dark(),
      child: _ImageActionSheet(imagePath: imagePath),
    ),
  );
}

class _ImageActionSheet extends StatelessWidget {
  const _ImageActionSheet({required this.imagePath});

  final String imagePath;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<ExaltedColors>()!;
    final text = theme.textTheme;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadius.sheet),
        ),
        border: Border(top: BorderSide(color: colors.outline)),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.md,
        AppSpacing.xl,
        AppSpacing.xl,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colors.outline,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.card),
              child: Image.file(
                File(imagePath),
                height: 160,
                width: double.infinity,
                fit: BoxFit.cover,
                cacheWidth: 900,
                errorBuilder: (context, error, stack) => Container(
                  height: 160,
                  color: colors.surfaceRaised,
                  child: Icon(Icons.image_outlined, color: colors.muted),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('What do you want to do?', style: text.titleMedium),
            const SizedBox(height: AppSpacing.lg),
            ExaltedButton(
              label: 'Scan code',
              icon: Icons.qr_code_scanner,
              expand: true,
              onPressed: () =>
                  Navigator.of(context).pop(GalleryAction.scanCode),
            ),
            const SizedBox(height: AppSpacing.md),
            ExaltedButton(
              label: 'Extract text',
              icon: Icons.text_fields,
              outlined: true,
              expand: true,
              onPressed: () =>
                  Navigator.of(context).pop(GalleryAction.extractText),
            ),
          ],
        ),
      ),
    );
  }
}
