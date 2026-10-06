import 'package:flutter/material.dart';

/// Draws the scan frame: corner brackets plus an animated scan line.
class ScanFramePainter extends CustomPainter {
  ScanFramePainter({required this.progress, required this.color});

  /// 0.0 (top) to 1.0 (bottom) position of the scan line.
  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    const double len = 34;

    // Faint outline of the scan area.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, w, h),
        const Radius.circular(18),
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.12),
    );

    // Corner brackets.
    final bracket = Paint()
      ..color = color
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(
      Path()
        ..moveTo(0, len)
        ..lineTo(0, 0)
        ..lineTo(len, 0),
      bracket,
    );
    canvas.drawPath(
      Path()
        ..moveTo(w - len, 0)
        ..lineTo(w, 0)
        ..lineTo(w, len),
      bracket,
    );
    canvas.drawPath(
      Path()
        ..moveTo(w, h - len)
        ..lineTo(w, h)
        ..lineTo(w - len, h),
      bracket,
    );
    canvas.drawPath(
      Path()
        ..moveTo(len, h)
        ..lineTo(0, h)
        ..lineTo(0, h - len),
      bracket,
    );

    // Scan line with a soft glow.
    final y = 14 + (h - 28) * progress;
    final glowRect = Rect.fromLTWH(14, y - 8, w - 28, 16);
    canvas.drawRect(
      glowRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0),
            color.withValues(alpha: 0.22),
            color.withValues(alpha: 0),
          ],
        ).createShader(glowRect),
    );
    final lineRect = Rect.fromLTWH(14, y - 1, w - 28, 2);
    canvas.drawRect(
      lineRect,
      Paint()
        ..shader = LinearGradient(
          colors: [
            color.withValues(alpha: 0),
            color,
            color.withValues(alpha: 0),
          ],
        ).createShader(lineRect),
    );
  }

  @override
  bool shouldRepaint(ScanFramePainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}