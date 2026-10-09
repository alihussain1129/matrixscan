import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';
import '../../interpret/interpreter.dart';
import '../../verify/verification_engine.dart';
import 'interpretation_view.dart';

/// Shows the interpretation at once, then adds verification results when the
/// checks finish. With no [verifier] it is just [InterpretationView].
class VerifiedInterpretationView extends StatefulWidget {
  const VerifiedInterpretationView({
    super.key,
    required this.interpretation,
    this.verifier,
    this.allowedSources = const {},
  });

  final Interpretation interpretation;
  final VerificationEngine? verifier;
  final Set<String> allowedSources;

  @override
  State<VerifiedInterpretationView> createState() =>
      _VerifiedInterpretationViewState();
}

class _VerifiedInterpretationViewState
    extends State<VerifiedInterpretationView> {
  Interpretation? _enriched;
  bool _busy = false;
  String? _key;

  static String _keyOf(Interpretation i, Set<String> allowed) {
    var raw = '';
    for (final f in i.allFields) {
      if (f.id == 'raw') {
        raw = f.value ?? '';
        break;
      }
    }
    final ids = allowed.toList()..sort();
    return '$raw|${ids.join(',')}';
  }

  void _start() {
    final verifier = widget.verifier;
    _enriched = null;
    _busy = false;
    if (verifier == null) {
      _key = null;
      return;
    }
    final base = widget.interpretation;
    final key = _keyOf(base, widget.allowedSources);
    _key = key;
    _busy = true;
    verifier
        .verify(base, allowedSources: widget.allowedSources)
        .then((report) {
          if (!mounted || _key != key) return;
          setState(() {
            _enriched = applyVerification(base, report);
            _busy = false;
          });
        })
        .catchError((Object _) {
          if (!mounted || _key != key) return;
          setState(() => _busy = false);
        });
  }

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(VerifiedInterpretationView old) {
    super.didUpdateWidget(old);
    final newKey = widget.verifier == null
        ? null
        : _keyOf(widget.interpretation, widget.allowedSources);
    if (newKey != _key || old.verifier != widget.verifier) _start();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _busy
            ? Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text('Checking sources\u2026', style: text.bodySmall),
                  ],
                ),
              )
            : const SizedBox.shrink(),
        InterpretationView(interpretation: _enriched ?? widget.interpretation),
      ],
    );
  }
}