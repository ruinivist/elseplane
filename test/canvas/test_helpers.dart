import 'dart:convert';
import 'dart:typed_data';

import 'package:elseplane/app/workspace.dart';
import 'package:elseplane/attachments/attachment_store.dart';
import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/editor/canvas_clipboard.dart';
import 'package:elseplane/canvas/editor/canvas_page.dart';
import 'package:elseplane/canvas/editor/editor_session.dart';
import 'package:elseplane/canvas/editor/element_resources.dart';
import 'package:elseplane/canvas/editor/elements/code/code_editor_resources.dart';
import 'package:elseplane/canvas/editor/elements/code/code_layout.dart';
import 'package:elseplane/canvas/editor/elements/media/media_resources.dart';
import 'package:elseplane/canvas/editor/elements/pen/pen_resources.dart';
import 'package:elseplane/canvas/editor/elements/text/text_editor_resources.dart';
import 'package:elseplane/canvas/editor/elements/text/text_markdown_images.dart';
import 'package:elseplane/canvas/geometry/arrow_geometry.dart';
import 'package:elseplane/canvas/geometry/element_geometry.dart';
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

TextEditorResources testTextModel(TextElementData data, {AttachmentStore? attachmentStore}) =>
    TextEditorResources(_elementSession(data), data, attachmentStore ?? TestAttachmentStore());

TextMarkdownImages testMarkdownImages([String source = '']) {
  final images = TextMarkdownImages(source, TestAttachmentStore());
  addTearDown(images.dispose);
  return images;
}

CodeEditorResources testCodeModel(CodeElementData data) => CodeEditorResources(_elementSession(data), data);
MediaResources testMediaModel(MediaElementData data, AttachmentStore store) =>
    MediaResources(_elementSession(data), data, store);
ElementFixture<ShapeElementData> testShapeFixture(ShapeElementData data) =>
    ElementFixture(_elementSession(data), data.id);
PenResources testPenModel(PenElementData data) => PenResources(_elementSession(data), data);
ElementFixture<ArrowElementData> testArrowFixture(ArrowElementData data) =>
    ElementFixture(_elementSession(data), data.id);

/// Sets up editor fixtures through the same operations used by presentation.
/// Keeps tests from writing presentation snapshots directly.
extension CanvasModelFixture on ElementResources {
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
    final model = this as MediaResources;
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

// ---------- Value-only element fixtures ----------

ElementFixture<T> canvasElement<T extends CanvasElementData>(WidgetTester tester, T value) =>
    ElementFixture(tester.widget<CanvasPage>(find.byType(CanvasPage)).session!, value.id);

@immutable
class ElementFixture<T extends CanvasElementData> {
  const ElementFixture(this.session, this.id);
  final EditorSession session;
  final String id;
  T get data => session.element(id)! as T;
  bool get selected => session.isSelected(id);
  bool get active => session.activeId == id;
  bool get autoArrange => data.autoArrange;
  Offset get canvasPosition => elementBounds(data, codeTitleHeight: codeTitleHeight, mediaSize: Size.zero).topLeft;
  Size get canvasSize => elementBounds(data, codeTitleHeight: codeTitleHeight, mediaSize: Size.zero).size;
  void setSelected({required bool value}) =>
      session.setSelection(value ? {...session.selectedIds, id} : session.selectedIds.difference({id}));
  void setActive({required bool value}) => session.setActive(value ? id : null);
  @override
  bool operator ==(Object other) => other is ElementFixture && identical(session, other.session) && id == other.id;
  @override
  int get hashCode => Object.hash(session, id);
  void setAutoArrange({required bool value}) => session.setAutoArrange([id], value: value);
  void moveBy(Offset delta) => session.move([id], delta);
}

extension ArrowFixtureGeometry on ElementFixture<ArrowElementData> {
  void setStrokeWidth(double width) => session.setArrowOptions(id, strokeWidth: width);
  ArrowGeometry get geometry => data.geometry;
  ArrowGeometry get localGeometry => data.localGeometry;
  Rect get bounds => data.bounds;
  Offset get start => data.start;
  Offset get end => data.end;
  List<Offset> get controls => data.controls;
  int get pointCount => data.pointCount;
  Offset point(int index) => data.point(index);
  bool setPoint(int index, Offset point) {
    final previous = data;
    session.setArrowPoint(id, index, point);
    return previous != data;
  }
}
