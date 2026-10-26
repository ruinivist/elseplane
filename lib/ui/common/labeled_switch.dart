// Provides elseplane's compact labeled switch button.
// Used by app-wide settings, preference surfaces, and menu toggles.

import 'package:elseplane/theme/theme.dart';
import 'package:elseplane/ui/common/menu_surface.dart';
import 'package:flutter/material.dart';

// ---------- Geometry ----------

const _switchSize = Size(34, 20);
const _thumbSize = 16.0;

// ---------- Widgets ----------

/// Renders a compact settings row with a trailing binary switch.
/// Used by preference surfaces that toggle a labeled boolean value.
class LabeledSwitch extends StatelessWidget {
  // ---------- Construction ----------

  const LabeledSwitch({
    required this.label,
    required this.value,
    required this.onChanged,
    this.focusNode,
    super.key,
  }) : _menuItem = false,
       closeOnActivate = true;

  const LabeledSwitch.menu({
    required this.label,
    required this.value,
    required this.onChanged,
    this.focusNode,
    super.key,
    this.closeOnActivate = true,
  }) : _menuItem = true;

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final FocusNode? focusNode;
  final bool _menuItem;
  final bool closeOnActivate;

  // ---------- Rendering ----------

  @override
  Widget build(BuildContext context) {
    final theme = BTheme.of(context);
    final colors = theme.colors;
    void toggle() => onChanged(!value);

    final style = ButtonStyle(
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(vertical: 6),
      ),
      minimumSize: const WidgetStatePropertyAll(Size.zero),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      alignment: Alignment.centerLeft,
      side: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.focused) ? BorderSide(color: colors.focusRing, width: 1.5) : BorderSide.none,
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: theme.geo.radiusSmall),
      ),
    );
    final content = Row(
      children: [
        Expanded(child: Text(label, style: theme.typo.label)),
        SizedBox.fromSize(
          size: _switchSize,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: value ? colors.accent : colors.surfacePressed,
              border: value ? null : Border.all(color: colors.borderSubtle),
              borderRadius: BorderRadius.circular(_switchSize.height / 2),
            ),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: AnimatedAlign(
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOutCubic,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surfaceRaised,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: colors.shadow,
                        blurRadius: 2,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: const SizedBox.square(dimension: _thumbSize),
                ),
              ),
            ),
          ),
        ),
      ],
    );
    return Semantics(
      toggled: value,
      child: _menuItem
          ? MenuItemButton(
              focusNode: focusNode,
              onPressed: toggle,
              closeOnActivate: closeOnActivate,
              style: menuItemStyle(theme, destructive: false),
              child: content,
            )
          : TextButton(focusNode: focusNode, onPressed: toggle, style: style, child: content),
    );
  }
}
