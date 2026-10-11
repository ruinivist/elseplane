// Verifies controlled disclosure and action routing in the file-tree popup.
// Exercises the canvas popup independently of document persistence.

import 'package:elseplane/canvas/editor/widgets/file_tree_popup.dart';
import 'package:elseplane/theme/starless.dart';
import 'package:elseplane/ui/common/context_menu.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
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
