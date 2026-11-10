import 'dart:async';
import 'dart:io';

import 'keyence_ftp_receiver.dart';
import 'keyence_sr751_client.dart';

/// Single check result in the commissioning report.
class CommissioningStep {
  const CommissioningStep({
    required this.name,
    required this.passed,
    required this.details,
    this.remediation,
  });

  final String name;
  final bool passed;
  final String details;
  final String? remediation;
}

/// Comprehensive report on scanner readiness and network compatibility.
class CommissioningReport {
  const CommissioningReport({
    required this.overallReady,
    required this.targetHost,
    required this.targetPort,
    this.detectedModel,
    this.detectedFirmware,
    this.detectedSerial,
    required this.steps,
    required this.recommendations,
    required this.measuredLatencyMs,
  });

  final bool overallReady;
  final String targetHost;
  final int targetPort;
  final String? detectedModel;
  final String? detectedFirmware;
  final String? detectedSerial;
  final List<CommissioningStep> steps;
  final List<String> recommendations;
  final int measuredLatencyMs;

  @override
  String toString() =>
      'CommissioningReport(ready: $overallReady, model: $detectedModel, steps: ${steps.length})';
}

/// Automated readiness assessment and commissioning assistant for KEYENCE SR-751.
///
/// Assesses reachability, subnet compatibility, TCP socket availability,
/// command channel responsiveness, barcode trigger readiness, and FTP service.
///
/// Safety Rule: Never silently modifies an industrial scanner's persistent
/// settings; generates non-destructive diagnostic reports and clear guidance.
class KeyenceCommissioningService {
  const KeyenceCommissioningService();

