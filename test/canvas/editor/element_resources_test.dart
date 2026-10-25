// Verifies rendering-resource lifetimes through lazy culling and removal.
// Exercises the real canvas projection with controlled attachment reads.

import 'dart:async';
import 'dart:ui' as ui;

import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/editor/elements/code/code_element_view.dart';
import 'package:elseplane/canvas/editor/elements/media/media_element_view.dart';
import 'package:elseplane/canvas/editor/elements/media/media_resources.dart';
import 'package:elseplane/canvas/editor/elements/text/text_element_view.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts_lite.dart';
import 'package:infinite_lazy_grid/infinite_lazy_grid.dart';

import '../test_helpers.dart';

void main() {
  setUp(() => GoogleFontsLite.config.allowRuntimeFetching = false);
  tearDown(() => GoogleFontsLite.config.allowRuntimeFetching = true);

  testWidgets('culling preserves controllers, independent scroll offsets, images, and measurements', (tester) async {
    await _cacheImage(tester);
    const path = 'attachments/11111111-1111-4111-8111-111111111111.png';
    final attachments = _CountingAttachments({path: onePixelPngBytes});
    final document = CanvasDocument(
      background: CanvasBackgroundKind.plain,
      elements: [
        TextElementData(
          id: 'text',
          position: const ui.Offset(30, 80),
          width: 300,
          height: 200,
          markdown: List.generate(70, (i) => 'Paragraph $i\n').join('\n'),
          style: const TextNodeStyle(fontFamily: 'JetBrains Mono'),
        ),
        CodeElementData(
          id: 'code',
          position: const ui.Offset(400, 80),
          size: const ui.Size(300, 240),
          language: CodeLanguage.dart,
          source: List.generate(80, (i) => 'line $i ${'x' * 120}').join('\n'),
          title: 'Code',
          showLineNumbers: true,
        ),
        MediaElementData(id: 'image', position: const ui.Offset(30, 360), width: 120, url: path),
      ],
    );
    await pumpCanvas(tester, TestLibraryStore(document), attachmentStore: attachments);
    await tester.pumpAndSettle();
    final text = tester.widget<TextElementView>(find.byType(TextElementView)).resources;
    final code = tester.widget<CodeElementView>(find.byType(CodeElementView)).resources;
    final media = tester.widget<MediaElementView>(find.byType(MediaElementView)).resources;
    final canvas = tester.widget<LazyCanvas>(find.byType(LazyCanvas)).controller;
    final image = media.image;
    expect(media.hasImage, isTrue);
    expect(attachments.reads, 1);
    text.scrollController.jumpTo(80);
    code.scrollController.verticalScroller.jumpTo(120);
    final horizontal = code.scrollController.horizontalScroller;
    await tester.pumpAndSettle();
    final textOffset = text.scrollController.offset;
    final codeOffset = code.scrollController.verticalScroller.offset;
    final measured = canvas.getInfo('code').childSize;
    canvas
      ..onScaleStart(ScaleStartDetails())
      ..onScaleUpdate(ScaleUpdateDetails(focalPointDelta: const ui.Offset(-20000, 0)));
    await tester.pumpAndSettle();
    expect(find.byType(TextElementView), findsNothing);
    expect(find.byType(CodeElementView), findsNothing);
    expect(find.byType(MediaElementView), findsNothing);
    expect(canvas.getInfo('code').childSize, measured);
    canvas
      ..onScaleStart(ScaleStartDetails())
      ..onScaleUpdate(ScaleUpdateDetails(focalPointDelta: const ui.Offset(20000, 0)));
    await tester.pumpAndSettle();
    expect(tester.widget<TextElementView>(find.byType(TextElementView)).resources, same(text));
    expect(tester.widget<CodeElementView>(find.byType(CodeElementView)).resources, same(code));
    expect(tester.widget<MediaElementView>(find.byType(MediaElementView)).resources, same(media));
    expect(text.scrollController.offset, textOffset);
    expect(code.scrollController.horizontalScroller, same(horizontal));
    expect(media.image, same(image));
    expect(attachments.reads, 1);
    expect(code.scrollController.verticalScroller.offset, codeOffset);
  });

  testWidgets('removal invalidates a delayed image read before resources dispose', (tester) async {
    await _cacheImage(tester);
    const path = 'attachments/11111111-1111-4111-8111-111111111111.png';
    final attachments = _PausedAttachments();
    final value = MediaElementData(id: 'image', position: ui.Offset.zero, width: 120, url: path);
    final session = testSession(CanvasDocument(background: CanvasBackgroundKind.plain, elements: [value]));
    final old = MediaResources(session, value, attachments);
    addTearDown(old.dispose);
    session.remove([value.id]);
    expect(old.attached, isFalse);
    expect(old.disposed, isFalse);
    session.insert([value]);
    final current = MediaResources(session, value, attachments);
    addTearDown(current.dispose);
    attachments.result.complete(onePixelPngBytes);
    await tester.pumpAndSettle();
    expect(old.hasImage, isFalse);
    expect(current.hasImage, isTrue);
  });
}

class _CountingAttachments extends TestAttachmentStore {
  _CountingAttachments(super.initial);
  int reads = 0;
  @override
  Future<Uint8List> read(String path) {
    reads++;
    return super.read(path);
  }
}

class _PausedAttachments extends TestAttachmentStore {
  final result = Completer<Uint8List>();
  @override
  Future<Uint8List> read(String path) => result.future;
}

Future<void> _cacheImage(WidgetTester tester) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(const ui.Rect.fromLTWH(0, 0, 1, 1), ui.Paint()..color = const ui.Color(0xff000000));
  final image = (await tester.runAsync(() => recorder.endRecording().toImage(1, 1)))!;
  PaintingBinding.instance.imageCache.putIfAbsent(
    MemoryImage(onePixelPngBytes),
    () => OneFrameImageStreamCompleter(SynchronousFuture(ImageInfo(image: image))),
  );
}
