// Maps saved shape kinds to presentation labels and icons.

import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Maps persisted shape kinds to concise user-facing labels.
/// Used by shape semantics and tool option controls.
extension ShapeKindPresentation on ShapeKind {
  String get label => switch (this) {
    ShapeKind.rectangle => 'Rectangle',
    ShapeKind.roundedRectangle => 'Rounded rectangle',
    ShapeKind.ellipse => 'Ellipse',
    ShapeKind.diamond => 'Diamond',
    ShapeKind.triangle => 'Triangle',
    ShapeKind.hexagon => 'Hexagon',
  };

  IconData get icon => switch (this) {
    ShapeKind.rectangle => LucideIcons.square,
    ShapeKind.roundedRectangle => LucideIcons.squareRoundCorner,
    ShapeKind.ellipse => LucideIcons.circle,
    ShapeKind.diamond => LucideIcons.diamond,
    ShapeKind.triangle => LucideIcons.triangle,
    ShapeKind.hexagon => LucideIcons.hexagon,
  };
}
