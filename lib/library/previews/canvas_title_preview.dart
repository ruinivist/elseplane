// Previews the canvas title and its hover-revealed breadcrumb path.
// Used by Flutter widget previews before the title is placed in the editor.

import 'package:elseplane/library/widgets/canvas_title.dart';
import 'package:elseplane/theme/theme.dart';
import 'package:elseplane/ui/previews/theme_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

// ---------- Preview ----------

@Preview(
  name: 'CanvasTitle',
  size: Size(640, 240),
  theme: previewTheme,
  brightness: Brightness.light,
)
Widget canvasTitlePreview() => Builder(
  builder: (context) => ColoredBox(
    color: BTheme.of(context).colors.canvasBackground,
    child: const Center(
      child: CanvasTitle(path: ['Notes', 'Projects', 'Brainstorm']),
    ),
  ),
);
