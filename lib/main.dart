// Boots the elseplane application and owns its root theme state.
// Used as the Flutter entry point for the canvas editor.

import 'package:elseplane/canvas/editor/canvas_page.dart';
import 'package:elseplane/canvas/persistence/attachments/store.dart';
import 'package:elseplane/canvas/persistence/canvas_document_store.dart';
import 'package:elseplane/canvas/persistence/canvas_project_files.dart';
import 'package:elseplane/feature_flags.dart';
import 'package:elseplane/theme/starless.dart';
import 'package:elseplane/theme/theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------- Theme preference ----------

const themePreferenceKey = 'elseplane.theme.mode';
const surfaceStylePreferenceKey = 'elseplane.surface.style';

Future<SurfaceStyle> loadSurfaceStyle(SharedPreferencesAsync preferences) async {
  try {
    return await preferences.getString(surfaceStylePreferenceKey) == 'solid' ? SurfaceStyle.solid : SurfaceStyle.glass;
  } on Object {
    return SurfaceStyle.glass;
  }
}

Future<ThemeMode> loadThemeMode(SharedPreferencesAsync preferences) async {
  try {
    return await preferences.getString(themePreferenceKey) == 'light' ? ThemeMode.light : ThemeMode.dark;
  } on Object {
    return ThemeMode.dark;
  }
}

// ---------- Application bootstrap ----------

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

// ---------- Root application ----------

/// Hosts the canvas editor under the application theme.
/// Used as the root widget created by the application bootstrap.
class ElseplaneApp extends StatefulWidget {
  const ElseplaneApp({
    this.initialThemeMode = ThemeMode.dark,
    this.initialSurfaceStyle = SurfaceStyle.glass,
    this.preferences,
    this.attachmentStore,
    this.documentStore,
    this.projectFiles,
    super.key,
  });

  final ThemeMode initialThemeMode;
  final SurfaceStyle initialSurfaceStyle;
  final SharedPreferencesAsync? preferences;
  final AttachmentStore? attachmentStore;
  final CanvasDocumentStore? documentStore;
  final CanvasProjectFiles? projectFiles;

  @override
  State<ElseplaneApp> createState() => _ElseplaneAppState();
}

class _ElseplaneAppState extends State<ElseplaneApp> {
  // ---------- State and persistence ----------

  late ThemeMode _themeMode = FeatureFlags.themeSelection ? widget.initialThemeMode : ThemeMode.dark;
  late SurfaceStyle _surfaceStyle = FeatureFlags.surfaceStyleSelection
      ? widget.initialSurfaceStyle
      : SurfaceStyle.glass;
  late final SharedPreferencesAsync _preferences = widget.preferences ?? SharedPreferencesAsync();
  Future<void> _saveQueue = Future<void>.value();

  Future<void> _setThemeMode(ThemeMode mode) {
    setState(() => _themeMode = mode);
    final save = _saveQueue.then((_) => _preferences.setString(themePreferenceKey, mode.name));
    _saveQueue = save.catchError((Object _) {});
    return save;
  }

  Future<void> _setSurfaceStyle(SurfaceStyle style) {
    setState(() => _surfaceStyle = style);
    final save = _saveQueue.then((_) => _preferences.setString(surfaceStylePreferenceKey, style.name));
    _saveQueue = save.catchError((Object _) {});
    return save;
  }

  ThemeData _styledTheme(ThemeData theme) => theme.copyWith(
    extensions: [theme.extension<BTheme>()!.copyWith(surfaceStyle: _surfaceStyle)],
  );

  // ---------- Rendering ----------

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'elseplane',
      debugShowCheckedModeBanner: false,
      theme: _styledTheme(starlessLightThemeData),
      darkTheme: _styledTheme(starlessDarkThemeData),
      themeMode: _themeMode,
      builder: (context, child) => Theme(
        data: _styledTheme(Theme.of(context)),
        child: child!,
      ),
      home: CanvasPage(
        attachmentStore: widget.attachmentStore,
        documentStore: widget.documentStore,
        projectFiles: widget.projectFiles,
        themeMode: _themeMode,
        onThemeModeChanged: FeatureFlags.themeSelection ? _setThemeMode : null,
        onSurfaceStyleChanged: FeatureFlags.surfaceStyleSelection ? _setSurfaceStyle : null,
      ),
    );
  }
}
