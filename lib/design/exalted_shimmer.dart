import 'package:flutter/material.dart';

/// Sweeps a soft highlight across [ExaltedSkeletonBox] children.
/// Use instead of a spinner while a list or card loads.
class ExaltedShimmer extends StatefulWidget {
  const ExaltedShimmer({super.key, required this.child});
  final Widget child;

  @override
  State<ExaltedShimmer> createState() => _ExaltedShimmerState();
}

class _ExaltedShimmerState extends State<ExaltedShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      return widget.child;
    }
    final dark = Theme.of(context).brightness == Brightness.dark;
    final hi = Colors.white.withValues(alpha: dark ? 0.10 : 0.55);
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (rect) => LinearGradient(
          colors: [hi.withValues(alpha: 0), hi, hi.withValues(alpha: 0)],
          stops: const [0.35, 0.5, 0.65],
          transform: _Slide(rect.width * (_c.value * 3 - 1)),
        ).createShader(rect),
        child: child,
      ),
    );
  }
}

class _Slide extends GradientTransform {
  const _Slide(this.dx);
  final double dx;
  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(dx, 0, 0);
}

class ExaltedSkeletonBox extends StatelessWidget {
  const ExaltedSkeletonBox({
    super.key,
    this.width,
    this.height = 16,
    this.radius = 8,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme.onSurface;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}
