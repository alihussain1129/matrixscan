import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// A ring, a disc and a self-drawing check mark. Plays each time [trigger]
/// changes (it does not play on first build). Put it in the scanner Stack,
/// centered on the scan frame, and bump [trigger] on every good decode.
class ExaltedSuccessBurst extends StatefulWidget {
  const ExaltedSuccessBurst({
    super.key,
    required this.trigger,
    required this.color,
    this.size = 180,
  });

  final int trigger;
  final Color color;
  final double size;

  @override
  State<ExaltedSuccessBurst> createState() => _ExaltedSuccessBurstState();
}

class _ExaltedSuccessBurstState extends State<ExaltedSuccessBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 750),
  );

  @override
  void didUpdateWidget(ExaltedSuccessBurst old) {
    super.didUpdateWidget(old);
    if (widget.trigger != old.trigger) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          if (_c.isDismissed) return const SizedBox.shrink();
          return RepaintBoundary(
            child: CustomPaint(
              size: Size.square(widget.size),
              painter: _BurstPainter(_c.value, widget.color),
            ),
          );
        },
      ),
    );
  }
}

class _BurstPainter extends CustomPainter {
  _BurstPainter(this.t, this.color);
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final s = size.width;
    final fade = t < 0.75 ? 1.0 : ((1 - t) / 0.25).clamp(0.0, 1.0);

    final ringT = Curves.easeOutCubic.transform((t / 0.7).clamp(0.0, 1.0));
    canvas.drawCircle(
      c,
      s * (0.30 + 0.20 * ringT),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = color.withValues(alpha: (1 - ringT) * 0.8 * fade),
    );

    final discT = Curves.easeOutBack.transform((t / 0.3).clamp(0.0, 1.0));
    canvas.drawCircle(
      c,
      s * 0.26 * discT,
      Paint()..color = color.withValues(alpha: 0.95 * fade),
    );

    final checkT = Curves.easeOut.transform(
      ((t - 0.15) / 0.35).clamp(0.0, 1.0),
    );
    if (checkT > 0) {
      final path = Path()
        ..moveTo(c.dx - s * 0.12, c.dy + s * 0.01)
        ..lineTo(c.dx - s * 0.03, c.dy + s * 0.10)
        ..lineTo(c.dx + s * 0.13, c.dy - s * 0.09);
      final m = path.computeMetrics().first;
      canvas.drawPath(
        m.extractPath(0, m.length * checkT),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = Colors.white.withValues(alpha: fade),
      );
    }
  }

  @override
  bool shouldRepaint(_BurstPainter old) => old.t != t || old.color != color;
}

// Keeps the dart:ui import used on all SDK versions.
// ignore: unused_element
final ui.Color _unused = const ui.Color(0x00000000);
