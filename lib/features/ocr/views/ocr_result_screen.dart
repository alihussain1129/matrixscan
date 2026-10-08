import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/exalted_button.dart';
import '../../../core/widgets/format_chip.dart';
import '../controllers/ocr_controller.dart';
import '../models/ocr_result.dart';
import '../services/ocr_repository.dart';
import '../widgets/ocr_tabs.dart';

/// Reads text from an image and lets the user edit, copy, share or save it.
class OcrResultScreen extends ConsumerStatefulWidget {
  const OcrResultScreen({super.key, required this.imagePath});

  final String imagePath;

  @override
  ConsumerState<OcrResultScreen> createState() => _OcrResultScreenState();
}

class _OcrResultScreenState extends ConsumerState<OcrResultScreen> {
  final TextEditingController _text = TextEditingController();
  String _original = '';
  OcrResult? _loadedFor;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(ocrControllerProvider.notifier).run(widget.imagePath);
      }
    });
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
      );
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _text.text));
    HapticFeedback.lightImpact();
    _snack('Text copied');
  }

  Future<void> _share() async {
    try {
      await SharePlus.instance.share(ShareParams(text: _text.text));
    } catch (_) {
      _snack("Couldn't open the share sheet.");
    }
  }

  Future<void> _save() async {
    try {
      await ref.read(ocrRepositoryProvider).save(_text.text);
      HapticFeedback.lightImpact();
      _snack('Saved on this device');
    } catch (_) {
      _snack("Couldn't save. Try again.");
    }
  }

  void _retry() {
    ref.read(ocrControllerProvider.notifier).run(widget.imagePath);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final ocr = ref.watch(ocrControllerProvider);

    ref.listen<OcrState>(ocrControllerProvider, (previous, next) {
      final result = next.result;
      if (next.status == OcrStatus.done &&
          result != null &&
          next.imagePath == widget.imagePath &&
          !identical(result, _loadedFor)) {
        _loadedFor = result;
        _original = result.fullText;
        _text.text = _original;
      }
    });

    final current = ocr.imagePath == widget.imagePath;
    final status = current ? ocr.status : OcrStatus.running;
    final result = current ? ocr.result : null;

    Widget body;
    if (status == OcrStatus.done && result != null) {
      body = _doneView(context, result);
    } else if (status == OcrStatus.failed && result?.error != null) {
      body = _failedView(result!.error!);
    } else {
      body = _RunningView(imagePath: widget.imagePath);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Read text', style: text.titleLarge),
        backgroundColor: theme.scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      body: SafeArea(child: body),
    );
  }

  Widget _failedView(OcrError error) {
    return Column(
      children: [
        Expanded(
          child: EmptyState(
            icon: error.type == OcrErrorType.noTextFound
                ? Icons.text_fields
                : Icons.error_outline,
            title: error.message,
            message: error.hint,
            actionLabel: 'Pick another image',
            onAction: () => Navigator.of(context).pop(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            0,
            AppSpacing.xl,
            AppSpacing.xl,
          ),
          child: ExaltedButton(
            label: 'Try again',
            outlined: true,
            expand: true,
            onPressed: _retry,
          ),
        ),
      ],
    );
  }

  Widget _doneView(BuildContext context, OcrResult result) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = theme.extension<ExaltedColors>()!;
    final text = theme.textTheme;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          child: Row(
            children: [
              Icon(Icons.check_circle, color: colors.valid, size: 20),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'TEXT EXTRACTED',
                style: text.labelLarge!.copyWith(color: colors.valid),
              ),
              const Spacer(),
              FormatChip(result.script.isEmpty ? 'Text' : result.script),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Expanded(
          child: DefaultTabController(
            length: 3,
            child: Column(
              children: [
                TabBar(
                  labelColor: colors.primaryText,
                  unselectedLabelColor: colors.muted,
                  indicatorColor: scheme.primary,
                  dividerColor: colors.outline,
                  labelStyle: text.labelLarge,
                  tabs: const [
                    Tab(text: 'TEXT'),
                    Tab(text: 'BLOCKS'),
                    Tab(text: 'ANALYSIS'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      OcrTextTab(
                        controller: _text,
                        original: _original,
                        imagePath: widget.imagePath,
                        result: result,
                      ),
                      OcrBlocksTab(result: result),
                      OcrAnalysisTab(result: result),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.md,
            AppSpacing.xl,
            AppSpacing.lg,
          ),
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
            border: Border(top: BorderSide(color: colors.outline)),
          ),
          child: ValueListenableBuilder<TextEditingValue>(
            valueListenable: _text,
            builder: (context, value, child) {
              final has = value.text.trim().isNotEmpty;
              return Row(
                children: [
                  Expanded(
                    child: ExaltedButton(
                      label: 'Copy',
                      expand: true,
                      onPressed: has ? _copy : null,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: ExaltedButton(
                      label: 'Share',
                      outlined: true,
                      expand: true,
                      onPressed: has ? _share : null,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: ExaltedButton(
                      label: 'Save',
                      outlined: true,
                      expand: true,
                      onPressed: has ? _save : null,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _RunningView extends StatelessWidget {
  const _RunningView({required this.imagePath});

  final String imagePath;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<ExaltedColors>()!;
    final text = theme.textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.card),
              child: Image.file(
                File(imagePath),
                width: 200,
                height: 200,
                fit: BoxFit.cover,
                cacheWidth: 600,
                errorBuilder: (context, error, stack) => Container(
                  width: 200,
                  height: 200,
                  color: colors.surfaceRaised,
                  child: Icon(Icons.image_outlined, color: colors.muted),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            SizedBox(
              width: 200,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                child: LinearProgressIndicator(
                  minHeight: 3,
                  color: theme.colorScheme.primary,
                  backgroundColor: colors.outline,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('Extracting text...', style: text.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Reading on this device. Nothing is uploaded.',
              textAlign: TextAlign.center,
              style: text.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
