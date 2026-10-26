// Initializes Flutter and starts the application.
// App composition and root appearance state belong to app/app.dart.

import 'package:elseplane/app/app.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) await BrowserContextMenu.disableContextMenu();
  LicenseRegistry.addLicense(() async* {
    final license = await rootBundle.loadString('assets/fonts/jetbrains-mono/OFL.txt');
    yield LicenseEntryWithLineBreaks(['JetBrains Mono'], license);
  });
  final preferences = SharedPreferencesAsync();
  runApp(
    ElseplaneApp(
      initialThemeMode: await loadThemeMode(preferences),
      initialSurfaceStyle: await loadSurfaceStyle(preferences),
      preferences: preferences,
    ),
  );
}
