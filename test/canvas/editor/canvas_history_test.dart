// Verifies undo and redo behavior for canvas mutations.
// Exercises editor history through persisted element changes.

import 'dart:async';
import 'dart:ui' as ui;

import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/editor/canvas_element_model.dart';
import 'package:elseplane/canvas/editor/canvas_page.dart';
import 'package:elseplane/canvas/editor/widgets/toolbar_button.dart';
import 'package:elseplane/canvas/tools/arrow/arrow_tool.dart';
import 'package:elseplane/canvas/tools/code/code_tool.dart';
import 'package:elseplane/canvas/tools/media/media_tool.dart';
import 'package:elseplane/canvas/tools/pen/pen_tool.dart';
import 'package:elseplane/canvas/tools/shape/shape_tool.dart';
import 'package:elseplane/canvas/tools/text/text_tool.dart';
import 'package:elseplane/library/canvas_library.dart';
import 'package:elseplane/theme/fonts.dart';
import 'package:elseplane/ui/common/select.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts_lite.dart';
import 'package:infinite_lazy_grid/infinite_lazy_grid.dart';
import 'package:shared_preferences_web/shared_preferences_web.dart';
import 'package:super_clipboard/super_clipboard.dart';

import '../test_helpers.dart';

// ---------- Tests ----------

