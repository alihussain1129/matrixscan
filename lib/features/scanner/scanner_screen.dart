import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_shadows.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/exalted_button.dart';
import '../../core/widgets/exalted_logo.dart';
import 'scan_frame_painter.dart';
import 'scanner_controller.dart';

/// Main scanner screen. Camera preview is added in Phase 4.
class ScannerScreen extends ConsumerStatefulWidget {
  const ScannerScreen({super.key});

  @override
  ConsumerState<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends ConsumerState<ScannerScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _line = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat(reverse: true);

  // The camera screen always uses dark chrome.
  late final ThemeData _darkTheme = AppTheme.dark();

  @override
  void dispose() {
    _line.dispose();
    super.dispose();
  }

  void _comingSoon(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
      );
  }

  @override
  Widget build(BuildContext context) {
    final ui = ref.watch(scannerControllerProvider);
    final ctrl = ref.read(scannerControllerProvider.notifier);

    return Theme(
      data: _darkTheme,
      child: Builder(
        builder: (context) {
          final theme = Theme.of(context);
          final scheme = theme.colorScheme;
          final text = theme.textTheme;

          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle.light,
            child: Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -0.2),
                  radius: 1.1,
                  colors: [Color(0xFF1B1C20), Color(0xFF0A0A0B)],
                ),
              ),
              child: SafeArea(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                  child: Column(
                    children: [
                      const SizedBox(height: AppSpacing.md),
                      Row(
                        children: [
                          const ExaltedLogo(width: 120),
                          const Spacer(),
                          IconButton(
                            tooltip: 'Settings',
                            onPressed: () =>
                                ref.read(navIndexProvider.notifier).set(2),
                            icon: const Icon(Icons.settings_outlined),
                            color: Colors.white,
                            iconSize: 26,
                            constraints: const BoxConstraints(
                              minWidth: 48,
                              minHeight: 48,
                            ),
                          ),
                        ],
                      ),
                      _ModeChip(
                        continuous: ui.continuous,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          ctrl.toggleContinuous();
                        },
                      ),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            var side = constraints.biggest.shortestSide * 0.82;
                            if (side > 340) side = 340;
                            return Center(
                              child: Semantics(
                                label:
                                    'Scan area. Align a code inside the frame.',
                                child: SizedBox(
                                  width: side,
                                  height: side,
                                  child: Stack(
                                    children: [
                                      Center(
                                        child: Text(
                                          'CAMERA PREVIEW\nPhase 4',
                                          textAlign: TextAlign.center,
                                          style: text.labelSmall,
                                        ),
                                      ),
                                      Positioned.fill(
                                        child: AnimatedBuilder(
                                          animation: _line,
                                          builder: (context, child) {
                                            return CustomPaint(
                                              painter: ScanFramePainter(
                                                progress: Curves.easeInOut
                                                    .transform(_line.value),
                                                color: scheme.primary,
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      Text(
                        'Align a code inside the frame',
                        style: text.bodyMedium!.copyWith(
                          color: Colors.white70,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _RoundControl(
                            icon: ui.flashOn
                                ? Icons.flash_on
                                : Icons.flash_off,
                            label: 'Flash',
                            active: ui.flashOn,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              ctrl.toggleFlash();
                            },
                          ),
                          _CaptureButton(
                            onTap: () => _comingSoon(
                              'Camera scanning arrives in Phase 4',
                            ),
                          ),
                          _RoundControl(
                            icon: Icons.bolt,
                            label: 'Auto',
                            active: ui.autoScan,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              ctrl.toggleAuto();
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      ExaltedButton(
                        label: 'Gallery',
                        icon: Icons.photo_library_outlined,
                        outlined: true,
                        expand: true,
                        onPressed: () => _comingSoon(
                          'Gallery import arrives in Phase 5',
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({required this.continuous, required this.onTap});

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
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
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

class _RoundControl extends StatelessWidget {
  const _RoundControl({
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
                        : Colors.white.withValues(alpha: 0.08),
                    border: Border.all(
                      color: active ? primary : Colors.white24,
                    ),
                  ),
                  child: Icon(icon, color: Colors.white),
                ),
                const SizedBox(height: 6),
                Text(label.toUpperCase(), style: theme.textTheme.labelSmall),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CaptureButton extends StatefulWidget {
  const _CaptureButton({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_CaptureButton> createState() => _CaptureButtonState();
}

class _CaptureButtonState extends State<_CaptureButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Semantics(
      button: true,
      label: 'Scan',
      onTap: widget.onTap,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _down = true),
          onTapUp: (_) => setState(() => _down = false),
          onTapCancel: () => setState(() => _down = false),
          onTap: widget.onTap,
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
              child: const Icon(
                Icons.qr_code_scanner,
                color: Colors.white,
                size: 34,
              ),
            ),
          ),
        ),
      ),
    );
  }
}