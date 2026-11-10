import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/device_adapter.dart';
import '../core/device_models.dart';

/// Progress event emitted during KEYENCE scanner discovery.
class ScannerDiscoveryEvent {
  const ScannerDiscoveryEvent({
    required this.phase,
    required this.message,
    this.foundDevice,
    this.progress = 0.0,
  });

  final String phase;
  final String message;
  final DeviceIdentity? foundDevice;
  final double progress;

  @override
  String toString() => 'ScannerDiscoveryEvent($phase: $message)';
}

/// Discovered scanner information with handshake details.
class DiscoveredKeyenceScanner {
  const DiscoveredKeyenceScanner({
    required this.identity,
    required this.rawResponse,
    required this.responseTimeMs,
    required this.interfaceName,
  });

  final DeviceIdentity identity;
  final String rawResponse;
  final int responseTimeMs;
  final String interfaceName;
}

/// Automatic scanner discovery service for KEYENCE SR-750 / SR-751 series readers.
///
/// Implements [DeviceDiscoverySource] for seamless integration into the Exalted
/// [DeviceHub].
///
/// Strategy:
/// 1. Enumerates active network interfaces (Ethernet, Wi-Fi, loopback).
/// 2. Reads local ARP / neighbor cache (on Linux/Android) for instantaneous device hits.
/// 3. Builds candidate IP list:
///    - Last known / persisted scanner endpoints
///    - Keyence factory default IP: 192.168.100.100 (port 9004)
///    - Active ARP neighbor IPs
///    - Common industrial static IPs (.100, .101, .200, .10, .20) on active subnets
///    - Subnet broadcast probe
/// 4. Performs asynchronous parallel TCP connection and explicit KEYENCE handshake verification:
///    Sends 'KEYENCE\r' -> Expects 'SR-751...' or 'KEYENCE...' signature.
/// 5. Deduplicates devices and creates verified [DeviceIdentity] entries.
class KeyenceScannerDiscoveryService implements DeviceDiscoverySource {
  KeyenceScannerDiscoveryService({
    this.defaultPort = 9004,
    this.probeTimeout = const Duration(milliseconds: 350),
    this.handshakeTimeout = const Duration(milliseconds: 600),
    List<String>? initialCandidateHosts,
  }) : _extraCandidateHosts = List<String>.of(
         initialCandidateHosts ?? const [],
       );

  final int defaultPort;
  final Duration probeTimeout;
  final Duration handshakeTimeout;
  final List<String> _extraCandidateHosts;

  final _eventsController = StreamController<ScannerDiscoveryEvent>.broadcast();
  Stream<ScannerDiscoveryEvent> get eventsStream => _eventsController.stream;

  bool _isDiscovering = false;
  bool get isDiscovering => _isDiscovering;

  @override
  String get id => 'keyence-auto-discovery';

  /// Adds a host or IP to always probe first during discovery (e.g. from saved registry).
  void addCandidateHost(String host) {
    final trimmed = host.trim();
    if (trimmed.isNotEmpty && !_extraCandidateHosts.contains(trimmed)) {
      _extraCandidateHosts.add(trimmed);
    }
  }

  @override
  Future<List<DeviceIdentity>> discover() async {
    final scanners = await scanForScanners();
    return scanners.map((s) => s.identity).toList();
  }

  /// Runs the full automatic discovery process across local networks.
  Future<List<DiscoveredKeyenceScanner>> scanForScanners({
    Duration overallTimeout = const Duration(seconds: 4),
    bool includeSubnetSweep = true,
  }) async {
    if (_isDiscovering) {
      debugPrint('[KEYENCE][DISCOVERY] Discovery already in progress');
      return const [];
    }

    _isDiscovering = true;
    _emit('init', 'Detecting active network interfaces...', 0.1);

    final discovered = <String, DiscoveredKeyenceScanner>{};

    try {
      // Step 1: Detect interfaces
      final interfaces = await _detectNetworkInterfaces();
      _emit(
        'interfaces',
        'Found ${interfaces.length} active network interface(s)',
        0.2,
      );

      // Step 2: Gather candidate endpoints
      final candidates = await _buildCandidates(interfaces, includeSubnetSweep);
      _emit(
        'candidates',
        'Probing ${candidates.length} candidate endpoint(s)...',
        0.3,
      );

      // Step 3: Fast parallel probe & handshake verification
      // Run candidates in batches of 32 for optimal concurrency without socket exhaustion
      const batchSize = 32;
      final total = candidates.length;
      var processed = 0;

      for (var i = 0; i < candidates.length; i += batchSize) {
        final end = (i + batchSize < candidates.length)
            ? i + batchSize
            : candidates.length;
        final batch = candidates.sublist(i, end);

        final futures = batch.map((target) => _probeAndVerify(target));
        final results = await Future.wait(futures);

        for (final res in results) {
          if (res != null && !discovered.containsKey(res.identity.id)) {
            discovered[res.identity.id] = res;
            _emit(
              'found',
              'Discovered ${res.identity.displayName} at ${res.identity.ipAddress}:${res.identity.port}',
              0.5 + (0.5 * (processed / total)),
              res.identity,
            );
          }
        }

        processed += batch.length;
        _emit(
          'probing',
          'Probed $processed of $total endpoints ($discovered found)',
          0.3 + (0.6 * (processed / total)),
        );

        // If we found a scanner on direct priority candidates, we can finish early
        if (discovered.isNotEmpty && i >= 32) {
          break;
        }
      }

      _emit(
        'complete',
        'Discovery complete. Found ${discovered.length} scanner(s).',
        1.0,
      );
      return discovered.values.toList();
    } catch (e) {
      debugPrint('[KEYENCE][DISCOVERY] Discovery error: $e');
      _emit('error', 'Discovery error: $e', 1.0);
      return discovered.values.toList();
    } finally {
      _isDiscovering = false;
    }
  }

