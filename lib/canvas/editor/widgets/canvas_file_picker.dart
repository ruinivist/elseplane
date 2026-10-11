// Coordinates file-tree navigation and inline creation and renaming.
// Used by the canvas title to manage the browser's saved library.

import 'dart:async';

import 'package:elseplane/canvas/debug/demo_canvas.dart';
import 'package:elseplane/canvas/editor/widgets/file_tree_popup.dart';
import 'package:elseplane/canvas/persistence/attachments/store.dart';
import 'package:elseplane/canvas/persistence/canvas_library.dart';
import 'package:elseplane/canvas/persistence/canvas_project.dart';
import 'package:elseplane/theme/theme.dart';
import 'package:elseplane/ui/common/context_menu.dart';
import 'package:elseplane/ui/common/surface_dialog.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:uuid/uuid.dart';

// ---------- Picker ----------

class CanvasFilePicker extends StatefulWidget {
  const CanvasFilePicker({required this.library, required this.onSave, required this.attachmentStore, super.key});

  final CanvasLibrary library;
  final Future<void> Function(CanvasLibrary library) onSave;
  final AttachmentStore attachmentStore;

  @override
  State<CanvasFilePicker> createState() => _CanvasFilePickerState();
}

class _CanvasFilePickerState extends State<CanvasFilePicker> {
  // ---------- State ----------

  late CanvasLibrary _library = widget.library;
  late final Set<String> _expanded = _library.path(_library.currentId).map((file) => file.id).toSet();
  final _name = TextEditingController();
  final _nameFocus = FocusNode();
  CanvasFile? _editing;
  String? _error;
  var _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  // ---------- Actions ----------

  void _edit(CanvasFile file) {
    setState(() {
      _editing = file;
      _error = null;
      _name.text = file.name;
      _name.selection = TextSelection(baseOffset: 0, extentOffset: file.name.length);
      if (file.parentId != null) _expanded.add(file.parentId!);
    });
    _nameFocus.requestFocus();
  }

  void _create({required bool folder, String? parentId}) => _edit(
    CanvasFile(
      id: const Uuid().v4(),
      name: '',
      parentId: parentId,
      document: folder ? null : CanvasLibrary.emptyDocument,
    ),
  );

  void _cancelEdit() => setState(() {
    _editing = null;
    _error = null;
  });

  Future<bool> _saveName({String? openId, bool close = false}) async {
    final editing = _editing;
    if (editing == null || _busy) return false;
    if (_name.text.trim().isEmpty) {
      _cancelEdit();
      if (openId != null) {
        await _open(openId);
      } else if (close) {
        Navigator.of(context).pop();
      }
      return true;
    }
    final error = _library.nameError(_name.text, editing.parentId, exceptId: editing.id);
    if (error != null) {
      setState(() => _error = error);
      _nameFocus.requestFocus();
      return false;
    }
    final file = editing.copyWith(name: _name.text.trim());
    final exists = _library.files.any((entry) => entry.id == file.id);
    var next = exists
        ? _library.replace(file)
        : CanvasLibrary(files: [..._library.files, file], currentId: _library.currentId);
    final selectedId = openId ?? (!exists && !file.isFolder ? file.id : null);
    if (selectedId != null) next = next.select(selectedId);
    if (!await _save(() => next) || !mounted) return false;
    setState(() => _editing = null);
    if (selectedId != null || close) Navigator.of(context).pop(selectedId);
    return true;
  }

  Future<void> _open(String id) async {
    if (_editing != null) {
      await _saveName(openId: id);
      return;
    }
    if (!await _save(() => _library.select(id)) || !mounted) return;
    Navigator.of(context).pop(id);
  }

  Future<bool> _commitPendingEdit() async {
    final editing = _editing;
    if (editing == null) return true;
    final empty = _name.text.trim().isEmpty;
    final opensCanvas = !editing.isFolder && !_library.files.any((file) => file.id == editing.id);
    return await _saveName() && (empty || !opensCanvas) && mounted;
  }

