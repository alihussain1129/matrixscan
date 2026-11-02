import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/exalted_button.dart';
import 'keyence_ftp_receiver.dart';
import 'keyence_sr751_client.dart';
import 'sr751_inspection_pipeline.dart';

/// Industrial control and monitoring workspace for KEYENCE SR-751 series
/// 2D code readers and connected machine-vision inspection.
class KeyenceDeviceScreen extends ConsumerStatefulWidget {
  const KeyenceDeviceScreen({super.key});

  @override
  ConsumerState<KeyenceDeviceScreen> createState() =>
      _KeyenceDeviceScreenState();
}

class _KeyenceDeviceScreenState extends ConsumerState<KeyenceDeviceScreen> {
  final TextEditingController _hostController =
      TextEditingController(text: '192.168.100.100');
  final TextEditingController _portController =
      TextEditingController(text: '9004');
  final TextEditingController _ftpPortController =
      TextEditingController(text: '2121');
  final TextEditingController _ocvPatternController =
      TextEditingController(text: r'LOT-[A-Z0-9]+');

  bool _isConnecting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startFtpServer();
    });
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _ftpPortController.dispose();
    _ocvPatternController.dispose();
    super.dispose();
  }

  Future<void> _startFtpServer() async {
    final ftp = ref.read(keyenceFtpReceiverProvider);
    if (!ftp.isRunning) {
      final port = int.tryParse(_ftpPortController.text) ?? 2121;
      await ftp.start(listenPort: port);
    }
  }

  Future<void> _toggleConnection() async {
    final client = ref.read(keyenceSr751ClientProvider);
    if (client.status == KeyenceConnectionStatus.connected) {
      await client.disconnect();
      setState(() {});
    } else {
      setState(() => _isConnecting = true);
      final host = _hostController.text.trim();
      final port = int.tryParse(_portController.text.trim()) ?? 9004;

      final success = await client.connect(targetHost: host, targetPort: port);
      if (mounted) {
        setState(() => _isConnecting = false);
        if (!success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Could not connect to Keyence reader at $host:$port. '
                'Check network cables and IP configuration.',
              ),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    }
  }

  Widget _buildStatusChip(KeyenceConnectionStatus status) {
    Color bg;
    Color fg;
    String label;

    switch (status) {
      case KeyenceConnectionStatus.connected:
        bg = const Color(0xFF22C55E).withAlpha(30);
        fg = const Color(0xFF22C55E);
        label = 'ONLINE / READY';
        break;
      case KeyenceConnectionStatus.connecting:
        bg = Colors.amber.withAlpha(30);
        fg = Colors.amber;
        label = 'CONNECTING...';
        break;
      case KeyenceConnectionStatus.error:
        bg = Colors.red.withAlpha(30);
        fg = Colors.red;
        label = 'CONNECTION ERROR';
        break;
      case KeyenceConnectionStatus.disconnected:
      default:
        bg = Colors.grey.withAlpha(30);
        fg = Colors.grey;
        label = 'DISCONNECTED';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: fg.withAlpha(80)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<ExaltedColors>()!;
    final text = theme.textTheme;

    final client = ref.watch(keyenceSr751ClientProvider);
    final pipeline = ref.watch(sr751InspectionPipelineProvider);
    final ftp = ref.watch(keyenceFtpReceiverProvider);

    final isConnected = client.status == KeyenceConnectionStatus.connected;

    return ListenableBuilder(
      listenable: pipeline,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                const Icon(Icons.router_outlined, size: 24),
                const SizedBox(width: 8),
                Text('KEYENCE SR-751 Industrial Vision', style: text.titleMedium),
                const SizedBox(width: 12),
                _buildStatusChip(client.status),
              ],
            ),
            actions: [
              if (pipeline.inspections.isNotEmpty)
                IconButton(
                  tooltip: 'Clear Inspections',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => pipeline.clearInspections(),
                ),
            ],
          ),
          body: Row(
            children: [
              // ---- Left Side: Device Configuration & Controls -----------------
              Container(
                width: 320,
                decoration: BoxDecoration(
                  color: colors.surfaceRaised,
                  border: Border(right: BorderSide(color: colors.outline)),
                ),
                child: ListView(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  children: [
                    Text(
                      'COMMUNICATION CONFIG',
                      style: text.labelSmall!.copyWith(
                        color: colors.muted,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TextField(
                      controller: _hostController,
                      decoration: const InputDecoration(
                        labelText: 'Reader IPv4 Address',
                        prefixIcon: Icon(Icons.lan_outlined),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _portController,
                            decoration: const InputDecoration(
                              labelText: 'TCP Port',
                              isDense: true,
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: TextField(
                            controller: _ftpPortController,
                            decoration: const InputDecoration(
                              labelText: 'FTP Port',
                              isDense: true,
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    ExaltedButton(
                      label: isConnected ? 'Disconnect Reader' : 'Connect Reader',
                      outlined: isConnected,
                      expand: true,
                      onPressed: _isConnecting ? null : _toggleConnection,
                    ),

                    const Divider(height: 32),

                    Text(
                      'TRIGGER CONTROLS',
                      style: text.labelSmall!.copyWith(
                        color: colors.muted,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.play_arrow, size: 18),
                            label: const Text('LON (Read)'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: theme.colorScheme.primary,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: isConnected
                                ? () => pipeline.triggerInspection()
                                : null,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: OutlinedButton(
                            child: const Text('LOFF (Stop)'),
                            onPressed:
                                isConnected ? () => client.stopRead() : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            child: const Text('Trigger T1'),
                            onPressed:
                                isConnected ? () => client.triggerT1() : null,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: OutlinedButton(
                            child: const Text('Pull CMOS Frame'),
                            onPressed:
                                isConnected ? () => client.requestFtpImage() : null,
                          ),
                        ),
                      ],
                    ),

                    const Divider(height: 32),

                    Text(
                      'OCV INSPECTION VERIFICATION',
                      style: text.labelSmall!.copyWith(
                        color: colors.muted,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Auto OCR CMOS Frames', style: TextStyle(fontSize: 14)),
                      subtitle: const Text('Extract text from Keyence camera images', style: TextStyle(fontSize: 12)),
                      value: pipeline.autoOcr,
                      onChanged: (v) => pipeline.autoOcr = v,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    TextField(
                      controller: _ocvPatternController,
                      decoration: const InputDecoration(
                        labelText: 'Expected OCV Pattern (Regex)',
                        hintText: 'e.g. LOT-[0-9]{6}',
                        prefixIcon: Icon(Icons.verified_outlined),
                        isDense: true,
                      ),
                      onChanged: (v) => pipeline.expectedOcvPattern = v,
                    ),

                    const SizedBox(height: AppSpacing.lg),
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: colors.surfaceRaised,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: colors.outline),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            ftp.isRunning ? Icons.check_circle : Icons.warning_amber,
                            color: ftp.isRunning ? const Color(0xFF22C55E) : Colors.amber,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              ftp.isRunning
                                  ? 'Embedded FTP Receiver active on port ${ftp.boundPort}'
                                  : 'FTP Receiver offline',
                              style: text.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // ---- Right Side: Inspection Stream & Image Feed -----------------
              Expanded(
                child: pipeline.inspections.isEmpty
                    ? const EmptyState(
                        icon: Icons.precision_manufacturing_outlined,
                        title: 'Keyence Machine Vision Standby',
                        message:
                            'Connect to the Keyence SR-751 reader via TCP/IP and trigger reads. '
                            'Decoded 2D codes, captured CMOS frames, and OCR results will appear here in real-time.',
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        itemCount: pipeline.inspections.length,
                        itemBuilder: (context, index) {
                          final item = pipeline.inspections[index];
                          return _buildInspectionCard(item, theme, colors, text);
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInspectionCard(
    IndustrialInspectionRecord item,
    ThemeData theme,
    ExaltedColors colors,
    TextTheme text,
  ) {
    Color statusColor;
    String statusLabel;
    IconData statusIcon;

    switch (item.status) {
      case InspectionStatus.pass:
        statusColor = const Color(0xFF22C55E);
        statusLabel = 'PASS';
        statusIcon = Icons.check_circle_outline;
        break;
      case InspectionStatus.fail:
        statusColor = Colors.red;
        statusLabel = 'FAIL';
        statusIcon = Icons.cancel_outlined;
        break;
      case InspectionStatus.noRead:
        statusColor = Colors.orange;
        statusLabel = 'NO READ';
        statusIcon = Icons.error_outline;
        break;
      default:
        statusColor = Colors.blue;
        statusLabel = 'PROCESSING';
        statusIcon = Icons.hourglass_top;
        break;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: statusColor.withAlpha(120), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image Preview
            if (item.imagePath != null && item.imagePath!.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.file(
                  File(item.imagePath!),
                  width: 140,
                  height: 105,
                  fit: BoxFit.cover,
                  errorBuilder: (ctx, _, __) => Container(
                    width: 140,
                    height: 105,
                    color: Colors.grey.withAlpha(40),
                    child: const Icon(Icons.broken_image),
                  ),
                ),
              )
            else
              Container(
                width: 140,
                height: 105,
                decoration: BoxDecoration(
                  color: colors.surfaceRaised,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: colors.outline),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.camera_alt_outlined, color: colors.muted),
                    const SizedBox(height: 4),
                    Text('No CMOS Frame', style: text.labelSmall),
                  ],
                ),
              ),

            const SizedBox(width: AppSpacing.md),

            // Inspection Information
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: statusColor.withAlpha(25),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: statusColor),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(statusIcon, color: statusColor, size: 14),
                            const SizedBox(width: 4),
                            Text(
                              statusLabel,
                              style: TextStyle(
                                color: statusColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Time: ${item.timestamp.toIso8601String().substring(11, 19)}',
                        style: text.bodySmall!.copyWith(color: colors.muted),
                      ),
                      const Spacer(),
                      if (item.processingTimeMs > 0)
                        Text(
                          '${item.processingTimeMs} ms',
                          style: text.bodySmall!.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colors.muted,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),

                  if (item.barcode != null) ...[
                    Text(
                      'DECODED CODE:',
                      style: text.labelSmall!.copyWith(
                        color: colors.muted,
                        letterSpacing: 0.5,
                      ),
                    ),
                    SelectableText(
                      item.barcode!,
                      style: text.titleMedium!.copyWith(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],

                  if (item.ocrText != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'EXTRACTED OCR TEXT:',
                      style: text.labelSmall!.copyWith(
                        color: colors.muted,
                        letterSpacing: 0.5,
                      ),
                    ),
                    SelectableText(
                      item.ocrText!,
                      style: text.bodyMedium!.copyWith(
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],

                  if (item.ocvPassed != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      item.ocvPassed!
                          ? 'OCV Verification: Pattern Matched (${item.ocvPattern})'
                          : 'OCV Verification: FAILED (Expected: ${item.ocvPattern})',
                      style: text.bodySmall!.copyWith(
                        color: item.ocvPassed! ? const Color(0xFF22C55E) : Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