  /// Directly verifies an endpoint (e.g. entered manually by the user or from saved profiles).
  Future<DiscoveredKeyenceScanner?> verifyEndpoint(
    String host, [
    int? port,
  ]) async {
    final targetPort = port ?? defaultPort;
    return _probeAndVerify(_TargetEndpoint(host, targetPort, 'manual'));
  }

  Future<List<_DetectedInterface>> _detectNetworkInterfaces() async {
    final detected = <_DetectedInterface>[];
    try {
      final ifaces = await NetworkInterface.list(
        includeLoopback: true,
        type: InternetAddressType.IPv4,
      );
      for (final iface in ifaces) {
        for (final addr in iface.addresses) {
          final isEthernet = RegExp(
            r'^(eth|en|ethernet|lan)',
            caseSensitive: false,
          ).hasMatch(iface.name);
          final isWifi = RegExp(
            r'^(wl|wlan|wifi)',
            caseSensitive: false,
          ).hasMatch(iface.name);
          final isLoopback = iface.name.startsWith('lo') || addr.isLoopback;

          detected.add(
            _DetectedInterface(
              name: iface.name,
              address: addr.address,
              isEthernet: isEthernet,
              isWifi: isWifi,
              isLoopback: isLoopback,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('[KEYENCE][DISCOVERY] NetworkInterface.list error: $e');
    }

    // Always ensure at least loopback is present for tests / simulators
    if (detected.isEmpty) {
      detected.add(
        const _DetectedInterface(
          name: 'lo',
          address: '127.0.0.1',
          isEthernet: false,
          isWifi: false,
          isLoopback: true,
        ),
      );
    }
    return detected;
  }

  Future<List<_TargetEndpoint>> _buildCandidates(
    List<_DetectedInterface> interfaces,
    bool includeSubnetSweep,
  ) async {
    final candidates = <_TargetEndpoint>[];
    final seen = <String>{};

    void addCandidate(String host, int port, String origin) {
      final key = '$host:$port';
      if (seen.add(key)) {
        candidates.add(_TargetEndpoint(host, port, origin));
      }
    }

    // Priority 1: User-configured / saved endpoints
    for (final host in _extraCandidateHosts) {
      addCandidate(host, defaultPort, 'saved-profile');
    }

    // Priority 2: Keyence factory default IP (192.168.100.100)
    addCandidate('192.168.100.100', defaultPort, 'factory-default');

    // Priority 3: Neighbor cache / ARP table (Linux & Android)
    final arpIps = await _readArpEntries();
    for (final ip in arpIps) {
      addCandidate(ip, defaultPort, 'arp-neighbor');
    }

    // Priority 4: Interface-specific priority hosts
    for (final iface in interfaces) {
      if (iface.isLoopback) {
        addCandidate('127.0.0.1', defaultPort, 'loopback');
        continue;
      }

      final parts = iface.address.split('.');
      if (parts.length == 4) {
        final prefix = '${parts[0]}.${parts[1]}.${parts[2]}';
        // Common industrial static IPs
        final priorityOctets = [100, 101, 200, 10, 20, 1, 2, 254];
        for (final octet in priorityOctets) {
          final ip = '$prefix.$octet';
          if (ip != iface.address) {
            addCandidate(ip, defaultPort, 'subnet-priority');
          }
        }

        // Priority 5: Subnet sweep if enabled (1..254)
        if (includeSubnetSweep) {
          for (var i = 1; i <= 254; i++) {
            final ip = '$prefix.$i';
            if (ip != iface.address) {
              addCandidate(ip, defaultPort, 'subnet-sweep');
            }
          }
        }
      }
    }

    return candidates;
  }

  Future<List<String>> _readArpEntries() async {
    final ips = <String>[];
    if (Platform.isLinux || Platform.isAndroid) {
      try {
        final file = File('/proc/net/arp');
        if (await file.exists()) {
          final lines = await file.readAsLines();
          // Skip header line
          for (var i = 1; i < lines.length; i++) {
            final tokens = lines[i].trim().split(RegExp(r'\s+'));
            if (tokens.isNotEmpty) {
              final ip = tokens[0].trim();
              if (RegExp(r'^\d+\.\d+\.\d+\.\d+$').hasMatch(ip)) {
                ips.add(ip);
              }
            }
          }
        }
      } catch (_) {}
    }
    return ips;
  }

  Future<DiscoveredKeyenceScanner?> _probeAndVerify(
    _TargetEndpoint target,
  ) async {
    final sw = Stopwatch()..start();
    Socket? socket;
    try {
      socket = await Socket.connect(
        target.host,
        target.port,
        timeout: probeTimeout,
      );
      try {
        socket.setOption(SocketOption.tcpNoDelay, true);
      } catch (_) {}

      // Connection succeeded! Perform KEYENCE handshake query.
      socket.write('KEYENCE\r');
      await socket.flush();

      final completer = Completer<String>();
      final buffer = <int>[];

      final sub = socket.listen(
        (data) {
          buffer.addAll(data);
          final idx = buffer.indexOf(0x0D);
          if (idx >= 0 && !completer.isCompleted) {
            final line = utf8.decode(
              buffer.sublist(0, idx),
              allowMalformed: true,
            );
            completer.complete(line.trim());
          }
        },
        onError: (Object err) {
          if (!completer.isCompleted) completer.completeError(err);
        },
        onDone: () {
          if (!completer.isCompleted) {
            final rest = utf8.decode(buffer, allowMalformed: true).trim();
            completer.complete(rest);
          }
        },
        cancelOnError: true,
      );

      final response = await completer.future.timeout(handshakeTimeout);
      await sub.cancel();
      final elapsedMs = sw.elapsedMilliseconds;

      // Verify the response matches KEYENCE signature
      final trimmed = response.trim();
      if (trimmed.isEmpty) return null;

      final isKeyence =
          trimmed.startsWith('SR-') ||
          trimmed.toUpperCase().contains('KEYENCE') ||
          trimmed.toUpperCase().contains('SR-7');

      if (!isKeyence) return null;

      var model = 'SR-751';
      String? firmware;
      String? serial;

      if (trimmed.contains(',')) {
        final parts = trimmed.split(',');
        if (parts.isNotEmpty && parts[0].trim().isNotEmpty) {
          model = parts[0].trim();
        }
        if (parts.length > 1 && parts[1].trim().isNotEmpty) {
          firmware = parts[1].trim();
        }
        if (parts.length > 2 && parts[2].trim().isNotEmpty) {
          serial = parts[2].trim();
        }
      } else {
        model = trimmed;
      }

      final identity = DeviceIdentity.create(
        manufacturer: 'KEYENCE',
        model: model,
        interfaceType: DeviceInterfaceType.ethernet,
        transport: DeviceTransport.tcp,
        ipAddress: target.host,
        port: target.port,
        serialNumber: serial,
        firmwareVersion: firmware,
        displayName: 'KEYENCE $model (${target.host})',
      );

      return DiscoveredKeyenceScanner(
        identity: identity,
        rawResponse: trimmed,
        responseTimeMs: elapsedMs,
        interfaceName: target.origin,
      );
    } catch (_) {
      return null;
    } finally {
      try {
        socket?.destroy();
      } catch (_) {}
    }
  }

  void _emit(
    String phase,
    String message,
    double progress, [
    DeviceIdentity? device,
  ]) {
    if (_eventsController.isClosed) return;
    _eventsController.add(
      ScannerDiscoveryEvent(
        phase: phase,
        message: message,
        foundDevice: device,
        progress: progress,
      ),
    );
  }

  Future<void> dispose() async {
    await _eventsController.close();
  }
}

class _DetectedInterface {
  const _DetectedInterface({
    required this.name,
    required this.address,
    required this.isEthernet,
    required this.isWifi,
    required this.isLoopback,
  });

  final String name;
  final String address;
  final bool isEthernet;
  final bool isWifi;
  final bool isLoopback;
}

class _TargetEndpoint {
  const _TargetEndpoint(this.host, this.port, this.origin);
  final String host;
  final int port;
  final String origin;

  @override
  String toString() => '$host:$port ($origin)';
}
