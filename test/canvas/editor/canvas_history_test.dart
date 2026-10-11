// Verifies undo and redo behavior for canvas mutations.
// Exercises editor history through persisted element changes.

import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/editor/canvas_background.dart';
import 'package:elseplane/canvas/tools/code/code_tool.dart';
import 'package:elseplane/canvas/tools/pen/pen_tool.dart';
import 'package:elseplane/canvas/tools/text/text_tool.dart';
import 'package:elseplane/theme/fonts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts_lite.dart';
import 'package:infinite_lazy_grid/infinite_lazy_grid.dart';
import 'package:shared_preferences_web/shared_preferences_web.dart';

import '../test_helpers.dart';

// ---------- Tests ----------

void main() {
  setUp(() {
    SharedPreferencesAsyncWeb.registerWith(null);
    GoogleFontsLite.config.allowRuntimeFetching = false;
  });
  tearDown(() => GoogleFontsLite.config.allowRuntimeFetching = true);

  testWidgets('transient model state does not persist', (tester) async {
    final store = TestCanvasDocumentStore(_document());
    await pumpCanvas(tester, store);
    final model = _stroke(tester)
      ..selected = true
      ..active = true;
    await pumpPastSave(tester);
    expect(store.persisted, isNull);

    model.moveBy(const Offset(10, 10));
    await pumpPastSave(tester);
    expect(store.persisted, isNotNull);
  });

  testWidgets('undo and redo restore and persist canvas operations', (
    tester,
  ) async {
    final store = TestCanvasDocumentStore(_document());
    await pumpCanvas(tester, store);

    final controller = tester.widget<LazyCanvas>(find.byType(LazyCanvas)).controller;
    final removed = _stroke(tester)..selected = true;
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    // Removed models remain alive until their widgets unmount, without a renderer listener.
    removed.moveBy(const Offset(10, 10));
    expect(controller.childOrder, isEmpty);
    await tester.pump();
    expect(find.byType(PenStroke), findsNothing);

    await _shortcut(tester);
    expect(find.byType(PenStroke), findsOneWidget);
    final restored = _stroke(tester);
    expect(restored, isNot(same(removed)));
    expect(controller.getInfo(restored.data.id).gsPosition, restored.canvasPosition);
    expect(controller.childOrder, ['pen-0']);
    await pumpPastSave(tester);
    expect(store.persisted!.elements, hasLength(1));

    await _shortcut(tester, redo: true);
    expect(find.byType(PenStroke), findsNothing);
    await pumpPastSave(tester);
    expect(store.persisted!.elements, isEmpty);
    await _shortcut(tester);
    final afterRedo = _stroke(tester)..moveBy(const Offset(20, 10));
    expect(controller.getInfo(afterRedo.data.id).gsPosition, afterRedo.canvasPosition);
    await tester.pump();
  });

  testWidgets('a drag is one step and a new operation clears redo', (
    tester,
  ) async {
    final store = TestCanvasDocumentStore(_document());
    await pumpCanvas(tester, store);
    final start = _stroke(tester).data.position;

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(PenStroke)),
    );
    await gesture.moveBy(const Offset(30, 10));
    await gesture.moveBy(const Offset(40, 20));
    await gesture.moveBy(const Offset(50, 30));
    await gesture.up();
    await tester.pump();
    final moved = _stroke(tester).data.position;
    expect(moved, isNot(start));

    await _shortcut(tester);
    expect(_stroke(tester).data.position, start);
    await _shortcut(tester);
    expect(_stroke(tester).data.position, start);

    _stroke(tester).selected = true;
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump();
    await _shortcut(tester, redo: true);
    expect(find.byType(PenStroke), findsNothing);
  });

  testWidgets('focused editors keep ownership of undo shortcuts', (
    tester,
  ) async {
    await pumpCanvas(tester, TestCanvasDocumentStore(_textDocument()));
    final original = tester.widget<TextTool>(find.byType(TextTool)).model;

    await tester.tap(find.byKey(const ValueKey('text-markdown-preview')));
    await tester.pump();
    original.controller.text = 'changed';
    await tester.pump();
    await _shortcut(tester);

    expect(
      tester.widget<TextTool>(find.byType(TextTool)).model,
      same(original),
    );
  });

  testWidgets('font choice is one undo step and restores the saved family', (tester) async {
    final store = TestCanvasDocumentStore(_textDocument());
    await pumpCanvas(tester, store);
    TextBlockModel model() => tester.widget<TextTool>(find.byType(TextTool)).model;
    final savedFamily = model().style.fontFamily;
    await tester.tap(find.byKey(const ValueKey('text-markdown-preview')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('searchable-select-trigger')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MenuItemButton, defaultFontFamily));
    await tester.pumpAndSettle();
    await pumpPastSave(tester);
    expect(model().style.fontFamily, defaultFontFamily);
    expect((store.persisted!.elements.single as TextElementData).style.fontFamily, defaultFontFamily);
    await _shortcut(tester);
    await pumpPastSave(tester);
    expect(model().style.fontFamily, savedFamily);
    expect((store.persisted!.elements.single as TextElementData).style.fontFamily, savedFamily);
    final original = model();
    await _shortcut(tester);
    expect(model(), same(original));
    await _shortcut(tester, redo: true);
    expect(model().style.fontFamily, defaultFontFamily);
  });

  testWidgets('text background choices persist as individual undo steps', (tester) async {
    final store = TestCanvasDocumentStore(_textDocument());
    await pumpCanvas(tester, store);
    TextBlockModel model() => tester.widget<TextTool>(find.byType(TextTool)).model;
    Future<void> choose(String label) async {
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('text-background-select')),
          matching: find.byKey(const ValueKey('select-trigger')),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(MenuItemButton, label));
      await tester.pumpAndSettle();
    }

    Future<void> expectPersisted(BlockBackgroundKind background) async {
      expect(model().style.background, background);
      await pumpPastSave(tester);
      expect((store.persisted!.elements.single as TextElementData).style.background, background);
    }

    await tester.tap(find.byKey(const ValueKey('text-markdown-preview')));
    await tester.pumpAndSettle();
    await choose('Card');
    expect(model().active, isTrue);
    expect(model().editing, isFalse);
    await pumpPastSave(tester);
    expect(store.persisted, isNull);

    await choose('Transparent');
    await expectPersisted(BlockBackgroundKind.transparent);
    await choose('Card');
    await expectPersisted(BlockBackgroundKind.card);
    await choose('Glass');
    await expectPersisted(BlockBackgroundKind.glass);
    await _shortcut(tester);
    await expectPersisted(BlockBackgroundKind.card);
    await _shortcut(tester);
    await expectPersisted(BlockBackgroundKind.transparent);
    await _shortcut(tester);
    await expectPersisted(BlockBackgroundKind.card);
    final original = model();
    await _shortcut(tester);
    expect(model(), same(original));
    await _shortcut(tester, redo: true);
    await expectPersisted(BlockBackgroundKind.transparent);
    await _shortcut(tester, redo: true);
    await expectPersisted(BlockBackgroundKind.card);
    await _shortcut(tester, redo: true);
    await expectPersisted(BlockBackgroundKind.glass);
  });

  testWidgets('code background choices persist as individual undo steps', (tester) async {
    final store = TestCanvasDocumentStore(_codeDocument());
    await pumpCanvas(tester, store);
    CodeBlockModel model() => tester
        .widgetList<CodeTool>(find.byType(CodeTool))
        .firstWhere((widget) => widget.model.data.id == 'code-0')
        .model;
    Future<void> choose(String label) async {
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('code-background-select')),
          matching: find.byKey(const ValueKey('select-trigger')),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(MenuItemButton, label));
      await tester.pumpAndSettle();
      expect(model().active, isTrue);
    }

    Future<void> expectPersisted(BlockBackgroundKind background) async {
      expect(model().background, background);
      await pumpPastSave(tester);
      expect((store.persisted!.elements.first as CodeElementData).background, background);
      expect((store.persisted!.elements.last as CodeElementData).background, BlockBackgroundKind.card);
    }

    await tester.tap(find.byKey(const ValueKey('code-block-preview-surface')).first);
    await tester.pumpAndSettle();
    await choose('Card');
    await pumpPastSave(tester);
    expect(store.persisted, isNull);

    await choose('Transparent');
    await expectPersisted(BlockBackgroundKind.transparent);
    await choose('Glass');
    await expectPersisted(BlockBackgroundKind.glass);
    await _shortcut(tester);
    await expectPersisted(BlockBackgroundKind.transparent);
    await _shortcut(tester);
    await expectPersisted(BlockBackgroundKind.card);
    final original = model();
    await _shortcut(tester);
    expect(model(), same(original));
    await _shortcut(tester, redo: true);
    await expectPersisted(BlockBackgroundKind.transparent);
    await _shortcut(tester, redo: true);
    await expectPersisted(BlockBackgroundKind.glass);

    final saved = CanvasDocument.fromJson(store.persisted!.toJson());
    await tester.pumpWidget(const SizedBox());
    await pumpCanvas(tester, TestCanvasDocumentStore(saved));
    expect(model().background, BlockBackgroundKind.glass);
    expect(model().active, isFalse);
  });

  testWidgets('history retains only the latest 50 operations', (tester) async {
    await pumpCanvas(tester, TestCanvasDocumentStore(_penDocument(51)));

    for (var index = 0; index < 51; index++) {
      tester
              .widgetList<PenStroke>(find.byType(PenStroke))
              .map((widget) => widget.model)
              .firstWhere((model) => model.data.id == 'pen-$index')
              .selected =
          true;
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();
    }
    expect(find.byType(PenStroke), findsNothing);

    for (var index = 0; index < 51; index++) {
      await _shortcut(tester);
    }
    expect(find.byType(PenStroke), findsNWidgets(50));
    expect(
      tester.widgetList<PenStroke>(find.byType(PenStroke)).map((widget) => widget.model.data.id),
      isNot(contains('pen-0')),
    );
  });
}

