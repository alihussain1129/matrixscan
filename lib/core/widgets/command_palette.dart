import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../router/app_router.dart';
import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';

/// A command palette (Ctrl+K) that lets users jump to any destination or
/// trigger common actions from anywhere in the app.
///
/// On desktop it is triggered with Ctrl+K. On mobile it is available from the
/// overflow menu.
class CommandPalette extends ConsumerStatefulWidget {
  const CommandPalette({super.key});

  @override
  ConsumerState<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends ConsumerState<CommandPalette> {
  final TextEditingController _query = TextEditingController();
  String _filter = '';

  static const List<_Command> _commands = [
    _Command('Dashboard', kHomeTab, Icons.dashboard, 'Workspace overview'),
    _Command('Scanner', kScanTab, Icons.qr_code_scanner, 'Live scanner'),
    _Command(
      'Decode & OCR',
      kOcrTab,
      Icons.document_scanner,
      'Decode barcodes or OCR',
    ),
    _Command('History', kHistoryTab, Icons.history, 'Scan and OCR history'),
    _Command('Devices', kDevicesTab, Icons.router, 'Linked hardware'),
    _Command(
      'Synchronization',
      kLinkTab,
      Icons.sync_alt,
      'Sync with linked devices',
    ),
    _Command(
      'Verification',
      kVerificationTab,
      Icons.fact_check,
      'Verify codes',
    ),
    _Command(
      'Inspection',
      kInspectionTab,
      Icons.fact_check,
      'Quality inspection',
    ),
    _Command('Settings', kSettingsTab, Icons.tune, 'App settings'),
  ];

  List<_Command> get _filtered {
    if (_filter.isEmpty) return _commands;
    final q = _filter.toLowerCase();
    return _commands.where((c) {
      return c.label.toLowerCase().contains(q) ||
          c.subtitle.toLowerCase().contains(q);
    }).toList();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.exalted;

    return Material(
      color: Colors.transparent,
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 40),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: TextField(
                controller: _query,
                autofocus: true,
                onChanged: (v) => setState(() => _filter = v),
                decoration: InputDecoration(
                  hintText: 'Go to or type a command\u2026',
                  hintStyle: theme.textTheme.bodyLarge?.copyWith(
                    color: colors.muted,
                  ),
                  prefixIcon: const Icon(Icons.search, size: 20),
                  filled: true,
                  fillColor: colors.surfaceRaised,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: colors.outline),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: theme.colorScheme.primary,
                      width: 1.5,
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                style: theme.textTheme.bodyLarge,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _filtered.isEmpty
                  ? Center(
                      child: Text(
                        'No matches',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.muted,
                        ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: _filtered.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final cmd = _filtered[index];
                        return ListTile(
                          leading: Icon(
                            cmd.icon,
                            size: 20,
                            color: theme.colorScheme.primary,
                          ),
                          title: Text(cmd.label),
                          subtitle: Text(
                            cmd.subtitle,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.muted,
                            ),
                          ),
                          onTap: () {
                            Navigator.of(context).pop();
                            ref.read(navIndexProvider.notifier).set(cmd.index);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Command {
  const _Command(this.label, this.index, this.icon, this.subtitle);
  final String label;
  final int index;
  final IconData icon;
  final String subtitle;
}

/// Overlay entry key for the command palette so only one can be open at a time.
final commandPaletteOverlayKey = GlobalKey<NavigatorState>();

/// Opens the command palette as a full-screen route.
Future<void> showCommandPalette(BuildContext context) async {
  await Navigator.of(context).push(
    PageRouteBuilder<void>(
      pageBuilder: (_, _, _) => const CommandPalette(),
      transitionDuration: AppMotion.fast,
      reverseTransitionDuration: AppMotion.fast,
    ),
  );
}
