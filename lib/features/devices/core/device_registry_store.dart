import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'device_models.dart';

/// One saved device: identity, chosen backend and non-secret settings.
class SavedDevice {
  const SavedDevice({
    required this.identity,
    this.backendId,
    this.configuration,
  });

  final DeviceIdentity identity;
  final String? backendId;
  final DeviceConfiguration? configuration;
}

class RegistryLoadResult {
  const RegistryLoadResult({
    required this.devices,
    this.warning,
    this.preserved = false,
  });

  final List<SavedDevice> devices;
  final String? warning;

  /// True when stored data was left untouched because it could not be read
  /// safely (newer schema or corrupt). Saving is then refused.
  final bool preserved;
}

class RegistrySaveResult {
  const RegistrySaveResult({
    required this.written,
    this.droppedSecretKeys = const [],
    this.droppedUnsupported = const [],
    this.refusal,
  });

  /// True only if the registry was actually written to storage.
  final bool written;

  /// Paths (`deviceId/key/...`) of configuration keys that looked like
  /// credentials and were not stored. Values are never reported.
  final List<String> droppedSecretKeys;

  /// Paths of values that cannot be stored as JSON and were not stored.
  final List<String> droppedUnsupported;

  /// Why nothing was written, or null.
  final String? refusal;
}

/// Saves the device registry in SharedPreferences as versioned JSON.
///
/// Never stores secrets: configuration keys that look like credentials are
/// removed on save and on load (see [isSecretKey]). Never overwrites data it
/// cannot read: a newer schema or corrupt data is left exactly as it is.
class DeviceRegistryStore {
  DeviceRegistryStore(this._prefs);

  static const String key = 'exalted_device_registry';
  static const int schemaVersion = 1;

  final SharedPreferences _prefs;

  // Deliberately broad: a false positive only drops a setting (and reports
  // it); a false negative would store a credential.
  static final RegExp _secret = RegExp(
    r'(pass|pwd|secret|token|api[_-]?key|private[_-]?key|credential|auth)',
    caseSensitive: false,
  );

  static bool isSecretKey(String name) => _secret.hasMatch(name);

  static const Object _omit = Object();

  RegistryLoadResult load() {
    final String? raw;
    try {
      raw = _prefs.getString(key);
    } catch (_) {
      return _unreadable();
    }
    if (raw == null) return const RegistryLoadResult(devices: []);
    try {
      final data = jsonDecode(raw);
      if (data is! Map) throw const FormatException('not an object');
      final version = data['schemaVersion'];
      if (version is! int || version < 1) {
        throw const FormatException('invalid schema version');
      }
      if (version > schemaVersion) {
        return RegistryLoadResult(
          devices: const [],
          warning: 'Saved devices use newer schema $version; left untouched',
          preserved: true,
        );
      }
      final list = data['devices'];
      if (list is! List) throw const FormatException('no device list');
      final devices = <SavedDevice>[];
      final seen = <String>{};
      var skipped = 0;
      for (final item in list) {
        final device = _decode(item);
        if (device == null || !seen.add(device.identity.id)) {
          skipped++;
        } else {
          devices.add(device);
        }
      }
      return RegistryLoadResult(
        devices: devices,
        warning: skipped == 0
            ? null
            : '$skipped saved device(s) were unreadable and skipped',
      );
    } catch (_) {
      return _unreadable();
    }
  }

  /// Writes [devices], unless unreadable data is stored (then nothing is
  /// written and [RegistrySaveResult.refusal] says so).
  Future<RegistrySaveResult> save(Iterable<SavedDevice> devices) async {
    final existing = load();
    if (existing.preserved) {
      return RegistrySaveResult(written: false, refusal: existing.warning);
    }
    final secrets = <String>[];
    final unsupported = <String>[];
    final byId = <String, SavedDevice>{};
    for (final d in devices) {
      byId[d.identity.id] = d;
    }
    final encoded = [
      for (final d in byId.values) _encode(d, secrets, unsupported),
    ];
    final ok = await _prefs.setString(
      key,
      jsonEncode({'schemaVersion': schemaVersion, 'devices': encoded}),
    );
    return RegistrySaveResult(
      written: ok,
      droppedSecretKeys: secrets,
      droppedUnsupported: unsupported,
      refusal: ok ? null : 'Storage write failed',
    );
  }

