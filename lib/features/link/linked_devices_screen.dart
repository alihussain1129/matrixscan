import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/widgets/exalted_empty_state.dart';
import '../../core/widgets/exalted_error_state.dart';
import '../../core/widgets/exalted_status_chip.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import 'link_models.dart';
import 'link_journal.dart';
import 'link_pairing.dart';
import 'link_providers.dart';
import 'link_server.dart';
import 'pairing_scan_screen.dart';

String _fmt(DateTime? t) {
  if (t == null) return 'never';
  final l = t.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${l.year}-${two(l.month)}-${two(l.day)} '
      '${two(l.hour)}:${two(l.minute)}';
}

String _short(String id) => id.length <= 12 ? id : '${id.substring(0, 12)}…';

/// Groups the start of a certificate fingerprint so both devices can be
/// compared by eye.
String _fp(String hex) {
  final up = hex.toUpperCase();
  final s = up.length > 32 ? up.substring(0, 32) : up;
  return [
    for (var i = 0; i < s.length; i += 4)
      s.substring(i, math.min(i + 4, s.length)),
  ].join(' ');
}

/// Pairing, linked devices and sync. Desktop shows a QR code and approves
/// phones; Android connects to a desktop and syncs.
class LinkedDevicesScreen extends ConsumerStatefulWidget {
  const LinkedDevicesScreen({super.key});

  @override
  ConsumerState<LinkedDevicesScreen> createState() =>
      _LinkedDevicesScreenState();
}

class _LinkedDevicesScreenState extends ConsumerState<LinkedDevicesScreen> {
  final TextEditingController _code = TextEditingController();
  bool _approvalOpen = false;

