// Verifies controlled disclosure and action routing in the file-tree popup.
// Exercises the canvas popup independently of document persistence.

import 'package:elseplane/library/widgets/file_tree_popup.dart';
import 'package:elseplane/theme/starless.dart';
import 'package:elseplane/ui/common/context_menu.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------- Tests ----------

void main() {
  testWidgets('routes tree and popup actions', (tester) async {
    const nodes = [
      FileTreeNode(
        id: 'projects',
        name: 'Projects',
        type: FileTreeNodeType.folder,
        children: [
          FileTreeNode(id: 'brainstorm', name: 'Brainstorm', type: FileTreeNodeType.file),
        ],
      ),
    ];
    final expandedIds = {'projects'};
    String? selectedId;
    String? contextId;
    var newFolderCalls = 0;
    var closeCalls = 0;
    var demoCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: starlessLightThemeData,
        home: Scaffold(
          body: Center(
            child: StatefulBuilder(
              builder: (context, setState) => FileTreePopup(
                nodes: nodes,
                selectedId: selectedId,
                expandedIds: expandedIds,
                onSelect: (node) => setState(() => selectedId = node.id),
                onToggle: (folder) => setState(() {
                  if (!expandedIds.remove(folder.id)) expandedIds.add(folder.id);
                }),
                canMove: (_, _, _) => true,
                onMove: (_, _, _) {},
                onNewFolder: () => newFolderCalls++,
                onNewFile: () {},
                onClose: () => closeCalls++,
                onDemo: () => demoCalls++,
                actionsFor: (node) => [
                  ContextMenuAction(label: 'Rename', icon: Icons.edit, onPressed: () => contextId = node.id),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Brainstorm'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('file-tree-node-projects')));
    await tester.pump();
    expect(find.text('Brainstorm'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('file-tree-node-projects')));
    await tester.pump();
    await tester.tap(find.text('Brainstorm'));
    await tester.pump();
    expect(selectedId, 'brainstorm');

    await tester.tap(
      find.byKey(const ValueKey('file-tree-node-brainstorm')),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    expect(contextId, 'brainstorm');

    await tester.tap(find.byKey(const ValueKey('file-tree-new-folder')));
    await tester.tap(find.byTooltip('Demo'));
    await tester.tap(find.byKey(const ValueKey('file-tree-close')));
    expect(newFolderCalls, 1);
    expect(closeCalls, 1);
    expect(demoCalls, 1);
  });

  testWidgets('keyboard follows visible rows and opens only on Enter', (tester) async {
    const nodes = [
      FileTreeNode(id: 'first', name: 'First', type: FileTreeNodeType.file),
      FileTreeNode(
        id: 'folder',
        name: 'Folder',
        type: FileTreeNodeType.folder,
        children: [
          FileTreeNode(id: 'child', name: 'Child', type: FileTreeNodeType.file),
        ],
      ),
      FileTreeNode(id: 'last', name: 'Last', type: FileTreeNodeType.file),
    ];
    final expanded = <String>{};
    final opened = <String>[];
    await _pumpTree(tester, nodes: nodes, expanded: expanded, onSelect: (node) => opened.add(node.id));
    expect(_rowFocus(tester, 'first').hasFocus, isTrue);
    await _key(tester, LogicalKeyboardKey.arrowUp);
    expect(_rowFocus(tester, 'first').hasFocus, isTrue);
    await _key(tester, LogicalKeyboardKey.arrowDown);
    expect(_rowFocus(tester, 'folder').hasFocus, isTrue);
    await _key(tester, LogicalKeyboardKey.arrowDown);
    expect(_rowFocus(tester, 'last').hasFocus, isTrue);
    await _key(tester, LogicalKeyboardKey.arrowDown);
    expect(_rowFocus(tester, 'last').hasFocus, isTrue);
    await _key(tester, LogicalKeyboardKey.arrowUp);
    await _key(tester, LogicalKeyboardKey.arrowRight);
    expect(expanded, contains('folder'));
    await _key(tester, LogicalKeyboardKey.arrowRight);
    expect(_rowFocus(tester, 'child').hasFocus, isTrue);
    await _key(tester, LogicalKeyboardKey.arrowLeft);
    expect(_rowFocus(tester, 'folder').hasFocus, isTrue);
    await _key(tester, LogicalKeyboardKey.arrowLeft);
    expect(expanded, isEmpty);
    await _key(tester, LogicalKeyboardKey.enter);
    expect(expanded, contains('folder'));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(_rowFocus(tester, 'child').hasFocus, isTrue);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(_rowFocus(tester, 'last').hasFocus, isTrue);
    expect(opened, isEmpty);
    await _key(tester, LogicalKeyboardKey.numpadEnter);
    expect(opened, ['last']);
  });

  testWidgets('initial and navigated focus scroll into view and Tab reaches header', (tester) async {
    final nodes = List.generate(30, (i) => FileTreeNode(id: '$i', name: 'Canvas $i', type: FileTreeNodeType.file));
    await _pumpTree(tester, nodes: nodes, selectedId: '29');
    expect(_rowFocus(tester, '29').hasFocus, isTrue);
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scrollable.position.pixels, greaterThan(0));
    for (var i = 0; i < 29; i++) {
      await _key(tester, LogicalKeyboardKey.arrowUp);
    }
    expect(_rowFocus(tester, '0').hasFocus, isTrue);
    expect(scrollable.position.pixels, 0);
    _rowFocus(tester, '29').requestFocus();
    await tester.pumpAndSettle();
    for (var i = 0; i < nodes.length * 2 + 6; i++) {
      await _key(tester, LogicalKeyboardKey.tab);
      if (FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<IconButton>() != null) break;
    }
    expect(_rowFocus(tester, '29').hasFocus, isFalse);
    expect(FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<IconButton>(), isNotNull);
  });

  testWidgets('focus preserves visible rows and reveals rows beyond either edge', (tester) async {
    final nodes = List.generate(30, (i) => FileTreeNode(id: '$i', name: 'Canvas $i', type: FileTreeNodeType.file));
    await _pumpTree(tester, nodes: nodes, selectedId: '0');
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    final viewport = tester.getRect(find.byType(SingleChildScrollView));
    Rect rowRect(int index) => tester.getRect(find.byKey(ValueKey('file-tree-node-$index')));
    void expectVisible(int index) {
      final row = rowRect(index);
      expect(row.top, greaterThanOrEqualTo(viewport.top - 0.01));
      expect(row.bottom, lessThanOrEqualTo(viewport.bottom + 0.01));
    }

    final initialOffset = scrollable.position.pixels;
    await _key(tester, LogicalKeyboardKey.arrowDown);
    expect(_rowFocus(tester, '1').hasFocus, isTrue);
    expectVisible(1);
    expect(scrollable.position.pixels, initialOffset);
    for (var i = 2; i < nodes.length; i++) {
      final before = scrollable.position.pixels;
      final wasVisible = rowRect(i).bottom <= viewport.bottom;
      await _key(tester, LogicalKeyboardKey.arrowDown);
      expect(_rowFocus(tester, '$i').hasFocus, isTrue);
      expectVisible(i);
      expect(scrollable.position.pixels, wasVisible ? before : greaterThan(before));
    }
    for (var i = nodes.length - 2; i >= 0; i--) {
      final before = scrollable.position.pixels;
      final wasVisible = rowRect(i).top >= viewport.top;
      await _key(tester, LogicalKeyboardKey.arrowUp);
      expect(_rowFocus(tester, '$i').hasFocus, isTrue);
      expectVisible(i);
      expect(scrollable.position.pixels, wasVisible ? before : lessThan(before));
    }
  });

  testWidgets('busy tree blocks navigation and activation, menus own their keys', (tester) async {
    const nodes = [
      FileTreeNode(id: 'first', name: 'First', type: FileTreeNodeType.file),
      FileTreeNode(id: 'last', name: 'Last', type: FileTreeNodeType.file),
    ];
    var opened = 0;
    await _pumpTree(tester, nodes: nodes, onSelect: (_) => opened++);
    await _pumpTree(tester, nodes: nodes, enabled: false, onSelect: (_) => opened++);
    await _key(tester, LogicalKeyboardKey.arrowDown);
    await _key(tester, LogicalKeyboardKey.enter);
    expect(_rowFocus(tester, 'first').hasFocus, isTrue);
    expect(opened, 0);
    await _pumpTree(tester, nodes: nodes, onSelect: (_) => opened++);
    await tester.tap(find.text('First'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await _key(tester, LogicalKeyboardKey.arrowDown);
    await _key(tester, LogicalKeyboardKey.enter);
    expect(opened, 0);
    expect(find.text('Rename'), findsNothing);
  });

  testWidgets('focus recovers after collapse and removal', (tester) async {
    const child = FileTreeNode(id: 'child', name: 'Child', type: FileTreeNodeType.file);
    const folder = FileTreeNode(id: 'folder', name: 'Folder', type: FileTreeNodeType.folder, children: [child]);
    const last = FileTreeNode(id: 'last', name: 'Last', type: FileTreeNodeType.file);
    final expanded = {'folder'};
    await _pumpTree(tester, nodes: [folder, last], expanded: expanded, selectedId: 'child');
    expect(_rowFocus(tester, 'child').hasFocus, isTrue);
    expanded.clear();
    await _pumpTree(tester, nodes: [folder, last], expanded: expanded);
    expect(_rowFocus(tester, 'folder').hasFocus, isTrue);
    await _key(tester, LogicalKeyboardKey.arrowDown);
    await _pumpTree(tester, nodes: [folder], expanded: expanded);
    expect(_rowFocus(tester, 'folder').hasFocus, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('routes before, folder, and after drops without selecting', (tester) async {
    const nodes = [
      FileTreeNode(id: 'first', name: 'First', type: FileTreeNodeType.file),
      FileTreeNode(id: 'folder', name: 'Folder', type: FileTreeNodeType.folder),
      FileTreeNode(id: 'last', name: 'Last', type: FileTreeNodeType.file),
    ];
    final moves = <(String, String, FileTreeDropPosition)>[];
    var selections = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: starlessLightThemeData,
        home: Scaffold(
          body: Center(
            child: FileTreePopup(
              nodes: nodes,
              selectedId: null,
              expandedIds: const {},
              onSelect: (_) => selections++,
              onToggle: (_) {},
              canMove: (_, _, _) => true,
              onMove: (source, target, position) => moves.add((source, target, position)),
              onNewFolder: () {},
              onNewFile: () {},
              onClose: () {},
              actionsFor: (_) => [],
            ),
          ),
        ),
      ),
    );

    expect(find.byTooltip('Demo'), findsNothing);

    Future<void> dragTo(Offset destination) async {
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('file-tree-node-first'))),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump();
      await gesture.moveTo(destination);
      await tester.pump();
      await gesture.up();
      await tester.pump();
    }

    final folder = find.byKey(const ValueKey('file-tree-node-folder'));
    await dragTo(tester.getTopLeft(folder) + const Offset(30, 3));
    await dragTo(tester.getCenter(folder));
    await dragTo(tester.getBottomLeft(folder) + const Offset(30, -3));
    expect(moves, [
      ('first', 'folder', FileTreeDropPosition.before),
      ('first', 'folder', FileTreeDropPosition.inside),
      ('first', 'folder', FileTreeDropPosition.after),
    ]);
    expect(selections, 0);
  });
}

// ---------- Helpers ----------

FocusNode _rowFocus(WidgetTester tester, String id) =>
    tester.widget<InkWell>(find.byKey(ValueKey('file-tree-node-$id'))).focusNode!;

Future<void> _key(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
}

Future<void> _pumpTree(
  WidgetTester tester, {
  required List<FileTreeNode> nodes,
  Set<String>? expanded,
  String? selectedId = 'first',
  bool enabled = true,
  ValueChanged<FileTreeNode>? onSelect,
}) async {
  final expandedIds = expanded ?? <String>{};
  await tester.pumpWidget(
    MaterialApp(
      theme: starlessLightThemeData,
      home: Scaffold(
        body: Center(
          child: StatefulBuilder(
            builder: (context, setState) => FileTreePopup(
              nodes: nodes,
              selectedId: selectedId,
              expandedIds: expandedIds,
              enabled: enabled,
              onSelect: onSelect ?? (_) {},
              onToggle: (node) => setState(() {
                if (!expandedIds.remove(node.id)) expandedIds.add(node.id);
              }),
              canMove: (_, _, _) => false,
              onMove: (_, _, _) {},
              onNewFolder: () {},
              onNewFile: () {},
              onClose: () {},
              actionsFor: (_) => [ContextMenuAction(label: 'Rename', icon: Icons.edit, onPressed: () {})],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
