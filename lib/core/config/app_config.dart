// Single source of truth for Exalted configuration.
// Provenance tags used in comments:
//   [APP-VALUE]  value the app already used before this file existed. VERIFY against hardware.
//   [ASSUMPTION] configurable assumption chosen as a safe default. Not manufacturer-documented.
//   [MANUFACTURER] reserved for values confirmed in KEYENCE documentation. None yet.
//   [VERIFIED]   reserved for values confirmed on real hardware. None yet.

enum AppEnv { dev, test, prod }

AppEnv currentEnv() {
  const v = String.fromEnvironment('EXALTED_ENV', defaultValue: 'prod');
  return AppEnv.values.firstWhere(
    (e) => e.name == v,
    orElse: () => AppEnv.prod,
  );
}

class ConfigIssue {
  final String path;
  final String message;
  const ConfigIssue(this.path, this.message);
  @override
  String toString() => '$path: $message';
}

class ConfigInvalid implements Exception {
  final List<ConfigIssue> issues;
  ConfigInvalid(this.issues);
  @override
  String toString() => 'ConfigInvalid(${issues.join('; ')})';
}

/// Reads typed values tolerantly. Wrong type -> default plus a recorded issue.
class _R {
  final Map<String, dynamic> m;
  final String prefix;
  final List<ConfigIssue> issues;
  _R(this.m, this.prefix, this.issues);
  T _get<T>(String k, T def) {
    final v = m[k];
    if (v == null) return def;
    if (v is T) return v;
    issues.add(ConfigIssue('$prefix.$k', 'wrong type, using default'));
    return def;
  }

  int i(String k, int d) => _get<int>(k, d);
  bool b(String k, bool d) => _get<bool>(k, d);
  String s(String k, String d) => _get<String>(k, d);
  String? sn(String k) {
    final v = m[k];
    if (v == null) return null;
    if (v is String) return v;
    issues.add(ConfigIssue('$prefix.$k', 'wrong type, using null'));
    return null;
  }

  double d(String k, double def) {
    final v = m[k];
    if (v == null) return def;
    if (v is num) return v.toDouble();
    issues.add(ConfigIssue('$prefix.$k', 'wrong type, using default'));
    return def;
  }

  List<String> ls(String k, List<String> d) {
    final v = m[k];
    if (v == null) return d;
    if (v is List && v.every((e) => e is String)) return List<String>.from(v);
    issues.add(ConfigIssue('$prefix.$k', 'wrong type, using default'));
    return d;
  }
}

Map<String, dynamic> _sub(Map<String, dynamic> m, String k) {
  final v = m[k];
  return v is Map<String, dynamic> ? v : <String, dynamic>{};
}

bool _isIpv4(String s) {
  if (!RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(s)) return false;
  return s.split('.').every((p) => int.parse(p) <= 255);
}

class ScannerConfig {
  /// SecretStore key for the FTP receiver password. Never written to config.json.
  static const String ftpPasswordSecretKey = 'scanner.ftpReceiverPassword';

