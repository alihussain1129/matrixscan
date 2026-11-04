import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_spacing.dart';
import '../ocr/models/ocr_record.dart';
import '../ocr/services/ocr_history_repository.dart';
import 'history_item_tile.dart';

/// One saved OCR record: image, full text, details, copy / delete.
class OcrHistoryDetailScreen extends ConsumerWidget {
  const OcrHistoryDetailScreen({super.key, required this.record});

  final OcrRecord record;

  Future<void> _copy(BuildContext context, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('Copied'), duration: Duration(seconds: 2)),
      );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this OCR record?'),
        content: const Text('It will be removed from History on this device.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(ocrHistoryRepositoryProvider).deleteRecord(record.id);
    if (!context.mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final hasImage =
        record.imagePath.isNotEmpty && File(record.imagePath).existsSync();
    final ms = record.processingDurationMs as num?;

    Widget row(String label, String value) => Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 80, child: Text(label, style: text.bodySmall)),
          Expanded(child: Text(value, style: text.bodyMedium)),
        ],
      ),
    );

    Widget textBox(String value) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: SelectableText(value, style: text.bodyLarge),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('OCR details')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          children: [
            if (hasImage) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.file(
                  File(record.imagePath),
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
            row('Type', 'OCR text'),
            row('Engine', record.engine),
            row('Language', record.language),
            row('Time', formatHistoryTime(record.createdAt, DateTime.now())),
            if (ms != null) row('Speed', '${ms.toStringAsFixed(0)} ms'),
            if (record.ocvPassed != null)
              row('OCV', record.ocvPassed! ? 'PASS' : 'FAIL'),
            const SizedBox(height: AppSpacing.md),
            textBox(record.text),
            if (record.rawText.trim().isNotEmpty &&
                record.rawText.trim() != record.text.trim()) ...[
              const SizedBox(height: AppSpacing.lg),
              Text('Raw OCR output', style: text.bodySmall),
              const SizedBox(height: AppSpacing.sm),
              textBox(record.rawText),
            ],
            const SizedBox(height: AppSpacing.xl),
            FilledButton.icon(
              onPressed: () => _copy(context, record.text),
              icon: const Icon(Icons.copy),
              label: const Text('Copy'),
            ),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              onPressed: () => _delete(context, ref),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete'),
            ),
          ],
        ),
      ),
    );
  }
}
