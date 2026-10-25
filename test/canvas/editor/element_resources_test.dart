// Verifies rendering-resource lifetimes through lazy culling and removal.
// Exercises the real canvas projection with controlled attachment reads.

import 'dart:async';
import 'dart:ui' as ui;

import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/editor/editor_session.dart';
import 'package:elseplane/canvas/editor/elements/code/code_element_view.dart';
import 'package:elseplane/canvas/editor/elements/media/media_element_view.dart';
import 'package:elseplane/canvas/editor/elements/media/media_resources.dart';
import 'package:elseplane/canvas/editor/elements/text/text_element_view.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
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
          source: List.generate(80, (i) => 'line $i').join('\n'),
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

  // Keep enabled until re_editor supplies correct wrapped-line restoration.
  // This is the deferred defect in docs/BUGS.md #3, isolated from app contracts.
  testWidgets('known re_editor defect: wrapped code retains its scroll offset after culling', (tester) async {
    await pumpCanvas(
      tester,
      TestLibraryStore(
        CanvasDocument(
          background: CanvasBackgroundKind.plain,
          elements: [
            CodeElementData(
              id: 'code',
              position: const ui.Offset(400, 80),
              size: const ui.Size(300, 240),
              language: CodeLanguage.dart,
              source: List.generate(80, (i) => 'line $i ${'x' * 120}').join('\n'),
              title: 'Code',
              showLineNumbers: true,
            ),
          ],
        ),
      ),
    );
    final code = tester.widget<CodeElementView>(find.byType(CodeElementView)).resources;
    code.scrollController.verticalScroller.jumpTo(120);
    await tester.pumpAndSettle();
    final offset = code.scrollController.verticalScroller.offset;
    await _pan(tester, -20000);
    expect(find.byType(CodeElementView), findsNothing);
    await _pan(tester, 20000);
    expect(tester.widget<CodeElementView>(find.byType(CodeElementView)).resources, same(code));
    expect(code.scrollController.verticalScroller.offset, offset);
  });

  for (final delayed in [false, true]) {
    testWidgets('Markdown images survive culling and editing with delayed load $delayed', (tester) async {
      await _cacheImage(tester);
      const path = 'attachments/11111111-1111-4111-8111-111111111111.png';
      final delay = delayed ? Completer<Uint8List>() : null;
      final attachments = _CountingAttachments({path: onePixelPngBytes}, delay: delay);
      final value = TextElementData(
        id: 'text',
        position: const ui.Offset(30, 80),
        width: 300,
        height: 200,
        markdown: '![first]($path)\n\n![second][shared]\n\n[shared]: $path',
        style: const TextNodeStyle(fontFamily: 'JetBrains Mono'),
      );
      await pumpCanvas(
        tester,
        TestLibraryStore(
          CanvasDocument(
            background: CanvasBackgroundKind.plain,
            elements: [value],
          ),
        ),
        attachmentStore: attachments,
      );
      final text = tester.widget<TextElementView>(find.byType(TextElementView)).resources;
      final uri = Uri.parse(path);
      final provider = text.images.resolve(uri).provider;
      expect(attachments.reads, 1);
      text.session.setSelection(['text']);
      await tester.pumpAndSettle();
      expect(attachments.reads, 1);
      await _pan(tester, -20000);
      expect(find.byType(TextElementView), findsNothing);
      if (provider != null) {
        // Remove ordinary cache entries: the resource's live stream still pins
        // the decoded image when there are no mounted Image widgets.
        PaintingBinding.instance.imageCache.clear();
        expect(PaintingBinding.instance.imageCache.statusForKey(provider).live, isTrue);
      }
      await _pan(tester, 20000);
      expect(tester.widget<TextElementView>(find.byType(TextElementView)).resources, same(text));
      expect(attachments.reads, 1);
      if (delay != null) {
        delay.complete(onePixelPngBytes);
        await tester.pumpAndSettle();
      }
      final loaded = text.images.resolve(uri).provider;
      expect(loaded, isA<MemoryImage>());
      expect(tester.widgetList<Image>(find.byType(Image)).every((widget) => identical(widget.image, loaded)), isTrue);
      text.session
        ..setActive('text')
        ..editField((id: 'text', field: EditorField.markdown));
      await tester.pumpAndSettle();
      text.session.editField(null);
      await tester.pumpAndSettle();
      text.session
        ..move(['text'], const ui.Offset(5, 0))
        ..finishOperation()
        ..undo();
      await tester.pumpAndSettle();
      expect(text.images.resolve(uri).provider, same(loaded));
      expect(attachments.reads, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('HTTPS Markdown images retain their decoded stream while culled', (tester) async {
    const url = 'https://example.com/retained.png';
    const key = NetworkImage(url);
    await _cacheImage(tester, provider: key);
    await pumpCanvas(
      tester,
      TestLibraryStore(
        CanvasDocument(
          background: CanvasBackgroundKind.plain,
          elements: [
            TextElementData(
              id: 'text',
              position: const ui.Offset(30, 80),
              width: 300,
              height: 200,
              markdown: '![remote]($url)',
              style: const TextNodeStyle(fontFamily: 'JetBrains Mono'),
            ),
          ],
        ),
      ),
    );
    final text = tester.widget<TextElementView>(find.byType(TextElementView)).resources;
    final provider = text.images.resolve(Uri.parse(url)).provider;
    expect(provider, isA<NetworkImage>());
    await _pan(tester, -20000);
    expect(find.byType(Image), findsNothing);
    PaintingBinding.instance.imageCache.clear();
    expect(PaintingBinding.instance.imageCache.statusForKey(key).live, isTrue);
    await _pan(tester, 20000);
    expect(text.images.resolve(Uri.parse(url)).provider, same(provider));
    expect(tester.widget<Image>(find.byType(Image)).image, same(provider));
    expect(tester.takeException(), isNull);
  });

  for (final change in ['source', 'removal', 'disposal']) {
    testWidgets('retired Markdown $change rejects a delayed image completion', (tester) async {
      await _cacheImage(tester);
      const path = 'attachments/11111111-1111-4111-8111-111111111111.png';
      const other = 'attachments/22222222-2222-4222-8222-222222222222.png';
      final delay = Completer<Uint8List>();
      final attachments = _CountingAttachments({}, delay: delay);
      final text = testTextModel(
        TextElementData(
          id: 'text',
          position: ui.Offset.zero,
          width: 300,
          height: 200,
          markdown: '![first]($path)',
          style: const TextNodeStyle(fontFamily: 'JetBrains Mono'),
        ),
        attachmentStore: attachments,
      );
      expect(attachments.reads, 0);
      final uri = Uri.parse(path);
      expect(text.images.resolve(uri).provider, isNull);
      expect(attachments.reads, 1);
      var completions = 0;
      text.images.addListener(() => completions++);
      if (change == 'source') {
        text.session.setMarkdown('text', '![replacement]($other)');
      } else if (change == 'removal') {
        text.session.remove(['text']);
        expect(text.disposed, isFalse);
      } else {
        text.dispose();
      }
      delay.complete(onePixelPngBytes);
      await tester.pumpAndSettle();
      expect(completions, 0);
      expect(text.images.resolve(uri).provider, isNull);
      expect(text.images.resolve(uri).failed, isTrue);
      if (!text.disposed) text.dispose();
    });
  }

  testWidgets('Markdown source reconciliation preserves survivors and reloads restored sources', (tester) async {
    await _cacheImage(tester);
    const path = 'attachments/11111111-1111-4111-8111-111111111111.png';
    const ignored = 'attachments/22222222-2222-4222-8222-222222222222.png';
    final attachments = _CountingAttachments({path: onePixelPngBytes});
    final text = testTextModel(
      TextElementData(
        id: 'text',
        position: ui.Offset.zero,
        width: 300,
        height: 200,
        markdown: '![first]($path)\n\n`![code]($ignored)`\n\n\$![math]($ignored)\$',
        style: const TextNodeStyle(fontFamily: 'JetBrains Mono'),
      ),
      attachmentStore: attachments,
    );
    addTearDown(text.dispose);
    final uri = Uri.parse(path);
    expect(text.images.resolve(Uri.parse(ignored)).failed, isTrue);
    expect(attachments.reads, 0);
    text.images.resolve(uri);
    await tester.pumpAndSettle();
    final provider = text.images.resolve(uri).provider;
    text.session
      ..setMarkdown('text', 'Different prose\n\n![same][ref]\n\n[ref]: $path')
      ..finishOperation()
      ..undo();
    expect(text.images.resolve(uri).provider, same(provider));
    expect(attachments.reads, 1);
    text.session
      ..setMarkdown('text', 'No image')
      ..finishOperation()
      ..undo();
    expect(text.images.resolve(uri).provider, isNull);
    await tester.pumpAndSettle();
    expect(text.images.resolve(uri).provider, isA<MemoryImage>());
    expect(attachments.reads, 2);
  });

  testWidgets('Markdown image read failures remain stable until the source is removed', (tester) async {
    const path = 'attachments/11111111-1111-4111-8111-111111111111.png';
    final attachments = _CountingAttachments({});
    final text = testTextModel(
      TextElementData(
        id: 'text',
        position: ui.Offset.zero,
        width: 300,
        height: 200,
        markdown: '![missing]($path)',
        style: const TextNodeStyle(fontFamily: 'JetBrains Mono'),
      ),
      attachmentStore: attachments,
    );
    addTearDown(text.dispose);
    final uri = Uri.parse(path);
    text.images.resolve(uri);
    await tester.pumpAndSettle();
    expect(text.images.resolve(uri).failed, isTrue);
    expect(text.images.resolve(uri).failed, isTrue);
    expect(attachments.reads, 1);
  });

  testWidgets('removal invalidates a delayed image read before resources dispose', (tester) async {
    await _cacheImage(tester);
    const path = 'attachments/11111111-1111-4111-8111-111111111111.png';
    final result = Completer<Uint8List>();
    final attachments = _CountingAttachments({}, delay: result);
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
    result.complete(onePixelPngBytes);
    await tester.pumpAndSettle();
    expect(old.hasImage, isFalse);
    expect(current.hasImage, isTrue);
  });
}

class _CountingAttachments extends TestAttachmentStore {
  _CountingAttachments(super.initial, {this.delay});
  final Completer<Uint8List>? delay;
  int reads = 0;
  @override
  Future<Uint8List> read(String path) {
    reads++;
    return delay?.future ?? super.read(path);
  }
}

Future<void> _cacheImage(WidgetTester tester, {ImageProvider<Object>? provider}) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(const ui.Rect.fromLTWH(0, 0, 1, 1), ui.Paint()..color = const ui.Color(0xff000000));
  final image = (await tester.runAsync(() => recorder.endRecording().toImage(1, 1)))!;
  PaintingBinding.instance.imageCache.putIfAbsent(
    provider ?? MemoryImage(onePixelPngBytes),
    () => OneFrameImageStreamCompleter(SynchronousFuture(ImageInfo(image: image))),
  );
}

Future<void> _pan(WidgetTester tester, double dx) async {
  tester.widget<LazyCanvas>(find.byType(LazyCanvas)).controller
    ..onScaleStart(ScaleStartDetails())
    ..onScaleUpdate(ScaleUpdateDetails(focalPointDelta: ui.Offset(dx, 0)));
  await tester.pumpAndSettle();
}