  final bool
  autoReconnect; // [APP-VALUE] true, keyence_scanner_coordinator.dart:181
  final bool
  hostSaved; // true once a host was saved: migrated, or a connect succeeded
  final bool autoConnect; // [APP-VALUE] true, keyence_scanner_coordinator.dart:180 (connects only if a host was saved)
  final String
  host; // [APP-VALUE] keyence_device_screen.dart preset. VERIFY on the reader
  final String? hostname; // optional DNS name, overrides host when set
  final int port; // [APP-VALUE] 9004. VERIFY
  final int? dataPort; // null = same as port. Not assumed to differ.
  final String mode; // 'tcp' only for now
  final int connectTimeoutMs; // [APP-VALUE] 10000, device_hub.dart:130
  final int acquisitionTimeoutMs; // [APP-VALUE] 5000, device_hub.dart:131
  final int operationTimeoutMs; // [APP-VALUE] 5000, device_hub.dart:132
  final int discoveryTimeoutMs; // [APP-VALUE] 10000, device_hub.dart:133
  final int reconnectInitialDelayMs; // [APP-VALUE] 1000, device_hub.dart:15
  final int reconnectMaxDelayMs; // [APP-VALUE] 16000, device_hub.dart:16
  final int? reconnectMaxAttempts; // null = config sets no limit (hub behaviour unverified)
  final bool
  ftpReceiverEnabled; // false: the user starts it from the device screen today
  final int ftpReceiverPort; // [APP-VALUE] 2121, keyence_ftp_receiver.dart:44
  final String ftpBindAddress; // [APP-VALUE] 0.0.0.0 (InternetAddress.anyIPv4)
  final String?
  ftpUsername; // required, with the vault password, for the FTP receiver to start
  final int? ftpMaxUploadBytes; // null = receiver built-in kMaxUploadBytes
  final String? imageDir; // null = app storage default
  final String deviceLabel; // display name only
  const ScannerConfig({
    this.autoConnect = true,
    this.hostSaved = false,
    this.autoReconnect = true,
    this.host = '192.168.100.100',
    this.hostname,
    this.port = 9004,
    this.dataPort,
    this.mode = 'tcp',
    this.connectTimeoutMs = 10000,
    this.acquisitionTimeoutMs = 5000,
    this.operationTimeoutMs = 5000,
    this.discoveryTimeoutMs = 10000,
    this.reconnectInitialDelayMs = 1000,
    this.reconnectMaxDelayMs = 16000,
    this.reconnectMaxAttempts,
    this.ftpReceiverEnabled = false,
    this.ftpReceiverPort = 2121,
    this.ftpBindAddress = '0.0.0.0',
    this.ftpUsername,
    this.ftpMaxUploadBytes,
    this.imageDir,
    this.deviceLabel = 'SR-751',
  });

  factory ScannerConfig.from(Map<String, dynamic> m, List<ConfigIssue> iss) {
    const d = ScannerConfig();
    final r = _R(m, 'scanner', iss);
    return ScannerConfig(
      autoConnect: r.b('autoConnect', d.autoConnect),
      hostSaved: r.b('hostSaved', d.hostSaved),
      autoReconnect: r.b('autoReconnect', d.autoReconnect),
      host: r.s('host', d.host),
      hostname: r.sn('hostname'),
      port: r.i('port', d.port),
      dataPort: m['dataPort'] is int ? m['dataPort'] as int : null,
      mode: r.s('mode', d.mode),
      connectTimeoutMs: r.i('connectTimeoutMs', d.connectTimeoutMs),
      acquisitionTimeoutMs: r.i('acquisitionTimeoutMs', d.acquisitionTimeoutMs),
      operationTimeoutMs: r.i('operationTimeoutMs', d.operationTimeoutMs),
      discoveryTimeoutMs: r.i('discoveryTimeoutMs', d.discoveryTimeoutMs),
      reconnectInitialDelayMs: r.i(
        'reconnectInitialDelayMs',
        d.reconnectInitialDelayMs,
      ),
      reconnectMaxDelayMs: r.i('reconnectMaxDelayMs', d.reconnectMaxDelayMs),
      reconnectMaxAttempts: m['reconnectMaxAttempts'] is int
          ? m['reconnectMaxAttempts'] as int
          : null,
      ftpReceiverEnabled: r.b('ftpReceiverEnabled', d.ftpReceiverEnabled),
      ftpReceiverPort: r.i('ftpReceiverPort', d.ftpReceiverPort),
      ftpBindAddress: r.s('ftpBindAddress', d.ftpBindAddress),
      ftpUsername: r.sn('ftpUsername'),
      ftpMaxUploadBytes: m['ftpMaxUploadBytes'] is int
          ? m['ftpMaxUploadBytes'] as int
          : null,
      imageDir: r.sn('imageDir'),
      deviceLabel: r.s('deviceLabel', d.deviceLabel),
    );
  }

