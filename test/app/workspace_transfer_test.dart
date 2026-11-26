// Verifies additive local imports and portable exports at the workspace boundary.

import 'dart:async';
import 'dart:convert';

import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/editor/canvas_page.dart';
import 'package:elseplane/canvas/editor/elements/text/text_element_view.dart';
import 'package:elseplane/library/canvas_library.dart';
import 'package:elseplane/library/transfer/canvas_project_files.dart';
import 'package:elseplane/library/transfer/canvas_transfer.dart';
import 'package:elseplane/library/transfer/canvas_transfer_zip.dart';
import 'package:elseplane/library/widgets/canvas_file_picker.dart';
import 'package:elseplane/library/widgets/canvas_title.dart';
import 'package:elseplane/settings/settings_dialog.dart';
import 'package:elseplane/ui/common/select.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_lazy_grid/infinite_lazy_grid.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences_web/shared_preferences_web.dart';

import '../canvas/test_helpers.dart';

void main() {
  setUp(() => SharedPreferencesAsyncWeb.registerWith(null));

  testWidgets('exports the current canvas as its full transfer tree', (tester) async {
    final store = _FakeLibraryStore(_library(_imageDocument('Current')));
    final files = _FakeProjectFiles();
    await pumpElseplaneApp(
      tester,
      libraryStore: store,
      attachmentStore: _FakeAttachmentStore({_path0: onePixelPngBytes}),
      projectFiles: files,
    );
    await _openCanvasSettings(tester);

    await tester.tap(find.byKey(const ValueKey('canvas-export-button')));
    await pumpUntil(tester, () => files.saved != null);
    final transfer = await decodeTransfer(ZipTransferSource(files.saved!));

    expect(files.savedName, 'canvas.elseplane.zip');
    expect(files.savedMime, 'application/zip');
    expect(transfer.canvases.keys, ['Current.canvas.json']);
    expect(transfer.attachments.keys, [_path0]);
    expect(
      find.descendant(of: find.byType(SettingsDialog), matching: find.text('Canvas exported')),
      findsOneWidget,
    );
  });

  testWidgets('exports the whole library including completed edits and empty folders', (tester) async {
    final current = _document('Before');
    final library = _library(
      current,
      extras: [
        const CanvasFile(id: 'folder', name: 'Projects'),
        CanvasFile(id: 'other', name: 'Other', parentId: 'folder', document: _document('Other')),
        const CanvasFile(id: 'empty', name: 'Empty', parentId: 'folder'),
      ],
    );
    final store = _FakeLibraryStore(library);
    final files = _FakeProjectFiles();
    await pumpElseplaneApp(tester, libraryStore: store, attachmentStore: _FakeAttachmentStore(), projectFiles: files);
    tester.widget<TextElementView>(find.byType(TextElementView)).resources.insertPastedText(' changed');
    await tester.pump();
    await pumpPastSave(tester);
    await _openCanvasSettings(tester);

    await tester.tap(find.byKey(const ValueKey('library-export-button')));
    await pumpUntil(tester, () => files.saved != null);
    final transfer = await decodeTransfer(ZipTransferSource(files.saved!));

    expect(files.savedName, 'library.elseplane.zip');
    expect(files.savedMime, 'application/zip');
    expect(transfer.canvases.keys, containsAll(['Current.canvas.json', 'Projects/Other.canvas.json']));
    expect(transfer.directories, containsAll(['Projects', 'Projects/Empty']));
    expect(
      transfer.canvases['Current.canvas.json']!.elements.whereType<TextElementData>().single.markdown,
      'Before changed',
    );
  });

  testWidgets('failed export reports inline and releases the workspace transfer lock', (tester) async {
    final store = _FakeLibraryStore(_library(_document('Current')));
    final files = _FakeProjectFiles()..failSave = true;
    await pumpElseplaneApp(tester, libraryStore: store, attachmentStore: _FakeAttachmentStore(), projectFiles: files);
    await _openCanvasSettings(tester);
    final export = find.byKey(const ValueKey('canvas-export-button'));
    final failure = find.descendant(of: find.byType(SettingsDialog), matching: find.text('Could not export canvas'));
    final success = find.descendant(of: find.byType(SettingsDialog), matching: find.text('Canvas exported'));

    await tester.tap(export);
    await pumpUntil(tester, () => failure.evaluate().isNotEmpty);
    expect(success, findsNothing);

    files.failSave = false;
    await tester.tap(export);
    await pumpUntil(tester, () => success.evaluate().isNotEmpty);
    expect(failure, findsNothing);
    expect(files.savedName, 'canvas.elseplane.zip');
  });

  testWidgets('imports without collisions add content and preserve current selection and local extras', (tester) async {
    final store = _FakeLibraryStore(
      _library(
        _document('Current'),
        extras: [CanvasFile(id: 'extra', name: 'Extra', document: _document('Extra'))],
      ),
    );
    final files = _FakeProjectFiles()..opened = _transferZip({'Projects/New.canvas.json': _document('New')});
    await pumpElseplaneApp(tester, libraryStore: store, attachmentStore: _FakeAttachmentStore(), projectFiles: files);
    final currentId = store.library.currentId;
    await _openCanvasSettings(tester);

    await tester.tap(find.byKey(const ValueKey('canvas-import-button')));
    await _waitForReport(tester);

    expect(find.text('Overwrite canvases?'), findsNothing);
    expect(store.library.currentId, currentId);
    expect(store.library.files.map((file) => file.name), containsAll(['Current', 'Extra', 'Projects', 'New']));
    expect(
      store.library.serializedPath(store.library.files.singleWhere((file) => file.name == 'New').id),
      'Projects/New.canvas.json',
    );
    expect(find.text('Imported 1 canvas.'), findsOneWidget);
    await _closeReport(tester);
  });

  testWidgets('reports skipped document paths with fixed reasons', (tester) async {
    final store = _FakeLibraryStore(_library(_document('Current')));
    final attachments = _FakeAttachmentStore();
    final files = _FakeProjectFiles()
      ..opened = _rawTransferZip({'Projects/Broken.canvas.json': Uint8List.fromList(utf8.encode('{'))});
    await pumpElseplaneApp(tester, libraryStore: store, attachmentStore: attachments, projectFiles: files);
    await _openCanvasSettings(tester);

    await tester.tap(find.byKey(const ValueKey('canvas-import-button')));
    await _waitForReport(tester);

    expect(find.textContaining('Projects/Broken.canvas.json: Invalid JSON'), findsOneWidget);
    expect(find.textContaining('FormatException'), findsNothing);
    expect(attachments.writeCalls, 0);
    expect(store.library.files.map((file) => file.name), containsAll(['Current', 'Projects']));
    expect(store.library.files.any((file) => file.name == 'Broken'), isFalse);
    await _closeReport(tester);
  });

  testWidgets('sanitizes preparation failures before showing the import result', (tester) async {
    final store = _FakeLibraryStore(_library(_document('Current')));
    final attachments = _FakeAttachmentStore();
    final files = _FakeProjectFiles()..opened = Uint8List.fromList([1, 2, 3]);
    await pumpElseplaneApp(tester, libraryStore: store, attachmentStore: attachments, projectFiles: files);
    await _openCanvasSettings(tester);

    await tester.tap(find.byKey(const ValueKey('canvas-import-button')));
    await _waitForReport(tester);

    expect(find.textContaining('Could not prepare transfer'), findsOneWidget);
    expect(find.textContaining('FormatException'), findsNothing);
    expect(attachments.writeCalls, 0);
    expect(store.library.files.map((file) => file.name), ['Current']);
    await _closeReport(tester);
  });

  testWidgets('canceling a batch overwrite performs no image or metadata writes', (tester) async {
    final store = _FakeLibraryStore(
      _library(
        _imageDocument('Current'),
        extras: [CanvasFile(id: 'other', name: 'Other', document: _document('Other'))],
      ),
    );
    final attachments = _FakeAttachmentStore({_path0: onePixelPngBytes});
    final files = _FakeProjectFiles()
      ..opened = _transferZip(
        {'Current.canvas.json': _imageDocument('Replacement'), 'Other.canvas.json': _document('Other replacement')},
        attachments: {_path0: _newBytes},
      );
    await pumpElseplaneApp(tester, libraryStore: store, attachmentStore: attachments, projectFiles: files);
    await _openCanvasSettings(tester);

    await tester.tap(find.byKey(const ValueKey('canvas-import-button')));
    await _waitForOverwrite(tester);
    expect(find.text('Current.canvas.json'), findsOneWidget);
    expect(find.text('Other.canvas.json'), findsOneWidget);
    expect(find.textContaining('Shared images may also change in other canvases.'), findsOneWidget);
    await tester.tap(find.text('Cancel').last);
    await _waitForReport(tester);

    expect(find.text('Import canceled.'), findsOneWidget);
    expect(attachments.writeCalls, 0);
    expect(attachments.files[_path0], orderedEquals(onePixelPngBytes));
    expect(store.persisted, isNull);
    expect(store.library.current.document!.elements.whereType<TextElementData>().single.markdown, contains('Current'));
    await _closeReport(tester);
  });

  testWidgets('durably overwriting the active canvas retains its ID and replaces only its editor', (tester) async {
    final store = _FakeLibraryStore(_library(_imageDocument('Current')));
    final attachments = _FakeAttachmentStore({_path0: onePixelPngBytes});
    final files = _FakeProjectFiles()
      ..opened = _transferZip({'Current.canvas.json': _imageDocument('Replacement')}, attachments: {_path0: _newBytes});
    await pumpElseplaneApp(tester, libraryStore: store, attachmentStore: attachments, projectFiles: files);
    final page = tester.widget<CanvasPage>(find.byType(CanvasPage));
    final oldSession = page.session!;
    final currentId = store.library.currentId;
    final controller = _canvasController(tester)
      ..scrollBy(const Offset(90, 60))
      ..updateScalebyDelta(0.25);
    await tester.pump();
    final offset = controller.offset;
    final scale = controller.scale;
    await _openCanvasSettings(tester);

    await tester.tap(find.byKey(const ValueKey('canvas-import-button')));
    await _waitForOverwrite(tester);
    await tester.tap(find.text('Overwrite and import'));
    await _waitForReport(tester);

    final updatedPage = tester.widget<CanvasPage>(find.byType(CanvasPage));
    expect(store.library.currentId, currentId);
    expect(
      store.library.current.document!.elements.whereType<TextElementData>().single.markdown,
      contains('Replacement'),
    );
    expect(identical(updatedPage.session, oldSession), isFalse);
    expect(oldSession.isLive, isFalse);
    expect(_canvasController(tester).offset, offset);
    expect(_canvasController(tester).scale, scale);
    expect(attachments.files[_path0], orderedEquals(_newBytes));
    expect(find.text('Imported 1 canvas.'), findsOneWidget);
    await _closeReport(tester);
  });

  testWidgets('overwriting another canvas refreshes shared bytes without clearing active history', (tester) async {
    final current = _imageDocument('Current');
    final store = _FakeLibraryStore(
      _library(
        current,
        extras: [CanvasFile(id: 'other', name: 'Other', document: _imageDocument('Other'))],
      ),
    );
    final attachments = _FakeAttachmentStore({_path0: onePixelPngBytes});
    final files = _FakeProjectFiles()
      ..opened = _transferZip(
        {'Other.canvas.json': _imageDocument('Other imported')},
        attachments: {_path0: _newBytes},
      );
    await pumpElseplaneApp(tester, libraryStore: store, attachmentStore: attachments, projectFiles: files);
    final page = tester.widget<CanvasPage>(find.byType(CanvasPage));
    final session = page.session!;
    tester.widget<TextElementView>(find.byType(TextElementView)).resources.insertPastedText(' changed');
    await tester.pump();
    await _openCanvasSettings(tester);

    await tester.tap(find.byKey(const ValueKey('canvas-import-button')));
    await _waitForOverwrite(tester);
    await tester.tap(find.text('Overwrite and import'));
    await _waitForReport(tester);

    expect(identical(tester.widget<CanvasPage>(find.byType(CanvasPage)).session, session), isTrue);
    expect(attachments.files[_path0], orderedEquals(_newBytes));
    session.undo();
    expect(
      session.document.elements.whereType<TextElementData>().single.markdown,
      current.elements.whereType<TextElementData>().single.markdown,
    );
    await _closeReport(tester);
  });

  testWidgets('metadata failure reports possible image changes and retains the current editor', (tester) async {
    final store = _FakeLibraryStore(_library(_document('Current')));
    final attachments = _FakeAttachmentStore({_path0: onePixelPngBytes});
    final files = _FakeProjectFiles()
      ..opened = _transferZip({'Current.canvas.json': _imageDocument('Replacement')}, attachments: {_path0: _newBytes});
    await pumpElseplaneApp(tester, libraryStore: store, attachmentStore: attachments, projectFiles: files);
    final session = tester.widget<CanvasPage>(find.byType(CanvasPage)).session!;
    store.failSaves = true;
    await _openCanvasSettings(tester);

    await tester.tap(find.byKey(const ValueKey('canvas-import-button')));
    await _waitForOverwrite(tester);
    await tester.tap(find.text('Overwrite and import'));
    await _waitForReport(tester);

    expect(find.textContaining('Images may have changed; imported canvases were not saved.'), findsOneWidget);
    expect(find.textContaining('Library save failed'), findsOneWidget);
    expect(attachments.files[_path0], orderedEquals(_newBytes));
    expect(store.library.current.document!.elements.whereType<TextElementData>().single.markdown, contains('Current'));
    expect(identical(tester.widget<CanvasPage>(find.byType(CanvasPage)).session, session), isTrue);
    await _closeReport(tester);
  });

  testWidgets('failed image write reports its attempted key and preserves the current canvas', (tester) async {
    final store = _FakeLibraryStore(_library(_document('Current')));
    final attachments = _FakeAttachmentStore({_path0: onePixelPngBytes})
      ..failNextWrite = true
      ..writeThenFail = true;
    final files = _FakeProjectFiles()
      ..opened = _transferZip({'Current.canvas.json': _imageDocument('Replacement')}, attachments: {_path0: _newBytes});
    await pumpElseplaneApp(tester, libraryStore: store, attachmentStore: attachments, projectFiles: files);
    final session = tester.widget<CanvasPage>(find.byType(CanvasPage)).session!;
    await _openCanvasSettings(tester);

    await tester.tap(find.byKey(const ValueKey('canvas-import-button')));
    await _waitForOverwrite(tester);
    await tester.tap(find.text('Overwrite and import'));
    await _waitForReport(tester);

    expect(find.textContaining('Images may have changed; imported canvases were not saved.'), findsOneWidget);
    expect(find.textContaining('Image write failed: $_path0'), findsOneWidget);
    expect(attachments.files[_path0], orderedEquals(_newBytes));
    expect(store.library.current.document!.elements.whereType<TextElementData>().single.markdown, 'Current');
    expect(identical(tester.widget<CanvasPage>(find.byType(CanvasPage)).session, session), isTrue);
    expect(store.persisted, isNull);
    await _closeReport(tester);
  });

  testWidgets('nested current-canvas context is used by the editor and export', (tester) async {
    final store = _FakeLibraryStore(
      _library(
        _imageDocument('Nested'),
        extras: [const CanvasFile(id: 'folder', name: 'Work')],
        currentParentId: 'folder',
      ),
    );
    final files = _FakeProjectFiles();
    await pumpElseplaneApp(
      tester,
      libraryStore: store,
      attachmentStore: _FakeAttachmentStore({'Work/$_path0': onePixelPngBytes}),
      projectFiles: files,
    );
    expect(tester.widget<CanvasPage>(find.byType(CanvasPage)).canvasDirectory, 'Work');
    await _openCanvasSettings(tester);

    await tester.tap(find.byKey(const ValueKey('canvas-export-button')));
    await pumpUntil(tester, () => files.saved != null);
    final transfer = await decodeTransfer(ZipTransferSource(files.saved!));

    expect(transfer.canvases.keys, ['Work/Map.canvas.json']);
    expect(transfer.attachments.keys, ['Work/$_path0']);
  });

  testWidgets('moving the active canvas while the picker is open updates only its directory context', (tester) async {
    final store = _FakeLibraryStore(
      _library(
        _imageDocument('Nested'),
        extras: [const CanvasFile(id: 'folder', name: 'Work')],
        currentParentId: 'folder',
      ),
    );
    final attachments = _FakeAttachmentStore({'Work/$_path0': onePixelPngBytes});
    await pumpElseplaneApp(tester, libraryStore: store, attachmentStore: attachments);
    final session = tester.widget<CanvasPage>(find.byType(CanvasPage)).session!;
    await tester.tap(find.byType(CanvasTitle));
    await tester.pumpAndSettle();
    final picker = tester.widget<CanvasFilePicker>(find.byType(CanvasFilePicker));

    await picker.controller.move('current', parentId: null);
    await tester.pumpAndSettle();

    expect(store.library.parentDirectory('current'), '');
    expect(attachments.files[_path0], orderedEquals(onePixelPngBytes));
    expect(tester.widget<CanvasPage>(find.byType(CanvasPage)).canvasDirectory, '');
    expect(identical(tester.widget<CanvasPage>(find.byType(CanvasPage)).session, session), isTrue);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
  });

  testWidgets('the workspace blocks editor actions while import writes are pending', (tester) async {
    final store = _FakeLibraryStore(_library(_document('Current')));
    final attachments = _FakeAttachmentStore()..writeGate = Completer<void>();
    final writeGate = attachments.writeGate!;
    final files = _FakeProjectFiles()
      ..opened = _transferZip({'New.canvas.json': _imageDocument('New')}, attachments: {_path0: _newBytes});
    await pumpElseplaneApp(tester, libraryStore: store, attachmentStore: attachments, projectFiles: files);
    final session = tester.widget<CanvasPage>(find.byType(CanvasPage)).session!;
    await _openCanvasSettings(tester);

    await tester.tap(find.byKey(const ValueKey('canvas-import-button')));
    await pumpUntil(tester, () => attachments.writeStarted);
    tester.widget<Select<CanvasBackgroundKind>>(find.byKey(const ValueKey('canvas-background-select'))).onChanged!(
      CanvasBackgroundKind.dotGrid,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    expect(session.document.background, CanvasBackgroundKind.plain);
    expect(session.document.elements.whereType<TextElementData>().single.markdown, 'Current');

    writeGate.complete();
    await _waitForReport(tester);
    expect(store.library.files.any((file) => file.name == 'New'), isTrue);
    expect(session.document.elements.whereType<TextElementData>().single.markdown, 'Current');
    await _closeReport(tester);
  });

  testWidgets('failed dirty flush stops import before any transfer writes', (tester) async {
    final store = _FakeLibraryStore(_library(_document('Original')));
    final attachments = _FakeAttachmentStore();
    final files = _FakeProjectFiles()..opened = _transferZip({'New.canvas.json': _document('New')});
    await pumpElseplaneApp(tester, libraryStore: store, attachmentStore: attachments, projectFiles: files);
    tester.widget<TextElementView>(find.byType(TextElementView)).resources.insertPastedText(' dirty');
    await tester.pump();
    store.failSaves = true;
    await _openCanvasSettings(tester);

    await tester.tap(find.byKey(const ValueKey('canvas-import-button')));
    await _waitForReport(tester);

    expect(attachments.writeCalls, 0);
    expect(store.library.files.where((file) => file.name == 'New'), isEmpty);
    expect(find.text('Could not prepare transfer'), findsOneWidget);
    await _closeReport(tester);
    final text = tester.widget<TextElementView>(find.byType(TextElementView)).resources;
    expect(text.node.markdown, 'Original dirty');
    store.failSaves = false;
    text.insertPastedText(' retry');
    await pumpPastSave(tester);
    expect(store.persisted!.elements.whereType<TextElementData>().single.markdown, 'Original dirty retry');
  });

  testWidgets('canceled file selection is silent and overlapping Settings imports are blocked', (tester) async {
    final files = _FakeProjectFiles()..cancelOpen = true;
    await pumpElseplaneApp(
      tester,
      libraryStore: _FakeLibraryStore(_library(_document('Original'))),
      projectFiles: files,
    );
    await _openCanvasSettings(tester);
    await tester.tap(find.byKey(const ValueKey('canvas-import-button')));
    await tester.pumpAndSettle();
    expect(files.openCalls, 1);
    expect(find.text('Import result'), findsNothing);

    files
      ..cancelOpen = false
      ..openCompleter = Completer<({String name, Uint8List bytes})?>();
    await tester.tap(find.byKey(const ValueKey('canvas-import-button')));
    await tester.pump();
    expect(_button(tester, 'canvas-import-button').onPressed, isNull);
    files.openCompleter!.complete(null);
    await tester.pumpAndSettle();
  });
}

Future<void> _openCanvasSettings(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('settings-button')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Canvas').last);
  await tester.pumpAndSettle();
}

Future<void> _waitForOverwrite(WidgetTester tester) =>
    pumpUntil(tester, () => find.text('Overwrite canvases?').evaluate().isNotEmpty);

Future<void> _waitForReport(WidgetTester tester) =>
    pumpUntil(tester, () => find.text('Import result').evaluate().isNotEmpty);

Future<void> _closeReport(WidgetTester tester) async {
  await tester.tap(find.text('Done'));
  await tester.pumpAndSettle();
}

ButtonStyleButton _button(WidgetTester tester, String key) => tester.widget(find.byKey(ValueKey(key)));

CanvasLibrary _library(
  CanvasDocument current, {
  List<CanvasFile> extras = const [],
  String? currentParentId,
}) => CanvasLibrary(
  currentId: 'current',
  files: [
    if (currentParentId != null) ...extras.where((file) => file.id == currentParentId),
    CanvasFile(
      id: 'current',
      name: currentParentId == null ? 'Current' : 'Map',
      parentId: currentParentId,
      document: current,
    ),
    ...extras.where((file) => file.id != currentParentId),
  ],
);

CanvasDocument _document(String markdown) => CanvasDocument(
  background: CanvasBackgroundKind.plain,
  elements: [
    TextElementData(
      id: 'text',
      position: const Offset(10, 20),
      width: 280,
      height: null,
      markdown: markdown,
      style: const TextNodeStyle(fontFamily: 'ABeeZee', color: Color(0xff201C1A)),
    ),
  ],
);

CanvasDocument _imageDocument(String markdown) => _document('$markdown\n\n![image]($_path0)');

Uint8List _transferZip(
  Map<String, CanvasDocument> canvases, {
  Map<String, Uint8List> attachments = const {},
  Set<String> directories = const {},
}) => encodeTransferZip(
  TransferTree(
    files: {
      for (final entry in canvases.entries)
        entry.key: Uint8List.fromList(utf8.encode(jsonEncode(entry.value.toJson()))),
      ...attachments,
    },
    directories: directories,
  ),
);

Uint8List _rawTransferZip(Map<String, Uint8List> files) => encodeTransferZip(TransferTree(files: files));

const _path0 = 'attachments/00000000-0000-4000-8000-000000000000.png';
final _newBytes = Uint8List.fromList(
  base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADUlEQVR4nGP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC'),
);

class _FakeLibraryStore extends TestLibraryStore {
  _FakeLibraryStore(CanvasLibrary library) : super(library.current.document) {
    this.library = library;
  }

  bool failSaves = false;
  int saveCalls = 0;

  @override
  Future<void> save(CanvasLibrary snapshot, {required CanvasLibrary? previous}) async {
    saveCalls++;
    if (failSaves) throw Exception('save failed');
    await super.save(snapshot, previous: previous);
  }
}

class _FakeAttachmentStore extends TestAttachmentStore {
  _FakeAttachmentStore([super.initial]);

  int writeCalls = 0;
  bool writeStarted = false;
  bool failNextWrite = false;
  bool writeThenFail = false;
  Completer<void>? writeGate;

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
      if (writeThenFail) files[path] = Uint8List.fromList(bytes);
      throw StateError('write failed');
    }
    files[path] = Uint8List.fromList(bytes);
  }
}

LazyCanvasController _canvasController(WidgetTester tester) =>
    tester.widget<LazyCanvas>(find.byType(LazyCanvas)).controller;

class _FakeProjectFiles implements CanvasProjectFiles {
  Uint8List? opened;
  String openedName = 'input.zip';
  Uint8List? saved;
  String? savedName;
  String? savedMime;
  Completer<({String name, Uint8List bytes})?>? openCompleter;
  bool cancelOpen = false;
  bool cancelSave = false;
  bool failSave = false;
  int openCalls = 0;

  @override
  Future<({String name, Uint8List bytes})?> open() async {
    openCalls++;
    final completer = openCompleter;
    if (completer != null) return await completer.future;
    if (cancelOpen) return null;
    return opened == null ? null : (name: openedName, bytes: opened!);
  }

  @override
  Future<bool> save(Uint8List bytes, {required String suggestedName, required String mimeType}) async {
    if (failSave) throw StateError('save failed');
    if (cancelSave) return false;
    saved = bytes;
    savedName = suggestedName;
    savedMime = mimeType;
    return true;
  }
}
