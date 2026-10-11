// Provides the canvas file-tree popup and its controlled node model.
// Used by the canvas file picker and isolated previews.

import 'package:elseplane/theme/theme.dart';
import 'package:elseplane/ui/common/context_menu.dart';
import 'package:elseplane/ui/common/surface.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scroll_animator/scroll_animator.dart';

// ---------- Models ----------

enum FileTreeNodeType { folder, file }

enum FileTreeDropPosition { before, inside, after }

@immutable
class FileTreeNode {
  const FileTreeNode({
    required this.id,
    required this.name,
    required this.type,
    this.children = const [],
  });

  final String id;
  final String name;
  final FileTreeNodeType type;
  final List<FileTreeNode> children;
}

// ---------- Popup ----------

class FileTreePopup extends StatelessWidget {
  const FileTreePopup({
    required this.nodes,
    required this.selectedId,
    required this.expandedIds,
    required this.onSelect,
    required this.onToggle,
    required this.canMove,
    required this.onMove,
    required this.onNewFolder,
    required this.onNewFile,
    required this.onClose,
    required this.actionsFor,
    this.onDemo,
    this.editingId,
    this.editor,
    super.key,
  });

  final List<FileTreeNode> nodes;
  final String? selectedId;
  final Set<String> expandedIds;
  final ValueChanged<FileTreeNode> onSelect;
  final ValueChanged<FileTreeNode> onToggle;
  final bool Function(String sourceId, String targetId, FileTreeDropPosition position) canMove;
  final void Function(String sourceId, String targetId, FileTreeDropPosition position) onMove;
  final VoidCallback onNewFolder;
  final VoidCallback onNewFile;
  final VoidCallback onClose;
  final VoidCallback? onDemo;
  final List<ContextMenuAction> Function(FileTreeNode node) actionsFor;
  final String? editingId;
  final Widget? editor;

  static const _width = 380.0;
  static const _minHeight = 360.0;
  static const _maxHeight = 420.0;
  static const _rowHeight = 30.0;
  static const _indent = 18.0;
  static const _iconSize = 16.0;
  static const _controlSize = 28.0;

  // ---------- Rendering ----------

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _width,
      child: Surface(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: _minHeight, maxHeight: _maxHeight),
          child: Stack(
            children: [
              AnimatedPrimaryScrollController(
                child: SingleChildScrollView(
                  primary: true,
                  padding: const EdgeInsets.fromLTRB(8, 38, 8, 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [for (final node in nodes) _node(context, node, 0)],
                  ),
                ),
              ),
              Positioned(
                top: 6,
                right: 6,
                child: Row(
                  children: [
                    _control(
                      context,
                      key: const ValueKey('file-tree-new-file'),
                      icon: LucideIcons.filePlus,
                      tooltip: 'New canvas',
                      onPressed: onNewFile,
                    ),
                    const SizedBox(width: 2),
                    _control(
                      context,
                      key: const ValueKey('file-tree-new-folder'),
                      icon: LucideIcons.folderPlus,
                      tooltip: 'New folder',
                      onPressed: onNewFolder,
                    ),
                    if (onDemo case final onDemo?) ...[
                      const SizedBox(width: 2),
                      _control(
                        context,
                        key: const ValueKey('file-tree-demo'),
                        icon: LucideIcons.flaskConical,
                        tooltip: 'Demo',
                        onPressed: onDemo,
                      ),
                    ],
                    const SizedBox(width: 2),
                    _control(
                      context,
                      key: const ValueKey('file-tree-close'),
                      icon: LucideIcons.x,
                      tooltip: 'Close',
                      onPressed: onClose,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _node(BuildContext context, FileTreeNode node, int depth) {
    final theme = BTheme.of(context);
    final isFolder = node.type == FileTreeNodeType.folder;
    final isExpanded = isFolder && expandedIds.contains(node.id);
    final isSelected = !isFolder && selectedId == node.id;
    final radius = theme.geo.radiusSmall;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.only(left: depth * _indent, bottom: 2),
          child: _DropRow(
            node: node,
            enabled: editingId == null,
            canMove: canMove,
            onMove: onMove,
            child: Semantics(
              button: true,
              selected: isSelected,
              expanded: isFolder ? isExpanded : null,
              child: ContextMenu(
                groups: [actionsFor(node)],
                child: InkWell(
                  key: ValueKey('file-tree-node-${node.id}'),
                  borderRadius: radius,
                  mouseCursor: SystemMouseCursors.click,
                  onTap: () => isFolder ? onToggle(node) : onSelect(node),
                  overlayColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.pressed)) return theme.colors.surfacePressed;
                    if (states.contains(WidgetState.hovered) || states.contains(WidgetState.focused)) {
                      return theme.colors.surfaceHover;
                    }
                    return Colors.transparent;
                  }),
                  child: Container(
                    height: _rowHeight,
                    padding: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? theme.colors.accentSoft
                          : editingId == node.id
                          ? theme.colors.surfaceSubtle
                          : Colors.transparent,
                      borderRadius: radius,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 3,
                          height: _rowHeight,
                          decoration: BoxDecoration(
                            color: isSelected ? theme.colors.accent : null,
                            borderRadius: radius,
                          ),
                        ),
                        const SizedBox(width: 3),
                        SizedBox(
                          width: _iconSize,
                          child: isFolder
                              ? Icon(
                                  isExpanded ? LucideIcons.chevronDown : LucideIcons.chevronRight,
                                  size: 14,
                                  color: theme.colors.textMuted,
                                )
                              : null,
                        ),
                        const SizedBox(width: 5),
                        Icon(
                          isFolder ? LucideIcons.folder : LucideIcons.file,
                          size: _iconSize,
                          color: theme.colors.textSecondary,
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: editingId == node.id
                              ? editor!
                              : Text(
                                  node.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.typo.body,
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (isExpanded)
          for (final child in node.children) _node(context, child, depth + 1),
      ],
    );
  }

  Widget _control(
    BuildContext context, {
    required Key key,
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    final theme = BTheme.of(context);
    return IconButton(
      key: key,
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon),
      iconSize: _iconSize,
      style: ButtonStyle(
        foregroundColor: WidgetStatePropertyAll(theme.colors.textSecondary),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.pressed)) return theme.colors.surfacePressed;
          if (states.contains(WidgetState.hovered) || states.contains(WidgetState.focused)) {
            return theme.colors.surfaceHover;
          }
          return Colors.transparent;
        }),
        fixedSize: const WidgetStatePropertyAll(Size.square(_controlSize)),
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: theme.geo.radiusSmall)),
      ),
    );
  }
}