  Map<String, dynamic> toJson() => {
    'autoConnect': autoConnect,
    'hostSaved': hostSaved,
    'autoReconnect': autoReconnect,
    'host': host,
    'hostname': hostname,
    'port': port,
    'dataPort': dataPort,
    'mode': mode,
    'connectTimeoutMs': connectTimeoutMs,
    'acquisitionTimeoutMs': acquisitionTimeoutMs,
    'operationTimeoutMs': operationTimeoutMs,
    'discoveryTimeoutMs': discoveryTimeoutMs,
    'reconnectInitialDelayMs': reconnectInitialDelayMs,
    'reconnectMaxDelayMs': reconnectMaxDelayMs,
    'reconnectMaxAttempts': reconnectMaxAttempts,
    'ftpReceiverEnabled': ftpReceiverEnabled,
    'ftpReceiverPort': ftpReceiverPort,
    'ftpBindAddress': ftpBindAddress,
    'ftpUsername': ftpUsername,
    'ftpMaxUploadBytes': ftpMaxUploadBytes,
    'imageDir': imageDir,
    'deviceLabel': deviceLabel,
  };

  List<ConfigIssue> validate() {
    final e = <ConfigIssue>[];
    void range(String p, int v, int lo, int hi) {
      if (v < lo || v > hi) {
        e.add(ConfigIssue('scanner.$p', 'must be $lo..$hi, got $v'));
      }
    }

    if (mode != 'tcp') {
      e.add(const ConfigIssue('scanner.mode', 'must be tcp'));
    }
    if (mode == 'tcp' &&
        host.trim().isEmpty &&
        (hostname ?? '').trim().isEmpty) {
      e.add(
        const ConfigIssue('scanner.host', 'host or hostname required for tcp'),
      );
    }
    if (RegExp(r'^[\d.]+$').hasMatch(host) && !_isIpv4(host)) {
      e.add(const ConfigIssue('scanner.host', 'invalid IPv4 address'));
    }
    range('port', port, 1, 65535);
    final dp = dataPort;
    if (dp != null) range('dataPort', dp, 1, 65535);
    range('connectTimeoutMs', connectTimeoutMs, 200, 120000);
    range('acquisitionTimeoutMs', acquisitionTimeoutMs, 200, 120000);
    range('operationTimeoutMs', operationTimeoutMs, 200, 120000);
    range('discoveryTimeoutMs', discoveryTimeoutMs, 200, 120000);
    range('reconnectInitialDelayMs', reconnectInitialDelayMs, 100, 600000);
    range('reconnectMaxDelayMs', reconnectMaxDelayMs, 100, 600000);
    if (reconnectMaxDelayMs < reconnectInitialDelayMs) {
      e.add(
        const ConfigIssue(
          'scanner.reconnectMaxDelayMs',
          'must be >= reconnectInitialDelayMs',
        ),
      );
    }
    final ra = reconnectMaxAttempts;
    if (ra != null) range('reconnectMaxAttempts', ra, 0, 100000);
    range('ftpReceiverPort', ftpReceiverPort, 1, 65535);
    if (!_isIpv4(ftpBindAddress)) {
      e.add(
        const ConfigIssue(
          'scanner.ftpBindAddress',
          'must be an IPv4 address such as 0.0.0.0',
        ),
      );
    }
    final mu = ftpMaxUploadBytes;
    if (mu != null) range('ftpMaxUploadBytes', mu, 1, 2147483647);
    return e;
  }

  /// Non-blocking findings for the Settings screen.
  List<ConfigIssue> warnings() {
    final w = <ConfigIssue>[];
    if (ftpReceiverEnabled && (ftpUsername ?? '').isEmpty) {
      w.add(
        const ConfigIssue(
          'scanner.ftpUsername',
          'FTP receiver has no username set: it will not start until a username and password are saved',
        ),
      );
    }
    if (ftpReceiverEnabled && ftpBindAddress == '0.0.0.0') {
      w.add(
        const ConfigIssue(
          'scanner.ftpBindAddress',
          'FTP receiver listens on all network interfaces',
        ),
      );
    }
    return w;
  }
}

