// Verifies workspace reopening and unreadable library preservation.

import 'package:elseplane/app/app.dart';
import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/editor/elements/arrow/arrow_element_view.dart';
import 'package:elseplane/canvas/editor/elements/code/code_element_view.dart';
import 'package:elseplane/canvas/editor/elements/pen/pen_element_view.dart';
import 'package:elseplane/canvas/editor/elements/text/text_element_view.dart';
import 'package:elseplane/library/library_store.dart';
import 'package:elseplane/ui/common/select.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_lazy_grid/infinite_lazy_grid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_web/shared_preferences_web.dart';

import '../canvas/test_helpers.dart';

void main() {
  setUp(() async {
    SharedPreferencesAsyncWeb.registerWith(null);
    final preferences = SharedPreferencesAsync();
    await preferences.remove(PreferencesLibraryStore.libraryKey);
  });

  testWidgets('all element types restore in document order', (tester) async {
    await tester.pumpWidget(const ElseplaneApp());
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('toolbar-text')));
    await tester.pump();
    await tester.tapAt(const Offset(40, 160));
    await tester.pump();
    await tester.pump();
    final text = tester.widget<TextElementView>(find.byType(TextElementView)).resources;
    final textPosition = text.data.position;
    await tester.enterText(
      find.byKey(const ValueKey('text-markdown-editor')),
      'saved text',
    );

    await placeCodeBlock(tester, const Offset(120, 140));
    final code = tester.widget<CodeElementView>(find.byType(CodeElementView)).resources
      ..setLanguage(CodeLanguage.json)
      ..controller.text = '{"saved": true}';
    final codePosition = code.data.position;
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('toolbar-draw')));
    await tester.pump();
    await tester.dragFrom(
      const Offset(40, 520),
      const Offset(100, 40),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    final pen = tester.widget<PenElementView>(find.byType(PenElementView)).resources;
    final penPosition = pen.data.position;
    final penSize = pen.data.size;
    final penPoints = pen.data.toJson()['points'];
    await tester.tap(find.byKey(const ValueKey('toolbar-draw')));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('toolbar-arrow')));
    await tester.pump();
    final arrowDrag = await tester.startGesture(
      const Offset(520, 520),
      kind: PointerDeviceKind.mouse,
    );
    await arrowDrag.moveTo(const Offset(700, 560));
    await arrowDrag.up();
    await tester.pump();
    final arrow = canvasElement(tester, tester.widget<ArrowElementView>(find.byType(ArrowElementView)).data);
    final arrowGeometry = arrow.geometry;

    await tester.tap(find.byKey(const ValueKey('settings-button')));
    await tester.pump();
    await tester.tap(find.text('Canvas'));
    await tester.pump();
    tester
        .widget<Select<CanvasBackgroundKind>>(
          find.byKey(const ValueKey('canvas-background-select')),
        )
        .onChanged!
        .call(CanvasBackgroundKind.plain);
    await tester.pump();
    await tester.tap(find.byTooltip('Close'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
    await tester.pump();

    final document = (await PreferencesLibraryStore().load())!.current.document!;
    final ids = document.elements.map((element) => element.id).toList();
    expect(document.background, CanvasBackgroundKind.plain);
    expect(document.elements, hasLength(4));
    expect(document.elements.map((element) => element.type), [
      'text',
      'code',
      'pen',
      'arrow',
    ]);
    expect((document.elements[0] as TextElementData).markdown, 'saved text');
    expect((document.elements[0] as TextElementData).position, textPosition);
    expect(
      (document.elements[1] as CodeElementData).language,
      CodeLanguage.json,
    );
    expect((document.elements[1] as CodeElementData).position, codePosition);
    expect((document.elements[2] as PenElementData).position, penPosition);
    expect((document.elements[2] as PenElementData).size, penSize);
    expect(
      (document.elements[2] as PenElementData).toJson()['points'],
      penPoints,
    );
    expect(
      (document.elements[3] as ArrowElementData).start,
      arrowGeometry.start,
    );
    expect(
      (document.elements[3] as ArrowElementData).controls.single,
      arrowGeometry.controls.single,
    );
    expect((document.elements[3] as ArrowElementData).end, arrowGeometry.end);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester.pumpWidget(const ElseplaneApp());
    await tester.pump();
    await tester.pump();

    final restored = (await PreferencesLibraryStore().load())!.current.document!;
    expect(restored.elements.map((element) => element.id), ids);
    expect(find.byType(TextElementView), findsOneWidget);
    expect(find.byType(CodeElementView), findsOneWidget);
    expect(find.byType(PenElementView), findsOneWidget);
    expect(find.byType(ArrowElementView), findsOneWidget);
    final restoredCanvas = tester.widget<LazyCanvas>(find.byType(LazyCanvas));
    expect(
      restoredCanvas.controller.widgetsWithScreenPositions().map(
        (child) => child.id,
      ),
      ids,
    );
    for (final block in tester.widgetList<TextElementView>(find.byType(TextElementView))) {
      expect(block.resources.selected, isFalse);
      expect(block.resources.focusNode.hasFocus, isFalse);
    }
    for (final block in tester.widgetList<CodeElementView>(find.byType(CodeElementView))) {
      expect(block.resources.selected, isFalse);
      expect(block.resources.focusNode.hasFocus, isFalse);
    }
    expect(
      tester.widget<CodeElementView>(find.byType(CodeElementView)).resources.data.source,
      '{"saved": true}',
    );
    expect(
      tester.widget<TextElementView>(find.byType(TextElementView)).resources.data.position,
      textPosition,
    );
    expect(
      tester.widget<CodeElementView>(find.byType(CodeElementView)).resources.data.position,
      codePosition,
    );
    final restoredPen = tester.widget<PenElementView>(find.byType(PenElementView)).resources;
    expect(restoredPen.data.position, penPosition);
    expect(restoredPen.data.size, penSize);
    expect(restoredPen.data.toJson()['points'], penPoints);
    final restoredArrow = canvasElement(tester, tester.widget<ArrowElementView>(find.byType(ArrowElementView)).data);
    expect(restoredArrow.geometry.start, arrowGeometry.start);
    expect(restoredArrow.geometry.controls.single, arrowGeometry.controls.single);
    expect(restoredArrow.geometry.end, arrowGeometry.end);
  });

  testWidgets('malformed saved libraries are preserved and reported', (
    tester,
  ) async {
    const invalid = '{"version":99,"currentId":"invalid","files":[]}';
    final preferences = SharedPreferencesAsync();
    await preferences.setString(PreferencesLibraryStore.libraryKey, invalid);

    await tester.pumpWidget(const ElseplaneApp());
    await tester.pump();
    await tester.pump();

    expect(find.byType(TextElementView), findsNothing);
    expect(find.text('Could not load saved canvas'), findsOneWidget);
    expect(await preferences.getString(PreferencesLibraryStore.libraryKey), invalid);

    await tester.tap(find.byKey(const ValueKey('toolbar-text')));
    await tester.pump();
    await tester.tapAt(const Offset(120, 200));
    await pumpPastSave(tester);
    expect(find.byType(TextElementView), findsNothing);
    expect(await preferences.getString(PreferencesLibraryStore.libraryKey), invalid);
  });
}