Future<void> _shortcut(WidgetTester tester, {bool redo = false}) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (redo) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.keyZ);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.keyZ);
  if (redo) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

PenStrokeModel _stroke(WidgetTester tester) => tester.widget<PenStroke>(find.byType(PenStroke)).model;

// ---------- Fixtures ----------

CanvasDocument _document() => _penDocument(1);

CanvasDocument _penDocument(int count) => CanvasDocument(
  background: CanvasBackgroundKind.plain,
  elements: [
    for (var index = 0; index < count; index++)
      PenElementData(
        id: 'pen-$index',
        position: Offset(
          40 + (index % 10) * 60,
          100 + (index ~/ 10) * 60,
        ),
        size: const Size(40, 40),
        hitSlop: 6,
        color: 0xff000000,
        width: 4,
        points: const [
          PenPointData(Offset(4, 4), pressure: 1),
          PenPointData(Offset(36, 36), pressure: 1),
        ],
      ),
  ],
);

CanvasDocument _textDocument() => CanvasDocument(
  background: CanvasBackgroundKind.plain,
  elements: [
    TextElementData(
      id: 'text',
      position: const Offset(200, 240),
      width: 280,
      height: null,
      markdown: 'original',
      style: const TextNodeStyle(
        fontFamily: 'Inter',
        color: '#201C1A',
      ),
    ),
  ],
);

CanvasDocument _codeDocument() => CanvasDocument(
  background: CanvasBackgroundKind.plain,
  elements: [
    for (var index = 0; index < 2; index++)
      CodeElementData(
        id: 'code-$index',
        position: Offset(180 + index * 320, 240),
        size: const Size(280, 240),
        language: CodeLanguage.dart,
        source: 'void main() {}',
        title: 'main.dart',
        showLineNumbers: true,
      ),
  ],
);
