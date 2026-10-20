// Verifies canvas clipboard encoding, decoding, and paste behavior.
// Exercises serialized elements and external clipboard content in the editor.

import 'dart:async';
import 'dart:convert';

import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/editor/canvas_clipboard.dart';
import 'package:elseplane/canvas/editor/canvas_element_model.dart';
import 'package:elseplane/canvas/editor/widgets/canvas_title.dart';
import 'package:elseplane/canvas/persistence/attachments/store.dart';
import 'package:elseplane/canvas/tools/arrow/arrow_tool.dart';
import 'package:elseplane/canvas/tools/code/code_tool.dart';
import 'package:elseplane/canvas/tools/media/media_tool.dart';
import 'package:elseplane/canvas/tools/pen/pen_tool.dart';
import 'package:elseplane/canvas/tools/shape/shape_tool.dart';
import 'package:elseplane/canvas/tools/text/text_tool.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_lazy_grid/infinite_lazy_grid.dart';
import 'package:shared_preferences_web/shared_preferences_web.dart';

import '../test_helpers.dart';

// ---------- Tests ----------

void main() {
  setUp(() => SharedPreferencesAsyncWeb.registerWith(null));

  test('clipboard preserves per-object Auto settings', () {
    final document = _document.withElements(
      (elements) => elements[0] = elements[0].copyWith(autoArrange: false),
    );
    final restored = decodeCanvasClipboard(encodeCanvasClipboard(document.elements))!;
    expect(restored.map((element) => element.autoArrange), document.elements.map((element) => element.autoArrange));
  });

  test(
    'clipboard payload round-trips and rejects recognized malformed data',
    () {
      final payload = encodeCanvasClipboard(_document.elements);
      expect(
        decodeCanvasClipboard(
          payload,
        )!.map((element) => element.toJson()),
        _document.elements.map((element) => element.toJson()),
      );
      expect(decodeCanvasClipboard('ordinary clipboard text'), isNull);
      expect(
        () => decodeCanvasClipboard(
          '{"format":"elseplane-canvas-clipboard","version":1}',
        ),
        throwsFormatException,
      );
      expect(
        () => decodeCanvasClipboard(
          '{"format":"elseplane-canvas-clipboard",',
        ),
        throwsFormatException,
      );
    },
  );

  test('clipboard preserves text backgrounds and rejects the previous version', () {
    var text = _document.elements.whereType<TextElementData>().first;
    for (final background in BlockBackgroundKind.values) {
      text = text.copyWith(style: text.style.copyWith(background: background));
      final payload = encodeCanvasClipboard([text]);
      final restored = decodeCanvasClipboard(payload)!.single as TextElementData;
      expect(restored.style.background, background);
      final previous = jsonDecode(payload) as Map<String, dynamic>;
      previous['version'] = canvasClipboardVersion - 1;
      expect(() => decodeCanvasClipboard(jsonEncode(previous)), throwsFormatException);
    }
  });

  test('clipboard preserves shape geometry', () {
    final shape = ShapeElementData(
      id: 'shape',
      kind: ShapeKind.diamond,
      position: const Offset(30, 40),
      size: const Size(120, 80),
      strokeColor: const Color(0xffdc3f3f),
      fillColor: const Color(0xffffc936),
      strokeWidth: 4,
    );

    final restored =
        decodeCanvasClipboard(
              encodeCanvasClipboard([shape]),
            )!.single
            as ShapeElementData;
    expect(restored.toJson(), shape.toJson());
  });

  testWidgets('copies, pastes, cuts, restores, and persists mixed elements', (
    tester,
  ) async {
    final store = TestCanvasDocumentStore(_document);
    String? clipboard;
    var failWrite = false;
    await pumpCanvas(
      tester,
      store,
      readClipboard: () async => (text: clipboard, image: null),
      writeClipboardText: (text) async {
        if (failWrite) throw StateError('write failed');
        clipboard = text;
      },
    );
    for (final model in _models(tester)) {
      model.selected = true;
    }
    await _shortcut(tester, LogicalKeyboardKey.keyC);
    expect(clipboard, isNotNull);

    await _shortcut(tester, LogicalKeyboardKey.keyV);
    await pumpPastSave(tester);
    final copied = store.persisted!;
    final renderer = tester.widget<LazyCanvas>(find.byType(LazyCanvas)).controller;
    expect(renderer.childOrder, copied.elements.map((element) => element.id));
    expect(copied.elements, hasLength(8));
    expect(_types(copied.elements), [
      ..._types(_document.elements),
      ..._types(_document.elements),
    ]);
    expect(copied.elements.map((element) => element.id).toSet(), hasLength(8));
    final firstPaste = copied.elements.skip(4).toList();
    for (var index = 0; index < 4; index++) {
      _expectShifted(
        _document.elements[index],
        firstPaste[index],
        const Offset(24, 24),
      );
    }
    _expectOnlySelected(
      tester,
      firstPaste.map((element) => element.id).toSet(),
    );

    failWrite = true;
    await _shortcut(tester, LogicalKeyboardKey.keyX);
    await tester.pump();
    expect(_models(tester), hasLength(8));
    expect(find.text('Could not cut canvas elements'), findsOneWidget);

    failWrite = false;
    await _shortcut(tester, LogicalKeyboardKey.keyX);
    await pumpPastSave(tester);
    expect(store.persisted!.elements, hasLength(4));

    await _shortcut(tester, LogicalKeyboardKey.keyV);
    await pumpPastSave(tester);
    final restored = store.persisted!;
    expect(restored.elements, hasLength(8));
    final restoredPaste = restored.elements.skip(4).toList();
    expect(
      restoredPaste
          .map((element) => element.id)
          .toSet()
          .intersection(
            firstPaste.map((element) => element.id).toSet(),
          ),
      isEmpty,
    );
    for (var index = 0; index < 4; index++) {
      _expectShifted(firstPaste[index], restoredPaste[index], Offset.zero);
    }
    _expectOnlySelected(
      tester,
      restoredPaste.map((element) => element.id).toSet(),
    );

    await _shortcut(tester, LogicalKeyboardKey.keyV);
    await pumpPastSave(tester);
    final cascaded = store.persisted!;
    expect(cascaded.elements, hasLength(12));
    for (var index = 0; index < 4; index++) {
      _expectShifted(
        firstPaste[index],
        cascaded.elements[index + 8],
        const Offset(24, 24),
      );
    }
    _expectOnlySelected(
      tester,
      cascaded.elements.skip(8).map((element) => element.id).toSet(),
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(const Offset(300, 400));
    await _shortcut(tester, LogicalKeyboardKey.keyC);

    const target = Offset(600, 400);
    await mouse.moveTo(target);
    await _shortcut(tester, LogicalKeyboardKey.keyV);
    await pumpPastSave(tester);
    final controller = tester.widget<LazyCanvas>(find.byType(LazyCanvas)).controller;
    final targetOnCanvas = controller.offset + target / controller.scale;
    expect(_selectedBounds(tester).center, targetOnCanvas);

    await _shortcut(tester, LogicalKeyboardKey.keyV);
    await pumpPastSave(tester);
    expect(
      _selectedBounds(tester).center,
      targetOnCanvas + const Offset(24, 24) / controller.scale,
    );

    clipboard = encodeCanvasClipboard(
      _document.elements.map(
        (element) => element.copyWith(id: 'external-${element.id}'),
      ),
    );
    await _shortcut(tester, LogicalKeyboardKey.keyV);
    await pumpPastSave(tester);
    expect(_selectedBounds(tester).center, targetOnCanvas);
    await mouse.removePointer();
  });

  for (final group in [false, true]) {
    for (final action in ['Copy', 'Cut', 'Delete']) {
      testWidgets('$action captures ${group ? 'group' : 'single'} targets, persists, and undoes once', (tester) async {
        final store = TestCanvasDocumentStore(_menuDocument);
        final write = Completer<void>();
        String? payload;
        await pumpCanvas(
          tester,
          store,
          writeClipboardText: (text) {
            payload = text;
            return write.future;
          },
        );
        if (group) {
          for (final model in _models(tester)) {
            model.selected = true;
          }
        }
        await _openMenu(tester, const Offset(310, 310));
        await tester.tap(find.text(action));
        await tester.pump();
        expect(find.text('Arrange'), findsNothing);
        if (action != 'Delete') {
          expect(decodeCanvasClipboard(payload!)!.map((element) => element.id), group ? ['a', 'b'] : ['a']);
          // Menu dismissal and later selection changes must not retarget Cut.
          for (final model in _models(tester)) {
            model.selected = model.data.id == 'b';
          }
          write.complete();
          await tester.pump();
        }
        await pumpPastSave(tester);
        final canvas = tester.widget<LazyCanvas>(find.byType(LazyCanvas)).controller;
        final remaining = action == 'Copy'
            ? ['a', 'b']
            : group
            ? <String>[]
            : ['b'];
        expect(canvas.childOrder, remaining);
        if (action == 'Copy') {
          expect(store.persisted, isNull);
        } else {
          expect(store.persisted!.elements.map((element) => element.id), remaining);
        }
        await _shortcut(tester, LogicalKeyboardKey.keyZ);
        expect(canvas.childOrder, ['a', 'b']);
        await _shortcut(tester, LogicalKeyboardKey.keyZ);
        expect(canvas.childOrder, ['a', 'b']);
      });
    }
  }

  testWidgets('first enabled menu items receive focus and Escape preserves selection', (tester) async {
    await pumpCanvas(tester, TestCanvasDocumentStore(_menuDocument));
    await _openMenu(tester, const Offset(310, 310));
    MenuItemButton button(String label) => tester.widget<MenuItemButton>(
      find.ancestor(of: find.text(label), matching: find.byType(MenuItemButton)),
    );
    expect(button('Cut').focusNode!.hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(_models(tester).first.selected, isTrue);
    await _openMenu(tester, const Offset(400, 550));
    expect(button('Paste').focusNode!.hasPrimaryFocus, isTrue);
    expect(find.text('Cut'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Paste'), findsNothing);
    expect(_models(tester).first.selected, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(_models(tester).every((model) => !model.selected), isTrue);
  });

  testWidgets('failed menu Cut preserves targets and undo history', (tester) async {
    final store = TestCanvasDocumentStore(_menuDocument);
    await pumpCanvas(tester, store, writeClipboardText: (_) async => throw StateError('denied'));
    await _openMenu(tester, const Offset(310, 310));
    await tester.tap(find.text('Cut'));
    await tester.pumpAndSettle();
    expect(find.text('Could not cut canvas elements'), findsOneWidget);
    expect(_models(tester).map((model) => model.data.id), ['a', 'b']);
    await pumpPastSave(tester);
    expect(store.persisted, isNull);
    await _shortcut(tester, LogicalKeyboardKey.keyZ);
    expect(_models(tester), hasLength(2));
  });

  for (final emptyCanvas in [false, true]) {
    testWidgets(
      'delayed menu Paste centers at captured ${emptyCanvas ? 'empty canvas' : 'object'} location under zoom',
      (tester) async {
        final store = TestCanvasDocumentStore(_menuDocument);
        final read = Completer<CanvasClipboardSnapshot>();
        await pumpCanvas(tester, store, readClipboard: () => read.future);
        final canvas = tester.widget<LazyCanvas>(find.byType(LazyCanvas)).controller
          ..updateScalebyDelta(0.5, focalPoint: Offset.zero);
        await tester.pumpAndSettle();
        final first = _models(tester).first..selected = true;
        final position = emptyCanvas ? const Offset(600, 420) : canvas.getInfo('a').ssPosition + const Offset(5, 5);
        final target = canvas.offset + position / canvas.scale;
        await _openMenu(tester, position);
        expect(first.selected, isTrue);
        if (emptyCanvas) {
          expect(find.text('Arrange'), findsNothing);
          expect(find.text('Copy'), findsNothing);
          expect(find.text('Delete'), findsNothing);
        }
        await tester.tap(find.text('Paste'));
        await tester.pump();
        expect(find.text('Paste'), findsNothing);
        final mouse = await tester.createGesture(pointer: 99, kind: PointerDeviceKind.mouse);
        await mouse.moveTo(const Offset(750, 550));
        canvas.updateScalebyDelta(0.25);
        await tester.pump();
        read.complete((text: encodeCanvasClipboard(_menuDocument.elements), image: null));
        await tester.pumpAndSettle();
        expect(_selectedBounds(tester).center, target);
        final pasted = _models(tester).where((model) => model.selected).toList();
        expect(pasted, hasLength(2));
        expect(pasted[1].canvasPosition - pasted[0].canvasPosition, const Offset(200, 0));
        expect(canvas.childOrder.skip(2), pasted.map((model) => model.data.id));
        await pumpPastSave(tester);
        expect(store.persisted!.elements, hasLength(4));
        await _shortcut(tester, LogicalKeyboardKey.keyZ);
        expect(canvas.childOrder, ['a', 'b']);
        await _shortcut(tester, LogicalKeyboardKey.keyZ);
        expect(canvas.childOrder, ['a', 'b']);
        await mouse.removePointer();
      },
    );
  }

  for (final image in [false, true]) {
    testWidgets('menu Paste centers ${image ? 'images' : 'media URLs'} at its captured location', (tester) async {
      final read = Completer<CanvasClipboardSnapshot>();
      final store = TestCanvasDocumentStore(_emptyDocument);
      await pumpCanvas(
        tester,
        store,
        attachmentStore: TestAttachmentStore(),
        readClipboard: () => read.future,
      );
      final canvas = tester.widget<LazyCanvas>(find.byType(LazyCanvas)).controller
        ..updateScalebyDelta(0.5, focalPoint: Offset.zero);
      await tester.pumpAndSettle();
      const position = Offset(400, 300);
      final target = canvas.offset + position / canvas.scale;
      await _openMenu(tester, position);
      await tester.runAsync(() async {
        tester
            .widget<MenuItemButton>(
              find.ancestor(of: find.text('Paste'), matching: find.byType(MenuItemButton)),
            )
            .onPressed!();
        canvas.updateScalebyDelta(0.5);
        read.complete((
          text: 'https://example.com/image.png',
          image: image ? (bytes: onePixelPngBytes, extension: 'png') : null,
        ));
        await Future.doWhile(() async {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          await tester.pump();
          return store.persisted?.elements.length != 1;
        }).timeout(const Duration(seconds: 5));
      });
      await tester.pumpAndSettle();
      final model = tester.widget<MediaTool>(find.byType(MediaTool)).model;
      expect((model.canvasPosition & model.canvasSize).center, target);
      expect(model.selected, isTrue);
      await pumpPastSave(tester);
      expect(store.persisted!.elements, hasLength(1));
      await _shortcut(tester, LogicalKeyboardKey.keyZ);
      expect(canvas.childOrder, isEmpty);
    });
  }

  for (final key in [
    LogicalKeyboardKey.keyC,
    LogicalKeyboardKey.keyX,
    LogicalKeyboardKey.keyV,
    LogicalKeyboardKey.delete,
  ]) {
    for (final platform in [TargetPlatform.linux, TargetPlatform.macOS]) {
      testWidgets('$platform menu shortcut $key uses captured targets and position', (tester) async {
        String? payload;
        await pumpCanvas(
          tester,
          TestCanvasDocumentStore(_menuDocument),
          platform: platform,
          writeClipboardText: (text) async => payload = text,
          readClipboard: () async => (text: encodeCanvasClipboard(_menuDocument.elements), image: null),
        );
        await _openMenu(tester, const Offset(310, 310));
        for (final model in _models(tester)) {
          model.selected = model.data.id == 'b';
        }
        if (key == LogicalKeyboardKey.delete) {
          await tester.sendKeyEvent(platform == TargetPlatform.macOS ? LogicalKeyboardKey.backspace : key);
        } else {
          await _shortcut(tester, key, platform: platform);
        }
        await tester.pumpAndSettle();
        expect(find.text('Arrange'), findsNothing);
        if (key == LogicalKeyboardKey.keyC || key == LogicalKeyboardKey.keyX) {
          expect(decodeCanvasClipboard(payload!)!.single.id, 'a');
        }
        if (key == LogicalKeyboardKey.keyX || key == LogicalKeyboardKey.delete) {
          expect(_models(tester).single.data.id, 'b');
        } else if (key == LogicalKeyboardKey.keyV) {
          expect(_selectedBounds(tester).center, const Offset(310, 310));
        } else {
          expect(_models(tester), hasLength(2));
        }
      });
    }
  }

  for (final cut in [false, true]) {
    testWidgets('pending ${cut ? 'Cut' : 'Paste'} is canceled by document undo', (tester) async {
      final read = Completer<CanvasClipboardSnapshot>();
      final write = Completer<void>();
      final store = TestCanvasDocumentStore(_menuDocument);
      await pumpCanvas(tester, store, readClipboard: () => read.future, writeClipboardText: (_) => write.future);
      final model = tester.widgetList<Shape>(find.byType(Shape)).first.model;
      final position = model.data.position;
      model.moveBy(const Offset(10, 10));
      await tester.pump();
      await _openMenu(tester, const Offset(320, 320));
      await tester.tap(find.text(cut ? 'Cut' : 'Paste'));
      await tester.pump();
      await _shortcut(tester, LogicalKeyboardKey.keyZ);
      expect(model.data.position, position);
      read.complete((text: encodeCanvasClipboard(_menuDocument.elements), image: null));
      write.complete();
      await tester.pumpAndSettle();
      expect(tester.widget<LazyCanvas>(find.byType(LazyCanvas)).controller.childOrder, ['a', 'b']);
      expect(tester.widgetList<Shape>(find.byType(Shape)).first.model, same(model));
      await pumpPastSave(tester);
      expect(store.persisted!.toJson(), _menuDocument.toJson());
    });

    testWidgets('pending ${cut ? 'Cut' : 'Paste'} cannot affect a replacement document', (tester) async {
      final read = Completer<CanvasClipboardSnapshot>();
      final write = Completer<void>();
      await pumpCanvas(
        tester,
        TestCanvasDocumentStore(_menuDocument),
        readClipboard: () => read.future,
        writeClipboardText: (_) => write.future,
      );
      await _openMenu(tester, const Offset(310, 310));
      await tester.tap(find.text(cut ? 'Cut' : 'Paste'));
      await tester.pump();
      tester.widget<CanvasTitle>(find.byType(CanvasTitle)).onPressed!();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('New canvas'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Fresh');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      tester.widget<CanvasTitle>(find.byType(CanvasTitle)).onPressed!();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Untitled'));
      await tester.pumpAndSettle();
      read.complete((text: encodeCanvasClipboard(_menuDocument.elements), image: null));
      write.complete();
      await tester.pumpAndSettle();
      expect(tester.widget<LazyCanvas>(find.byType(LazyCanvas)).controller.childOrder, ['a', 'b']);
      expect(tester.takeException(), isNull);
    });
  }

  for (final failDelete in [false, true]) {
    testWidgets(
      'canceled canvas image paste ${failDelete ? 'stays canceled if cleanup fails' : 'deletes its written attachment'}',
      (tester) async {
        final attachments = (await tester.runAsync(() async => _PausedImageWrite(failDeletes: failDelete)))!;
        final store = TestCanvasDocumentStore(_menuDocument);
        await pumpCanvas(
          tester,
          store,
          attachmentStore: attachments,
          readClipboard: () async => (text: null, image: (bytes: onePixelPngBytes, extension: 'png')),
        );
        final model = tester.widgetList<Shape>(find.byType(Shape)).first.model;
        final position = model.canvasPosition;
        model.moveBy(const Offset(10, 10));
        await pumpPastSave(tester);
        await tester.runAsync(() async {
          await _shortcut(tester, LogicalKeyboardKey.keyV);
          await attachments.started.future;
        });
        await _shortcut(tester, LogicalKeyboardKey.keyZ);
        expect(model.canvasPosition, position);
        await tester.runAsync(() async {
          attachments.release.complete();
          await attachments.finished.future;
          await Future<void>.delayed(Duration.zero);
        });
        await tester.pumpAndSettle();
        expect(find.byType(MediaTool), findsNothing);
        expect(attachments.files, hasLength(failDelete ? 1 : 0));
        expect(find.text('Could not paste canvas elements'), findsNothing);
        await pumpPastSave(tester);
        expect(store.persisted!.toJson(), _menuDocument.toJson());
      },
    );
  }

  testWidgets('routes image clipboard content to media', (
    tester,
  ) async {
    final attachments = TestAttachmentStore();
    CanvasClipboardSnapshot clipboard = (
      text: ' https://example.com/image.png ',
      image: null,
    );
    await pumpCanvas(
      tester,
      TestCanvasDocumentStore(_emptyDocument),
      attachmentStore: attachments,
      readClipboard: () async => clipboard,
    );

    await _shortcut(tester, LogicalKeyboardKey.keyV);
    await tester.pump();
    expect(
      tester.widget<MediaTool>(find.byType(MediaTool)).model.data.url,
      'https://example.com/image.png',
    );

    clipboard = (text: 'ordinary text', image: null);
    await _shortcut(tester, LogicalKeyboardKey.keyV);
    expect(find.byType(MediaTool), findsOneWidget);

    clipboard = (
      text: 'https://example.com/ignored.png',
      image: (bytes: onePixelPngBytes, extension: 'png'),
    );
    await tester.runAsync(
      () async {
        await _shortcut(tester, LogicalKeyboardKey.keyV);
        await Future<void>.delayed(const Duration(milliseconds: 100));
      },
    );
    await tester.pumpAndSettle();

    final pasted = tester.widgetList<MediaTool>(find.byType(MediaTool)).last.model;
    expect(pasted.data.url, matches(attachmentPathPattern));
    expect(attachments.files[pasted.data.url], onePixelPngBytes);
  });
}

// ---------- Test helpers ----------

Future<void> _openMenu(WidgetTester tester, Offset position) async {
  final click = await tester.startGesture(position, kind: PointerDeviceKind.mouse, buttons: kSecondaryButton);
  await click.up();
  await tester.pumpAndSettle();
}

Future<void> _shortcut(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  TargetPlatform platform = TargetPlatform.linux,
}) async {
  final modifier = platform == TargetPlatform.macOS ? LogicalKeyboardKey.metaLeft : LogicalKeyboardKey.controlLeft;
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyDownEvent(key);
  await tester.sendKeyUpEvent(key);
  await tester.sendKeyUpEvent(modifier);
  await tester.pump();
}

List<CanvasElementModel> _models(WidgetTester tester) => <CanvasElementModel>[
  ...tester.widgetList<TextTool>(find.byType(TextTool)).map((widget) => widget.model),
  ...tester.widgetList<CodeTool>(find.byType(CodeTool)).map((widget) => widget.model),
  ...tester.widgetList<PenStroke>(find.byType(PenStroke)).map((widget) => widget.model),
  ...tester.widgetList<Arrow>(find.byType(Arrow)).map((widget) => widget.model),
  ...tester.widgetList<Shape>(find.byType(Shape)).map((widget) => widget.model),
  ...tester.widgetList<MediaTool>(find.byType(MediaTool)).map((widget) => widget.model),
];

void _expectOnlySelected(WidgetTester tester, Set<String> ids) {
  for (final model in _models(tester)) {
    expect(model.selected, ids.contains(model.data.id), reason: model.data.id);
  }
}

List<String> _types(Iterable<CanvasElementData> elements) => elements.map((element) => element.type).toList();

Rect _selectedBounds(WidgetTester tester) =>
    _models(tester)
        .where((model) => model.selected)
        .map((model) => model.canvasPosition & model.canvasSize)
        .reduce((bounds, next) => bounds.expandToInclude(next));

void _expectShifted(
  CanvasElementData source,
  CanvasElementData result,
  Offset delta,
) {
  expect(result.type, source.type);
  switch ((source, result)) {
    case (final TextElementData source, final TextElementData result):
      expect(result.position, source.position + delta);
      expect(result.markdown, source.markdown);
      expect(result.style.toJson(), source.style.toJson());
    case (final CodeElementData source, final CodeElementData result):
      expect(result.position, source.position + delta);
      expect(result.source, source.source);
      expect(result.language, source.language);
      expect(result.title, source.title);
      expect(result.showLineNumbers, source.showLineNumbers);
      expect(result.background, source.background);
    case (final PenElementData source, final PenElementData result):
      expect(result.position, source.position + delta);
      expect(result.toJson()['points'], source.toJson()['points']);
      expect(result.color, source.color);
      expect(result.width, source.width);
    case (final ArrowElementData source, final ArrowElementData result):
      expect(result.start, source.start + delta);
      expect(result.controls, source.controls.map((point) => point + delta).toList());
      expect(result.end, source.end + delta);
      expect(result.color, source.color);
      expect(result.strokeStyle, source.strokeStyle);
      expect(result.strokeWidth, source.strokeWidth);
    default:
      fail('Mismatched element types');
  }
}

// ---------- Fixtures ----------

final _document = CanvasDocument(
  background: CanvasBackgroundKind.plain,
  elements: [
    TextElementData(
      id: 'text',
      position: const Offset(10, 20),
      width: 280,
      height: null,
      markdown: 'hello',
      style: const TextNodeStyle(
        fontFamily: 'ABeeZee',
        color: Color(0xff201C1A),
      ),
    ),
    CodeElementData(
      id: 'code',
      position: const Offset(40, 50),
      size: const Size(280, 240),
      language: CodeLanguage.dart,
      source: 'void main() {}',
      title: 'main.dart',
      showLineNumbers: true,
      background: BlockBackgroundKind.glass,
    ),
    PenElementData(
      id: 'pen',
      position: const Offset(70, 80),
      size: const Size(10, 10),
      hitSlop: 0,
      color: const Color(0xff000000),
      width: 1,
      points: const [PenPointData(Offset.zero, pressure: 0)],
    ),
    ArrowElementData(
      id: 'arrow',
      start: const Offset(100, 110),
      controls: const [Offset(110, 114), Offset(140, 90), Offset(170, 130)],
      end: const Offset(120, 110),
      color: const Color(0xff000000),
      strokeStyle: ArrowStrokeStyle.solid,
      strokeWidth: 2,
    ),
  ],
);

final _emptyDocument = CanvasDocument(
  background: CanvasBackgroundKind.plain,
  elements: [],
);

final _menuDocument = CanvasDocument(
  background: CanvasBackgroundKind.plain,
  elements: [
    for (final (id, x) in [('a', 300.0), ('b', 500.0)])
      ShapeElementData(
        autoArrange: false,
        id: id,
        kind: ShapeKind.rectangle,
        position: Offset(x, 300),
        size: const Size(80, 80),
        strokeColor: const Color(0xff000000),
        fillColor: const Color(0xffffffff),
        strokeWidth: 2,
      ),
  ],
);

class _PausedImageWrite extends TestAttachmentStore {
  _PausedImageWrite({required this.failDeletes});

  final bool failDeletes;
  final started = Completer<void>();
  final release = Completer<void>();
  final finished = Completer<void>();

  @override
  Future<void> write(String path, Uint8List bytes) async {
    started.complete();
    await release.future;
    await super.write(path, bytes);
  }

  @override
  Future<void> delete(String path) async {
    try {
      if (failDeletes) throw StateError('delete failed');
      await super.delete(path);
    } finally {
      finished.complete();
    }
  }
}