  Future<void> _toggle(String id) async {
    if (!await _commitPendingEdit()) return;
    setState(() {
      if (!_expanded.remove(id)) _expanded.add(id);
    });
  }

  Future<void> _createAfterEdit({required bool folder, String? parentId}) async {
    if (await _commitPendingEdit()) _create(folder: folder, parentId: parentId);
  }

  Future<void> _createDemo() async {
    if (!kDebugMode || _busy || !await _commitPendingEdit() || !mounted) return;
    final saved = await _save(() async {
      final project = rebaseCanvasProjectAttachments(
        await loadDemoCanvas(),
        _library.files.where((file) => !file.isFolder).expand((file) => canvasAttachmentPaths(file.document!)).toSet(),
      );
      var name = 'Demo';
      for (var suffix = 2; _library.nameError(name, null) != null; suffix++) {
        name = 'Demo $suffix';
      }
      final file = CanvasFile(id: const Uuid().v4(), name: name, document: project.document);
      for (final entry in project.attachments.entries) {
        await widget.attachmentStore.write(entry.key, entry.value);
      }
      return CanvasLibrary(files: [..._library.files, file], currentId: file.id);
    });
    if (saved && mounted) Navigator.of(context).pop(_library.currentId);
  }

  void _close() {
    if (_editing != null) {
      unawaited(_saveName(close: true));
    } else if (!_busy) {
      Navigator.of(context).pop();
    }
  }

  (String?, String?) _destination(String sourceId, String targetId, FileTreeDropPosition position) {
    final target = _library.file(targetId);
    if (position == FileTreeDropPosition.inside) return (target.id, null);
    if (position == FileTreeDropPosition.before) return (target.parentId, target.id);
    final siblings = _library.files.where((file) => file.parentId == target.parentId && file.id != sourceId).toList();
    final index = siblings.indexWhere((file) => file.id == targetId);
    return (target.parentId, index + 1 < siblings.length ? siblings[index + 1].id : null);
  }

  CanvasLibrary _movedLibrary(String sourceId, String targetId, FileTreeDropPosition position) {
    final (parentId, beforeId) = _destination(sourceId, targetId, position);
    return _library.move(sourceId, parentId: parentId, beforeId: beforeId);
  }

  bool _canMove(String sourceId, String targetId, FileTreeDropPosition position) {
    try {
      return !identical(_movedLibrary(sourceId, targetId, position), _library);
    } on FormatException {
      return false;
    }
  }

  Future<void> _move(String sourceId, String targetId, FileTreeDropPosition position) async {
    if (_busy || _editing != null) return;
    CanvasLibrary next;
    try {
      next = _movedLibrary(sourceId, targetId, position);
    } on FormatException catch (error) {
      setState(() => _error = error.message);
      return;
    }
    if (identical(next, _library) || !await _save(() => next) || !mounted) return;
    if (position == FileTreeDropPosition.inside) setState(() => _expanded.add(targetId));
  }

