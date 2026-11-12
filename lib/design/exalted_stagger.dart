import 'package:flutter/material.dart';

/// Fades and slides its child up once, after a delay of [index] steps.
/// Use index 0, 1, 2... on cards in a list so they arrive one by one.
class ExaltedStagger extends StatefulWidget {
  const ExaltedStagger({
    super.key,
    required this.child,
    this.index = 0,
    this.step = const Duration(milliseconds: 70),
    this.duration = const Duration(milliseconds: 450),
    this.dy = 20,
  });

  final Widget child;
  final int index;
  final Duration step;
  final Duration duration;
  final double dy;

  @override
  State<ExaltedStagger> createState() => _ExaltedStaggerState();
}

class _ExaltedStaggerState extends State<ExaltedStagger>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _a;

  @override
  void initState() {
    super.initState();
    final i = widget.index.clamp(0, 8);
    final delay = widget.step * i;
    final total = delay + widget.duration;
    _c = AnimationController(vsync: this, duration: total);
    _a = CurvedAnimation(
      parent: _c,
      curve: Interval(
        delay.inMilliseconds / total.inMilliseconds,
        1.0,
        curve: Curves.easeOutCubic,
      ),
    );
    _c.forward();
  }

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
    return AnimatedBuilder(
      animation: _a,
      child: widget.child,
      builder: (context, child) => Opacity(
        opacity: _a.value.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, (1 - _a.value) * widget.dy),
          child: child,
        ),
      ),
    );
  }
}
