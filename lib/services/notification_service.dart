import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/arr_api.dart';
import '../models/server_config.dart';
import 'settings_store.dart';

/// Shows "download complete" notifications. The check itself is driven by
/// a WorkManager periodic task (see main.dart) and also runs on app open.
class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    _initialized = true;
  }

  static Future<bool> requestPermission() async {
    await init();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    return await android?.requestNotificationsPermission() ?? false;
  }

  static Future<void> _show(int id, String title, String body) async {
    await init();
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'downloads',
          'Download complete',
          channelDescription:
              'Notifies when Radarr/Sonarr finish importing a download',
          importance: Importance.defaultImportance,
        ),
      ),
    );
  }

  /// Compares each server's import history against the last-seen
  /// timestamp and notifies for anything new. Safe to call from the
  /// WorkManager background isolate.
  static Future<void> checkForCompletedDownloads() async {
    final store = SettingsStore();
    final prefs = await SharedPreferences.getInstance();
    for (final type in ServerType.values) {
      final config = await store.load(type);
      if (config == null || !config.isConfigured) continue;
      final api = ArrApi(config);
      try {
        final imports = await api.recentImports();
        if (imports.isEmpty) continue;
        final prefsKey = 'last_import_check_${type.name}';
        final lastSeenRaw = prefs.getString(prefsKey);
        final newest = imports.first.$1;
        await prefs.setString(prefsKey, newest.toIso8601String());
        if (lastSeenRaw == null) continue; // first run: baseline only
        final lastSeen = DateTime.tryParse(lastSeenRaw);
        if (lastSeen == null) continue;
        for (final (date, title) in imports) {
          if (date.isAfter(lastSeen)) {
            await _show(
              date.millisecondsSinceEpoch ~/ 1000,
              'Download complete',
              title,
            );
          }
        }
      } catch (_) {
        // Server unreachable (e.g. away from home) — try again next cycle.
      } finally {
        api.dispose();
      }
    }
  }
}
