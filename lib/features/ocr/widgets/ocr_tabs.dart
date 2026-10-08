import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/exalted_card.dart';
import '../models/ocr_result.dart';

/// Tab 1: image summary and the editable extracted text.
class OcrTextTab extends StatelessWidget {
  const OcrTextTab({
    super.key,
    required this.controller,
    required this.original,
    required this.imagePath,
    required this.result,
  });

  final TextEditingController controller;
  final String original;
  final String imagePath;
  final OcrResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<ExaltedColors>()!;
    final text = theme.textTheme;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.button),
              child: Image.file(
                File(imagePath),
                width: 64,
                height: 64,
                fit: BoxFit.cover,
                cacheWidth: 192,
                errorBuilder: (context, error, stack) => Container(
                  width: 64,
                  height: 64,
                  color: colors.surfaceRaised,
                  child: Icon(Icons.image_outlined, color: colors.muted),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${result.words.length} words, ${result.lines.length} lines',
                    style: text.titleMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Read in ${result.processingTime.inMilliseconds} ms '
                    'on this device',
                    style: text.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        ExaltedCard(
          child: TextField(
            controller: controller,
            maxLines: null,
            minLines: 8,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.none,
            style: text.bodyLarge!.copyWith(height: 1.4),
            decoration: const InputDecoration.collapsed(hintText: 'No text'),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, child) {
            final edited = value.text != original;
            return Row(
              children: [
                Expanded(
                  child: Text(
                    'OCR can make mistakes. Edit the text above before you '
                    'copy or save it.',
                    style: text.bodySmall,
                  ),
                ),
                if (edited)
                  TextButton(
                    onPressed: () => controller.text = original,
                    style: TextButton.styleFrom(
                      foregroundColor: colors.primaryText,
                    ),
                    child: const Text('Reset'),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

Future<void> _copyLine(BuildContext context, String line) async {
  await Clipboard.setData(ClipboardData(text: line));
  HapticFeedback.selectionClick();
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      const SnackBar(
        content: Text('Line copied'),
        duration: Duration(seconds: 2),
      ),
    );
}

/// Tab 2: detected text blocks and lines. Tap a line to copy it.
class OcrBlocksTab extends StatelessWidget {
  const OcrBlocksTab({super.key, required this.result});

  final OcrResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<ExaltedColors>()!;
    final text = theme.textTheme;

    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.xl),
      itemCount: result.blocks.length,
      separatorBuilder: (context, index) =>
          const SizedBox(height: AppSpacing.md),
      itemBuilder: (context, i) {
        final block = result.blocks[i];
        return ExaltedCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('BLOCK ${i + 1}', style: text.labelSmall),
              const SizedBox(height: AppSpacing.sm),
              for (final line in block.lines)
                Semantics(
                  button: true,
                  label: 'Copy line: ${line.text}',
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _copyLine(context, line.text),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 40),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(line.text, style: text.bodyMedium),
                          ),
                          if (line.confidence != null) ...[
                            const SizedBox(width: AppSpacing.sm),
                            Text(
                              '${(line.confidence! * 100).round()}%',
                              style: AppTypography.mono(
                                size: 12,
                                color: colors.muted,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Tab 3: facts reported by the engine. Anything unknown says "Not available".
class OcrAnalysisTab extends StatelessWidget {
  const OcrAnalysisTab({super.key, required this.result});

  final OcrResult result;

  static String _ms(Duration d) => '${d.inMilliseconds} ms';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<ExaltedColors>()!;

    final c = result.confidence;
    final rows = <MapEntry<String, String>>[
      MapEntry(
        'Engine',
        result.engine.isEmpty ? 'Not available' : result.engine,
      ),
      MapEntry(
        'Script',
        result.script.isEmpty ? 'Not available' : result.script,
      ),
      MapEntry(
        'Language',
        result.language.isEmpty ? 'Not available' : result.language,
      ),
      MapEntry(
        'Image size',
        result.imageWidth == null
            ? 'Not available'
            : '${result.imageWidth} x ${result.imageHeight}',
      ),
      MapEntry(
        'Analyzed at',
        result.analyzedWidth == null
            ? 'Not available'
            : (result.resized
                  ? '${result.analyzedWidth} x ${result.analyzedHeight} (resized)'
                  : 'Original size'),
      ),
      MapEntry('Preparation', _ms(result.prepTime)),
      MapEntry('Recognition', _ms(result.recognitionTime)),
      MapEntry('Total time', _ms(result.processingTime)),
      MapEntry('Blocks', '${result.blocks.length}'),
      MapEntry('Lines', '${result.lines.length}'),
      MapEntry('Words', '${result.words.length}'),
      MapEntry(
        'Confidence',
        c == null ? 'Not available' : '${(c * 100).round()}% (line average)',
      ),
    ];

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        ExaltedCard(
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0)
                  Divider(color: colors.outline, height: AppSpacing.xl),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        rows[i].key,
                        style: theme.textTheme.bodyLarge,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Flexible(
                      child: Text(
                        rows[i].value,
                        textAlign: TextAlign.right,
                        style: AppTypography.mono(
                          size: 13,
                          color: rows[i].value == 'Not available'
                              ? colors.muted
                              : theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
