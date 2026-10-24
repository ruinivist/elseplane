import 'dart:convert';
import 'dart:typed_data';

import 'package:elseplane/app/workspace.dart';
import 'package:elseplane/attachments/attachment_store.dart';
import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/editor/canvas_clipboard.dart';
import 'package:elseplane/canvas/editor/canvas_element_model.dart';
import 'package:elseplane/canvas/editor/canvas_page.dart';
import 'package:elseplane/canvas/editor/editor_session.dart';
import 'package:elseplane/canvas/tools/arrow/arrow_tool.dart';
import 'package:elseplane/canvas/tools/code/code_tool.dart';
import 'package:elseplane/canvas/tools/media/media_tool.dart';
import 'package:elseplane/canvas/tools/pen/pen_tool.dart';
import 'package:elseplane/canvas/tools/shape/shape_tool.dart';
import 'package:elseplane/canvas/tools/text/text_tool.dart';
import 'package:elseplane/library/canvas_library.dart';
import 'package:elseplane/library/library_store.dart';
import 'package:elseplane/library/transfer/canvas_project_files.dart';
import 'package:elseplane/main.dart';
import 'package:elseplane/theme/preset_colors.dart';
import 'package:elseplane/theme/starless.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class TestLibraryStore implements LibraryStore {
  TestLibraryStore([this.initial]) : library = CanvasLibrary.initial(initial);

  CanvasLibrary library;
  CanvasDocument? persisted;

  CanvasDocument? initial;

  @override
  Future<CanvasLibrary?> load() async => library;

  @override
  Future<void> save(CanvasLibrary snapshot) async {
    library = snapshot;
    persisted = snapshot.current.document;
  }
}

class TestAttachmentStore implements AttachmentStore {
  TestAttachmentStore([Map<String, Uint8List>? initial]) : files = {...?initial};

  final Map<String, Uint8List> files;

  @override
  Future<void> delete(String path) async {
    files.remove(path);
  }

  @override
  Future<Uint8List> read(String path) async {
    final bytes = files[path];
    if (bytes == null) throw StateError('Missing attachment: $path');
    return bytes;
  }

  @override
  Future<Uint8List?> readIfExists(String path) async => files[path];

  @override
  Future<void> write(String path, Uint8List bytes) async {
    files[path] = bytes;
  }
}

class TestProjectFiles implements CanvasProjectFiles {
  @override
  Future<Uint8List?> open() async => null;

  @override
  Future<bool> save(Uint8List bytes, {required String suggestedName, required String mimeType}) async => false;
}

final onePixelPngBytes = Uint8List.fromList(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8A'
    'AQUBAScY42YAAAAASUVORK5CYII=',
  ),
);

