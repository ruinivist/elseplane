// Previews the canvas file-tree popup with temporary interactive data.
// Used by Flutter widget previews for isolated tree layout and disclosure.

import 'package:elseplane/library/canvas_library.dart';
import 'package:elseplane/library/widgets/file_tree_popup.dart';
import 'package:elseplane/theme/theme.dart';
import 'package:elseplane/ui/previews/theme_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

// ---------- Preview ----------

@Preview(
  name: 'FileTreePopup',
  size: Size(480, 520),
  theme: previewTheme,
  brightness: Brightness.light,
)
Widget fileTreePopupPreview() => const _FileTreePopupPreview();

class _FileTreePopupPreview extends StatefulWidget {
  const _FileTreePopupPreview();

  @override
  State<_FileTreePopupPreview> createState() => _FileTreePopupPreviewState();
}

class _FileTreePopupPreviewState extends State<_FileTreePopupPreview> {
  CanvasLibrary _library = CanvasLibrary(
    currentId: 'brainstorm',
    files: [
      const CanvasFile(id: 'notes', name: 'Notes'),
      const CanvasFile(id: 'projects', name: 'Projects', parentId: 'notes'),
      CanvasFile(
        id: 'brainstorm',
        name: 'Brainstorm',
        parentId: 'projects',
        document: CanvasLibrary.emptyDocument,
      ),
      CanvasFile(id: 'design', name: 'Design', parentId: 'projects', document: CanvasLibrary.emptyDocument),
      CanvasFile(id: 'research', name: 'Research', parentId: 'projects', document: CanvasLibrary.emptyDocument),
      CanvasFile(id: 'ideas', name: 'Ideas', parentId: 'projects', document: CanvasLibrary.emptyDocument),
      const CanvasFile(id: 'archive', name: 'Archive'),
      const CanvasFile(id: 'personal', name: 'Personal'),
      const CanvasFile(id: 'templates', name: 'Templates'),
    ],
  );

  String? _selectedId = 'brainstorm';
  final _expandedIds = {'notes', 'projects'};

  List<FileTreeNode> _nodes(String? parentId) => [
    for (final file in _library.files.where((file) => file.parentId == parentId))
      FileTreeNode(
        id: file.id,
        name: file.name,
        type: file.isFolder ? FileTreeNodeType.folder : FileTreeNodeType.file,
        children: file.isFolder ? _nodes(file.id) : const [],
      ),
  ];

  CanvasLibrary _moved(String sourceId, String targetId, FileTreeDropPosition position) {
    final target = _library.file(targetId);
    final parentId = position == FileTreeDropPosition.inside ? targetId : target.parentId;
    String? beforeId;
    if (position == FileTreeDropPosition.before) beforeId = targetId;
    if (position == FileTreeDropPosition.after) {
      final siblings = _library.files.where((file) => file.parentId == parentId && file.id != sourceId).toList();
      final index = siblings.indexWhere((file) => file.id == targetId);
      if (index + 1 < siblings.length) beforeId = siblings[index + 1].id;
    }
    return _library.move(sourceId, parentId: parentId, beforeId: beforeId);
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: BTheme.of(context).colors.canvasBackground,
      child: Center(
        child: FileTreePopup(
          nodes: _nodes(null),
          selectedId: _selectedId,
          expandedIds: _expandedIds,
          onSelect: (node) => setState(() => _selectedId = node.id),
          onToggle: _toggle,
          canMove: (sourceId, targetId, position) {
            try {
              return !identical(_moved(sourceId, targetId, position), _library);
            } on FormatException {
              return false;
            }
          },
          onMove: (sourceId, targetId, position) {
            try {
              setState(() {
                _library = _moved(sourceId, targetId, position);
                if (position == FileTreeDropPosition.inside) _expandedIds.add(targetId);
              });
            } on FormatException {
              // The preview ignores invalid drops.
            }
          },
          onNewFolder: () {},
          onNewFile: () {},
          onClose: () {},
          actionsFor: (_) => [],
        ),
      ),
    );
  }

  void _toggle(FileTreeNode folder) {
    setState(() {
      if (!_expandedIds.remove(folder.id)) _expandedIds.add(folder.id);
    });
  }
}
