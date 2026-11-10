import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import 'combined_inspector.dart';
import 'gs1_fields.dart';
import 'inspection_log.dart';
import 'inspection_row.dart';
import 'inspection_row_card.dart';
import '../../core/config/data_directory_provider.dart';

/// Every inspection event as one row: decoded fields, printed text, checks.
class InspectionDataScreen extends ConsumerStatefulWidget {
  const InspectionDataScreen({super.key});

  @override
  ConsumerState<InspectionDataScreen> createState() =>
      _InspectionDataScreenState();
}

class _InspectionDataScreenState extends ConsumerState<InspectionDataScreen> {
  static const double _tableWidth = 1500;

  List<InspectionRow> _rows = const [];
  bool _loading = true;
  String _query = '';
  RowStatus? _filter;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final rows = await ref.read(inspectionLogProvider).loadAll();
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  static String _time(DateTime t) =>
      '${t.year}-${_two(t.month)}-${_two(t.day)} ${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';

  List<InspectionRow> get _shown {
    final q = _query.trim().toLowerCase();
    return [
      for (final r in _rows)
        if ((_filter == null || r.status == _filter) &&
            (q.isEmpty ||
                '${r.raw} ${r.ocrText ?? ''} ${r.reasons.join(' ')} ${r.fields.values.join(' ')}'
                    .toLowerCase()
                    .contains(q)))
          r,
    ];
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _export() async {
    try {
      final dir = await ref.read(dataDirectoryProvider)();
      final now = DateTime.now();
      final stamp =
          '${now.year}${_two(now.month)}${_two(now.day)}_${_two(now.hour)}${_two(now.minute)}${_two(now.second)}';
      final file = File(
        '${dir.path}${Platform.pathSeparator}inspection_rows_$stamp.csv',
      );
      await file.writeAsString(inspectionRowsToCsv(_shown));
      _snack('Saved ${file.path}');
    } catch (e) {
      _snack('Could not export: $e');
    }
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: inspectionRowsToCsv(_shown)));
    _snack('CSV copied');
  }

  void _details(InspectionRow r) {
    final theme = Theme.of(context);
    final image = r.imagePath;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            RowStatusChip(r.status),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _time(r.createdAt),
                style: theme.textTheme.titleMedium,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${r.symbology} · ${r.source}${r.decodeMs == null ? '' : ' · decode ${r.decodeMs!.toStringAsFixed(1)} ms'}',
                ),
                const SizedBox(height: 12),
                if (r.fields.isEmpty)
                  SelectableText(r.raw)
                else
                  for (final e in r.fields.entries)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 130,
                            child: Text(Gs1Field(e.key, e.value).label),
                          ),
                          Expanded(
                            child: SelectableText(
                              Gs1Field(e.key, e.value).display,
                            ),
                          ),
                        ],
                      ),
                    ),
                const SizedBox(height: 12),
                for (final reason in r.reasons)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('• $reason'),
                  ),
                const SizedBox(height: 8),
                Text('Printed text (OCR)', style: theme.textTheme.labelMedium),
                const SizedBox(height: 4),
                if (r.ocrText == null)
                  Text(r.ocrNote ?? 'OCR did not run.')
                else if (r.ocrText!.trim().isEmpty)
                  const Text('No text was read.')
                else
                  SelectableText(r.ocrText!.trim()),
                const SizedBox(height: 12),
                Text('Raw code', style: theme.textTheme.labelMedium),
                SelectableText(r.raw),
                if (image != null && File(image).existsSync()) ...[
                  const SizedBox(height: 12),
                  Image.file(File(image), height: 220, fit: BoxFit.contain),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _cell(String text, double width, {TextStyle? style}) => SizedBox(
    width: width,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: style,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(combinedInspectorProvider.select((s) => s.count), (
      previous,
      next,
    ) {
      unawaited(_load());
    });

    final theme = Theme.of(context);
    final colors = context.exalted;
    final shown = _shown;
    final pass = shown.where((r) => r.status == RowStatus.pass).length;
    final fail = shown.where((r) => r.status == RowStatus.fail).length;
    final review = shown.where((r) => r.status == RowStatus.review).length;
    final head = theme.textTheme.labelSmall!.copyWith(
      color: colors.muted,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.6,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inspection data'),
        actions: [
          IconButton(
            tooltip: 'Reload',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Copy CSV',
            onPressed: _copy,
            icon: const Icon(Icons.copy_all_outlined),
          ),
          IconButton(
            tooltip: 'Export CSV',
            onPressed: _export,
            icon: const Icon(Icons.download_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 320,
                  child: TextField(
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search code, serial, batch, text',
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
                for (final s in <RowStatus?>[null, ...RowStatus.values])
                  ChoiceChip(
                    label: Text(s == null ? 'All' : s.name.toUpperCase()),
                    selected: _filter == s,
                    onSelected: (_) => setState(() => _filter = s),
                  ),
                Text(
                  '${shown.length} rows · PASS $pass · FAIL $fail · REVIEW $review',
                  style: theme.textTheme.bodyMedium!.copyWith(
                    color: colors.muted,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : shown.isEmpty
                ? Center(
                    child: Text(
                      _rows.isEmpty
                          ? 'No inspections yet. Scan a code in the Decoder.'
                          : 'No rows match.',
                      style: theme.textTheme.bodyMedium!.copyWith(
                        color: colors.muted,
                      ),
                    ),
                  )
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: _tableWidth,
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              children: [
                                _cell('TIME', 160, style: head),
                                _cell('STATUS', 100, style: head),
                                _cell('SYMBOLOGY', 110, style: head),
                                _cell('GTIN', 150, style: head),
                                _cell('BATCH / LOT', 130, style: head),
                                _cell('EXPIRY', 100, style: head),
                                _cell('SERIAL', 160, style: head),
                                _cell('PRINTED TEXT (OCR)', 230, style: head),
                                _cell('CHECKS', 360, style: head),
                              ],
                            ),
                          ),
                          const Divider(height: 1),
                          Expanded(
                            child: ListView.builder(
                              itemCount: shown.length,
                              itemBuilder: (context, i) {
                                final r = shown[i];
                                final body = theme.textTheme.bodyMedium!;
                                final ocr = r.ocrText == null
                                    ? '–'
                                    : (r.ocrText!.trim().isEmpty
                                          ? 'no text'
                                          : r.ocrText!.trim().replaceAll(
                                              '\n',
                                              ' | ',
                                            ));
                                return InkWell(
                                  onTap: () => _details(r),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      border: Border(
                                        bottom: BorderSide(
                                          color: colors.outline,
                                        ),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        _cell(
                                          _time(r.createdAt),
                                          160,
                                          style: body,
                                        ),
                                        SizedBox(
                                          width: 100,
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                            ),
                                            child: Align(
                                              alignment: Alignment.centerLeft,
                                              child: RowStatusChip(r.status),
                                            ),
                                          ),
                                        ),
                                        _cell(r.symbology, 110, style: body),
                                        _cell(
                                          r.gtin ??
                                              (r.fields.isEmpty ? r.raw : '–'),
                                          150,
                                          style: body,
                                        ),
                                        _cell(r.lot ?? '–', 130, style: body),
                                        _cell(
                                          r.expiryDisplay ?? '–',
                                          100,
                                          style: body,
                                        ),
                                        _cell(
                                          r.serial ?? '–',
                                          160,
                                          style: body,
                                        ),
                                        _cell(ocr, 230, style: body),
                                        _cell(
                                          r.reasons.isEmpty
                                              ? 'OK'
                                              : r.reasons.join('; '),
                                          360,
                                          style: body.copyWith(
                                            color: r.reasons.isEmpty
                                                ? colors.valid
                                                : rowStatusColor(
                                                    context,
                                                    r.status,
                                                  ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
