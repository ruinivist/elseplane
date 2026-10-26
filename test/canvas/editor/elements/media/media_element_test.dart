// Verifies media editing, rendering resources, and asynchronous workflows.

import 'dart:async';
import 'dart:js_interop';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:elseplane/attachments/attachment_store.dart';
import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/editor/elements/media/media_element_view.dart';
import 'package:elseplane/canvas/editor/elements/text/text_element_view.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_lazy_grid/infinite_lazy_grid.dart';
import 'package:shared_preferences_web/shared_preferences_web.dart';
import 'package:web/web.dart' as web;

import '../../../test_helpers.dart';

void main() {
  setUp(() => SharedPreferencesAsyncWeb.registerWith(null));

  testWidgets('URL changes publish the value after clearing the previous image', (tester) async {
    const url = 'https://example.com/image.png';
    await _cacheImage(url);
    final model = testMediaModel(
      MediaElementData(id: 'media', position: Offset.zero, width: 280, url: url),
      TestAttachmentStore(),
    );
    addTearDown(model.dispose);
    expect(model.hasImage, isTrue);
    final changes = <(String, bool)>[];
    model.session.documentChanges.addListener(() => changes.add((model.data.url, model.hasImage)));
    model.controller.text = 'not an image';
    model.commitUrl();
    expect(changes, [('not an image', false)]);
  });

  for (final media in [false, true]) {
    for (final stale in [false, true]) {
      testWidgets(
        '${media ? 'media' : 'text'} image paste ${stale ? 'cancels stale' : 'reports current'} write failure',
        (tester) async {
          final attachments = (await tester.runAsync(() async => _FailedWrite()))!;
          var document = _document();
          if (media) {
            document = document.withElements(
              (elements) => elements.add(
                MediaElementData(id: 'media', position: const Offset(120, 150), width: 280, url: 'original'),
              ),
            );
          } else {
            document = document.withElements(
              (elements) => elements.add(
                TextElementData(
                  id: 'text',
                  position: const Offset(120, 150),
                  width: 280,
                  height: null,
                  markdown: 'original',
                  style: const TextNodeStyle(fontFamily: 'Inter', color: Color(0xff201C1A)),
                ),
              ),
            );
          }
          await pumpCanvas(tester, TestLibraryStore(document), attachmentStore: attachments);
          final text = media ? null : tester.widget<TextElementView>(find.byType(TextElementView)).resources;
          final image = media ? tester.widget<MediaElementView>(find.byType(MediaElementView)).resources : null;
          await tester.tap(find.byKey(ValueKey(media ? 'media-url-field' : 'text-markdown-preview')));
          await tester.pump();
          await tester.runAsync(() async {
            _dispatchImagePaste(onePixelPngBytes);
            await attachments.started.future;
          });
          if (stale) {
            if (media) {
              image!.session.invalidatePendingEdits();
            } else {
              text!.session.invalidatePendingEdits();
            }
          }
          await tester.runAsync(() async {
            attachments.release.completeError(StateError('write failed'));
            await attachments.finished.future;
            await Future<void>.delayed(Duration.zero);
          });
          await tester.pump();
          expect(find.text('Could not paste image'), stale ? findsNothing : findsOneWidget);
          expect(media ? image!.data.url : text!.data.markdown, 'original');
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }

  testWidgets('restoring during image decoding prevents storage writes and silences stale decoding errors', (
    tester,
  ) async {
    final attachments = TestAttachmentStore();
    final model = testMediaModel(
      MediaElementData(id: 'media', position: Offset.zero, width: 200, url: 'original'),
      attachments,
    );
    for (final bytes in [
      onePixelPngBytes,
      Uint8List.fromList([1, 2, 3]),
    ]) {
      await tester.runAsync(() async {
        final pending = model.setDeviceImage(bytes, 'png');
        model.session.invalidatePendingEdits();
        await pending;
      });
      expect(attachments.files, isEmpty);
      expect(model.data.url, 'original');
    }
    await tester.runAsync(() async {
      await expectLater(model.setDeviceImage(Uint8List.fromList([1, 2, 3]), 'png'), throwsFormatException);
    });
    model.dispose();
  });

  testWidgets('media places as a selectable URL-only node', (tester) async {
    await pumpCanvas(tester, TestLibraryStore(_document()));

    await tester.tap(find.byKey(const ValueKey('toolbar-media')));
    await tester.pump();
    await tester.tapAt(const Offset(120, 180));
    await tester.pump();
    await tester.pump();

    final model = tester.widget<MediaElementView>(find.byType(MediaElementView)).resources;
    expect(model.data.position, const Offset(120, 180));
    expect(model.data.width, mediaNodeDefaultWidth);
    expect(model.hasImage, isFalse);
    expect(find.byKey(const ValueKey('media-url-field')), findsOneWidget);
    expect(find.byKey(const ValueKey('media-device-picker')), findsOneWidget);
    expect(find.byKey(const ValueKey('media-block-handle')), findsOneWidget);
    expect(find.byKey(const ValueKey('media-block-rotate-control')), findsNothing);
    expect(find.byKey(const ValueKey('media-block-delete-control')), findsOneWidget);
    expect(model.focusNode.hasFocus, isTrue);
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('media-url-field')),
    );
    expect(field.minLines, 1);
    expect(field.maxLines, 3);

    await tester.enterText(
      find.byKey(const ValueKey('media-url-field')),
      'http://example.com/image.png',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(model.hasImage, isFalse);
    expect(find.byKey(const ValueKey('media-url-field')), findsOneWidget);

    const validUrl = 'https://example.com/new-image.png';
    await _cacheImage(validUrl);
    await tester.enterText(
      find.byKey(const ValueKey('media-url-field')),
      validUrl,
    );
    await tester.pump();
    expect(model.hasImage, isFalse);
    expect(model.data.url, 'http://example.com/image.png');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(model.hasImage, isTrue);
    expect(model.active, isTrue);
    expect(find.byKey(const ValueKey('media-image')), findsOneWidget);
    expect(find.byKey(const ValueKey('media-url-field')), findsOneWidget);
    expect(find.byKey(const ValueKey('media-block-rotate-control')), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.tapAt(tester.getCenter(find.byType(MediaElementView)));
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(model.selected, isTrue);
    await tester.pumpAndSettle();
  });

  testWidgets('URL-only media keeps its draft while moving the caret and selecting text', (tester) async {
    const url = 'https://example.com/image.png';
    await _cacheImage(url);
    await pumpCanvas(
      tester,
      TestLibraryStore(
        _document(MediaElementData(id: 'media', position: const Offset(120, 150), width: 400, url: 'original')),
      ),
    );
    final model = tester.widget<MediaElementView>(find.byType(MediaElementView)).resources;
    final field = find.byKey(const ValueKey('media-url-field'));
    await tester.enterText(field, url);
    await tester.pump();

    final rect = tester.getRect(field);
    final click = await tester.startGesture(
      Offset(rect.left + 30, rect.center.dy),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    expect(model.focusNode.hasFocus, isTrue);
    expect(model.data.url, 'original');
    expect(model.hasImage, isFalse);
    await click.moveBy(const Offset(80, 0));
    await tester.pump();
    await click.up();
    await tester.pump();
    expect(model.focusNode.hasFocus, isTrue);
    expect(model.controller.selection.isCollapsed, isFalse);
    expect(model.controller.text, url);
    expect(model.data.url, 'original');
    expect(model.hasImage, isFalse);

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(model.data.url, url);
    expect(model.hasImage, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('loaded media path accepts mouse editing and Escape', (tester) async {
    const url = 'https://example.com/image.png';
    const editedUrl = 'https://example.com/edited.png';
    await _cacheImage(url);
    await _cacheImage(editedUrl);
    await pumpCanvas(
      tester,
      TestLibraryStore(
        _document(
          MediaElementData(
            id: 'media',
            position: const Offset(120, 150),
            width: 400,
            url: url,
          ),
        ),
      ),
    );

    final model = tester.widget<MediaElementView>(find.byType(MediaElementView)).resources;
    await tester.tap(find.byKey(const ValueKey('media-image')));
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('media-url-field'));
    final fieldRect = tester.getRect(field);
    final click = await tester.startGesture(
      Offset(fieldRect.left + 100, fieldRect.center.dy),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    expect(model.active, isTrue);
    await click.up();
    await tester.pump();
    expect(model.focusNode.hasFocus, isTrue);
    final selection = model.controller.selection;
    expect(selection.isCollapsed, isTrue);
    expect(selection.isValid, isTrue);

    await tester.tapAt(
      Offset(fieldRect.left + 20, fieldRect.center.dy),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    expect(model.focusNode.hasFocus, isTrue);
    expect(model.controller.selection.baseOffset, lessThan(selection.baseOffset));
    tester.testTextInput.enterText(editedUrl);
    await tester.pump();
    expect(model.data.url, url);
    model.setSelected(value: true);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(model.focusNode.hasFocus, isFalse);
    expect(model.data.url, editedUrl);
    expect(model.active, isFalse);
    expect(model.selected, isFalse);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const ValueKey('media-url-field')), findsNothing);
  });

  for (final exit in ['Enter', 'mouse outside', 'touch outside', 'focus loss']) {
    testWidgets('loaded media keeps its image while drafting until $exit', (tester) async {
      const url = 'https://example.com/image.png';
      const editedUrl = 'https://example.com/edited.png';
      await _cacheImage(url);
      await _cacheImage(editedUrl);
      final store = TestLibraryStore(
        _document(MediaElementData(id: 'media', position: const Offset(120, 150), width: 400, url: url)),
      );
      await pumpCanvas(tester, store);
      final model = tester.widget<MediaElementView>(find.byType(MediaElementView)).resources;
      final image = model.image;
      final size = model.canvasSize;
      var changes = 0;
      model.session.documentChanges.addListener(() => changes++);
      await tester.tap(find.byKey(const ValueKey('media-image')));
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('media-url-field'));

      for (final draft in ['', 'incomplete path', editedUrl]) {
        await tester.enterText(field, draft);
        await tester.pump();
        expect(model.controller.text, draft);
        expect(model.data.url, url);
        expect(model.image, same(image));
        expect(model.canvasSize, size);
        expect(find.byKey(const ValueKey('media-image')), findsOneWidget);
        expect(changes, 0);
      }

      switch (exit) {
        case 'Enter':
          await tester.testTextInput.receiveAction(TextInputAction.done);
        case 'mouse outside':
          await tester.tapAt(const Offset(700, 500), kind: PointerDeviceKind.mouse);
        case 'touch outside':
          await tester.tapAt(const Offset(700, 500));
        case 'focus loss':
          model.focusNode.unfocus();
      }
      await tester.pumpAndSettle();
      expect(model.data.url, editedUrl);
      expect(model.image, const NetworkImage(editedUrl));
      expect(model.hasImage, isTrue);
      expect(changes, 1);
      model.commitUrl();
      expect(changes, 1);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      expect((store.persisted!.elements.single as MediaElementData).url, editedUrl);
      await _shortcut(tester, LogicalKeyboardKey.keyZ);
      expect(model.data.url, url);
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final draft in ['', 'invalid path']) {
    testWidgets('loaded media clears only after submitting "$draft"', (tester) async {
      const url = 'https://example.com/image.png';
      await _cacheImage(url);
      await pumpCanvas(
        tester,
        TestLibraryStore(
          _document(MediaElementData(id: 'media', position: const Offset(120, 150), width: 400, url: url)),
        ),
      );
      final model = tester.widget<MediaElementView>(find.byType(MediaElementView)).resources;
      await tester.tap(find.byKey(const ValueKey('media-image')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('media-url-field')), draft);
      await tester.pump();
      expect(model.hasImage, isTrue);
      expect(model.data.url, url);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(model.data.url, draft);
      expect(model.hasImage, isFalse);
      expect(find.byKey(const ValueKey('media-image')), findsNothing);
      expect(find.byKey(const ValueKey('media-url-field')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('restoring media clears a draft before focus loss can apply it', (tester) async {
    const url = 'https://example.com/image.png';
    await _cacheImage(url);
    await pumpCanvas(
      tester,
      TestLibraryStore(
        _document(MediaElementData(id: 'media', position: const Offset(120, 150), width: 400, url: url)),
      ),
    );
    final model = tester.widget<MediaElementView>(find.byType(MediaElementView)).resources;
    final image = model.image;
    await tester.tap(find.byKey(const ValueKey('media-image')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('media-url-field')), 'unfinished');
    model.session
      ..setBackground(CanvasBackgroundKind.dotGrid)
      ..finishOperation()
      ..undo();
    model.focusNode.unfocus();
    await tester.pumpAndSettle();
    expect(model.controller.text, url);
    expect(model.data.url, url);
    expect(model.image, same(image));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('device images are stored and rendered from memory', (
    tester,
  ) async {
    final attachments = TestAttachmentStore();
    await pumpCanvas(
      tester,
      TestLibraryStore(_document()),
      attachmentStore: attachments,
    );

    await tester.tap(find.byKey(const ValueKey('toolbar-media')));
    await tester.pump();
    await tester.tapAt(const Offset(120, 180));
    await tester.pump();
    await tester.pump();

    final model = tester.widget<MediaElementView>(find.byType(MediaElementView)).resources;
    final controller = tester.widget<LazyCanvas>(find.byType(LazyCanvas)).controller;
    final urlPanelSize = controller.getInfo(model.data.id).childSize;
    final bytes = onePixelPngBytes;
    await tester.runAsync(() => model.setDeviceImage(bytes, 'PNG'));
    await tester.pumpAndSettle();

    expect(model.data.url, matches(attachmentPathPattern));
    expect(attachments.files, {model.data.url: bytes});
    expect(model.image, isA<MemoryImage>());
    expect(model.canvasSize, const Size.square(mediaNodeDefaultWidth));
    expect(controller.getInfo(model.data.id).childSize, model.canvasSize);
    expect(controller.getInfo(model.data.id).childSize, isNot(urlPanelSize));
    model.rotate(math.pi / 4);
    expect(controller.getInfo(model.data.id).rotation, model.rotation);
    expect(controller.getInfo(model.data.id).childSize, model.canvasSize);
    await tester.pump();
    expect(find.byKey(const ValueKey('media-image')), findsOneWidget);
    expect(model.active, isTrue);
  });

  testWidgets('focused media editor consumes browser paste', (tester) async {
    final attachments = TestAttachmentStore();
    await pumpCanvas(
      tester,
      TestLibraryStore(
        _document(
          MediaElementData(
            id: 'media',
            position: const Offset(120, 150),
            width: 400,
            url: 'replace me',
          ),
        ),
      ),
      attachmentStore: attachments,
    );

    final field = find.byKey(const ValueKey('media-url-field'));
    final model = tester.widget<MediaElementView>(find.byType(MediaElementView)).resources;
    await tester.tap(field);
    model.controller.selection = const TextSelection(baseOffset: 0, extentOffset: 7);

    await tester.runAsync(() async {
      _dispatchTextPaste('keep');
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    expect(model.controller.text, 'keep me');
    expect(model.data.url, 'replace me');

    await tester.runAsync(() async {
      _dispatchImagePaste(onePixelPngBytes);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();

    expect(find.byType(MediaElementView), findsOneWidget);
    expect(model.data.url, matches(attachmentPathPattern));
    expect(attachments.files[model.data.url], onePixelPngBytes);
    expect(model.image, isA<MemoryImage>());
  });

  testWidgets('unfocused active media leaves paste to the canvas', (
    tester,
  ) async {
    final attachments = TestAttachmentStore();
    await pumpCanvas(
      tester,
      TestLibraryStore(_document()),
      attachmentStore: attachments,
      readClipboard: () async => (
        text: null,
        image: (bytes: onePixelPngBytes, extension: 'png'),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('toolbar-media')));
    await tester.pump();
    await tester.tapAt(const Offset(120, 180));
    await tester.pump();

    final model = tester.widget<MediaElementView>(find.byType(MediaElementView)).resources;
    model.focusNode.unfocus();
    await tester.pump();
    expect(model.active, isTrue);
    expect(model.focusNode.hasFocus, isFalse);

    await tester.runAsync(() async {
      await _shortcut(tester, LogicalKeyboardKey.keyV);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();

    expect(find.byType(MediaElementView), findsNWidgets(2));
  });

  testWidgets('loaded media activates, moves, and resizes to its ratio', (
    tester,
  ) async {
    const url = 'https://example.com/image.png';
    await _cacheImage(url);
    final store = TestLibraryStore(
      _document(
        MediaElementData(
          id: 'media',
          position: const Offset(120, 150),
          width: 400,
          url: url,
        ),
      ),
    );
    await pumpCanvas(tester, store);

    final node = find.byType(MediaElementView);
    final model = tester.widget<MediaElementView>(node).resources;
    expect(model.hasImage, isTrue);
    expect(model.canvasSize, const Size(400, 200));
    expect(find.byKey(const ValueKey('media-url-field')), findsNothing);

    final inactivePosition = model.data.position;
    await tester.drag(
      find.byKey(const ValueKey('media-image')),
      const Offset(30, 20),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    expect(model.data.position, inactivePosition + const Offset(30, 20));
    expect(model.active, isFalse);
    expect(find.byKey(const ValueKey('media-url-field')), findsNothing);
    expect(find.byKey(const ValueKey('media-block-handle')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('media-image')));
    await tester.pumpAndSettle();
    expect(model.active, isTrue);
    expect(model.selected, isFalse);
    expect(find.byKey(const ValueKey('media-url-field')), findsOneWidget);
    expect(find.byKey(const ValueKey('media-resize-handle')), findsOneWidget);
    expect(find.byKey(const ValueKey('media-block-handle')), findsOneWidget);
    expect(find.byKey(const ValueKey('media-block-rotate-control')), findsOneWidget);
    expect(find.byKey(const ValueKey('media-block-delete-control')), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('media-url-panel'))).dy -
          tester.getBottomLeft(find.byKey(const ValueKey('media-image'))).dy,
      8,
    );

    final canvas = tester.widget<LazyCanvas>(find.byType(LazyCanvas));
    canvas.controller.updateScalebyDelta(1, focalPoint: Offset.zero);
    await tester.pump();
    final imageRect = Rect.fromPoints(
      tester.getTopLeft(find.byKey(const ValueKey('media-image'))),
      tester.getBottomRight(find.byKey(const ValueKey('media-image'))),
    );
    final panelRect = Rect.fromPoints(
      tester.getTopLeft(find.byKey(const ValueKey('media-url-panel'))),
      tester.getBottomRight(find.byKey(const ValueKey('media-url-panel'))),
    );
    expect(panelRect.width, model.urlPanelWidth * canvas.controller.scale);
    expect(panelRect.center.dx, imageRect.center.dx);
    expect(panelRect.top - imageRect.bottom, 8 * canvas.controller.scale);

    canvas.controller.updateScalebyDelta(-1, focalPoint: Offset.zero);
    await tester.pump();

    final resize = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('media-resize-handle'))),
      kind: PointerDeviceKind.mouse,
    );
    for (var i = 0; i < 10; i++) {
      await resize.moveBy(const Offset(10, 5));
      await tester.pump();
    }
    await resize.up();
    expect(tester.takeException(), isNull);
    expect(model.data.width, closeTo(500, 0.01));
    expect(model.canvasSize.height, closeTo(250, 0.01));
    expect(
      tester.getSize(find.byKey(const ValueKey('media-url-panel'))).width,
      closeTo(model.data.width, 0.01),
    );

    final rotate = find.byKey(const ValueKey('media-block-rotate-control'));
    final center = tester.getCenter(find.byKey(const ValueKey('media-image')));
    final controlOffset = tester.getCenter(rotate) - center;
    await tester.drag(
      rotate,
      const Offset(0, 40),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    expect(model.rotation, isNot(0));
    final cosine = math.cos(model.rotation);
    final sine = math.sin(model.rotation);
    final rotatedControlOffset = Offset(
      controlOffset.dx * cosine - controlOffset.dy * sine,
      controlOffset.dx * sine + controlOffset.dy * cosine,
    );
    expect(tester.getCenter(rotate).dx, closeTo((center + rotatedControlOffset).dx, 1));
    expect(tester.getCenter(rotate).dy, closeTo((center + rotatedControlOffset).dy, 1));

    final rotatedResizeDelta = Offset(
      50 * math.cos(model.rotation) - 25 * math.sin(model.rotation),
      50 * math.sin(model.rotation) + 25 * math.cos(model.rotation),
    );
    await tester.drag(
      find.byKey(const ValueKey('media-resize-handle')),
      rotatedResizeDelta,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    expect(model.data.width, closeTo(550, 0.01));

    final position = model.data.position;
    await tester.drag(
      find.byKey(const ValueKey('media-image')),
      const Offset(30, 20),
    );
    await tester.pump();
    expect(model.data.position.dx, closeTo(position.dx + 30, 0.01));
    expect(model.data.position.dy, closeTo(position.dy + 20, 0.01));

    final clickAway = await tester.startGesture(
      const Offset(700, 500),
      kind: PointerDeviceKind.mouse,
    );
    await clickAway.up();
    await tester.pump();
    expect(model.active, isFalse);
    expect(find.byKey(const ValueKey('media-url-field')), findsOneWidget);
    expect(find.byKey(const ValueKey('media-resize-handle')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const ValueKey('media-url-field')), findsNothing);
    expect(find.byKey(const ValueKey('media-resize-handle')), findsNothing);

    await tester.pump(const Duration(milliseconds: 320));
    await tester.pump();
    final persisted = store.persisted!.elements.single as MediaElementData;
    expect(persisted.width, closeTo(550, 0.01));
    expect(persisted.position.dx, closeTo(position.dx + 30, 0.01));
    expect(persisted.position.dy, closeTo(position.dy + 20, 0.01));
    expect(persisted.rotation, model.rotation);
  });

  testWidgets('URL-only media can be deleted from its controls', (tester) async {
    await pumpCanvas(tester, TestLibraryStore(_document()));

    await tester.tap(find.byKey(const ValueKey('toolbar-media')));
    await tester.pump();
    await tester.tapAt(const Offset(120, 180));
    await tester.pump();

    expect(find.byType(MediaElementView), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('media-block-delete-control')));
    await tester.pump();
    expect(find.byType(MediaElementView), findsNothing);
  });
}

Future<void> _cacheImage(String url) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    const Rect.fromLTWH(0, 0, 200, 100),
    Paint()..color = Colors.black,
  );
  final image = await recorder.endRecording().toImage(200, 100);
  PaintingBinding.instance.imageCache.putIfAbsent(
    NetworkImage(url),
    () => OneFrameImageStreamCompleter(
      SynchronousFuture(ImageInfo(image: image)),
    ),
  );
}

Future<void> _shortcut(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyDownEvent(key);
  await tester.sendKeyUpEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

void _dispatchTextPaste(String text) => _dispatchPaste(web.DataTransfer()..setData('text/plain', text));

void _dispatchImagePaste(Uint8List bytes) {
  final data = web.DataTransfer();
  data.items.add(
    web.File(
      <web.BlobPart>[bytes.toJS].toJS,
      'pasted.png',
      web.FilePropertyBag(type: 'image/png'),
    ),
  );
  _dispatchPaste(data);
}

void _dispatchPaste(web.DataTransfer data) => web.window.dispatchEvent(
  web.ClipboardEvent(
    'paste',
    web.ClipboardEventInit(clipboardData: data),
  ),
);

CanvasDocument _document([MediaElementData? media]) => CanvasDocument(
  background: CanvasBackgroundKind.plain,
  elements: [?media],
);

class _FailedWrite extends TestAttachmentStore {
  final started = Completer<void>();
  final release = Completer<void>();
  final finished = Completer<void>();

  @override
  Future<void> write(String path, Uint8List bytes) async {
    started.complete();
    try {
      await release.future;
    } finally {
      finished.complete();
    }
  }
}