class CameraConfig {
  /// Same names as CameraQuality in scanner_controller.dart.
  static const List<String> qualities = ['balanced', 'high', 'ultra'];

  final String? deviceId; // null = first available
  final String quality; // [APP-VALUE] balanced, scanner_controller.dart (EXALTED_QUALITY define overrides)
  final bool showPreview;
  const CameraConfig({
    this.deviceId,
    this.quality = 'balanced',
    this.showPreview = true,
  });
  factory CameraConfig.from(Map<String, dynamic> m, List<ConfigIssue> iss) {
    const d = CameraConfig();
    final r = _R(m, 'camera', iss);
    return CameraConfig(
      deviceId: r.sn('deviceId'),
      quality: r.s('quality', d.quality),
      showPreview: r.b('showPreview', d.showPreview),
    );
  }
  Map<String, dynamic> toJson() => {
    'deviceId': deviceId,
    'quality': quality,
    'showPreview': showPreview,
  };
  List<ConfigIssue> validate() => [
    if (!qualities.contains(quality))
      ConfigIssue('camera.quality', 'must be one of ${qualities.join(', ')}'),
  ];
}

void _range(List<ConfigIssue> e, String p, int v, int lo, int hi) {
  if (v < lo || v > hi) e.add(ConfigIssue(p, 'must be $lo..$hi, got $v'));
}

class DecoderConfig {
  /// Same names as BarcodeKind in lib/ffi/decode_result.dart (without unknown).
  static const List<String> knownSymbologies = [
    'aztec',
    'codabar',
    'code39',
    'code93',
    'code128',
    'dataBar',
    'dataBarExpanded',
    'dataMatrix',
    'ean8',
    'ean13',
    'itf',
    'maxiCode',
    'pdf417',
    'qrCode',
    'upcA',
    'upcE',
    'microQr',
  ];

  /// Empty = pass formatsMask 0, as decoder_service.dart does by default.
  final List<String> symbologies;
  final bool ocrWithDecode; // [APP-VALUE] true, combined_inspector.dart:18
  final int rearmGapMs; // [APP-VALUE] 1000 (200..5000), detection_events.dart
  const DecoderConfig({
    this.symbologies = const [],
    this.ocrWithDecode = true,
    this.rearmGapMs = 1000,
  });
  factory DecoderConfig.from(Map<String, dynamic> m, List<ConfigIssue> iss) {
    const d = DecoderConfig();
    final r = _R(m, 'decoder', iss);
    return DecoderConfig(
      symbologies: r.ls('symbologies', d.symbologies),
      ocrWithDecode: r.b('ocrWithDecode', d.ocrWithDecode),
      rearmGapMs: r.i('rearmGapMs', d.rearmGapMs),
    );
  }
  Map<String, dynamic> toJson() => {
    'symbologies': symbologies,
    'ocrWithDecode': ocrWithDecode,
    'rearmGapMs': rearmGapMs,
  };
  List<ConfigIssue> validate() {
    final e = <ConfigIssue>[
      for (final n in symbologies)
        if (!knownSymbologies.contains(n))
          ConfigIssue('decoder.symbologies', 'unknown symbology: $n'),
    ];
    _range(e, 'decoder.rearmGapMs', rearmGapMs, 200, 5000);
    return e;
  }
}

class StorageConfig {
  final bool keepImages; // [APP-VALUE] false, combined_inspector.dart:18
  /// Not read by anything yet. A future path resolver may use it, and
  /// changing it must never move or delete existing data.
  final String? dataDirOverride;
  const StorageConfig({this.keepImages = false, this.dataDirOverride});
  factory StorageConfig.from(Map<String, dynamic> m, List<ConfigIssue> iss) {
    const d = StorageConfig();
    final r = _R(m, 'storage', iss);
    return StorageConfig(
      keepImages: r.b('keepImages', d.keepImages),
      dataDirOverride: r.sn('dataDirOverride'),
    );
  }
  Map<String, dynamic> toJson() => {
    'keepImages': keepImages,
    'dataDirOverride': dataDirOverride,
  };
  List<ConfigIssue> validate() => const [];
}

