// Verifies native menu and dialog behavior with shared glass surfaces.
// Exercises keyboard navigation, scrolling, dismissal, and confirmation actions.

import 'package:elseplane/theme/starless.dart';
import 'package:elseplane/theme/theme.dart';
import 'package:elseplane/ui/common/context_menu.dart';
import 'package:elseplane/ui/common/glass_surface.dart';
import 'package:elseplane/ui/common/menu_surface.dart';
import 'package:elseplane/ui/common/select.dart';
import 'package:elseplane/ui/common/surface.dart';
import 'package:elseplane/ui/common/surface_dialog.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
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

  testWidgets(
    'flat glass omits shadows while raised glass and floating surfaces retain them',
    (tester) async {
      for (final theme in [starlessLightThemeData, starlessDarkThemeData]) {
        for (final selected in [false, true]) {
          await tester.pumpWidget(
            MaterialApp(
              theme: theme.copyWith(
                extensions: [
                  theme.extension<BTheme>()!.copyWith(
                    surfaceStyle: SurfaceStyle.glass,
                  ),
                ],
              ),
              home: Scaffold(
                body: Column(
                  children: [
                    GlassSurface(
                      selected: selected,
                      child: const SizedBox(width: 80, height: 40),
                    ),
                    GlassSurface(
                      raised: true,
                      selected: selected,
                      child: const SizedBox(width: 80, height: 40),
                    ),
                    Surface(
                      selected: selected,
                      child: const SizedBox(width: 80, height: 40),
                    ),
                  ],
                ),
              ),
            ),
          );
          final surfaces = find.byType(GlassSurface).evaluate().toList();
          for (var i = 0; i < surfaces.length; i++) {
            final decoration =
                tester
                        .widget<DecoratedBox>(
                          find
                              .descendant(
                                of: find.byWidget(surfaces[i].widget),
                                matching: find.byType(DecoratedBox),
                              )
                              .first,
                        )
                        .decoration
                    as BoxDecoration;
            expect(decoration.boxShadow, i == 0 ? isNull : isNotEmpty);
          }
        }
      }
    },
  );

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
