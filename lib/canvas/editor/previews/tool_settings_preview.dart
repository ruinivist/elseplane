// Interactive previews of element options and shared canvas controls.

import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/editor/editor_session.dart';
import 'package:elseplane/canvas/editor/elements/arrow/arrow_stroke_style_icon.dart';
import 'package:elseplane/canvas/editor/elements/arrow/arrow_tool_settings.dart';
import 'package:elseplane/canvas/editor/elements/code/code_tool_settings.dart';
import 'package:elseplane/canvas/editor/elements/pen/pen_tool_settings.dart';
import 'package:elseplane/canvas/editor/elements/shape/shape_tool_settings.dart';
import 'package:elseplane/canvas/editor/elements/text/text_tool_settings.dart';
import 'package:elseplane/canvas/editor/widgets/stroke_settings.dart';
import 'package:elseplane/canvas/editor/widgets/tool_options.dart';
import 'package:elseplane/canvas/editor/widgets/toolbar_button.dart';
import 'package:elseplane/theme/fonts.dart';
import 'package:elseplane/theme/preset_colors.dart';
import 'package:elseplane/ui/previews/theme_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

@Preview(name: 'PenToolSettings', size: Size(320, 620), theme: previewTheme)
Widget penToolSettingsPreview() => const _SettingsPreview(_SettingsKind.pen);

@Preview(name: 'ArrowToolSettings', size: Size(320, 620), theme: previewTheme)
Widget arrowToolSettingsPreview() => const _SettingsPreview(_SettingsKind.arrow);

@Preview(name: 'ShapeToolSettings', size: Size(320, 740), theme: previewTheme)
Widget shapeToolSettingsPreview() => const _SettingsPreview(_SettingsKind.shape);

@Preview(name: 'CodeToolSettings', size: Size(320, 400), theme: previewTheme)
Widget codeToolSettingsPreview() => const _SettingsPreview(_SettingsKind.code);

@Preview(name: 'TextToolSettings', size: Size(320, 620), theme: previewTheme)
Widget textToolSettingsPreview() => const _SettingsPreview(_SettingsKind.text);

@Preview(name: 'StrokeSettings', size: Size(320, 520), theme: previewTheme)
@Preview(name: 'ToolOptions', size: Size(320, 300), theme: previewTheme)
Widget strokeSettingsPreview() => const _SettingsPreview(_SettingsKind.stroke);

@Preview(name: 'ToolbarButton', size: Size(320, 160), theme: previewTheme)
Widget toolbarButtonPreview() {
  var selected = false;
  return StatefulBuilder(
    builder: (context, setState) => Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ToolbarButton(
            selected: selected,
            onPressed: () => setState(() => selected = !selected),
            child: const Icon(Icons.edit, semanticLabel: 'Draw'),
          ),
          const ToolbarButton(selected: false, onPressed: null, child: Icon(Icons.edit_off)),
        ],
      ),
    ),
  );
}

@Preview(name: 'ArrowStrokeStyleIcon', size: Size(200, 120), theme: previewTheme)
Widget arrowStrokeStyleIconPreview() => const Center(
  child: Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      ArrowStrokeStyleIcon(style: ArrowStrokeStyle.solid),
      SizedBox(width: 20),
      ArrowStrokeStyleIcon(style: ArrowStrokeStyle.dashed),
    ],
  ),
);

enum _SettingsKind { pen, arrow, shape, code, text, stroke }

class _SettingsPreview extends StatefulWidget {
  const _SettingsPreview(this.kind);
  final _SettingsKind kind;

  @override
  State<_SettingsPreview> createState() => _SettingsPreviewState();
}

class _SettingsPreviewState extends State<_SettingsPreview> {
  late final _session = EditorSession(
    CanvasDocument(
      background: CanvasBackgroundKind.dotGrid,
      elements: [
        TextElementData(
          id: 'text',
          position: Offset.zero,
          width: 300,
          height: null,
          markdown: 'Preview',
          style: const TextNodeStyle(fontFamily: defaultFontFamily),
        ),
        CodeElementData(
          id: 'code',
          position: Offset.zero,
          size: const Size(300, 240),
          language: CodeLanguage.dart,
          source: 'print("Hello");',
          title: 'Example',
          showLineNumbers: true,
        ),
      ],
    ),
    initialColor: defaultCanvasColor,
  )..setActive('text');
  bool _colorExpanded = false;
  bool _fillExpanded = false;