  RegistryLoadResult _unreadable() => const RegistryLoadResult(
    devices: [],
    warning: 'Saved devices are unreadable; left untouched',
    preserved: true,
  );

  Map<String, Object?> _encode(
    SavedDevice d,
    List<String> secrets,
    List<String> unsupported,
  ) {
    final i = d.identity;
    final config = _sanitize(
      d.configuration?.values ?? const <String, Object?>{},
      i.id,
      secrets,
      unsupported,
    );
    return {
      'id': i.id,
      'manufacturer': i.manufacturer,
      'model': i.model,
      'interfaceType': i.interfaceType.name,
      'transport': i.transport.name,
      'serialNumber': i.serialNumber,
      'firmwareVersion': i.firmwareVersion,
      'ipAddress': i.ipAddress,
      'port': i.port,
      'systemId': i.systemId,
      'displayName': i.displayName,
      'backendId': d.backendId,
      'configuration': config,
    };
  }

  SavedDevice? _decode(Object? item) {
    if (item is! Map) return null;
    try {
      final id = item['id'];
      final manufacturer = item['manufacturer'];
      final model = item['model'];
      if (id is! String || id.isEmpty) return null;
      if (manufacturer is! String || model is! String) return null;
      final interfaceName = item['interfaceType'];
      final transportName = item['transport'];
      if (interfaceName is! String || transportName is! String) return null;
      final identity = DeviceIdentity(
        id: id,
        manufacturer: manufacturer,
        model: model,
        interfaceType: DeviceInterfaceType.values.byName(interfaceName),
        transport: DeviceTransport.values.byName(transportName),
        serialNumber: _optional<String>(item['serialNumber']),
        firmwareVersion: _optional<String>(item['firmwareVersion']),
        ipAddress: _optional<String>(item['ipAddress']),
        port: _optional<int>(item['port']),
        systemId: _optional<String>(item['systemId']),
        displayName: _optional<String>(item['displayName']),
      );
      final cfg = item['configuration'];
      var values = const <String, Object?>{};
      if (cfg != null) {
        if (cfg is! Map) return null;
        // Strips secrets that an older or hand-edited file may contain.
        values = _sanitize(cfg, '', <String>[], <String>[]);
      }
      return SavedDevice(
        identity: identity,
        backendId: _optional<String>(item['backendId']),
        configuration: DeviceConfiguration(values),
      );
    } catch (_) {
      return null;
    }
  }

  static T? _optional<T>(Object? value) {
    if (value == null) return null;
    if (value is T) return value as T;
    throw const FormatException('wrong field type');
  }

  /// Copies [map] keeping only JSON-safe values and no secret-looking keys.
  /// Dropped paths are added to [secrets] or [unsupported]; values never are.
  Map<String, Object?> _sanitize(
    Map<Object?, Object?> map,
    String path,
    List<String> secrets,
    List<String> unsupported,
  ) {
    final out = <String, Object?>{};
    for (final e in map.entries) {
      final k = e.key;
      if (k is! String) {
        unsupported.add('$path/<non-text key>');
        continue;
      }
      final childPath = path.isEmpty ? k : '$path/$k';
      if (isSecretKey(k)) {
        secrets.add(childPath);
        continue;
      }
      final clean = _sanitizeValue(e.value, childPath, secrets, unsupported);
      if (!identical(clean, _omit)) out[k] = clean;
    }
    return out;
  }

  Object? _sanitizeValue(
    Object? value,
    String path,
    List<String> secrets,
    List<String> unsupported,
  ) {
    if (value == null || value is bool || value is String) return value;
    if (value is num) {
      if (value is double && !value.isFinite) {
        unsupported.add(path);
        return _omit;
      }
      return value;
    }
    if (value is List) {
      final out = <Object?>[];
      for (var n = 0; n < value.length; n++) {
        final clean = _sanitizeValue(
          value[n],
          '$path[$n]',
          secrets,
          unsupported,
        );
        if (!identical(clean, _omit)) out.add(clean);
      }
      return out;
    }
    if (value is Map) return _sanitize(value, path, secrets, unsupported);
    unsupported.add(path);
    return _omit;
  }
}
