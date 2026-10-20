// Defines the available canvas backgrounds and their grid delegates.
// Used by document settings and infinite-canvas rendering.

import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/theme/theme.dart';
import 'package:infinite_lazy_grid/infinite_lazy_grid.dart';

// ---------- Backgrounds ----------

/// Builds grid backgrounds from saved document choices.
/// Used by canvas presentation when applying settings and restoring documents.
extension CanvasBackgroundPresentation on CanvasBackgroundKind {
  CanvasBackground build(BColors colors) => switch (this) {
    CanvasBackgroundKind.dotGrid => DotGridBackground(
      dotColor: colors.canvasGrid,
      backgroundColor: colors.canvasBackground,
    ),
    CanvasBackgroundKind.plain => SingleColorBackground(
      colors.canvasBackground,
    ),
  };
}
