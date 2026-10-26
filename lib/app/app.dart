// Composes application dependencies, root UI, and appearance preferences.
// Created by the Flutter entry point; Workspace connects feature lifetimes.

import 'package:elseplane/app/feature_flags.dart';
import 'package:elseplane/app/workspace.dart';
import 'package:elseplane/attachments/attachment_store.dart';
import 'package:elseplane/attachments/attachment_store_web.dart';
import 'package:elseplane/library/library_store.dart';
import 'package:elseplane/library/transfer/canvas_project_files.dart';
import 'package:elseplane/theme/starless.dart';
import 'package:elseplane/theme/theme.dart';
import 'package:flutter/material.dart';
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

// ---------- Root application ----------

/// Hosts the canvas editor under the application theme.
/// Used as the root widget created by the application bootstrap.
class ElseplaneApp extends StatefulWidget {
  const ElseplaneApp({
    this.initialThemeMode = ThemeMode.dark,
    this.initialSurfaceStyle = SurfaceStyle.glass,
    this.preferences,
    this.attachmentStore,
    this.libraryStore,
    this.projectFiles,
    super.key,
  });

  final ThemeMode initialThemeMode;
  final SurfaceStyle initialSurfaceStyle;
  final SharedPreferencesAsync? preferences;
  final AttachmentStore? attachmentStore;
  final LibraryStore? libraryStore;
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
  late final LibraryStore _libraryStore = widget.libraryStore ?? PreferencesLibraryStore();
  late final AttachmentStore _attachmentStore = widget.attachmentStore ?? PlatformAttachmentStore();
  late final CanvasProjectFiles _projectFiles = widget.projectFiles ?? createCanvasProjectFiles();

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
      home: Workspace(
        attachmentStore: _attachmentStore,
        libraryStore: _libraryStore,
        projectFiles: _projectFiles,
        themeMode: _themeMode,
        onThemeModeChanged: FeatureFlags.themeSelection ? _setThemeMode : null,
        onSurfaceStyleChanged: FeatureFlags.surfaceStyleSelection ? _setSurfaceStyle : null,
      ),
    );
  }
}
