// Composes the canvas with page chrome and application dialogs.
// Used by Workspace to present the open editor session.

import 'dart:async';

import 'package:elseplane/attachments/attachment_store.dart';
import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/editor/browser_touch_observer.dart'
    if (dart.library.js_interop) 'package:elseplane/canvas/editor/browser_touch_observer_web.dart';
import 'package:elseplane/canvas/editor/canvas_clipboard.dart';
import 'package:elseplane/canvas/editor/canvas_input.dart';
import 'package:elseplane/canvas/editor/canvas_view.dart';
import 'package:elseplane/canvas/editor/editor_session.dart';
import 'package:elseplane/canvas/editor/elements/code/code_element_view.dart';
import 'package:elseplane/canvas/editor/elements/shape/shape_element_view.dart';
import 'package:elseplane/canvas/editor/elements/text/text_tool_settings.dart';
import 'package:elseplane/canvas/editor/widgets/arrow_stroke_style_icon.dart';
import 'package:elseplane/canvas/editor/widgets/canvas_chrome.dart';
import 'package:elseplane/canvas/editor/widgets/canvas_toolbar.dart';
import 'package:elseplane/canvas/editor/widgets/toolbar_button.dart';
import 'package:elseplane/library/widgets/canvas_title.dart';
import 'package:elseplane/settings/settings_dialog.dart';
import 'package:elseplane/theme/theme.dart';
import 'package:elseplane/ui/common/color_picker.dart';
import 'package:elseplane/ui/common/discrete_slider.dart';
import 'package:elseplane/ui/common/surface.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

// ---------- Canvas workspace ----------

/// Projects the editor session into the canvas, tools, and workspace controls.
/// Used as the application's primary interactive workspace.
class CanvasPage extends StatefulWidget {
  // ---------- Construction ----------

  const CanvasPage({
    required this.session,
    required this.attachmentStore,
    required this.libraryPath,
    required this.onOpenLibrary,
    required this.onImportCanvas,
    required this.onExportCanvas,
    required this.onBackupLibrary,
    required this.onRestoreLibrary,
    this.blocked = false,
    this.readClipboard,
    this.writeClipboardText,
    this.themeMode = ThemeMode.light,
    this.onSurfaceStyleChanged,
    this.onThemeModeChanged,
    super.key,
  });

  final EditorSession? session;
  final AttachmentStore attachmentStore;
  final List<String> libraryPath;
  final Future<void> Function() onOpenLibrary;
  final Future<bool> Function() onImportCanvas;
  final Future<void> Function() onExportCanvas;
  final Future<void> Function() onBackupLibrary;
  final Future<bool> Function() onRestoreLibrary;
  final bool blocked;
  final Future<CanvasClipboardSnapshot> Function()? readClipboard;
  final Future<void> Function(String text)? writeClipboardText;
  final ThemeMode themeMode;
  final Future<void> Function(SurfaceStyle)? onSurfaceStyleChanged;
  final Future<void> Function(ThemeMode)? onThemeModeChanged;

  @override
  State<CanvasPage> createState() => _CanvasPageState();
}

class _CanvasPageState extends State<CanvasPage> {
  EditorSession get _session => widget.session!;
  CanvasTool get _activeTool => widget.session?.tool ?? CanvasTool.select;
  CanvasBackgroundKind get _canvasBackgroundKind => _session.document.background;
  bool get _touchSelectionEnabled => widget.session?.touchSelectionEnabled ?? false;
  bool get _documentLoaded => widget.session?.isLive == true && !widget.blocked;
  bool _filePickerOpen = false;
  bool _settingsOpen = false;
  bool _touchControlsVisible = false;
  final _pageTouchPointers = <int>{};
  bool _browserTouchObserved = false;
  late final VoidCallback _stopObservingBrowserTouch;
  bool _penColorPickerExpanded = false;
  bool _shapeOutlineColorPickerExpanded = false;
  bool _shapeFillColorPickerExpanded = false;
  bool _arrowColorPickerExpanded = false;
  bool _textColorPickerExpanded = false;
  CanvasElementData? get _activeElement => _session.activeId == null ? null : _session.element(_session.activeId!);
  TextElementData? get _activeTextBlock => switch (_activeElement) {
    final TextElementData data => data,
    _ => null,
  };
  CodeElementData? get _activeCodeBlock => switch (_activeElement) {
    final CodeElementData data => data,
    _ => null,
  };
  ShapeElementData? get _activeShape => switch (_activeElement) {
    final ShapeElementData data => data,
    _ => null,
  };
  ArrowElementData? get _activeArrow => switch (_activeElement) {
    final ArrowElementData data => data,
    _ => null,
  };
  bool get _penEnabled => _activeTool == CanvasTool.pen;
  bool get _shapeEnabled => _activeTool == CanvasTool.shape;
  bool get _arrowEnabled => _activeTool == CanvasTool.arrow;
  Color get _penColor => _session.defaults.color;
  double get _penWidth => _session.defaults.width;
  double get _penStreamline => _session.defaults.streamline;

