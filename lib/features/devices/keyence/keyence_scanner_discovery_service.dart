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
/// Checks saved endpoints, the documented factory-default address, ARP
/// neighbours, and optionally the configured TCP port across private /24
/// Ethernet subnets. When enabled, it verifies identity with the documented
/// read-only `KEYENCE` command and requires the exact documented response.
/// Connect-only mode remains available for installations that prohibit probes.
class KeyenceScannerDiscoveryService implements DeviceDiscoverySource {
  KeyenceScannerDiscoveryService({
    this.defaultPort = 9004,
    this.probeEnabled = true,
    this.probeTimeout = const Duration(milliseconds: 350),
    this.handshakeTimeout = const Duration(milliseconds: 600),
    List<String>? initialCandidateHosts,
  }) {
    for (final host in initialCandidateHosts ?? const <String>[]) {
      addCandidateHost(host);
    }
  }

  int defaultPort;

  /// When false, discovery uses connect-only checks and sends no application
  /// bytes. When true, it sends the documented read-only `KEYENCE` identity
  /// query and validates `OK, KEYENCE, SR-***, version`.
  bool probeEnabled;
  final Duration probeTimeout;
  final Duration handshakeTimeout;
  final List<_TargetEndpoint> _extraCandidateHosts = <_TargetEndpoint>[];

  final _eventsController = StreamController<ScannerDiscoveryEvent>.broadcast();
  Stream<ScannerDiscoveryEvent> get eventsStream => _eventsController.stream;

  bool _isDiscovering = false;
  bool get isDiscovering => _isDiscovering;

  void setDefaultPort(int port) {
    if (port < 1 || port > 65535) {
      throw RangeError.range(port, 1, 65535, 'port');
    }
    defaultPort = port;
  }

  @override
  String get id => 'keyence-auto-discovery';

