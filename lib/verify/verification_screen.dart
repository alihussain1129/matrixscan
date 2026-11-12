import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_spacing.dart';
import 'verification_settings.dart';

/// Controls the user's opt-in online verification sources.
class VerificationScreen extends ConsumerWidget {
  const VerificationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final allowed = ref.watch(allowedSourcesProvider);
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          children: [
            Text('Verification', style: theme.textTheme.headlineMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Structural checks run on this device. Online sources stay off '
              'until you enable them here.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.xl),
            Text('ON-DEVICE CHECKS', style: theme.textTheme.labelLarge),
            const ListTile(
              leading: Icon(Icons.check_circle_outline),
              title: Text('Code structure and checksum'),
              subtitle: Text('Runs locally when a supported code is scanned.'),
            ),
            const ListTile(
              leading: Icon(Icons.link_outlined),
              title: Text('URL safety checks'),
              subtitle: Text(
                'Inspects the scanned address without opening it.',
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('OPTIONAL ONLINE SOURCES', style: theme.textTheme.labelLarge),
            const SizedBox(height: AppSpacing.xs),
            for (final source in onlineSourceChoices)
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text(source.name),
                subtitle: Text(source.subtitle),
                value: allowed.contains(source.id),
                onChanged: (value) => ref
                    .read(allowedSourcesProvider.notifier)
                    .setAllowed(source.id, value),
              ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'A catalogue match is informational. It does not prove that a '
              'product is authentic or safe.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