  @override
  void initState() {
    super.initState();
    GestureBinding.instance.pointerRouter.addGlobalRoute(_observePageTouch);
    _stopObservingBrowserTouch = observeBrowserTouch(
      onStart: () => _browserTouchObserved = true,
      onEnd: _revealTouchControls,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final platform = Theme.of(context).platform;
    if (platform == TargetPlatform.android || platform == TargetPlatform.iOS) _touchControlsVisible = true;
  }

  @override
  void dispose() {
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_observePageTouch);
    _stopObservingBrowserTouch();
    super.dispose();
  }

  void _observePageTouch(PointerEvent event) {
    if (_touchControlsVisible || _browserTouchObserved || event.kind != PointerDeviceKind.touch) return;
    if (event is PointerDownEvent) {
      _pageTouchPointers.add(event.pointer);
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      // Wait for release callbacks before allowing the toolbar to rearrange.
      scheduleMicrotask(() {
        _pageTouchPointers.remove(event.pointer);
        if (!_browserTouchObserved && _pageTouchPointers.isEmpty) _revealTouchControls();
      });
    }
  }

  void _revealTouchControls() {
    if (mounted && !_touchControlsVisible) setState(() => _touchControlsVisible = true);
  }

  void _finishHistoryOperation() => _session.finishOperation();
  void _clearTextEditing() {
    if (_session.editing?.field == EditorField.markdown) _session.editField(null);
  }

  void _editElement(CanvasElementData value, VoidCallback edit) {
    if (_session.element(value.id) == null) return;
    _session.finishOperation();
    edit();
    _session.finishOperation();
  }

  void _setCanvasBackground(CanvasBackgroundKind kind) {
    if (!_documentLoaded) return;
    _session
      ..finishOperation()
      ..setBackground(kind)
      ..finishOperation();
  }

  Future<void> _showFilePicker(CanvasInput input) async {
    if (!_documentLoaded || _filePickerOpen) return;
    input.endInteraction();
    setState(() => _filePickerOpen = true);
    try {
      await widget.onOpenLibrary();
    } finally {
      if (mounted) setState(() => _filePickerOpen = false);
    }
  }

