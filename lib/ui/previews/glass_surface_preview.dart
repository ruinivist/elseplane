// Demonstrates shared glass surfaces over visible canvas-like content.
// Used by Flutter's preview gallery to inspect light, dark, and overlapping surfaces.

import 'package:elseplane/theme/theme.dart';
import 'package:elseplane/ui/common/glass_surface.dart';
import 'package:elseplane/ui/common/menu_surface.dart';
import 'package:elseplane/ui/common/pointer_scroll_boundary.dart';
import 'package:elseplane/ui/common/surface.dart';
import 'package:elseplane/ui/common/surface_dialog.dart';
import 'package:elseplane/ui/previews/theme_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

// ---------- Annotated previews ----------

@Preview(name: 'PointerScrollBoundary', size: Size(420, 300), theme: previewTheme)
Widget pointerScrollBoundaryPreview() => _background(
  Center(
    child: SizedBox(
      width: 224,
      height: 160,
      child: PointerScrollBoundary(
        child: ListView(children: [for (var i = 0; i < 20; i++) ListTile(title: Text('Item $i'))]),
      ),
    ),
  ),
);

@Preview(name: 'GlassSurface light', size: Size(420, 300), theme: previewTheme, brightness: Brightness.light)
@Preview(name: 'GlassSurface dark', size: Size(420, 300), theme: previewTheme, brightness: Brightness.dark)
Widget glassSurfacePreview() => _background(
  const Stack(
    children: [
      Positioned(
        left: 32,
        top: 50,
        child: GlassSurface(
          child: Padding(padding: EdgeInsets.all(32), child: Text('Flat glass')),
        ),
      ),
      Positioned(
        left: 132,
        top: 92,
        child: GlassSurface(
          selected: true,
          child: Padding(padding: EdgeInsets.all(32), child: Text('Selected')),
        ),
      ),
      Positioned(
        left: 32,
        top: 190,
        child: GlassSurface(
          raised: true,
          child: Padding(padding: EdgeInsets.all(24), child: Text('Raised glass')),
        ),
      ),
    ],
  ),
);

@Preview(name: 'MenuSurface', size: Size(420, 300), theme: previewTheme, brightness: Brightness.light)
Widget menuSurfacePreview() => _background(
  Center(
    child: SizedBox(
      width: 224,
      child: MenuSurface(
        children: [
          MenuItemButton(onPressed: () {}, child: const Text('Copy')),
          MenuItemButton(onPressed: () {}, child: const Text('Paste')),
        ],
      ),
    ),
  ),
);

@Preview(name: 'SurfaceDialog', size: Size(420, 300), theme: previewTheme, brightness: Brightness.light)
Widget surfaceDialogPreview() => _background(
  const SurfaceDialog(
    child: Padding(padding: EdgeInsets.all(32), child: Text('Settings surface')),
  ),
);

@Preview(name: 'SurfaceConfirmationDialog', size: Size(420, 300), theme: previewTheme, brightness: Brightness.light)
Widget surfaceConfirmationDialogPreview() => _background(
  SurfaceConfirmationDialog(
    title: const Text('Replace canvas?'),
    content: const Text('The imported canvas will replace the active canvas.'),
    actions: [
      TextButton(onPressed: () {}, child: const Text('Cancel')),
      TextButton(onPressed: () {}, child: const Text('Replace')),
    ],
  ),
);

@Preview(name: 'Surface glass', size: Size(420, 300), theme: previewTheme, brightness: Brightness.dark)
Widget glassPanelPreview() => _background(
  const Center(
    child: Surface(
      child: Padding(padding: EdgeInsets.all(32), child: Text('App surface')),
    ),
  ),
);

// ---------- Background ----------

Widget _background(Widget child) => Builder(
  builder: (context) {
    final data = Theme.of(context);
    final theme = BTheme.of(context);
    return Theme(
      data: data.copyWith(extensions: [theme.copyWith(surfaceStyle: SurfaceStyle.glass)]),
      child: Material(
        color: theme.colors.canvasBackground,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final color in [
                  theme.colors.accent,
                  theme.colors.canvasGrid,
                  theme.colors.destructive,
                  theme.colors.accentSoft,
                ])
                  Expanded(
                    child: ColoredBox(
                      color: color,
                      child: const Center(child: Text('Canvas content behind glass')),
                    ),
                  ),
              ],
            ),
            child,
          ],
        ),
      ),
    );
  },
);
