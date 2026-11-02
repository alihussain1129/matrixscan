import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/storage/image_storage_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/exalted_button.dart';
import '../../../core/widgets/format_chip.dart';
import '../../gallery/gallery_import_service.dart';
import '../controllers/ocr_controller.dart';
import '../models/ocr_record.dart';
import '../models/ocr_result.dart';
import '../services/desktop_ocr_engine.dart';
import '../services/ocr_engine.dart';
import '../services/ocr_history_repository.dart';

/// Full-featured industrial OCR and OCV Workspace supporting image acquisition,
/// region-of-interest selection, offline recognition, verification, and permanent storage.
class OcrWorkspaceScreen extends ConsumerStatefulWidget {
  const OcrWorkspaceScreen({super.key, this.initialImagePath});

  final String? initialImagePath;

  @override
  ConsumerState<OcrWorkspaceScreen> createState() =>
      _OcrWorkspaceScreenState();
}

class _OcrWorkspaceScreenState extends ConsumerState<OcrWorkspaceScreen> {
  String? _currentImagePath;
  final TextEditingController _textController = TextEditingController();
  final TextEditingController _ocvPatternController =
      TextEditingController(text: r'LOT-[A-Z0-9]+');

  bool _isProcessing = false;
  OcrResult? _lastResult;
  int _processingTimeMs = 0;
  bool? _ocvPassed;
  String _selectedLanguage = 'eng';

  // Region of Interest (ROI) normalized coords (0..1)
  Rect? _roiRect;
  bool _roiMode = false;
  Offset? _roiStart;
  Offset? _roiEnd;

