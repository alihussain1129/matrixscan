import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences keys the app already writes. Read-only here.
abstract final class LegacyKeys {
  static const String keyenceHost = 'exalted_keyence_last_host';
  static const String keyencePort = 'exalted_keyence_last_port';
  static const String keyenceModel = 'exalted_keyence_last_model';
  static const String keyenceAutoConnect = 'exalted_keyence_auto_connect';
  static const String keyenceAutoReconnect = 'exalted_keyence_auto_reconnect';
  static const String cameraQuality = 'exalted_camera_quality';
  static const String rearmGapMs = 'exalted_rearm_gap_ms';
  static const String themeMode = 'exalted_theme_mode';
  static const String ocrWithDecode = 'exalted_ocr_with_decode';
  static const String keepImages = 'exalted_keep_images';
}

/// Snapshot of values the app saved before config.json existed.
/// A null field means the user never saved it, so the config default applies.
class LegacySettings {
  const LegacySettings({
    this.host,
    this.port,
    this.model,
    this.autoConnect,
    this.autoReconnect,
    this.cameraQuality,
    this.rearmGapMs,
    this.themeMode,
    this.ocrWithDecode,
    this.keepImages,
  });

  final String? host;
  final int? port;
  final String? model;
  final bool? autoConnect;
  final bool? autoReconnect;
  final String? cameraQuality;
  final int? rearmGapMs;
  final String? themeMode;
  final bool? ocrWithDecode;
  final bool? keepImages;

  bool get isEmpty =>
      host == null &&
      port == null &&
      model == null &&
      autoConnect == null &&
      autoReconnect == null &&
      cameraQuality == null &&
      rearmGapMs == null &&
      themeMode == null &&
      ocrWithDecode == null &&
      keepImages == null;

  Map<String, dynamic> appearanceJson() => {
    if (themeMode == 'system' || themeMode == 'light' || themeMode == 'dark')
      'themeMode': themeMode,
  };

  Map<String, dynamic> cameraJson() => {
    if (cameraQuality != null) 'quality': cameraQuality,
  };

  Map<String, dynamic> decoderJson() => {
    if (ocrWithDecode != null) 'ocrWithDecode': ocrWithDecode,
    if (rearmGapMs != null) 'rearmGapMs': rearmGapMs!.clamp(200, 5000).toInt(),
  };

  Map<String, dynamic> storageJson() => {
    if (keepImages != null) 'keepImages': keepImages,
  };

  /// Values that map onto fields ScannerConfig already has.
  Map<String, dynamic> scannerJson() => {
    if (host != null) 'host': host,
    if (port != null) 'port': port,
    if (model != null) 'deviceLabel': model,
    if (autoConnect != null) 'autoConnect': autoConnect,
    if (autoReconnect != null) 'autoReconnect': autoReconnect,
  };
}

/// Reads the old stores. Never writes or removes anything.
Future<LegacySettings> readLegacySettings([SharedPreferences? prefs]) async {
  final p = prefs ?? await SharedPreferences.getInstance();
  String? s(String k) {
    final v = p.get(k);
    return v is String ? v : null;
  }

  int? i(String k) {
    final v = p.get(k);
    return v is int ? v : null;
  }

  bool? b(String k) {
    final v = p.get(k);
    return v is bool ? v : null;
  }

  return LegacySettings(
    host: s(LegacyKeys.keyenceHost),
    port: i(LegacyKeys.keyencePort),
    model: s(LegacyKeys.keyenceModel),
    autoConnect: b(LegacyKeys.keyenceAutoConnect),
    autoReconnect: b(LegacyKeys.keyenceAutoReconnect),
    cameraQuality: s(LegacyKeys.cameraQuality),
    rearmGapMs: i(LegacyKeys.rearmGapMs),
    themeMode: s(LegacyKeys.themeMode),
    ocrWithDecode: b(LegacyKeys.ocrWithDecode),
    keepImages: b(LegacyKeys.keepImages),
  );
}
