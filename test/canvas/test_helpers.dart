import 'dart:convert';
import 'dart:typed_data';

import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/editor/canvas_clipboard.dart';
import 'package:elseplane/canvas/editor/canvas_page.dart';
import 'package:elseplane/canvas/persistence/attachments/store.dart';
import 'package:elseplane/canvas/persistence/canvas_document_store.dart';
import 'package:elseplane/canvas/persistence/canvas_library.dart';
import 'package:elseplane/canvas/persistence/canvas_project_files.dart';
import 'package:elseplane/main.dart';
import 'package:elseplane/theme/starless.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class TestCanvasDocumentStore extends CanvasDocumentStore {
  TestCanvasDocumentStore([this.initial]);

  CanvasDocument? initial;
  CanvasDocument? persisted;

  @override
  Future<CanvasDocument?> load() async {
    library = CanvasLibrary.initial(initial);
    return initial;
  }

  @override
  Future<void> save(CanvasDocument document) async {
    persisted = document;
    library = library.replace(library.current.copyWith(document: document));
  }

  @override
  Future<void> saveLibrary(CanvasLibrary next) async {
    library = next;
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

final onePixelPngBytes = Uint8List.fromList(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8A'
    'AQUBAScY42YAAAAASUVORK5CYII=',
  ),
);

Future<void> pumpCanvas(
  WidgetTester tester,
  CanvasDocumentStore documentStore, {
  AttachmentStore? attachmentStore,
  Future<CanvasClipboardSnapshot> Function()? readClipboard,
  Future<void> Function(String text)? writeClipboardText,
  TargetPlatform? platform,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: platform == null ? starlessLightThemeData : starlessLightThemeData.copyWith(platform: platform),
      home: CanvasPage(
        documentStore: documentStore,
        attachmentStore: attachmentStore,
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
  CanvasDocumentStore? documentStore,
  CanvasProjectFiles? projectFiles,
}) async {
  await tester.pumpWidget(
    ElseplaneApp(
      attachmentStore: attachmentStore,
      documentStore: documentStore,
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