  @override
  void initState() {
    super.initState();
    if (widget.initialImagePath != null) {
      _currentImagePath = widget.initialImagePath;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _runOcr();
      });
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _ocvPatternController.dispose();
    super.dispose();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 2)));
  }

  Future<void> _pickImage() async {
    final picked = await GalleryImportService().pickImage();
    if (picked.path != null && mounted) {
      setState(() {
        _currentImagePath = picked.path;
        _lastResult = null;
        _textController.clear();
        _ocvPassed = null;
        _roiRect = null;
      });
      await _runOcr();
    }
  }

  Future<void> _runOcr() async {
    if (_currentImagePath == null) return;

    setState(() {
      _isProcessing = true;
      _ocvPassed = null;
    });

    final stopwatch = Stopwatch()..start();
    try {
      final engine = ref.read(ocrEngineProvider);
      final result = await engine.recognizeFile(_currentImagePath!);

      if (mounted) {
        setState(() {
          _isProcessing = false;
          _processingTimeMs = stopwatch.elapsedMilliseconds;
          _lastResult = result;
          if (result.error == null) {
            _textController.text = result.fullText;
            _verifyOcv();
          } else {
            _textController.text = '';
            _snack(result.error!.message);
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        _snack('OCR processing failed: $e');
      }
    }
  }

  void _verifyOcv() {
    final pattern = _ocvPatternController.text.trim();
    if (pattern.isEmpty || _textController.text.isEmpty) {
      setState(() => _ocvPassed = null);
      return;
    }

    try {
      final regex = RegExp(pattern, caseSensitive: false);
      setState(() {
        _ocvPassed = regex.hasMatch(_textController.text);
      });
    } catch (_) {
      setState(() => _ocvPassed = false);
    }
  }

  Future<void> _saveRecord() async {
    if (_currentImagePath == null || _textController.text.isEmpty) return;

    try {
      // 1. Permanently copy source image into media repository
      final storage = ref.read(imageStorageServiceProvider);
      final permanentPath = await storage.persistSourceImage(
        _currentImagePath!,
        prefix: 'ocr_record',
      );

      // 2. Save full metadata into dedicated OCR repository
      final ocrRepo = ref.read(ocrHistoryRepositoryProvider);
      final record = OcrRecord(
        id: 'ocr_${DateTime.now().microsecondsSinceEpoch}',
        imagePath: permanentPath,
        text: _textController.text,
        rawText: _lastResult?.fullText ?? _textController.text,
        createdAt: DateTime.now(),
        language: _selectedLanguage,
        engine: Platform.isAndroid ? 'Google ML Kit' : 'Tesseract 5.3',
        confidence: _lastResult?.confidence ?? 0.0,
        processingDurationMs: _processingTimeMs,
        blockCount: _lastResult?.blocks.length ?? 0,
        ocvPattern: _ocvPatternController.text.trim().isNotEmpty
            ? _ocvPatternController.text.trim()
            : null,
        ocvPassed: _ocvPassed,
      );

      await ocrRepo.addRecord(record);
      _snack('Saved to OCR History with preserved image');
    } catch (e) {
      _snack('Could not save record: $e');
    }
  }

  Future<void> _copyText() async {
    await Clipboard.setData(ClipboardData(text: _textController.text));
    HapticFeedback.lightImpact();
    _snack('Copied to clipboard');
  }

  Future<void> _shareText() async {
    try {
      await SharePlus.instance.share(ShareParams(text: _textController.text));
    } catch (_) {
      _snack("Couldn't open share sheet");
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<ExaltedColors>()!;
    final text = theme.textTheme;

    final isWide = MediaQuery.sizeOf(context).width >= 720;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.document_scanner, size: 22),
            const SizedBox(width: 8),
            Text('OCR & OCV Workspace', style: text.titleMedium),
            const SizedBox(width: 12),
            FormatChip(Platform.isAndroid ? 'ML Kit OCR' : 'Tesseract TSV Engine'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Open Image',
            icon: const Icon(Icons.file_open_outlined),
            onPressed: _pickImage,
          ),
          IconButton(
            tooltip: 'View OCR History',
            icon: const Icon(Icons.history_edu_outlined),
            onPressed: () => _openOcrHistorySheet(context),
          ),
        ],
      ),
      body: _currentImagePath == null
          ? Center(
              child: EmptyState(
                icon: Icons.document_scanner_outlined,
                title: 'OCR Document & Image Workspace',
                message:
                    'Import an image, technical drawing, or industrial label '
                    'to perform genuine offline text recognition and verification.',
                actionLabel: 'Select Image File',
                onAction: _pickImage,
              ),
            )
          : (isWide
              ? Row(
                  children: [
                    // Left Pane: Image & ROI viewer
                    Expanded(flex: 5, child: _buildImagePane(colors, text)),
                    VerticalDivider(width: 1, color: colors.outline),
                    // Right Pane: Extracted text, OCV & Actions
                    Expanded(flex: 5, child: _buildTextPane(theme, colors, text)),
                  ],
                )
              : SingleChildScrollView(
                  child: Column(
                    children: [
                      SizedBox(
                        height: 300,
                        child: _buildImagePane(colors, text),
                      ),
                      const Divider(height: 1),
                      _buildTextPane(theme, colors, text),
                    ],
                  ),
                )),
    );
  }

  Widget _buildImagePane(ExaltedColors colors, TextTheme text) {
    return Container(
      color: colors.surfaceRaised,
      child: Column(
        children: [
          // Toolbar above image
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 8),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: colors.outline)),
            ),
            child: Row(
              children: [
                Text('SOURCE IMAGE', style: text.labelSmall!.copyWith(color: colors.muted)),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: _pickImage,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Change Image'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Clear',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => setState(() {
                    _currentImagePath = null;
                    _lastResult = null;
                    _textController.clear();
                  }),
                ),
              ],
            ),
          ),
          // Main image view
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                InteractiveViewer(
                  maxScale: 5.0,
                  child: Center(
                    child: Image.file(
                      File(_currentImagePath!),
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                if (_isProcessing)
                  Container(
                    color: Colors.black45,
                    child: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 12),
                          Text(
                            'Extracting text offline...',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextPane(ThemeData theme, ExaltedColors colors, TextTheme text) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Metrics Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: (_lastResult?.confidence ?? 0) >= 0.7
                      ? const Color(0xFF22C55E).withAlpha(30)
                      : Colors.orange.withAlpha(30),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'CONFIDENCE: ${((_lastResult?.confidence ?? 0) * 100).toStringAsFixed(1)}%',
                  style: text.labelSmall!.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 8),
              if (_processingTimeMs > 0)
                Text(
                  'Time: ${_processingTimeMs}ms',
                  style: text.bodySmall!.copyWith(color: colors.muted),
                ),
              const Spacer(),
              ElevatedButton.icon(
                icon: const Icon(Icons.play_arrow, size: 16),
                label: const Text('Re-run OCR'),
                onPressed: _isProcessing ? null : _runOcr,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          // Extracted Text Field
          Text('EXTRACTED TEXT (EDITABLE)', style: text.labelSmall!.copyWith(color: colors.muted)),
          const SizedBox(height: 4),
          Expanded(
            child: TextField(
              controller: _textController,
              maxLines: null,
              expands: true,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Recognized text will appear here...',
                filled: true,
                fillColor: colors.surfaceRaised,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: colors.outline),
                ),
              ),
              onChanged: (_) => _verifyOcv(),
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // OCV Verification Panel
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: colors.surfaceRaised,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: _ocvPassed == true
                    ? const Color(0xFF22C55E)
                    : (_ocvPassed == false ? Colors.red : colors.outline),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.verified_outlined, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      'OPTICAL CHARACTER VERIFICATION (OCV)',
                      style: text.labelSmall!.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    if (_ocvPassed != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: _ocvPassed! ? const Color(0xFF22C55E) : Colors.red,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _ocvPassed! ? 'PASS' : 'FAIL',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _ocvPatternController,
                        decoration: const InputDecoration(
                          labelText: 'Expected Pattern / Regex',
                          hintText: 'e.g. LOT-[0-9]{6}',
                          isDense: true,
                        ),
                        onChanged: (_) => _verifyOcv(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: _verifyOcv,
                      child: const Text('Verify'),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.md),

          // Action Buttons: Copy, Share, Save to History
          Row(
            children: [
              Expanded(
                child: ExaltedButton(
                  label: 'Copy Text',
                  expand: true,
                  onPressed: _textController.text.isNotEmpty ? _copyText : null,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: ExaltedButton(
                  label: 'Share',
                  outlined: true,
                  expand: true,
                  onPressed: _textController.text.isNotEmpty ? _shareText : null,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: ExaltedButton(
                  label: 'Save Record',
                  outlined: true,
                  expand: true,
                  onPressed: _textController.text.isNotEmpty ? _saveRecord : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _openOcrHistorySheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => _OcrHistoryModal(
        onSelectRecord: (record) {
          Navigator.of(ctx).pop();
          setState(() {
            _currentImagePath = record.imagePath;
            _textController.text = record.text;
            _ocvPatternController.text = record.ocvPattern ?? '';
            _ocvPassed = record.ocvPassed;
            _processingTimeMs = record.processingDurationMs;
          });
        },
      ),
    );
  }
}

class _OcrHistoryModal extends ConsumerStatefulWidget {
  const _OcrHistoryModal({required this.onSelectRecord});

  final ValueChanged<OcrRecord> onSelectRecord;

  @override
  ConsumerState<_OcrHistoryModal> createState() => _OcrHistoryModalState();
}

class _OcrHistoryModalState extends ConsumerState<_OcrHistoryModal> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final repo = ref.watch(ocrHistoryRepositoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('OCR & OCV Record History'),
        actions: [
          IconButton(
            tooltip: 'Clear All OCR Records',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: () async {
              await repo.clearAll();
              if (mounted) setState(() {});
            },
          ),
        ],
      ),
      body: FutureBuilder<List<OcrRecord>>(
        future: repo.loadAll(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final all = snapshot.data!;
          final filtered = repo.filter(all, _searchQuery);

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search OCR text or patterns...',
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v),
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? const Center(child: Text('No OCR records found.'))
                    : ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final item = filtered[index];
                          return ListTile(
                            leading: item.imagePath.isNotEmpty &&
                                    File(item.imagePath).existsSync()
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: Image.file(
                                      File(item.imagePath),
                                      width: 48,
                                      height: 48,
                                      fit: BoxFit.cover,
                                    ),
                                  )
                                : const Icon(Icons.document_scanner),
                            title: Text(
                              item.text.replaceAll('\n', ' '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text(
                              '${item.engine} • ${item.createdAt.toIso8601String().substring(0, 16)}'
                              '${item.ocvPassed != null ? (item.ocvPassed! ? ' • PASS' : ' • FAIL') : ''}',
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline, size: 20),
                              onPressed: () async {
                                await repo.deleteRecord(item.id);
                                if (mounted) setState(() {});
                              },
                            ),
                            onTap: () => widget.onSelectRecord(item),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