void main() {
  setUp(() {
    SharedPreferencesAsyncWeb.registerWith(null);
    GoogleFontsLite.config.allowRuntimeFetching = false;
  });
  tearDown(() => GoogleFontsLite.config.allowRuntimeFetching = true);

  for (final media in [false, true]) {
    for (final unchanged in [false, true]) {
      for (final failure in [false, true]) {
        testWidgets(
          '${media ? 'media' : 'text'} pending image ${failure ? 'failure' : 'write'} cannot change ${unchanged ? 'unchanged' : 'moved'} undo target or redo',
          (tester) async {
            var document = _textDocument().withElements((elements) => elements.add(_penDocument(1).elements.single));
            if (media) {
              document = document.withElements(
                (elements) => elements[0] = MediaElementData(
                  id: 'media',
                  position: const Offset(200, 240),
                  width: 280,
                  url: 'original',
                ),
              );
            }
            final store = TestLibraryStore(document);
            final attachments = (await tester.runAsync(() async => _PausedWrite()))!;
            const existingPath = 'attachments/11111111-1111-4111-8111-111111111111.png';
            attachments.files[existingPath] = onePixelPngBytes;
            await pumpCanvas(tester, store, attachmentStore: attachments);
            final text = media ? null : tester.widget<TextTool>(find.byType(TextTool)).model;
            final image = media ? tester.widget<MediaTool>(find.byType(MediaTool)).model : null;
            final target = (media ? image! : text!) as CanvasElementModel;
            final moved = unchanged ? _stroke(tester) : target;
            final start = moved.canvasPosition;
            moved.moveBy(const Offset(20, 10));
            await pumpPastSave(tester);
            late Future<void> pending;
            await tester.runAsync(() async {
              pending = media
                  ? image!.setDeviceImage(onePixelPngBytes, 'png')
                  : text!.insertPastedImage(onePixelPngBytes, 'png', attachments);
              await attachments.started.future;
            });
            await _shortcut(tester);
            expect(moved.canvasPosition, start);
            await tester.runAsync(() async {
              if (failure) {
                attachments.release.completeError(StateError('write failed'));
              } else {
                attachments.release.complete();
              }
              await pending;
            });
            expect(attachments.files, {existingPath: onePixelPngBytes});
            expect(media ? image!.data.url : text!.data.markdown, 'original');
            expect(
              media
                  ? tester.widget<MediaTool>(find.byType(MediaTool)).model
                  : tester.widget<TextTool>(find.byType(TextTool)).model,
              same(target),
            );
            await pumpPastSave(tester);
            expect(
              media
                  ? (store.persisted!.elements.first as MediaElementData).url
                  : (store.persisted!.elements.first as TextElementData).markdown,
              'original',
            );
            await _shortcut(tester, redo: true);
            expect(moved.canvasPosition, start + const Offset(20, 10));
            expect(media ? image!.data.url : text!.data.markdown, 'original');
          },
        );
      }
    }
  }

  for (final media in [false, true]) {
    for (final failDelete in [false, true]) {
      testWidgets(
        '${media ? 'media' : 'text'} disposed upload ${failDelete ? 'stays canceled if deletion fails' : 'deletes its completed write'}',
        (tester) async {
          final attachments = (await tester.runAsync(() async => _PausedWrite(failDeletes: failDelete)))!;
          var document = _textDocument();
          if (media) {
            document = document.withElements(
              (elements) => elements[0] = MediaElementData(
                id: 'media',
                position: const Offset(200, 240),
                width: 280,
                url: 'original',
              ),
            );
          }
          await pumpCanvas(tester, TestLibraryStore(document), attachmentStore: attachments);
          final text = media ? null : tester.widget<TextTool>(find.byType(TextTool)).model;
          final image = media ? tester.widget<MediaTool>(find.byType(MediaTool)).model : null;
          late Future<void> pending;
          await tester.runAsync(() async {
            pending = media
                ? image!.setDeviceImage(onePixelPngBytes, 'png')
                : text!.insertPastedImage(onePixelPngBytes, 'png', attachments);
            await attachments.started.future;
          });
          await tester.pumpWidget(const SizedBox());
          await tester.runAsync(() async {
            attachments.release.complete();
            await pending;
          });
          expect(media ? image!.data.url : text!.data.markdown, 'original');
          expect(attachments.files, hasLength(failDelete ? 1 : 0));
        },
      );
    }
  }

  for (final removal in [false, true]) {
    testWidgets('pending write cancels immediately on ${removal ? 'removal' : 'document replacement'}', (tester) async {
      final attachments = (await tester.runAsync(() async => _PausedWrite()))!;
      final store = TestLibraryStore(_textDocument());
      await pumpCanvas(tester, store, attachmentStore: attachments);
      final text = tester.widget<TextTool>(find.byType(TextTool)).model;
      late Future<void> pending;
      await tester.runAsync(() async {
        pending = text.insertPastedImage(onePixelPngBytes, 'png', attachments);
        await attachments.started.future;
      });
      if (removal) {
        text.selected = true;
        await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      } else {
        (tester.widget<CanvasPage>(find.byType(CanvasPage)).replacement as ValueNotifier<CanvasReplacement>).value = (
          document: CanvasLibrary.emptyDocument,
          token: Object(),
        );
      }
      expect(text.disposed, isFalse);
      expect(text.asyncEditGeneration, greaterThan(0));
      await tester.runAsync(() async {
        attachments.release.complete();
        await pending;
      });
      expect(text.data.markdown, 'original');
      expect(attachments.files, isEmpty);
      await tester.pumpAndSettle();
    });
  }

  for (final media in [false, true]) {
    testWidgets('pending ${media ? 'media' : 'text'} paste stays canceled after leaving editing and tool-only undo', (
      tester,
    ) async {
      var document = _textDocument();
      if (media) {
        document = document.withElements(
          (elements) => elements[0] = MediaElementData(
            id: 'media',
            position: const Offset(200, 240),
            width: 280,
            url: 'original',
          ),
        );
      }
      await pumpCanvas(tester, TestLibraryStore(document));
      final text = media ? null : tester.widget<TextTool>(find.byType(TextTool)).model;
      final image = media ? tester.widget<MediaTool>(find.byType(MediaTool)).model : null;
      await tester.tap(find.byKey(ValueKey(media ? 'media-url-field' : 'text-markdown-preview')));
      await tester.pump();
      (media ? image!.controller : text!.controller).selection = const TextSelection.collapsed(offset: 8);
      final reader = Completer<ClipboardReader>();
      final pending = media ? image!.paste(reader.future) : text!.paste(reader.future, TestAttachmentStore());
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.tap(find.byKey(const ValueKey('toolbar-draw')));
      await tester.pump();
      await _shortcut(tester);
      reader.complete(_HistoryTextReader());
      await pending;
      expect(media ? image!.data.url : text!.data.markdown, 'original');
      await pumpPastSave(tester);
    });
  }

  testWidgets('unchanged-source attachment read finishes through undo', (tester) async {
    const path = 'attachments/11111111-1111-4111-8111-111111111111.png';
    final attachments = _PausedRead();
    final document = _textDocument().withElements(
      (elements) => elements.add(MediaElementData(id: 'media', position: const Offset(80, 100), width: 120, url: path)),
    );
    await _cacheAttachmentImage();
    await pumpCanvas(tester, TestLibraryStore(document), attachmentStore: attachments);
    final media = tester.widget<MediaTool>(find.byType(MediaTool)).model;
    tester.widget<TextTool>(find.byType(TextTool)).model.moveBy(const Offset(20, 10));
    await pumpPastSave(tester);
    await _shortcut(tester);
    attachments.bytes.complete(onePixelPngBytes);
    await tester.pumpAndSettle();
    expect(media.hasImage, isTrue);
    expect(attachments.reads, 1);
  });

  testWidgets('unrelated undo retains mixed canvas resources and widget states', (tester) async {
    var document = _textDocument();
    document = document.withElements(
      (elements) => elements.addAll([
        (_codeDocument().elements.first as CodeElementData).copyWith(position: const Offset(500, 240)),
        MediaElementData(
          id: 'media',
          position: const Offset(80, 100),
          width: 120,
          url: 'attachments/11111111-1111-4111-8111-111111111111.png',
        ),
        _penDocument(1).elements.single,
      ]),
    );
    document = document.withElements(
      (elements) => elements.add(
        (_penDocument(1).elements.single as PenElementData).copyWith(
          id: 'offscreen',
          position: const Offset(10000, 10000),
        ),
      ),
    );
    document = document.withElements(
      (elements) => elements[1] = (elements[1] as CodeElementData).copyWith(
        source: List.generate(80, (i) => '$i ${'long source ' * 30}').join('\n'),
      ),
    );
    final attachments = _CountingAttachments({
      'attachments/11111111-1111-4111-8111-111111111111.png': onePixelPngBytes,
    });
    final store = TestLibraryStore(document);
    await _cacheAttachmentImage();
    await pumpCanvas(tester, store, attachmentStore: attachments);
    await tester.pumpAndSettle();
    final text = tester.widget<TextTool>(find.byType(TextTool)).model;
    final codeFinder = find.byType(CodeTool);
    final code = tester.widget<CodeTool>(codeFinder).model;
    final codeState = tester.state(codeFinder);
    final imageFinder = find.byKey(const ValueKey('media-image'));
    final imageState = tester.state(imageFinder);
    final media = tester.widget<MediaTool>(find.byType(MediaTool)).model;
    final image = media.image;
    final pen = _stroke(tester);
    code.scrollController.verticalScroller.jumpTo(120);
    await tester.pump();
    final vertical = code.scrollController.verticalScroller.offset;
    final horizontal = code.scrollController.horizontalScroller;
    expect(vertical, greaterThan(0));
    text.controller.text = 'changed';
    await _shortcut(tester);
    expect(text.controller.text, 'original');
    for (final redo in [true, false, true]) {
      await _shortcut(tester, redo: redo);
      expect(tester.widget<TextTool>(find.byType(TextTool)).model, same(text));
      expect(tester.widget<CodeTool>(codeFinder).model, same(code));
      expect(tester.state(codeFinder), same(codeState));
      expect(tester.state(imageFinder), same(imageState));
      expect(media.image, same(image));
      expect(_stroke(tester), same(pen));
      expect(code.scrollController.verticalScroller.offset, vertical);
      expect(code.scrollController.horizontalScroller, same(horizontal));
      expect(attachments.reads, 1);
      expect(
        tester.widget<LazyCanvas>(find.byType(LazyCanvas)).controller.childOrder,
        redo
            ? [...document.elements.skip(1).map((data) => data.id), 'text']
            : document.elements.map((data) => data.id).toList(),
      );
    }
    await pumpPastSave(tester);
    expect(store.persisted!.elements.whereType<TextElementData>().single.markdown, 'changed');
  });

  testWidgets('code restore synchronizes source and visible title without extra history', (tester) async {
    final store = TestLibraryStore(_codeDocument().withElements((elements) => elements.removeLast()));
    await pumpCanvas(tester, store);
    final code = tester.widget<CodeTool>(find.byType(CodeTool)).model;
    final controller = code.controller;
    final titleController = code.titleController;
    controller.runRevocableOp(() => controller.text = 'changed source');
    titleController.text = 'changed.dart';
    code
      ..moveBy(const Offset(10, 10))
      ..rotate(0.2)
      ..size = const Size(300, 260);
    await _shortcut(tester);
    expect(tester.widget<CodeTool>(find.byType(CodeTool)).model, same(code));
    expect(code.controller, same(controller));
    expect(code.titleController, same(titleController));
    expect(controller.text, 'void main() {}');
    expect(controller.canUndo, isFalse);
    expect(titleController.text, 'main.dart');
    expect(find.text('main.dart'), findsOneWidget);
    expect(code.rotation, 0);
    expect(code.size, const Size(280, 240));
    await _shortcut(tester, redo: true);
    expect(controller.text, 'changed source');
    expect(titleController.text, 'changed.dart');
    expect(find.text('changed.dart'), findsOneWidget);
    expect(code.rotation, 0.2);
    final canvas = tester.widget<LazyCanvas>(find.byType(LazyCanvas)).controller;
    expect(canvas.getInfo(code.data.id).gsPosition, code.canvasPosition);
    await _shortcut(tester);
    await _shortcut(tester);
    expect(controller.text, 'void main() {}');
    await _shortcut(tester, redo: true);
    expect(controller.text, 'changed source');
  });

  testWidgets('media transforms retain image and changed sources reload on restore', (tester) async {
    final attachments = _CountingAttachments({
      'attachments/11111111-1111-4111-8111-111111111111.png': onePixelPngBytes,
      'attachments/22222222-2222-4222-8222-222222222222.png': onePixelPngBytes,
    });
    final store = TestLibraryStore(
      CanvasDocument(
        background: CanvasBackgroundKind.plain,
        elements: [
          MediaElementData(
            id: 'media',
            position: const Offset(200, 200),
            width: 160,
            url: 'attachments/11111111-1111-4111-8111-111111111111.png',
          ),
        ],
      ),
    );
    await _cacheAttachmentImage();
    await pumpCanvas(tester, store, attachmentStore: attachments);
    await tester.pumpAndSettle();
    final media = tester.widget<MediaTool>(find.byType(MediaTool)).model;
    final image = media.image;
    expect(media.hasImage, isTrue);
    media
      ..moveBy(const Offset(10, 20))
      ..rotate(0.3)
      ..resizeBy(const Offset(50, 50));
    await _shortcut(tester);
    expect(media.data.position, const Offset(200, 200));
    expect(media.rotation, 0);
    expect(media.data.width, 160);
    expect(media.image, same(image));
    expect(attachments.reads, 1);
    await _shortcut(tester, redo: true);
    expect(media.rotation, 0.3);
    expect(media.image, same(image));
    media.controller.text = 'attachments/22222222-2222-4222-8222-222222222222.png';
    media.commitUrl();
    await tester.pumpAndSettle();
    expect(attachments.reads, 2);
    await _shortcut(tester);
    await tester.pumpAndSettle();
    expect(media.controller.text, 'attachments/11111111-1111-4111-8111-111111111111.png');
    expect(media.data.url, 'attachments/11111111-1111-4111-8111-111111111111.png');
    expect(media.hasImage, isTrue);
    expect(attachments.reads, 3);
    await _shortcut(tester, redo: true);
    await tester.pumpAndSettle();
    expect(media.data.url, 'attachments/22222222-2222-4222-8222-222222222222.png');
    expect(attachments.reads, 4);
  });

  test('ordinary edits preserve published values and pending edit generations', () {
    final model = TextBlockModel(_textDocument().elements.single as TextElementData);
    final original = model.data;
    final document = CanvasDocument(background: CanvasBackgroundKind.plain, elements: [original]);
    final generation = model.asyncEditGeneration;
    var edits = 0;
    model.documentChanges.addListener(() => edits++);
    model
      ..moveBy(Offset.zero)
      ..autoArrange = original.autoArrange;
    expect(edits, 0);
    model.moveBy(const Offset(20, 10));
    model.controller.text = 'changed';
    model.autoArrange = !original.autoArrange;
    expect(edits, 3);
    expect(model.asyncEditGeneration, generation);
    expect(document.elements.single, same(original));
    expect(model.data.position, original.position + const Offset(20, 10));
    expect(original.markdown, isNot('changed'));
    expect(original.autoArrange, isNot(model.autoArrange));
    model.restoreData(original);
    expect(model.asyncEditGeneration, generation + 1);
    expect(model.data, same(original));
    expect(model.controller.text, original.markdown);
    expect(edits, 3);
    model.dispose();
  });

  test('restore rejects identity changes and refreshes pen geometry without edits', () {
    final pen = PenStrokeModel(_penDocument(1).elements.single as PenElementData);
    var edits = 0;
    pen.documentChanges.addListener(() => edits++);
    final path = pen.path;
    final snapshot = pen.data.copyWith(width: 20);
    pen.restoreData(snapshot);
    expect(pen.path, isNot(same(path)));
    expect(pen.path.getBounds(), isNot(path.getBounds()));
    expect(edits, 0);
    expect(() => pen.restoreData(snapshot.copyWith(id: 'other')), throwsArgumentError);
    expect(pen.data, same(snapshot));
    pen.dispose();
  });

  testWidgets('background undo retains objects and saves one reversible step', (tester) async {
    final store = TestLibraryStore(_document());
    await pumpCanvas(tester, store);
    final pen = _stroke(tester);
    final canvas = tester.widget<LazyCanvas>(find.byType(LazyCanvas)).controller;
    final originalBackground = canvas.background;
    await tester.tap(find.byKey(const ValueKey('settings-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Canvas').last);
    await tester.pumpAndSettle();
    tester.widget<Select<CanvasBackgroundKind>>(find.byKey(const ValueKey('canvas-background-select'))).onChanged!(
      CanvasBackgroundKind.dotGrid,
    );
    await tester.tap(find.byKey(const ValueKey('settings-close')));
    await tester.pumpAndSettle();
    await pumpPastSave(tester);
    expect(store.persisted!.background, CanvasBackgroundKind.dotGrid);
    expect(canvas.background, isNot(same(originalBackground)));
    await _shortcut(tester);
    await pumpPastSave(tester);
    expect(store.persisted!.background, CanvasBackgroundKind.plain);
    final restoredBackground = canvas.background;
    await _shortcut(tester);
    expect(canvas.background, same(restoredBackground));
    expect(_stroke(tester), same(pen));
    await _shortcut(tester, redo: true);
    await pumpPastSave(tester);
    expect(store.persisted!.background, CanvasBackgroundKind.dotGrid);
    expect(_stroke(tester), same(pen));
  });

  testWidgets('stroke undo keeps Pen ready and tool selection is a separate step', (tester) async {
    final store = TestLibraryStore(_penDocument(0));
    await pumpCanvas(tester, store);
    await tester.tap(find.byKey(const ValueKey('toolbar-draw')));
    await tester.pump();
    await _draw(tester);
    expect(find.byType(PenStroke), findsOneWidget);

    await _shortcut(tester);
    expect(find.byType(PenStroke), findsNothing);
    expect(_toolSelected(tester, 'draw'), isTrue);
    await _shortcut(tester);
    expect(_toolSelected(tester, 'draw'), isFalse);
    await _shortcut(tester, redo: true);
    expect(_toolSelected(tester, 'draw'), isTrue);
    expect(find.byType(PenStroke), findsNothing);
    await _shortcut(tester, redo: true);
    expect(find.byType(PenStroke), findsOneWidget);
    expect(_toolSelected(tester, 'draw'), isTrue);

    await _shortcut(tester);
    await _draw(tester);
    final newStroke = _stroke(tester);
    await _shortcut(tester, redo: true);
    expect(_stroke(tester), same(newStroke));
    await pumpPastSave(tester);
    expect(store.persisted!.elements.single.id, newStroke.data.id);
  });

  for (final (tool, key) in const [
    ('text', LogicalKeyboardKey.keyT),
    ('code', LogicalKeyboardKey.keyC),
    ('media', LogicalKeyboardKey.keyM),
    ('shape', LogicalKeyboardKey.keyS),
    ('draw', LogicalKeyboardKey.keyP),
    ('erase', LogicalKeyboardKey.keyE),
    ('arrow', LogicalKeyboardKey.keyA),
  ]) {
    testWidgets('$tool choice, toggle, and Escape undo without saving or replacing objects', (tester) async {
      final store = TestLibraryStore(_document());
      await pumpCanvas(tester, store);
      final original = _stroke(tester)..selected = true;
      await tester.tap(find.byKey(ValueKey('toolbar-$tool')));
      await tester.pump();
      expect(_toolSelected(tester, tool), isTrue);
      await _shortcut(tester);
      expect(_toolSelected(tester, tool), isFalse);
      await _shortcut(tester, redo: true);
      expect(_toolSelected(tester, tool), isTrue);

      await tester.sendKeyEvent(key);
      await tester.pump();
      expect(_toolSelected(tester, tool), isFalse);
      await _shortcut(tester);
      expect(_toolSelected(tester, tool), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(_toolSelected(tester, tool), isFalse);
      await _shortcut(tester);
      expect(_toolSelected(tester, tool), isTrue);
      await _shortcut(tester);
      expect(_toolSelected(tester, tool), isFalse);

      // Escape in the default tool must leave redo available.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _shortcut(tester, redo: true);
      expect(_toolSelected(tester, tool), isTrue);
      final next = tool == 'draw' ? 'erase' : 'draw';
      await tester.tap(find.byKey(ValueKey('toolbar-$next')));
      await tester.pump();
      await _shortcut(tester, redo: true);
      expect(_toolSelected(tester, next), isTrue);
      await _shortcut(tester);
      expect(_toolSelected(tester, tool), isTrue);
      expect(_stroke(tester), same(original));
      await pumpPastSave(tester);
      expect(store.persisted, isNull);
    });
  }

  for (final (tool, type) in const [
    ('text', TextTool),
    ('code', CodeTool),
    ('media', MediaTool),
    ('shape', Shape),
    ('arrow', Arrow),
  ]) {
    testWidgets('$tool placement undo restores its tool and redo returns to Select', (tester) async {
      final store = TestLibraryStore(_penDocument(0));
      await pumpCanvas(tester, store);
      await tester.tap(find.byKey(ValueKey('toolbar-$tool')));
      await tester.pump();
      if (tool == 'shape' || tool == 'arrow') {
        await _draw(tester);
      } else {
        await tester.tapAt(const Offset(300, 250));
        await tester.pumpAndSettle();
      }
      expect(find.byType(type), findsOneWidget);
      expect(_toolSelected(tester, tool), isFalse);
      // Leave focused editors before issuing the canvas Undo shortcut.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _shortcut(tester);
      expect(find.byType(type), findsNothing);
      expect(_toolSelected(tester, tool), isTrue);
      await pumpPastSave(tester);
      expect(store.persisted!.elements, isEmpty);
      await _shortcut(tester);
      expect(_toolSelected(tester, tool), isFalse);
      await _shortcut(tester, redo: true);
      expect(_toolSelected(tester, tool), isTrue);
      await _shortcut(tester, redo: true);
      expect(find.byType(type), findsOneWidget);
      expect(_toolSelected(tester, tool), isFalse);
      await pumpPastSave(tester);
      expect(store.persisted!.elements, hasLength(1));
    });
  }

  testWidgets('choosing touch Select from Pen is one reversible tool action', (tester) async {
    final store = TestLibraryStore(_document());
    await pumpCanvas(tester, store, platform: TargetPlatform.android);
    final original = _stroke(tester)..selected = true;
    await tester.tap(find.byKey(const ValueKey('toolbar-draw')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('toolbar-select')));
    await tester.pump();
    expect(_toolSelected(tester, 'select'), isTrue);
    expect(_toolSelected(tester, 'draw'), isFalse);
    await _shortcut(tester);
    expect(_toolSelected(tester, 'select'), isFalse);
    expect(_toolSelected(tester, 'draw'), isTrue);
    await _shortcut(tester, redo: true);
    expect(_toolSelected(tester, 'select'), isTrue);
    expect(_toolSelected(tester, 'draw'), isFalse);
    expect(_stroke(tester), same(original));
    expect(original.selected, isTrue);
    await pumpPastSave(tester);
    expect(store.persisted, isNull);
  });

  testWidgets('transient model state does not persist', (tester) async {
    final store = TestLibraryStore(_document());
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

  testWidgets('tool-only Undo interrupts held object drags and preserves Redo', (tester) async {
    final store = TestLibraryStore(
      CanvasDocument(
        background: CanvasBackgroundKind.plain,
        elements: [
          ArrowElementData(
            id: 'arrow',
            start: const Offset(150, 250),
            controls: const [Offset(200, 250)],
            end: const Offset(250, 250),
            color: const Color(0xff000000),
            strokeStyle: ArrowStrokeStyle.solid,
            strokeWidth: 3,
          ),
        ],
      ),
    );
    await pumpCanvas(tester, store, platform: TargetPlatform.android);
    final select = find.byKey(const ValueKey('toolbar-select'));
    await tester.tap(select);
    await tester.pump();
    await tester.tap(select);
    await tester.pump();
    final model = tester.widget<Arrow>(find.byType(Arrow)).model;
    final original = model.start;
    final gesture = await tester.startGesture(tester.getCenter(find.byType(Arrow)), kind: PointerDeviceKind.mouse);
    await _shortcut(tester);
    expect(_toolSelected(tester, 'select'), isTrue);
    await gesture.moveBy(const Offset(60, 30));
    await gesture.up();
    await tester.pump();
    expect(model.start, original);
    expect(tester.widget<Arrow>(find.byType(Arrow)).model, same(model));
    await _shortcut(tester, redo: true);
    expect(_toolSelected(tester, 'select'), isFalse);
    await pumpPastSave(tester);
    expect(store.persisted, isNull);

    await tester.drag(find.byType(Arrow), const Offset(60, 30), kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect(model.start, original + const Offset(60, 30));
  });

  testWidgets('undo and redo restore and persist canvas operations', (
    tester,
  ) async {
    final store = TestLibraryStore(_document());
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
    final store = TestLibraryStore(_document());
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
    await pumpCanvas(tester, TestLibraryStore(_textDocument()));
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
    final store = TestLibraryStore(_textDocument());
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
    final store = TestLibraryStore(_textDocument());
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
    final store = TestLibraryStore(
      _codeDocument().withElements((elements) => elements[0] = elements[0].copyWith(autoArrange: false)),
    );
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
    await pumpCanvas(tester, TestLibraryStore(saved));
    expect(model().background, BlockBackgroundKind.glass);
    expect(model().active, isFalse);
  });

  testWidgets('history retains only the latest 50 operations', (tester) async {
    await pumpCanvas(tester, TestLibraryStore(_penDocument(51)));

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

bool _toolSelected(WidgetTester tester, String tool) =>
    tester.widget<ToolbarButton>(find.byKey(ValueKey('toolbar-$tool'))).selected;

Future<void> _draw(WidgetTester tester) async {
  final gesture = await tester.startGesture(const Offset(300, 250), kind: PointerDeviceKind.mouse);
  await gesture.moveTo(const Offset(420, 350));
  await gesture.up();
  await tester.pump();
}

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
        color: const Color(0xff000000),
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
        color: Color(0xff201C1A),
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

class _CountingAttachments extends TestAttachmentStore {
  _CountingAttachments(super.initial);

  int reads = 0;

  @override
  Future<Uint8List> read(String path) {
    reads++;
    return super.read(path);
  }
}

Future<void> _cacheAttachmentImage() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 100, 100), Paint()..color = Colors.black);
  final image = await recorder.endRecording().toImage(100, 100);
  PaintingBinding.instance.imageCache.putIfAbsent(
    MemoryImage(onePixelPngBytes),
    () => OneFrameImageStreamCompleter(SynchronousFuture(ImageInfo(image: image))),
  );
}

class _PausedWrite extends TestAttachmentStore {
  _PausedWrite({this.failDeletes = false});

  final bool failDeletes;

  @override
  Future<void> delete(String path) async {
    if (failDeletes) throw StateError('delete failed');
    await super.delete(path);
  }

  final started = Completer<void>();
  final release = Completer<void>();

  @override
  Future<void> write(String path, Uint8List bytes) async {
    started.complete();
    await release.future;
    await super.write(path, bytes);
  }
}

class _PausedRead extends TestAttachmentStore {
  final bytes = Completer<Uint8List>();
  int reads = 0;

  @override
  Future<Uint8List> read(String path) {
    reads++;
    return bytes.future;
  }
}

class _HistoryTextReader extends ClipboardReader {
  _HistoryTextReader() : super([]);

  @override
  bool canProvide(DataFormat format) => format == Formats.plainText;

  @override
  Future<T?> readValue<T extends Object>(ValueFormat<T> format) async => 'late' as T;
}
