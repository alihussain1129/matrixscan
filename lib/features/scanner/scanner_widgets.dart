import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_shadows.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/exalted_button.dart';
import 'frame_pipeline.dart';

/// Card shown instead of the camera for permission and error states.
class ScannerStatePanel extends StatelessWidget {
  const ScannerStatePanel({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<ExaltedColors>()!;

    return Container(
      constraints: const BoxConstraints(maxWidth: 320),
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.outline),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: colors.surfaceRaised,
              borderRadius: BorderRadius.circular(AppRadius.sheet),
            ),
            child: Icon(icon, size: 30, color: Colors.white),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.xl),
          ExaltedButton(label: actionLabel, onPressed: onAction),
        ],
      ),
    );
  }
}

/// Ring that shrinks and fades where the user tapped to focus.
class FocusRing extends StatelessWidget {
  const FocusRing({super.key, required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) {
        final opacity = t < 0.6 ? 1.0 : 1.0 - ((t - 0.6) / 0.4);
        return Opacity(
          opacity: opacity.clamp(0.0, 1.0).toDouble(),
          child: Transform.scale(scale: 1.5 - 0.5 * t, child: child),
        );
      },
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 2),
        ),
      ),
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: AppSpacing.sm),
          Text(
            label,
            style: text.labelLarge!.copyWith(color: Colors.white, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class ModeChip extends StatelessWidget {
  const ModeChip({super.key, required this.continuous, required this.onTap});

  final bool continuous;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final label = continuous ? 'CONTINUOUS' : 'SINGLE SCAN';

    return Semantics(
      button: true,
      label: 'Scan mode: $label. Tap to change.',
      onTap: onTap,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            height: 48,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(color: Colors.white24),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      continuous ? Icons.all_inclusive : Icons.filter_1,
                      size: 16,
                      color: Colors.white,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      label,
                      style: text.labelLarge!.copyWith(
                        color: Colors.white,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class RoundControl extends StatelessWidget {
  const RoundControl({
    super.key,
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return Semantics(
      button: true,
      selected: active,
      label: label,
      onTap: onTap,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            width: 72,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOutCubic,
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: active
                        ? primary
                        : Colors.black.withValues(alpha: 0.35),
                    border: Border.all(
                      color: active ? primary : Colors.white24,
                    ),
                  ),
                  child: Icon(icon, color: Colors.white),
                ),
                const SizedBox(height: 6),
                Text(
                  label.toUpperCase(),
                  style: theme.textTheme.labelSmall!.copyWith(
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class CaptureButton extends StatefulWidget {
  const CaptureButton({
    super.key,
    required this.paused,
    required this.enabled,
    required this.onTap,
  });

  final bool paused;
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<CaptureButton> createState() => _CaptureButtonState();
}

class _CaptureButtonState extends State<CaptureButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final enabled = widget.enabled;
    final IconData icon = !enabled
        ? Icons.qr_code_scanner
        : (widget.paused ? Icons.play_arrow_rounded : Icons.pause_rounded);
    final label = widget.paused ? 'Resume scanning' : 'Pause scanning';

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      onTap: enabled ? widget.onTap : null,
      child: ExcludeSemantics(
        child: Opacity(
          opacity: enabled ? 1 : 0.4,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: enabled ? (_) => setState(() => _down = true) : null,
            onTapUp: enabled ? (_) => setState(() => _down = false) : null,
            onTapCancel: enabled ? () => setState(() => _down = false) : null,
            onTap: enabled ? widget.onTap : null,
            child: AnimatedScale(
              scale: _down ? 0.92 : 1,
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOutCubic,
              child: Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: primary,
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: AppShadows.button,
                ),
                child: Icon(icon, color: Colors.white, size: 34),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Debug and profile builds only: live camera and pipeline numbers.
class DebugStatsLine extends StatelessWidget {
  const DebugStatsLine({
    super.key,
    required this.pipeline,
    required this.streaming,
    required this.previewSize,
    required this.qualityLabel,
  });

  final FramePipeline pipeline;
  final bool streaming;
  final String previewSize;
  final String qualityLabel;

  @override
  Widget build(BuildContext context) {
    final style = AppTypography.mono(size: 11, color: Colors.white54);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'PREVIEW $previewSize  ${qualityLabel.toUpperCase()}',
          style: style,
        ),
        ValueListenableBuilder<PipelineStats>(
          valueListenable: pipeline.stats,
          builder: (context, s, child) {
            return Text(
              streaming
                  ? 'STREAM RX ${s.receivedFps}  AN ${s.analyzedFps}  '
                        'SKIP ${s.skippedFps}  ${s.lastAnalyzeMs}ms'
                  : 'STREAM OFF',
              style: style,
            );
          },
        ),
      ],
    );
  }
}
