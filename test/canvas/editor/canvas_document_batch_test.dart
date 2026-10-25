// Checks complete document snapshots from group mutations.
// Exercises the editor callback directly so autosave timing cannot hide repeated copies.

import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/editor/canvas_page.dart';
import 'package:elseplane/canvas/editor/elements/pen/pen_element_view.dart';
import 'package:elseplane/theme/starless.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

// ---------- Tests ----------

void main() {
  for (final count in [100, 1000]) {
    for (final auto in [false, true]) {
      testWidgets('$count group elements publish once per move with Auto $auto', (tester) async {
        final document = _document(count, auto: auto);
        final snapshots = <CanvasDocument>[];
        await _pumpEditor(tester, document, snapshots.add);
        await _selectGroup(tester);
        final stroke = tester
            .widgetList<PenElementView>(find.byType(PenElementView))
            .firstWhere((stroke) => stroke.resources.data.id == 'p0');
        for (var update = 1; update <= 3; update++) {
          stroke.onMove(const Offset(4, 3));
          expect(snapshots, hasLength(update));
          final snapshot = snapshots.last;
          final movedById = {for (final element in snapshot.elements) element.id: element as PenElementData};
          for (final original in document.elements.take(count)) {
            final moved = movedById[original.id]!;
            expect(moved.position, (original as PenElementData).position + Offset(4.0 * update, 3.0 * update));
          }
          expect(snapshot.elements.first.id, auto ? 'sentinel' : 'p0');
          expect(snapshot.elements.last.id, auto ? 'p${count - 1}' : 'sentinel');
          expect(
            (snapshot.elements.firstWhere((element) => element.id == 'sentinel') as PenElementData).position,
            const Offset(400, 200),
          );
          await tester.pump();
        }
        stroke.onMove(Offset.zero);
        expect(snapshots, hasLength(3));
        expect(
          (snapshots.first.elements.firstWhere((element) => element.id == 'p0') as PenElementData).position,
          const Offset(104, 203),
        );
        await _shortcut(tester, LogicalKeyboardKey.keyZ);
        expect(snapshots.last.toJson(), document.toJson());
        await _shortcut(tester, LogicalKeyboardKey.keyZ, shift: true);
        expect(snapshots.last.toJson(), snapshots[2].toJson());
        await tester.pumpWidget(const SizedBox());
      });
    }
  }

  testWidgets('group Arrange and Auto publish their settings and order together', (tester) async {
    final document = _document(100, auto: true);
    final snapshots = <CanvasDocument>[];
    await _pumpEditor(tester, document, snapshots.add);
    await _selectGroup(tester);
    await _shortcut(tester, LogicalKeyboardKey.bracketRight, shift: true);
    expect(snapshots, hasLength(1));
    expect(snapshots.single.elements.first.id, 'sentinel');
    expect(snapshots.single.elements.skip(1).every((element) => !element.autoArrange), isTrue);
    await _shortcut(tester, LogicalKeyboardKey.bracketRight, shift: true);
    expect(snapshots, hasLength(1));

    final click = await tester.startGesture(
      const Offset(110, 210),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryButton,
    );
    await click.up();
    await tester.pumpAndSettle();
    Focus.of(tester.element(find.text('Arrange'))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Auto'));
    await tester.pumpAndSettle();
    expect(snapshots, hasLength(2));
    expect(snapshots.last.elements.skip(1).every((element) => element.autoArrange), isTrue);
    await _shortcut(tester, LogicalKeyboardKey.keyZ);
    expect(snapshots.last.toJson(), snapshots.first.toJson());
    await tester.pumpWidget(const SizedBox());
  });
}

// ---------- Fixtures ----------

CanvasDocument _document(int count, {required bool auto}) => CanvasDocument(
  background: CanvasBackgroundKind.plain,
  elements: [
    for (var index = 0; index <= count; index++)
      PenElementData(
        id: index == count ? 'sentinel' : 'p$index',
        autoArrange: index != count && auto,
        position: index == count
            ? const Offset(400, 200)
            : index == 0
            ? const Offset(100, 200)
            : Offset(10000.0 + index * 100, 200),
        size: const Size(40, 20),
        hitSlop: 6,
        color: Colors.black,
        width: 3,
        points: const [PenPointData(Offset(0, 10), pressure: 0.5), PenPointData(Offset(40, 10), pressure: 0.5)],
      ),
  ],
);

Future<void> _pumpEditor(WidgetTester tester, CanvasDocument document, ValueChanged<CanvasDocument> onChanged) async {
  final session = testSession(document);
  session.documentChanges.addListener(() => onChanged(session.document));
  await tester.pumpWidget(
    MaterialApp(
      theme: starlessLightThemeData.copyWith(platform: TargetPlatform.linux),
      home: CanvasPage(
        session: session,
        attachmentStore: TestAttachmentStore(),
        libraryPath: const ['Test'],
        onOpenLibrary: () async {},
        onImportCanvas: () async => false,
        onExportCanvas: () async {},
        onBackupLibrary: () async {},
        onRestoreLibrary: () async => false,
        readClipboard: () async => (text: null, image: null),
        writeClipboardText: (_) async {},
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _selectGroup(WidgetTester tester) async {
  await _shortcut(tester, LogicalKeyboardKey.keyA);
  final sentinel = tester
      .widgetList<PenElementView>(find.byType(PenElementView))
      .firstWhere((stroke) => stroke.resources.data.id == 'sentinel');
  sentinel.resources.setSelected(value: false);
}

Future<void> _shortcut(WidgetTester tester, LogicalKeyboardKey key, {bool shift = false}) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(key);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
}
