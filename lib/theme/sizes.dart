// Defines reusable layout dimensions and component sizes.
// Used across application themes and reusable UI components.

import 'package:flutter/material.dart';

abstract final class BSizes {
  static const defaultTextButtonSize = Size(160, 36);
  static const colorButtonSize = Size.square(32);
  static const defaultIconSize = 18.0;
  static const defaultIconButtonSize = Size.square(40);
  static const markdownBodyFontSize = 14.0;
  static const double markdownLatexFontSize = markdownBodyFontSize * 1.2;
  static const toolOptionsWidth = 160.0;
}
