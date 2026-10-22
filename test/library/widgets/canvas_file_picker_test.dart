// Checks file creation, naming, switching, and persistence failure behavior.
// Exercises the file picker through the canvas title and browser-backed UI.

import 'dart:async';

import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/editor/widgets/toolbar_button.dart';
import 'package:elseplane/canvas/tools/text/text_tool.dart';
import 'package:elseplane/library/canvas_library.dart';
import 'package:elseplane/library/debug/demo_canvas.dart';
import 'package:elseplane/library/library_controller.dart';
import 'package:elseplane/library/transfer/canvas_project.dart';
import 'package:elseplane/library/widgets/canvas_file_picker.dart';
import 'package:elseplane/library/widgets/canvas_title.dart';
import 'package:elseplane/library/widgets/file_tree_popup.dart';
import 'package:elseplane/theme/fonts.dart';
import 'package:elseplane/theme/starless.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_web/shared_preferences_web.dart';

import '../../canvas/test_helpers.dart';

// ---------- Tests ----------

void main() {
  setUp(() => SharedPreferencesAsyncWeb.registerWith(null));

  for (final platform in [TargetPlatform.linux, TargetPlatform.macOS]) {
    for (final releaseModifier in [true, false]) {
      testWidgets('$platform picker dismissal tracks modifier release: $releaseModifier', (tester) async {
        final store = TestLibraryStore(
          CanvasDocument(
            background: CanvasBackgroundKind.plain,
            elements: [
              TextElementData(
                id: 'text',
                position: const Offset(100, 150),
                width: 280,
                height: null,
                markdown: 'Original',
                style: const TextNodeStyle(fontFamily: defaultFontFamily),
              ),
            ],
          ),
        );
        await pumpCanvas(tester, store, platform: platform);
        final modifier = platform == TargetPlatform.macOS
            ? LogicalKeyboardKey.metaLeft
            : LogicalKeyboardKey.controlLeft;
        await tester.sendKeyDownEvent(modifier);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
        await tester.pumpAndSettle();
        expect(find.byType(CanvasFilePicker), findsOneWidget);
        if (releaseModifier) await tester.sendKeyUpEvent(modifier);
        await tester.tap(find.byKey(const ValueKey('file-tree-close')), kind: PointerDeviceKind.mouse);
        await tester.pumpAndSettle();
        expect(find.byType(CanvasFilePicker), findsNothing);
        await tester.tapAt(tester.getCenter(find.byType(TextTool)), kind: PointerDeviceKind.mouse);
        await tester.pumpAndSettle();
        final model = tester.widget<TextTool>(find.byType(TextTool)).model;
        expect(model.editing, releaseModifier);
        expect(model.selected, !releaseModifier);
        if (!releaseModifier) await tester.sendKeyUpEvent(modifier);
      });
    }

    testWidgets('$platform shortcut opens while editing and Enter switches canvases', (tester) async {
      final store = TestLibraryStore(
        CanvasDocument(
          background: CanvasBackgroundKind.plain,
          elements: [
            TextElementData(
              id: 'text',
              position: const Offset(100, 150),
              width: 280,
              height: null,
              markdown: 'Original',
              style: const TextNodeStyle(fontFamily: defaultFontFamily),
            ),
          ],
        ),
      );
      final originalId = store.library.currentId;
      store.library = CanvasLibrary(
        files: [
          ...store.library.files,
          CanvasFile(id: 'next', name: 'Next', document: CanvasLibrary.emptyDocument),
        ],
        currentId: originalId,
      );
      await pumpCanvas(tester, store, platform: platform);
      final text = tester.widget<TextTool>(find.byType(TextTool));
      text.onEdit();
      await tester.pumpAndSettle();
      expect(text.model.focusNode.hasFocus, isTrue);
      text.model.insertPastedText(' edited');
      final modifier = platform == TargetPlatform.macOS ? LogicalKeyboardKey.metaLeft : LogicalKeyboardKey.controlLeft;
      await tester.sendKeyDownEvent(modifier);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyP);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.keyP);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyP);
      await tester.sendKeyUpEvent(modifier);
      await tester.pumpAndSettle();
      expect(find.byType(CanvasFilePicker), findsOneWidget);
      expect(
        store.library.file(originalId).document!.elements.whereType<TextElementData>().single.markdown,
        contains('edited'),
      );
      expect(text.model.editing, isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(store.library.currentId, originalId);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(store.library.currentId, 'next');
      expect(find.byType(CanvasFilePicker), findsNothing);
      expect(find.byType(TextTool), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('keyboard open failure retains current file and picker for retry', (tester) async {
    final store = _FailingLibraryStore();
    final originalId = store.library.currentId;
    store.library = CanvasLibrary(
      files: [
        ...store.library.files,
        CanvasFile(id: 'next', name: 'Next', document: CanvasLibrary.emptyDocument),
      ],
      currentId: originalId,
    );
    await pumpCanvas(tester, store);
    await _open(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    store.fail = true;
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(store.library.currentId, originalId);
    expect(find.byType(CanvasFilePicker), findsOneWidget);
    expect(find.text('Could not save changes. Please try again.'), findsOneWidget);
    store.fail = false;
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(store.library.currentId, 'next');
    expect(find.byType(CanvasFilePicker), findsNothing);
  });

  testWidgets('failed outgoing flush keeps the editor open and retries its latest content', (tester) async {
    final store = _FailingLibraryStore();
    await pumpCanvas(tester, store);
    await tester.tap(find.byKey(const ValueKey('toolbar-text')));
    await tester.tapAt(const Offset(100, 180));
    await tester.pumpAndSettle();
    tester.widget<TextTool>(find.byType(TextTool)).model.insertPastedText('Unsaved');
    store.fail = true;
    await _open(tester);
    expect(find.byType(CanvasFilePicker), findsNothing);
    expect(find.text('Could not open canvas. Your current canvas is still open.'), findsOneWidget);
    expect(tester.widget<TextTool>(find.byType(TextTool)).model.node.markdown, 'Unsaved');
    store.fail = false;
    await _open(tester);
    expect(find.byType(CanvasFilePicker), findsOneWidget);
    expect(store.library.current.document!.elements.whereType<TextElementData>().single.markdown, 'Unsaved');
  });

  testWidgets('switching identical documents still resets tool choice and undo', (tester) async {
    final store = TestLibraryStore();
    store.library = CanvasLibrary(
      currentId: store.library.currentId,
      files: [
        ...store.library.files,
        CanvasFile(id: 'other', name: 'Other', document: CanvasLibrary.emptyDocument),
      ],
    );
    await pumpCanvas(tester, store);
    await tester.tap(find.byKey(const ValueKey('toolbar-draw')));
    await tester.pump();
    expect(tester.widget<ToolbarButton>(find.byKey(const ValueKey('toolbar-draw'))).selected, isTrue);
    await _open(tester);
    await tester.tap(find.byKey(const ValueKey('file-tree-node-other')));
    await tester.pumpAndSettle();
    expect(store.library.currentId, 'other');
    expect(tester.widget<ToolbarButton>(find.byKey(const ValueKey('toolbar-draw'))).selected, isFalse);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(tester.widget<ToolbarButton>(find.byKey(const ValueKey('toolbar-draw'))).selected, isFalse);
  });

  testWidgets('name editing keeps arrows and returns tree focus after Escape', (tester) async {
    final store = TestLibraryStore();
    await pumpCanvas(tester, store);
    await _open(tester);
    await tester.tap(find.byTooltip('New folder'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Notes');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(store.library.files.any((file) => file.name == 'Notes'), isTrue);
    await tester.tap(find.byTooltip('New canvas'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Discard');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(CanvasFilePicker), findsOneWidget);
    expect(FocusManager.instance.primaryFocus?.debugLabel, startsWith('File tree '));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(CanvasFilePicker), findsNothing);
    expect(store.library.files.any((file) => file.name == 'Discard'), isFalse);
  });

  test('bundled demo validates and round-trips every element type and its image', () async {
    final demo = await loadDemoCanvas();
    expect(demo.document.elements.map((element) => element.type).toSet(), {
      'text',
      'code',
      'media',
      'shape',
      'arrow',
      'pen',
    });
    expect(demo.document.elements, hasLength(12));
    expect(
      demo.document.elements.whereType<TextElementData>().every(
        (element) => element.style.fontFamily == defaultFontFamily,
      ),
      isTrue,
    );
    expect(demo.attachments, hasLength(1));
    final exported = await encodeCanvasProject(demo.document, TestAttachmentStore(demo.attachments));
    final imported = await decodeCanvasProject(exported);
    expect(imported.document.toJson(), demo.document.toJson());
    expect(imported.attachments, demo.attachments);
  });

  testWidgets('demo opens at root with unique names and preserves edits and images', (tester) async {
    final demo = await tester.runAsync(loadDemoCanvas);
    final imagePath = demo!.attachments.keys.single;
    final attachments = TestAttachmentStore({imagePath: onePixelPngBytes});
    final original = CanvasDocument(
      background: CanvasBackgroundKind.plain,
      elements: [
        TextElementData(
          id: 'original-text',
          position: const Offset(100, 150),
          width: 280,
          height: null,
          markdown: 'Original ![image]($imagePath)',
          style: const TextNodeStyle(fontFamily: defaultFontFamily, color: Color(0xff201C1A)),
        ),
      ],
    );
    final store = TestLibraryStore(original);
    final current = store.library.current;
    store.library = CanvasLibrary(
      files: [
        const CanvasFile(id: 'work', name: 'Work'),
        CanvasFile(id: current.id, name: 'Original', parentId: 'work', document: current.document),
        const CanvasFile(id: 'demo-folder', name: 'dEmO'),
        CanvasFile(id: 'other', name: 'demo 2', document: CanvasLibrary.emptyDocument),
      ],
      currentId: current.id,
    );
    await pumpCanvas(tester, store, attachmentStore: attachments);
    tester.widget<TextTool>(find.byType(TextTool)).model.insertPastedText(' edited');
    await _open(tester);
    final originalSaved = store.library.current.document!.toJson();
    await tester.tap(find.byTooltip('Demo'));
    await tester.pumpAndSettle();

    expect(find.byType(CanvasFilePicker), findsNothing);
    final first = store.library.current;
    expect(first.name, 'Demo 3');
    expect(first.parentId, isNull);
    expect(first.document!.elements, hasLength(12));
    expect(store.library.file(current.id).document!.toJson(), originalSaved);
    expect(attachments.files[imagePath], onePixelPngBytes);
    final firstPath = canvasAttachmentPaths(first.document!).single;
    expect(firstPath, isNot(imagePath));
    expect(attachments.files[firstPath], demo.attachments[imagePath]);
    expect(tester.widget<CanvasTitle>(find.byType(CanvasTitle)).path, ['Demo 3']);

    tester.widgetList<TextTool>(find.byType(TextTool)).first.model.insertPastedText(' changed');
    await _open(tester);
    final firstSaved = store.library.current.document!.toJson();
    await tester.tap(find.byTooltip('Demo'));
    await tester.pumpAndSettle();
    final second = store.library.current;
    expect(second.name, 'Demo 4');
    expect(second.id, isNot(first.id));
    expect(store.library.file(first.id).document!.toJson(), firstSaved);
    final secondPath = canvasAttachmentPaths(second.document!).single;
    expect(rebaseCanvasDocumentAttachments(second.document!, {secondPath: imagePath}).toJson(), demo.document.toJson());
    expect(secondPath, isNot(firstPath));
    expect(attachments.files[secondPath], demo.attachments[imagePath]);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(store.library.currentId, second.id);
    expect(store.library.current.document!.elements, hasLength(12));
    expect(tester.takeException(), isNull);
  });

  for (final failAttachment in [true, false]) {
    testWidgets('failed demo ${failAttachment ? 'image' : 'library'} save preserves the current canvas', (
      tester,
    ) async {
      final store = _FailingLibraryStore();
      final attachments = _FailingAttachmentStore();
      await pumpCanvas(tester, store, attachmentStore: attachments);
      await _open(tester);
      final original = store.library.toJson();
      attachments.fail = failAttachment;
      store.fail = !failAttachment;
      await tester.tap(find.byTooltip('Demo'));
      await tester.pumpAndSettle();
      expect(store.library.toJson(), original);
      expect(find.byType(CanvasFilePicker), findsOneWidget);
      expect(find.text('Could not save changes. Please try again.'), findsOneWidget);

      attachments.fail = false;
      store.fail = false;
      await tester.tap(find.byTooltip('Demo'));
      await tester.pumpAndSettle();
      expect(store.library.current.name, 'Demo');
      expect(find.byType(CanvasFilePicker), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('demo saves pending folder names and blocks dismissal until its image is saved', (tester) async {
    final store = TestLibraryStore();
    final attachments = _FailingAttachmentStore();
    await pumpCanvas(tester, store, attachmentStore: attachments);
    await _open(tester);
    await tester.tap(find.byTooltip('New folder'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Notes');
    final gate = Completer<void>();
    attachments.gate = gate.future;
    await tester.tap(find.byTooltip('Demo'));
    await tester.pumpAndSettle();
    expect(store.library.files.singleWhere((file) => file.isFolder).name, 'Notes');
    expect(find.byType(CanvasFilePicker), findsOneWidget);
    final popup = tester.widget<FileTreePopup>(find.byType(FileTreePopup));
    popup.onClose();
    popup.onDemo!();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(CanvasFilePicker), findsOneWidget);
    gate.complete();
    await tester.pumpAndSettle();
    expect(store.library.files.where((file) => !file.isFolder), hasLength(2));
    expect(store.library.current.name, 'Demo');
    expect(find.byType(CanvasFilePicker), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('creates nested canvases, renames, switches, and isolates undo', (tester) async {
    final store = TestLibraryStore(
      CanvasDocument(
        background: CanvasBackgroundKind.plain,
        elements: [
          TextElementData(
            id: 'original-text',
            position: const Offset(100, 150),
            width: 280,
            height: null,
            markdown: 'Original contents',
            style: const TextNodeStyle(fontFamily: 'Inter', color: Color(0xff201C1A)),
          ),
        ],
      ),
    );
    await pumpCanvas(tester, store);
    final originalId = store.library.currentId;
    tester.widget<TextTool>(find.byType(TextTool)).model.insertPastedText(' edited');
    await _open(tester);
    expect(store.library.current.document!.elements.whereType<TextElementData>().single.markdown, contains('edited'));

    await tester.tap(find.byTooltip('New folder'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Notes');
    await tester.tapAt(tester.getBottomLeft(find.byType(FileTreePopup)) + const Offset(24, -12));
    await tester.pumpAndSettle();
    final folder = store.library.files.singleWhere((file) => file.isFolder);
    await tester.tap(find.text('Notes'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('New canvas'));
    await _name(tester, 'Brainstorm');
    expect(find.byType(CanvasFilePicker), findsNothing);
    expect(find.byType(TextTool), findsNothing);
    expect(store.library.current.parentId, folder.id);
    expect(tester.widget<CanvasTitle>(find.byType(CanvasTitle)).path, ['Notes', 'Brainstorm']);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(find.byType(TextTool), findsNothing);

    await _open(tester);
    final canvasId = store.library.currentId;
    await tester.tap(find.byKey(ValueKey('file-tree-node-$canvasId')), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Ideas');
    await tester.tap(find.byKey(ValueKey('file-tree-node-$originalId')));
    await tester.pumpAndSettle();
    expect(store.library.file(canvasId).name, 'Ideas');
    expect(store.library.currentId, originalId);
    expect(tester.widget<TextTool>(find.byType(TextTool)).model.node.markdown, contains('edited'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('rejects duplicate names, cancels drafts, and retains failed changes', (tester) async {
    final store = _FailingLibraryStore();
    await pumpCanvas(tester, store);
    await _open(tester);
    await tester.tap(find.byTooltip('New canvas'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Untitled');
    await tester.tapAt(const Offset(790, 590));
    await tester.pumpAndSettle();
    expect(find.text('This name is already in use'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(CanvasFilePicker), findsOneWidget);
    expect(store.library.files, hasLength(1));

    await tester.tap(find.byTooltip('New canvas'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(790, 590));
    await tester.pumpAndSettle();
    expect(find.byType(CanvasFilePicker), findsNothing);
    expect(store.library.files, hasLength(1));

    await _open(tester);
    await tester.tap(find.byTooltip('New folder'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '   ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(store.library.files, hasLength(1));

    store.fail = true;
    await tester.tap(find.byTooltip('New folder'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Unsaved');
    await tester.tapAt(const Offset(790, 590));
    await tester.pumpAndSettle();
    expect(find.text('Could not save changes. Please try again.'), findsOneWidget);
    expect(store.library.files, hasLength(1));
    expect(find.byType(TextField), findsOneWidget);
    store.fail = false;
    await _name(tester, 'Saved');
    expect(store.library.files, hasLength(2));
    await tester.tap(find.text('Saved'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(store.library.files, hasLength(2));
    await tester.tap(find.text('Saved'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(store.library.files, hasLength(1));
    final previousId = store.library.currentId;
    await tester.tap(find.text('Untitled').last, buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.byType(CanvasFilePicker), findsNothing);
    expect(store.library.currentId, isNot(previousId));
    expect(store.library.current.document!.elements, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('click-away creates a canvas and preserves a clicked file selection', (tester) async {
    final store = TestLibraryStore();
    await pumpCanvas(tester, store);
    final originalId = store.library.currentId;

    await _open(tester);
    await tester.tap(find.byTooltip('New canvas'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'First');
    await tester.tapAt(const Offset(790, 590));
    await tester.pumpAndSettle();
    expect(find.byType(CanvasFilePicker), findsNothing);
    expect(store.library.current.name, 'First');
    final firstId = store.library.currentId;

    await _open(tester);
    await tester.tap(find.byTooltip('New canvas'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Second');
    await tester.tap(find.byKey(ValueKey('file-tree-node-$originalId')));
    await tester.pumpAndSettle();
    expect(find.byType(CanvasFilePicker), findsNothing);
    expect(store.library.currentId, originalId);
    expect(store.library.files.map((file) => file.name), containsAll(['First', 'Second']));

    await _open(tester);
    await tester.tap(find.byTooltip('New canvas'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('file-tree-node-$firstId')));
    await tester.pumpAndSettle();
    expect(store.library.current.name, 'First');
    expect(store.library.files, hasLength(3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('drag moves save and failed moves keep the original tree', (tester) async {
    final store = _FailingLibraryStore()
      ..library = CanvasLibrary(
        currentId: 'a',
        files: [
          CanvasFile(id: 'a', name: 'A', document: CanvasLibrary.emptyDocument),
          CanvasFile(id: 'b', name: 'B', document: CanvasLibrary.emptyDocument),
          const CanvasFile(id: 'folder', name: 'Folder'),
        ],
      );
    final controller = LibraryController(store: store, attachments: TestAttachmentStore(), files: TestProjectFiles());
    await controller.load();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: starlessLightThemeData,
        home: Scaffold(
          body: Center(
            child: CanvasFilePicker(
              controller: controller,
            ),
          ),
        ),
      ),
    );

    Future<void> drag(String sourceId, String targetId, {bool inside = false}) async {
      final target = find.byKey(ValueKey('file-tree-node-$targetId'));
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(ValueKey('file-tree-node-$sourceId'))),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump();
      await gesture.moveTo(inside ? tester.getCenter(target) : tester.getTopLeft(target) + const Offset(30, 3));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
    }

    await drag('b', 'a');
    expect(store.library.files.where((file) => file.parentId == null).map((file) => file.id), ['b', 'a', 'folder']);
    await drag('b', 'folder', inside: true);
    expect(store.library.file('b').parentId, 'folder');
    expect(find.byKey(const ValueKey('file-tree-node-b')), findsOneWidget);
    await drag('b', 'a');
    expect(store.library.file('b').parentId, isNull);
    expect(store.library.files.where((file) => file.parentId == null).map((file) => file.id), ['b', 'a', 'folder']);
    await drag('b', 'folder', inside: true);

    store.fail = true;
    await drag('a', 'folder', inside: true);
    expect(store.library.file('a').parentId, isNull);
    expect(find.text('Could not save changes. Please try again.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

// ---------- Helpers ----------

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.byType(CanvasTitle));
  await tester.pumpAndSettle();
}

Future<void> _name(WidgetTester tester, String value) async {
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), value);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();
}

class _FailingLibraryStore extends TestLibraryStore {
  bool fail = false;

  @override
  Future<void> save(CanvasLibrary next) async {
    if (fail) throw StateError('Storage full');
    await super.save(next);
  }
}

class _FailingAttachmentStore extends TestAttachmentStore {
  bool fail = false;
  Future<void>? gate;

  @override
  Future<void> write(String path, Uint8List bytes) async {
    if (fail) throw StateError('Storage full');
    if (gate case final gate?) await gate;
    await super.write(path, bytes);
  }
}
