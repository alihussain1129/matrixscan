import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../interpret/default_registry.dart';
import '../../interpret/interpreter.dart';
import '../../verify/verification_engine.dart';
import '../scanner/verified_interpretation_view.dart';

final InterpreterRegistry _registry = defaultInterpreterRegistry();

/// Everything about one decoded code, in three parts: Overview, the exact
/// original content, and the interpretation (parsed fields, validation,
/// verification, provenance). The raw text is never changed by parsing.
class ResultBody extends StatefulWidget {
  const ResultBody({
    super.key,
    required this.raw,
    required this.symbology,
    this.source,
    this.scannedAt,
    this.decodeMicros,
    this.verifier,
    this.allowedSources = const {},
  });

  /// Exactly as decoded.
  final String raw;
  final String symbology;

  /// For example "live" or "gallery". Shown only when known.
  final String? source;

  /// Shown only when a real time is known.
  final DateTime? scannedAt;
  final int? decodeMicros;
  final VerificationEngine? verifier;
  final Set<String> allowedSources;

  @override
  State<ResultBody> createState() => _ResultBodyState();
}

class _ResultBodyState extends State<ResultBody> {
  late Interpretation _interp = _interpret();
  bool _revealed = false;

  Interpretation _interpret() => _registry.interpret(
    ScanPayload(
      raw: widget.raw,
      symbology: widget.symbology,
      source: widget.source,
      scannedAt: widget.scannedAt,
    ),
  );

  @override
  void didUpdateWidget(ResultBody old) {
    super.didUpdateWidget(old);
    if (old.raw != widget.raw || old.symbology != widget.symbology) {
      _interp = _interpret();
      _revealed = false;
    }
  }

  void _toast(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _copyRaw() async {
    await Clipboard.setData(ClipboardData(text: widget.raw));
    HapticFeedback.selectionClick();
    _toast('Original content copied');
  }

  Future<void> _shareRaw() async {
    try {
      await SharePlus.instance.share(ShareParams(text: widget.raw));
    } catch (_) {
      _toast("Couldn't open the share sheet.");
    }
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  static String _fmt(DateTime t) {
    final l = t.toLocal();
    return '${l.year}-${_two(l.month)}-${_two(l.day)} '
        '${_two(l.hour)}:${_two(l.minute)}:${_two(l.second)}';
  }

  Widget _card(String title, Widget child) {
    final theme = Theme.of(context);
    final colors = theme.extension<ExaltedColors>()!;
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: colors.surfaceRaised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: BorderSide(color: colors.outline),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleMedium),
              const SizedBox(height: AppSpacing.md),
              child,
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    final theme = Theme.of(context);
    final colors = theme.extension<ExaltedColors>()!;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(
              label,
              style: theme.textTheme.bodySmall!.copyWith(color: colors.muted),
            ),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final colors = theme.extension<ExaltedColors>()!;
    final recognised = _interp.interpreterId != 'none';
    final hidden = _interp.rawIsSensitive && !_revealed;
    final micros = widget.decodeMicros;
    final at = widget.scannedAt;
    final src = widget.source;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _card(
          'Overview',
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _row('Symbology', widget.symbology),
              _row('Interpreted as', _interp.formatName),
              if (micros != null)
                _row('Decode time', '${(micros / 1000).toStringAsFixed(1)} ms'),
              if (at != null) _row('Scanned at', _fmt(at)),
              if (src != null) _row('Source', src),
              _row('Length', '${widget.raw.length} characters'),
              const SizedBox(height: AppSpacing.xs),
              Text(
                recognised
                    ? 'Recognised as ${_interp.formatName}. Decoding a code '
                          'does not show that its content is genuine or safe.'
                    : 'This content was not recognised. The original data '
                          'is shown exactly as decoded.',
                style: text.bodySmall!.copyWith(color: colors.muted),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _card(
          'Original decoded content',
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hidden)
                Text('\u2022' * 12, style: text.bodyLarge)
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 240),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      widget.raw,
                      style: text.bodyMedium!.copyWith(fontFamily: 'monospace'),
                    ),
                  ),
                ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: [
                  if (_interp.rawIsSensitive)
                    TextButton.icon(
                      onPressed: () => setState(() => _revealed = !_revealed),
                      icon: Icon(
                        _revealed ? Icons.visibility_off : Icons.visibility,
                        size: 18,
                      ),
                      label: Text(_revealed ? 'Hide' : 'Reveal'),
                    ),
                  TextButton.icon(
                    onPressed: _copyRaw,
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Copy original'),
                  ),
                  TextButton.icon(
                    onPressed: _shareRaw,
                    icon: const Icon(Icons.ios_share, size: 18),
                    label: const Text('Share'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _card(
          'Interpretation',
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!recognised)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: Text(
                    'Interpretation unavailable for this content. No field '
                    'meanings are guessed.',
                    style: text.bodyMedium,
                  ),
                ),
              VerifiedInterpretationView(
                interpretation: _interp,
                verifier: widget.verifier,
                allowedSources: widget.allowedSources,
              ),
            ],
          ),
        ),
      ],
    );
  }
}