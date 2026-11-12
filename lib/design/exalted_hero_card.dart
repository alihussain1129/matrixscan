import 'package:flutter/material.dart';

import 'exalted_press_scale.dart';
import 'exalted_tokens.dart';

/// Big gradient card with a count-up number. Shows a dash while loading.
class ExaltedHeroCard extends StatelessWidget {
  const ExaltedHeroCard({
    super.key,
    required this.title,
    required this.value,
    this.icon = Icons.qr_code_scanner,
    this.footnote,
    this.loading = false,
    this.onTap,
  });

  final String title;
  final int value;
  final IconData icon;
  final String? footnote;
  final bool loading;
  final VoidCallback? onTap;

  static String _fmt(int v) => v.toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );

  @override
  Widget build(BuildContext context) {
    final t = ExaltedTokens.of(context);
    final text = Theme.of(context).textTheme;
    final reduced = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final end = Color.lerp(t.brand, t.accent, 0.45)!;
    final radius = BorderRadius.circular(ExaltedRadius.lg);
    const white = Colors.white;

    final numberStyle = text.displaySmall?.copyWith(
      color: white,
      fontWeight: FontWeight.w800,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    final card = Container(
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [t.brand, end],
        ),
        boxShadow: [
          BoxShadow(
            color: t.brand.withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          children: [
            Positioned(right: -30, top: -30, child: _orb(130, 0.10)),
            Positioned(right: 36, bottom: -55, child: _orb(110, 0.07)),
            Padding(
              padding: const EdgeInsets.all(ExaltedSpace.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: white.withValues(alpha: 0.18),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(icon, color: white, size: 18),
                      ),
                      const SizedBox(width: ExaltedSpace.sm + 4),
                      Text(
                        title,
                        style: text.titleSmall?.copyWith(
                          color: white.withValues(alpha: 0.9),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      if (onTap != null)
                        Icon(
                          Icons.arrow_forward_rounded,
                          color: white.withValues(alpha: 0.85),
                          size: 20,
                        ),
                    ],
                  ),
                  const SizedBox(height: ExaltedSpace.md),
                  if (loading)
                    Text('\u2014', style: numberStyle)
                  else
                    TweenAnimationBuilder<double>(
                      tween: Tween<double>(begin: 0, end: value.toDouble()),
                      duration: reduced
                          ? Duration.zero
                          : const Duration(milliseconds: 900),
                      curve: Curves.easeOutCubic,
                      builder: (context, v, _) =>
                          Text(_fmt(v.round()), style: numberStyle),
                    ),
                  if (footnote != null) ...[
                    const SizedBox(height: ExaltedSpace.xs),
                    Text(
                      footnote!,
                      style: text.bodyMedium?.copyWith(
                        color: white.withValues(alpha: 0.82),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );

    return Semantics(
      container: true,
      label: loading ? title : '$title ${_fmt(value)}',
      child: onTap == null
          ? card
          : ExaltedPressScale(onTap: onTap, haptic: true, child: card),
    );
  }

  static Widget _orb(double size, double alpha) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: Colors.white.withValues(alpha: alpha),
    ),
  );
}