class StartupConfig {
  /// Relaunch the app after a fatal crash. Off by default.
  final bool autoRestart;

  /// Give up after this many automatic restarts within one hour, so a crash
  /// loop cannot spin forever.
  final int maxRestartsPerHour;
  const StartupConfig({this.autoRestart = false, this.maxRestartsPerHour = 3});
  factory StartupConfig.from(Map<String, dynamic> m, List<ConfigIssue> iss) {
    const d = StartupConfig();
    final r = _R(m, 'startup', iss);
    return StartupConfig(
      autoRestart: r.b('autoRestart', d.autoRestart),
      maxRestartsPerHour: r.i('maxRestartsPerHour', d.maxRestartsPerHour),
    );
  }
  Map<String, dynamic> toJson() => {
    'autoRestart': autoRestart,
    'maxRestartsPerHour': maxRestartsPerHour,
  };
  List<ConfigIssue> validate() {
    final e = <ConfigIssue>[];
    _range(e, 'startup.maxRestartsPerHour', maxRestartsPerHour, 1, 20);
    return e;
  }
}

class NetworkConfig {
  final int
  httpConnectTimeoutMs; // [APP-VALUE] 7000, verify/http_client.dart:35
  final int
  httpRequestTimeoutMs; // [APP-VALUE] 10000 per attempt, http_client.dart:16
  final int httpIdleTimeoutMs; // [APP-VALUE] 5000, http_client.dart:36
  final int httpMaxAttempts; // [APP-VALUE] 2, retry loop in http_client.dart
  final int httpRetryDelayMs; // [APP-VALUE] 400, http_client.dart
  final int maxResponseBytes; // [APP-VALUE] 1 MB, http_client.dart
  const NetworkConfig({
    this.httpConnectTimeoutMs = 7000,
    this.httpRequestTimeoutMs = 10000,
    this.httpIdleTimeoutMs = 5000,
    this.httpMaxAttempts = 2,
    this.httpRetryDelayMs = 400,
    this.maxResponseBytes = 1048576,
  });
  factory NetworkConfig.from(Map<String, dynamic> m, List<ConfigIssue> iss) {
    const d = NetworkConfig();
    final r = _R(m, 'network', iss);
    return NetworkConfig(
      httpConnectTimeoutMs: r.i('httpConnectTimeoutMs', d.httpConnectTimeoutMs),
      httpRequestTimeoutMs: r.i('httpRequestTimeoutMs', d.httpRequestTimeoutMs),
      httpIdleTimeoutMs: r.i('httpIdleTimeoutMs', d.httpIdleTimeoutMs),
      httpMaxAttempts: r.i('httpMaxAttempts', d.httpMaxAttempts),
      httpRetryDelayMs: r.i('httpRetryDelayMs', d.httpRetryDelayMs),
      maxResponseBytes: r.i('maxResponseBytes', d.maxResponseBytes),
    );
  }
  Map<String, dynamic> toJson() => {
    'httpConnectTimeoutMs': httpConnectTimeoutMs,
    'httpRequestTimeoutMs': httpRequestTimeoutMs,
    'httpIdleTimeoutMs': httpIdleTimeoutMs,
    'httpMaxAttempts': httpMaxAttempts,
    'httpRetryDelayMs': httpRetryDelayMs,
    'maxResponseBytes': maxResponseBytes,
  };
  List<ConfigIssue> validate() {
    final e = <ConfigIssue>[];
    _range(
      e,
      'network.httpConnectTimeoutMs',
      httpConnectTimeoutMs,
      200,
      120000,
    );
    _range(
      e,
      'network.httpRequestTimeoutMs',
      httpRequestTimeoutMs,
      200,
      120000,
    );
    _range(e, 'network.httpIdleTimeoutMs', httpIdleTimeoutMs, 200, 120000);
    _range(e, 'network.httpMaxAttempts', httpMaxAttempts, 1, 10);
    _range(e, 'network.httpRetryDelayMs', httpRetryDelayMs, 0, 60000);
    _range(e, 'network.maxResponseBytes', maxResponseBytes, 1024, 104857600);
    return e;
  }
}

