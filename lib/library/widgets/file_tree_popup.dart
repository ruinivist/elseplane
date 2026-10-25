// Provides the canvas file-tree popup and its controlled node model.
// Used by the canvas file picker and isolated previews.

import 'package:elseplane/theme/theme.dart';
import 'package:elseplane/ui/common/context_menu.dart';
import 'package:elseplane/ui/common/surface.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
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

class FileTreePopup extends StatefulWidget {
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
    this.enabled = true,
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
  final bool enabled;

  @override
  State<FileTreePopup> createState() => _FileTreePopupState();
}

class _FileTreePopupState extends State<FileTreePopup> {
  static const _width = 380.0;
  static const _minHeight = 360.0;
  static const _maxHeight = 420.0;
  static const _rowHeight = 30.0;
  static const _indent = 18.0;
  static const _iconSize = 16.0;
  static const _controlSize = 28.0;

  // ---------- Keyboard focus ----------

  final _focusNodes = <String, FocusNode>{};
  String? _focusedId;
  List<String> _visibleIds = [];

  FocusNode _focusNode(String id) => _focusNodes.putIfAbsent(id, () => FocusNode(debugLabel: 'File tree $id'));

  List<FileTreeNode> _visibleNodes(List<FileTreeNode> nodes) => [
    for (final node in nodes) ...[
      node,
      if (widget.expandedIds.contains(node.id)) ..._visibleNodes(node.children),
    ],
  ];

