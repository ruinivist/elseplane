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
  }) : toggleValue = null;

  const ContextMenuAction.toggle({
    required this.label,
    required bool value,
    required VoidCallback this.onPressed,
    this.focusNode,
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
}

// ---------- Widgets ----------

/// Renders a context menu around a pointer-interactive child.
/// Used by canvas elements and other surfaces with grouped actions.
class ContextMenu extends StatelessWidget {
  const ContextMenu({
    required this.groups,
    required this.child,
    this.semanticLabel,
    this.title,
    this.controller,
    this.onClose,
    this.tapRegionGroupId,
    super.key,
  });

  final List<List<ContextMenuAction>> groups;
  final Widget child;
  final String? semanticLabel;
  final String? title;
  final MenuController? controller;
  final VoidCallback? onClose;
  final Object? tapRegionGroupId;

  static const _menuWidth = 224.0;
  static const double width = _menuWidth + 8; // Includes the menu surface's padding.

  // ---------- Composition ----------

  Widget _item(BuildContext context, ContextMenuAction action) {
    if (action.toggleValue case final value?) {
      return SizedBox(
        width: _menuWidth,
        child: LabeledSwitch.menu(
          label: action.label,
          value: value,
          focusNode: action.focusNode,
          onChanged: (_) => action.onPressed!(),
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
            focusNode: action.focusNode,
            style: style,
            menuStyle: menuShellStyle(),
            leadingIcon: Icon(action.icon, size: 16),
            menuChildren: [MenuSurface(children: _items(context, action.groups))],
            child: label,
          )
        : MenuItemButton(
            focusNode: action.focusNode,
            onPressed: action.onPressed,
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
      for (final action in groups[index])
        if (tapRegionGroupId != null)
          TapRegion(
            groupId: tapRegionGroupId,
            child: _item(context, action),
          )
        else
          _item(context, action),
    ],
  ];

  // ---------- Rendering ----------

  @override
  Widget build(BuildContext context) {
    final theme = BTheme.of(context);
    return MenuAnchor(
      consumeOutsideTap: true,
      style: menuShellStyle(),
      controller: controller,
      onClose: onClose,
      menuChildren: [
        MenuSurface(
          children: [
            if (title case final title?)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
                child: Text(title, style: theme.typo.label.copyWith(color: theme.colors.textMuted)),
              ),
            ..._items(context, groups),
          ],
        ),
      ],
      builder: (context, menuController, child) => controller != null
          ? child!
          : Semantics(
              label: semanticLabel,
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
      child: DefaultTextEditingShortcuts(child: child),
    );
  }
}