class AppearanceConfig {
  static const List<String> themeModes = ['system', 'light', 'dark'];

  /// null = the platform default (light on phones, dark on desktop).
  final String? themeMode;
  const AppearanceConfig({this.themeMode});
  factory AppearanceConfig.from(Map<String, dynamic> m, List<ConfigIssue> iss) {
    final r = _R(m, 'appearance', iss);
    return AppearanceConfig(themeMode: r.sn('themeMode'));
  }
  Map<String, dynamic> toJson() => {'themeMode': themeMode};
  List<ConfigIssue> validate() => [
    if (themeMode != null && !themeModes.contains(themeMode))
      ConfigIssue(
        'appearance.themeMode',
        'must be one of ${themeModes.join(', ')}',
      ),
  ];
}

class AppConfig {
  static const int currentVersion = 1;
  final int version;
  final ScannerConfig scanner;
  final CameraConfig camera;
  final DecoderConfig decoder;
  final StorageConfig storage;
  final NetworkConfig network;
  final AppearanceConfig appearance;
  final StartupConfig startup;
  const AppConfig({
    this.version = currentVersion,
    this.scanner = const ScannerConfig(),
    this.camera = const CameraConfig(),
    this.decoder = const DecoderConfig(),
    this.storage = const StorageConfig(),
    this.network = const NetworkConfig(),
    this.appearance = const AppearanceConfig(),
    this.startup = const StartupConfig(),
  });

  static AppConfig defaults() => const AppConfig();

  factory AppConfig.fromJson(
    Map<String, dynamic> m,
    List<ConfigIssue> issues,
  ) => AppConfig(
    version: m['version'] is int ? m['version'] as int : currentVersion,
    scanner: ScannerConfig.from(_sub(m, 'scanner'), issues),
    camera: CameraConfig.from(_sub(m, 'camera'), issues),
    decoder: DecoderConfig.from(_sub(m, 'decoder'), issues),
    storage: StorageConfig.from(_sub(m, 'storage'), issues),
    network: NetworkConfig.from(_sub(m, 'network'), issues),
    appearance: AppearanceConfig.from(_sub(m, 'appearance'), issues),
    startup: StartupConfig.from(_sub(m, 'startup'), issues),
  );

  Map<String, dynamic> toJson() => {
    'version': version,
    'scanner': scanner.toJson(),
    'camera': camera.toJson(),
    'decoder': decoder.toJson(),
    'storage': storage.toJson(),
    'network': network.toJson(),
    'appearance': appearance.toJson(),
    'startup': startup.toJson(),
  };

  /// Non-blocking findings the Settings screen should show.
  List<ConfigIssue> warnings() => scanner.warnings();

  List<ConfigIssue> validate() {
    final e = <ConfigIssue>[];
    e.addAll(scanner.validate());

    e.addAll(camera.validate());

    e.addAll(decoder.validate());
    e.addAll(storage.validate());
    e.addAll(network.validate());
    e.addAll(appearance.validate());
    e.addAll(startup.validate());
    return e;
  }
}

/// Secrets never live in config.json. Back this with platform secure storage later.
abstract class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Safe for logs and diagnostics. Masks any value whose key looks secret.
Object? redact(Object? node) {
  final secret = RegExp(
    r'pass(word|wd)?|token|secret|private|api_?key',
    caseSensitive: false,
  );
  if (node is Map) {
    return {
      for (final e in node.entries)
        e.key: secret.hasMatch('${e.key}') ? '***' : redact(e.value),
    };
  }
  if (node is List) return node.map(redact).toList();
  return node;
}