  FileTreeNode? _parent(String id, List<FileTreeNode> nodes) {
    for (final node in nodes) {
      if (node.children.any((child) => child.id == id)) return node;
      final parent = _parent(id, node.children);
      if (parent != null) return parent;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _focusedId = widget.selectedId ?? _visibleNodes(widget.nodes).firstOrNull?.id;
    _restoreFocus();
  }

  @override
  void didUpdateWidget(FileTreePopup oldWidget) {
    super.didUpdateWidget(oldWidget);
    final visible = _visibleNodes(widget.nodes);
    final visibleIds = visible.map((node) => node.id).toSet();
    final previousId = _focusedId;
    while (_focusedId != null && !visibleIds.contains(_focusedId)) {
      _focusedId = _parent(_focusedId!, oldWidget.nodes)?.id;
    }
    if (_focusedId == null && visible.isNotEmpty) {
      final previousIndex = _visibleIds.indexOf(previousId ?? '');
      _focusedId = visible[previousIndex.clamp(0, visible.length - 1)].id;
    }
    if (_focusedId != previousId ||
        oldWidget.editingId != null && widget.editingId == null ||
        !oldWidget.enabled && widget.enabled) {
      _restoreFocus();
    }
  }

  @override
  void dispose() {
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _restoreFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.editingId != null || !widget.enabled || ModalRoute.of(context)?.isCurrent == false) return;
      if (_focusedId case final id?) _focusNode(id).requestFocus();
    });
  }

  void _revealFocusedRow() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final rowContext = _focusNodes[_focusedId]?.context;
      if (rowContext == null) return;
      final row = rowContext.findRenderObject()!;
      final viewport = RenderAbstractViewport.of(row);
      final position = Scrollable.of(rowContext).position;
      final rowStart = viewport.getOffsetToReveal(row, 0).offset;
      position.ensureVisible(
        row,
        alignmentPolicy: rowStart < position.pixels
            ? ScrollPositionAlignmentPolicy.keepVisibleAtStart
            : ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
    });
  }

  KeyEventResult _onKeyEvent(FocusNode _, KeyEvent event) {
    final keyboard = HardwareKeyboard.instance;
    if (widget.editingId != null ||
        ModalRoute.of(context)?.isCurrent == false ||
        keyboard.isControlPressed ||
        keyboard.isMetaPressed ||
        keyboard.isAltPressed ||
        keyboard.isShiftPressed ||
        event is KeyUpEvent) {
      return KeyEventResult.ignored;
    }
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext != null && MenuController.maybeOf(focusContext)?.isOpen == true) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final navigationKey =
        key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter;
    if (!navigationKey) return KeyEventResult.ignored;
    if (!widget.enabled) return KeyEventResult.handled;
    final visible = _visibleNodes(widget.nodes);
    final index = visible.indexWhere((node) => node.id == _focusedId);
    if (index < 0) return KeyEventResult.handled;
    final node = visible[index];
    final folder = node.type == FileTreeNodeType.folder;
    final expanded = widget.expandedIds.contains(node.id);
    String? target;
    if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.arrowUp) {
      target = visible[(index + (key == LogicalKeyboardKey.arrowDown ? 1 : -1)).clamp(0, visible.length - 1)].id;
    } else if (key == LogicalKeyboardKey.arrowRight) {
      if (folder && !expanded) {
        widget.onToggle(node);
      } else if (folder && node.children.isNotEmpty) {
        target = node.children.first.id;
      }
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      if (folder && expanded) {
        widget.onToggle(node);
      } else {
        target = _parent(node.id, widget.nodes)?.id;
      }
    } else if (event is KeyDownEvent) {
      if (folder) {
        widget.onToggle(node);
      } else {
        widget.onSelect(node);
      }
    }
    if (target != null) _focusNode(target).requestFocus();
    return KeyEventResult.handled;
  }

  // ---------- Rendering ----------

  @override
  Widget build(BuildContext context) {
    _visibleIds = _visibleNodes(widget.nodes).map((node) => node.id).toList();
    return SizedBox(
      width: _width,
      child: Surface(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: _minHeight, maxHeight: _maxHeight),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 38),
                // Keep scrolling rows together so their moving bounds cannot
                // reorder Tab traversal around the fixed header controls.
                child: FocusTraversalGroup(
                  child: AnimatedPrimaryScrollController(
                    child: SingleChildScrollView(
                      primary: true,
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [for (final node in widget.nodes) _node(context, node, 0)],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 6,
                right: 6,
                child: Row(
                  children: [
                    _control(
                      key: const ValueKey('file-tree-new-file'),
                      icon: LucideIcons.filePlus,
                      tooltip: 'New canvas',
                      onPressed: widget.onNewFile,
                    ),
                    const SizedBox(width: 2),
                    _control(
                      key: const ValueKey('file-tree-new-folder'),
                      icon: LucideIcons.folderPlus,
                      tooltip: 'New folder',
                      onPressed: widget.onNewFolder,
                    ),
                    if (widget.onDemo case final onDemo?) ...[
                      const SizedBox(width: 2),
                      _control(
                        key: const ValueKey('file-tree-demo'),
                        icon: LucideIcons.flaskConical,
                        tooltip: 'Demo',
                        onPressed: onDemo,
                      ),
                    ],
                    const SizedBox(width: 2),
                    _control(
                      key: const ValueKey('file-tree-close'),
                      icon: LucideIcons.x,
                      tooltip: 'Close',
                      onPressed: widget.onClose,
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
    final isExpanded = isFolder && widget.expandedIds.contains(node.id);
    final isSelected = !isFolder && widget.selectedId == node.id;
    final radius = theme.geo.radiusSmall;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.only(left: depth * _indent, bottom: 2),
          child: _DropRow(
            node: node,
            enabled: widget.enabled && widget.editingId == null,
            canMove: widget.canMove,
            onMove: widget.onMove,
            child: Semantics(
              button: true,
              selected: isSelected,
              expanded: isFolder ? isExpanded : null,
              child: ContextMenu(
                groups: [widget.actionsFor(node)],
                onClose: _restoreFocus,
                child: Focus(
                  canRequestFocus: false,
                  onKeyEvent: _onKeyEvent,
                  child: InkWell(
                    key: ValueKey('file-tree-node-${node.id}'),
                    focusNode: _focusNode(node.id),
                    onFocusChange: (focused) {
                      if (focused) {
                        _focusedId = node.id;
                        _revealFocusedRow();
                      }
                    },
                    borderRadius: radius,
                    mouseCursor: SystemMouseCursors.click,
                    onTap: () {
                      if (!widget.enabled) return;
                      _focusNode(node.id).requestFocus();
                      if (isFolder) {
                        widget.onToggle(node);
                      } else {
                        widget.onSelect(node);
                      }
                    },
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
                            : widget.editingId == node.id
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
                            child: widget.editingId == node.id
                                ? widget.editor!
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
        ),
        if (isExpanded)
          for (final child in node.children) _node(context, child, depth + 1),
      ],
    );
  }

  Widget _control({
    required Key key,
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) => IconButton(
    key: key,
    tooltip: tooltip,
    onPressed: onPressed,
    icon: Icon(icon),
    iconSize: _iconSize,
    style: const ButtonStyle(
      minimumSize: WidgetStatePropertyAll(Size.zero),
      fixedSize: WidgetStatePropertyAll(Size.square(_controlSize)),
    ),
  );
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
