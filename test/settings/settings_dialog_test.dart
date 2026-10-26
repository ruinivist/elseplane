// Verifies settings navigation, editing, and project transfer actions.
// Exercises the settings dialog under responsive widget layouts.

import 'dart:async';

import 'package:elseplane/settings/settings_dialog.dart';
import 'package:elseplane/theme/starless.dart';
import 'package:elseplane/theme/theme.dart';
import 'package:elseplane/ui/common/select.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
      onExport: () async {},
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
      await tester.tap(find.text('Build ${gitSha.substring(0, 7)}'));
      await tester.pumpAndSettle();
      expect(launcher.launched.last, 'https://github.com/ruinivist/elseplane/commit/$gitSha');
    }

    launcher.succeeds = false;
    await tester.tap(github);
    await tester.pumpAndSettle();
    expect(find.text('Could not open link'), findsOneWidget);
  });

  for (final themeEnabled in [false, true]) {
    for (final surfaceEnabled in [false, true]) {
      testWidgets('appearance follows callbacks with theme $themeEnabled and surface $surfaceEnabled', (tester) async {
        ThemeMode? chosenTheme;
        SurfaceStyle? chosenSurface;
        await _openCanvasSettings(
          tester,
          onImport: () async => true,
          onExport: () async {},
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

  testWidgets(
    'export disables both actions until it completes',
    (tester) async {
      final exportCompleted = Completer<void>();
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
      expect(find.text('Import canvas'), findsOneWidget);
      expect(find.text('Export canvas'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('canvas-export-button')));
      await tester.pump();

      expect(exportCalls, 1);
      expect(_button(tester, 'canvas-import-button').onPressed, isNull);
      expect(_button(tester, 'canvas-export-button').onPressed, isNull);

      await tester.tap(find.byKey(const ValueKey('canvas-export-button')));
      await tester.pump();
      expect(exportCalls, 1);

      exportCompleted.complete();
      await tester.pumpAndSettle();

      expect(find.byType(SettingsDialog), findsOneWidget);
    },
  );

  testWidgets('import closes only when the callback succeeds', (tester) async {
    var imported = true;
    var importCalls = 0;

    Future<bool> onImport() async {
      importCalls++;
      return imported;
    }

    await _openCanvasSettings(
      tester,
      onImport: onImport,
      onExport: () async {},
    );

    await tester.tap(find.byKey(const ValueKey('canvas-import-button')));
    await tester.pumpAndSettle();

    expect(importCalls, 1);
    expect(find.byType(SettingsDialog), findsNothing);

    imported = false;
    await _openCanvasSettings(
      tester,
      onImport: onImport,
      onExport: () async {},
    );
    await tester.tap(find.byKey(const ValueKey('canvas-import-button')));
    await tester.pumpAndSettle();

    expect(importCalls, 2);
    expect(find.byType(SettingsDialog), findsOneWidget);
  });
}

TextButton _button(WidgetTester tester, String key) => tester.widget<TextButton>(find.byKey(ValueKey(key)));

// ---------- Test helpers ----------

Future<void> _openCanvasSettings(
  WidgetTester tester, {
  required Future<bool> Function() onImport,
  required Future<void> Function() onExport,
  Future<void> Function(ThemeMode)? onThemeModeChanged,
  Future<void> Function(SurfaceStyle)? onSurfaceStyleChanged,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: starlessLightThemeData,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            key: const ValueKey('open-settings-button'),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => SettingsDialog(
                onImportCanvas: onImport,
                onExportCanvas: onExport,
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