  bool get _isDesktop => Platform.isLinux || Platform.isWindows;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _scanCode() async {
    final ctl = ref.read(linkControllerProvider.notifier);
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(builder: (_) => const PairingScanScreen()),
    );
    if (code != null && mounted) ctl.previewCode(code);
  }

  Future<void> _showApproval(PairRequest req) async {
    if (!mounted || _approvalOpen) return;
    _approvalOpen = true;
    final ctl = ref.read(linkControllerProvider.notifier);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Approve this device?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('A device is asking to link with this computer.'),
            const SizedBox(height: 12),
            _kv('Name', req.name),
            _kv('Platform', req.platform),
            _kv('App version', req.appVersion),
            _kv('Device ID', _short(req.deviceId)),
            const SizedBox(height: 12),
            const Text(
              'Approve only if you just started this on your own device.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              _approvalOpen = false;
              ctl.respondToPairing(false);
              Navigator.of(ctx).pop();
            },
            child: const Text('Reject'),
          ),
          FilledButton(
            onPressed: () {
              _approvalOpen = false;
              ctl.respondToPairing(true);
              Navigator.of(ctx).pop();
            },
            child: const Text('Approve'),
          ),
        ],
      ),
    );
    _approvalOpen = false;
  }

  Future<void> _confirmRevoke(LinkedDevice d) async {
    final ctl = ref.read(linkControllerProvider.notifier);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Revoke ${d.name}?'),
        content: const Text(
          'This device will no longer be able to sign in. Records it already '
          'synchronized stay on this computer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
    if (ok == true) await ctl.revokeDevice(d.id);
  }

  Future<void> _setRemoteControl(LinkedDevice device, bool allowed) async {
    if (allowed) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Allow ${device.name} to control scanning?'),
          content: const Text(
            'This paired Android device will be able to start, stop, pause, '
            'and resume this computer’s camera scanner. You can revoke this '
            'permission here at any time.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Allow control'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    await ref
        .read(linkControllerProvider.notifier)
        .setRemoteControlAuthorization(device.id, allowed);
  }

  Future<void> _editAddress(PeerDesktop p) async {
    final ctl = ref.read(linkControllerProvider.notifier);
    final host = TextEditingController(text: p.host);
    final port = TextEditingController(text: '${p.port}');
    String? problem;
    await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text('Address of ${p.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Use this if the desktop got a new network address. The '
                'certificate fingerprint stays pinned, so only the same '
                'desktop is accepted.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: host,
                decoration: const InputDecoration(labelText: 'IPv4 address'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: port,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Port'),
              ),
              if (problem != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    problem!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final error = await ctl.updatePeerAddress(
                  p.id,
                  host.text,
                  port.text,
                );
                if (error == null) {
                  if (dialogContext.mounted) {
                    Navigator.of(dialogContext).pop(true);
                  }
                } else {
                  setLocal(() => problem = error);
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmUnlink(PeerDesktop p) async {
    final ctl = ref.read(linkControllerProvider.notifier);
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Unlink ${p.name}?'),
        content: const Text(
          'The desktop is told to stop trusting this phone. Records on this '
          'phone are kept. If the desktop cannot be reached, use "Remove here '
          'only".',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('cancel'),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('local'),
            child: const Text('Remove here only'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop('unlink'),
            child: const Text('Unlink'),
          ),
        ],
      ),
    );
    if (choice == 'unlink') {
      await ctl.unlink(p);
    } else if (choice == 'local') {
      await ctl.removePeerLocally(p.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<LinkUiState>(linkControllerProvider, (prev, next) {
      if (prev?.pending == null && next.pending != null) {
        unawaited(_showApproval(next.pending!));
      } else if (prev?.pending != null && next.pending == null) {
        // The request timed out or was cancelled while the dialog was open.
        if (_approvalOpen && mounted) {
          _approvalOpen = false;
          Navigator.of(context, rootNavigator: true).pop();
        }
      }
    });
    final ui = ref.watch(linkControllerProvider);
    final ctl = ref.read(linkControllerProvider.notifier);

    if (!ui.ready) {
      if (ui.error != null) {
        return ExaltedErrorState(
          title: 'Linked devices are unavailable',
          message: ui.error,
          onRetry: ctl.retryInit,
        );
      }
      return const Center(child: CircularProgressIndicator());
    }

    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (ui.error != null)
                _Banner(
                  text: ui.error!,
                  error: true,
                  onClose: ctl.clearMessages,
                ),
              if (ui.notice != null)
                _Banner(
                  text: ui.notice!,
                  error: false,
                  onClose: ctl.clearMessages,
                ),
              if (_isDesktop) ..._desktop(ui, ctl) else ..._phone(ui, ctl),
              if (ui.conflicts.isNotEmpty) ...[
                const SizedBox(height: 16),
                _conflictSection(ui, ctl),
              ],
              if (ui.syncHistory.isNotEmpty) ...[
                const SizedBox(height: 16),
                _syncHistorySection(ui, ctl),
              ],
              const SizedBox(height: 16),
              Text(
                'Both devices keep their own records. Linking never replaces '
                'one device\'s data with another\'s, and it works on the local '
                'network without an account.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _conflictSection(LinkUiState ui, LinkController ctl) {
    final unresolved = ui.conflicts.where((c) => !c.resolved).toList();
    final resolved = ui.conflicts.where((c) => c.resolved).toList();
    return _Section(
      title: 'Sync conflicts',
      subtitle: unresolved.isEmpty
          ? 'All conflicts have a recorded decision.'
          : '${unresolved.length} incoming version(s) need review. Existing data is preserved.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final conflict in unresolved)
            _ConflictTile(
              conflict: conflict,
              enabled: !ui.syncing,
              onResolve: (saveIncoming) =>
                  ctl.resolveConflict(conflict, saveIncomingCopy: saveIncoming),
            ),
          if (resolved.isNotEmpty)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text('Resolved (${resolved.length})'),
              children: [
                for (final conflict in resolved)
                  ListTile(
                    dense: true,
                    title: Text(_conflictTitle(conflict)),
                    subtitle: Text(
                      conflict.resolution == 'save_incoming_copy'
                          ? 'Incoming version saved as a separate record'
                          : 'Current version kept; incoming evidence retained',
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _syncHistorySection(LinkUiState ui, LinkController ctl) {
    return _Section(
      title: 'Sync history',
      subtitle: '${ui.syncHistory.length} recorded session(s)',
      child: Column(
        children: [
          for (final session in ui.syncHistory.take(20))
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                session.succeeded
                    ? Icons.check_circle_outline
                    : Icons.error_outline,
                color: session.succeeded
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.error,
              ),
              title: Text(
                '${session.peerName} · ${session.succeeded ? 'Complete' : 'Failed'}',
              ),
              subtitle: Text(
                session.succeeded
                    ? '${_fmt(session.finishedAt)} · sent ${session.pushed}, received ${session.pulled}, conflicts ${session.conflicts}'
                    : '${_fmt(session.finishedAt)} · ${session.error ?? 'Transfer failed'}',
              ),
              trailing:
                  !session.succeeded &&
                      _peerForSession(ui.peers, session.peerId) != null
                  ? TextButton(
                      onPressed: ui.syncing
                          ? null
                          : () => ctl.syncNow(
                              _peerForSession(ui.peers, session.peerId)!,
                            ),
                      child: const Text('Retry'),
                    )
                  : null,
            ),
        ],
      ),
    );
  }

  PeerDesktop? _peerForSession(List<PeerDesktop> peers, String id) {
    for (final peer in peers) {
      if (peer.id == id) return peer;
    }
    return null;
  }

  // ------------------------------------------------------------ desktop

  List<Widget> _desktop(LinkUiState ui, LinkController ctl) {
    final running = ui.serverPort != 0;
    return [
      _Section(
        title: 'This computer',
        subtitle: ui.deviceName,
        trailing: ExaltedStatusChip(
          label: running
              ? 'Service on port ${ui.serverPort}'
              : 'Service stopped',
          kind: running ? ExaltedStatusKind.success : ExaltedStatusKind.neutral,
        ),
        child: ui.payload == null
            ? Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: ui.busy ? null : () => ctl.startPairing(),
                  icon: const Icon(Icons.qr_code_2),
                  label: const Text('Add device'),
                ),
              )
            : _QrPanel(payload: ui.payload!, onCancel: ctl.cancelPairing),
      ),
      if (ui.remoteCommands.isNotEmpty) ...[
        const SizedBox(height: 16),
        _Section(
          title: 'Remote scanner command history',
          subtitle: 'Durable acknowledgements from authorized phones',
          child: Column(
            children: [
              for (final command in ui.remoteCommands.take(12))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.manage_accounts_outlined),
                  title: Text('${command['action']} · ${command['state']}'),
                  subtitle: Text(
                    '${command['message'] ?? ''} · device ${_short(command['deviceId'] as String? ?? '')}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ),
      ],
      const SizedBox(height: 16),
      _Section(
        title: 'Linked devices',
        subtitle: 'Phones allowed to sync with this computer',
        child: ui.devices.isEmpty
            ? const ExaltedEmptyState(
                icon: Icons.phone_android,
                title: 'No linked devices yet',
                message:
                    'Choose Add device and scan the code in Exalted on '
                    'your phone.',
              )
            : Column(
                children: [
                  for (final d in ui.devices)
                    _DeviceRow(
                      device: d,
                      onRevoke: () => _confirmRevoke(d),
                      onRemoteControlChanged: (allowed) =>
                          _setRemoteControl(d, allowed),
                    ),
                ],
              ),
      ),
    ];
  }

  // -------------------------------------------------------------- phone

  List<Widget> _phone(LinkUiState ui, LinkController ctl) {
    return [
      _Section(
        title: 'Connect to a desktop',
        subtitle:
            'On the desktop open Link, choose Add device, then copy the '
            'pairing code and paste it here.',
        child: ui.preview == null
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (Platform.isAndroid) ...[
                    FilledButton.icon(
                      onPressed: _scanCode,
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text('Scan QR code'),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    controller: _code,
                    minLines: 2,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'Pairing code',
                      hintText: 'Paste the code from the desktop',
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => ctl.previewCode(_code.text),
                    child: const Text('Check code'),
                  ),
                ],
              )
            : _PreviewCard(
                payload: ui.preview!,
                busy: ui.busy,
                onCancel: () {
                  ctl.discardPreview();
                  _code.clear();
                },
                onConnect: () async {
                  await ctl.confirmPair();
                  if (ref.read(linkControllerProvider).preview == null) {
                    _code.clear();
                  }
                },
              ),
      ),
      const SizedBox(height: 16),
      _Section(
        title: 'Linked desktops',
        subtitle: 'Records stay on this phone and are copied, never replaced',
        child: ui.peers.isEmpty
            ? const ExaltedEmptyState(
                icon: Icons.desktop_windows_outlined,
                title: 'Not linked to a desktop',
                message: 'Connect to a desktop above to start syncing.',
              )
            : Column(
                children: [
                  for (final p in ui.peers)
                    _PeerRow(
                      peer: p,
                      syncing: ui.syncing,
                      progress: ui.progress,
                      onSync: () => ctl.syncNow(p),
                      onUnlink: () => _confirmUnlink(p),
                      onEditAddress: () => _editAddress(p),
                      pending: ctl.pendingFor(p),
                    ),
                  if (ui.summary != null) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Last result: sent ${ui.summary!.pushed}, received '
                        '${ui.summary!.pulled}, already present '
                        '${ui.summary!.duplicates}, conflicts '
                        '${ui.summary!.conflicts}.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ],
              ),
      ),
    ];
  }
}

String _conflictTitle(SyncConflictCase conflict) =>
    '${conflict.incoming.kind.name.toUpperCase()} · ${conflict.incoming.id}';

String _conflictSummary(SyncRecord record) {
  final value = switch (record.kind) {
    SyncKind.decoder => record.payload['text'] ?? record.payload['raw'],
    SyncKind.ocr => record.payload['text'] ?? record.payload['rawText'],
    SyncKind.inspection => record.payload['raw'] ?? record.payload['text'],
    SyncKind.image => 'Image attachment',
  };
  final text = value?.toString().trim() ?? '(No text value)';
  return text.length > 140 ? '${text.substring(0, 137)}…' : text;
}

class _ConflictTile extends StatelessWidget {
  const _ConflictTile({
    required this.conflict,
    required this.enabled,
    required this.onResolve,
  });

  final SyncConflictCase conflict;
  final bool enabled;
  final Future<void> Function(bool saveIncomingCopy) onResolve;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_conflictTitle(conflict), style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Text('Current · ${_conflictSummary(conflict.current)}'),
            const SizedBox(height: 4),
            Text('Incoming · ${_conflictSummary(conflict.incoming)}'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                OutlinedButton(
                  onPressed: enabled ? () => onResolve(false) : null,
                  child: const Text('Keep current'),
                ),
                FilledButton.tonal(
                  onPressed: enabled ? () => onResolve(true) : null,
                  child: const Text('Save incoming copy'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Widget _kv(String k, String v) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 2),
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(width: 96, child: Text(k)),
      Expanded(child: SelectableText(v)),
    ],
  ),
);

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.exalted;
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            subtitle!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.muted,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.text,
    required this.error,
    required this.onClose,
  });

  final String text;
  final bool error;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = error ? scheme.error : scheme.primary;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(
            error ? Icons.error_outline : Icons.check_circle_outline,
            color: color,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(child: SelectableText(text)),
          IconButton(
            tooltip: 'Dismiss',
            onPressed: onClose,
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    );
  }
}

class _QrPanel extends StatefulWidget {
  const _QrPanel({required this.payload, required this.onCancel});

  final PairingPayload payload;
  final VoidCallback onCancel;

  @override
  State<_QrPanel> createState() => _QrPanelState();
}

class _QrPanelState extends State<_QrPanel> {
  @override
  void initState() {
    super.initState();
    // No polling: the expiry time is read once at build. The QR code either
    // works or it doesn't; refreshing every second causes needless rebuilds.
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.payload;
    final left = p.expiresAt.difference(DateTime.now());
    final expired = left.isNegative;
    final mm = left.inMinutes.toString().padLeft(1, '0');
    final ss = (left.inSeconds % 60).toString().padLeft(2, '0');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            padding: const EdgeInsets.all(12),
            color: Colors.white,
            child: expired
                ? const SizedBox(
                    width: 220,
                    height: 220,
                    child: Center(
                      child: Text(
                        'Code expired',
                        style: TextStyle(color: Colors.black),
                      ),
                    ),
                  )
                : QrImageView(
                    data: p.encode(),
                    size: 220,
                    backgroundColor: Colors.white,
                  ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          expired
              ? 'This code has expired.'
              : 'Expires in $mm:$ss. Works once.',
        ),
        const SizedBox(height: 4),
        _kv('Fingerprint', _fp(p.fingerprint)),
        _kv('Address', '${p.hosts.join(', ')}  port ${p.port}'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: expired
                  ? null
                  : () async {
                      await Clipboard.setData(ClipboardData(text: p.encode()));
                      if (!context.mounted) return;
                      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Pairing code copied. It works once and expires soon.',
                          ),
                        ),
                      );
                    },
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('Copy pairing code'),
            ),
            TextButton(
              onPressed: widget.onCancel,
              child: Text(expired ? 'Close' : 'Cancel'),
            ),
          ],
        ),
      ],
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({
    required this.payload,
    required this.busy,
    required this.onCancel,
    required this.onConnect,
  });

  final PairingPayload payload;
  final bool busy;
  final VoidCallback onCancel;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Connect to this desktop?'),
        const SizedBox(height: 8),
        _kv('Name', payload.desktopName),
        _kv('Address', '${payload.hosts.join(', ')}  port ${payload.port}'),
        _kv('Fingerprint', _fp(payload.fingerprint)),
        const SizedBox(height: 8),
        const Text(
          'Check that the fingerprint matches the one shown on the desktop.',
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            FilledButton(
              onPressed: busy ? null : onConnect,
              child: Text(busy ? 'Waiting for the desktop…' : 'Connect'),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: busy ? null : onCancel,
              child: const Text('Cancel'),
            ),
          ],
        ),
        if (busy)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('The desktop owner has to approve this device.'),
          ),
      ],
    );
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({
    required this.device,
    required this.onRevoke,
    required this.onRemoteControlChanged,
  });

  final LinkedDevice device;
  final VoidCallback onRevoke;
  final ValueChanged<bool> onRemoteControlChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.exalted;
    final isLinked = !device.revoked;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isLinked
                    ? colors.valid.withValues(alpha: 0.10)
                    : colors.outline.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.phone_android,
                size: 24,
                color: isLinked ? colors.valid : colors.muted,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          device.name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      ExaltedStatusChip(
                        label: isLinked ? 'Linked' : 'Revoked',
                        kind: isLinked
                            ? ExaltedStatusKind.success
                            : ExaltedStatusKind.error,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    device.platform,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.muted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Linked ${_fmt(device.pairedAt)} · '
                    'last seen ${_fmt(device.lastSeen)} · '
                    'last sync ${_fmt(device.lastSync)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (isLinked) ...[
              if (device.platform == 'android')
                Tooltip(
                  message: 'Allow this phone to control the desktop scanner',
                  child: Switch.adaptive(
                    value: device.remoteControlAuthorized,
                    onChanged: onRemoteControlChanged,
                  ),
                ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Revoke access',
                onPressed: onRevoke,
                icon: Icon(Icons.link_off, size: 20, color: colors.muted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PeerRow extends StatelessWidget {
  const _PeerRow({
    required this.peer,
    required this.syncing,
    required this.progress,
    required this.onSync,
    required this.onUnlink,
    required this.onEditAddress,
    required this.pending,
  });

  final PeerDesktop peer;
  final bool syncing;
  final SyncProgress? progress;
  final VoidCallback onSync;
  final VoidCallback onUnlink;
  final VoidCallback onEditAddress;
  final int pending;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.exalted;
    final p = progress;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colors.aqua.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.desktop_windows_outlined,
                    size: 24,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Text(
                              peer.name,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: theme.colorScheme.onSurface,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          ExaltedStatusChip(
                            label: syncing ? 'Syncing' : 'Online',
                            kind: syncing
                                ? ExaltedStatusKind.info
                                : ExaltedStatusKind.success,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${peer.host}:${peer.port}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.muted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.access_time,
                            size: 14,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Last sync ${_fmt(peer.lastSync)}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: 12),
                          if (pending > 0) ...[
                            Icon(
                              Icons.pending_actions,
                              size: 14,
                              color: colors.warning,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '$pending waiting',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colors.warning,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    FilledButton.tonal(
                      onPressed: syncing ? null : onSync,
                      style: FilledButton.styleFrom(
                        foregroundColor: colors.valid,
                      ),
                      child: Text(syncing ? 'Syncing…' : 'Sync now'),
                    ),
                    const SizedBox(height: 8),
                    IconButton(
                      tooltip: 'Change address',
                      onPressed: syncing ? null : onEditAddress,
                      icon: Icon(
                        Icons.edit_location_alt_outlined,
                        size: 20,
                        color: colors.muted,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Unlink',
                      onPressed: syncing ? null : onUnlink,
                      icon: Icon(Icons.link_off, size: 20, color: colors.muted),
                    ),
                  ],
                ),
              ],
            ),
            if (syncing) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: (p != null && p.total > 0) ? p.done / p.total : null,
                backgroundColor: colors.outline.withValues(alpha: 0.30),
                valueColor: AlwaysStoppedAnimation<Color>(colors.valid),
              ),
              if (p != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    p.total > 0
                        ? '${p.phase}: ${p.done} of ${p.total}'
                        : '${p.phase}: ${p.done} item(s) processed',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
