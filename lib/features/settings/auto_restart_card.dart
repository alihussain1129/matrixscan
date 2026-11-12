import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/config/config_controller.dart';

/// Switch and limit for restarting the app after an uncaught async error.
/// Saved through the config controller. A change applies at the next start.
class AutoRestartCard extends ConsumerWidget {
  const AutoRestartCard({super.key});

  static const List<int> limits = [1, 2, 3, 5, 10];

  Future<void> _save(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> change,
  ) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final result = await ref.read(configControllerProvider.notifier).patch({
      'startup': change,
    });
    String? msg;
    if (!result.applied) {
      msg = result.issues.map((i) => '$i').join('\n');
    } else if (result.saveError != null) {
      msg = 'Applied, but could not be saved: ${result.saveError}';
    }
    if (msg != null) messenger?.showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final StartupConfig sc = ref.watch(
      configControllerProvider.select((c) => c.startup),
    );
    final choices = {...limits, sc.maxRestartsPerHour}.toList()..sort();
    final supported = !Platform.isIOS;
    final style = Theme.of(context).textTheme.bodySmall;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          key: const Key('restart-enable'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Restart the app after a crash'),
          subtitle: Text(
            !supported
                ? 'Not supported on this platform yet.'
                : Platform.isAndroid
                ? 'Starts the app again after a crash in its Android code. Takes effect right away.'
                : 'Starts a new copy after an uncaught error. Applies the next time the app starts.',
          ),
          value: sc.autoRestart,
          onChanged: supported
              ? (v) => _save(context, ref, {'autoRestart': v})
              : null,
        ),
        Row(
          children: [
            const Expanded(child: Text('Most restarts per hour')),
            DropdownButton<int>(
              key: const Key('restart-limit'),
              value: sc.maxRestartsPerHour,
              items: [
                for (final n in choices)
                  DropdownMenuItem<int>(value: n, child: Text('$n')),
              ],
              onChanged: supported
                  ? (v) {
                      if (v != null) {
                        _save(context, ref, {'maxRestartsPerHour': v});
                      }
                    }
                  : null,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'After the limit is reached the app stays closed instead of looping. Errors are written to crash.log.',
          style: style,
        ),
      ],
    );
  }
}
