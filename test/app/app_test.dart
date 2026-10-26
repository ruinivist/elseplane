// Verifies app-wide theme switching, storage, and failure handling.
// Exercises settings through the root app without changing canvas content.

import 'package:elseplane/app/app.dart';
import 'package:elseplane/app/feature_flags.dart';
import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/editor/canvas_page.dart';
import 'package:elseplane/canvas/editor/elements/code/code_element_view.dart';
import 'package:elseplane/canvas/editor/elements/text/text_element_view.dart';
import 'package:elseplane/settings/settings_dialog.dart';
import 'package:elseplane/theme/fonts.dart';
import 'package:elseplane/theme/theme.dart';
import 'package:elseplane/ui/common/glass_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_lazy_grid/infinite_lazy_grid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_web/shared_preferences_web.dart';

import '../canvas/test_helpers.dart';

// ---------- Tests ----------

void main() {
  setUp(() async {
    SharedPreferencesAsyncWeb.registerWith(null);
    await SharedPreferencesAsync().remove(themePreferenceKey);
    await SharedPreferencesAsync().remove(surfaceStylePreferenceKey);
  });
  tearDown(() async {
    await SharedPreferencesAsync().remove(themePreferenceKey);
    await SharedPreferencesAsync().remove(surfaceStylePreferenceKey);
  });

  testWidgets('appearance flags guard root state, callbacks, and settings independently', (tester) async {
    await tester.pumpWidget(
      ElseplaneApp(
        initialThemeMode: ThemeMode.light,
        initialSurfaceStyle: SurfaceStyle.solid,
        libraryStore: TestLibraryStore(),
      ),
    );
    await tester.pumpAndSettle();
    final page = tester.widget<CanvasPage>(find.byType(CanvasPage));
    final context = tester.element(find.byType(CanvasPage));
    expect(Theme.of(context).brightness, FeatureFlags.themeSelection ? Brightness.light : Brightness.dark);
    expect(
      BTheme.of(context).surfaceStyle,
      FeatureFlags.surfaceStyleSelection ? SurfaceStyle.solid : SurfaceStyle.glass,
    );
    expect(page.onThemeModeChanged, FeatureFlags.themeSelection ? isNotNull : isNull);
    expect(page.onSurfaceStyleChanged, FeatureFlags.surfaceStyleSelection ? isNotNull : isNull);

    await tester.tap(find.byKey(const ValueKey('settings-button')));
    await tester.pumpAndSettle();
    if (FeatureFlags.themeSelection || FeatureFlags.surfaceStyleSelection) {
      await tester.tap(find.text('Appearance').last);
      await tester.pumpAndSettle();
    } else {
      expect(find.text('Appearance'), findsNothing);
    }
    expect(find.byKey(const ValueKey('theme-select')), FeatureFlags.themeSelection ? findsOneWidget : findsNothing);
    expect(
      find.byKey(const ValueKey('surface-style-select')),
      FeatureFlags.surfaceStyleSelection ? findsOneWidget : findsNothing,
    );
  });

  testWidgets('new users start dark and glass', (tester) async {
    final preferences = SharedPreferencesAsync();
    expect(await loadThemeMode(preferences), ThemeMode.dark);
    expect(await loadSurfaceStyle(preferences), SurfaceStyle.glass);
    await preferences.setString(themePreferenceKey, 'unknown');
    await preferences.setString(surfaceStylePreferenceKey, 'unknown');
    expect(await loadThemeMode(preferences), ThemeMode.dark);
    expect(await loadSurfaceStyle(preferences), SurfaceStyle.glass);
    final unavailable = _FailingPreferences(() => true);
    expect(await loadThemeMode(unavailable), ThemeMode.dark);
    expect(await loadSurfaceStyle(unavailable), SurfaceStyle.glass);
    await tester.pumpWidget(ElseplaneApp(libraryStore: TestLibraryStore()));
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(CanvasPage));
    expect(Theme.of(context).brightness, Brightness.dark);
    expect(BTheme.of(context).surfaceStyle, SurfaceStyle.glass);
  });

  testWidgets('theme switches live, persists, and keeps canvas content fixed', (tester) async {
    final preferences = SharedPreferencesAsync();
    expect(await loadThemeMode(preferences), ThemeMode.dark);
    await preferences.setString(themePreferenceKey, 'unknown');
    expect(await loadThemeMode(preferences), ThemeMode.dark);

    final store = TestLibraryStore(
      CanvasDocument(
        background: CanvasBackgroundKind.dotGrid,
        elements: [
          TextElementData(
            id: 'fixed-color',
            position: const Offset(80, 140),
            width: 420,
            height: 108,
            markdown: 'Fixed content color',
            style: const TextNodeStyle(fontFamily: 'Source Serif 4', color: Color(0xff201C1A)),
          ),
          TextElementData(
            id: 'theme-color',
            position: const Offset(80, 270),
            width: 420,
            height: 108,
            markdown: '# Themed heading\nBody',
            style: const TextNodeStyle(fontFamily: defaultFontFamily),
          ),
        ],
      ),
    );
    await tester.pumpWidget(
      ElseplaneApp(
        initialThemeMode: ThemeMode.light,
        initialSurfaceStyle: SurfaceStyle.solid,
        preferences: preferences,
        libraryStore: store,
      ),
    );
    await tester.pumpAndSettle();
    final canvasState = tester.state(find.byType(CanvasPage));
    final controller = tester.widget<LazyCanvas>(find.byType(LazyCanvas)).controller;
    final models = tester.widgetList<TextElementView>(find.byType(TextElementView)).map((widget) => widget.resources);
    final text = models.singleWhere((model) => model.node.id == 'fixed-color');
    final themedText = models.singleWhere((model) => model.node.id == 'theme-color');
    final originalContent = text.node.toJson();
    final originalThemedContent = themedText.node.toJson();
    MarkdownStyleSheet themedStyles() => tester
        .widgetList<MarkdownBody>(find.byType(MarkdownBody))
        .singleWhere((widget) => widget.data == themedText.node.markdown)
        .styleSheet!;
    final lightStyles = themedStyles();

    await _openAppearance(tester);
    expect(_brightness(tester), Brightness.light);
    await _selectTheme(tester, 'Dark');
    expect(_brightness(tester), Brightness.dark);
    expect(await preferences.getString(themePreferenceKey), 'dark');
    expect(tester.state(find.byType(CanvasPage)), same(canvasState));
    expect(tester.widget<LazyCanvas>(find.byType(LazyCanvas)).controller, same(controller));
    expect(text.node.toJson(), originalContent);
    expect(themedText.node.toJson(), originalThemedContent);
    final colors = BTheme.of(tester.element(find.byType(CanvasPage))).colors;
    expect(themedStyles().p!.color, colors.textPrimary);
    expect(themedStyles().h1!.color, colors.textHeading);
    expect(themedStyles().p!.color, isNot(lightStyles.p!.color));
    expect(store.persisted, isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      ElseplaneApp(initialThemeMode: await loadThemeMode(preferences), preferences: preferences, libraryStore: store),
    );
    await tester.pumpAndSettle();
    expect(Theme.of(tester.element(find.byType(CanvasPage))).brightness, Brightness.dark);
    await _openAppearance(tester);
    await _selectTheme(tester, 'Light');
    expect(_brightness(tester), Brightness.light);
    expect(await loadThemeMode(preferences), ThemeMode.light);
  }, skip: !FeatureFlags.themeSelection);

  testWidgets('surface style defaults, switches live, and reloads without changing canvas state', (tester) async {
    final preferences = SharedPreferencesAsync();
    expect(await loadSurfaceStyle(preferences), SurfaceStyle.glass);
    await preferences.setString(surfaceStylePreferenceKey, 'unknown');
    expect(await loadSurfaceStyle(preferences), SurfaceStyle.glass);
    final store = TestLibraryStore(
      CanvasDocument(
        background: CanvasBackgroundKind.dotGrid,
        elements: [
          TextElementData(
            id: 'text',
            position: const Offset(80, 140),
            width: 420,
            height: 108,
            markdown: 'Content',
            style: const TextNodeStyle(fontFamily: 'Source Serif 4', color: Color(0xff201C1A)),
          ),
        ],
      ),
    );
    await tester.pumpWidget(
      ElseplaneApp(
        initialThemeMode: ThemeMode.light,
        initialSurfaceStyle: SurfaceStyle.solid,
        preferences: preferences,
        libraryStore: store,
      ),
    );
    await tester.pumpAndSettle();
    final state = tester.state(find.byType(CanvasPage));
    final canvas = tester.widget<LazyCanvas>(find.byType(LazyCanvas)).controller;
    final model = tester.widget<TextElementView>(find.byType(TextElementView)).resources..setSelected(value: true);
    final original = model.data.toJson();
    await _openAppearance(tester);
    expect(_surfaceStyle(tester), SurfaceStyle.solid);
    await _selectSurfaceStyle(tester, 'Glass');
    expect(_surfaceStyle(tester), SurfaceStyle.glass);
    expect(find.descendant(of: find.byType(SettingsDialog), matching: find.byType(GlassSurface)), findsOneWidget);
    expect(await preferences.getString(surfaceStylePreferenceKey), 'glass');
    expect(tester.state(find.byType(CanvasPage)), same(state));
    expect(tester.widget<LazyCanvas>(find.byType(LazyCanvas)).controller, same(canvas));
    expect(tester.widget<TextElementView>(find.byType(TextElementView)).resources, same(model));
    expect(model.data.toJson(), original);
    expect(model.selected, isTrue);
    expect(store.persisted, isNull);
    if (FeatureFlags.themeSelection) await _selectTheme(tester, 'Dark');
    expect(_surfaceStyle(tester), SurfaceStyle.glass);
    expect(_brightness(tester), Brightness.dark);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      ElseplaneApp(
        initialSurfaceStyle: await loadSurfaceStyle(preferences),
        preferences: preferences,
        libraryStore: store,
      ),
    );
    await tester.pumpAndSettle();
    await _openAppearance(tester);
    expect(_surfaceStyle(tester), SurfaceStyle.glass);
    await _selectSurfaceStyle(tester, 'Solid');
    expect(_surfaceStyle(tester), SurfaceStyle.solid);
    expect(await loadSurfaceStyle(preferences), SurfaceStyle.solid);
    expect(find.descendant(of: find.byType(SettingsDialog), matching: find.byType(GlassSurface)), findsNothing);
  }, skip: !FeatureFlags.surfaceStyleSelection);

  for (final tool in ['text', 'code']) {
    testWidgets('new $tool backgrounds follow live surface style without changing existing blocks', (tester) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final store = TestLibraryStore();
      await tester.pumpWidget(ElseplaneApp(libraryStore: store));
      await tester.pumpAndSettle();

      Future<void> place(Offset position) async {
        await tester.tap(
          find.descendant(of: find.byKey(ValueKey('toolbar-$tool')), matching: find.byType(TextButton)),
        );
        await tester.pumpAndSettle();
        await tester.tapAt(position);
        await tester.pumpAndSettle();
        await pumpPastSave(tester);
      }

      List<BlockBackgroundKind> backgrounds() => tool == 'text'
          ? tester
                .widgetList<TextElementView>(find.byType(TextElementView))
                .map((widget) => widget.resources.style.background)
                .toList()
          : tester
                .widgetList<CodeElementView>(find.byType(CodeElementView))
                .map((widget) => widget.resources.background)
                .toList();

      await place(const Offset(100, 200));
      expect(backgrounds(), [BlockBackgroundKind.glass]);
      if (FeatureFlags.surfaceStyleSelection) {
        await _openAppearance(tester);
        await _selectSurfaceStyle(tester, 'Solid');
        await tester.tap(find.byKey(const ValueKey('settings-close')));
        await tester.pumpAndSettle();
      }
      await place(const Offset(800, 200));
      const secondBackground = FeatureFlags.surfaceStyleSelection
          ? BlockBackgroundKind.card
          : BlockBackgroundKind.glass;
      expect(backgrounds(), [BlockBackgroundKind.glass, secondBackground]);
      if (FeatureFlags.surfaceStyleSelection) {
        await _openAppearance(tester);
        await _selectSurfaceStyle(tester, 'Glass');
        await tester.tap(find.byKey(const ValueKey('settings-close')));
        await tester.pumpAndSettle();
      }
      await place(const Offset(100, 750));
      final expected = [BlockBackgroundKind.glass, secondBackground, BlockBackgroundKind.glass];
      expect(backgrounds(), expected);
      final saved = CanvasDocument.fromJson(store.persisted!.toJson());
      expect(
        saved.elements.map(
          (element) => switch (element) {
            TextElementData(:final style) => style.background,
            CodeElementData(:final background) => background,
            _ => throw StateError('Unexpected element'),
          },
        ),
        expected,
      );
    });
  }

  testWidgets('surface storage failure retains the live style and permits later saves', (tester) async {
    var fail = true;
    final preferences = _FailingPreferences(() => fail);
    expect(await loadSurfaceStyle(preferences), SurfaceStyle.glass);
    await tester.pumpWidget(
      ElseplaneApp(
        initialThemeMode: ThemeMode.light,
        initialSurfaceStyle: SurfaceStyle.solid,
        preferences: preferences,
        libraryStore: TestLibraryStore(),
      ),
    );
    await tester.pumpAndSettle();
    await _openAppearance(tester);
    await _selectSurfaceStyle(tester, 'Glass');
    expect(_surfaceStyle(tester), SurfaceStyle.glass);
    expect(find.text('Could not save surface style preference.'), findsOneWidget);
    fail = false;
    await _selectSurfaceStyle(tester, 'Solid');
    expect(await preferences.getString(surfaceStylePreferenceKey), 'solid');
  }, skip: !FeatureFlags.surfaceStyleSelection);

  testWidgets('storage failure keeps the chosen theme and allows a later save', (tester) async {
    var fail = true;
    final preferences = _FailingPreferences(() => fail);
    expect(await loadThemeMode(preferences), ThemeMode.dark);
    await tester.pumpWidget(
      ElseplaneApp(
        initialThemeMode: ThemeMode.light,
        initialSurfaceStyle: SurfaceStyle.solid,
        preferences: preferences,
        libraryStore: TestLibraryStore(),
      ),
    );
    await tester.pumpAndSettle();
    await _openAppearance(tester);
    await _selectTheme(tester, 'Dark');
    expect(_brightness(tester), Brightness.dark);
    expect(find.text('Could not save theme preference.'), findsOneWidget);

    fail = false;
    await _selectTheme(tester, 'Light');
    expect(await preferences.getString(themePreferenceKey), 'light');
  }, skip: !FeatureFlags.themeSelection);
}

// ---------- Helpers ----------

Brightness _brightness(WidgetTester tester) => Theme.of(tester.element(find.byType(SettingsDialog))).brightness;

Future<void> _openAppearance(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('settings-button')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Appearance').last);
  await tester.pumpAndSettle();
}

Future<void> _selectTheme(WidgetTester tester, String label) async {
  await tester.tap(find.descendant(of: find.byKey(const ValueKey('theme-select')), matching: find.byType(TextButton)));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

class _FailingPreferences extends SharedPreferencesAsync {
  _FailingPreferences(this.shouldFail);

  final bool Function() shouldFail;

  @override
  Future<String?> getString(String key) async {
    if (shouldFail()) throw StateError('Storage unavailable');
    return await super.getString(key);
  }

  @override
  Future<void> setString(String key, String value) async {
    if (shouldFail()) throw StateError('Storage unavailable');
    await super.setString(key, value);
  }
}

SurfaceStyle _surfaceStyle(WidgetTester tester) => BTheme.of(tester.element(find.byType(SettingsDialog))).surfaceStyle;

Future<void> _selectSurfaceStyle(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byKey(const ValueKey('surface-style-select')), matching: find.byType(TextButton)),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}
