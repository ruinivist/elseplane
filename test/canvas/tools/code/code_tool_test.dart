// Verifies code block backgrounds and distinguishes clicks from movement drags.
// Exercises CodeTool rendering and editing without the persistence boundary.

import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/tools/code/code_tool.dart';
import 'package:elseplane/theme/starless.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

void main() {
  test('title changes publish the synchronized controller and value once', () {
    final model = _codeModel();
    addTearDown(model.dispose);
    final changes = <(String, String)>[];
    model.documentChanges.addListener(() => changes.add((model.title, model.titleController.text)));
    model.title = 'New title';
    expect(changes, [('New title', 'New title')]);
  });

  test('separates presentation and document changes', () {
    final model = _codeModel();
    addTearDown(model.dispose);
    var rebuilds = 0;
    var documentChanges = 0;
    model.addListener(() => rebuilds++);
    model.documentChanges.addListener(() => documentChanges++);

    model
      ..selected = true
      ..active = true;
    expect((rebuilds, documentChanges), (2, 0));

    rebuilds = 0;
    model.controller.text = 'void main() {}';
    expect((rebuilds, documentChanges), (0, 1));

    model.language = CodeLanguage.python;
    expect((rebuilds, documentChanges), (1, 2));

    model.background = BlockBackgroundKind.glass;
    expect((rebuilds, documentChanges), (2, 3));
    model.background = BlockBackgroundKind.glass;
    expect((rebuilds, documentChanges), (2, 3));
  });

  testWidgets('active code selection drag interacts without moving or clearing the editor', (tester) async {
    final model = _codeModel(source: 'one two three four five')..active = true;
    addTearDown(model.dispose);
    var interactions = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: starlessLightThemeData,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: CodeTool(
              model: model,
              onEdit: () => fail('Active code must not be reactivated'),
              onInteract: () => interactions++,
              onMove: (_) => fail('Editor selection must not move the block'),
              onResize: (_) {},
              onChangeBoundary: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final start = tester.getTopLeft(find.byType(CodeEditor)) + const Offset(30, 20);
    await tester.tapAt(start, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(model.focusNode.hasFocus, isTrue);
    expect(interactions, 1);
    interactions = 0;
    final mobile = defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;
    final drag = await tester.startGesture(start, kind: mobile ? PointerDeviceKind.touch : PointerDeviceKind.mouse);
    if (mobile) await tester.pump(kLongPressTimeout + const Duration(milliseconds: 1));
    await tester.pump();
    await drag.moveBy(const Offset(50, 0));
    await tester.pump();
    await drag.moveBy(const Offset(50, 0));
    await tester.pump();
    final selection = model.controller.selection;
    expect(selection.isCollapsed, isFalse);
    await drag.up();
    await tester.pumpAndSettle();
    expect(model.controller.selection, selection);
    expect(model.focusNode.hasFocus, isTrue);
    expect(interactions, 1);
  });

  testWidgets('backgrounds cover body, title, and line numbers in every interaction state', (tester) async {
    for (final theme in [starlessLightThemeData, starlessDarkThemeData]) {
      final model = _codeModel(source: 'void main() {}')
        ..title = 'main.dart'
        ..showLineNumbers = true;
      addTearDown(model.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: CodeTool(
                model: model,
                onEdit: () => model.active = true,
                onMove: model.moveBy,
                onResize: (_) {},
                onChangeBoundary: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final block = find.byType(CodeTool);
      final surface = find.byKey(const ValueKey('code-block-surface'));
      final originalBounds = tester.getRect(surface);

      Material body() => tester.widget<Material>(
        model.background == BlockBackgroundKind.glass
            ? find.descendant(of: surface, matching: find.byType(Material)).first
            : surface,
      );
      BoxDecoration titleDecoration() {
        final title = find.byKey(ValueKey(model.active ? 'code-title-input-tab-surface' : 'code-title-tab-surface'));
        if (model.background != BlockBackgroundKind.glass) {
          return tester.widget<Container>(title).decoration! as BoxDecoration;
        }
        final material = tester.widget<Material>(find.descendant(of: title, matching: find.byType(Material)));
        final shape = material.shape! as RoundedRectangleBorder;
        return BoxDecoration(color: material.color, border: Border.fromBorderSide(shape.side));
      }

      BorderSide bodyBorder() => (body().shape! as RoundedRectangleBorder).side;

      for (final background in BlockBackgroundKind.values) {
        model
          ..background = background
          ..active = false
          ..selected = false;
        await tester.pumpAndSettle();
        final previewColor = body().color;
        for (final (active, selected) in [(false, false), (true, false), (false, true), (true, true)]) {
          model
            ..active = active
            ..selected = selected;
          await tester.pumpAndSettle();
          final editor = tester.widget<CodeEditor>(find.byType(CodeEditor));
          final gutter = tester.widget<ColoredBox>(find.byKey(const ValueKey('code-line-numbers')));
          final title = titleDecoration();
          final filters = find.descendant(of: block, matching: find.byType(BackdropFilter));
          expect(tester.getRect(surface), originalBounds);
          expect(editor.readOnly, !active);
          expect(editor.style!.backgroundColor!.a, 0);
          expect(model.controller.text, 'void main() {}');
          expect(model.title, 'main.dart');

          if (background == BlockBackgroundKind.card) {
            expect(body().color!.a, 1);
            expect(title.color!.a, 1);
            expect(gutter.color.a, 1);
            expect(body().elevation, greaterThan(0));
          } else {
            expect(gutter.color.a, 0);
            expect(body().elevation, 0);
          }
          if (background == BlockBackgroundKind.transparent && !selected) {
            expect(body().type, MaterialType.transparency);
            expect(body().color, isNull);
            expect(title.color!.a, 0);
          }
          if (background == BlockBackgroundKind.transparent && !active && !selected) {
            expect(bodyBorder(), BorderSide.none);
            expect((title.border! as Border).top, BorderSide.none);
          } else {
            expect(bodyBorder(), isNot(BorderSide.none));
            expect((title.border! as Border).top, isNot(BorderSide.none));
          }
          if (background == BlockBackgroundKind.glass) {
            expect(filters, findsNWidgets(2));
            expect(body().color!.a, inExclusiveRange(0, 1));
            expect(title.color!.a, inExclusiveRange(0, 1));
            for (final filter in filters.evaluate()) {
              final finder = find.byWidget(filter.widget);
              final clip = find.ancestor(of: finder, matching: find.byType(ClipRRect)).first;
              expect(tester.getSize(clip), tester.getSize(finder));
              expect((filter.widget as BackdropFilter).backdropGroupKey, isNull);
            }
            if (selected) expect(body().color, isNot(previewColor));
          } else {
            expect(filters, findsNothing);
          }
        }
      }
      model
        ..active = false
        ..title = '';
      await tester.pumpAndSettle();
      expect(find.descendant(of: block, matching: find.byType(BackdropFilter)), findsOneWidget);
      expect(tester.getRect(surface), originalBounds);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    }
  });

  for (final background in BlockBackgroundKind.values) {
    testWidgets('inactive ${background.name} code distinguishes editing clicks from drags', (
      tester,
    ) async {
      final model = _codeModel(source: 'first line\nsecond line')..background = background;
      addTearDown(model.dispose);
      var movement = Offset.zero;
      await tester.pumpWidget(
        MaterialApp(
          theme: starlessLightThemeData,
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: CodeTool(
                model: model,
                onEdit: () {
                  model.active = true;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!model.active) return;
                    model.focusNode.unfocus();
                    FocusManager.instance.applyFocusChangesIfNeeded();
                    model.focusNode.requestFocus();
                  });
                },
                onMove: (delta) => movement += delta,
                onResize: (_) {},
                onChangeBoundary: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      model.controller.selection = const CodeLineSelection.collapsed(
        index: 1,
        offset: 11,
      );

      final surface = tester.getRect(
        find.byKey(const ValueKey('code-block-surface')),
      );
      await tester.tapAt(surface.topLeft + const Offset(40, 20));
      await tester.pump();
      await tester.pump();

      expect(model.active, isTrue);
      expect(model.focusNode.hasFocus, isTrue);
      expect(
        model.controller.selection,
        const CodeLineSelection.collapsed(index: 0, offset: 2),
      );

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: surface.center);
      expect(
        RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
        SystemMouseCursors.text,
      );

      model
        ..active = false
        ..focusNode.unfocus();
      await tester.pump();
      expect(
        RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
        SystemMouseCursors.basic,
      );
      await mouse.removePointer();

      const delta = Offset(80, 60);
      final drag = await tester.startGesture(
        surface.topLeft + const Offset(40, 20),
        kind: PointerDeviceKind.mouse,
      );
      await drag.moveBy(delta / 2);
      await tester.pump();
      expect(model.controller.selection.isCollapsed, isTrue);
      await drag.moveBy(delta / 2);
      await tester.pump();
      expect(model.controller.selection.isCollapsed, isTrue);
      await drag.up();
      await tester.pump();

      expect(movement, delta);
      expect(model.active, isFalse);
      expect(model.focusNode.hasFocus, isFalse);
      await tester.pump(const Duration(milliseconds: 600));
    });
  }
}

CodeBlockModel _codeModel({String source = ''}) => CodeBlockModel(
  CodeElementData(
    id: 'code',
    position: Offset.zero,
    size: const Size(280, 240),
    language: CodeLanguage.dart,
    source: source,
    title: '',
    showLineNumbers: false,
  ),
);
