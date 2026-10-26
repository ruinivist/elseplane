// Provides elseplane's themed context menu and action model.
// Used by interactive surfaces that expose grouped pointer actions.

import 'package:elseplane/theme/theme.dart';
import 'package:elseplane/ui/common/labeled_switch.dart';
import 'package:elseplane/ui/common/menu_surface.dart';
import 'package:flutter/material.dart';

// ---------- Models ----------

class ContextMenuAction {
  const ContextMenuAction({
    required this.label,
    required this.icon,
    this.onPressed,
    this.shortcut,
    this.destructive = false,
    this.groups = const [],
    this.focusNode,
    this.closeOnActivate = true,
  }) : toggleValue = null;

  const ContextMenuAction.toggle({
    required this.label,
    required bool value,
    required VoidCallback this.onPressed,
    this.focusNode,
    this.closeOnActivate = true,
  }) : toggleValue = value,
       icon = null,
       shortcut = null,
       destructive = false,
       groups = const [];

  final String label;
  final IconData? icon;
  final bool? toggleValue;
  final VoidCallback? onPressed;
  final MenuSerializableShortcut? shortcut;
  final bool destructive;
  final List<List<ContextMenuAction>> groups;
  final FocusNode? focusNode;
  final bool closeOnActivate;
}

// ---------- Widgets ----------

/// Renders a context menu around a pointer-interactive child.
/// Used by canvas elements and other surfaces with grouped actions.
class ContextMenu extends StatefulWidget {
  const ContextMenu({
    required this.groups,
    required this.child,
    this.semanticLabel,
    this.title,
    this.controller,
    this.onClose,
    this.onTapOutside,
    this.consumeOutsideTap = true,
    this.tapRegionGroupId,
    super.key,
  });

  final List<List<ContextMenuAction>> groups;
  final Widget child;
  final String? semanticLabel;
  final String? title;
  final MenuController? controller;
  final VoidCallback? onClose;
  final TapRegionCallback? onTapOutside;
  final bool consumeOutsideTap;
  final Object? tapRegionGroupId;

  static const double width = _ContextMenuState._menuWidth + 8; // Includes the menu surface's padding.

  @override
  State<ContextMenu> createState() => _ContextMenuState();
}

class _ContextMenuState extends State<ContextMenu> {
  final _firstItemFocus = FocusNode(debugLabel: 'Context menu first action');

  ContextMenuAction? get _firstAction => widget.groups
      .expand((group) => group)
      .where((action) => action.onPressed != null || action.groups.isNotEmpty)
      .firstOrNull;

  @override
  void dispose() {
    _firstItemFocus.dispose();
    super.dispose();
  }

  void _focusFirstAction() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final action = _firstAction;
      if (action != null) (action.focusNode ?? _firstItemFocus).requestFocus();
    });
  }

  static const _menuWidth = 224.0;

  // ---------- Composition ----------

  Widget _item(BuildContext context, ContextMenuAction action) {
    final focusNode = action.focusNode ?? (identical(action, _firstAction) ? _firstItemFocus : null);
    if (action.toggleValue case final value?) {
      return SizedBox(
        width: _menuWidth,
        child: LabeledSwitch.menu(
          label: action.label,
          value: value,
          focusNode: focusNode,
          onChanged: (_) => action.onPressed!(),
          closeOnActivate: action.closeOnActivate,
        ),
      );
    }
    final theme = BTheme.of(context);
    final style = menuItemStyle(theme, destructive: action.destructive);
    final enabled = action.groups.isNotEmpty || action.onPressed != null;
    final label = Text(
      action.label,
      style: TextStyle(
        color: !enabled
            ? theme.colors.textMuted
            : action.destructive
            ? theme.colors.destructive
            : theme.colors.textPrimary,
      ),
    );
    final item = action.groups.isNotEmpty
        ? SubmenuButton(
            focusNode: focusNode,
            style: style,
            menuStyle: menuShellStyle(),
            leadingIcon: Icon(action.icon, size: 16),
            menuChildren: [_surface(_items(context, action.groups))],
            child: label,
          )
        : MenuItemButton(
            focusNode: focusNode,
            onPressed: action.onPressed,
            closeOnActivate: action.closeOnActivate,
            shortcut: action.shortcut,
            style: style,
            leadingIcon: Icon(action.icon, size: 16),
            child: label,
          );
    return SizedBox(
      width: _menuWidth,
      child: item,
    );
  }

  List<Widget> _items(BuildContext context, List<List<ContextMenuAction>> groups) => [
    for (var index = 0; index < groups.length; index++) ...[
      if (index > 0)
        SizedBox(
          width: _menuWidth,
          child: Divider(height: 8, color: BTheme.of(context).colors.borderSubtle),
        ),
      for (final action in groups[index]) _item(context, action),
    ],
  ];

  Widget _surface(List<Widget> children, {TapRegionCallback? onTapOutside}) {
    final surface = MenuSurface(children: children);
    if (widget.tapRegionGroupId == null && onTapOutside == null) return surface;
    return TapRegion(
      behavior: HitTestBehavior.opaque,
      groupId: widget.tapRegionGroupId,
      onTapOutside: onTapOutside,
      child: surface,
    );
  }

  // ---------- Rendering ----------

  @override
  Widget build(BuildContext context) {
    final theme = BTheme.of(context);
    return MenuAnchor(
      consumeOutsideTap: widget.consumeOutsideTap,
      style: menuShellStyle(),
      controller: widget.controller,
      onOpen: widget.controller == null ? _focusFirstAction : null,
      onClose: widget.onClose,
      menuChildren: [
        _surface(
          [
            if (widget.title case final title?)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
                child: Text(title, style: theme.typo.label.copyWith(color: theme.colors.textMuted)),
              ),
            ..._items(context, widget.groups),
          ],
          onTapOutside: widget.onTapOutside,
        ),
      ],
      builder: (context, menuController, child) => widget.controller != null
          ? child!
          : Semantics(
              label: widget.semanticLabel,
              button: true,
              child: InkWell(
                mouseCursor: SystemMouseCursors.contextMenu,
                onTap: menuController.open,
                onSecondaryTapDown: (details) => menuController.open(position: details.localPosition),
                overlayColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.pressed)) return theme.colors.surfacePressed;
                  if (states.contains(WidgetState.hovered) || states.contains(WidgetState.focused)) {
                    return theme.colors.surfaceHover;
                  }
                  return Colors.transparent;
                }),
                child: child,
              ),
            ),
      // MenuAnchor's traversal shortcuts must yield to editing inside its content.
      child: DefaultTextEditingShortcuts(child: widget.child),
    );
  }
}
