import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shrinks slightly while pressed and springs back on release.
/// Wrap any card, button or nav item. Skips motion in reduced-motion mode.
class ExaltedPressScale extends StatefulWidget {
  const ExaltedPressScale({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.96,
    this.haptic = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  final bool haptic;

  @override
  State<ExaltedPressScale> createState() => _ExaltedPressScaleState();
}

class _ExaltedPressScaleState extends State<ExaltedPressScale> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final enabled = widget.onTap != null || widget.onLongPress != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => _set(true) : null,
      onTapUp: enabled ? (_) => _set(false) : null,
      onTapCancel: enabled ? () => _set(false) : null,
      onTap: widget.onTap == null
          ? null
          : () {
              if (widget.haptic) HapticFeedback.selectionClick();
              widget.onTap!();
            },
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        scale: (_down && !reduced) ? widget.scale : 1.0,
        duration: Duration(milliseconds: reduced ? 0 : (_down ? 90 : 220)),
        curve: _down ? Curves.easeOutCubic : Curves.easeOutBack,
        child: widget.child,
      ),
    );
  }
}

/// An icon that pops when it becomes selected.
class ExaltedBounceIcon extends StatefulWidget {
  const ExaltedBounceIcon({
    super.key,
    required this.icon,
    required this.color,
    required this.size,
    required this.selected,
  });

  final IconData icon;
  final Color color;
  final double size;
  final bool selected;

  @override
  State<ExaltedBounceIcon> createState() => _ExaltedBounceIconState();
}

class _ExaltedBounceIconState extends State<ExaltedBounceIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween<double>(
        begin: 1.0,
        end: 1.3,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 35,
    ),
    TweenSequenceItem(
      tween: Tween<double>(
        begin: 1.3,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.elasticOut)),
      weight: 65,
    ),
  ]).animate(_c);

  @override
  void didUpdateWidget(ExaltedBounceIcon old) {
    super.didUpdateWidget(old);
    if (widget.selected && !old.selected) {
      final reduced = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
      if (!reduced) _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Icon(widget.icon, color: widget.color, size: widget.size),
    );
  }
}