class _DropRow extends StatefulWidget {
  const _DropRow({
    required this.node,
    required this.enabled,
    required this.canMove,
    required this.onMove,
    required this.child,
  });

  final FileTreeNode node;
  final bool enabled;
  final bool Function(String, String, FileTreeDropPosition) canMove;
  final void Function(String, String, FileTreeDropPosition) onMove;
  final Widget child;

  @override
  State<_DropRow> createState() => _DropRowState();
}

class _DropRowState extends State<_DropRow> {
  FileTreeDropPosition? _hover;

  FileTreeDropPosition _position(Offset globalPosition) {
    final box = context.findRenderObject()! as RenderBox;
    final y = box.globalToLocal(globalPosition).dy;
    if (y < 8) return FileTreeDropPosition.before;
    if (y > 22) return FileTreeDropPosition.after;
    return widget.node.type == FileTreeNodeType.folder
        ? FileTreeDropPosition.inside
        : y < 15
        ? FileTreeDropPosition.before
        : FileTreeDropPosition.after;
  }

  @override
  Widget build(BuildContext context) {
    final theme = BTheme.of(context);
    final row = widget.enabled
        ? Draggable<String>(
            data: widget.node.id,
            allowedButtonsFilter: (buttons) => buttons == kPrimaryButton,
            dragAnchorStrategy: pointerDragAnchorStrategy,
            feedback: Material(
              color: theme.colors.surfaceRaised,
              borderRadius: theme.geo.radiusSmall,
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Text(widget.node.name, style: theme.typo.body),
              ),
            ),
            childWhenDragging: Opacity(opacity: 0.4, child: widget.child),
            child: widget.child,
          )
        : widget.child;

    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => widget.enabled && details.data != widget.node.id,
      onMove: (details) {
        final position = _position(details.offset);
        final valid = widget.canMove(details.data, widget.node.id, position);
        if (_hover != (valid ? position : null)) setState(() => _hover = valid ? position : null);
      },
      onLeave: (_) {
        if (_hover != null) setState(() => _hover = null);
      },
      onAcceptWithDetails: (details) {
        final position = _position(details.offset);
        widget.onMove(details.data, widget.node.id, position);
        setState(() => _hover = null);
      },
      builder: (context, _, _) => DecoratedBox(
        decoration: BoxDecoration(
          color: _hover == FileTreeDropPosition.inside ? theme.colors.accentSoft : null,
          border: Border(
            top: _hover == FileTreeDropPosition.before
                ? BorderSide(color: theme.colors.accent, width: 2)
                : BorderSide.none,
            bottom: _hover == FileTreeDropPosition.after
                ? BorderSide(color: theme.colors.accent, width: 2)
                : BorderSide.none,
          ),
        ),
        child: row,
      ),
    );
  }
}