  Future<void> _showSettingsDialog(CanvasInput input) async {
    if (!_documentLoaded || _filePickerOpen || _settingsOpen) return;
    input.endInteraction();
    setState(() => _settingsOpen = true);
    try {
      await showDialog<void>(
        context: context,
        barrierColor: BTheme.of(context).colors.scrim,
        builder: (_) => SettingsDialog(
          themeMode: widget.themeMode,
          onThemeModeChanged: widget.onThemeModeChanged,
          onSurfaceStyleChanged: widget.onSurfaceStyleChanged,
          canvasBackgroundKind: _canvasBackgroundKind,
          onCanvasBackgroundChanged: _setCanvasBackground,
          onImportCanvas: widget.onImportCanvas,
          onExportCanvas: widget.onExportCanvas,
          onBackupLibrary: widget.onBackupLibrary,
          onRestoreLibrary: widget.onRestoreLibrary,
        ),
      );
    } finally {
      if (mounted) setState(() => _settingsOpen = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    if (session == null) return Scaffold(body: _buildChrome(context, null));
    return Scaffold(
      body: CanvasView(
        session: session,
        attachmentStore: widget.attachmentStore,
        blocked: widget.blocked || _filePickerOpen || _settingsOpen,
        libraryOpen: _filePickerOpen,
        readClipboard: widget.readClipboard,
        writeClipboardText: widget.writeClipboardText,
        onOpenLibrary: _showFilePicker,
        chromeBuilder: _buildChrome,
      ),
    );
  }

  Widget _buildChrome(BuildContext context, CanvasInput? input) {
    final theme = BTheme.of(context);
    return CanvasChrome(
      title: CanvasTitle(
        path: widget.libraryPath,
        onPressed: _documentLoaded && input != null ? () => _showFilePicker(input) : null,
      ),
      toolbar: CanvasToolbar(
        buttonsBuilder: ({required compact}) => _buildToolbarButtons(input, compact: compact),
      ),
      settingsButton: Surface(
        key: const ValueKey('settings-button-surface'),
        child: IconButton(
          key: const ValueKey('settings-button'),
          tooltip: 'Settings',
          onPressed: input == null ? null : () => _showSettingsDialog(input),
          style: _toolbarButtonStyle(
            theme.colors,
            theme.geo,
          ).copyWith(padding: const WidgetStatePropertyAll(EdgeInsets.all(8))),
          icon: const Icon(LucideIcons.settings),
        ),
      ),
      toolOptions: input == null ? null : _buildToolOptions(input),
    );
  }

  // ---------- Canvas chrome content ----------

  List<Widget> _buildToolbarButtons(CanvasInput? input, {required bool compact}) => [
    for (final (tool, key, message, icon, label) in const [
      (CanvasTool.text, 'text', 'Place text', LucideIcons.type, 'Text'),
      (CanvasTool.code, 'code', 'Place code block', LucideIcons.codeXml, 'Code'),
      (CanvasTool.media, 'media', 'Place media', LucideIcons.image, 'Media'),
      (CanvasTool.shape, 'shape', 'Draw rounded rectangle', LucideIcons.squareRoundCorner, 'Rect'),
      (CanvasTool.pen, 'draw', 'Draw with pen', LucideIcons.pencil, 'Draw'),
      (CanvasTool.eraser, 'erase', 'Erase elements', LucideIcons.eraser, 'Erase'),
      (CanvasTool.arrow, 'arrow', 'Draw an arrow', LucideIcons.arrowUpRight, 'Arrow'),
    ])
      Tooltip(
        message: message,
        child: ToolbarButton(
          compact: compact,
          key: ValueKey('toolbar-$key'),
          selected: _activeTool == tool,
          onPressed: input == null ? null : () => input.toggleTool(tool),
          child: Icon(icon, size: 20, semanticLabel: label),
        ),
      ),
    if (_touchControlsVisible)
      Tooltip(
        message: 'Select elements',
        child: ToolbarButton(
          key: const ValueKey('toolbar-select'),
          compact: compact,
          selected: _touchSelectionEnabled,
          onPressed: input == null
              ? null
              : () => input.chooseTool(CanvasTool.select, touchSelectionEnabled: !_touchSelectionEnabled),
          child: const Icon(LucideIcons.squareDashed, size: 20, semanticLabel: 'Select'),
        ),
      ),
  ];

  Widget? _buildToolOptions(CanvasInput input) {
    final activeTextBlock = _activeTextBlock;
    final activeCodeBlock = _activeCodeBlock;
    final activeShape = _activeShape;
    final activeArrow = _activeArrow;
    return activeTextBlock != null
        ? Listener(
            onPointerDown: (_) => _clearTextEditing(),
            child: TextToolSettings(
              key: ValueKey(
                'text-settings-${activeTextBlock.id}',
              ),
              session: _session,
              id: activeTextBlock.id,
              onChangeBoundary: _finishHistoryOperation,
              colorPickerExpanded: _textColorPickerExpanded,
              onColorPickerExpandedChanged: (expanded) => setState(
                () => _textColorPickerExpanded = expanded,
              ),
            ),
          )
        : activeCodeBlock != null
        ? CodeToolSettings(
            key: ValueKey(
              'code-settings-${activeCodeBlock.id}',
            ),
            session: _session,
            id: activeCodeBlock.id,
            onChangeBoundary: _finishHistoryOperation,
          )
        : activeShape != null
        ? ListenableBuilder(
            key: const ValueKey('shape-settings-panel'),
            listenable: _session,
            builder: (context, _) => _ShapeSettings(
              kind: activeShape.kind,
              strokeColor: activeShape.strokeColor,
              fillColor: activeShape.fillColor,
              strokeWidth: activeShape.strokeWidth,
              outlineColorPickerExpanded: _shapeOutlineColorPickerExpanded,
              fillColorPickerExpanded: _shapeFillColorPickerExpanded,
              onKindChanged: (kind) =>
                  _editElement(activeShape, () => _session.setShapeOptions(activeShape.id, kind: kind)),
              onStrokeColorChanged: (color) =>
                  _editElement(activeShape, () => _session.setShapeOptions(activeShape.id, strokeColor: color)),
              onFillColorChanged: (color) => _editElement(
                activeShape,
                () => _session.setShapeOptions(activeShape.id, fillColor: color, clearFillColor: color == null),
              ),
              onStrokeWidthChanged: (width) =>
                  _editElement(activeShape, () => _session.setShapeOptions(activeShape.id, strokeWidth: width)),
              onFillColorPickerExpandedChanged: (expanded) => setState(
                () => _shapeFillColorPickerExpanded = expanded,
              ),
              onOutlineColorPickerExpandedChanged: (expanded) => setState(
                () => _shapeOutlineColorPickerExpanded = expanded,
              ),
            ),
          )
        : activeArrow != null
        ? ListenableBuilder(
            key: const ValueKey('arrow-settings-panel'),
            listenable: _session,
            builder: (context, _) => _ArrowSettings(
              color: activeArrow.color,
              strokeStyle: activeArrow.strokeStyle,
              strokeWidth: activeArrow.strokeWidth,
              colorPickerExpanded: _arrowColorPickerExpanded,
              onColorChanged: (color) =>
                  _editElement(activeArrow, () => _session.setArrowOptions(activeArrow.id, color: color)),
              onStrokeStyleChanged: (style) =>
                  _editElement(activeArrow, () => _session.setArrowOptions(activeArrow.id, strokeStyle: style)),
              onStrokeWidthChanged: (width) =>
                  _editElement(activeArrow, () => _session.setArrowOptions(activeArrow.id, strokeWidth: width)),
              onColorPickerExpandedChanged: (expanded) => setState(() => _arrowColorPickerExpanded = expanded),
            ),
          )
        : _penEnabled
        ? _StrokeSettings(
            key: const ValueKey('draw-settings-panel'),
            color: _penColor,
            width: _penWidth,
            streamline: _penStreamline,
            colorPickerExpanded: _penColorPickerExpanded,
            onColorChanged: input.pen.setColor,
            onColorPickerExpandedChanged: (expanded) => setState(
              () => _penColorPickerExpanded = expanded,
            ),
            onWidthChanged: input.pen.setStrokeWidth,
            onStreamlineChanged: input.pen.setStreamline,
          )
        : _shapeEnabled
        ? ListenableBuilder(
            key: const ValueKey('shape-settings-panel'),
            listenable: input.shape,
            builder: (context, _) => _ShapeSettings(
              kind: input.shape.kind,
              strokeColor: input.shape.strokeColor,
              fillColor: input.shape.fillColor,
              strokeWidth: input.shape.strokeWidth,
              outlineColorPickerExpanded: _shapeOutlineColorPickerExpanded,
              fillColorPickerExpanded: _shapeFillColorPickerExpanded,
              onKindChanged: input.shape.setKind,
              onStrokeColorChanged: input.shape.setStrokeColor,
              onFillColorChanged: input.shape.setFillColor,
              onStrokeWidthChanged: input.shape.setStrokeWidth,
              onFillColorPickerExpandedChanged: (expanded) => setState(
                () => _shapeFillColorPickerExpanded = expanded,
              ),
              onOutlineColorPickerExpandedChanged: (expanded) => setState(
                () => _shapeOutlineColorPickerExpanded = expanded,
              ),
            ),
          )
        : _arrowEnabled
        ? ListenableBuilder(
            key: const ValueKey('arrow-settings-panel'),
            listenable: input.arrow,
            builder: (context, _) => _ArrowSettings(
              color: input.arrow.color,
              strokeStyle: input.arrow.strokeStyle,
              strokeWidth: input.arrow.strokeWidth,
              colorPickerExpanded: _arrowColorPickerExpanded,
              onColorChanged: input.arrow.setColor,
              onStrokeStyleChanged: input.arrow.setStrokeStyle,
              onStrokeWidthChanged: input.arrow.setStrokeWidth,
              onColorPickerExpandedChanged: (expanded) => setState(() => _arrowColorPickerExpanded = expanded),
            ),
          )
        : null;
  }
}

// ---------- Tool settings ----------

class _ArrowSettings extends StatelessWidget {
  const _ArrowSettings({
    required this.color,
    required this.strokeStyle,
    required this.strokeWidth,
    required this.colorPickerExpanded,
    required this.onColorChanged,
    required this.onStrokeStyleChanged,
    required this.onStrokeWidthChanged,
    required this.onColorPickerExpandedChanged,
  });

  final Color color;
  final ArrowStrokeStyle strokeStyle;
  final double strokeWidth;
  final bool colorPickerExpanded;
  final ValueChanged<Color> onColorChanged;
  final ValueChanged<ArrowStrokeStyle> onStrokeStyleChanged;
  final ValueChanged<double> onStrokeWidthChanged;
  final ValueChanged<bool> onColorPickerExpandedChanged;

  @override
  Widget build(BuildContext context) {
    final theme = BTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Style', style: theme.typo.label),
        const SizedBox(height: 6),
        Wrap(
          children: [
            for (final option in ArrowStrokeStyle.values)
              Tooltip(
                message: option == ArrowStrokeStyle.solid ? 'Solid' : 'Dashed',
                child: ToolbarButton(
                  key: ValueKey('arrow-style-${option.name}'),
                  selected: option == strokeStyle,
                  onPressed: () => onStrokeStyleChanged(option),
                  child: ArrowStrokeStyleIcon(style: option),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        _StrokeSettings(
          color: color,
          width: strokeWidth,
          widthMinimum: arrowStrokeWidthMinimum,
          widthMaximum: arrowStrokeWidthMaximum,
          widthLabelOffset: -3,
          colorPickerExpanded: colorPickerExpanded,
          onColorChanged: onColorChanged,
          onColorPickerExpandedChanged: onColorPickerExpandedChanged,
          onWidthChanged: onStrokeWidthChanged,
        ),
      ],
    );
  }
}

class _ShapeSettings extends StatelessWidget {
  const _ShapeSettings({
    required this.kind,
    required this.strokeColor,
    required this.fillColor,
    required this.strokeWidth,
    required this.outlineColorPickerExpanded,
    required this.fillColorPickerExpanded,
    required this.onKindChanged,
    required this.onStrokeColorChanged,
    required this.onFillColorChanged,
    required this.onStrokeWidthChanged,
    required this.onOutlineColorPickerExpandedChanged,
    required this.onFillColorPickerExpandedChanged,
  });

  final ShapeKind kind;
  final Color strokeColor;
  final Color? fillColor;
  final double strokeWidth;
  final bool outlineColorPickerExpanded;
  final bool fillColorPickerExpanded;
  final ValueChanged<ShapeKind> onKindChanged;
  final ValueChanged<Color> onStrokeColorChanged;
  final ValueChanged<Color?> onFillColorChanged;
  final ValueChanged<double> onStrokeWidthChanged;
  final ValueChanged<bool> onOutlineColorPickerExpandedChanged;
  final ValueChanged<bool> onFillColorPickerExpandedChanged;

  @override
  Widget build(BuildContext context) {
    final theme = BTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Shape', style: theme.typo.label),
        const SizedBox(height: 6),
        Wrap(
          children: [
            for (final option in ShapeKind.values)
              Tooltip(
                message: option.label,
                child: ToolbarButton(
                  key: ValueKey('shape-option-${option.name}'),
                  selected: option == kind,
                  onPressed: () => onKindChanged(option),
                  child: Icon(
                    _shapeIcon(option),
                    semanticLabel: option.label,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text('Outline', style: theme.typo.label),
        const SizedBox(height: 6),
        ColorControl(
          key: const ValueKey('shape-outline-color'),
          color: strokeColor,
          expanded: outlineColorPickerExpanded,
          onChanged: onStrokeColorChanged,
          onExpandedChanged: onOutlineColorPickerExpandedChanged,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: Text('Fill', style: theme.typo.label)),
            Semantics(
              selected: fillColor == null,
              child: IconButton(
                key: const ValueKey('shape-fill-none'),
                tooltip: 'No fill',
                constraints: BoxConstraints.tight(BSizes.colorButtonSize),
                iconSize: BSizes.defaultIconSize,
                style: IconButton.styleFrom(
                  padding: const EdgeInsets.all(6),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: const CircleBorder(),
                  side: BorderSide(
                    color: fillColor == null ? theme.colors.focusRing : Colors.transparent,
                    width: 2,
                  ),
                ),
                onPressed: () => onFillColorChanged(null),
                icon: const Icon(LucideIcons.ban),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ColorControl(
          key: const ValueKey('shape-fill-color'),
          color: fillColor,
          expanded: fillColorPickerExpanded,
          onChanged: onFillColorChanged,
          onExpandedChanged: onFillColorPickerExpandedChanged,
        ),
        const SizedBox(height: 10),
        Text('Width', style: theme.typo.label),
        DiscreteSlider(
          value: strokeWidth,
          onChanged: onStrokeWidthChanged,
        ),
      ],
    );
  }
}

IconData _shapeIcon(ShapeKind kind) => switch (kind) {
  ShapeKind.rectangle => LucideIcons.square,
  ShapeKind.roundedRectangle => LucideIcons.squareRoundCorner,
  ShapeKind.ellipse => LucideIcons.circle,
  ShapeKind.diamond => LucideIcons.diamond,
  ShapeKind.triangle => LucideIcons.triangle,
  ShapeKind.hexagon => LucideIcons.hexagon,
};

class _StrokeSettings extends StatelessWidget {
  const _StrokeSettings({
    required this.color,
    required this.width,
    required this.colorPickerExpanded,
    required this.onColorChanged,
    required this.onColorPickerExpandedChanged,
    required this.onWidthChanged,
    this.widthMinimum = 0.25,
    this.widthMaximum = 5.0,
    this.widthLabelOffset = 0,
    this.streamline,
    this.onStreamlineChanged,
    super.key,
  });

  final Color color;
  final double width;
  final double widthMinimum;
  final double widthMaximum;
  final int widthLabelOffset;
  final double? streamline;
  final bool colorPickerExpanded;
  final ValueChanged<Color> onColorChanged;
  final ValueChanged<bool> onColorPickerExpandedChanged;
  final ValueChanged<double> onWidthChanged;
  final ValueChanged<double>? onStreamlineChanged;

  @override
  Widget build(BuildContext context) {
    final theme = BTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Color', style: theme.typo.label),
        const SizedBox(height: 6),
        ColorControl(
          color: color,
          expanded: colorPickerExpanded,
          onChanged: onColorChanged,
          onExpandedChanged: onColorPickerExpandedChanged,
        ),
        const SizedBox(height: 10),
        Text('Width', style: theme.typo.label),
        DiscreteSlider(
          key: const ValueKey('pen-width-slider'),
          value: width,
          min: widthMinimum,
          max: widthMaximum,
          labelOffset: widthLabelOffset,
          onChanged: onWidthChanged,
        ),
        if ((streamline, onStreamlineChanged) case (final streamline?, final onStreamlineChanged?)) ...[
          const SizedBox(height: 10),
          Text('Smoothing', style: theme.typo.label),
          DiscreteSlider(
            key: const ValueKey('pen-smoothing-slider'),
            value: streamline,
            min: penStreamlineMinimum,
            max: penStreamlineMaximum,
            onChanged: onStreamlineChanged,
          ),
        ],
      ],
    );
  }
}

ButtonStyle _toolbarButtonStyle(BColors colors, BGeo geo) {
  return ButtonStyle(
    foregroundColor: WidgetStatePropertyAll(colors.textSecondary),
    backgroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.pressed)) {
        return colors.surfacePressed;
      }
      if (states.contains(WidgetState.hovered)) return colors.surfaceHover;
      return Colors.transparent;
    }),
    side: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.focused) ? BorderSide(color: colors.focusRing) : BorderSide.none,
    ),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: geo.radiusSmall),
    ),
  );
}
