// Defines reusable layout dimensions and component sizes.
// Used across application themes and reusable UI components.

import 'package:material_ui/material_ui.dart';

abstract final class BSizes {
  static const colorButtonSize = Size.square(32);
  static const defaultIconSize = 18.0;
  static const defaultIconButtonSize = Size.square(40);
  static const compactIconButtonStyle = ButtonStyle(
    fixedSize: WidgetStatePropertyAll(Size.square(32)),
    minimumSize: WidgetStatePropertyAll(Size.zero),
    visualDensity: VisualDensity.standard,
  );
}
