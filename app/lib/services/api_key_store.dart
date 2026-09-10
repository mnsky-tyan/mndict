import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Minimal key/value seam over flutter_secure_storage so tests can swap in
/// an in-memory backend instead of the Android Keystore plugin.
abstract class KeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Android-Keystore-backed storage (flutter_secure_storage, minSdk 23).
class SecureKeyValueStore implements KeyValueStore {
  final FlutterSecureStorage _storage;

  SecureKeyValueStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// The user's Gemini API key (bring-your-own). The key never leaves the
/// secure store except to be sent as the x-goog-api-key header.
class ApiKeyStore {
  static const String _storageKey = 'gemini_api_key';

  final KeyValueStore _store;

  ApiKeyStore({KeyValueStore? store}) : _store = store ?? SecureKeyValueStore();

  Future<String?> read() async {
    // Any storage failure reads as "no key": the app's contract is
    // "API key or get out", never a crash loop.
    try {
      final trimmed = (await _store.read(_storageKey))?.trim() ?? '';
      return trimmed.isEmpty ? null : trimmed;
    } catch (_) {
      return null;
    }
  }

  Future<void> save(String key) => _store.write(_storageKey, key.trim());

  Future<void> delete() => _store.delete(_storageKey);

  /// Masked display: only the last 4 characters stay readable.
  static String mask(String key) {
    final trimmed = key.trim();
    if (trimmed.length <= 4) return '••••$trimmed';
    return '••••••••••••${trimmed.substring(trimmed.length - 4)}';
  }
}
