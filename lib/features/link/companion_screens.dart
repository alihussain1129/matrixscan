import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../devices/keyence/keyence_device_screen.dart';
import '../diagnostics/diagnostics_screen.dart';
import '../ocr/views/ocr_workspace_screen.dart';
import '../../verify/verification_screen.dart';
import '../../core/router/app_router.dart';
import '../../core/widgets/exalted_status_chip.dart';
import 'link_models.dart';
import 'link_providers.dart';
import 'linked_devices_screen.dart';

class CompanionDashboardScreen extends ConsumerWidget {
  const CompanionDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(linkControllerProvider);
    final controller = ref.read(linkControllerProvider.notifier);
    final colors = Theme.of(context).colorScheme;
    final snapshot = state.companionSnapshot;
    PeerDesktop? peer;
    for (final candidate in state.peers) {
      if (candidate.id == state.companionPeerId) peer = candidate;
    }
    peer ??= state.peers.isEmpty ? null : state.peers.first;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Companion overview'),
        actions: [
          PopupMenuButton<int>(
            tooltip: 'More tools',
            onSelected: (index) => _openMobileTool(context, index),
            itemBuilder: (context) => const [
              PopupMenuItem(value: kOcrTab, child: Text('Decode & OCR')),
              PopupMenuItem(
                value: kVerificationTab,
                child: Text('Verification'),
              ),
              PopupMenuItem(value: kInspectionTab, child: Text('Inspection')),
              PopupMenuItem(value: kDiagnosticsTab, child: Text('Diagnostics')),
            ],
          ),
          IconButton(
            tooltip: 'Refresh desktop status',
            onPressed: state.ready
                ? () async {
                    await controller.sweepLocalRecords();
                    await controller.refreshCompanion();
                  }
                : null,
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => ref.read(navIndexProvider.notifier).set(kScanTab),
        icon: const Icon(Icons.qr_code_scanner),
        label: const Text('Scan on phone'),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            await controller.sweepLocalRecords();
            await controller.refreshCompanion();
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            children: [
              Text(
                'Quick tools',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _QuickTool(
                    label: 'Scanner',
                    icon: Icons.qr_code_scanner,
                    destination: kScanTab,
                  ),
                  _QuickTool(
                    label: 'Decode & OCR',
                    icon: Icons.document_scanner_outlined,
                    destination: kOcrTab,
                  ),
                  _QuickTool(
                    label: 'Inspection',
                    icon: Icons.fact_check_outlined,
                    destination: kInspectionTab,
                  ),
                  _QuickTool(
                    label: 'Verification',
                    icon: Icons.verified_outlined,
                    destination: kVerificationTab,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (!state.ready)
                const _LoadingPanel()
              else if (state.peers.isEmpty)
                _NoDesktopPanel(
                  onConnect: () =>
                      ref.read(navIndexProvider.notifier).set(kDevicesTab),
                )
              else ...[
                if (state.peers.length > 1) ...[
                  DropdownButtonFormField<String>(
                    key: ValueKey(state.companionPeerId),
                    initialValue: peer?.id,
                    decoration: const InputDecoration(
                      labelText: 'Desktop',
                      prefixIcon: Icon(Icons.desktop_windows_outlined),
                    ),
                    items: [
                      for (final item in state.peers)
                        DropdownMenuItem(
                          value: item.id,
                          child: Text(item.name),
                        ),
                    ],
                    onChanged: (id) {
                      if (id != null) controller.selectCompanionPeer(id);
                    },
                  ),
                  const SizedBox(height: 12),
                ],
                _ConnectionPanel(
                  name: snapshot?.name ?? peer?.name ?? 'Paired desktop',
                  platform: snapshot?.platform,
                  connected: state.companionConnected,
                  streaming: state.companionStreaming,
                  error: state.companionError,
                  heartbeat: state.companionHeartbeat,
                  latencyMs: state.companionLatencyMs,
                  color: colors.primary,
                ),
                const SizedBox(height: 20),
                Text('Today', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 10),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final width = (constraints.maxWidth - 12) / 2;
                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _Metric(
                          width: width,
                          label: 'Desktop scans',
                          value: '${snapshot?.todayScans ?? '—'}',
                          icon: Icons.qr_code_2,
                        ),
                        _Metric(
                          width: width,
                          label: 'OCR runs',
                          value: '${snapshot?.todayOcr ?? '—'}',
                          icon: Icons.document_scanner_outlined,
                        ),
                        _Metric(
                          width: width,
                          label: 'Inspections',
                          value: '${snapshot?.todayInspections ?? '—'}',
                          icon: Icons.fact_check_outlined,
                        ),
                        _Metric(
                          width: width,
                          label: 'Passed / failed',
                          value: snapshot == null
                              ? '—'
                              : '${snapshot.passedInspections} / ${snapshot.failedInspections}',
                          icon: Icons.verified_outlined,
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 20),
                _SyncPanel(
                  syncing: state.syncing,
                  pending: peer == null ? 0 : controller.pendingFor(peer),
                  linkedDevices: snapshot?.activeLinkedDevices,
                  onSync: peer == null || state.syncing
                      ? null
                      : () => controller.syncNow(peer!),
                ),
                const SizedBox(height: 20),
                _HardwarePanel(hardware: snapshot?.hardware),
                const SizedBox(height: 12),
                _RemoteScannerPanel(
                  peer: peer,
                  connected: state.companionConnected,
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Recent desktop activity',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    TextButton(
                      onPressed: () =>
                          ref.read(navIndexProvider.notifier).set(kLinkTab),
                      child: const Text('View all'),
                    ),
                  ],
                ),
                if (snapshot == null || snapshot.events.isEmpty)
                  const _InlineMessage(
                    icon: Icons.inbox_outlined,
                    text: 'No desktop activity has arrived yet.',
                  )
                else
                  for (final event in snapshot.events.take(5))
                    _ActivityTile(
                      event: event,
                      source: _eventSource(event, snapshot, state.deviceId),
                    ),
                if (!state.companionConnected &&
                    state.companionHeartbeat != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      'Showing the last successful snapshot. It may be out of date.',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: colors.onSurfaceVariant),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickTool extends ConsumerWidget {
  const _QuickTool({
    required this.label,
    required this.icon,
    required this.destination,
  });

  final String label;
  final IconData icon;
  final int destination;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ActionChip(
    avatar: Icon(icon, size: 18),
    label: Text(label),
    onPressed: () => ref.read(navIndexProvider.notifier).set(destination),
  );
}

class _RemoteScannerPanel extends ConsumerStatefulWidget {
  const _RemoteScannerPanel({required this.peer, required this.connected});

  final PeerDesktop? peer;
  final bool connected;

  @override
  ConsumerState<_RemoteScannerPanel> createState() =>
      _RemoteScannerPanelState();
}

class _RemoteScannerPanelState extends ConsumerState<_RemoteScannerPanel> {
  String? _pending;

  Future<void> _send(String action) async {
    final peer = widget.peer;
    if (peer == null || !widget.connected || _pending != null) return;
    final okay = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          '${action[0].toUpperCase()}${action.substring(1)} desktop scan?',
        ),
        content: Text(
          'Send this command to ${peer.name}? The desktop must have granted this phone scanner access.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (okay != true || !mounted) return;
    setState(() => _pending = action);
    try {
      final result = await ref
          .read(linkControllerProvider.notifier)
          .issueRemoteScannerCommand(peer, action);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(result.message)));
      }
    } catch (error) {
      if (mounted) {
        final message = error is LinkException
            ? error.message
            : 'The desktop did not confirm the command.';
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _pending = null);
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Desktop scanner controls',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Commands require desktop owner authorization and a live connection.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final action in const ['start', 'stop', 'pause', 'resume'])
                OutlinedButton.icon(
                  onPressed: widget.connected && _pending == null
                      ? () => _send(action)
                      : null,
                  icon: _pending == action
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(switch (action) {
                          'start' => Icons.play_arrow,
                          'stop' => Icons.stop,
                          'pause' => Icons.pause,
                          _ => Icons.play_circle_outline,
                        }),
                  label: Text(action[0].toUpperCase() + action.substring(1)),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}

class CompanionActivityScreen extends ConsumerStatefulWidget {
  const CompanionActivityScreen({super.key});

  @override
  ConsumerState<CompanionActivityScreen> createState() =>
      _CompanionActivityScreenState();
}

class MobileDevicesScreen extends StatefulWidget {
  const MobileDevicesScreen({super.key});

  @override
  State<MobileDevicesScreen> createState() => _MobileDevicesScreenState();
}

class _MobileDevicesScreenState extends State<MobileDevicesScreen> {
  int _selected = 0;
  bool _keyenceVisited = false;

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Devices'),
        bottom: TabBar(
          onTap: (index) => setState(() {
            _selected = index;
            if (index == 1) _keyenceVisited = true;
          }),
          tabs: const [
            Tab(text: 'Connections'),
            Tab(text: 'KEYENCE'),
          ],
        ),
      ),
      body: IndexedStack(
        index: _selected,
        children: [
          const LinkedDevicesScreen(),
          _keyenceVisited
              ? const KeyenceDeviceScreen()
              : const SizedBox.shrink(),
        ],
      ),
    ),
  );
}

class _CompanionActivityScreenState
    extends ConsumerState<CompanionActivityScreen> {
  String _filter = 'all';

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(linkControllerProvider);
    final snapshot = state.companionSnapshot;
    final events = snapshot?.events
        .where((event) {
          return switch (_filter) {
            'scan' => event.type == 'decoder',
            'ocr' => event.type == 'ocr',
            'inspection' => event.type == 'inspection',
            _ => true,
          };
        })
        .toList(growable: false);

    return Scaffold(
      appBar: AppBar(title: const Text('Live activity')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 'all', label: Text('All')),
                    ButtonSegment(value: 'scan', label: Text('Scans')),
                    ButtonSegment(value: 'ocr', label: Text('OCR')),
                    ButtonSegment(
                      value: 'inspection',
                      label: Text('Inspections'),
                    ),
                  ],
                  selected: {_filter},
                  onSelectionChanged: (value) =>
                      setState(() => _filter = value.first),
                ),
              ),
            ),
            Expanded(
              child: events == null
                  ? const _InlineMessage(
                      icon: Icons.cloud_off_outlined,
                      text: 'Pair a desktop to receive its activity feed.',
                    )
                  : events.isEmpty
                  ? const _InlineMessage(
                      icon: Icons.inbox_outlined,
                      text: 'No events match this filter.',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemCount: events.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) => _ActivityTile(
                        event: events[index],
                        source: _eventSource(
                          events[index],
                          snapshot,
                          state.deviceId,
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectionPanel extends StatelessWidget {
  const _ConnectionPanel({
    required this.name,
    required this.platform,
    required this.connected,
    required this.streaming,
    required this.error,
    required this.heartbeat,
    required this.latencyMs,
    required this.color,
  });

  final String name;
  final String? platform;
  final bool connected;
  final bool streaming;
  final String? error;
  final DateTime? heartbeat;
  final int? latencyMs;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = connected
        ? '${_platformName(platform)} · ${latencyMs ?? '—'} ms · heartbeat ${_time(heartbeat)} · ${streaming ? 'live events' : 'polling fallback'}'
        : error ?? 'Waiting for an authenticated desktop heartbeat';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.desktop_windows_outlined, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            ExaltedStatusChip(
              label: connected
                  ? 'Live'
                  : heartbeat == null
                  ? 'Offline'
                  : 'Stale',
              kind: connected
                  ? ExaltedStatusKind.success
                  : heartbeat == null
                  ? ExaltedStatusKind.neutral
                  : ExaltedStatusKind.warning,
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.width,
    required this.label,
    required this.value,
    required this.icon,
  });

  final double width;
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: width,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: theme.colorScheme.primary),
              const SizedBox(height: 10),
              Text(value, style: theme.textTheme.headlineSmall),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SyncPanel extends StatelessWidget {
  const _SyncPanel({
    required this.syncing,
    required this.pending,
    required this.linkedDevices,
    required this.onSync,
  });

  final bool syncing;
  final int pending;
  final int? linkedDevices;
  final VoidCallback? onSync;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(
              syncing ? Icons.sync : Icons.sync_alt,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    syncing ? 'Syncing' : 'Synchronization',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    linkedDevices == null
                        ? '$pending record(s) waiting on this phone'
                        : '$pending record(s) waiting · $linkedDevices linked device(s) recently active',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: onSync,
              child: const Text('Sync now'),
            ),
          ],
        ),
      ),
    );
  }
}

