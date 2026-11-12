import 'package:flutter/material.dart';

import 'exalted_motion.dart';
import 'exalted_tokens.dart';

enum ExaltedStateKind { empty, error, paused, permissionDenied, loading }

/// One widget for empty, error, paused, permission-denied and loading
/// states, so every workspace looks the same.
class ExaltedStateView extends StatelessWidget {
  const ExaltedStateView({
    super.key,
    required this.kind,
    this.title,
    this.message,
    this.actionLabel,
    this.onAction,
  });

  final ExaltedStateKind kind;
  final String? title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  IconData get _icon {
    switch (kind) {
      case ExaltedStateKind.empty:
        return Icons.inbox_outlined;
      case ExaltedStateKind.error:
        return Icons.error_outline;
      case ExaltedStateKind.paused:
        return Icons.pause_circle_outline;
      case ExaltedStateKind.permissionDenied:
        return Icons.no_photography_outlined;
      case ExaltedStateKind.loading:
        return Icons.center_focus_strong_outlined;
    }
  }

  String get _defaultTitle {
    switch (kind) {
      case ExaltedStateKind.empty:
        return 'Nothing here yet';
      case ExaltedStateKind.error:
        return 'Something went wrong';
      case ExaltedStateKind.paused:
        return 'Scanning paused';
      case ExaltedStateKind.permissionDenied:
        return 'Camera access is off';
      case ExaltedStateKind.loading:
        return 'Starting camera';
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ExaltedTokens.of(context);
    final color = kind == ExaltedStateKind.error ? t.danger : t.brand;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: ExaltedMotion.d(context, ExaltedMotion.slow),
      curve: ExaltedMotion.curve,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.scale(scale: 0.96 + 0.04 * v, child: child),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(ExaltedSpace.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                  ),
                  child: kind == ExaltedStateKind.loading
                      ? Padding(
                          padding: const EdgeInsets.all(22),
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: color,
                          ),
                        )
                      : Icon(_icon, size: 34, color: color),
                ),
                const SizedBox(height: ExaltedSpace.md),
                Text(
                  title ?? _defaultTitle,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (message != null) ...[
                  const SizedBox(height: ExaltedSpace.sm),
                  Text(
                    message!,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: t.textMuted),
                  ),
                ],
                if (actionLabel != null && onAction != null) ...[
                  const SizedBox(height: ExaltedSpace.md),
                  FilledButton(onPressed: onAction, child: Text(actionLabel!)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
