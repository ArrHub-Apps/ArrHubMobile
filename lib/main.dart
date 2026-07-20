import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:workmanager/workmanager.dart';

import 'screens/discover_screen.dart';
import 'screens/library_screen.dart';
import 'screens/queue_screen.dart';
import 'screens/settings_screen.dart';
import 'services/notification_service.dart';
import 'services/settings_store.dart';
import 'state/app_state.dart';

/// Debug-only: the dev PC's antivirus (AVG) re-signs HTTPS traffic, which
/// breaks external requests (TMDB) from the emulator. Never active in
/// release builds.
class _DevHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (cert, host, port) => true;
  }
}

/// WorkManager entry point — runs in a background isolate on a ~15 min
/// cadence to check for finished downloads.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
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
  if (kDebugMode) HttpOverrides.global = _DevHttpOverrides();
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
      child: const MediaManagerApp(),
    ),
  );
}

class MediaManagerApp extends StatelessWidget {
  const MediaManagerApp({super.key});

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
      title: 'Home Media',
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
  Widget build(BuildContext context) {
    final radarr = context.watch<RadarrState>();
    final sonarr = context.watch<SonarrState>();

    final pages = [
      LibraryScreen(state: radarr),
      LibraryScreen(state: sonarr),
      const DiscoverScreen(),
      const QueueScreen(),
      const SettingsScreen(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(switch (_tab) {
          0 => 'Movies',
          1 => 'TV Shows',
          2 => 'Discover',
          3 => 'Queue',
          _ => 'Settings',
        }),
      ),
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.movie_outlined),
            selectedIcon: Icon(Icons.movie),
            label: 'Movies',
          ),
          NavigationDestination(
            icon: Icon(Icons.tv_outlined),
            selectedIcon: Icon(Icons.tv),
            label: 'TV Shows',
          ),
          NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore),
            label: 'Discover',
          ),
          NavigationDestination(
            icon: Icon(Icons.download_outlined),
            selectedIcon: Icon(Icons.download),
            label: 'Queue',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
