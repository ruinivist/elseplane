// Verifies project import and export behavior from the canvas UI.
// Exercises file transfer, validation, and attachment replacement flows.

import 'dart:async';
import 'dart:convert';

import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/persistence/canvas_library.dart';
import 'package:elseplane/canvas/persistence/canvas_library_archive.dart';
import 'package:elseplane/canvas/persistence/canvas_project.dart';
import 'package:elseplane/canvas/persistence/canvas_project_files.dart';
import 'package:elseplane/canvas/tools/arrow/arrow_tool.dart';
import 'package:elseplane/canvas/tools/code/code_tool.dart';
import 'package:elseplane/canvas/tools/pen/pen_tool.dart';
import 'package:elseplane/canvas/tools/text/text_tool.dart';
import 'package:elseplane/ui/common/select.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_lazy_grid/infinite_lazy_grid.dart';
import 'package:shared_preferences_web/shared_preferences_web.dart';

import '../test_helpers.dart';

// ---------- Tests ----------

void main() {
  setUp(() => SharedPreferencesAsyncWeb.registerWith(null));

  testWidgets('exports the current durable project', (tester) async {
    final document = _document(markdown: '![image]($_path0)');
    final documentStore = _FakeDocumentStore(document);
    final attachments = _FakeAttachmentStore({_path0: onePixelPngBytes});
    final files = _FakeProjectFiles();

    await pumpElseplaneApp(
      tester,
      documentStore: documentStore,
      attachmentStore: attachments,
      projectFiles: files,
    );
    await _openCanvasSettings(tester);
    await tester.tap(find.byKey(const ValueKey('canvas-export-button')));
    await tester.pumpAndSettle();

    expect(files.saved, isNotNull);
    final root = jsonDecode(utf8.decode(files.saved!)) as Map<String, dynamic>;
    expect(root['format'], 'elseplane-canvas');
    expect(root['document'], document.toJson());
    expect(root['attachments'], {_path0: base64Encode(onePixelPngBytes)});
    expect(find.text('Canvas exported'), findsOneWidget);
  });

  testWidgets('backs up the full library including live edits', (tester) async {
    final store = _FakeDocumentStore(_document(markdown: 'before'));
    final files = _FakeProjectFiles();
    await pumpElseplaneApp(tester, documentStore: store, attachmentStore: _FakeAttachmentStore(), projectFiles: files);
    final current = store.library.current;
    store.library = CanvasLibrary(
      currentId: current.id,
      files: [
        current,
        const CanvasFile(id: 'folder', name: 'Work'),
        CanvasFile(
          id: 'second',
          name: 'Second',
          parentId: 'folder',
          document: _document(markdown: 'other'),
        ),
      ],
    );
    tester.widget<TextTool>(find.byType(TextTool)).model.insertPastedText(' changed');
    await tester.pump();
    await _openCanvasSettings(tester);
    await tester.tap(find.byKey(const ValueKey('library-backup-button')));
    await tester.pumpAndSettle();

    expect(files.savedName, 'library.elseplane.zip');
    expect(files.savedMime, 'application/zip');
    final backup = await decodeCanvasLibraryArchive(files.saved!);
    expect(backup.library.path(backup.library.files.last.id).map((file) => file.name), ['Work', 'Second']);
    expect(backup.library.current.document!.elements.whereType<TextElementData>().single.markdown, 'before changed');
  });

  testWidgets('library restore asks before replacing and keeps old data on save failure', (tester) async {
    final oldDocument = _document(markdown: '![old]($_path0)');
    final attachments = _FakeAttachmentStore({_path0: onePixelPngBytes});
    final store = _FakeDocumentStore(oldDocument);
    final imported = CanvasLibrary(
      currentId: 'new',
      files: [
        const CanvasFile(id: 'folder', name: 'Work'),
        CanvasFile(
          id: 'new',
          name: 'New',
          parentId: 'folder',
          document: _document(markdown: '![new]($_path0)'),
        ),
      ],
    );
    final files = _FakeProjectFiles()
      ..opened = await encodeCanvasLibraryArchive(imported, _FakeAttachmentStore({_path0: _newBytes}));
    await pumpElseplaneApp(tester, documentStore: store, attachmentStore: attachments, projectFiles: files);
    final oldId = store.library.currentId;
    await _openCanvasSettings(tester);

    await tester.tap(find.byKey(const ValueKey('library-restore-button')));
    await tester.pumpAndSettle();
    expect(find.text('Replace library?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(store.library.currentId, oldId);
    expect(attachments.files[_path0], onePixelPngBytes);

    store.failLibrarySaves = true;
    await tester.tap(find.byKey(const ValueKey('library-restore-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Replace library'));
    await tester.pumpAndSettle();
    expect(find.text('Could not restore library'), findsOneWidget);
    expect(store.library.currentId, oldId);
    expect(attachments.files[_path0], onePixelPngBytes);

    store.failLibrarySaves = false;
    await tester.tap(find.byKey(const ValueKey('library-restore-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Replace library'));
    await tester.pumpAndSettle();
    expect(store.library.current.name, 'New');
    expect(store.library.path(store.library.currentId).map((file) => file.name), ['Work', 'New']);
    final newPath = canvasAttachmentPaths(store.library.current.document!).single;
    expect(newPath, isNot(_path0));
    expect(attachments.files[newPath], _newBytes);
    expect(attachments.files[_path0], onePixelPngBytes);
  });

  testWidgets('canceled file operations are silent', (tester) async {
    final files = _FakeProjectFiles()..cancelOpen = true;
    await pumpElseplaneApp(
      tester,
      documentStore: _FakeDocumentStore(_document(markdown: '')),
      attachmentStore: _FakeAttachmentStore(),
      projectFiles: files,
    );
    await _openCanvasSettings(tester);
    await tester.tap(find.byKey(const ValueKey('canvas-import-button')));
    await tester.pumpAndSettle();
    expect(files.openCalls, 1);
    expect(find.text('Canvas imported'), findsNothing);
    expect(find.text('Could not import canvas'), findsNothing);

    files
      ..cancelOpen = false
      ..cancelSave = true;
    await tester.tap(find.byKey(const ValueKey('canvas-export-button')));
    await tester.pumpAndSettle();
    expect(find.text('Canvas exported'), findsNothing);
    expect(find.text('Could not export canvas'), findsNothing);
  });

  testWidgets('canceling canvas replacement keeps the active canvas', (tester) async {
    final store = _FakeDocumentStore(_document(markdown: 'original'));
    final files = _FakeProjectFiles()
      ..opened = await encodeCanvasProject(_document(markdown: 'replacement'), _FakeAttachmentStore());
    await pumpElseplaneApp(tester, documentStore: store, attachmentStore: _FakeAttachmentStore(), projectFiles: files);
    await _openCanvasSettings(tester);
    await tester.tap(find.byKey(const ValueKey('canvas-import-button')));
    await tester.pumpAndSettle();
    expect(find.text('Replace canvas?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextTool>(find.byType(TextTool)).model.node.markdown, 'original');
    expect(store.persisted, isNull);
  });

  testWidgets('valid import replaces, persists, and preserves the viewport', (
    tester,
  ) async {
    final oldDocument = _document(markdown: 'old');
    final newDocument = _document(
      markdown: '![new]($_path0)',
      background: CanvasBackgroundKind.dotGrid,
      idSuffix: '-new',
    );
    final attachments = _FakeAttachmentStore({_path0: onePixelPngBytes});
    final documentStore = _FakeDocumentStore(oldDocument);
    final files = _FakeProjectFiles()
      ..opened = await encodeCanvasProject(
        newDocument,
        _FakeAttachmentStore({_path0: _newBytes}),
      );

    await pumpElseplaneApp(
      tester,
      documentStore: documentStore,
      attachmentStore: attachments,
      projectFiles: files,
    );
    tester.widget<TextTool>(find.byType(TextTool)).model.selected = true;
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump();
    await _historyShortcut(tester);
    expect(find.byType(TextTool), findsOneWidget);

    final controller = _canvasController(tester)
      ..scrollBy(const Offset(90, 60))
      ..updateScalebyDelta(0.25);
    await tester.pump();
    final offset = controller.offset;
    final scale = controller.scale;

    await _openCanvasSettings(tester);
    await tester.tap(find.byKey(const ValueKey('canvas-import-button')));
    await _confirmCanvasImport(tester);
    await tester.pumpAndSettle();

    expect(find.text('Canvas imported'), findsOneWidget);
    expect(documentStore.persisted?.toJson(), newDocument.toJson());
    expect(attachments.files[_path0], _newBytes);
    expect(_canvasController(tester).offset, offset);
    expect(_canvasController(tester).scale, scale);
    expect(find.byType(TextTool), findsOneWidget);
    expect(find.byType(CodeTool), findsOneWidget);
    expect(find.byType(PenStroke), findsOneWidget);
    expect(find.byType(Arrow), findsOneWidget);
    expect(
      tester.widget<TextTool>(find.byType(TextTool)).model.selected,
      isFalse,
    );
    expect(
      tester.widget<TextTool>(find.byType(TextTool)).model.focusNode.hasFocus,
      isFalse,
    );

    await _historyShortcut(tester, redo: true);
    expect(
      tester.widget<TextTool>(find.byType(TextTool)).model.node.markdown,
      '![new]($_path0)',
    );

    documentStore.initial = documentStore.persisted;
    await pumpElseplaneApp(
      tester,
      documentStore: documentStore,
      attachmentStore: attachments,
      projectFiles: files,
    );
    expect(find.byType(TextTool), findsOneWidget);
    expect(
      tester.widget<TextTool>(find.byType(TextTool)).model.node.markdown,
      '![new]($_path0)',
    );
  });

  testWidgets(
    'import blocks keyboard and background mutations while committing',
    (
      tester,
    ) async {
      final oldDocument = _document(
        markdown: '![old]($_path0)',
      );
      final newDocument = _document(
        markdown: '![new]($_path0)',
        background: CanvasBackgroundKind.dotGrid,
        idSuffix: '-new',
      );
      final attachments = _FakeAttachmentStore({_path0: onePixelPngBytes});
      final documentStore = _FakeDocumentStore(oldDocument);
      final files = _FakeProjectFiles()
        ..opened = await encodeCanvasProject(
          newDocument,
          _FakeAttachmentStore({_path0: _newBytes}),
        );

      await pumpElseplaneApp(
        tester,
        documentStore: documentStore,
        attachmentStore: attachments,
        projectFiles: files,
      );
      await _openCanvasSettings(tester);
      tester.widget<TextTool>(find.byType(TextTool)).model.selected = true;
      await pumpPastSave(tester);

      final writeGate = Completer<void>();
      attachments.writeGate = writeGate;
      await tester.tap(find.byKey(const ValueKey('canvas-import-button')));
      await _confirmCanvasImport(tester);
      for (var index = 0; index < 10 && !attachments.writeStarted; index++) {
        await tester.pump();
      }
      expect(attachments.writeStarted, isTrue);

      tester
          .widget<Select<CanvasBackgroundKind>>(
            find.byKey(const ValueKey('canvas-background-select')),
          )
          .onChanged!
          .call(CanvasBackgroundKind.dotGrid);
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();

      attachments.failNextWrite = true;
      writeGate.complete();
      await tester.pumpAndSettle();

      expect(find.byType(TextTool), findsOneWidget);
      expect(
        tester.widget<TextTool>(find.byType(TextTool)).model.node.markdown,
        oldDocument.elements.whereType<TextElementData>().single.markdown,
      );
      expect(
        tester.widget<TextTool>(find.byType(TextTool)).model.selected,
        isTrue,
      );

      await tester.tap(find.byKey(const ValueKey('canvas-export-button')));
      await tester.pumpAndSettle();
      final root = jsonDecode(utf8.decode(files.saved!)) as Map<String, dynamic>;
      final exportedDocument = root['document'] as Map<String, dynamic>;
      expect(exportedDocument['background'], CanvasBackgroundKind.plain.name);
    },
  );

  testWidgets(
    'failed dirty flush aborts import and preserves edits for restart',
    (
      tester,
    ) async {
      final oldDocument = _document(markdown: 'old');
      final newDocument = _document(markdown: 'imported', idSuffix: '-new');
      final attachments = _FakeAttachmentStore();
      final documentStore = _FakeDocumentStore(oldDocument)..failSaves = true;
      final files = _FakeProjectFiles()
        ..opened = await encodeCanvasProject(
          newDocument,
          _FakeAttachmentStore(),
        );

      await pumpElseplaneApp(
        tester,
        documentStore: documentStore,
        attachmentStore: attachments,
        projectFiles: files,
      );
      await _openCanvasSettings(tester);
      tester.widget<TextTool>(find.byType(TextTool)).model.insertPastedText(' dirty');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('canvas-import-button')));
      await _confirmCanvasImport(tester);
      await tester.pumpAndSettle();

      expect(files.writeCalls, 0);
      expect(documentStore.saveCalls, greaterThan(0));
      expect(documentStore.persisted, isNull);
      expect(
        tester.widget<TextTool>(find.byType(TextTool)).model.node.markdown,
        'old dirty',
      );

      documentStore.failSaves = false;
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(documentStore.persisted, isNotNull);

      documentStore.initial = documentStore.persisted;
      await pumpElseplaneApp(
        tester,
        documentStore: documentStore,
        attachmentStore: attachments,
        projectFiles: files,
      );
      expect(
        tester.widget<TextTool>(find.byType(TextTool)).model.node.markdown,
        'old dirty',
      );
    },
  );

  testWidgets('failed attachment and document commits roll back safely', (
    tester,
  ) async {
    final oldDocument = _document(markdown: '![old]($_path0)');
    final newDocument = _document(
      markdown: '![new]($_path0)',
      idSuffix: '-new',
    );
    final attachments = _FakeAttachmentStore({_path0: onePixelPngBytes});
    final documentStore = _FakeDocumentStore(oldDocument)..failSaves = true;
    final files = _FakeProjectFiles()
      ..opened = await encodeCanvasProject(
        newDocument,
        _FakeAttachmentStore({_path0: _newBytes}),
      );

    await pumpElseplaneApp(
      tester,
      documentStore: documentStore,
      attachmentStore: attachments,
      projectFiles: files,
    );
    await _openCanvasSettings(tester);
    await tester.tap(find.byKey(const ValueKey('canvas-import-button')));
    await _confirmCanvasImport(tester);
    await tester.pumpAndSettle();

    expect(find.text('Could not import canvas'), findsOneWidget);
    expect(attachments.files[_path0], onePixelPngBytes);
    expect(documentStore.persisted, isNull);
    expect(
      tester.widget<TextTool>(find.byType(TextTool)).model.node.markdown,
      oldDocument.elements.whereType<TextElementData>().single.markdown,
    );

    attachments.failNextWrite = true;
    await tester.tap(find.byKey(const ValueKey('canvas-import-button')));
    await _confirmCanvasImport(tester);
    await tester.pumpAndSettle();
    expect(find.text('Could not import canvas'), findsOneWidget);
    expect(attachments.files[_path0], onePixelPngBytes);
    expect(documentStore.persisted, isNull);

    documentStore.failSaves = false;
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    tester.widget<TextTool>(find.byType(TextTool)).model.insertPastedText(' changed');
    await pumpPastSave(tester);
    expect(documentStore.saveCalls, greaterThan(1));
  });

  testWidgets('malformed import and repeated transfer are ignored safely', (
    tester,
  ) async {
    final files = _FakeProjectFiles()..opened = Uint8List.fromList(utf8.encode('{"format":"wrong"}'));
    await pumpElseplaneApp(
      tester,
      documentStore: _FakeDocumentStore(_document(markdown: 'unchanged')),
      attachmentStore: _FakeAttachmentStore(),
      projectFiles: files,
    );
    await _openCanvasSettings(tester);
    await tester.tap(find.byKey(const ValueKey('canvas-import-button')));
    await tester.pumpAndSettle();
    expect(find.text('Could not import canvas'), findsOneWidget);
    expect(files.writeCalls, 0);

    final completer = Completer<Uint8List?>();
    files
      ..opened = null
      ..openCompleter = completer;
    await tester.tap(find.byKey(const ValueKey('canvas-import-button')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('canvas-import-button')));
    expect(files.openCalls, 2);
    completer.complete(null);
    await tester.pumpAndSettle();
  });
}

Future<void> _openCanvasSettings(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('settings-button')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Canvas').last);
  await tester.pumpAndSettle();
}

Future<void> _confirmCanvasImport(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.tap(find.text('Replace canvas'));
}

Future<void> _historyShortcut(WidgetTester tester, {bool redo = false}) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (redo) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.keyZ);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.keyZ);
  if (redo) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

LazyCanvasController _canvasController(WidgetTester tester) =>
    tester.widget<LazyCanvas>(find.byType(LazyCanvas)).controller;

// ---------- Fixtures ----------

CanvasDocument _document({
  required String markdown,
  CanvasBackgroundKind background = CanvasBackgroundKind.plain,
  String idSuffix = '',
}) => CanvasDocument(
  background: background,
  elements: [
    TextElementData(
      id: 'text$idSuffix',
      position: const Offset(10, 20),
      width: 280,
      height: null,
      markdown: markdown,
      style: const TextNodeStyle(
        fontFamily: 'ABeeZee',
        color: Color(0xff201C1A),
      ),
    ),
    CodeElementData(
      id: 'code$idSuffix',
      position: const Offset(40, 50),
      size: const Size(280, 240),
      language: CodeLanguage.dart,
      source: 'void main() {}',
      title: 'main.dart',
      showLineNumbers: true,
    ),
    PenElementData(
      id: 'pen$idSuffix',
      position: Offset.zero,
      size: const Size(10, 10),
      hitSlop: 0,
      color: const Color(0xff000000),
      width: 1,
      points: const [PenPointData(Offset.zero, pressure: 0)],
    ),
    ArrowElementData(
      id: 'arrow$idSuffix',
      start: Offset.zero,
      controls: const [Offset(10, 4)],
      end: const Offset(20, 0),
      color: const Color(0xff000000),
      strokeStyle: ArrowStrokeStyle.solid,
      strokeWidth: 2,
    ),
  ],
);

const _path0 = 'attachments/00000000-0000-4000-8000-000000000000.png';
final _newBytes = Uint8List.fromList(
  base64Decode('R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw=='),
);

// ---------- Test doubles ----------

class _FakeDocumentStore extends TestCanvasDocumentStore {
  _FakeDocumentStore(super.initial);

  bool failSaves = false;
  bool failLibrarySaves = false;
  int saveCalls = 0;

  @override
  Future<void> save(CanvasDocument document) async {
    saveCalls++;
    if (failSaves) throw StateError('save failed');
    await super.save(document);
  }

  @override
  Future<void> saveLibrary(CanvasLibrary next) async {
    if (failLibrarySaves) throw StateError('library save failed');
    await super.saveLibrary(next);
  }
}

class _FakeAttachmentStore extends TestAttachmentStore {
  _FakeAttachmentStore([super.initial]);

  int writeCalls = 0;
  bool failNextWrite = false;
  Completer<void>? writeGate;
  bool writeStarted = false;

  @override
  Future<void> write(String path, Uint8List bytes) async {
    writeCalls++;
    writeStarted = true;
    final gate = writeGate;
    if (gate != null) {
      writeGate = null;
      await gate.future;
    }
    if (failNextWrite) {
      failNextWrite = false;
      throw StateError('write failed');
    }
    files[path] = Uint8List.fromList(bytes);
  }
}

class _FakeProjectFiles implements CanvasProjectFiles {
  Uint8List? opened;
  Uint8List? saved;
  String? savedName;
  String? savedMime;
  Completer<Uint8List?>? openCompleter;
  bool cancelOpen = false;
  bool cancelSave = false;
  int openCalls = 0;
  int writeCalls = 0;

  @override
  Future<Uint8List?> open() async {
    openCalls++;
    final completer = openCompleter;
    if (completer != null) return await completer.future;
    if (cancelOpen) return null;
    return opened;
  }

  @override
  Future<bool> save(Uint8List bytes, {required String suggestedName, required String mimeType}) async {
    if (cancelSave) return false;
    writeCalls++;
    saved = bytes;
    savedName = suggestedName;
    savedMime = mimeType;
    return true;
  }
}
