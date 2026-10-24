// Checks that navigation cancels unfinished edits and saves completed content.
// Exercises clipboard and attachment lifetimes across editor-to-workspace handoffs.

import 'dart:async';

import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/editor/canvas_clipboard.dart';
import 'package:elseplane/canvas/tools/code/code_tool.dart';
import 'package:elseplane/canvas/tools/media/media_tool.dart';
import 'package:elseplane/canvas/tools/text/text_tool.dart';
import 'package:elseplane/library/canvas_library.dart';
import 'package:elseplane/library/transfer/canvas_project.dart';
import 'package:elseplane/library/widgets/canvas_file_picker.dart';
import 'package:elseplane/library/widgets/canvas_title.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';
import 'package:shared_preferences_web/shared_preferences_web.dart';

import '../canvas/test_helpers.dart';

// ---------- Tests ----------

void main() {
  setUp(() => SharedPreferencesAsyncWeb.registerWith(null));

  for (final media in [false, true]) {
    for (final failed in [false, true]) {
      testWidgets(
        '${media ? 'media' : 'text'} upload ${failed ? 'failure' : 'completion'} stays canceled after switching',
        (tester) async {
          final store = _Store(_document(media: media));
          final attachments = (await tester.runAsync(() async => _PausedAttachments()))!;
          await pumpCanvas(tester, store, attachmentStore: attachments);
          late Future<void> upload;
          await tester.runAsync(() async {
            upload = media
                ? tester.widget<MediaTool>(find.byType(MediaTool)).model.setDeviceImage(onePixelPngBytes, 'png')
                : tester
                      .widget<TextTool>(find.byType(TextTool))
                      .model
                      .insertPastedImage(onePixelPngBytes, 'png', attachments);
            await attachments.started.future;
          });
          await tester.tap(find.byType(CanvasTitle));
          await tester.pumpAndSettle();
          expect(find.byType(CanvasFilePicker), findsOneWidget);
          expect(find.byType(CircularProgressIndicator), findsNothing);
          await tester.tap(find.byKey(const ValueKey('file-tree-node-b')));
          await tester.pumpAndSettle();
          expect(store.library.currentId, 'b');
          await tester.runAsync(() async {
            if (failed) {
              attachments.release.completeError(StateError('write failed'));
            } else {
              attachments.release.complete();
            }
            await upload;
          });
          await tester.pumpAndSettle();
          expect(attachments.files, isEmpty);
          expect(canvasAttachmentPaths(store.library.file('a').document!), isEmpty);
          expect(store.library.file('b').document!.elements, isEmpty);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }

  testWidgets('a media upload survives temporary browser focus loss in its original context', (tester) async {
    final store = _Store(_document(media: true));
    final attachments = (await tester.runAsync(() async => _PausedAttachments()))!;
    await pumpCanvas(tester, store, attachmentStore: attachments);
    await tester.tap(find.byKey(const ValueKey('media-url-field')));
    await tester.pumpAndSettle();
    final model = tester.widget<MediaTool>(find.byType(MediaTool)).model;
    late Future<void> upload;
    await tester.runAsync(() async {
      upload = model.setDeviceImage(onePixelPngBytes, 'png');
      await attachments.started.future;
    });
    model.focusNode.unfocus();
    await tester.pump();
    model.focusNode.requestFocus();
    await tester.pump();
    await tester.runAsync(() async {
      attachments.release.complete();
      await upload;
    });
    await tester.pumpAndSettle();
    expect(model.hasImage, isTrue);
    expect(attachments.files.keys, [model.data.url]);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a completed upload remains dirty after a failed save and saves on retry', (tester) async {
    final store = _Store(_document());
    final attachments = TestAttachmentStore();
    await pumpCanvas(tester, store, attachmentStore: attachments);
    final model = tester.widget<TextTool>(find.byType(TextTool)).model;
    await tester.runAsync(() => model.insertPastedImage(onePixelPngBytes, 'png', attachments));
    store.fail = true;
    await tester.tap(find.byType(CanvasTitle));
    await tester.pumpAndSettle();
    expect(find.byType(CanvasFilePicker), findsNothing);
    expect(model.data.markdown, contains('![pasted image]'));
    expect(find.text('Could not open canvas. Your current canvas is still open.'), findsOneWidget);
    store.fail = false;
    await tester.tap(find.byType(CanvasTitle));
    await tester.pumpAndSettle();
    expect(find.byType(CanvasFilePicker), findsOneWidget);
    expect(canvasAttachmentPaths(store.library.file('a').document!), attachments.files.keys.toSet());
    await tester.pumpWidget(const SizedBox());
  });

  for (final failedSave in [false, true]) {
    testWidgets('${failedSave ? 'failed save retry' : 'picker dismissal'} never revives a canceled clipboard read', (
      tester,
    ) async {
      final store = _Store(_document());
      final attachments = TestAttachmentStore();
      final read = Completer<CanvasClipboardSnapshot>();
      await pumpCanvas(tester, store, attachmentStore: attachments, readClipboard: () => read.future);
      tester.widget<TextTool>(find.byType(TextTool)).model.insertPastedText(' dirty');
      await _clipboardShortcut(tester, LogicalKeyboardKey.keyV);
      store.fail = failedSave;
      await tester.tap(find.byType(CanvasTitle));
      await tester.pumpAndSettle();
      expect(find.byType(CanvasFilePicker), failedSave ? findsNothing : findsOneWidget);
      if (!failedSave) {
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
      }
      read.complete((text: null, image: (bytes: onePixelPngBytes, extension: 'png')));
      await tester.pumpAndSettle();
      expect(attachments.files, isEmpty);
      expect(tester.widget<TextTool>(find.byType(TextTool)).model.data.markdown, 'Original dirty');
      store.fail = false;
      await tester.tap(find.byType(CanvasTitle));
      await tester.pumpAndSettle();
      expect((store.library.file('a').document!.elements.single as TextElementData).markdown, 'Original dirty');
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('a canvas image upload cleans up after navigation without blocking the picker', (tester) async {
    final store = _Store(CanvasLibrary.emptyDocument);
    final attachments = (await tester.runAsync(() async => _PausedAttachments()))!;
    await pumpCanvas(
      tester,
      store,
      attachmentStore: attachments,
      readClipboard: () async => (text: null, image: (bytes: onePixelPngBytes, extension: 'png')),
    );
    await tester.runAsync(() async {
      await _clipboardShortcut(tester, LogicalKeyboardKey.keyV);
      await attachments.started.future;
    });
    await tester.tap(find.byType(CanvasTitle));
    await tester.pumpAndSettle();
    expect(find.byType(CanvasFilePicker), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('file-tree-node-b')));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      attachments.release.complete();
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();
    expect(attachments.files, isEmpty);
    expect(store.library.files.every((file) => file.document!.elements.isEmpty), isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  for (final intoTitle in [false, true]) {
    testWidgets(
      '${intoTitle ? 'title' : 'source'} paste can finish after switching without touching a disposed controller',
      (tester) async {
        final read = Completer<Map<String, Object>>();
        _mockClipboard(tester, () => read.future);
        final store = _Store(_codeDocument());
        await pumpCanvas(tester, store);
        final model = await _focusCode(tester, intoTitle: intoTitle);
        await _pasteCode(tester, intoTitle: intoTitle);
        await tester.tap(find.byType(CanvasTitle));
        await tester.pumpAndSettle();
        expect(find.byType(CanvasFilePicker), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('file-tree-node-b')));
        await tester.pumpAndSettle();
        read.complete({'text': 'NEW'});
        await tester.pumpAndSettle();
        final saved = store.library.file('a').document!.elements.single as CodeElementData;
        expect(saved.source, 'old source');
        expect(saved.title, 'old title');
        expect(model.data.source, 'old source');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
    );

    testWidgets('changing ${intoTitle ? 'title to source' : 'source to title'} cancels paste even after returning', (
      tester,
    ) async {
      final read = Completer<Map<String, Object>>();
      _mockClipboard(tester, () => read.future);
      await pumpCanvas(tester, _Store(_codeDocument()));
      final model = await _focusCode(tester, intoTitle: intoTitle);
      await _pasteCode(tester, intoTitle: intoTitle);
      (intoTitle ? model.focusNode : model.titleFocusNode).requestFocus();
      await tester.pump();
      (intoTitle ? model.titleFocusNode : model.focusNode).requestFocus();
      await tester.pump();
      read.complete({'text': 'NEW'});
      await tester.pumpAndSettle();
      expect(model.data.source, 'old source');
      expect(model.title, 'old title');
      await tester.pumpWidget(const SizedBox());
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    testWidgets('${intoTitle ? 'title' : 'source'} paste survives temporary focus loss in the same context', (
      tester,
    ) async {
      final read = Completer<Map<String, Object>>();
      _mockClipboard(tester, () => read.future);
      await pumpCanvas(tester, _Store(_codeDocument()));
      final model = await _focusCode(tester, intoTitle: intoTitle);
      await _pasteCode(tester, intoTitle: intoTitle);
      tester.widget<CodeTool>(find.byType(CodeTool)).onMove(const Offset(20, 10));
      final node = (intoTitle ? model.titleFocusNode : model.focusNode)..unfocus();
      await tester.pump();
      node.requestFocus();
      await tester.pump();
      if (intoTitle) {
        model.titleController.selection = const TextSelection(baseOffset: 0, extentOffset: 3);
      } else {
        model.controller.selection = const CodeLineSelection(
          baseIndex: 0,
          baseOffset: 0,
          extentIndex: 0,
          extentOffset: 3,
        );
      }
      read.complete({'text': 'NEW'});
      await tester.pumpAndSettle();
      expect(intoTitle ? model.title : model.data.source, intoTitle ? 'NEW title' : 'NEW source');
      await tester.pumpWidget(const SizedBox());
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
  }

  testWidgets('temporary browser blur keeps a code field in one canvas undo group', (tester) async {
    await pumpCanvas(tester, _Store(_codeDocument()));
    final model = await _focusCode(tester, intoTitle: false);
    model.controller.text = 'first';
    model.focusNode.unfocus();
    await tester.pump();
    model.focusNode.requestFocus();
    await tester.pump();
    model.controller.text = 'second';
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _clipboardShortcut(tester, LogicalKeyboardKey.keyZ);
    expect(model.data.source, 'old source');
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('canceled Cut leaves its original objects after the clipboard write succeeds', (tester) async {
    final store = _Store(_document());
    final write = Completer<void>();
    await pumpCanvas(tester, store, writeClipboardText: (_) => write.future);
    tester.widget<TextTool>(find.byType(TextTool)).model.setSelected(value: true);
    await _clipboardShortcut(tester, LogicalKeyboardKey.keyX);
    await tester.tap(find.byType(CanvasTitle));
    await tester.pumpAndSettle();
    expect(find.byType(CanvasFilePicker), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('file-tree-node-b')));
    await tester.pumpAndSettle();
    write.complete();
    await tester.pumpAndSettle();
    expect(store.library.file('a').document!.elements, hasLength(1));
    expect(store.library.currentId, 'b');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('opening settings cancels a pending paste and keeps modal input ahead of the canvas', (tester) async {
    final read = Completer<CanvasClipboardSnapshot>();
    var reads = 0;
    await pumpCanvas(
      tester,
      _Store(CanvasLibrary.emptyDocument),
      readClipboard: () {
        reads++;
        return read.future;
      },
    );
    await _clipboardShortcut(tester, LogicalKeyboardKey.keyV);
    await tester.tap(find.byKey(const ValueKey('settings-button')));
    await tester.pumpAndSettle();
    await _clipboardShortcut(tester, LogicalKeyboardKey.keyV);
    expect(reads, 1);
    read.complete((text: 'https://example.com/image.png', image: null));
    await tester.pumpAndSettle();
    expect(find.byType(MediaTool), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}

// ---------- Fixtures ----------

CanvasDocument _document({bool media = false}) => CanvasDocument(
  background: CanvasBackgroundKind.plain,
  elements: [
    if (media)
      MediaElementData(id: 'media', position: const Offset(150, 200), width: 280, url: 'Original')
    else
      TextElementData(
        id: 'text',
        position: const Offset(150, 200),
        width: 280,
        height: null,
        markdown: 'Original',
        style: const TextNodeStyle(fontFamily: 'Inter'),
      ),
  ],
);

CanvasDocument _codeDocument() => CanvasDocument(
  background: CanvasBackgroundKind.plain,
  elements: [
    CodeElementData(
      id: 'code',
      position: const Offset(150, 200),
      size: const Size(280, 240),
      language: CodeLanguage.dart,
      source: 'old source',
      title: 'old title',
      showLineNumbers: false,
    ),
  ],
);

Future<CodeBlockModel> _focusCode(WidgetTester tester, {required bool intoTitle}) async {
  final tool = tester.widget<CodeTool>(find.byType(CodeTool));
  tool.onEdit();
  await tester.pumpAndSettle();
  final model = tool.model;
  if (intoTitle) {
    model.titleFocusNode.requestFocus();
    await tester.pump();
    model.titleController.selection = const TextSelection(baseOffset: 0, extentOffset: 3);
  } else {
    model.controller.selection = const CodeLineSelection(baseIndex: 0, baseOffset: 0, extentIndex: 0, extentOffset: 3);
  }
  return model;
}

Future<void> _pasteCode(WidgetTester tester, {required bool intoTitle}) async {
  if (intoTitle) {
    final field = find.descendant(
      of: find.byKey(const ValueKey('code-title-input')),
      matching: find.byType(EditableText),
    );
    Actions.invoke(tester.element(field), const PasteTextIntent(SelectionChangedCause.keyboard));
  } else {
    await _clipboardShortcut(tester, LogicalKeyboardKey.keyV);
  }
}

Future<void> _clipboardShortcut(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
}

void _mockClipboard(WidgetTester tester, Future<Map<String, Object>> Function() read) {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async => call.method == 'Clipboard.getData' ? await read() : null,
  );
  addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
}

class _Store extends TestLibraryStore {
  _Store(CanvasDocument document) {
    library = CanvasLibrary(
      currentId: 'a',
      files: [
        CanvasFile(id: 'a', name: 'A', document: document),
        CanvasFile(id: 'b', name: 'B', document: CanvasLibrary.emptyDocument),
      ],
    );
  }

  bool fail = false;

  @override
  Future<void> save(CanvasLibrary snapshot) async {
    if (fail) throw StateError('save failed');
    await super.save(snapshot);
  }
}

class _PausedAttachments extends TestAttachmentStore {
  final started = Completer<void>();
  final release = Completer<void>();

  @override
  Future<void> write(String path, Uint8List bytes) async {
    await super.write(path, bytes);
    started.complete();
    await release.future;
  }
}
