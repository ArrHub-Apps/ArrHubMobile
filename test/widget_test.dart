// Smoke test: the app boots with empty (mocked) storage and renders its shell.
//
// The default flutter-create counter test is replaced — ArrHub has no counter. The
// providers read from FlutterSecureStorage (SettingsStore) and SharedPreferences
// (ThemeState), both mocked here so init() resolves against empty stores.
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:media_manager/main.dart';
import 'package:media_manager/services/settings_store.dart';
import 'package:media_manager/state/app_state.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('boots to the shell with the bottom navigation', (tester) async {
    final store = SettingsStore();
    await tester.pumpWidget(
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
    await tester.pumpAndSettle();

    // Bottom navigation destinations that are always present.
    expect(find.text('Movies'), findsWidgets);
    expect(find.text('Settings'), findsWidgets);
  });
}