class _HardwarePanel extends StatelessWidget {
  const _HardwarePanel({required this.hardware});

  final Map<String, Object?>? hardware;

  @override
  Widget build(BuildContext context) {
    final available = hardware?['available'] == true;
    final keyence = hardware?['keyence'];
    final camera = hardware?['camera'];
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Desktop hardware',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            if (keyence is Map)
              _HardwareLine(
                label: '${keyence['model'] ?? 'KEYENCE'}',
                status: keyence['status'] as String? ?? 'unknown',
              ),
            if (camera is Map)
              _HardwareLine(
                label: 'Camera',
                status: camera['status'] as String? ?? 'unknown',
              ),
            if (!available)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'The desktop has not exposed live hardware telemetry yet.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _HardwareLine extends StatelessWidget {
  const _HardwareLine({required this.label, required this.status});

  final String label;
  final String status;

  @override
  Widget build(BuildContext context) {
    final normalized = status.toLowerCase();
    final kind = switch (normalized) {
      'connected' || 'ready' => ExaltedStatusKind.success,
      'connecting' || 'starting' => ExaltedStatusKind.info,
      'error' ||
      'disconnected' ||
      'permissiondenied' => ExaltedStatusKind.warning,
      _ => ExaltedStatusKind.neutral,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          ExaltedStatusChip(label: status, kind: kind),
        ],
      ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({required this.event, required this.source});

  final CompanionActivityEvent event;
  final String source;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon = switch (event.type) {
      'decoder' => Icons.qr_code_2,
      'ocr' => Icons.document_scanner_outlined,
      'inspection' => Icons.fact_check_outlined,
      _ => Icons.image_outlined,
    };
    final statusKind = switch (event.status) {
      'pass' || 'success' => ExaltedStatusKind.success,
      'fail' => ExaltedStatusKind.error,
      'review' => ExaltedStatusKind.warning,
      _ => null,
    };
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.1),
        child: Icon(icon, color: theme.colorScheme.primary, size: 20),
      ),
      title: Text(event.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${event.detail}\n$source · ${_time(event.createdAt)}',
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: true,
      trailing: statusKind == null
          ? null
          : ExaltedStatusChip(label: event.status!, kind: statusKind),
    );
  }
}