  @override
  void dispose() {
    _session.dispose();
    super.dispose();
  }

  void _expandColor(bool expanded) => setState(() => _colorExpanded = expanded);

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Padding(
      padding: const EdgeInsets.all(16),
      child: Align(
        alignment: Alignment.topRight,
        child: ListenableBuilder(
          listenable: _session,
          builder: (context, _) => ToolOptions(child: _settings()),
        ),
      ),
    ),
  );

  Widget _settings() {
    final defaults = _session.defaults;
    return switch (widget.kind) {
      _SettingsKind.pen => PenToolSettings(
        color: defaults.color,
        width: defaults.width,
        streamline: defaults.streamline,
        colorPickerExpanded: _colorExpanded,
        onColorChanged: (color) => _session.setDrawingDefaults(defaults.copyWith(color: color)),
        onWidthChanged: (width) => _session.setDrawingDefaults(defaults.copyWith(width: width)),
        onStreamlineChanged: (value) => _session.setDrawingDefaults(defaults.copyWith(streamline: value)),
        onColorPickerExpandedChanged: _expandColor,
      ),
      _SettingsKind.arrow => ArrowToolSettings(
        color: defaults.arrowColor,
        strokeStyle: defaults.arrowStyle,
        strokeWidth: defaults.arrowWidth,
        colorPickerExpanded: _colorExpanded,
        onColorChanged: (color) => _session.setDrawingDefaults(defaults.copyWith(arrowColor: color)),
        onStrokeStyleChanged: (style) => _session.setDrawingDefaults(defaults.copyWith(arrowStyle: style)),
        onStrokeWidthChanged: (width) => _session.setDrawingDefaults(defaults.copyWith(arrowWidth: width)),
        onColorPickerExpandedChanged: _expandColor,
      ),
      _SettingsKind.shape => ShapeToolSettings(
        kind: defaults.shapeKind,
        strokeColor: defaults.shapeColor,
        fillColor: defaults.shapeFill,
        strokeWidth: defaults.shapeWidth,
        outlineColorPickerExpanded: _colorExpanded,
        fillColorPickerExpanded: _fillExpanded,
        onKindChanged: (kind) => _session.setDrawingDefaults(defaults.copyWith(shapeKind: kind)),
        onStrokeColorChanged: (color) => _session.setDrawingDefaults(defaults.copyWith(shapeColor: color)),
        onFillColorChanged: (color) =>
            _session.setDrawingDefaults(defaults.copyWith(shapeFill: color, clearShapeFill: color == null)),
        onStrokeWidthChanged: (width) => _session.setDrawingDefaults(defaults.copyWith(shapeWidth: width)),
        onOutlineColorPickerExpandedChanged: _expandColor,
        onFillColorPickerExpandedChanged: (expanded) => setState(() => _fillExpanded = expanded),
      ),
      _SettingsKind.code => CodeToolSettings(
        session: _session,
        id: 'code',
        onChangeBoundary: _session.finishOperation,
      ),
      _SettingsKind.text => TextToolSettings(
        session: _session,
        id: 'text',
        onChangeBoundary: _session.finishOperation,
        colorPickerExpanded: _colorExpanded,
        onColorPickerExpandedChanged: _expandColor,
      ),
      _SettingsKind.stroke => StrokeSettings(
        color: defaults.color,
        width: defaults.width,
        colorPickerExpanded: _colorExpanded,
        onColorChanged: (color) => _session.setDrawingDefaults(defaults.copyWith(color: color)),
        onWidthChanged: (width) => _session.setDrawingDefaults(defaults.copyWith(width: width)),
        onColorPickerExpandedChanged: _expandColor,
      ),
    };
  }
}