Future<void> pumpCanvas(
  WidgetTester tester,
  LibraryStore libraryStore, {
  AttachmentStore? attachmentStore,
  Future<CanvasClipboardSnapshot> Function()? readClipboard,
  Future<void> Function(String text)? writeClipboardText,
  TargetPlatform? platform,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: platform == null ? starlessLightThemeData : starlessLightThemeData.copyWith(platform: platform),
      home: Workspace(
        libraryStore: libraryStore,
        attachmentStore: attachmentStore ?? TestAttachmentStore(),
        projectFiles: TestProjectFiles(),
        readClipboard: readClipboard,
        writeClipboardText: writeClipboardText,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

Future<void> pumpElseplaneApp(
  WidgetTester tester, {
  AttachmentStore? attachmentStore,
  LibraryStore? libraryStore,
  CanvasProjectFiles? projectFiles,
}) async {
  await tester.pumpWidget(
    ElseplaneApp(
      attachmentStore: attachmentStore,
      libraryStore: libraryStore,
      projectFiles: projectFiles,
    ),
  );
  await tester.pump();
  await tester.pump();
}

Future<void> pumpPastSave(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 320));
  await tester.pump();
}

// ---------- Document fixtures ----------

/// Builds a new fixture from a private editable list.
/// Published documents remain immutable throughout test setup.
extension CanvasDocumentFixture on CanvasDocument {
  CanvasDocument withElements(void Function(List<CanvasElementData>) update) {
    final elements = this.elements.toList();
    update(elements);
    return copyWith(elements: elements);
  }
}

// ---------- Editor fixtures ----------

EditorSession testSession(CanvasDocument document) {
  final session = EditorSession(document, initialColor: defaultCanvasColor);
  addTearDown(session.dispose);
  return session;
}

EditorSession _elementSession(CanvasElementData data) =>
    testSession(CanvasDocument(background: CanvasBackgroundKind.plain, elements: [data]));

TextBlockModel testTextModel(TextElementData data) => TextBlockModel(_elementSession(data), data);
CodeBlockModel testCodeModel(CodeElementData data) => CodeBlockModel(_elementSession(data), data);
MediaModel testMediaModel(MediaElementData data, AttachmentStore store) =>
    MediaModel(_elementSession(data), data, store);
ShapeModel testShapeModel(ShapeElementData data) => ShapeModel(_elementSession(data), data);
PenStrokeModel testPenModel(PenElementData data) => PenStrokeModel(_elementSession(data), data);
ArrowModel testArrowModel(ArrowElementData data) => ArrowModel(_elementSession(data), data);

/// Sets up editor fixtures through the same operations used by presentation.
/// Keeps tests from writing presentation snapshots directly.
extension CanvasModelFixture on CanvasElementModel {
  void setSelected({required bool value}) =>
      session.setSelection(value ? {...session.selectedIds, data.id} : ({...session.selectedIds}..remove(data.id)));
  void setActive({required bool value}) => session.setActive(value ? data.id : null);
  void setEditing({required bool value}) =>
      session.editField(value ? (id: data.id, field: EditorField.markdown) : null);
  void setAutoArrange({required bool value}) => session.setAutoArrange([data.id], value: value);
  void moveBy(Offset delta) {
    if (session.element(data.id) != null) session.move([data.id], delta);
  }

  void rotate(double angle) => session.rotate(data.id, angle);
  void setTitle(String title) => session.setCodeTitle(data.id, title);
  void resize(Size rendered, Offset delta) => session.resizeText(data.id, rendered, delta);
  void setStyle(TextNodeStyle style) => session.setTextStyle(data.id, style);
  void setLanguage(CodeLanguage language) => session.setCodeLanguage(data.id, language);
  void setBackground(BlockBackgroundKind background) => session.setCodeBackground(data.id, background);
  void setShowLineNumbers({required bool value}) => session.setLineNumbers(data.id, value: value);
  void setSize(Size size) => session.resizeCode(data.id, size);
  void setStrokeWidth(double width) => session.setArrowOptions(data.id, strokeWidth: width);
  bool setPoint(int index, Offset point) {
    final previous = data;
    session.setArrowPoint(data.id, index, point);
    return previous != data;
  }

  void resizeBy(Offset delta) {
    final model = this as MediaModel;
    session.resizeMedia(data.id, delta, model.aspectRatio!);
  }
}

Future<void> replaceTestEditor(WidgetTester tester, CanvasDocument document) async {
  final page = tester.widget<CanvasPage>(find.byType(CanvasPage));
  page.session!.endLifetime();
  await tester.pumpWidget(
    MaterialApp(
      theme: starlessLightThemeData,
      home: CanvasPage(
        session: testSession(document),
        attachmentStore: page.attachmentStore,
        libraryPath: page.libraryPath,
        onOpenLibrary: page.onOpenLibrary,
        onImportCanvas: page.onImportCanvas,
        onExportCanvas: page.onExportCanvas,
        onBackupLibrary: page.onBackupLibrary,
        onRestoreLibrary: page.onRestoreLibrary,
        readClipboard: page.readClipboard,
        writeClipboardText: page.writeClipboardText,
      ),
    ),
  );
}

EditorSession Function() testSessionProvider() {
  final session = testSession(CanvasLibrary.emptyDocument);
  return () => session;
}
