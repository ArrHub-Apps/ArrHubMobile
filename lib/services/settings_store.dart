import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/server_config.dart';

/// Persists server configs (URL + API key) in Android's encrypted storage.
class SettingsStore {
  static const _storage = FlutterSecureStorage();

  static String _key(ServerType type) => 'server_config_${type.name}';

  Future<ServerConfig?> load(ServerType type) async {
    final raw = await _storage.read(key: _key(type));
    try {
      return ServerConfig.decode(raw);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(ServerConfig config) =>
      _storage.write(key: _key(config.type), value: config.encode());

  Future<void> clear(ServerType type) => _storage.delete(key: _key(type));

  static const _tmdbKey = 'tmdb_api_key';

  Future<String?> loadTmdbApiKey() => _storage.read(key: _tmdbKey);

  Future<void> saveTmdbApiKey(String apiKey) =>
      _storage.write(key: _tmdbKey, value: apiKey);

  static const _notificationsKey = 'notifications_enabled';

  Future<bool> loadNotificationsEnabled() async =>
      await _storage.read(key: _notificationsKey) == 'true';

  Future<void> saveNotificationsEnabled(bool enabled) =>
      _storage.write(key: _notificationsKey, value: '$enabled');
}
