// Verifies settings navigation, editing, and project transfer actions.
// Exercises the settings dialog under responsive widget layouts.

import 'dart:async';

import 'package:elseplane/settings/settings_dialog.dart';
import 'package:elseplane/theme/starless.dart';
import 'package:elseplane/theme/theme.dart';
import 'package:elseplane/ui/common/select.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

// ---------- Tests ----------

void main() {
  const gitSha = String.fromEnvironment('GIT_SHA');

  testWidgets('about links identify the build', (tester) async {
    final originalLauncher = UrlLauncherPlatform.instance;
    final launcher = _FakeUrlLauncher();
    UrlLauncherPlatform.instance = launcher;
    addTearDown(() => UrlLauncherPlatform.instance = originalLauncher);

    await _openCanvasSettings(
      tester,
      onImport: () async => true,
      onExport: () async => true,
    );
    await tester.tap(find.text('About'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('elseplane logo'), findsOneWidget);
    expect(find.text('elseplane'), findsOneWidget);
    expect(tester.takeException(), isNull);

    final github = find.widgetWithText(TextButton, 'GitHub');
    await tester.tap(github);
    await tester.pumpAndSettle();
    expect(launcher.launched, ['https://github.com/ruinivist/elseplane']);

    if (gitSha.isEmpty) {
      expect(find.text('Development build'), findsOneWidget);
    } else {
      final build = find.text('Build ${gitSha.length < 7 ? gitSha : gitSha.substring(0, 7)}');
      await tester.tap(build);
      await tester.pumpAndSettle();
      expect(launcher.launched.last, 'https://github.com/ruinivist/elseplane/commit/$gitSha');

      launcher.succeeds = false;
      await tester.tap(build);
      await tester.pumpAndSettle();
      expect(_dialogText('Could not open link'), findsOneWidget);
    }

    launcher.succeeds = false;
    await tester.tap(github);
    await tester.pumpAndSettle();
    expect(_dialogText('Could not open link'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);

    launcher.succeeds = true;
    await tester.tap(github);
    await tester.pumpAndSettle();
    expect(_dialogText('Could not open link'), findsNothing);
  });

  for (final themeEnabled in [false, true]) {
    for (final surfaceEnabled in [false, true]) {
      testWidgets('appearance follows callbacks with theme $themeEnabled and surface $surfaceEnabled', (tester) async {
        ThemeMode? chosenTheme;
        SurfaceStyle? chosenSurface;
        await _openCanvasSettings(
          tester,
          onImport: () async => true,
          onExport: () async => true,
          onThemeModeChanged: themeEnabled ? (mode) async => chosenTheme = mode : null,
          onSurfaceStyleChanged: surfaceEnabled ? (style) async => chosenSurface = style : null,
        );
        if (!themeEnabled && !surfaceEnabled) {
          expect(find.text('Appearance'), findsNothing);
          return;
        }
        await tester.tap(find.text('Appearance').last);
        await tester.pumpAndSettle();
        final theme = find.byKey(const ValueKey('theme-select'));
        final surface = find.byKey(const ValueKey('surface-style-select'));
        expect(theme, themeEnabled ? findsOneWidget : findsNothing);
        expect(surface, surfaceEnabled ? findsOneWidget : findsNothing);
        if (themeEnabled) tester.widget<Select<ThemeMode>>(theme).onChanged!(ThemeMode.dark);
        if (surfaceEnabled) tester.widget<Select<SurfaceStyle>>(surface).onChanged!(SurfaceStyle.solid);
        await tester.pumpAndSettle();
        expect(chosenTheme, themeEnabled ? ThemeMode.dark : null);
        expect(chosenSurface, surfaceEnabled ? SurfaceStyle.solid : null);
      });
    }
  }

  testWidgets('Appearance reports save failures inline and ignores superseded failures', (tester) async {
    final firstThemeSave = Completer<void>();
    var themeSaves = 0;
    var failSurface = true;
    await _openCanvasSettings(
      tester,
      onImport: () async => false,
      onExport: () async => false,
      onThemeModeChanged: (_) async {
        final attempt = ++themeSaves;
        if (attempt == 1) await firstThemeSave.future;
        if (attempt == 3) throw StateError('Theme save failed');
      },
      onSurfaceStyleChanged: (_) async {
        if (failSurface) throw StateError('Surface save failed');
      },
    );
    await tester.tap(find.text('Appearance').last);
    await tester.pumpAndSettle();
    final changeTheme = tester.widget<Select<ThemeMode>>(find.byKey(const ValueKey('theme-select'))).onChanged!;
    final changeSurface = tester
        .widget<Select<SurfaceStyle>>(
          find.byKey(const ValueKey('surface-style-select')),
        )
        .onChanged!;
    final themeError = _dialogText('Could not save theme preference.');
    final surfaceError = _dialogText('Could not save surface style preference.');

    changeTheme(ThemeMode.dark);
    changeTheme(ThemeMode.light);
    changeSurface(SurfaceStyle.solid);
    firstThemeSave.completeError(StateError('Superseded theme save failed'));
    await tester.pumpAndSettle();
    expect(themeError, findsNothing);
    expect(surfaceError, findsOneWidget);

    changeTheme(ThemeMode.dark);
    await tester.pumpAndSettle();
    expect(themeError, findsOneWidget);
    expect(surfaceError, findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);

    failSurface = false;
    changeSurface(SurfaceStyle.solid);
    changeTheme(ThemeMode.dark);
    await tester.pumpAndSettle();
    expect(themeError, findsNothing);
    expect(surfaceError, findsNothing);
  });

  testWidgets(
    'transfer actions stay disabled until an export completes',
    (tester) async {
      final exportCompleted = Completer<bool>();
      var exportCalls = 0;

      await _openCanvasSettings(
        tester,
        onImport: () async => true,
        onExport: () {
          exportCalls++;
          return exportCompleted.future;
        },
      );

      expect(
        find.byKey(const ValueKey('canvas-import-button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('canvas-export-button')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('library-export-button')), findsOneWidget);
      expect(find.text('Import'), findsOneWidget);
      expect(find.text('Export current canvas'), findsOneWidget);
      expect(find.text('Export library'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('canvas-export-button')));
      await tester.pump();

      expect(exportCalls, 1);
      expect(_button(tester, 'canvas-import-button').onPressed, isNull);
      expect(_button(tester, 'canvas-export-button').onPressed, isNull);
      expect(_button(tester, 'library-export-button').onPressed, isNull);
      expect(_dialogText('Canvas exported'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('canvas-export-button')));
      await tester.pump();
      expect(exportCalls, 1);

      exportCompleted.complete(true);
      await tester.pumpAndSettle();

      expect(find.byType(SettingsDialog), findsOneWidget);
      expect(_dialogText('Canvas exported'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    },
  );

  testWidgets('export failure stays inline and a canceled retry is silent', (tester) async {
    var fail = true;
    await _openCanvasSettings(
      tester,
      onImport: () async => false,
      onExport: () async {
        if (fail) throw StateError('Export failed');
        return false;
      },
    );
    final export = find.byKey(const ValueKey('library-export-button'));
    await tester.tap(export);
    await tester.pumpAndSettle();
    expect(_dialogText('Could not export library'), findsOneWidget);
    expect(_dialogText('Library exported'), findsNothing);
    expect(_button(tester, 'library-export-button').onPressed, isNotNull);
    expect(find.byType(SnackBar), findsNothing);

    fail = false;
    await tester.tap(export);
    await tester.pumpAndSettle();
    expect(find.byType(SettingsDialog), findsOneWidget);
    expect(_dialogText('Could not export library'), findsNothing);
    expect(_dialogText('Library exported'), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('import closes Settings only when the callback succeeds', (tester) async {
    var imported = true;
    var importCalls = 0;

    Future<bool> onImport() async {
      importCalls++;
      return imported;
    }

    await _openCanvasSettings(
      tester,
      onImport: onImport,
      onExport: () async => true,
    );

    await tester.tap(find.byKey(const ValueKey('canvas-import-button')));
    await tester.pumpAndSettle();

    expect(importCalls, 1);
    expect(find.byType(SettingsDialog), findsNothing);

    imported = false;
    await _openCanvasSettings(
      tester,
      onImport: onImport,
      onExport: () async => true,
    );
    await tester.tap(find.byKey(const ValueKey('canvas-import-button')));
    await tester.pumpAndSettle();

    expect(importCalls, 2);
    expect(find.byType(SettingsDialog), findsOneWidget);
  });

  testWidgets('Data actions stay reachable in narrow dark Settings', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var exports = 0;
    await _openCanvasSettings(
      tester,
      theme: starlessDarkThemeData,
      onImport: () async => false,
      onExport: () async {
        exports++;
        return true;
      },
    );

    expect(find.byKey(const ValueKey('canvas-import-button')).hitTestable(), findsOneWidget);
    expect(find.byKey(const ValueKey('canvas-export-button')).hitTestable(), findsOneWidget);
    final exportLibrary = find.byKey(const ValueKey('library-export-button'));
    expect(exportLibrary.hitTestable(), findsOneWidget);
    await tester.tap(exportLibrary);
    await tester.pumpAndSettle();

    expect(exports, 1);
    expect(_dialogText('Library exported'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('export feedback scrolls into view in short Settings', (tester) async {
    await tester.binding.setSurfaceSize(const Size(280, 310));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _openCanvasSettings(
      tester,
      onImport: () async => false,
      onExport: () async => throw StateError('Export failed'),
    );
    final export = find.byKey(const ValueKey('canvas-export-button'));
    await Scrollable.ensureVisible(
      tester.element(export),
      alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
    );
    await tester.pumpAndSettle();
    expect(export.hitTestable(), findsOneWidget);
    await tester.tap(export);
    await tester.pumpAndSettle();

    expect(_dialogText('Could not export canvas').hitTestable(), findsOneWidget);
  });
}

ButtonStyleButton _button(WidgetTester tester, String key) => tester.widget(find.byKey(ValueKey(key)));

Finder _dialogText(String text) => find.descendant(of: find.byType(SettingsDialog), matching: find.text(text));

// ---------- Test helpers ----------

Future<void> _openCanvasSettings(
  WidgetTester tester, {
  required Future<bool> Function() onImport,
  required Future<bool> Function() onExport,
  ThemeData? theme,
  Future<void> Function(ThemeMode)? onThemeModeChanged,
  Future<void> Function(SurfaceStyle)? onSurfaceStyleChanged,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? starlessLightThemeData,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            key: const ValueKey('open-settings-button'),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => SettingsDialog(
                onImport: onImport,
                onExportCanvas: onExport,
                onExportLibrary: onExport,
                onThemeModeChanged: onThemeModeChanged,
                onSurfaceStyleChanged: onSurfaceStyleChanged,
              ),
            ),
            child: const Text('Open settings'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('open-settings-button')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Canvas').last);
  await tester.pumpAndSettle();
}

class _FakeUrlLauncher extends UrlLauncherPlatform {
  final launched = <String>[];
  bool succeeds = true;

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add(url);
    return succeeds;
  }
}
