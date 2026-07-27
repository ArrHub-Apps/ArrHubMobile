import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:workmanager/workmanager.dart';

import 'models/server_config.dart';

import 'screens/discover_screen.dart';
import 'screens/library_screen.dart';
import 'screens/queue_screen.dart';
import 'screens/settings_screen.dart';
import 'services/cert_pinning.dart';
import 'services/notification_service.dart';
import 'services/settings_store.dart';
import 'services/update_service.dart';
import 'state/app_state.dart';
import 'widgets/app_update.dart';

/// WorkManager entry point — runs in a background isolate on a ~15 min
/// cadence to check for finished downloads. The isolate has its own memory,
/// so cert pinning + trusted fingerprints must be re-established here too.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    CertPinning.install();
    final store = SettingsStore();
    for (final type in ServerType.values) {
      CertPinning.add((await store.load(type))?.certFingerprint);
    }
    try {
      await NotificationService.checkForCompletedDownloads();
    } catch (_) {}
    return true;
  });
}

const _downloadCheckTask = 'download-complete-check';

Future<void> configureBackgroundChecks(bool enabled) async {
  if (enabled) {
    await Workmanager().registerPeriodicTask(
      _downloadCheckTask,
      _downloadCheckTask,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
  } else {
    await Workmanager().cancelByUniqueName(_downloadCheckTask);
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  CertPinning.install();
  // DAN-17: mobile_scanner and workmanager (via workmanager_android) both apply
  // the Kotlin Gradle Plugin directly, which is deprecated and will eventually
  // fail Flutter builds — see
  // https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-app-developers
  // Checked upstream as of this build: mobile_scanner is pinned to the latest
  // 7.x (7.2.0) and workmanager to the latest 0.9.0+3 (federated, backed by
  // workmanager_android); neither's changelog documents a Built-in-Kotlin
  // migration yet. Nothing to change in this app until one ships — re-check
  // both changelogs periodically, and if a while passes with no movement,
  // raise it as an issue with the plugin authors (mobile_scanner:
  // github.com/juliansteenbakker/mobile_scanner, workmanager:
  // github.com/fluttercommunity/flutter_workmanager).
  Workmanager().initialize(callbackDispatcher);
  final store = SettingsStore();
  // Baseline the import history on launch so we never notify for things
  // that finished long ago, and catch up while the app is open.
  store.loadNotificationsEnabled().then((enabled) {
    if (enabled) NotificationService.checkForCompletedDownloads();
  });
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => RadarrState(store)..init()),
        ChangeNotifierProvider(create: (_) => SonarrState(store)..init()),
        ChangeNotifierProvider(create: (_) => TmdbState(store)..init()),
        ChangeNotifierProvider(create: (_) => ThemeState()..init()),
      ],
      child: const ArrHubApp(),
    ),
  );
}

class ArrHubApp extends StatelessWidget {
  const ArrHubApp({super.key});

  ThemeData _buildTheme(Color accent, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final onAccent =
        accent.computeLuminance() > 0.4 ? Colors.black : Colors.white;
    final background = isDark ? Colors.black : const Color(0xFFFAFAFA);
    final surface = isDark ? const Color(0xFF121212) : Colors.white;
    final placeholder =
        isDark ? const Color(0xFF222222) : const Color(0xFFE2E2E2);
    final outline =
        isDark ? const Color(0xFF3E3E3E) : const Color(0xFFB9B9B9);
    final onBackground = isDark ? Colors.white : const Color(0xFF161616);
    final unselected = isDark ? Colors.white70 : Colors.black54;

    final base =
        isDark ? const ColorScheme.dark() : const ColorScheme.light();
    final scheme = base.copyWith(
      primary: accent,
      onPrimary: onAccent,
      secondary: accent,
      onSecondary: onAccent,
      secondaryContainer: accent,
      onSecondaryContainer: onAccent,
      surface: background,
      onSurface: onBackground,
      surfaceContainerHighest: placeholder,
      outline: outline,
    );
    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: onBackground,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme:
          CardThemeData(color: surface, surfaceTintColor: Colors.transparent),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        showDragHandle: true,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: background,
        indicatorColor: accent,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            // Selected icon matches the scaffold: black pill-icon in dark
            // mode, white in light mode.
            color: states.contains(WidgetState.selected)
                ? background
                : unselected,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 12,
            color:
                states.contains(WidgetState.selected) ? accent : unselected,
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: accent,
        foregroundColor: onAccent,
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: accent,
          side: BorderSide(color: accent),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: accent),
      ),
      inputDecorationTheme: InputDecorationTheme(
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: accent, width: 2),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeState = context.watch<ThemeState>();
    return MaterialApp(
      title: 'ArrHub',
      debugShowCheckedModeBanner: false,
      themeMode: themeState.mode,
      theme: _buildTheme(themeState.accent, Brightness.light),
      darkTheme: _buildTheme(themeState.accent, Brightness.dark),
      home: const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    // Best-effort update check on launch. Notify only — a SnackBar points the user
    // at the download/install sheet; nothing downloads or installs on its own
    // (Settings → App updates is the explicit path). Runs after first frame so it
    // never blocks startup, and swallows failures (offline, no release yet).
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdate());
  }

  Future<void> _checkForUpdate() async {
    try {
      final update = await UpdateService.checkForUpdate();
      if (update == null || !mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Update available: ArrHub ${update.version}'),
          duration: const Duration(seconds: 8),
          action: SnackBarAction(
            label: 'Update',
            onPressed: () => showAppUpdateSheet(context, update),
          ),
        ),
      );
    } catch (_) {
      // Swallow — the Settings card surfaces errors when the user checks explicitly.
    }
  }

  @override
  Widget build(BuildContext context) {
    final radarr = context.watch<RadarrState>();
    final sonarr = context.watch<SonarrState>();
    // Discover only appears once TMDB is set up — whether the key was entered manually in
    // Settings or adopted from a desktop pairing. Without one it's just an empty prompt, so
    // the whole tab is hidden until a key exists.
    final showDiscover = context.watch<TmdbState>().isConfigured;

    final tabs = <_TabDef>[
      _TabDef('Movies', Icons.movie_outlined, Icons.movie, LibraryScreen(state: radarr)),
      _TabDef('TV Shows', Icons.tv_outlined, Icons.tv, LibraryScreen(state: sonarr)),
      if (showDiscover)
        _TabDef('Discover', Icons.explore_outlined, Icons.explore, const DiscoverScreen()),
      _TabDef('Queue', Icons.download_outlined, Icons.download, const QueueScreen()),
      _TabDef('Settings', Icons.settings_outlined, Icons.settings, const SettingsScreen()),
    ];
    // Clamp: the visible tab count changes when Discover is toggled, so a previously
    // selected index can fall out of range.
    final tab = _tab.clamp(0, tabs.length - 1);

    return Scaffold(
      appBar: AppBar(title: Text(tabs[tab].title)),
      body: IndexedStack(
        index: tab,
        children: [for (final t in tabs) t.page],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          for (final t in tabs)
            NavigationDestination(
              icon: Icon(t.icon),
              selectedIcon: Icon(t.selectedIcon),
              label: t.title,
            ),
        ],
      ),
    );
  }
}

/// One bottom-navigation tab: its label, icons, and page.
class _TabDef {
  final String title;
  final IconData icon;
  final IconData selectedIcon;
  final Widget page;
  const _TabDef(this.title, this.icon, this.selectedIcon, this.page);
}