  /// Runs complete non-destructive readiness assessment.
  Future<CommissioningReport> runReadinessAssessment({
    required String host,
    int port = 9004,
    KeyenceSr751Client? existingClient,
    KeyenceFtpReceiver? ftpReceiver,
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final sw = Stopwatch()..start();
    final steps = <CommissioningStep>[];
    final recommendations = <String>[];

    String? model;
    String? fw;
    String? sn;

    // 1. Socket Reachability & Port availability
    Socket? probeSocket;
    var socketOpen = false;
    try {
      probeSocket = await Socket.connect(host, port, timeout: timeout);
      socketOpen = true;
      steps.add(
        CommissioningStep(
          name: 'TCP Socket Availability',
          passed: true,
          details: 'Successfully opened TCP stream to $host:$port',
        ),
      );
    } catch (e) {
      steps.add(
        CommissioningStep(
          name: 'TCP Socket Availability',
          passed: false,
          details: 'Connection to $host:$port failed: $e',
          remediation: 'Verify scanner power (24 VDC), Ethernet link lights, and IP routing.',
        ),
      );
      recommendations.add(
        'Check physical Ethernet cable connection and ensure scanner power is active.',
      );
    } finally {
      try {
        probeSocket?.destroy();
      } catch (_) {}
    }

    // 2. Subnet & Network Interface Compatibility
    final subnetOk = await _checkSubnetCompatibility(host);
    if (subnetOk.passed) {
      steps.add(subnetOk);
    } else {
      steps.add(subnetOk);
      recommendations.add(
        subnetOk.remediation ?? 'Ensure host PC is on the same logical subnet.',
      );
    }

    // 3. Command Channel & Model Handshake
    var handshakeOk = false;
    final client = existingClient ?? KeyenceSr751Client();
    final shouldDisposeClient = existingClient == null;

    try {
      if (socketOpen) {
        final handshake = await client.connectAndVerify(
          targetHost: host,
          targetPort: port,
          timeout: timeout,
        );

        if (handshake.success) {
          handshakeOk = true;
          model = handshake.model;
          fw = handshake.firmwareVersion;
          sn = handshake.serialNumber;
          steps.add(
            CommissioningStep(
              name: 'Command Channel Handshake',
              passed: true,
              details:
                  'Verified KEYENCE protocol: Model $model, FW ${fw ?? "N/A"}, SN ${sn ?? "N/A"} (${handshake.handshakeTimeMs}ms)',
            ),
          );

          // 4. Status Check (STAT)
          try {
            final statReply = await client.sendCommand('STAT');
            if (statReply) {
              steps.add(
                const CommissioningStep(
                  name: 'Reader Health Status',
                  passed: true,
                  details: 'STAT query acknowledged (Normal operating status)',
                ),
              );
            }
          } catch (_) {}

          // 5. Test Illumination / Trigger Channel (LOFF safe command)
          final loffOk = await client.stopRead();
          steps.add(
            CommissioningStep(
              name: 'Barcode Control Channel',
              passed: loffOk,
              details: loffOk
                  ? 'Trigger and control command channel active'
                  : 'Control command was not acknowledged',
            ),
          );
        } else {
          steps.add(
            CommissioningStep(
              name: 'Command Channel Handshake',
              passed: false,
              details:
                  'Device connected but did not respond to KEYENCE handshake: ${handshake.errorMessage}',
              remediation:
                  'Ensure the device at $host:$port is a KEYENCE SR series reader.',
            ),
          );
        }
      }
    } catch (e) {
      steps.add(
        CommissioningStep(
          name: 'Command Channel Handshake',
          passed: false,
          details: 'Handshake error: $e',
        ),
      );
    } finally {
      if (shouldDisposeClient) {
        client.dispose();
      }
    }

    // 6. CMOS FTP Image Receiver Check
    final isFtpActive = ftpReceiver?.isRunning ?? false;
    steps.add(
      CommissioningStep(
        name: 'Embedded CMOS FTP Receiver',
        passed: isFtpActive,
        details: isFtpActive
            ? 'FTP Receiver running on port ${ftpReceiver?.boundPort ?? 2121} (Ready for CMOS images)'
            : 'FTP Receiver is currently idle (CMOS image transfer disabled until started)',
        remediation: isFtpActive ? null : 'Start FTP Receiver from the device screen to enable CMOS frame acquisition.',
      ),
    );

    final overallReady = socketOpen && subnetOk.passed && handshakeOk;

    return CommissioningReport(
      overallReady: overallReady,
      targetHost: host,
      targetPort: port,
      detectedModel: model,
      detectedFirmware: fw,
      detectedSerial: sn,
      steps: steps,
      recommendations: recommendations,
      measuredLatencyMs: sw.elapsedMilliseconds,
    );
  }

  Future<CommissioningStep> _checkSubnetCompatibility(String targetHost) async {
    try {
      final ifaces = await NetworkInterface.list(
        includeLoopback: true,
        type: InternetAddressType.IPv4,
      );
      final targetParts = targetHost.split('.');
      if (targetParts.length != 4) {
        return CommissioningStep(
          name: 'Network Subnet Compatibility',
          passed: true,
          details: 'Non-IPv4 or hostname target ($targetHost)',
        );
      }

      final targetSubnet =
          '${targetParts[0]}.${targetParts[1]}.${targetParts[2]}';

      for (final iface in ifaces) {
        for (final addr in iface.addresses) {
          final hostParts = addr.address.split('.');
          if (hostParts.length == 4) {
            final hostSubnet =
                '${hostParts[0]}.${hostParts[1]}.${hostParts[2]}';
            if (hostSubnet == targetSubnet) {
              return CommissioningStep(
                name: 'Network Subnet Compatibility',
                passed: true,
                details:
                    'Host interface ${iface.name} (${addr.address}) shares subnet with scanner ($targetHost)',
              );
            }
          }
        }
      }

      // Check for loopback
      if (targetHost == '127.0.0.1' || targetHost == 'localhost') {
        return const CommissioningStep(
          name: 'Network Subnet Compatibility',
          passed: true,
          details: 'Loopback target (local simulation / test)',
        );
      }

      return CommissioningStep(
        name: 'Network Subnet Compatibility',
        passed: false,
        details:
            'Scanner IP ($targetHost) is on subnet $targetSubnet.x, which does not match active host network interfaces.',
        remediation:
            'Configure host network card with a static IP on the scanner subnet (e.g. $targetSubnet.10, subnet 255.255.255.0) or adjust the scanner IP via AutoID Network Navigator.',
      );
    } catch (e) {
      return CommissioningStep(
        name: 'Network Subnet Compatibility',
        passed: true,
        details: 'Could not enumerate host interfaces: $e',
      );
    }
  }
}
