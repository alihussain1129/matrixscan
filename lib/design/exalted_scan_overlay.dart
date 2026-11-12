import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import 'exalted_motion.dart';
import 'exalted_tokens.dart';

enum ExaltedScanState { searching, detected, success, error }

/// Laser, corner brackets and glow drawn over the camera preview.
/// One AnimationController and one CustomPainter inside a RepaintBoundary,
/// so the camera preview is never rebuilt by this animation.
class ExaltedScanOverlay extends StatefulWidget {
  const ExaltedScanOverlay({
    super.key,
    this.state = ExaltedScanState.searching,
    this.inset = 32,
  });

  final ExaltedScanState state;
  final double inset;

  @override
  State<ExaltedScanOverlay> createState() => _ExaltedScanOverlayState();
}

class _ExaltedScanOverlayState extends State<ExaltedScanOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (ExaltedMotion.reduced(context)) {
      _c.stop();
      _c.value = 0.5;
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Color _colorFor(ExaltedTokens t) {
    switch (widget.state) {
      case ExaltedScanState.searching:
        return t.accent;
      case ExaltedScanState.detected:
        return t.warning;
      case ExaltedScanState.success:
        return t.success;
      case ExaltedScanState.error:
        return t.danger;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ExaltedTokens.of(context);
    final target = _colorFor(tokens);
    final showLaser =
        widget.state == ExaltedScanState.searching ||
        widget.state == ExaltedScanState.detected;
    return IgnorePointer(
      child: RepaintBoundary(
        child: TweenAnimationBuilder<Color?>(
          tween: ColorTween(end: target),
          duration: ExaltedMotion.d(context, ExaltedMotion.base),
          builder: (context, color, _) {
            return CustomPaint(
              size: Size.infinite,
              painter: _ScanPainter(
                t: _c,
                color: color ?? target,
                inset: widget.inset,
                showLaser: showLaser,
                tight:
                    widget.state == ExaltedScanState.success ||
                    widget.state == ExaltedScanState.detected,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ScanPainter extends CustomPainter {
  _ScanPainter({
    required this.t,
    required this.color,
    required this.inset,
    required this.showLaser,
    required this.tight,
  }) : super(repaint: t);

  final Animation<double> t;
  final Color color;
  final double inset;
  final bool showLaser;
  final bool tight;

  @override
  void paint(Canvas canvas, Size size) {
    final extra = tight ? 8.0 : 0.0;
    final rect = (Offset.zero & size).deflate(inset + extra);
    if (rect.width <= 0 || rect.height <= 0) return;
    final eased = Curves.easeInOut.transform(t.value);

    final pulse = lerpDouble(0.85, 1.0, eased)!;
    final bracket = Paint()
      ..color = color.withValues(alpha: pulse)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    const len = 28.0;
    final r = rect;
    final path = Path()
      ..moveTo(r.left, r.top + len)
      ..lineTo(r.left, r.top)
      ..lineTo(r.left + len, r.top)
      ..moveTo(r.right - len, r.top)
      ..lineTo(r.right, r.top)
      ..lineTo(r.right, r.top + len)
      ..moveTo(r.right, r.bottom - len)
      ..lineTo(r.right, r.bottom)
      ..lineTo(r.right - len, r.bottom)
      ..moveTo(r.left + len, r.bottom)
      ..lineTo(r.left, r.bottom)
      ..lineTo(r.left, r.bottom - len);
    canvas.drawPath(path, bracket);

    if (!showLaser) return;

    final y = lerpDouble(r.top + 4, r.bottom - 4, eased)!;
    const glowH = 44.0;
    final glowRect = Rect.fromLTRB(r.left, y - glowH, r.right, y);
    canvas.drawRect(
      glowRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0), color.withValues(alpha: 0.22)],
        ).createShader(glowRect),
    );
    final line = Rect.fromLTRB(r.left, y - 1, r.right, y + 1);
    canvas.drawRect(
      line,
      Paint()
        ..shader = LinearGradient(
          colors: [
            color.withValues(alpha: 0),
            color,
            color,
            color.withValues(alpha: 0),
          ],
          stops: const [0, 0.2, 0.8, 1],
        ).createShader(line),
    );
  }

  @override
  bool shouldRepaint(_ScanPainter old) =>
      old.color != color ||
      old.inset != inset ||
      old.showLaser != showLaser ||
      old.tight != tight;
}
