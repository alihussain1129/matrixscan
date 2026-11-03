import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/router/app_router.dart';
import 'scanner_controller.dart';

/// Camera settings for the desktop workspace.
Future<void> showCameraSettingsDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _CameraSettingsDialog(),
  );
}

class _CameraSettingsDialog extends ConsumerWidget {
  const _CameraSettingsDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ui = ref.watch(scannerControllerProvider);
    final ctrl = ref.read(scannerControllerProvider.notifier);
    final onDecoder = ref.watch(navIndexProvider) == kScanTab;
    final theme = Theme.of(context);
    final cam = ui.camera;
    final size = (cam != null && cam.value.isInitialized)
        ? cam.value.previewSize
        : null;
    final label = theme.textTheme.labelMedium;
    final note = theme.textTheme.bodySmall;

    return AlertDialog(
      title: const Text('Camera settings'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Camera', style: label),
            Text(cam == null ? 'No camera is open' : cam.description.name),
            const SizedBox(height: 12),
            Text('Preview size (reported by the camera)', style: label),
            Text(
              size == null
                  ? 'Not available'
                  : '${size.width.toInt()} x ${size.height.toInt()}',
            ),
            const SizedBox(height: 16),
            Text('Resolution preset', style: label),
            const SizedBox(height: 8),
            SegmentedButton<CameraQuality>(
              segments: [
                for (final q in CameraQuality.values)
                  ButtonSegment<CameraQuality>(value: q, label: Text(q.label)),
              ],
              selected: {ui.quality},
              showSelectedIcon: false,
              onSelectionChanged: (s) => ctrl.setQuality(s.first),
            ),
            const SizedBox(height: 8),
            Text(
              onDecoder
                  ? 'The preset is saved and used the next time the camera starts. Use Restart camera to apply it now.'
                  : 'The preset is saved and used the next time the camera starts on the Decoder screen.',
              style: note,
            ),
            const SizedBox(height: 12),
            Text(
              'Flash, focus and zoom controls are not available for desktop cameras.',
              style: note,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: onDecoder ? () => unawaited(ctrl.retry()) : null,
          child: const Text('Restart camera'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
