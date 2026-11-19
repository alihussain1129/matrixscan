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

/// Non-destructive command-channel and local-service diagnostic report.
///
/// A passing command channel does not prove Data Port 1, trigger, FTP upload,
/// or physical production readiness.
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

  /// True only when TCP reachability and the documented identity handshake
  /// pass. It is not a claim of full production or physical hardware readiness.
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
      'CommissioningReport(commandChannelVerified: $overallReady, model: $detectedModel, steps: ${steps.length})';
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
    bool sendCommands = true,
    Set<String>? allowedCommands,
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
    if (existingClient?.status == KeyenceConnectionStatus.connected) {
      // Do not open a second socket to a reader that may permit only one
      // command client. The existing authenticated connection is the probe.
      socketOpen = true;
      steps.add(
        CommissioningStep(
          name: 'TCP Socket Availability',
          passed: true,
          details:
              'Existing verified command connection to $host:$port is open.',
        ),
      );
    } else {
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
    final client =
        existingClient ?? KeyenceSr751Client(allowedCommands: allowedCommands);
    final shouldDisposeClient = existingClient == null;

    try {
      if (socketOpen && !sendCommands) {
        steps.add(
          const CommissioningStep(
            name: 'Command Channel Handshake',
            passed: false,
            details: 'Not checked: listen-only mode sends no commands to the reader.',
            remediation: 'Enable the documented KEYENCE identity command in the app allow-list, or keep this endpoint in connect-only mode.',
          ),
        );
      } else if (socketOpen) {
        // Reuse a live client without dropping its barcode stream. Opening a
        // second command connection can interrupt an active production link.
        final handshake =
            existingClient != null &&
                existingClient.status == KeyenceConnectionStatus.connected
            ? await client.queryDeviceInfo(timeout: timeout)
            : await client.connectAndVerify(
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

          // 4. Reader error-status check (ERRSTAT)
          try {
            final statReply = await client.sendCommand('ERRSTAT');
            if (statReply) {
              steps.add(
                const CommissioningStep(
                  name: 'Reader Error-Status Query Sent',
                  passed: true,
                  details: 'ERRSTAT was transmitted; its response is not correlated or evaluated by this check.',
                ),
              );
            } else {
              steps.add(
                const CommissioningStep(
                  name: 'Reader Error-Status Query Sent',
                  passed: false,
                  details: 'ERRSTAT was not transmitted; check the app command allow-list.',
                ),
              );
            }
          } catch (_) {
            steps.add(
              const CommissioningStep(
                name: 'Reader Error-Status Query Sent',
                passed: false,
                details: 'ERRSTAT transmission failed.',
              ),
            );
          }

          // Do not send LON/LOFF during automatic commissioning: these are
          // operational controls and could interrupt an active production read.
          steps.add(
            const CommissioningStep(
              name: 'Barcode Trigger Control',
              passed: false,
              details: 'Not exercised automatically; use the operator trigger controls during a safe machine state.',
              remediation: 'Verify trigger behavior with the line stopped and an operator present.',
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

    // 6. Local FTP listener check. A bound socket does not prove that the
    // scanner can authenticate, negotiate a data channel, or upload an image.
    final isFtpActive = ftpReceiver?.isRunning ?? false;
    steps.add(
      CommissioningStep(
        name: 'Local FTP Listener',
        passed: isFtpActive,
        details: isFtpActive
            ? 'Listener is bound on port ${ftpReceiver?.boundPort ?? 21}; scanner login and image upload have not been tested.'
            : 'FTP listener is idle. Physical image transfer remains unverified.',
        remediation: isFtpActive
            ? 'Test an actual SR-751 image upload before production use.'
            : 'Configure FTP credentials and start the listener, then test an actual scanner upload.',
      ),
    );

    // This is intentionally a command-channel result, not a production
    // readiness claim. Data Port 1, a real barcode trigger, and FTP upload are
    // not exercised by this non-destructive assessment.
    final overallReady = socketOpen && handshakeOk;

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
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      final targetParts = targetHost.split('.');
      if (targetParts.length != 4 ||
          targetParts.any((part) => int.tryParse(part) == null)) {
        return CommissioningStep(
          name: 'Network Interface Context',
          passed: true,
          details: 'Target is a hostname or non-IPv4 address; the TCP reachability check is authoritative.',
        );
      }

      final targetPrefix = targetParts.take(3).join('.');
      for (final iface in ifaces) {
        for (final addr in iface.addresses) {
          final hostParts = addr.address.split('.');
          if (hostParts.length == 4 &&
              hostParts.take(3).join('.') == targetPrefix) {
            return CommissioningStep(
              name: 'Network Interface Context',
              passed: true,
              details:
                  'Interface ${iface.name} (${addr.address}) shares the same first three IPv4 octets. The actual prefix length is not available here, so this is only a /24 hint.',
            );
          }
        }
      }

      return CommissioningStep(
        name: 'Network Interface Context',
        passed: true,
        details: 'No interface with the same /24 prefix was found. A routed connection may still work; TCP reachability and KEYENCE identity checks determine connectivity.',
      );
    } catch (e) {
      return CommissioningStep(
        name: 'Network Interface Context',
        passed: true,
        details:
            'Interface enumeration was unavailable; TCP reachability remains the authoritative check (${e.runtimeType}).',
      );
    }
  }
}
