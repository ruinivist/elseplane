// Verifies erasing overlapping elements and saving completed edits.

import 'dart:convert';

import 'package:elseplane/app/app.dart';
import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/editor/elements/arrow/arrow_element_view.dart';
import 'package:elseplane/canvas/editor/elements/code/code_element_view.dart';
import 'package:elseplane/canvas/editor/elements/pen/pen_element_view.dart';
import 'package:elseplane/canvas/editor/elements/text/text_element_view.dart';
import 'package:elseplane/library/canvas_library.dart';
import 'package:elseplane/library/library_store.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_lazy_grid/infinite_lazy_grid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_web/shared_preferences_web.dart';

void main() {
  setUp(() async {
    SharedPreferencesAsyncWeb.registerWith(null);
    final preferences = SharedPreferencesAsync();
    await preferences.remove(PreferencesLibraryStore.libraryKey);
  });

  testWidgets('eraser scrubs every overlapping element and saves', (
    tester,
  ) async {
    PenElementData stroke(String id, Offset position) => PenElementData(
      id: id,
      position: position,
      size: const Size(100, 100),
      hitSlop: 6,
      color: const Color(0xff000000),
      width: 3,
      points: const [
        PenPointData(Offset(0, 50), pressure: 0.5),
        PenPointData(Offset(100, 50), pressure: 0.5),
      ],
    );

    final document = CanvasDocument(
      background: CanvasBackgroundKind.plain,
      elements: [
        TextElementData(
          id: 'text-overlap',
          position: const Offset(100, 250),
          width: 280,
          height: 100,
          markdown: 'overlap',
          style: const TextNodeStyle(
            fontFamily: 'Source Serif 4',
            color: Color(0xff201C1A),
          ),
        ),
        CodeElementData(
          id: 'code-overlap',
          position: const Offset(100, 250),
          size: const Size(280, 240),
          language: CodeLanguage.dart,
          source: '',
          title: '',
          showLineNumbers: true,
        ),
        stroke('pen-overlap', const Offset(100, 250)),
        ArrowElementData(
          id: 'arrow-overlap',
          start: const Offset(100, 300),
          controls: const [Offset(150, 300)],
          end: const Offset(200, 300),
          color: const Color(0xff000000),
          strokeStyle: ArrowStrokeStyle.solid,
          strokeWidth: 2,
        ),
        TextElementData(
          id: 'text-drag',
          position: const Offset(500, 250),
          width: 160,
          height: 100,
          markdown: 'drag',
          style: const TextNodeStyle(
            fontFamily: 'Source Serif 4',
            color: Color(0xff201C1A),
          ),
        ),
        stroke('pen-safe', const Offset(100, 450)),
      ],
    );
    await SharedPreferencesAsync().setString(
      PreferencesLibraryStore.libraryKey,
      jsonEncode(CanvasLibrary.initial(document).toJson()),
    );
    await tester.pumpWidget(const ElseplaneApp());
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('toolbar-draw')));
    await tester.tap(find.byKey(const ValueKey('toolbar-erase')));
    await tester.pump();
    final erase = await tester.startGesture(
      const Offset(150, 300),
      kind: PointerDeviceKind.mouse,
    );
    await erase.moveTo(const Offset(550, 300));
    await erase.up();
    await tester.pump();

    expect(find.byType(TextElementView), findsNothing);
    expect(find.byType(CodeElementView), findsNothing);
    expect(find.byType(ArrowElementView), findsNothing);
    expect(find.byType(PenElementView), findsOneWidget);
    expect(
      tester.widget<PenElementView>(find.byType(PenElementView)).resources.data.id,
      'pen-safe',
    );

    final canvas = tester.widget<LazyCanvas>(find.byType(LazyCanvas));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    await tester.pump();
    final pan = await tester.startGesture(
      const Offset(150, 500),
      kind: PointerDeviceKind.mouse,
    );
    await pan.moveBy(const Offset(40, 20));
    await pan.up();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(canvas.controller.offset, isNot(Offset.zero));
    expect(find.byType(PenElementView), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 320));
    await tester.pump();
    final saved = (await PreferencesLibraryStore().load())!.current.document!;
    expect(saved.elements.map((element) => element.id), ['pen-safe']);
  });
}
