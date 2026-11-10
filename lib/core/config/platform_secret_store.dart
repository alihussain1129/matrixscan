import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'app_config.dart';

/// Secret storage backed by the operating system's credential facility
/// (Linux Secret Service/libsecret, Windows credential storage, Android
/// Keystore). It never falls back to plaintext files.
class PlatformSecretStore implements SecretStore {
  PlatformSecretStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) async {
    if (key.trim().isEmpty) {
      throw ArgumentError.value(key, 'key', 'must not be blank');
    }
    if (value.isEmpty) {
      // Never echo the value into the error.
      throw ArgumentError('secret value must not be empty');
    }
    await _storage.write(key: key, value: value);
  }

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Tests override this with an in-memory store.
final secretStoreProvider = Provider<SecretStore>(
  (ref) => PlatformSecretStore(),
);