  /// Adds a host or IP to always probe first during discovery (e.g. from saved registry).
  void addCandidateHost(String host, {int? port}) {
    final trimmed = host.trim();
    final targetPort = port ?? defaultPort;
    if (trimmed.isEmpty || targetPort < 1 || targetPort > 65535) return;
    if (!_extraCandidateHosts.any(
      (candidate) => candidate.host == trimmed && candidate.port == targetPort,
    )) {
      _extraCandidateHosts.add(
        _TargetEndpoint(trimmed, targetPort, 'saved-profile'),
      );
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
    final discoveryClock = Stopwatch()..start();
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

      // Step 3: Fast parallel connect-only checks or explicitly enabled probes.
      // Run candidates in batches of 32 for optimal concurrency without socket exhaustion
      const batchSize = 32;
      final total = candidates.length;
      var processed = 0;

      for (var i = 0; i < candidates.length; i += batchSize) {
        if (discoveryClock.elapsed >= overallTimeout) {
          _emit(
            'timeout',
            'Discovery time limit reached after $processed of $total endpoints.',
            1.0,
          );
          break;
        }
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
          total == 0 ? 1.0 : 0.3 + (0.6 * (processed / total)),
        );
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

    // Priority 1: User-configured / saved endpoints, preserving their port.
    for (final endpoint in _extraCandidateHosts) {
      addCandidate(endpoint.host, endpoint.port, endpoint.origin);
    }

    // Priority 2: The documented SR-750 factory-default address
    // (192.168.100.100/24 in the user's manual).
    addCandidate('192.168.100.100', defaultPort, 'possible-factory-default');

    // Priority 3: Neighbor cache / ARP table (Linux & Android).
    final ethernetInterfaceNames = interfaces
        .where((iface) => iface.isEthernet && !iface.isLoopback)
        .map((iface) => iface.name)
        .toSet();
    final arpIps = await _readArpEntries(ethernetInterfaceNames);
    for (final ip in arpIps) {
      addCandidate(ip, defaultPort, 'arp-neighbor');
    }

    // Include the private /24 Ethernet subnet sweep in both verified and
    // connect-only modes. Dart's cross-platform interface API does not expose
    // the interface prefix consistently, so /24 remains an explicit limit.
    if (!probeEnabled) {
      if (includeSubnetSweep) {
        for (final iface in interfaces) {
          if (iface.isLoopback || !iface.isEthernet || !_isPrivateIpv4(iface.address)) continue;
          final parts = iface.address.split('.');
          if (parts.length != 4) continue;
          final prefix = '${parts[0]}.${parts[1]}.${parts[2]}';
          for (var octet = 1; octet <= 254; octet++) {
            final ip = '$prefix.$octet';
            if (ip != iface.address) {
              addCandidate(ip, defaultPort, 'connect-only-subnet-sweep');
            }
          }
        }
      }
      return candidates;
    }

    // Interface-specific candidates. Only sweep private Ethernet links;
    // never scan Wi-Fi or public/otherwise routed interfaces.
    for (final iface in interfaces) {
      if (iface.isLoopback) {
        addCandidate('127.0.0.1', defaultPort, 'loopback');
        continue;
      }
      if (!iface.isEthernet || !_isPrivateIpv4(iface.address)) continue;

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

        // Full private /24 subnet sweep when enabled (1..254).
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


  /// Explicit connect-only fallback. Opens the configured TCP endpoint,
  /// writes no bytes, and never claims that an open port proves KEYENCE identity.
  Future<DiscoveredKeyenceScanner?> _connectOnlyCandidate(
    _TargetEndpoint target,
    Stopwatch sw,
  ) async {
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

      final identity = DeviceIdentity.create(
        manufacturer: 'Unverified',
        model: 'TCP endpoint (unverified)',
        interfaceType: DeviceInterfaceType.ethernet,
        transport: DeviceTransport.tcp,
        ipAddress: target.host,
        port: target.port,
        displayName: 'Possible KEYENCE SR-751 endpoint (${target.host}:${target.port})',
      );
      return DiscoveredKeyenceScanner(
        identity: identity,
        rawResponse: 'TCP connection succeeded; no protocol bytes sent; identity unverified',
        responseTimeMs: sw.elapsedMilliseconds,
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

  bool _isPrivateIpv4(String value) {
    final parts = value.split('.').map(int.tryParse).toList();
    if (parts.length != 4 || parts.any((part) => part == null)) return false;
    final a = parts[0]!;
    final b = parts[1]!;
    return a == 10 ||
        (a == 172 && b >= 16 && b <= 31) ||
        (a == 192 && b == 168);
  }

  Future<List<String>> _readArpEntries(
    Set<String> ethernetInterfaceNames,
  ) async {
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
              final device = tokens.length >= 6 ? tokens[5] : '';
              if (ethernetInterfaceNames.contains(device) &&
                  _isPrivateIpv4(ip) &&
                  RegExp(r'^\d+\.\d+\.\d+\.\d+$').hasMatch(ip)) {
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
    if (!probeEnabled) {
      return _connectOnlyCandidate(target, sw);
    }
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

      // The SR-750 manual documents KEYENCE as a read-only model/version
      // query. Commands use CR followed by LF; responses terminate with CR.
      socket.write('KEYENCE\r\n');
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

      // Accept only the exact response shape documented for the KEYENCE
      // identity command. A generic banner or a different model is not enough.
      final trimmed = response.trim();
      final parts = trimmed.split(',').map((part) => part.trim()).toList();
      if (parts.length < 4 ||
          parts[0].toUpperCase() != 'OK' ||
          parts[1].toUpperCase() != 'KEYENCE' ||
          !RegExp(r'^SR-\d{3,4}\w*$', caseSensitive: false)
              .hasMatch(parts[2])) {
        return null;
      }

      final model = parts[2];
      final firmware = parts[3].isEmpty ? null : parts[3];
      // The documented identity response contains no serial number.
      const String? serial = null;

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
