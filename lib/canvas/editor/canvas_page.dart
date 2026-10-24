// Provides the infinite canvas editor and reports immutable document snapshots.
// Used as the application's primary workspace screen.

import 'dart:async';
import 'dart:math' as math;

import 'package:elseplane/attachments/attachment_store.dart';
import 'package:elseplane/attachments/image_import.dart';
import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/editor/browser_touch_observer.dart'
    if (dart.library.js_interop) 'package:elseplane/canvas/editor/browser_touch_observer_web.dart';
import 'package:elseplane/canvas/editor/canvas_background.dart';
import 'package:elseplane/canvas/editor/canvas_clipboard.dart';
import 'package:elseplane/canvas/editor/canvas_element_model.dart';
import 'package:elseplane/canvas/editor/editor_session.dart';
import 'package:elseplane/canvas/editor/widgets/arrow_stroke_style_icon.dart';
import 'package:elseplane/canvas/editor/widgets/canvas_chrome.dart';
import 'package:elseplane/canvas/editor/widgets/canvas_toolbar.dart';
import 'package:elseplane/canvas/editor/widgets/element_transform_controls.dart';
import 'package:elseplane/canvas/editor/widgets/toolbar_button.dart';
import 'package:elseplane/canvas/editor/widgets/zoom_control.dart';
import 'package:elseplane/canvas/geometry/element_geometry.dart';
import 'package:elseplane/canvas/geometry/transforms.dart';
import 'package:elseplane/canvas/tools/arrow/arrow_tool.dart';
import 'package:elseplane/canvas/tools/code/code_tool.dart';
import 'package:elseplane/canvas/tools/media/media_tool.dart';
import 'package:elseplane/canvas/tools/pen/pen_tool.dart';
import 'package:elseplane/canvas/tools/shape/shape_tool.dart';
import 'package:elseplane/canvas/tools/text/text_tool.dart';
import 'package:elseplane/library/widgets/canvas_title.dart';
import 'package:elseplane/settings/settings_dialog.dart';
import 'package:elseplane/theme/fonts.dart';
import 'package:elseplane/theme/preset_colors.dart';
import 'package:elseplane/theme/theme.dart';
import 'package:elseplane/ui/common/color_picker.dart';
import 'package:elseplane/ui/common/context_menu.dart';
import 'package:elseplane/ui/common/discrete_slider.dart';
import 'package:elseplane/ui/common/surface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:infinite_lazy_grid/infinite_lazy_grid.dart';
import 'package:infinite_lazy_grid/utils/conversions.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:uuid/uuid.dart';

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
  // ---------- Constants ----------

  static const _secondaryPanSlop = 4.0;

  // ---------- State ----------

  final _canvasController = LazyCanvasController(
    minScale: 0.5,
    maxScale: 2,
    buildExtentMultiplier: 3.4,
    useIdsFromArgs: true,
  );
  EditorSession get _session => widget.session!;
  CanvasBackgroundKind get _canvasBackgroundKind => widget.session?.document.background ?? CanvasBackgroundKind.dotGrid;
  AttachmentStore get _attachmentStore => widget.attachmentStore;
  final _elements = <CanvasElementModel>[];
  CanvasDocument? _projectedDocument;
  final MenuController _contextMenuController = MenuController();
  final GlobalKey _contextMenuKey = GlobalKey();
  final Object _contextMenuTapRegionGroup = Object();
  final _contextMenuFocusNode = FocusNode(debugLabel: 'Canvas context menu');
  List<CanvasElementModel> _contextMenuTargets = const [];
  ({int pointer, Offset start, CanvasElementModel? model, double slop})? _secondaryClick;
  (Offset, double)? _contextMenuView;
  Offset? _contextMenuPosition;
  bool _arrangeMenuOpen = false;
  FocusNode? _pasteField;
  final _geometryListeners = <CanvasElementModel, VoidCallback>{};
  CanvasElementModel? get _activeElement =>
      _elements.where((model) => model.data.id == widget.session?.activeId).firstOrNull;
  final _editingChromeModel = ValueNotifier<CanvasElementModel?>(null);
  final ValueNotifier<bool> _selectionModifierPressed = ValueNotifier(false);
  final _interactiveCanvasPointerIds = <int>{};
  final _selectionBeforeWidgetPointer = <Object>{};
  final _selectionKeys = <Object, GlobalKey>{};
  final _controlsOverlayController = OverlayPortalController();
  final GlobalKey _controlsPortalKey = GlobalKey();
  final _selectionBeforeDrag = <Object>{};
  int? _widgetPointer;
  bool _widgetTransforming = false;
  int? _dragSelectionPointer;
  Offset? _dragSelectionStart;
  Offset? _dragSelectionEnd;
  double _dragSelectionSlop = kPrecisePointerPanSlop;
  int? _dragArrowPointer;
  ArrowModel? _dragArrow;
  Offset _dragArrowStart = Offset.zero;
  double _dragArrowSlop = kPrecisePointerPanSlop;
  bool _dragArrowMoving = false;
  var _toggleDragSelection = false;
  bool get _documentLoaded => widget.session?.isLive == true && !widget.blocked;
  var _filePickerOpen = false;
  late final PenTool _penTool;
  late final ArrowTool _arrowTool;
  late final ShapeTool _shapeTool;
  double get _penWidth => _session.defaults.width;
  double get _penStreamline => _session.defaults.streamline;
  final ValueNotifier<CanvasTool> _activeTool = ValueNotifier(
    CanvasTool.select,
  );
  int? _eraserPointer;
  final _canvasPointers = <int, PointerDeviceKind>{};
  final _blockedCanvasPointers = <int>{};
  var _touchNavigationActive = false;
  ({int pointer, Offset start, CanvasTool tool, double slop})? _touchPlacement;
  ({int pointer, Offset start, double slop, VelocityTracker velocity})? _pointerPan;
  var _pointerPanStarted = false;
  var _touchControlsVisible = false;
  bool get _touchSelectionEnabled => widget.session?.touchSelectionEnabled ?? false;
  final _pageTouchPointers = <int>{};
  var _browserTouchObserved = false;
  late final VoidCallback _stopObservingBrowserTouch;
  var _spaceHeld = false;
  ClipboardEvents? _clipboardEvents;
  String? _lastPastedPayload;
  String? _cutPayload;
  Offset _pasteOffset = Offset.zero;
  final ValueNotifier<Offset?> _canvasPointerPosition = ValueNotifier(null);
  (String, Offset?)? _pointerReference;
  var _penColorPickerExpanded = false;
  var _shapeOutlineColorPickerExpanded = false;
  var _shapeFillColorPickerExpanded = false;
  var _arrowColorPickerExpanded = false;
  var _textColorPickerExpanded = false;

  Color get _penColor => widget.session?.defaults.color ?? defaultCanvasColor;

  bool get _penEnabled => _activeTool.value == CanvasTool.pen;

  bool get _arrowEnabled => _activeTool.value == CanvasTool.arrow;

  bool get _shapeEnabled => _activeTool.value == CanvasTool.shape;

  ValueChanged<Offset>? get _placementAction => switch (_activeTool.value) {
    CanvasTool.text => _addTextBlock,
    CanvasTool.code => _addCodeBlock,
    CanvasTool.media => _addMedia,
    _ => null,
  };

  bool get _placementEnabled => _placementAction != null;

  bool get _eraserEnabled => _activeTool.value == CanvasTool.eraser;

  TextBlockModel? get _activeTextBlock => switch (_activeElement) {
    final TextBlockModel model => model,
    _ => null,
  };

  CodeBlockModel? get _activeCodeBlock => switch (_activeElement) {
    final CodeBlockModel model => model,
    _ => null,
  };

  ShapeModel? get _activeShape => switch (_activeElement) {
    final ShapeModel model => model,
    _ => null,
  };

  ArrowModel? get _activeArrow => switch (_activeElement) {
    final ArrowModel model => model,
    _ => null,
  };

  // ---------- Lifecycle ----------

  @override
  void initState() {
    super.initState();
    widget.session?.addListener(_sessionChanged);
    _controlsOverlayController.show();
    _canvasController
      ..rawPointerDownListener = _handleCanvasPointerDown
      ..rawPointerMoveListener = _handleCanvasPointerMove
      ..rawPointerUpListener = _handleCanvasPointerUp
      ..rawPointerCancelListener = _handleCanvasPointerCancel
      ..addListener(_closeContextMenuOnNavigation);
    _penTool = PenTool(session: () => _session, onStroke: _addStroke);
    _arrowTool = ArrowTool(session: () => _session, onArrow: _addArrow)..addListener(_handleDrawingToolChanged);
    _shapeTool = ShapeTool(session: () => _session, onShape: _addShape)..addListener(_handleDrawingToolChanged);
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    FocusManager.instance.addListener(_handleEditorFocusChanged);
    GestureBinding.instance.pointerRouter.addGlobalRoute(_observePageTouch);
    _stopObservingBrowserTouch = observeBrowserTouch(
      onStart: () => _browserTouchObserved = true,
      onEnd: _revealTouchControls,
    );
    _clipboardEvents = widget.readClipboard == null && widget.writeClipboardText == null
        ? ClipboardEvents.instance
        : null;
    _clipboardEvents
      ?..registerCopyEventListener(_handleWebCopy)
      ..registerCutEventListener(_handleWebCut)
      ..registerPasteEventListener(_handleWebPaste);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_elements.isEmpty && widget.session != null) _sessionChanged();
    final platform = Theme.of(context).platform;
    if (platform == TargetPlatform.android || platform == TargetPlatform.iOS) _touchControlsVisible = true;
    final colors = BTheme.of(context).colors;
    _canvasController.background = _canvasBackgroundKind.build(colors);
  }

  FocusNode? _editorFocusNode(CanvasElementModel model) => switch (model) {
    final TextBlockModel text => text.focusNode,
    final CodeBlockModel code => code.focusNode,
    final MediaModel media => media.focusNode,
    _ => null,
  };

  void _handleEditorFocusChanged() {
    final node = FocusManager.instance.primaryFocus;
    if (node == null || identical(node, _pasteField) || widget.session == null) return;
    for (final model in _elements) {
      final field = switch (model) {
        final TextBlockModel text when identical(node, text.focusNode) => EditorField.markdown,
        final CodeBlockModel code when identical(node, code.focusNode) => EditorField.source,
        final CodeBlockModel code when identical(node, code.titleFocusNode) => EditorField.title,
        final MediaModel media when identical(node, media.focusNode) => EditorField.mediaUrl,
        _ => null,
      };
      if (field != null) {
        _session.editField((id: model.data.id, field: field));
        _pasteField = node;
        return;
      }
    }
    final context = node.context;
    if (context?.widget is EditableText || context?.findAncestorWidgetOfExactType<EditableText>() != null) {
      _session.editField(null);
      _invalidatePendingEdits();
      _pasteField = node;
    }
  }

  void _invalidatePendingEdits() {
    widget.session?.invalidatePendingEdits();
    _pasteField = null;
  }

  @override
  void dispose() {
    widget.session?.invalidatePendingEdits();
    widget.session?.removeListener(_sessionChanged);
    FocusManager.instance.removeListener(_handleEditorFocusChanged);
    _closeContextMenu();
    _contextMenuFocusNode.dispose();
    _canvasController.removeListener(_closeContextMenuOnNavigation);
    for (final model in _elements) {
      model.removeListener(_geometryListeners.remove(model)!);
      model.dispose();
    }
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_observePageTouch);
    _stopObservingBrowserTouch();
    _clipboardEvents
      ?..unregisterCopyEventListener(_handleWebCopy)
      ..unregisterCutEventListener(_handleWebCut)
      ..unregisterPasteEventListener(_handleWebPaste);
    _activeTool.dispose();
    _selectionModifierPressed.dispose();
    _editingChromeModel.dispose();
    _canvasPointerPosition.dispose();
    _penTool.dispose();
    _arrowTool
      ..removeListener(_handleDrawingToolChanged)
      ..dispose();
    _shapeTool
      ..removeListener(_handleDrawingToolChanged)
      ..dispose();
    _canvasController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(CanvasPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      oldWidget.session?.removeListener(_sessionChanged);
      _endCanvasInteraction();
      _detachModels(List.of(_elements));
      _projectedDocument = null;
      widget.session?.addListener(_sessionChanged);
      _sessionChanged();
    }
  }

  void _sessionChanged() {
    final session = widget.session;
    if (session == null) return;
    if (!identical(_projectedDocument, session.document)) {
      final previous = _projectedDocument;
      _projectedDocument = session.document;
      final values = {for (final value in session.document.elements) value.id: value};
      _detachModels(_elements.where((model) => values[model.data.id]?.runtimeType != model.data.runtimeType).toList());
      final models = {for (final model in _elements) model.data.id: model};
      for (final value in session.document.elements) {
        if (!models.containsKey(value.id)) _mountElement(_createElementModel(value));
      }
      final ordered = {for (final model in _elements) model.data.id: model};
      _elements
        ..clear()
        ..addAll(session.document.elements.map((value) => ordered[value.id]!));
      _canvasController.setChildOrder(session.document.elements.map((value) => value.id).toList());
      if (previous?.background != session.document.background) {
        _canvasController.background = session.document.background.build(BTheme.of(context).colors);
      }
    }
    _activeTool.value = session.tool;
    if (_activeElement case final active?) _editingChromeModel.value = active;
    if (mounted) setState(() {});
  }

  // ---------- Tool selection ----------

  void _handleDrawingToolChanged() {
    if (mounted) setState(() {});
  }

  void _toggleTool(CanvasTool tool) {
    if (!_documentLoaded) return;
    _applyTool(_activeTool.value != tool ? tool : CanvasTool.select);
    _finishHistoryOperation();
  }

  void _applyTool(CanvasTool tool, {bool touchSelectionEnabled = false}) {
    _endCanvasInteraction();
    _session.chooseTool(tool, touchSelectionEnabled: touchSelectionEnabled);
  }

  void _endCanvasInteraction({bool commitMediaDraft = true}) {
    _closeContextMenu();
    _blockedCanvasPointers.addAll(_canvasPointers.keys);
    _cancelDrawingTools();
    _touchPlacement = null;
    _pointerPan = null;
    _dragArrowPointer = null;
    _dragArrow = null;
    _widgetPointer = null;
    _interactiveCanvasPointerIds.clear();
    _selectionBeforeWidgetPointer.clear();
    _finishDragSelection(canceled: true);
    _finishHistoryOperation();
    _clearElementEditing(commitMediaDraft: commitMediaDraft);
    _eraserPointer = null;
    _spaceHeld = false;
  }

  void _toggleTouchSelection() {
    if (!_documentLoaded) return;
    _applyTool(CanvasTool.select, touchSelectionEnabled: !_touchSelectionEnabled);
    _finishHistoryOperation();
  }

  void _setPenColor(Color color) {
    _penTool.setColor(color);
  }

  void _setPenWidth(double width) {
    _penTool.setStrokeWidth(width);
  }

  void _setPenStreamline(double streamline) {
    _penTool.setStreamline(streamline);
  }

  void _setShapeStrokeColor(Color color) {
    _shapeTool.setStrokeColor(color);
  }

  void _setArrowColor(Color color) {
    _arrowTool.setColor(color);
  }

  void _editElement(CanvasElementModel model, VoidCallback edit) {
    if (!_elements.contains(model)) return;
    _finishHistoryOperation();
    edit();
    _finishHistoryOperation();
  }

  // ---------- Canvas pointer events ----------

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

  bool get _canvasPointersBlocked => _touchNavigationActive || _blockedCanvasPointers.isNotEmpty;

  bool get _canvasInputBlocked => _filePickerOpen || _canvasPointersBlocked;

  bool _canHandleCanvasPointer(PointerEvent event) {
    if (_canvasInputBlocked) return false;
    return event is! PointerDownEvent ||
        event.kind != PointerDeviceKind.touch ||
        !_canvasPointers.entries.any((entry) => entry.key != event.pointer && entry.value == PointerDeviceKind.touch);
  }

  void _cancelDrawingTools() {
    _penTool.cancel();
    _arrowTool.cancel();
    _shapeTool.cancel();
  }

  void _handleTouchNavigationChanged(bool active) {
    _touchNavigationActive = active;
    if (active) {
      _closeContextMenu();
      _blockedCanvasPointers.addAll(_canvasPointers.keys);
      _cancelDrawingTools();
      _touchPlacement = null;
      _pointerPan = null;
      _eraserPointer = null;
      _dragArrowPointer = null;
      _dragArrow = null;
      _widgetPointer = null;
      _interactiveCanvasPointerIds.clear();
      _selectionBeforeWidgetPointer.clear();
      _finishDragSelection(canceled: true);
      if (_widgetTransforming || widget.session?.editing == null) _finishHistoryOperation();
      _canvasPointerPosition.value = null;
    }
    if (mounted) setState(() {});
  }

  void _releaseCanvasPointer(int pointer) {
    // Gesture callbacks run after the raw listener, including final-up taps.
    scheduleMicrotask(() {
      _canvasPointers.remove(pointer);
      _blockedCanvasPointers.remove(pointer);
      _interactiveCanvasPointerIds.remove(pointer);
    });
  }

  void _handleObjectControlPointerDown(PointerDownEvent event) {
    if (_canHandleCanvasPointer(event)) _interactiveCanvasPointerIds.add(event.pointer);
  }

  bool _tryPlaceActiveTool(Offset position) {
    final place = _placementAction;
    if (place == null) return false;
    place(position);
    return true;
  }

  Offset _screenToCanvas(Offset screenPosition) => _canvasController.offset + screenPosition / _canvasController.scale;

  void _handleCanvasPointerDown(PointerDownEvent event) {
    final allowed = _canHandleCanvasPointer(event);
    _canvasPointers[event.pointer] = event.kind;
    if (_canvasInputBlocked) _blockedCanvasPointers.add(event.pointer);
    if (!_documentLoaded || !allowed) return;
    _canvasPointerPosition.value = event.localPosition;
    if (_eraserEnabled && !_spaceHeld) {
      if (_eraserPointer == null && (event.kind != PointerDeviceKind.mouse || event.buttons == kPrimaryButton)) {
        _eraserPointer = event.pointer;
        _eraseAt(event.position);
      }
      return;
    }
    if (_penEnabled && !_spaceHeld) {
      _penTool.onPointerDown(event);
      return;
    }
    if (event.kind == PointerDeviceKind.mouse &&
        event.buttons == kSecondaryButton &&
        _activeTool.value == CanvasTool.select) {
      _secondaryClick ??= (
        pointer: event.pointer,
        start: event.position,
        model: null,
        slop: _secondaryPanSlop,
      );
      _canvasController.stopAnimation();
      _pointerPan = (
        pointer: event.pointer,
        start: event.localPosition,
        slop: _secondaryPanSlop,
        velocity: VelocityTracker.withKind(event.kind)..addPosition(event.timeStamp, event.localPosition),
      );
      _pointerPanStarted = false;
      return;
    }
    if (event.buttons != kPrimaryButton) return;
    final onInteractiveChild = _interactiveCanvasPointerIds.remove(
      event.pointer,
    );
    final position = _screenToCanvas(event.localPosition);
    if (_placementEnabled && event.kind == PointerDeviceKind.touch) {
      _touchPlacement = (
        pointer: event.pointer,
        start: event.localPosition,
        tool: _activeTool.value,
        slop: computePanSlop(event.kind, MediaQuery.maybeGestureSettingsOf(context)),
      );
      return;
    }
    if (_tryPlaceActiveTool(position)) return;
    if (onInteractiveChild) {
      if (!_selectionModifierPressed.value) {
        _selectionBeforeWidgetPointer
          ..clear()
          ..addAll(_selectedModels());
        _widgetPointer = event.pointer;
        _widgetTransforming = false;
        _setSelection(const {}, preserveContext: true);
      }
      return;
    }
    if (_arrowEnabled) {
      _arrowTool.onPointerDown(event, position);
      return;
    }
    if (_shapeEnabled) {
      _shapeTool.onPointerDown(event, position);
      return;
    }
    if (event.kind == PointerDeviceKind.touch &&
        _activeTool.value == CanvasTool.select &&
        !_touchSelectionEnabled &&
        !_spaceHeld) {
      _pointerPan = (
        pointer: event.pointer,
        start: event.localPosition,
        slop: computePanSlop(event.kind, MediaQuery.maybeGestureSettingsOf(context)),
        velocity: VelocityTracker.withKind(event.kind)..addPosition(event.timeStamp, event.localPosition),
      );
      _pointerPanStarted = false;
      return;
    }
    final touchSelection = event.kind == PointerDeviceKind.touch && _touchSelectionEnabled;
    if (!touchSelection) _clearElementEditing();
    _selectionBeforeDrag
      ..clear()
      ..addAll(_selectedModels());
    _toggleDragSelection = !touchSelection && _selectionModifierPressed.value;
    if (!touchSelection && !_toggleDragSelection) _clearSelection();
    if ((!touchSelection && event.kind != PointerDeviceKind.mouse) || _penEnabled || _eraserEnabled) {
      return;
    }
    setState(() {
      _dragSelectionPointer = event.pointer;
      _dragSelectionStart = event.localPosition;
      _dragSelectionEnd = null;
      _dragSelectionSlop = computePanSlop(event.kind, MediaQuery.maybeGestureSettingsOf(context));
    });
  }

  void _handleCanvasPointerMove(PointerMoveEvent event) {
    if (_secondaryClick case final click? when click.pointer == event.pointer) {
      if ((event.position - click.start).distance > click.slop) _secondaryClick = null;
    }
    if (!_canHandleCanvasPointer(event)) return;
    if (_pointerPan case final pan? when pan.pointer == event.pointer) {
      pan.velocity.addPosition(event.timeStamp, event.localPosition);
      final displacement = event.localPosition - pan.start;
      if (!_pointerPanStarted && displacement.distance <= pan.slop) return;
      if (!_pointerPanStarted) {
        _canvasController.onScaleStart(ScaleStartDetails(localFocalPoint: pan.start));
      }
      _canvasController.onScaleUpdate(
        ScaleUpdateDetails(
          localFocalPoint: event.localPosition,
          focalPointDelta: _pointerPanStarted ? event.localDelta : displacement,
        ),
      );
      _pointerPanStarted = true;
      return;
    }
    if (_touchPlacement case final placement? when placement.pointer == event.pointer) {
      if ((event.localPosition - placement.start).distance > placement.slop) _touchPlacement = null;
      return;
    }
    _canvasPointerPosition.value = event.localPosition;
    if (_penEnabled) {
      _penTool.onPointerUpdate(event);
      return;
    }
    if (event.pointer == _eraserPointer) {
      _eraseAt(event.position);
      return;
    }
    if (_arrowTool.ownsPointer(event.pointer)) {
      _arrowTool.onPointerMove(
        event,
        _screenToCanvas(event.localPosition),
      );
      return;
    }
    if (_shapeTool.ownsPointer(event.pointer)) {
      _shapeTool.onPointerMove(
        event,
        _screenToCanvas(event.localPosition),
      );
      return;
    }
    if (event.pointer == _dragArrowPointer) {
      final arrow = _dragArrow;
      if (arrow != null) {
        final displacement = event.position - _dragArrowStart;
        if (!_dragArrowMoving && displacement.distance <= _dragArrowSlop) return;
        _moveSelectedChildren(arrow, _dragArrowMoving ? event.delta : displacement);
        _dragArrowMoving = true;
      }
      return;
    }
    if (event.pointer != _dragSelectionPointer) return;
    _updateDragSelection(event.localPosition);
  }

  void _handleCanvasPointerUp(PointerUpEvent event) {
    if (_secondaryClick case final click? when click.pointer == event.pointer) {
      _secondaryClick = null;
      if (_canHandleCanvasPointer(event) && (event.position - click.start).distance <= click.slop) {
        _openCanvasContextMenu(click.model, event.position);
      }
    }
    _releaseCanvasPointer(event.pointer);
    if (!_canHandleCanvasPointer(event)) return;
    if (_pointerPan case final pan? when pan.pointer == event.pointer) {
      _pointerPan = null;
      if (_pointerPanStarted) {
        pan.velocity.addPosition(event.timeStamp, event.localPosition);
        _canvasController.onScaleEnd(ScaleEndDetails(velocity: pan.velocity.getVelocity()));
      } else if (event.kind == PointerDeviceKind.touch && (event.localPosition - pan.start).distance <= pan.slop) {
        _clearElementEditing();
        _clearSelection();
      }
      return;
    }
    if (_touchPlacement case final placement? when placement.pointer == event.pointer) {
      _touchPlacement = null;
      if (placement.tool == _activeTool.value && (event.localPosition - placement.start).distance <= placement.slop) {
        _tryPlaceActiveTool(_screenToCanvas(event.localPosition));
      }
      return;
    }
    if (_penEnabled) {
      _penTool.onPointerUp(event);
      return;
    }
    if (event.pointer == _eraserPointer) {
      _eraserPointer = null;
      _finishHistoryOperation();
      return;
    }
    _finishWidgetPointer(event.pointer);
    if (_arrowTool.ownsPointer(event.pointer)) {
      _arrowTool.onPointerUp(
        event,
        _screenToCanvas(event.localPosition),
      );
      return;
    }
    if (_shapeTool.ownsPointer(event.pointer)) {
      _shapeTool.onPointerUp(
        event,
        _screenToCanvas(event.localPosition),
      );
      return;
    }
    if (event.pointer == _dragArrowPointer) {
      if (!_dragArrowMoving && _dragArrow != null) _activateElement(_dragArrow!);
      _finishArrowDrag();
      return;
    }
    if (event.pointer != _dragSelectionPointer) return;
    _updateDragSelection(event.localPosition);
    if (event.kind == PointerDeviceKind.touch && _dragSelectionEnd == null) {
      _clearElementEditing();
      _clearSelection();
    }
    _finishDragSelection();
  }

  void _handleCanvasPointerCancel(PointerCancelEvent event) {
    if (_secondaryClick?.pointer == event.pointer) _secondaryClick = null;
    _releaseCanvasPointer(event.pointer);
    if (_touchPlacement?.pointer == event.pointer) _touchPlacement = null;
    if (_pointerPan?.pointer == event.pointer) _pointerPan = null;
    if (!_canHandleCanvasPointer(event)) return;
    if (_penEnabled) {
      _penTool.onPointerCancel(event);
      return;
    }
    if (event.pointer == _eraserPointer) {
      _eraserPointer = null;
      _finishHistoryOperation();
      return;
    }
    _finishWidgetPointer(event.pointer);
    if (_arrowTool.ownsPointer(event.pointer)) {
      _arrowTool.onPointerCancel(event);
      return;
    }
    if (_shapeTool.ownsPointer(event.pointer)) {
      _shapeTool.onPointerCancel(event);
      return;
    }
    if (event.pointer == _dragArrowPointer) {
      _finishArrowDrag();
      return;
    }
    if (event.pointer != _dragSelectionPointer) return;
    _finishDragSelection(canceled: true);
  }

  // ---------- Selection ----------

  void _updateDragSelection(Offset end) {
    final start = _dragSelectionStart;
    if (start == null) return;
    if (_dragSelectionEnd == null && (end - start).distance <= _dragSelectionSlop) {
      return;
    }
    if (_dragSelectionEnd == null) _clearElementEditing();
    setState(() => _dragSelectionEnd = end);
    final rect = Rect.fromPoints(start, end);
    bool selected(CanvasElementModel model) {
      final info = _canvasController.getInfo(model.data.id);
      final size = info.childSize;
      final overlaps = size != null && _selectionRectOverlaps(rect, info, size);
      return _toggleDragSelection ? _selectionBeforeDrag.contains(model) != overlaps : overlaps;
    }

    _setSelection(_elements.where(selected).toSet());
  }

  bool _selectionRectOverlaps(Rect selection, ChildInfo info, Size size) {
    return transformedRectOverlaps(
      selection,
      size,
      childTransform(
        info.ssPosition,
        size,
        info.rotation,
        scale: _canvasController.scale,
      ).storage,
    );
  }

  void _finishDragSelection({bool canceled = false}) {
    if (_dragSelectionPointer == null) return;
    if (canceled) _setSelection(_selectionBeforeDrag);
    setState(() {
      _dragSelectionPointer = null;
      _dragSelectionStart = null;
      _dragSelectionEnd = null;
      _selectionBeforeDrag.clear();
    });
  }

  void _finishWidgetPointer(int pointer) {
    if (pointer != _widgetPointer) return;
    // Tap callbacks run after the raw up listener and still need the selection snapshot.
    scheduleMicrotask(() {
      if (!mounted || pointer != _widgetPointer) return;
      _widgetPointer = null;
      _selectionBeforeWidgetPointer.clear();
      if (_widgetTransforming || widget.session?.editing == null) _finishHistoryOperation();
      _widgetTransforming = false;
    });
  }

  bool _toggleSelectionIfModifierPressed(CanvasElementModel model) {
    if (!_selectionModifierPressed.value) return false;
    _invalidatePendingEdits();
    _finishHistoryOperation();
    final selection = _selectedModels();
    if (!selection.remove(model)) selection.add(model);
    _setSelection(selection);
    _promoteAuto([model]);
    _finishHistoryOperation();
    return true;
  }

  void _handleCodeBlockPointerDown(
    CodeBlockModel model,
    PointerDownEvent event,
  ) {
    if (!_canHandleCanvasPointer(event)) return;
    if (event.buttons != kPrimaryButton || !_documentLoaded || _placementEnabled || _penEnabled || _eraserEnabled) {
      return;
    }
    _interactiveCanvasPointerIds.add(event.pointer);
    if (!_elements.contains(model)) return;
    if (_toggleSelectionIfModifierPressed(model)) return;
    if (!model.active) {
      if (!model.selected) _invalidatePendingEdits();
      _setActiveElement(null);
    }
    _clearTextEditing();
  }

  void _editCodeBlock(CodeBlockModel model) {
    if (_canvasInputBlocked) return;
    if (!_documentLoaded || _placementEnabled || _penEnabled || _eraserEnabled || !_elements.contains(model)) {
      return;
    }
    _clearTextEditing();
    _setActiveElement(model);
    // re_editor does not restart cursor/input state when readOnly changes while focused.
    // Refocus after the editable frame so the first click shows a working caret.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && model.active && _elements.contains(model)) {
        model.focusNode.unfocus();
        FocusManager.instance.applyFocusChangesIfNeeded();
        model.focusNode.requestFocus();
      }
    });
  }

  void _handleTextBlockPointerDown(
    TextBlockModel model,
    PointerDownEvent event,
  ) {
    if (!_canHandleCanvasPointer(event)) return;
    if (event.buttons != kPrimaryButton || _placementEnabled || _penEnabled || _eraserEnabled) {
      return;
    }
    _interactiveCanvasPointerIds.add(event.pointer);
    if (!_elements.contains(model)) return;
    if (_toggleSelectionIfModifierPressed(model)) return;
    if (!model.active) {
      if (!model.selected) _invalidatePendingEdits();
      _setActiveElement(null);
    }
    if (!model.editing) {
      FocusManager.instance.primaryFocus?.unfocus();
      _clearTextEditing();
    }
  }

  void _handleSelectableElementPointerDown(
    CanvasElementModel model,
    PointerDownEvent event,
  ) {
    if (!_canHandleCanvasPointer(event)) return;
    if (event.buttons != kPrimaryButton ||
        !_documentLoaded ||
        _activeTool.value != CanvasTool.select ||
        !_elements.contains(model)) {
      return;
    }
    _interactiveCanvasPointerIds.add(event.pointer);
    if (_toggleSelectionIfModifierPressed(model)) return;
    if (!model.active) {
      if (!model.selected) _invalidatePendingEdits();
      _setActiveElement(null);
    }
    final editingMediaPath = model is MediaModel && !model.hasImage && model.focusNode.hasFocus;
    if (!editingMediaPath) FocusManager.instance.primaryFocus?.unfocus();
    _clearTextEditing();
  }

  void _activateElement(CanvasElementModel model) {
    if (_canvasInputBlocked) return;
    if (!_documentLoaded || _activeTool.value != CanvasTool.select || !_elements.contains(model)) return;
    _clearTextEditing();
    _setActiveElement(model);
  }

  void _editTextBlock(TextBlockModel model) {
    if (_canvasInputBlocked) return;
    if (!_documentLoaded || _placementEnabled || _penEnabled || _eraserEnabled || !_elements.contains(model)) {
      return;
    }
    _startTextEditing(model);
    model.focusNode.requestFocus();
  }

  void _startTextEditing(TextBlockModel editing) {
    _setActiveElement(editing);
    _session.editField((id: editing.data.id, field: EditorField.markdown));
    _editingChromeModel.value = editing;
  }

  void _clearTextEditing() {
    if (widget.session?.editing?.field == EditorField.markdown) _session.editField(null);
  }

  void _clearElementEditing({bool commitMediaDraft = true}) {
    _invalidatePendingEdits();
    if (commitMediaDraft) {
      for (final model in _elements.whereType<MediaModel>()) {
        if (model.focusNode.hasFocus) model.commitUrl();
      }
    }
    widget.session?.editField(null);
    FocusManager.instance.primaryFocus?.unfocus();
    _setActiveElement(null);
  }

  void _setActiveElement(CanvasElementModel? model) {
    if (widget.session == null) return;
    if (model != null) _promoteAuto([model]);
    _session.setActive(model?.data.id);
    if (model != null) _editingChromeModel.value = model;
  }

  void _clearSelection() {
    _setSelection(const <Object>{});
  }

  void _setSelection(Set<Object> selection, {bool preserveContext = false}) {
    widget.session?.setSelection(
      selection.cast<CanvasElementModel>().map((model) => model.data.id),
      preserveContext: preserveContext,
    );
  }

  Set<Object> _selectedModels() => {
    ..._elements.where((model) => model.selected),
  };

  // ---------- Object context menu and ordering ----------

  List<CanvasElementModel> get _arrangeTargets {
    if (_contextMenuController.isOpen) return _contextMenuTargets;
    final selected = _selectedInStackingOrder;
    return selected.isNotEmpty ? selected : [?_activeElement];
  }

  void _handleObjectSecondaryDown(CanvasElementModel model, PointerDownEvent event) {
    if (!_documentLoaded ||
        !_canHandleCanvasPointer(event) ||
        _activeTool.value != CanvasTool.select ||
        event.buttons != kSecondaryButton) {
      return;
    }
    _secondaryClick = (
      pointer: event.pointer,
      start: event.position,
      model: model,
      slop: event.kind == PointerDeviceKind.mouse
          ? _secondaryPanSlop
          : computePanSlop(event.kind, MediaQuery.maybeGestureSettingsOf(context)),
    );
  }

  void _openArrangeMenu(CanvasElementModel model, Rect buttonBounds) {
    if (_canvasInputBlocked || !_elements.contains(model) || _activeTool.value != CanvasTool.select) return;
    final selection = _widgetPointer == null ? _selectedModels() : _selectionBeforeWidgetPointer;
    if (selection.contains(model) && selection.length > 1) {
      _setSelection(selection);
      // TODO(zero): Selected groups need their own menu for move, rotate, arrange, and delete.
      throw UnimplementedError('Arrange controls for selected groups');
    }
    _setSelection({model});
    final left = buttonBounds.left - ContextMenu.width - 4;
    final position = Offset(
      left >= MediaQuery.paddingOf(context).left ? left : buttonBounds.right + 4,
      buttonBounds.top,
    );
    _openCanvasContextMenu(model, position, arrangeOnly: true);
  }

  void _openCanvasContextMenu(CanvasElementModel? model, Offset position, {bool arrangeOnly = false}) {
    if ((model != null && !_elements.contains(model)) || _activeTool.value != CanvasTool.select) return;
    _clearElementEditing();
    if (model != null) _promoteAuto([model]);
    _finishHistoryOperation();
    if (model != null && !model.selected) _setSelection({model});
    _contextMenuTargets = model == null ? const [] : _selectedInStackingOrder;
    _arrangeMenuOpen = arrangeOnly;
    final box = _contextMenuKey.currentContext!.findRenderObject()! as RenderBox;
    _contextMenuPosition = _screenToCanvas(box.globalToLocal(position));
    _contextMenuView = (_canvasController.offset, _canvasController.scale);
    setState(() {});
    // Build the captured targets before opening; editor release callbacks finish first.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _contextMenuPosition == null) return;
      final box = _contextMenuKey.currentContext!.findRenderObject()! as RenderBox;
      _contextMenuController.open(position: box.globalToLocal(position));
      _contextMenuFocusNode.requestFocus();
    });
  }

  void _handleContextMenuOutsideTap(PointerDownEvent event) {
    _contextMenuController.close();
    // Canvas presses already capture selection for group dragging before clearing it.
    if (!_canvasPointers.containsKey(event.pointer) &&
        event.buttons == kPrimaryButton &&
        !_selectionModifierPressed.value) {
      _clearSelection();
    }
  }

  void _contextMenuClosed() {
    _contextMenuTargets = const [];
    _contextMenuView = null;
    _contextMenuPosition = null;
    _arrangeMenuOpen = false;
    _contextMenuFocusNode.unfocus();
  }

  void _closeContextMenu() {
    _secondaryClick = null;
    _contextMenuController.close();
    _contextMenuClosed();
  }

  void _closeContextMenuOnNavigation() {
    if (_contextMenuView case final view? when view != (_canvasController.offset, _canvasController.scale)) {
      _closeContextMenu();
    }
  }

  bool _canArrange(CanvasArrange action, List<CanvasElementModel> targets) {
    if (targets.isEmpty || targets.any((model) => !_elements.contains(model))) return false;
    try {
      return _canvasController.canArrange(targets.map((model) => model.data.id), action) ||
          targets.any((model) => model.autoArrange);
      // The ordering API documents unknown layout sizes as a StateError.
      // ignore: avoid_catching_errors
    } on StateError {
      if (action == CanvasArrange.forward || action == CanvasArrange.backward) {
        return false;
      }
      rethrow;
    }
  }

  void _arrange(CanvasArrange action, List<CanvasElementModel> targets) {
    if (!_canArrange(action, targets)) return;
    _finishHistoryOperation();
    final ids = targets.map((model) => model.data.id).toList();
    _session.arrange(ids, _canvasController.arrangedOrder(ids, action));
    _finishHistoryOperation();
  }

  void _setAutoArrange(List<CanvasElementModel> targets, bool value) {
    if (targets.isEmpty || targets.any((model) => !_elements.contains(model))) return;
    _finishHistoryOperation();
    _session.setAutoArrange(targets.map((model) => model.data.id), value: value);
    _finishHistoryOperation();
  }

  void _promoteAuto(Iterable<CanvasElementModel> targets, {bool contentChanged = false}) {
    if (!_documentLoaded || (!contentChanged && _canvasInputBlocked)) return;
    _session.promoteAuto(targets.where(_elements.contains).map((model) => model.data.id));
  }

  bool get _canCopyDirectly => widget.writeClipboardText != null || SystemClipboard.instance != null;

  bool get _canPasteDirectly => widget.readClipboard != null || SystemClipboard.instance != null;

  void _dispatchContextMenuAction(VoidCallback action) {
    _closeContextMenu();
    action();
  }

  List<List<ContextMenuAction>> _arrangeContextMenuActions() {
    final targets = _contextMenuTargets;
    final macOS = Theme.of(context).platform == TargetPlatform.macOS;
    final auto = targets.isNotEmpty && targets.every((model) => model.autoArrange);
    ContextMenuAction arrange(CanvasArrange action, String label, IconData icon) {
      final enabled = _canArrange(action, targets);
      return ContextMenuAction(
        label: label,
        icon: icon,
        onPressed: enabled ? () => _dispatchContextMenuAction(() => _arrange(action, targets)) : null,
        shortcut: SingleActivator(
          action == CanvasArrange.forward || action == CanvasArrange.front
              ? LogicalKeyboardKey.bracketRight
              : LogicalKeyboardKey.bracketLeft,
          meta: macOS,
          control: !macOS,
          shift: action == CanvasArrange.front || action == CanvasArrange.back,
        ),
      );
    }

    return [
      [
        ContextMenuAction.toggle(
          label: 'Auto',
          value: auto,
          focusNode: _arrangeMenuOpen ? _contextMenuFocusNode : null,
          onPressed: () => _dispatchContextMenuAction(() => _setAutoArrange(targets, !auto)),
        ),
      ],
      [
        arrange(CanvasArrange.forward, 'Bring Forward', LucideIcons.arrowUp),
        arrange(CanvasArrange.backward, 'Send Backward', LucideIcons.arrowDown),
      ],
      [
        arrange(CanvasArrange.front, 'Bring to Front', LucideIcons.bringToFront),
        arrange(CanvasArrange.back, 'Send to Back', LucideIcons.sendToBack),
      ],
    ];
  }

  List<List<ContextMenuAction>> _objectContextMenuActions() {
    final targets = _contextMenuTargets;
    final position = _contextMenuPosition;
    final macOS = Theme.of(context).platform == TargetPlatform.macOS;
    SingleActivator shortcut(LogicalKeyboardKey key) => SingleActivator(key, meta: macOS, control: !macOS);
    return [
      [
        if (targets.isNotEmpty) ...[
          ContextMenuAction(
            label: 'Cut',
            icon: LucideIcons.scissors,
            shortcut: shortcut(LogicalKeyboardKey.keyX),
            focusNode: _canCopyDirectly ? _contextMenuFocusNode : null,
            onPressed: _canCopyDirectly
                ? () => _dispatchContextMenuAction(() => unawaited(_copySelection(null, cut: true, targets: targets)))
                : null,
          ),
          ContextMenuAction(
            label: 'Copy',
            icon: LucideIcons.copy,
            shortcut: shortcut(LogicalKeyboardKey.keyC),
            onPressed: _canCopyDirectly
                ? () => _dispatchContextMenuAction(() => unawaited(_copySelection(null, targets: targets)))
                : null,
          ),
        ],
        ContextMenuAction(
          label: 'Paste',
          icon: LucideIcons.clipboardPaste,
          shortcut: shortcut(LogicalKeyboardKey.keyV),
          focusNode: (targets.isEmpty || !_canCopyDirectly) && _canPasteDirectly ? _contextMenuFocusNode : null,
          onPressed: _canPasteDirectly
              ? () => _dispatchContextMenuAction(() => unawaited(_pasteSelection(null, position: position)))
              : null,
        ),
      ],
      if (targets.isNotEmpty) ...[
        [
          ContextMenuAction(
            label: 'Arrange',
            icon: LucideIcons.layers,
            focusNode: !_canCopyDirectly && !_canPasteDirectly ? _contextMenuFocusNode : null,
            groups: _arrangeContextMenuActions(),
          ),
        ],
        [
          ContextMenuAction(
            label: 'Delete',
            icon: LucideIcons.trash2,
            destructive: true,
            shortcut: SingleActivator(macOS ? LogicalKeyboardKey.backspace : LogicalKeyboardKey.delete),
            onPressed: () => _dispatchContextMenuAction(() => _removeElements(targets)),
          ),
        ],
      ],
    ];
  }

  // ---------- Element transforms ----------

  GlobalKey _selectionKey(Object model) => _selectionKeys.putIfAbsent(model, GlobalKey.new);

  void _moveSelectedChildren(CanvasElementModel dragged, Offset screenDelta) {
    if (_canvasInputBlocked) return;
    if (!_documentLoaded ||
        _placementEnabled ||
        _penEnabled ||
        _eraserEnabled ||
        _selectionModifierPressed.value ||
        screenDelta == Offset.zero) {
      return;
    }

    final selectedBeforeWidgetPointer = _selectionBeforeWidgetPointer;
    final draggedWasSelected = selectedBeforeWidgetPointer.contains(dragged);
    if (draggedWasSelected) _setSelection(selectedBeforeWidgetPointer, preserveContext: true);

    final draggedSelected = draggedWasSelected || (_elements.contains(dragged) && dragged.selected);

    if (!draggedSelected) _clearSelection();

    final gridDelta = screenDelta / _canvasController.scale;
    final affected = _elements
        .where(
          (model) => identical(model, dragged) || draggedSelected && model.selected,
        )
        .toList();

    if (affected.isEmpty) return;
    _beginWidgetTransform();
    _session.move(affected.map((model) => model.data.id), gridDelta);
  }

  void _beginWidgetTransform() {
    if (_widgetTransforming) return;
    _finishHistoryOperation();
    _widgetTransforming = true;
  }

  void _resizeTextBlock(TextBlockModel model, Size renderedSize, Offset screenDelta) {
    if (_canvasInputBlocked || !_documentLoaded || !_elements.contains(model)) return;
    _beginWidgetTransform();
    _session.resizeText(model.data.id, renderedSize, _localTransformDelta(model.rotation, screenDelta));
  }

  void _resizeCodeBlock(CodeBlockModel model, Offset localDelta) {
    if (_canvasInputBlocked || !_documentLoaded || !_elements.contains(model)) return;
    _beginWidgetTransform();
    _session.resizeCode(model.data.id, Size(model.size.width + localDelta.dx, model.size.height + localDelta.dy));
  }

  void _resizeMedia(MediaModel model, Offset screenDelta) {
    if (_canvasInputBlocked || !_documentLoaded || !_elements.contains(model) || model.aspectRatio == null) return;
    _beginWidgetTransform();
    _session.resizeMedia(model.data.id, _localTransformDelta(model.rotation, screenDelta), model.aspectRatio!);
  }

  void _resizeShape(ShapeModel model, Offset screenDelta) {
    if (_canvasInputBlocked || !_documentLoaded || !_elements.contains(model)) return;
    if (_selectionBeforeWidgetPointer.contains(model)) _setSelection(_selectionBeforeWidgetPointer);
    _beginWidgetTransform();
    _session.resizeShape(model.data.id, screenDelta / _canvasController.scale);
  }

  Offset _localTransformDelta(double rotation, Offset screenDelta) =>
      screenDeltaToLocal(screenDelta, scale: _canvasController.scale, rotation: rotation);

  void _rotateElement(RotatableCanvasElementModel model, double angle) {
    if (_canvasInputBlocked || !_documentLoaded || !_elements.contains(model)) return;
    _beginWidgetTransform();
    _session.rotate(model.data.id, angle);
  }

  Offset _elementCenter(CanvasElementModel model) {
    final renderObject = _selectionKey(
      model,
    ).currentContext?.findRenderObject();
    if (renderObject is! RenderBox) return Offset.zero;
    final center = model is CodeBlockModel
        ? Offset(model.size.width / 2, model.canvasSize.height - model.size.height / 2)
        : renderObject.size.center(Offset.zero);
    return renderObject.localToGlobal(center);
  }

  // ---------- Element creation ----------

  BlockBackgroundKind get _newBlockBackground =>
      BTheme.of(context).surfaceStyle == SurfaceStyle.glass ? BlockBackgroundKind.glass : BlockBackgroundKind.card;

  void _addTextBlock(Offset position) {
    if (!_documentLoaded) return;
    final node = TextElementData(
      id: const Uuid().v4(),
      position: position,
      width: textNodeDefaultWidth,
      height: textNodeDefaultHeight,
      markdown: '',
      style: TextNodeStyle(
        fontFamily: defaultFontFamily,
        color: defaultCanvasColor,
        background: _newBlockBackground,
      ),
    );
    _session.insert([node], returnToSelect: true);
    final model = _elements.whereType<TextBlockModel>().firstWhere((model) => model.data.id == node.id);
    model.focusNode.requestFocus();
    _startTextEditing(model);
  }

  void _addMedia(Offset position) {
    if (!_documentLoaded) return;
    final value = _newMediaData('').copyWith(position: position);
    _session.insert([value], returnToSelect: true);
    final model = _elements.firstWhere((model) => model.data.id == value.id);
    _setActiveElement(model);
    _editorFocusNode(model)?.requestFocus();
  }

  CanvasElementModel _createElementModel(CanvasElementData data) {
    return switch (data) {
      final TextElementData data => TextBlockModel(_session, data),
      final CodeElementData data => CodeBlockModel(_session, data),
      final MediaElementData data => MediaModel(_session, data, _attachmentStore),
      final ShapeElementData data => ShapeModel(_session, data),
      final PenElementData data => PenStrokeModel(_session, data),
      final ArrowElementData data => ArrowModel(_session, data),
    };
  }

  void _mountElement(CanvasElementModel model) {
    _elements.add(model);
    final child = switch (model) {
      final TextBlockModel text => _CanvasElementHost(
        key: _selectionKey(text),
        model: text,
        activeTool: _activeTool,
        modifierPressed: _selectionModifierPressed,
        onSecondaryPointerDown: (event) => _handleObjectSecondaryDown(model, event),
        onPointerDown: (event) => _handleTextBlockPointerDown(text, event),
        child: TextTool(
          model: text,
          attachmentStore: _attachmentStore,
          onEdit: () => _editTextBlock(text),
          onInteract: () => _promoteAuto([text]),
          onMove: (delta) => _moveSelectedChildren(text, delta),
          onResize: (size, delta) => _resizeTextBlock(text, size, delta),
        ),
      ),
      final CodeBlockModel code => _CanvasElementHost(
        key: _selectionKey(code),
        model: code,
        activeTool: _activeTool,
        modifierPressed: _selectionModifierPressed,
        onSecondaryPointerDown: (event) => _handleObjectSecondaryDown(model, event),
        onPointerDown: (event) => _handleCodeBlockPointerDown(code, event),
        child: CodeTool(
          model: code,
          onEdit: () => _editCodeBlock(code),
          onInteract: () => _promoteAuto([code]),
          onMove: (delta) => _moveSelectedChildren(code, delta),
          onResize: (delta) => _resizeCodeBlock(code, delta),
          onChangeBoundary: _finishHistoryOperation,
          onControlPointerDown: _handleObjectControlPointerDown,
          canHandlePointer: _canHandleCanvasPointer,
        ),
      ),
      final MediaModel media => _CanvasElementHost(
        key: _selectionKey(media),
        model: media,
        activeTool: _activeTool,
        modifierPressed: _selectionModifierPressed,
        onSecondaryPointerDown: (event) => _handleObjectSecondaryDown(model, event),
        onPointerDown: (event) => _handleSelectableElementPointerDown(media, event),
        child: MediaTool(
          model: media,
          onActivate: () => _activateElement(media),
          onMove: (delta) => _moveSelectedChildren(media, delta),
          onResize: (delta) => _resizeMedia(media, delta),
          onPanelPointerDown: (event) {
            _handleObjectControlPointerDown(event);
            _handleObjectSecondaryDown(media, event);
          },
          onDeactivate: () {
            if (_contextMenuController.isOpen || _secondaryClick != null) return;
            if (identical(_activeElement, media)) _setActiveElement(null);
          },
        ),
      ),
      final ShapeModel shape => _CanvasElementHost(
        key: _selectionKey(shape),
        model: shape,
        activeTool: _activeTool,
        modifierPressed: _selectionModifierPressed,
        onSecondaryPointerDown: (event) => _handleObjectSecondaryDown(model, event),
        onPointerDown: (event) => _handleSelectableElementPointerDown(shape, event),
        child: Shape(
          model: shape,
          onActivate: () => _activateElement(shape),
          onMove: (delta) => _moveSelectedChildren(shape, delta),
          onResize: (delta) => _resizeShape(shape, delta),
        ),
      ),
      final PenStrokeModel pen => _CanvasElementHost(
        key: _selectionKey(pen),
        model: pen,
        activeTool: _activeTool,
        modifierPressed: _selectionModifierPressed,
        onSecondaryPointerDown: (event) => _handleObjectSecondaryDown(model, event),
        onPointerDown: (event) => _handleStrokePointerDown(pen, event),
        child: PenStroke(
          model: pen,
          onTap: () {
            if (_activeTool.value == CanvasTool.select) _promoteAuto([pen]);
          },
          onMove: (delta) => _moveSelectedChildren(pen, delta),
        ),
      ),
      final ArrowModel arrow => _CanvasElementHost(
        key: _selectionKey(arrow),
        model: arrow,
        activeTool: _activeTool,
        modifierPressed: _selectionModifierPressed,
        onSecondaryPointerDown: (event) => _handleObjectSecondaryDown(model, event),
        onPointerDown: (event) => _handleArrowPointerDown(arrow, event),
        child: Arrow(model: arrow),
      ),
      _ => throw StateError('Unknown canvas element model'),
    };
    _canvasController.addChild(
      model.canvasPosition,
      // The portal must sit beneath the canvas transform to read current layout geometry.
      ListenableBuilder(
        listenable: Listenable.merge([_editingChromeModel, model]),
        child: child,
        builder: (context, child) => Stack(
          clipBehavior: Clip.none,
          children: [
            child!,
            if (identical(_editingChromeModel.value, model)) Positioned.fill(child: _buildControlsPortal()),
          ],
        ),
      ),
      id: model.data.id,
      childSize: model.canvasSize,
      rotation: model is RotatableCanvasElementModel ? model.rotation : 0,
    );
    var declaredSize = model.canvasSize;
    void syncGeometry() {
      final size = model.canvasSize;
      _canvasController.update(
        model.data.id,
        position: model.canvasPosition,
        rotation: model is RotatableCanvasElementModel ? model.rotation : 0,
        childSize: size != declaredSize ? size : null,
      );
      declaredSize = size;
    }

    _geometryListeners[model] = syncGeometry;
    model.addListener(syncGeometry);
  }

  // ---------- Drawing tools ----------

  void _handleCanvasPointerExit(PointerExitEvent event) {
    _canvasPointerPosition.value = null;
    if (_penEnabled && !_canvasInputBlocked) _penTool.onPointerExit(event);
  }

  void _handleCanvasPointerHover(PointerHoverEvent event) {
    _canvasPointerPosition.value = event.localPosition;
    if (_penEnabled && !_spaceHeld && !_canvasInputBlocked) _penTool.onPointerHover(event);
  }

  void _addCodeBlock(Offset position) {
    if (!_documentLoaded) return;
    final size = _fittedBlockSize(const Size(600, 400), codeBlockMinimumSize);
    final value = CodeElementData(
      id: const Uuid().v4(),
      position: position,
      size: size,
      language: CodeLanguage.dart,
      source: '',
      title: '',
      showLineNumbers: true,
      background: _newBlockBackground,
    );
    _session.insert([value], returnToSelect: true);
    final model = _elements.firstWhere((model) => model.data.id == value.id);
    _setActiveElement(model);
    _editorFocusNode(model)?.requestFocus();
  }

  Size _fittedBlockSize(Size preferred, Size minimum) {
    final scale = _canvasController.scale;
    final viewport = _canvasController.canvasSize;
    return Size(
      math.max(
        minimum.width,
        math.min(preferred.width, (viewport.width - 32) / scale),
      ),
      math.max(
        minimum.height,
        math.min(preferred.height, (viewport.height - 32) / scale),
      ),
    );
  }

  void _addStroke(RawPenStroke rawStroke) {
    if (!_documentLoaded) return;
    _session.insert([
      positionStroke(
        rawStroke,
        id: const Uuid().v4(),
        canvasOffset: _canvasController.offset,
        canvasScale: _canvasController.scale,
      ),
    ]);
  }

  void _addArrow(ArrowElementData value) {
    if (!_documentLoaded) return;
    _session.insert([value], returnToSelect: true);
    _setActiveElement(_elements.firstWhere((model) => model.data.id == value.id));
  }

  void _addShape(ShapeElementData value) {
    if (!_documentLoaded) return;
    _session.insert([value], returnToSelect: true);
    _setActiveElement(_elements.firstWhere((model) => model.data.id == value.id));
  }

  void _handleArrowPointerDown(
    ArrowModel model,
    PointerDownEvent event,
  ) {
    if (!_canHandleCanvasPointer(event)) return;
    if (event.buttons != kPrimaryButton ||
        !_documentLoaded ||
        _placementEnabled ||
        _penEnabled ||
        _eraserEnabled ||
        _arrowEnabled ||
        !_elements.contains(model)) {
      return;
    }
    _interactiveCanvasPointerIds.add(event.pointer);
    if (_toggleSelectionIfModifierPressed(model)) return;
    if (!model.active) {
      _clearElementEditing();
    } else {
      _clearTextEditing();
    }
    _dragArrowPointer = event.pointer;
    _dragArrow = model;
    _dragArrowStart = event.position;
    _dragArrowSlop = computePanSlop(event.kind, MediaQuery.maybeGestureSettingsOf(context));
    _dragArrowMoving = false;
  }

  void _finishArrowDrag() {
    _dragArrowPointer = null;
    _dragArrow = null;
    _finishHistoryOperation();
  }

  void _startArrowPointEdit() {
    if (_canvasInputBlocked) return;
    _finishHistoryOperation();
    _clearSelection();
  }

  void _editArrowPoint(
    ArrowModel model,
    int point,
    Offset position,
  ) {
    if (_canvasInputBlocked) return;
    if (!_documentLoaded || !identical(_activeElement, model) || !_elements.contains(model)) return;
    _session.setArrowPoint(model.data.id, point, position);
  }

  void _handleStrokePointerDown(
    PenStrokeModel model,
    PointerDownEvent event,
  ) {
    if (!_canHandleCanvasPointer(event)) return;
    if (event.buttons != kPrimaryButton ||
        !_documentLoaded ||
        _placementEnabled ||
        _penEnabled ||
        _eraserEnabled ||
        !_elements.contains(model)) {
      return;
    }
    _interactiveCanvasPointerIds.add(event.pointer);
    if (_toggleSelectionIfModifierPressed(model)) return;
    _clearElementEditing();
  }

  // ---------- Editing commands ----------

  void _selectAll() {
    if (!_documentLoaded) return;
    _session.setSelection(_session.document.elements.map((value) => value.id));
  }

  void _deleteSelected() {
    final targets = _elements.where((model) => model.selected).toList();
    if (targets.isEmpty && _activeElement != null) targets.add(_activeElement!);
    _removeElements(targets);
  }

  // ---------- Clipboard ----------

  bool get _editingElement {
    final focusContext = FocusManager.instance.primaryFocus?.context;
    return focusContext?.widget is EditableText ||
        focusContext?.findAncestorWidgetOfExactType<EditableText>() != null ||
        _elements.whereType<TextBlockModel>().any(
          (model) => model.focusNode.hasFocus,
        ) ||
        _elements.whereType<CodeBlockModel>().any(
          (model) => model.focusNode.hasFocus,
        ) ||
        _elements.whereType<MediaModel>().any(
          (model) => model.focusNode.hasFocus,
        );
  }

  List<CanvasElementModel> get _selectedInStackingOrder => _elements.where((model) => model.selected).toList();

  void _handleWebCopy(ClipboardWriteEvent event) => _handleWebWrite(event, cut: false);

  void _handleWebCut(ClipboardWriteEvent event) => _handleWebWrite(event, cut: true);

  void _handleWebWrite(ClipboardWriteEvent event, {required bool cut}) {
    final targets = _contextMenuController.isOpen ? _contextMenuTargets : null;
    if (targets != null) _closeContextMenu();
    unawaited(_copySelection(event, cut: cut, targets: targets));
  }

  void _handleWebPaste(ClipboardReadEvent event) {
    if (!_documentLoaded || _filePickerOpen || ModalRoute.of(context)?.isCurrent == false || _editingElement) return;
    final position = _contextMenuPosition;
    _closeContextMenu();
    unawaited(_pasteSelection(event.getClipboardReader(), position: position));
  }

  Future<void> _copySelection(
    ClipboardWriter? writer, {
    bool cut = false,
    List<CanvasElementModel>? targets,
  }) async {
    if (!_documentLoaded ||
        _filePickerOpen ||
        ModalRoute.of(context)?.isCurrent == false ||
        (targets == null && (_contextMenuController.isOpen || _editingElement))) {
      return;
    }
    final selected = targets ?? _selectedInStackingOrder;
    final generation = _session.captureEdit();
    if (selected.isEmpty) return;
    final payload = encodeCanvasClipboard(
      selected.map((model) => model.data),
    );
    try {
      final write = widget.writeClipboardText;
      if (write != null) {
        await write(payload);
      } else {
        final clipboard = writer ?? SystemClipboard.instance;
        if (clipboard == null) throw StateError('Clipboard unavailable');
        final item = DataWriterItem()..add(Formats.plainText(payload));
        await clipboard.write([item]);
      }
      if (!mounted || !generation.isCurrent) return;
      _lastPastedPayload = null;
      _pasteOffset = Offset.zero;
      _cutPayload = cut ? payload : null;
      _pointerReference = (payload, _canvasPointerPosition.value);
      if (cut) {
        _removeElements(selected);
      }
    } on Object {
      if (!mounted || !generation.isCurrent) return;
      _showClipboardError(
        cut ? 'Could not cut canvas elements' : 'Could not copy canvas elements',
      );
    }
  }

  Future<void> _pasteSelection(Future<ClipboardReader>? readerFuture, {Offset? position}) async {
    if (!_documentLoaded || _filePickerOpen || ModalRoute.of(context)?.isCurrent == false) return;
    final generation = _session.captureEdit();
    final pointer = _canvasPointerPosition.value;
    final scale = _canvasController.scale;
    final pointerPosition = pointer == null ? null : _screenToCanvas(pointer);
    final mediaPosition =
        position ?? pointerPosition ?? _screenToCanvas(_canvasController.canvasSize.center(Offset.zero));
    try {
      final read = widget.readClipboard;
      late final CanvasClipboardSnapshot clipboard;
      try {
        clipboard = read != null
            ? await read()
            : await readCanvasClipboard(await (readerFuture ?? SystemClipboard.instance!.read()));
      } on FormatException {
        return;
      }
      if (!mounted || !_documentLoaded || !generation.isCurrent) return;
      final text = clipboard.text;
      final elements = text == null ? null : decodeCanvasClipboard(text);
      if (elements == null) {
        if (clipboard.image case final image?) {
          await _pasteImage(image, mediaPosition, generation);
        } else if (text?.trim() case final url? when isSupportedMediaUrl(url)) {
          _pasteMediaUrl(url, mediaPosition);
        }
        return;
      }
      if (!mounted || !_documentLoaded) return;
      final payload = text!;

      final placeAtPointer = position != null || (pointer != null && (payload, pointer) != _pointerReference);
      final pasted = [for (final element in elements) element.copyWith(id: const Uuid().v4())];
      _finishHistoryOperation();
      if (placeAtPointer) {
        final bounds = pasted.map(_elementBounds).reduce((bounds, next) => bounds.expandToInclude(next));
        _pasteOffset = (position ?? pointerPosition!) - bounds.center;
      } else if (_lastPastedPayload != payload) {
        _pasteOffset = payload == _cutPayload ? Offset.zero : const Offset(24, 24) / scale;
      } else {
        _pasteOffset += const Offset(24, 24) / scale;
      }
      _lastPastedPayload = payload;
      _pointerReference = (payload, pointer);
      _clearTextEditing();
      _setActiveElement(null);
      _session.insert([for (final value in pasted) moveElement(value, _pasteOffset)]);
      _session.setSelection(pasted.map((value) => value.id));
    } on Object {
      if (!mounted || !generation.isCurrent) return;
      _showClipboardError('Could not paste canvas elements');
    }
  }

  Future<void> _pasteImage(ClipboardImage image, Offset position, EditorEditToken generation) async {
    final extension = image.extension.toLowerCase() == 'jpeg' ? 'jpg' : image.extension.toLowerCase();
    final path = 'attachments/${const Uuid().v4()}.$extension';
    if (!attachmentPathPattern.hasMatch(path)) throw const FormatException('Unsupported image type');
    var published = false;
    try {
      final size = await readCanvasImageSize(image.bytes);
      if (!generation.isCurrent) return;
      await _attachmentStore.write(path, image.bytes);
      if (!mounted || !generation.isCurrent) return;
      _placePastedMedia(
        _newMediaData(path),
        position,
        imageSize: Size(mediaNodeDefaultWidth, mediaNodeDefaultWidth * size.height / size.width),
      );
      published = true;
    } finally {
      if (!published) {
        try {
          await _attachmentStore.delete(path);
        } on Object {
          // Cleanup cannot hide the original failure or revive a canceled edit.
        }
      }
    }
  }

  void _pasteMediaUrl(String url, Offset position) {
    if (!mounted || !_documentLoaded) return;
    _placePastedMedia(_newMediaData(url), position);
  }

  Rect _elementBounds(CanvasElementData value) => elementBounds(
    value,
    codeTitleHeight: codeTitleHeight,
    mediaSize: const Size(mediaUrlPanelMinimumWidth, mediaUrlPanelCanvasHeight),
  );

  MediaElementData _newMediaData(String url) =>
      MediaElementData(id: const Uuid().v4(), position: Offset.zero, width: mediaNodeDefaultWidth, url: url);

  void _placePastedMedia(MediaElementData value, Offset position, {Size? imageSize}) {
    _finishHistoryOperation();
    final placed = value.copyWith(
      position: position - (imageSize?.center(Offset.zero) ?? _elementBounds(value).center),
    );
    _clearTextEditing();
    _setActiveElement(null);
    _session
      ..insert([placed])
      ..setSelection([placed.id]);
  }

  // ---------- Erasing ----------

  void _eraseAt(Offset globalPosition) {
    final hits = <CanvasElementModel>[];
    for (final model in _elements) {
      final renderObject = _selectionKeys[model]?.currentContext?.findRenderObject();
      if (renderObject is RenderBox &&
          renderObject.hitTest(
            BoxHitTestResult(),
            position: renderObject.globalToLocal(globalPosition),
          )) {
        hits.add(model);
      }
    }
    _removeElements(hits, finishHistory: false);
  }

  void _removeElements(Iterable<CanvasElementModel> models, {bool finishHistory = true}) {
    if (!_documentLoaded) return;
    final ids = models.where(_elements.contains).map((model) => model.data.id).toList();
    if (ids.isEmpty) return;
    if (finishHistory) _finishHistoryOperation();
    _session.remove(ids);
    if (finishHistory) _finishHistoryOperation();
  }

  void _detachModels(List<CanvasElementModel> models) {
    if (models.isEmpty) return;
    if (models.any(_contextMenuTargets.contains)) _closeContextMenu();
    if (models.contains(_editingChromeModel.value)) _editingChromeModel.value = null;
    for (final model in models) {
      model.removeListener(_geometryListeners.remove(model)!);
      _canvasController.removeChild(model.data.id);
      _elements.remove(model);
      _selectionKeys.remove(model);
      _selectionBeforeDrag.remove(model);
      _selectionBeforeWidgetPointer.remove(model);
    }
    if (_selectionBeforeWidgetPointer.isEmpty) _widgetPointer = null;
    if (models.contains(_dragArrow)) {
      _dragArrow = null;
      _dragArrowPointer = null;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final model in models) {
        model.dispose();
      }
    });
  }

  // ---------- Workspace presentation and replacement ----------

  Future<void> _showFilePicker() async {
    if (!_documentLoaded || _filePickerOpen) return;
    setState(() => _filePickerOpen = true);
    _endCanvasInteraction();
    try {
      await widget.onOpenLibrary();
    } finally {
      if (mounted) setState(() => _filePickerOpen = false);
    }
  }

  void _showSettingsDialog() {
    if (_filePickerOpen || widget.blocked) return;
    _endCanvasInteraction();
    unawaited(
      showDialog<void>(
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
      ),
    );
  }

  void _showClipboardError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _setCanvasBackground(CanvasBackgroundKind kind) {
    if (!_documentLoaded) return;
    _finishHistoryOperation();
    _session.setBackground(kind);
    _finishHistoryOperation();
  }

  // ---------- Keyboard commands ----------

  bool _handleKeyEvent(KeyEvent event) {
    final keyboard = HardwareKeyboard.instance;
    final macOS = Theme.of(context).platform == TargetPlatform.macOS;
    _selectionModifierPressed.value = macOS ? keyboard.isMetaPressed : keyboard.isControlPressed;
    final openPicker = SingleActivator(LogicalKeyboardKey.keyP, meta: macOS, control: !macOS).accepts(event, keyboard);
    if (_filePickerOpen) return openPicker;
    if (!_documentLoaded || ModalRoute.of(context)?.isCurrent == false) return false;
    final unmodifiedKeyDown =
        event is KeyDownEvent &&
        ModalRoute.of(context)?.isCurrent != false &&
        !HardwareKeyboard.instance.isControlPressed &&
        !HardwareKeyboard.instance.isMetaPressed &&
        !HardwareKeyboard.instance.isAltPressed &&
        !HardwareKeyboard.instance.isShiftPressed;
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (!_contextMenuController.isOpen &&
        focusContext != null &&
        MenuController.maybeOf(focusContext)?.isOpen == true) {
      return false;
    }
    final arrangeModifier = macOS
        ? keyboard.isMetaPressed && !keyboard.isControlPressed
        : keyboard.isControlPressed && !keyboard.isMetaPressed;
    if (openPicker) {
      if (event is KeyDownEvent) unawaited(_showFilePicker());
      return true;
    }
    if ((!_editingElement || _contextMenuController.isOpen) &&
        (event is KeyDownEvent || event is KeyRepeatEvent) &&
        arrangeModifier &&
        !keyboard.isAltPressed) {
      final action = switch (event.logicalKey) {
        LogicalKeyboardKey.bracketRight => keyboard.isShiftPressed ? CanvasArrange.front : CanvasArrange.forward,
        LogicalKeyboardKey.bracketLeft => keyboard.isShiftPressed ? CanvasArrange.back : CanvasArrange.backward,
        LogicalKeyboardKey.braceRight when keyboard.isShiftPressed => CanvasArrange.front,
        LogicalKeyboardKey.braceLeft when keyboard.isShiftPressed => CanvasArrange.back,
        _ => null,
      };
      if (action != null) {
        final targets = _arrangeTargets;
        if (_contextMenuController.isOpen) {
          _closeContextMenu();
        } else {
          if (_selectedInStackingOrder.isEmpty) _setSelection(targets.toSet());
          _clearElementEditing();
        }
        _arrange(action, targets);
        return true;
      }
    }
    if (_contextMenuController.isOpen) {
      if (event is KeyDownEvent && arrangeModifier && !keyboard.isAltPressed && !keyboard.isShiftPressed) {
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.keyC || key == LogicalKeyboardKey.keyX || key == LogicalKeyboardKey.keyV) {
          // Browser clipboard events retain the native shortcut's clipboard access.
          if (_clipboardEvents != null) return false;
          final targets = _contextMenuTargets;
          final position = _contextMenuPosition;
          if (key == LogicalKeyboardKey.keyV) {
            if (_canPasteDirectly) {
              _dispatchContextMenuAction(() => unawaited(_pasteSelection(null, position: position)));
            }
          } else if (targets.isNotEmpty && _canCopyDirectly) {
            _dispatchContextMenuAction(
              () => unawaited(_copySelection(null, targets: targets, cut: key == LogicalKeyboardKey.keyX)),
            );
          }
          return true;
        }
      }
      if (unmodifiedKeyDown &&
          (event.logicalKey == LogicalKeyboardKey.delete ||
              (macOS && event.logicalKey == LogicalKeyboardKey.backspace))) {
        final targets = _contextMenuTargets;
        _dispatchContextMenuAction(() => _removeElements(targets));
        return true;
      }
      if (unmodifiedKeyDown && event.logicalKey == LogicalKeyboardKey.escape) _closeContextMenu();
      return false;
    }
    if (unmodifiedKeyDown && event.logicalKey == LogicalKeyboardKey.escape) {
      if (_editingElement || _activeElement != null) {
        _clearElementEditing();
      } else {
        _toggleTool(_activeTool.value);
      }
      _clearSelection();
      return true;
    }
    if (_editingElement) return false;
    if ((event is KeyDownEvent || event is KeyRepeatEvent) &&
        _selectionModifierPressed.value &&
        event.logicalKey == LogicalKeyboardKey.keyZ) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        _redo();
      } else {
        _undo();
      }
      return true;
    }
    if (event is KeyDownEvent && _selectionModifierPressed.value && _clipboardEvents == null) {
      if (event.logicalKey == LogicalKeyboardKey.keyC || event.logicalKey == LogicalKeyboardKey.keyX) {
        if (_selectedInStackingOrder.isEmpty) return false;
        unawaited(
          _copySelection(
            null,
            cut: event.logicalKey == LogicalKeyboardKey.keyX,
          ),
        );
        return true;
      }
      if (event.logicalKey == LogicalKeyboardKey.keyV) {
        unawaited(_pasteSelection(null));
        return true;
      }
    }
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.keyA && _selectionModifierPressed.value) {
      _selectAll();
      return true;
    }
    if (unmodifiedKeyDown) {
      final tool = switch (event.logicalKey) {
        LogicalKeyboardKey.keyT => CanvasTool.text,
        LogicalKeyboardKey.keyC => CanvasTool.code,
        LogicalKeyboardKey.keyM => CanvasTool.media,
        LogicalKeyboardKey.keyS => CanvasTool.shape,
        LogicalKeyboardKey.keyP => CanvasTool.pen,
        LogicalKeyboardKey.keyE => CanvasTool.eraser,
        LogicalKeyboardKey.keyA => CanvasTool.arrow,
        _ => null,
      };
      if (tool != null) {
        _toggleTool(tool);
        return true;
      }
    }
    final deletionKey =
        event.logicalKey == LogicalKeyboardKey.delete ||
        (Theme.of(context).platform == TargetPlatform.macOS && event.logicalKey == LogicalKeyboardKey.backspace);
    if ((event is KeyDownEvent || event is KeyRepeatEvent) && deletionKey) {
      _deleteSelected();
      return true;
    }
    if ((!_penEnabled && !_eraserEnabled) || event.logicalKey != LogicalKeyboardKey.space) {
      return false;
    }
    final held = event is! KeyUpEvent;
    if (_spaceHeld != held) setState(() => _spaceHeld = held);
    return true;
  }

  // ---------- History ----------

  void _finishHistoryOperation() {
    widget.session?.finishOperation();
    _widgetTransforming = false;
  }

  void _undo() {
    _endCanvasInteraction(commitMediaDraft: false);
    _session.undo();
  }

  void _redo() {
    _endCanvasInteraction(commitMediaDraft: false);
    _session.redo();
  }

  // ---------- Rendering ----------

  Widget _buildControlsPortal() => OverlayPortal.overlayChildLayoutBuilder(
    key: _controlsPortalKey,
    controller: _controlsOverlayController,
    overlayChildBuilder: (_, layout) {
      final anchor = _editingChromeModel.value;
      final bodyOffset = anchor is CodeBlockModel ? layout.childSize.height - anchor.size.height : 0.0;
      return Positioned(
        left: 0,
        top: 0,
        child: Transform(
          transform: layout.childPaintTransform,
          child: Transform.translate(
            offset: Offset(-ElementTransformControls.size.width - 10, bodyOffset),
            child: SizedBox.fromSize(
              size: ElementTransformControls.size,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                reverseDuration: const Duration(milliseconds: 180),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeOutCubic,
                transitionBuilder: _textEditingChromeTransition,
                child: switch (_activeElement) {
                  final CanvasElementModel editing => ListenableBuilder(
                    key: ValueKey(editing.data.id),
                    listenable: editing,
                    builder: (context, child) => IgnorePointer(
                      ignoring: !editing.active,
                      child: child,
                    ),
                    child: Listener(
                      onPointerDown: _handleObjectControlPointerDown,
                      child: ElementTransformControls(
                        key: ValueKey(editing.data.id),
                        elementName: editing.data.type,
                        rotation: switch (editing) {
                          final RotatableCanvasElementModel model => model.rotation,
                          _ => 0,
                        },
                        tapRegionGroupId: editing is MediaModel ? editing : null,
                        onMove: (delta) => _moveSelectedChildren(editing, delta),
                        onArrange: (bounds) => _openArrangeMenu(editing, bounds),
                        onRotate: switch (editing) {
                          final RotatableCanvasElementModel model when model.canRotate => (angle) => _rotateElement(
                            model,
                            angle,
                          ),
                          _ => null,
                        },
                        onDelete: () {
                          if (!_canvasInputBlocked) _removeElements([editing]);
                        },
                        onTransformStart: () {
                          if (_canvasInputBlocked) return;
                          if (editing is TextBlockModel) {
                            _clearTextEditing();
                          } else {
                            _finishHistoryOperation();
                          }
                        },
                        onTransformEnd: _finishHistoryOperation,
                        rotationCenter: () => _elementCenter(editing),
                      ),
                    ),
                  ),
                  _ => const SizedBox(
                    key: ValueKey('text-editing-chrome-hidden'),
                  ),
                },
              ),
            ),
          ),
        ),
      );
    },
    child: const SizedBox.shrink(),
  );

  Widget _buildCanvasViewport(BuildContext context, Widget viewport) {
    final colors = BTheme.of(context).colors;
    final activeArrow = _activeArrow;
    final canvas = Overlay.wrap(
      clipBehavior: Clip.none,
      child: Stack(
        children: [
          viewport,
          if (_arrowTool.preview case final preview?)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  key: const ValueKey('arrow-preview'),
                  painter: ArrowPreviewPainter(
                    preview: preview,
                    guideColor: colors.accent,
                    canvasOffset: _canvasController.offset,
                    canvasScale: _canvasController.scale,
                  ),
                ),
              ),
            ),
          if (_shapeTool.preview case final preview?)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  key: const ValueKey('shape-preview'),
                  painter: ShapePreviewPainter(
                    preview: preview,
                    canvasOffset: _canvasController.offset,
                    canvasScale: _canvasController.scale,
                  ),
                ),
              ),
            ),
          if (_penEnabled)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  key: const ValueKey('pen-preview'),
                  painter: PenPreviewPainter(
                    tool: _penTool,
                    color: colors.accent,
                  ),
                ),
              ),
            ),
          if (_eraserEnabled && !_spaceHeld)
            ValueListenableBuilder<Offset?>(
              valueListenable: _canvasPointerPosition,
              builder: (context, pointer, child) {
                if (pointer == null) return const SizedBox.shrink();
                return Positioned(
                  key: const ValueKey('eraser-cursor'),
                  left: pointer.dx - 4,
                  top: pointer.dy - 9,
                  child: IgnorePointer(
                    child: Icon(
                      LucideIcons.eraser,
                      color: colors.accent,
                      size: 20,
                    ),
                  ),
                );
              },
            ),
          if ((_dragSelectionStart, _dragSelectionEnd) case (
            final start?,
            final end?,
          ))
            Positioned.fromRect(
              key: const ValueKey('drag-selection-marquee'),
              rect: Rect.fromPoints(start, end),
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.accentSubtle.withValues(alpha: 0.45),
                    border: Border.all(color: colors.accent),
                  ),
                ),
              ),
            ),
          if (activeArrow != null)
            Positioned.fill(
              child: ListenableBuilder(
                listenable: Listenable.merge([activeArrow, _canvasController]),
                builder: (context, _) => Listener(
                  onPointerDown: _handleObjectControlPointerDown,
                  child: ArrowEditor(
                    model: activeArrow,
                    canvasOffset: _canvasController.offset,
                    canvasScale: _canvasController.scale,
                    onChangeStart: _startArrowPointEdit,
                    onPointChanged: (point, position) => _editArrowPoint(activeArrow, point, position),
                    onChangeEnd: _finishHistoryOperation,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    return canvas;
  }

  @override
  Widget build(BuildContext context) {
    final theme = BTheme.of(context);
    final colors = theme.colors;
    final geo = theme.geo;
    return Scaffold(
      body: Stack(
        children: [
          IgnorePointer(
            ignoring: !_documentLoaded || _filePickerOpen,
            child: MouseRegion(
              cursor: !_spaceHeld && (_penEnabled || _eraserEnabled) ? SystemMouseCursors.none : MouseCursor.defer,
              onExit: _handleCanvasPointerExit,
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerHover: _handleCanvasPointerHover,
                child: LazyCanvas(
                  controller: _canvasController,
                  foregroundChildId: _activeElement?.data.id,
                  touchNavigationMode: TouchNavigationMode.twoFinger,
                  onTouchNavigationChanged: _handleTouchNavigationChanged,
                  viewportBuilder: _buildCanvasViewport,
                  mousePanButtons:
                      (_activeTool.value == CanvasTool.select ? 0 : kSecondaryMouseButton) |
                      kMiddleMouseButton |
                      (_spaceHeld ? kPrimaryMouseButton : 0),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            child: ContextMenu(
              key: _contextMenuKey,
              controller: _contextMenuController,
              onClose: _contextMenuClosed,
              onTapOutside: _handleContextMenuOutsideTap,
              consumeOutsideTap: false,
              title: _arrangeMenuOpen ? 'Arrange' : null,
              groups: _arrangeMenuOpen ? _arrangeContextMenuActions() : _objectContextMenuActions(),
              tapRegionGroupId: _contextMenuTapRegionGroup,
              child: const SizedBox.shrink(),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.bottomRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 16, bottom: 12),
                child: ZoomControl(controller: _canvasController),
              ),
            ),
          ),
          Positioned.fill(
            child: CanvasChrome(
              title: CanvasTitle(
                path: widget.libraryPath,
                onPressed: _documentLoaded ? _showFilePicker : null,
              ),
              toolbar: CanvasToolbar(buttonsBuilder: _buildToolbarButtons),
              settingsButton: Surface(
                key: const ValueKey('settings-button-surface'),
                child: IconButton(
                  key: const ValueKey('settings-button'),
                  tooltip: 'Settings',
                  onPressed: _showSettingsDialog,
                  style:
                      _toolbarButtonStyle(
                        colors,
                        geo,
                      ).copyWith(
                        padding: const WidgetStatePropertyAll(EdgeInsets.all(8)),
                      ),
                  icon: const Icon(LucideIcons.settings),
                ),
              ),
              toolOptions: _buildToolOptions(),
            ),
          ),
        ],
      ),
    );
  }

  // ---------- Canvas chrome content ----------

  List<Widget> _buildToolbarButtons({required bool compact}) => [
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
          selected: _activeTool.value == tool,
          onPressed: () => _toggleTool(tool),
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
          onPressed: _toggleTouchSelection,
          child: const Icon(LucideIcons.squareDashed, size: 20, semanticLabel: 'Select'),
        ),
      ),
  ];

  Widget? _buildToolOptions() {
    final activeTextBlock = _activeTextBlock;
    final activeCodeBlock = _activeCodeBlock;
    final activeShape = _activeShape;
    final activeArrow = _activeArrow;
    return activeTextBlock != null
        ? Listener(
            onPointerDown: (_) => _clearTextEditing(),
            child: TextToolSettings(
              key: ValueKey(
                'text-settings-${activeTextBlock.node.id}',
              ),
              model: activeTextBlock,
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
              'code-settings-${activeCodeBlock.data.id}',
            ),
            model: activeCodeBlock,
            onChangeBoundary: _finishHistoryOperation,
          )
        : activeShape != null
        ? ListenableBuilder(
            key: const ValueKey('shape-settings-panel'),
            listenable: activeShape,
            builder: (context, _) => _ShapeSettings(
              kind: activeShape.kind,
              strokeColor: activeShape.strokeColor,
              fillColor: activeShape.fillColor,
              strokeWidth: activeShape.strokeWidth,
              outlineColorPickerExpanded: _shapeOutlineColorPickerExpanded,
              fillColorPickerExpanded: _shapeFillColorPickerExpanded,
              onKindChanged: (kind) =>
                  _editElement(activeShape, () => _session.setShapeOptions(activeShape.data.id, kind: kind)),
              onStrokeColorChanged: (color) =>
                  _editElement(activeShape, () => _session.setShapeOptions(activeShape.data.id, strokeColor: color)),
              onFillColorChanged: (color) => _editElement(
                activeShape,
                () => _session.setShapeOptions(activeShape.data.id, fillColor: color, clearFillColor: color == null),
              ),
              onStrokeWidthChanged: (width) =>
                  _editElement(activeShape, () => _session.setShapeOptions(activeShape.data.id, strokeWidth: width)),
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
            listenable: activeArrow,
            builder: (context, _) => _ArrowSettings(
              color: activeArrow.color,
              strokeStyle: activeArrow.strokeStyle,
              strokeWidth: activeArrow.strokeWidth,
              colorPickerExpanded: _arrowColorPickerExpanded,
              onColorChanged: (color) =>
                  _editElement(activeArrow, () => _session.setArrowOptions(activeArrow.data.id, color: color)),
              onStrokeStyleChanged: (style) =>
                  _editElement(activeArrow, () => _session.setArrowOptions(activeArrow.data.id, strokeStyle: style)),
              onStrokeWidthChanged: (width) =>
                  _editElement(activeArrow, () => _session.setArrowOptions(activeArrow.data.id, strokeWidth: width)),
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
            onColorChanged: _setPenColor,
            onColorPickerExpandedChanged: (expanded) => setState(
              () => _penColorPickerExpanded = expanded,
            ),
            onWidthChanged: _setPenWidth,
            onStreamlineChanged: _setPenStreamline,
          )
        : _shapeEnabled
        ? ListenableBuilder(
            key: const ValueKey('shape-settings-panel'),
            listenable: _shapeTool,
            builder: (context, _) => _ShapeSettings(
              kind: _shapeTool.kind,
              strokeColor: _shapeTool.strokeColor,
              fillColor: _shapeTool.fillColor,
              strokeWidth: _shapeTool.strokeWidth,
              outlineColorPickerExpanded: _shapeOutlineColorPickerExpanded,
              fillColorPickerExpanded: _shapeFillColorPickerExpanded,
              onKindChanged: _shapeTool.setKind,
              onStrokeColorChanged: _setShapeStrokeColor,
              onFillColorChanged: _shapeTool.setFillColor,
              onStrokeWidthChanged: _shapeTool.setStrokeWidth,
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
            listenable: _arrowTool,
            builder: (context, _) => _ArrowSettings(
              color: _arrowTool.color,
              strokeStyle: _arrowTool.strokeStyle,
              strokeWidth: _arrowTool.strokeWidth,
              colorPickerExpanded: _arrowColorPickerExpanded,
              onColorChanged: _setArrowColor,
              onStrokeStyleChanged: _arrowTool.setStrokeStyle,
              onStrokeWidthChanged: _arrowTool.setStrokeWidth,
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

// ---------- Selection chrome ----------

class _CanvasElementHost extends StatelessWidget {
  const _CanvasElementHost({
    required this.model,
    required this.activeTool,
    required this.modifierPressed,
    required this.onPointerDown,
    required this.onSecondaryPointerDown,
    required this.child,
    super.key,
  });

  final CanvasElementModel model;
  final ValueListenable<CanvasTool> activeTool;
  final ValueListenable<bool> modifierPressed;
  final ValueChanged<PointerDownEvent> onPointerDown;
  final ValueChanged<PointerDownEvent> onSecondaryPointerDown;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final listener = Listener(
      onPointerDown: (event) {
        if (activeTool.value == CanvasTool.select) {
          onSecondaryPointerDown(event);
          onPointerDown(event);
        }
      },
      child: ListenableBuilder(
        listenable: Listenable.merge([activeTool, modifierPressed]),
        builder: (context, child) => AbsorbPointer(
          absorbing: activeTool.value != CanvasTool.select || modifierPressed.value && model is! PenStrokeModel,
          child: child,
        ),
        child: child,
      ),
    );
    return listener;
  }
}

Widget _textEditingChromeTransition(
  Widget child,
  Animation<double> animation,
) {
  return FadeTransition(
    opacity: animation,
    child: ScaleTransition(
      scale: Tween<double>(begin: 0.94, end: 1).animate(animation),
      alignment: Alignment.centerLeft,
      child: child,
    ),
  );
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