  Future<bool> _save(FutureOr<CanvasLibrary> Function() buildLibrary) async {
    if (_busy) return false;
    setState(() => _busy = true);
    try {
      final next = await buildLibrary();
      await widget.onSave(next);
      if (!mounted) return false;
      setState(() {
        _library = next;
        _error = null;
      });
      return true;
    } on Object {
      if (mounted) setState(() => _error = 'Could not save changes. Please try again.');
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(CanvasFile file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => SurfaceConfirmationDialog(
        title: Text('Delete “${file.name}”?'),
        content: Text(file.isFolder ? 'This deletes the folder and all its canvases.' : 'This canvas will be deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final remaining = _library.files
        .where((entry) => !_library.path(entry.id).any((part) => part.id == file.id))
        .toList();
    if (!remaining.any((entry) => !entry.isFolder)) {
      var name = 'Untitled';
      for (
        var suffix = 2;
        remaining.any((entry) => entry.parentId == null && entry.name.toLowerCase() == name.toLowerCase());
        suffix++
      ) {
        name = 'Untitled $suffix';
      }
      remaining.add(CanvasLibrary.initial().current.copyWith(name: name));
    }
    final currentId = remaining.any((entry) => entry.id == _library.currentId)
        ? _library.currentId
        : remaining.firstWhere((entry) => !entry.isFolder).id;
    final changedCurrent = currentId != _library.currentId;
    if (!await _save(() => CanvasLibrary(files: remaining, currentId: currentId)) || !mounted) return;
    setState(() {
      _editing = null;
    });
    if (changedCurrent) Navigator.of(context).pop(currentId);
  }

  // ---------- Rendering ----------

  List<FileTreeNode> _nodes(String? parentId) {
    final files = [..._library.files];
    if (_editing != null && !files.any((file) => file.id == _editing!.id)) files.add(_editing!);
    return [
      for (final file in files.where((file) => file.parentId == parentId))
        FileTreeNode(
          id: file.id,
          name: file.name,
          type: file.isFolder ? FileTreeNodeType.folder : FileTreeNodeType.file,
          children: file.isFolder ? _nodes(file.id) : const [],
        ),
    ];
  }

  @override
  Widget build(BuildContext context) => PopScope<String>(
    canPop: !_busy && _editing == null,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && _editing != null && !_busy) unawaited(_saveName(close: true));
    },
    child: Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(16),
      child: AbsorbPointer(
        absorbing: _busy,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () {
                  if (_editing != null) unawaited(_saveName());
                },
                child: FileTreePopup(
                  nodes: _nodes(null),
                  selectedId: _library.currentId,
                  expandedIds: _expanded,
                  editingId: _editing?.id,
                  editor: CallbackShortcuts(
                    bindings: {
                      const SingleActivator(LogicalKeyboardKey.escape): _cancelEdit,
                    },
                    child: TextField(
                      controller: _name,
                      focusNode: _nameFocus,
                      autofocus: true,
                      style: BTheme.of(context).typo.body,
                      decoration: const InputDecoration(
                        hintText: 'Name',
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 5),
                        border: InputBorder.none,
                      ),
                      onSubmitted: (_) => _saveName(),
                    ),
                  ),
                  onSelect: (node) => _open(node.id),
                  onToggle: (node) => _toggle(node.id),
                  canMove: _canMove,
                  onMove: _move,
                  onNewFile: () => _createAfterEdit(folder: false),
                  onNewFolder: () => _createAfterEdit(folder: true),
                  onDemo: kDebugMode ? _createDemo : null,
                  onClose: _close,
                  actionsFor: (node) {
                    final file = _library.files.where((file) => file.id == node.id).firstOrNull;
                    if (file == null) return [];
                    return [
                      if (file.isFolder) ...[
                        ContextMenuAction(
                          label: 'New canvas',
                          icon: LucideIcons.filePlus,
                          onPressed: () => _createAfterEdit(folder: false, parentId: file.id),
                        ),
                        ContextMenuAction(
                          label: 'New folder',
                          icon: LucideIcons.folderPlus,
                          onPressed: () => _createAfterEdit(folder: true, parentId: file.id),
                        ),
                      ],
                      ContextMenuAction(
                        label: 'Rename',
                        icon: LucideIcons.pencil,
                        onPressed: () async {
                          if (await _commitPendingEdit()) _edit(_library.file(file.id));
                        },
                      ),
                      ContextMenuAction(
                        label: 'Delete',
                        icon: LucideIcons.trash2,
                        destructive: true,
                        onPressed: () async {
                          if (await _commitPendingEdit()) await _delete(_library.file(file.id));
                        },
                      ),
                    ];
                  },
                ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(_error!, style: BTheme.of(context).typo.body, semanticsLabel: _error),
              ),
          ],
        ),
      ),
    ),
  );
}