class _NoDesktopPanel extends StatelessWidget {
  const _NoDesktopPanel({required this.onConnect});

  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.desktop_windows_outlined,
            size: 48,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            'Connect a desktop',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          const Text(
            'Pair this phone with Exalted Desktop to see live status, scans, and inspection activity here.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: onConnect,
            icon: const Icon(Icons.link),
            label: const Text('Link desktop'),
          ),
        ],
      ),
    ),
  );
}

class _LoadingPanel extends StatelessWidget {
  const _LoadingPanel();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.only(top: 80),
    child: Center(child: CircularProgressIndicator()),
  );
}

class _InlineMessage extends StatelessWidget {
  const _InlineMessage({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(height: 8),
        Text(text, textAlign: TextAlign.center),
      ],
    ),
  );
}

String _platformName(String? platform) => switch (platform) {
  'linux' => 'Linux desktop',
  'windows' => 'Windows desktop',
  'macos' => 'macOS desktop',
  _ => 'Desktop',
};

String _eventSource(
  CompanionActivityEvent event,
  CompanionSnapshot? snapshot,
  String localDeviceId,
) {
  if (event.sourceDeviceId == localDeviceId && localDeviceId.isNotEmpty) {
    return 'This phone';
  }
  return event.sourceDeviceName ??
      (event.sourceDeviceId == snapshot?.deviceId
          ? snapshot?.name ?? 'Desktop'
          : 'Linked device');
}

String _time(DateTime? value) {
  if (value == null) return 'waiting';
  final local = value.toLocal();
  final hour = (local.hour % 12 == 0 ? 12 : local.hour % 12).toString().padLeft(
    2,
    '0',
  );
  final minute = local.minute.toString().padLeft(2, '0');
  final period = local.hour < 12 ? 'AM' : 'PM';
  return '$hour:$minute $period';
}

void _openMobileTool(BuildContext context, int index) {
  final screen = switch (index) {
    kOcrTab => const OcrWorkspaceScreen(),
    kVerificationTab => const VerificationScreen(),
    _ => const DiagnosticsScreen(),
  };
  Navigator.of(context)
      .push<void>(MaterialPageRoute<void>(builder: (_) => screen));
}
