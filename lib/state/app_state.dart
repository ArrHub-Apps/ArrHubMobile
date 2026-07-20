import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/arr_api.dart';
import '../api/tmdb_api.dart';
import '../models/media_item.dart';
import '../models/server_config.dart';
import '../services/settings_store.dart';

/// Per-service (Radarr or Sonarr) state: config + library cache.
class ServiceState extends ChangeNotifier {
  final ServerType type;
  final SettingsStore _store;

  ServerConfig? _config;
  ArrApi? _api;
  List<MediaItem> _library = [];
  Set<int> _queueIds = {};
  bool _loading = false;
  String? _error;

  ServiceState(this.type, this._store);

  ServerConfig? get config => _config;
  ArrApi? get api => _api;
  List<MediaItem> get library => _library;
  bool get loading => _loading;
  String? get error => _error;
  bool get isConfigured => _config?.isConfigured ?? false;

  Future<void> init() async {
    _config = await _store.load(type);
    if (isConfigured) {
      _api = ArrApi(_config!);
      // Show the last-known library immediately; refresh in the background
      // so a slow server never blanks the UI.
      await _loadCache();
      await refreshLibrary();
    } else {
      notifyListeners();
    }
  }

  MediaItem _toItem(Map<String, dynamic> json) => type == ServerType.radarr
      ? MediaItem.movie(json, _config!.normalizedUrl, _config!.apiKey)
      : MediaItem.series(json, _config!.normalizedUrl, _config!.apiKey);

  Future<File> _cacheFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/library_${type.name}.json');
  }

  Future<void> _loadCache() async {
    try {
      final file = await _cacheFile();
      if (!await file.exists()) return;
      final list = jsonDecode(await file.readAsString()) as List<dynamic>;
      if (_library.isEmpty) {
        _library = list
            .map((e) => _toItem(e as Map<String, dynamic>))
            .toList();
        notifyListeners();
      }
    } catch (_) {} // cache is best-effort
  }

  Future<void> _saveCache() async {
    try {
      final file = await _cacheFile();
      await file
          .writeAsString(jsonEncode(_library.map((m) => m.raw).toList()));
    } catch (_) {}
  }

  Future<void> updateConfig(ServerConfig config) async {
    await _store.save(config);
    _config = config;
    _api?.dispose();
    _api = config.isConfigured ? ArrApi(config) : null;
    _library = [];
    _error = null;
    notifyListeners();
    if (_api != null) await refreshLibrary();
  }

  /// Status for a library item, taking the download queue into account.
  MediaStatus statusFor(MediaItem item) {
    if (_queueIds.contains(item.id)) return MediaStatus.downloading;
    if (item.downloaded) return MediaStatus.downloaded;
    return item.monitored ? MediaStatus.wanted : MediaStatus.unmonitored;
  }

  /// Toggles monitoring on the server and patches the cached library
  /// entry in place, so the grid updates without a full refresh.
  Future<void> setMonitored(MediaItem item, bool monitored) async {
    await _api!.setMonitored(item, monitored);
    final raw = Map<String, dynamic>.from(item.raw)..['monitored'] = monitored;
    final i = _library.indexWhere((m) => m.id == item.id);
    if (i != -1) _library[i] = _toItem(raw);
    notifyListeners();
    unawaited(_saveCache());
  }

  Future<void> refreshLibrary() async {
    final api = _api;
    if (api == null) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final library = api.getLibrary();
      // Queue failures shouldn't take down the library view.
      final queue = api.getQueueIds().catchError((_) => <int>{});
      _library = await library;
      _queueIds = await queue;
      unawaited(_saveCache());
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _api?.dispose();
    super.dispose();
  }
}

/// Distinct types so Provider can expose both services simultaneously.
class RadarrState extends ServiceState {
  RadarrState(SettingsStore store) : super(ServerType.radarr, store);
}

class SonarrState extends ServiceState {
  SonarrState(SettingsStore store) : super(ServerType.sonarr, store);
}

/// Theme preferences: accent color and light/dark/system mode.
class ThemeState extends ChangeNotifier {
  static const _accentKey = 'accent_color';
  static const _modeKey = 'theme_mode';
  static const defaultAccent = Color(0xFF1DB954);

  Color accent = defaultAccent;
  ThemeMode mode = ThemeMode.dark;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final accentValue = prefs.getInt(_accentKey);
    if (accentValue != null) accent = Color(accentValue);
    final modeName = prefs.getString(_modeKey);
    mode = ThemeMode.values.firstWhere(
      (m) => m.name == modeName,
      orElse: () => ThemeMode.dark,
    );
    notifyListeners();
  }

  Future<void> setAccent(Color color) async {
    accent = color;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_accentKey, color.toARGB32());
  }

  Future<void> setMode(ThemeMode newMode) async {
    mode = newMode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_modeKey, newMode.name);
  }
}

/// Holds the TMDB API key + client for the Discover tab.
class TmdbState extends ChangeNotifier {
  final SettingsStore _store;

  String? _apiKey;
  TmdbApi? _api;

  TmdbState(this._store);

  String? get apiKey => _apiKey;
  TmdbApi? get api => _api;
  bool get isConfigured => (_apiKey ?? '').isNotEmpty;

  Future<void> init() async {
    _apiKey = await _store.loadTmdbApiKey();
    if (isConfigured) _api = TmdbApi(_apiKey!);
    notifyListeners();
  }

  Future<void> updateApiKey(String apiKey) async {
    await _store.saveTmdbApiKey(apiKey);
    _apiKey = apiKey;
    _api?.dispose();
    _api = apiKey.isEmpty ? null : TmdbApi(apiKey);
    notifyListeners();
  }

  @override
  void dispose() {
    _api?.dispose();
    super.dispose();
  }
}
