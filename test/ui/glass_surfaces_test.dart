// Verifies shared glass rendering and native menu and dialog behavior.
// Exercises exterior shadows, navigation, scrolling, dismissal, and confirmation.

import 'package:elseplane/theme/starless.dart';
import 'package:elseplane/theme/theme.dart';
import 'package:elseplane/ui/common/context_menu.dart';
import 'package:elseplane/ui/common/glass_surface.dart';
import 'package:elseplane/ui/common/menu_surface.dart';
import 'package:elseplane/ui/common/select.dart';
import 'package:elseplane/ui/common/surface_dialog.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------- Tests ----------

void main() {
  for (final kind in ['dropdown', 'searchable', 'context']) {
    for (final count in [2, 30]) {
      testWidgets('$kind menu with $count items contains pointer scrolling', (tester) async {
        var ancestorScrolls = 0;
        final controller = MenuController();
        final options = [for (var i = 0; i < count; i++) SelectOption(value: i, label: 'Option $i')];
        final menu = switch (kind) {
          'dropdown' => Select<int>(value: 0, options: options, onChanged: (_) {}),
          'searchable' => SearchableSelect<int>(value: 0, options: options, searchHint: 'Search', onChanged: (_) {}),
          _ => ContextMenu(
            controller: controller,
            groups: [
              [
                for (var i = 0; i < count; i++)
                  ContextMenuAction(label: 'Option $i', icon: Icons.copy, onPressed: () {}),
              ],
            ],
            child: const SizedBox(width: 20, height: 20),
          ),
        };
        await tester.pumpWidget(
          Listener(
            onPointerSignal: (event) {
              if (event is PointerScrollEvent) {
                GestureBinding.instance.pointerSignalResolver.register(event, (_) => ancestorScrolls++);
              }
            },
            child: _app(menu),
          ),
        );
        if (kind == 'context') {
          controller.open();
        } else {
          await tester.tap(find.byKey(ValueKey(kind == 'dropdown' ? 'select-trigger' : 'searchable-select-trigger')));
        }
        await tester.pumpAndSettle();

        final surface = find.byType(MenuSurface);
        final scrollable = find.descendant(of: surface, matching: find.byType(Scrollable)).last;
        final position = tester.state<ScrollableState>(scrollable).position;
        final point = tester.getCenter(scrollable);
        await _wheel(tester, point, const Offset(0, -60));
        expect(position.pixels, position.minScrollExtent);
        position.jumpTo(position.maxScrollExtent);
        await tester.pump();
        await _wheel(tester, point, const Offset(0, 60));
        expect(position.pixels, position.maxScrollExtent);
        await _wheel(tester, point, const Offset(60, 0));
        await _wheel(
          tester,
          tester.getTopLeft(surface) + Offset(tester.getSize(surface).width / 2, 2),
          const Offset(0, 60),
        );
        await _wheel(tester, point, const Offset(0, -60));
        if (count == 30) expect(position.pixels, lessThan(position.maxScrollExtent));

        if (kind == 'searchable') {
          final search = find.byKey(const ValueKey('searchable-select-search'));
          await tester.enterText(search, 'missing option');
          await tester.pumpAndSettle();
          await _wheel(tester, tester.getCenter(search), const Offset(0, 60));
          await _wheel(tester, tester.getCenter(find.text('No results')), const Offset(0, -60));
        }
        expect(ancestorScrolls, 0);
        await tester.sendEventToBinding(
          const PointerScrollEvent(position: Offset(780, 580), scrollDelta: Offset(0, 60)),
        );
        await tester.pumpAndSettle();
        expect(ancestorScrolls, 1);
      });
    }
  }

  testWidgets('large glass keeps its center undarkened while casting an exterior shadow', (tester) async {
    final disabledShadows = debugDisableShadows;
    debugDisableShadows = false;
    try {
      final boundaryKey = GlobalKey();
      for (final theme in [starlessLightThemeData, starlessDarkThemeData]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: RepaintBoundary(
              key: boundaryKey,
              child: ColoredBox(
                color: const Color(0xffb0b0b0),
                child: Stack(
                  children: [
                    const Positioned(
                      left: 50,
                      top: 50,
                      child: GlassSurface(child: SizedBox(width: 300, height: 300)),
                    ),
                    Positioned(
                      left: 450,
                      top: 50,
                      child: Material(
                        color: theme.extension<BTheme>()!.colors.glassSurface,
                        child: const SizedBox(width: 300, height: 300),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(boundaryKey));
        final pixels = await tester.runAsync(() async {
          final image = await boundary.toImage();
          try {
            return (await image.toByteData())!;
          } finally {
            image.dispose();
          }
        });
        final width = boundary.size.width.toInt();
        int channel(int x, int y, int c) => pixels!.getUint8((y * width + x) * 4 + c);
        for (var c = 0; c < 3; c++) {
          expect(channel(200, 200, c), closeTo(channel(600, 200, c), 1), reason: '${theme.brightness}: interior');
          expect(channel(42, 200, c), lessThan(channel(10, 200, c)), reason: '${theme.brightness}: exterior');
        }
      }
    } finally {
      debugDisableShadows = disabledShadows;
    }
  }, skip: !kIsWeb);

  for (final searchable in [false, true]) {
    testWidgets('${searchable ? 'searchable' : 'plain'} dropdown supports keyboard opening and dismissal', (
      tester,
    ) async {
      int? selected;
      final options = [for (var i = 0; i < 3; i++) SelectOption(value: i, label: 'Option $i')];
      await tester.pumpWidget(
        _app(
          searchable
              ? SearchableSelect<int>(value: 0, options: options, searchHint: 'Search', onChanged: (v) => selected = v)
              : Select<int>(value: 0, options: options, onChanged: (v) => selected = v),
        ),
      );
      final trigger = find.byKey(ValueKey(searchable ? 'searchable-select-trigger' : 'select-trigger'));
      final focus = tester.widget<TextButton>(trigger).focusNode!..requestFocus();
      await tester.pump();
      for (final key in [
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.enter,
        LogicalKeyboardKey.space,
      ]) {
        await tester.sendKeyEvent(key);
        await tester.pumpAndSettle();
        expect(find.byType(MenuSurface), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byType(MenuSurface), findsNothing);
        expect(focus.hasFocus, isTrue);
        expect(selected, isNull);
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      if (!searchable) await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(selected, 0);
      expect(find.byType(MenuSurface), findsNothing);
      expect(focus.hasFocus, isTrue);
    });

    testWidgets('${searchable ? 'searchable' : 'plain'} disabled dropdown stays closed', (tester) async {
      const options = [SelectOption(value: 0, label: 'Option')];
      await tester.pumpWidget(
        _app(
          searchable
              ? const SearchableSelect<int>(value: 0, options: options, searchHint: 'Search', onChanged: null)
              : const Select<int>(value: 0, options: options, onChanged: null),
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byType(MenuSurface), findsNothing);
    });
  }

  testWidgets('hovering searchable results preserves typing and keyboard navigation', (tester) async {
    int? selected;
    await tester.pumpWidget(
      _app(
        SearchableSelect<int>(
          value: 0,
          searchHint: 'Search',
          options: [
            for (var i = 0; i < 30; i++) SelectOption(value: i, label: 'Option ${i.toString().padLeft(2, '0')}'),
          ],
          onChanged: (value) => selected = value,
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('searchable-select-trigger')));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(700, 500));
    await mouse.moveTo(tester.getCenter(find.text('Option 02')));
    await tester.pumpAndSettle();
    final search = find.byKey(const ValueKey('searchable-select-search'));
    expect(tester.widget<TextField>(search).focusNode!.hasFocus, isTrue);
    expect(selected, isNull);
    await tester.enterText(search, 'Option 2');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(selected, 21);
    expect(find.byType(MenuSurface), findsNothing);
    await mouse.removePointer();
  });

  testWidgets('search keyboard navigation reveals results in a short viewport', (tester) async {
    tester.view.physicalSize = const Size(800, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    int? selected;
    await tester.pumpWidget(
      _app(
        SearchableSelect<int>(
          value: 0,
          searchHint: 'Search',
          options: [
            for (var i = 0; i < 30; i++) SelectOption(value: i, label: 'Option ${i.toString().padLeft(2, '0')}'),
          ],
          onChanged: (value) => selected = value,
        ),
      ),
    );
    final trigger = find.byKey(const ValueKey('searchable-select-trigger'));
    await tester.tap(trigger);
    await tester.pumpAndSettle();
    for (var i = 0; i < 7; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('searchable-select-option-$i')).hitTestable(), findsOneWidget);
    }
    final surfaceBounds = tester.getRect(find.byType(MenuSurface));
    final optionBounds = tester.getRect(find.byKey(const ValueKey('searchable-select-option-6')));
    expect(surfaceBounds.contains(optionBounds.topLeft), isTrue);
    expect(surfaceBounds.contains(optionBounds.bottomRight), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(selected, 6);
    await tester.tap(trigger);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(find.text('Option 29').hitTestable(), findsOneWidget);
    final search = find.byKey(const ValueKey('searchable-select-search'));
    expect(search.hitTestable(), findsOneWidget);
    expect(tester.widget<TextField>(search).focusNode!.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(selected, 29);
  });

  testWidgets('search arrows retain typing focus, reveal offscreen results, and reset on filtering', (tester) async {
    int? selected;
    await tester.pumpWidget(
      _app(
        SearchableSelect<int>(
          value: 0,
          options: [
            for (var i = 0; i < 30; i++) SelectOption(value: i, label: 'Option ${i.toString().padLeft(2, '0')}'),
          ],
          searchHint: 'Search',
          onChanged: (value) => selected = value,
        ),
      ),
    );
    final trigger = find.byKey(const ValueKey('searchable-select-trigger'));
    await tester.tap(trigger);
    await tester.pumpAndSettle();
    final search = find.byKey(const ValueKey('searchable-select-search'));
    final searchFocus = tester.widget<TextField>(search).focusNode!;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
    for (var i = 0; i < 29; i++) {
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(searchFocus.hasFocus, isTrue);
    expect(find.text('Option 29').hitTestable(), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(selected, 29);

    await tester.tap(trigger);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(find.text('Option 29').hitTestable(), findsOneWidget);
    await tester.enterText(search, 'Option 1');
    await tester.pumpAndSettle();
    expect(searchFocus.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(selected, 10);

    await tester.tap(trigger);
    await tester.pumpAndSettle();
    await tester.enterText(search, 'Option 2');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(selected, 20);

    await tester.tap(trigger);
    await tester.pumpAndSettle();
    await tester.enterText(search, 'Option 1');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
    await tester.pumpAndSettle();
    expect(selected, 11);

    await tester.tap(trigger);
    await tester.pumpAndSettle();
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'Option 1',
        selection: TextSelection.collapsed(offset: 8),
        composing: TextRange(start: 0, end: 8),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(selected, 11);
    expect(searchFocus.hasFocus, isTrue);
    await tester.enterText(search, 'Option 1');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(selected, 10);

    await tester.tap(trigger);
    await tester.pumpAndSettle();
    await tester.enterText(search, 'no match');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('No results'), findsOneWidget);
    expect(selected, 10);
    expect(searchFocus.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(MenuSurface), findsNothing);
  });

  testWidgets('glass dropdown retains keyboard selection, bounded scrolling, and dismissal', (tester) async {
    var selected = 0;
    await tester.pumpWidget(
      _app(
        Select<int>(
          value: selected,
          options: [for (var i = 0; i < 30; i++) SelectOption(value: i, label: 'Option $i')],
          onChanged: (value) => selected = value,
        ),
      ),
    );
    final trigger = find.byKey(const ValueKey('select-trigger'));
    await tester.tap(trigger);
    await tester.pumpAndSettle();
    expect(find.byType(GlassSurface), findsOneWidget);
    final filter = tester.widget<BackdropFilter>(find.byType(BackdropFilter));
    expect(filter.backdropGroupKey, isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(selected, 1);
    expect(find.byType(MenuSurface), findsNothing);
    await tester.tap(trigger);
    await tester.pumpAndSettle();
    final scroll = find.descendant(of: find.byType(MenuSurface), matching: find.byType(SingleChildScrollView));
    await tester.drag(scroll, const Offset(0, -1500));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Option 29'));
    await tester.pumpAndSettle();
    expect(selected, 29);
    await tester.tap(trigger);
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(780, 580));
    await tester.pumpAndSettle();
    expect(find.byType(MenuSurface), findsNothing);
  });

  testWidgets('glass searchable menu filters, scrolls, and preserves focus', (tester) async {
    var selected = 0;
    await tester.pumpWidget(
      _app(
        SearchableSelect<int>(
          value: selected,
          searchHint: 'Search languages',
          options: [
            for (var i = 0; i < 30; i++) SelectOption(value: i, label: 'Language ${i.toString().padLeft(2, '0')}'),
          ],
          onChanged: (value) => selected = value,
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('searchable-select-trigger')));
    await tester.pumpAndSettle();
    final search = find.byKey(const ValueKey('searchable-select-search'));
    expect(tester.widget<TextField>(search).focusNode!.hasFocus, isTrue);
    final list = find.byType(ListView);
    await tester.drag(list, const Offset(0, -1500));
    await tester.pumpAndSettle();
    expect(find.text('Language 29'), findsOneWidget);
    await tester.enterText(search, 'Language 12');
    await tester.pumpAndSettle();
    expect(find.byType(MenuItemButton), findsOneWidget);
    await tester.tap(find.byType(MenuItemButton));
    await tester.pumpAndSettle();
    expect(selected, 12);
    expect(search, findsNothing);
  });

  testWidgets('glass context submenus and narrow confirmations retain native actions', (tester) async {
    var called = false;
    final controller = MenuController();
    await tester.pumpWidget(
      _app(
        ContextMenu(
          controller: controller,
          groups: [
            [
              ContextMenuAction(
                label: 'Arrange',
                icon: Icons.layers,
                groups: [
                  [ContextMenuAction(label: 'Bring forward', icon: Icons.arrow_upward, onPressed: () => called = true)],
                ],
              ),
            ],
          ],
          child: const SizedBox(width: 20, height: 20),
        ),
      ),
    );
    controller.open();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Arrange'));
    await tester.pumpAndSettle();
    expect(find.byType(GlassSurface), findsNWidgets(2));
    await _wheel(tester, tester.getCenter(find.text('Bring forward')), const Offset(0, 60));
    await tester.tap(find.text('Bring forward'));
    await tester.pumpAndSettle();
    expect(called, isTrue);
    expect(controller.isOpen, isFalse);

    tester.view.physicalSize = const Size(360, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    bool? result;
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showDialog<bool>(
                context: context,
                builder: (context) => SurfaceConfirmationDialog(
                  title: const Text('Replace canvas?'),
                  content: const Text('Replace the active canvas with the imported canvas.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                    TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Replace')),
                  ],
                ),
              );
            },
            child: const Text('Confirm'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(find.byType(GlassSurface), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Replace'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });
}

// ---------- Harness ----------

Future<void> _wheel(WidgetTester tester, Offset position, Offset delta) async {
  bool? platformDefault;
  await tester.sendEventToBinding(
    PointerScrollEvent(
      position: position,
      scrollDelta: delta,
      onRespond: ({required allowPlatformDefault}) => platformDefault = allowPlatformDefault,
    ),
  );
  await tester.pumpAndSettle();
  expect(platformDefault, isFalse);
}

Widget _app(Widget child) => MaterialApp(
  theme: starlessLightThemeData.copyWith(
    extensions: [starlessLightThemeData.extension<BTheme>()!.copyWith(surfaceStyle: SurfaceStyle.glass)],
  ),
  home: Scaffold(
    body: Align(alignment: Alignment.topLeft, child: child),
  ),
);
