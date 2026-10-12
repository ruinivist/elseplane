// Provides the infinite canvas editor and coordinates tools and persistence.
// Used as the application's primary workspace screen.

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/editor/browser_touch_observer.dart'
    if (dart.library.js_interop) 'package:elseplane/canvas/editor/browser_touch_observer_web.dart';
import 'package:elseplane/canvas/editor/canvas_background.dart';
import 'package:elseplane/canvas/editor/canvas_clipboard.dart';
import 'package:elseplane/canvas/editor/canvas_element_model.dart';
import 'package:elseplane/canvas/editor/widgets/arrow_stroke_style_icon.dart';
import 'package:elseplane/canvas/editor/widgets/canvas_chrome.dart';
import 'package:elseplane/canvas/editor/widgets/canvas_file_picker.dart';
import 'package:elseplane/canvas/editor/widgets/canvas_title.dart';
import 'package:elseplane/canvas/editor/widgets/canvas_toolbar.dart';
import 'package:elseplane/canvas/editor/widgets/element_transform_controls.dart';
import 'package:elseplane/canvas/editor/widgets/toolbar_button.dart';
import 'package:elseplane/canvas/editor/widgets/zoom_control.dart';
import 'package:elseplane/canvas/persistence/attachments/store.dart';
import 'package:elseplane/canvas/persistence/canvas_document_store.dart';
import 'package:elseplane/canvas/persistence/canvas_library.dart';
import 'package:elseplane/canvas/persistence/canvas_library_archive.dart';
import 'package:elseplane/canvas/persistence/canvas_project.dart';
import 'package:elseplane/canvas/persistence/canvas_project_files.dart';
import 'package:elseplane/canvas/tools/arrow/arrow_tool.dart';
import 'package:elseplane/canvas/tools/code/code_tool.dart';
import 'package:elseplane/canvas/tools/media/media_tool.dart';
import 'package:elseplane/canvas/tools/pen/pen_tool.dart';
import 'package:elseplane/canvas/tools/shape/shape_tool.dart';
import 'package:elseplane/canvas/tools/text/text_tool.dart';
import 'package:elseplane/settings/settings_dialog.dart';
import 'package:elseplane/theme/fonts.dart';
import 'package:elseplane/theme/preset_colors.dart';
import 'package:elseplane/theme/theme.dart';
import 'package:elseplane/ui/common/color_picker.dart';
import 'package:elseplane/ui/common/context_menu.dart';
import 'package:elseplane/ui/common/discrete_slider.dart';
import 'package:elseplane/ui/common/surface.dart';
import 'package:elseplane/ui/common/surface_dialog.dart';
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

// ---------- Tools and presets ----------

enum _CanvasTool { select, text, code, media, shape, pen, arrow, eraser }

typedef _CanvasHistoryEntry = ({String document, _CanvasTool tool, bool touchSelectionEnabled});

final List<({String label, Color color})> _toolColorSwatches = presetColors
    .where(
      (swatch) => switch (swatch.label) {
        'Black' || 'Gray' || 'Red' => true,
        _ => false,
      },
    )
    .toList(growable: false);

// ---------- Canvas workspace ----------

/// Coordinates the infinite canvas, element tools, persistence, and transfer.
/// Used as the application's primary interactive workspace.
class CanvasPage extends StatefulWidget {
  // ---------- Construction ----------

  const CanvasPage({
    this.attachmentStore,
    this.documentStore,
    this.projectFiles,
    this.readClipboard,
    this.writeClipboardText,
    this.themeMode = ThemeMode.light,
    this.onSurfaceStyleChanged,
    this.onThemeModeChanged,
    super.key,
  });

  final AttachmentStore? attachmentStore;
  final CanvasDocumentStore? documentStore;
  final CanvasProjectFiles? projectFiles;
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

  static const _historyLimit = 50;
  static const _secondaryPanSlop = 4.0;

  // ---------- State ----------

  final _canvasController = LazyCanvasController(
    buildExtentMultiplier: 3.4,
    useIdsFromArgs: true,
  );
  CanvasBackgroundKind _canvasBackgroundKind = CanvasBackgroundKind.dotGrid;
  late final CanvasDocumentStore _documentStore = widget.documentStore ?? CanvasDocumentStore();
  late final AttachmentStore _attachmentStore = widget.attachmentStore ?? createAttachmentStore();
  late final CanvasProjectFiles _projectFiles = widget.projectFiles ?? createCanvasProjectFiles();
  final _elements = <CanvasElementModel>[];
  final MenuController _contextMenuController = MenuController();
  final GlobalKey _contextMenuKey = GlobalKey();
  final _contextMenuFocusNode = FocusNode(debugLabel: 'Canvas context menu');
  List<CanvasElementModel> _contextMenuTargets = const [];
  ({int pointer, Offset start, CanvasElementModel? model, double slop})? _secondaryClick;
  (Offset, double)? _contextMenuView;
  Offset? _contextMenuPosition;
  bool _arrangeMenuOpen = false;
  int _documentGeneration = 0;
  final _geometryListeners = <CanvasElementModel, VoidCallback>{};
  CanvasElementModel? _activeElement;
  TextBlockModel? _editingTextBlock;
  final _editingChromeModel = ValueNotifier<CanvasElementModel?>(null);
  final ValueNotifier<bool> _selectionModifierPressed = ValueNotifier(false);
  final _interactiveCanvasPointerIds = <int>{};
  final _selectionBeforeWidgetPointer = <Object>{};
  final _selectionKeys = <Object, GlobalKey>{};
  final _controlsOverlayController = OverlayPortalController();
  final GlobalKey _controlsPortalKey = GlobalKey();
  final _selectionBeforeDrag = <Object>{};
  int? _widgetPointer;
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
  Timer? _saveTimer;
  Future<void> _saveQueue = Future<void>.value();
  bool _documentDirty = false;
  bool _documentLoaded = false;
  var _projectTransferActive = false;
  var _filePickerOpen = false;
  late final PenTool _penTool;
  late final ArrowTool _arrowTool;
  late final ShapeTool _shapeTool;
  Color? _customPenColor;
  Color? _customShapeStrokeColor;
  Color? _customArrowColor;
  double _penWidth = 4;
  double _penStreamline = penStreamlineDefault;
  final ValueNotifier<_CanvasTool> _activeTool = ValueNotifier(
    _CanvasTool.select,
  );
  int? _eraserPointer;
  final _canvasPointers = <int, PointerDeviceKind>{};
  final _blockedCanvasPointers = <int>{};
  var _touchNavigationActive = false;
  ({int pointer, Offset start, _CanvasTool tool, double slop})? _touchPlacement;
  ({int pointer, Offset start, double slop, VelocityTracker velocity})? _pointerPan;
  var _pointerPanStarted = false;
  var _touchControlsVisible = false;
  var _touchSelectionEnabled = false;
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
  final _undoHistory = <_CanvasHistoryEntry>[];
  final _redoHistory = <_CanvasHistoryEntry>[];
  _CanvasHistoryEntry? _historyCurrent;
  var _historyOperationActive = false;
  var _penColorPickerExpanded = false;
  var _shapeOutlineColorPickerExpanded = false;
  var _arrowColorPickerExpanded = false;
  var _textColorPickerExpanded = false;

  Color get _penColor => _customPenColor ?? BTheme.of(context).colors.textPrimary;

  bool get _penEnabled => _activeTool.value == _CanvasTool.pen;

  bool get _arrowEnabled => _activeTool.value == _CanvasTool.arrow;

  bool get _shapeEnabled => _activeTool.value == _CanvasTool.shape;

  ValueChanged<Offset>? get _placementAction => switch (_activeTool.value) {
    _CanvasTool.text => _addTextBlock,
    _CanvasTool.code => _addCodeBlock,
    _CanvasTool.media => _addMedia,
    _ => null,
  };

  bool get _placementEnabled => _placementAction != null;

  bool get _eraserEnabled => _activeTool.value == _CanvasTool.eraser;

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
    _controlsOverlayController.show();
    _canvasController
      ..rawPointerDownListener = _handleCanvasPointerDown
      ..rawPointerMoveListener = _handleCanvasPointerMove
      ..rawPointerUpListener = _handleCanvasPointerUp
      ..rawPointerCancelListener = _handleCanvasPointerCancel
      ..addListener(_closeContextMenuOnNavigation);
    _penTool = PenTool(onStroke: _addStroke)..setStrokeWidth(_penWidth);
    _arrowTool = ArrowTool(onArrow: _addArrow)..addListener(_handleDrawingToolChanged);
    _shapeTool = ShapeTool(onShape: _addShape)..addListener(_handleDrawingToolChanged);
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
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
    unawaited(_restoreDocument());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final platform = Theme.of(context).platform;
    if (platform == TargetPlatform.android || platform == TargetPlatform.iOS) _touchControlsVisible = true;
    final colors = BTheme.of(context).colors;
    _canvasController.background = _canvasBackgroundKind.build(colors);
    if (_customPenColor == null) _penTool.setColor(colors.textPrimary);
    if (_customShapeStrokeColor == null) {
      _shapeTool.setStrokeColor(colors.textSecondary);
    }
    if (_customArrowColor == null) {
      _arrowTool.setColor(colors.textSecondary);
    }
  }

  FocusNode? _editorFocusNode(CanvasElementModel model) => switch (model) {
    final TextBlockModel text => text.focusNode,
    final CodeBlockModel code => code.focusNode,
    final MediaModel media => media.focusNode,
    _ => null,
  };

  @override
  void dispose() {
    _closeContextMenu();
    _contextMenuFocusNode.dispose();
    _canvasController.removeListener(_closeContextMenuOnNavigation);
    _saveTimer?.cancel();
    _saveTimer = null;
    if (_documentLoaded && _documentDirty) {
      unawaited(_enqueueDocumentSave() ?? Future<void>.value());
    }
    unawaited(_saveQueue);
    for (final model in _elements) {
      _editorFocusNode(model)?.removeListener(_finishHistoryOperation);
      model.removeListener(_geometryListeners.remove(model)!);
      model.documentChanges.removeListener(_scheduleDocumentSave);
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

  // ---------- Tool selection ----------

  void _handleDrawingToolChanged() {
    if (mounted) setState(() {});
  }

  void _toggleTool(_CanvasTool tool) {
    if (!_documentLoaded) return;
    _applyTool(_activeTool.value != tool ? tool : _CanvasTool.select);
    _noteHistoryChange();
    _finishHistoryOperation();
  }

  void _applyTool(_CanvasTool tool, {bool touchSelectionEnabled = false}) {
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
    _clearElementEditing();
    setState(() {
      _activeTool.value = tool;
      _touchSelectionEnabled = touchSelectionEnabled;
      _eraserPointer = null;
      _spaceHeld = false;
    });
  }

  void _toggleTouchSelection() {
    if (!_documentLoaded) return;
    _applyTool(_CanvasTool.select, touchSelectionEnabled: !_touchSelectionEnabled);
    _noteHistoryChange();
    _finishHistoryOperation();
  }

  void _setPenColor(Color color) {
    setState(() => _customPenColor = color);
    _penTool.setColor(color);
  }

  void _setPenWidth(double width) {
    setState(() => _penWidth = width);
    _penTool.setStrokeWidth(width);
  }

  void _setPenStreamline(double streamline) {
    setState(() => _penStreamline = streamline);
    _penTool.setStreamline(streamline);
  }

  void _setShapeStrokeColor(Color color) {
    _customShapeStrokeColor = color;
    _shapeTool.setStrokeColor(color);
  }

  void _setArrowColor(Color color) {
    _customArrowColor = color;
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

  bool get _canvasInputBlocked => _touchNavigationActive || _blockedCanvasPointers.isNotEmpty;

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
      _finishHistoryOperation();
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
    setState(() => _activeTool.value = _CanvasTool.select);
    place(position);
    return true;
  }

  Offset _screenToCanvas(Offset screenPosition) => _canvasController.offset + screenPosition / _canvasController.scale;

  void _handleCanvasPointerDown(PointerDownEvent event) {
    // Menu overlays share this raw listener; their clicks and dismissal own the pointer.
    if (_contextMenuController.isOpen) return;
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
        _activeTool.value == _CanvasTool.select) {
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
        _clearSelection();
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
        _activeTool.value == _CanvasTool.select &&
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
      _finishArrowDrag(select: true);
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

    for (final model in _elements) {
      model.selected = selected(model);
    }
  }

  bool _selectionRectOverlaps(Rect selection, ChildInfo info, Size size) {
    final elementPath = (Path()..addRect(Offset.zero & size)).transform(
      childTransform(
        info.ssPosition,
        size,
        info.rotation,
        scale: _canvasController.scale,
      ).storage,
    );
    final overlap = Path.combine(
      PathOperation.intersect,
      Path()..addRect(selection),
      elementPath,
    ).getBounds();
    return !overlap.isEmpty;
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
      _finishHistoryOperation();
    });
  }

  bool _toggleSelectionIfModifierPressed(CanvasElementModel model) {
    if (!_selectionModifierPressed.value) return false;
    model.selected = !model.selected;
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
    if (!model.active) _setActiveElement(null);
    if (model.focusNode.hasFocus) _finishHistoryOperation();
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
    if (!model.active) _setActiveElement(null);
    if (model.focusNode.hasFocus) _finishHistoryOperation();
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
        _activeTool.value != _CanvasTool.select ||
        !_elements.contains(model)) {
      return;
    }
    _interactiveCanvasPointerIds.add(event.pointer);
    if (_toggleSelectionIfModifierPressed(model)) return;
    if (!model.active) _setActiveElement(null);
    FocusManager.instance.primaryFocus?.unfocus();
    _clearTextEditing();
  }

  void _activateElement(CanvasElementModel model) {
    if (_canvasInputBlocked) return;
    if (!_documentLoaded || _activeTool.value != _CanvasTool.select || !_elements.contains(model)) return;
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
    setState(() {
      _editingTextBlock = editing;
      _editingChromeModel.value = editing;
      for (final model in _elements.whereType<TextBlockModel>()) {
        model.editing = identical(model, editing);
      }
    });
  }

  void _clearTextEditing() {
    setState(() {
      _editingTextBlock = null;
      for (final model in _elements.whereType<TextBlockModel>()) {
        model.editing = false;
      }
    });
    _finishHistoryOperation();
  }

  void _clearElementEditing() {
    FocusManager.instance.primaryFocus?.unfocus();
    _clearTextEditing();
    _setActiveElement(null);
  }

  void _setActiveElement(CanvasElementModel? model) {
    if (identical(_activeElement, model)) return;
    setState(() {
      _activeElement?.active = false;
      _activeElement = model;
      model?.active = true;
      if (model != null) _editingChromeModel.value = model;
    });
  }

  void _clearSelection() {
    _setSelection(const <Object>{});
  }

  void _setSelection(Set<Object> selection) {
    for (final model in _elements) {
      model.selected = selection.contains(model);
    }
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
        _activeTool.value != _CanvasTool.select ||
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
    if (_canvasInputBlocked || !_elements.contains(model) || _activeTool.value != _CanvasTool.select) return;
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
    if ((model != null && !_elements.contains(model)) || _activeTool.value != _CanvasTool.select) return;
    if (model != null && !model.selected) _setSelection({model});
    _contextMenuTargets = model == null ? const [] : _selectedInStackingOrder;
    _arrangeMenuOpen = arrangeOnly;
    final box = _contextMenuKey.currentContext!.findRenderObject()! as RenderBox;
    _contextMenuPosition = _screenToCanvas(box.globalToLocal(position));
    _clearElementEditing();
    _contextMenuView = (_canvasController.offset, _canvasController.scale);
    // Build the captured targets before opening; editor release callbacks finish first.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _contextMenuPosition == null) return;
      final box = _contextMenuKey.currentContext!.findRenderObject()! as RenderBox;
      _contextMenuController.open(position: box.globalToLocal(position));
      _contextMenuFocusNode.requestFocus();
    });
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
    if (targets.any((model) => !_elements.contains(model))) return false;
    try {
      return _canvasController.canArrange(targets.map((model) => model.data.id), action);
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
    final ids = targets.map((model) => model.data.id);
    final changed = switch (action) {
      CanvasArrange.forward => _canvasController.bringForward(ids),
      CanvasArrange.backward => _canvasController.sendBackward(ids),
      CanvasArrange.front => _canvasController.bringToFront(ids),
      CanvasArrange.back => _canvasController.sendToBack(ids),
    };
    if (!changed) return;
    final models = {for (final model in _elements) model.data.id: model};
    _elements
      ..clear()
      ..addAll(_canvasController.childOrder.map((id) => models[id]!));
    _scheduleDocumentSave();
    _finishHistoryOperation();
    setState(() {});
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
    var focusFirst = _arrangeMenuOpen;
    ContextMenuAction arrange(CanvasArrange action, String label, IconData icon) {
      final enabled = _canArrange(action, targets);
      final focusNode = focusFirst && enabled ? _contextMenuFocusNode : null;
      if (enabled) focusFirst = false;
      return ContextMenuAction(
        label: label,
        icon: icon,
        focusNode: focusNode,
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
    if (draggedWasSelected) _setSelection(selectedBeforeWidgetPointer);

    final draggedSelected = draggedWasSelected || (_elements.contains(dragged) && dragged.selected);

    if (!draggedSelected) _clearSelection();

    final gridDelta = screenDelta / _canvasController.scale;
    final affected = _elements
        .where(
          (model) => identical(model, dragged) || draggedSelected && model.selected,
        )
        .toList();

    if (affected.isEmpty) return;
    _canvasController.moveChildrenBy(
      affected.map((model) => model.data.id),
      gridDelta,
    );
    for (final model in affected) {
      model.moveBy(gridDelta);
    }
  }

  void _resizeTextBlock(
    TextBlockModel model,
    Size renderedSize,
    Offset screenDelta,
  ) {
    if (_canvasInputBlocked) return;
    if (!_documentLoaded || _placementEnabled || _penEnabled || _eraserEnabled) {
      return;
    }
    if (!_elements.contains(model)) return;
    model.resize(renderedSize, _localTransformDelta(model.rotation, screenDelta));
  }

  void _resizeCodeBlock(CodeBlockModel model, Offset localDelta) {
    if (_canvasInputBlocked) return;
    if (!_documentLoaded || _placementEnabled || _penEnabled || _eraserEnabled) {
      return;
    }
    if (!_elements.contains(model)) return;
    model.size = Size(
      model.size.width + localDelta.dx,
      model.size.height + localDelta.dy,
    );
  }

  void _resizeMedia(MediaModel model, Offset screenDelta) {
    if (_canvasInputBlocked) return;
    if (!_documentLoaded || _activeTool.value != _CanvasTool.select || !_elements.contains(model)) {
      return;
    }
    model.resizeBy(_localTransformDelta(model.rotation, screenDelta));
  }

  void _resizeShape(ShapeModel model, Offset screenDelta) {
    if (_canvasInputBlocked) return;
    if (!_documentLoaded || _activeTool.value != _CanvasTool.select || !_elements.contains(model)) {
      return;
    }
    if (_selectionBeforeWidgetPointer.contains(model)) {
      _setSelection(_selectionBeforeWidgetPointer);
    }
    model.resizeBy(screenDelta / _canvasController.scale);
  }

  Offset _localTransformDelta(double rotation, Offset screenDelta) {
    final delta = screenDelta / _canvasController.scale;
    final angle = -rotation;
    final cosine = math.cos(angle);
    final sine = math.sin(angle);
    return Offset(
      delta.dx * cosine - delta.dy * sine,
      delta.dx * sine + delta.dy * cosine,
    );
  }

  void _rotateElement(RotatableCanvasElementModel model, double angle) {
    if (_canvasInputBlocked) return;
    if (!_documentLoaded || _placementEnabled || _penEnabled || _eraserEnabled) {
      return;
    }
    if (!_elements.contains(model)) return;
    model.rotate(angle);
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

  void _addTextBlock(Offset position) {
    if (!_documentLoaded) return;
    final node = TextElementData(
      id: const Uuid().v4(),
      position: position,
      width: textNodeDefaultWidth,
      height: textNodeDefaultHeight,
      markdown: '',
      style: const TextNodeStyle(fontFamily: defaultFontFamily),
    );
    final model = TextBlockModel(node);

    _mountElement(model, requestFocus: true);
    _startTextEditing(model);
    _scheduleDocumentSave();
  }

  void _addMedia(Offset position) {
    if (!_documentLoaded) return;
    final model = _newMediaModel('')..data.position = position;
    _mountElement(model, requestFocus: true);
    _setActiveElement(model);
    _scheduleDocumentSave();
    _finishHistoryOperation();
  }

  CanvasElementModel _createElementModel(CanvasElementData data) {
    return switch (data) {
      final TextElementData data => TextBlockModel(data),
      final CodeElementData data => CodeBlockModel(data),
      final MediaElementData data => MediaModel(data, _attachmentStore),
      final ShapeElementData data => ShapeModel(data),
      final PenElementData data => PenStrokeModel(data),
      final ArrowElementData data => ArrowModel(data),
    };
  }

  void _mountElement(
    CanvasElementModel model, {
    bool requestFocus = false,
  }) {
    _elements.add(model);
    model.documentChanges.addListener(_scheduleDocumentSave);
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
          onPanelPointerDown: (event) => _handleObjectSecondaryDown(media, event),
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
    _editorFocusNode(model)?.addListener(_finishHistoryOperation);
    if (requestFocus) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _editorFocusNode(model)?.requestFocus(),
      );
    }
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
    final model = CodeBlockModel(
      CodeElementData(
        id: const Uuid().v4(),
        position: position,
        size: size,
        language: CodeLanguage.dart,
        source: '',
        title: '',
        showLineNumbers: true,
      ),
    );
    _mountElement(model, requestFocus: true);
    _setActiveElement(model);
    _scheduleDocumentSave();
    _finishHistoryOperation();
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
    final model = PenStrokeModel(
      positionStroke(
        rawStroke,
        id: const Uuid().v4(),
        canvasOffset: _canvasController.offset,
        canvasScale: _canvasController.scale,
      ),
    );
    _mountElement(model);
    _scheduleDocumentSave();
    _finishHistoryOperation();
  }

  void _addArrow(ArrowModel model) {
    if (!_documentLoaded) return;
    if (_arrowEnabled) setState(() => _activeTool.value = _CanvasTool.select);
    _mountElement(model);
    _setActiveElement(model);
    _scheduleDocumentSave();
    _finishHistoryOperation();
  }

  void _addShape(ShapeModel model) {
    if (!_documentLoaded) return;
    if (_shapeEnabled) setState(() => _activeTool.value = _CanvasTool.select);
    _mountElement(model);
    _setActiveElement(model);
    _scheduleDocumentSave();
    _finishHistoryOperation();
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

  void _finishArrowDrag({bool select = false}) {
    if (select) _dragArrow?.selected = true;
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
    model.setPoint(point, position);
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
    for (final model in _elements) {
      model.selected = true;
    }
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
    if (!_documentLoaded || _filePickerOpen || _editingElement) return;
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
        (targets == null && (_contextMenuController.isOpen || _editingElement))) {
      return;
    }
    final selected = targets ?? _selectedInStackingOrder;
    final generation = _documentGeneration;
    if (selected.isEmpty) return;
    final payload = encodeCanvasClipboard(
      selected.map((model) => model.data.copy()),
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
      if (!mounted || _documentGeneration != generation) return;
      _lastPastedPayload = null;
      _pasteOffset = Offset.zero;
      _cutPayload = cut ? payload : null;
      _pointerReference = (payload, _canvasPointerPosition.value);
      if (cut && !_filePickerOpen) {
        _removeElements(selected);
      }
    } on Object {
      _showProjectSnackBar(
        cut ? 'Could not cut canvas elements' : 'Could not copy canvas elements',
      );
    }
  }

  Future<void> _pasteSelection(Future<ClipboardReader>? readerFuture, {Offset? position}) async {
    final generation = _documentGeneration;
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
      if (!mounted || !_documentLoaded || _filePickerOpen || _documentGeneration != generation) return;
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
      final pasted = [
        for (final element in elements) _createElementModel(element.copy(id: const Uuid().v4())),
      ];
      _finishHistoryOperation();
      if (placeAtPointer) {
        final bounds = pasted
            .map((model) => model.canvasPosition & model.canvasSize)
            .reduce((bounds, next) => bounds.expandToInclude(next));
        _pasteOffset = (position ?? pointerPosition!) - bounds.center;
      } else if (_lastPastedPayload != payload) {
        _pasteOffset = payload == _cutPayload ? Offset.zero : const Offset(24, 24) / scale;
      } else {
        _pasteOffset += const Offset(24, 24) / scale;
      }
      _lastPastedPayload = payload;
      _pointerReference = (payload, pointer);
      for (final model in pasted) {
        model.moveBy(_pasteOffset);
        _mountElement(model);
      }
      _clearTextEditing();
      _setActiveElement(null);
      _setSelection(pasted.toSet());
      _scheduleDocumentSave();
      _finishHistoryOperation();
    } on Object {
      _showProjectSnackBar('Could not paste canvas elements');
    }
  }

  Future<void> _pasteImage(ClipboardImage image, Offset position, int generation) async {
    final model = _newMediaModel('');
    try {
      await model.setDeviceImage(image.bytes, image.extension);
    } on FormatException {
      model.dispose();
      return;
    } on Object {
      model.dispose();
      rethrow;
    }
    if (!mounted || !_documentLoaded || _filePickerOpen || _documentGeneration != generation) {
      model.dispose();
      return;
    }
    _placePastedMedia(model, position);
  }

  void _pasteMediaUrl(String url, Offset position) {
    if (!mounted || !_documentLoaded) return;
    _placePastedMedia(_newMediaModel(url), position);
  }

  MediaModel _newMediaModel(String url) => MediaModel(
    MediaElementData(
      id: const Uuid().v4(),
      position: Offset.zero,
      width: mediaNodeDefaultWidth,
      url: url,
    ),
    _attachmentStore,
  );

  void _placePastedMedia(MediaModel model, Offset position) {
    _finishHistoryOperation();
    model.data.position = position - model.canvasSize.center(Offset.zero);
    _clearTextEditing();
    _setActiveElement(null);
    _clearSelection();
    model.selected = true;
    _mountElement(model);
    _scheduleDocumentSave();
    _finishHistoryOperation();
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

  void _removeElements(
    Iterable<CanvasElementModel> models, {
    bool finishHistory = true,
  }) {
    if (!_documentLoaded) return;
    final modelsToDispose = models.where(_elements.contains).toList();
    if (modelsToDispose.isEmpty) return;
    if (finishHistory) _finishHistoryOperation();
    if (modelsToDispose.any(_contextMenuTargets.contains)) _closeContextMenu();

    final removesEditingElement = modelsToDispose.any(
      (model) => identical(model, _editingTextBlock) || identical(model, _editingChromeModel.value),
    );
    if (removesEditingElement) {
      _clearTextEditing();
      setState(() => _editingChromeModel.value = null);
    }
    if (modelsToDispose.contains(_activeElement)) _setActiveElement(null);
    for (final model in modelsToDispose) {
      _editorFocusNode(model)?.unfocus();
      _editorFocusNode(model)?.removeListener(_finishHistoryOperation);
      model.removeListener(_geometryListeners.remove(model)!);
      _canvasController.removeChild(model.data.id);
      _elements.remove(model);
      _selectionKeys.remove(model);
      _selectionBeforeDrag.remove(model);
      _selectionBeforeWidgetPointer.remove(model);
      model.documentChanges.removeListener(_scheduleDocumentSave);
    }
    if (_selectionBeforeWidgetPointer.isEmpty) _widgetPointer = null;
    if (modelsToDispose.contains(_dragArrow)) _finishArrowDrag();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final model in modelsToDispose) {
        model.dispose();
      }
    });
    _scheduleDocumentSave();
    if (finishHistory) _finishHistoryOperation();
  }

  // ---------- Settings and project transfer ----------

  Future<void> _showFilePicker() async {
    if (!_documentLoaded || _projectTransferActive || _filePickerOpen) return;
    _closeContextMenu();
    setState(() => _filePickerOpen = true);
    _clearElementEditing();
    FocusManager.instance.primaryFocus?.unfocus();
    _saveTimer?.cancel();
    _saveTimer = null;
    final previousId = _documentStore.library.currentId;
    try {
      await _saveQueue;
      // Capture even a failed autosave before allowing any file operation.
      await _persistDocument(_currentDocument());
      _documentDirty = false;
      if (!mounted) return;
      final id = await showDialog<String>(
        context: context,
        barrierColor: Colors.transparent,
        builder: (_) => CanvasFilePicker(
          library: _documentStore.library,
          onSave: _documentStore.saveLibrary,
          attachmentStore: _attachmentStore,
        ),
      );
      if (!mounted) return;
      if (id != null && id != previousId) {
        final next = _documentStore.library;
        _replaceLiveModels(next.current.document!.copy());
        _resetHistory();
      }
    } on Object {
      _showProjectSnackBar('Could not open canvas. Your current canvas is still open.');
    } finally {
      if (mounted) setState(() => _filePickerOpen = false);
    }
  }

  void _showSettingsDialog() {
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
          onImportCanvas: _importProject,
          onExportCanvas: _exportProject,
          onBackupLibrary: _backupLibrary,
          onRestoreLibrary: _restoreLibrary,
        ),
      ),
    );
  }

  Future<void> _exportProject() async {
    if (_projectTransferActive || !_documentLoaded) return;
    _projectTransferActive = true;
    try {
      final snapshot = _currentDocument();
      final bytes = await encodeCanvasProject(snapshot, _attachmentStore);
      if (await _projectFiles.save(bytes, suggestedName: 'canvas.elseplane.json', mimeType: 'application/json')) {
        _showProjectSnackBar('Canvas exported');
      }
    } on Object {
      _showProjectSnackBar('Could not export canvas');
    } finally {
      _projectTransferActive = false;
    }
  }

  Future<void> _backupLibrary() async {
    if (_projectTransferActive || !_documentLoaded) return;
    _projectTransferActive = true;
    try {
      await _saveQueue;
      if (!mounted) return;
      final library = _documentStore.library;
      final snapshot = library.replace(library.current.copyWith(document: _currentDocument()));
      final bytes = await encodeCanvasLibraryArchive(snapshot, _attachmentStore);
      if (await _projectFiles.save(bytes, suggestedName: 'library.elseplane.zip', mimeType: 'application/zip')) {
        _showProjectSnackBar('Library backed up');
      }
    } on FormatException catch (error) {
      _showProjectSnackBar(error.message);
    } on Object {
      _showProjectSnackBar('Could not back up library');
    } finally {
      _projectTransferActive = false;
    }
  }

  Future<bool> _confirmReplacement({required String title, required String message, required String action}) async {
    if (!mounted) return false;
    return await showDialog<bool>(
          context: context,
          builder: (context) => SurfaceConfirmationDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
              TextButton(onPressed: () => Navigator.pop(context, true), child: Text(action)),
            ],
          ),
        ) ??
        false;
  }

  Future<bool> _restoreLibrary() async {
    if (_projectTransferActive || !_documentLoaded) return false;
    _projectTransferActive = true;
    try {
      final bytes = await _projectFiles.open();
      if (bytes == null) return false;
      final imported = await decodeCanvasLibraryArchive(bytes);
      final count = imported.library.files.where((file) => !file.isFolder).length;
      if (!await _confirmReplacement(
        title: 'Replace library?',
        message:
            'Restore $count ${count == 1 ? 'canvas' : 'canvases'}? This replaces all existing canvases and folders.',
        action: 'Replace library',
      )) {
        return false;
      }
      await _replaceAfterFlush(() => _commitImportedLibrary(imported));
      _showProjectSnackBar('Library restored');
      return true;
    } on Object {
      if (!_documentLoaded) {
        _documentLoaded = true;
        if (mounted) setState(() {});
      }
      _showProjectSnackBar('Could not restore library');
      return false;
    } finally {
      _projectTransferActive = false;
    }
  }

  Future<bool> _importProject() async {
    if (_projectTransferActive || !_documentLoaded) return false;
    _projectTransferActive = true;
    try {
      final bytes = await _projectFiles.open();
      if (bytes == null) return false;
      final project = await decodeCanvasProject(bytes);
      if (!await _confirmReplacement(
        title: 'Replace canvas?',
        message: 'Importing replaces “${_documentStore.library.current.name}”.',
        action: 'Replace canvas',
      )) {
        return false;
      }
      await _replaceAfterFlush(() => _commitImportedProject(project));
      _showProjectSnackBar('Canvas imported');
      return true;
    } on Object {
      if (!_documentLoaded) {
        _documentLoaded = true;
        if (mounted) setState(() {});
      }
      _showProjectSnackBar('Could not import canvas');
      return false;
    } finally {
      _projectTransferActive = false;
    }
  }

  Future<void> _replaceAfterFlush(Future<void> Function() commit) async {
    _saveTimer?.cancel();
    _saveTimer = null;
    final dirtyFlush = _documentDirty ? _enqueueDocumentSave(throwOnFailure: true) : null;
    _documentLoaded = false;
    if (dirtyFlush != null) await dirtyFlush;
    final operation = _saveQueue.then((_) => commit());
    _saveQueue = operation.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    );
    await operation;
  }

  Future<void> _commitImportedLibrary(CanvasLibraryArchive imported) async {
    final replacements = <String, String>{};
    final reserved = imported.attachments.keys.toSet();
    for (final path in imported.attachments.keys.toList()..sort()) {
      String fresh;
      do {
        fresh = 'attachments/${const Uuid().v4()}.${path.split('.').last}';
      } while (reserved.contains(fresh) || await _attachmentStore.readIfExists(fresh) != null);
      reserved.add(fresh);
      replacements[path] = fresh;
    }
    final source = imported.library;
    final next = CanvasLibrary(
      files: [
        for (final file in source.files)
          if (file.isFolder)
            file
          else
            file.copyWith(document: rebaseCanvasDocumentAttachments(file.document!, replacements)),
      ],
      currentId: source.currentId,
    );
    for (final entry in replacements.entries) {
      await _attachmentStore.write(entry.value, imported.attachments[entry.key]!);
    }
    await _documentStore.saveLibrary(next);
    _replaceLiveModels(next.current.document!);
    _resetHistory();
  }

  Future<void> _commitImportedProject(CanvasProject imported) async {
    final project = rebaseCanvasProjectAttachments(
      imported,
      _documentStore.library.files
          .where((file) => file.id != _documentStore.library.currentId && !file.isFolder)
          .expand((file) => canvasAttachmentPaths(file.document!))
          .toSet(),
    );
    final currentDocument = _currentDocument();
    final currentPaths = canvasAttachmentPaths(currentDocument);
    final importedPaths = project.attachments.keys.toSet();
    final collisionPaths = currentPaths.intersection(importedPaths).toList()..sort();
    final backups = <String, Uint8List>{};
    final attemptedPaths = <String>[];

    try {
      for (final path in collisionPaths) {
        final bytes = await _attachmentStore.readIfExists(path);
        if (bytes == null) {
          throw StateError('Missing current attachment: $path');
        }
        backups[path] = Uint8List.fromList(bytes);
      }

      try {
        final paths = project.attachments.keys.toList()..sort();
        for (final path in paths) {
          attemptedPaths.add(path);
          await _attachmentStore.write(path, project.attachments[path]!);
        }
        await _persistDocument(project.document);
      } on Object catch (error, stackTrace) {
        Object? rollbackError;
        StackTrace? rollbackStackTrace;
        for (final path in attemptedPaths) {
          final backup = backups[path];
          if (backup == null) continue;
          try {
            await _attachmentStore.write(path, Uint8List.fromList(backup));
          } on Object catch (error, stackTrace) {
            rollbackError ??= error;
            rollbackStackTrace ??= stackTrace;
          }
        }
        if (rollbackError != null) {
          debugPrint(
            'Canvas import rollback failed: $rollbackError\n'
            '$rollbackStackTrace',
          );
        }
        Error.throwWithStackTrace(error, stackTrace);
      }

      _replaceLiveModels(project.document);
      _resetHistory();
    } on Object {
      _documentLoaded = true;
      if (mounted) setState(() {});
      rethrow;
    }
  }

  void _replaceLiveModels(CanvasDocument document) {
    _documentGeneration++;
    _closeContextMenu();
    final oldElements = List<CanvasElementModel>.of(_elements);
    _clearTextEditing();
    FocusManager.instance.primaryFocus?.unfocus();
    _cancelDrawingTools();
    _touchPlacement = null;
    _pointerPan = null;
    _blockedCanvasPointers.addAll(_canvasPointers.keys);
    _activeTool.value = _CanvasTool.select;
    _touchSelectionEnabled = false;
    _activeElement = null;
    _eraserPointer = null;
    _spaceHeld = false;
    _interactiveCanvasPointerIds.clear();
    _selectionBeforeWidgetPointer.clear();
    _selectionBeforeDrag.clear();
    _selectionKeys.clear();
    _widgetPointer = null;
    _dragSelectionPointer = null;
    _dragSelectionStart = null;
    _dragSelectionEnd = null;
    _dragArrowPointer = null;
    _dragArrow = null;
    _editingTextBlock = null;
    _editingChromeModel.value = null;

    for (final model in oldElements) {
      model.removeListener(_geometryListeners.remove(model)!);
      model.documentChanges.removeListener(_scheduleDocumentSave);
      _editorFocusNode(model)?.removeListener(_finishHistoryOperation);
    }
    _elements.clear();
    _canvasController.clear();
    _canvasBackgroundKind = document.background;
    _canvasController.background = document.background.build(
      BTheme.of(context).colors,
    );
    for (final data in document.elements) {
      _mountElement(_createElementModel(data));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final model in oldElements) {
        model.dispose();
      }
    });
    _documentDirty = false;
    _documentLoaded = true;
    if (mounted) setState(() {});
  }

  void _showProjectSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _setCanvasBackground(CanvasBackgroundKind kind) {
    if (!_documentLoaded || _canvasBackgroundKind == kind) return;
    _canvasBackgroundKind = kind;
    _canvasController.background = kind.build(BTheme.of(context).colors);
    _scheduleDocumentSave();
    _finishHistoryOperation();
  }

  // ---------- Keyboard commands ----------

  bool _handleKeyEvent(KeyEvent event) {
    if (!_documentLoaded || _filePickerOpen || ModalRoute.of(context)?.isCurrent == false) return false;
    _selectionModifierPressed.value = Theme.of(context).platform == TargetPlatform.macOS
        ? HardwareKeyboard.instance.isMetaPressed
        : HardwareKeyboard.instance.isControlPressed;
    final unmodifiedKeyDown =
        event is KeyDownEvent &&
        ModalRoute.of(context)?.isCurrent != false &&
        !HardwareKeyboard.instance.isControlPressed &&
        !HardwareKeyboard.instance.isMetaPressed &&
        !HardwareKeyboard.instance.isAltPressed &&
        !HardwareKeyboard.instance.isShiftPressed;
    final keyboard = HardwareKeyboard.instance;
    final macOS = Theme.of(context).platform == TargetPlatform.macOS;
    final arrangeModifier = macOS
        ? keyboard.isMetaPressed && !keyboard.isControlPressed
        : keyboard.isControlPressed && !keyboard.isMetaPressed;
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
        LogicalKeyboardKey.keyT => _CanvasTool.text,
        LogicalKeyboardKey.keyC => _CanvasTool.code,
        LogicalKeyboardKey.keyM => _CanvasTool.media,
        LogicalKeyboardKey.keyS => _CanvasTool.shape,
        LogicalKeyboardKey.keyP => _CanvasTool.pen,
        LogicalKeyboardKey.keyE => _CanvasTool.eraser,
        LogicalKeyboardKey.keyA => _CanvasTool.arrow,
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

  // ---------- Document persistence ----------

  Future<void> _restoreDocument() async {
    try {
      final document = await _documentStore.load();
      if (!mounted) return;
      if (document != null) {
        _canvasBackgroundKind = document.background;
        _canvasController.background = document.background.build(
          BTheme.of(context).colors,
        );
        for (final data in document.elements) {
          _mountElement(_createElementModel(data));
        }
      }
      _documentLoaded = true;
      _resetHistory();
      if (mounted) setState(() {});
    } on Object {
      _resetHistory();
      if (!mounted) return;
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not load saved canvas')),
        );
      });
    }
  }

  CanvasDocument _currentDocument() {
    return CanvasDocument(
      background: _canvasBackgroundKind,
      elements: _elements.map((model) => model.data.copy()).toList(),
    );
  }

  void _scheduleDocumentSave() {
    if (!_documentLoaded) return;
    _noteHistoryChange();
    _documentDirty = true;
    _saveTimer?.cancel();
    _saveTimer = Timer(
      const Duration(milliseconds: 300),
      _enqueueDocumentSave,
    );
  }

  Future<void>? _enqueueDocumentSave({bool throwOnFailure = false}) {
    _saveTimer = null;
    if (!_documentLoaded || !_documentDirty) return null;
    _documentDirty = false;
    final snapshot = _currentDocument();
    final operation = _saveQueue.then(
      (_) => throwOnFailure ? _persistDocument(snapshot) : _saveDocument(snapshot),
    );
    _saveQueue = operation.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    );
    if (!throwOnFailure) return null;
    return _saveAndRestoreDirty(operation);
  }

  Future<void> _saveAndRestoreDirty(Future<void> operation) async {
    try {
      await operation;
    } on Object {
      _documentDirty = true;
      rethrow;
    }
  }

  Future<void> _persistDocument(CanvasDocument document) {
    return _documentStore.save(document);
  }

  Future<void> _saveDocument(CanvasDocument document) async {
    try {
      await _persistDocument(document);
    } on Object {
      _documentDirty = true;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save canvas')),
      );
    }
  }

  // ---------- History ----------

  _CanvasHistoryEntry _captureHistory() => (
    document: jsonEncode(_currentDocument().toJson()),
    tool: _activeTool.value,
    touchSelectionEnabled: _touchSelectionEnabled,
  );

  void _resetHistory() {
    _undoHistory.clear();
    _redoHistory.clear();
    _historyCurrent = _captureHistory();
    _historyOperationActive = false;
  }

  void _noteHistoryChange() {
    if (_historyOperationActive) return;
    final current = _historyCurrent;
    if (current == null) return;
    if (_captureHistory() != current) {
      _historyOperationActive = true;
    }
  }

  void _finishHistoryOperation() {
    if (!_historyOperationActive || !_documentLoaded) {
      return;
    }
    final previous = _historyCurrent;
    final current = _captureHistory();
    _historyOperationActive = false;
    if (previous == null || previous == current) return;
    _undoHistory.add(previous);
    if (_undoHistory.length > _historyLimit) _undoHistory.removeAt(0);
    _redoHistory.clear();
    _historyCurrent = current;
  }

  void _undo() {
    _finishHistoryOperation();
    final current = _historyCurrent;
    if (current == null || _undoHistory.isEmpty) return;
    _redoHistory.add(current);
    _restoreHistory(_undoHistory.removeLast());
  }

  void _redo() {
    _finishHistoryOperation();
    final current = _historyCurrent;
    if (current == null || _redoHistory.isEmpty) return;
    _undoHistory.add(current);
    _restoreHistory(_redoHistory.removeLast());
  }

  void _restoreHistory(_CanvasHistoryEntry entry) {
    final documentChanged = _historyCurrent?.document != entry.document;
    _historyOperationActive = false;
    if (documentChanged) _replaceLiveModels(CanvasDocument.fromJson(jsonDecode(entry.document)));
    _applyTool(entry.tool, touchSelectionEnabled: entry.touchSelectionEnabled);
    _historyCurrent = entry;
    if (documentChanged) _scheduleDocumentSave();
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
    return ContextMenu(
      key: _contextMenuKey,
      controller: _contextMenuController,
      onClose: _contextMenuClosed,
      title: _arrangeMenuOpen ? 'Arrange' : null,
      groups: _arrangeMenuOpen ? _arrangeContextMenuActions() : _objectContextMenuActions(),
      tapRegionGroupId: _activeElement,
      child: canvas,
    );
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
                      (_activeTool.value == _CanvasTool.select ? 0 : kSecondaryMouseButton) |
                      kMiddleMouseButton |
                      (_spaceHeld ? kPrimaryMouseButton : 0),
                ),
              ),
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
                path: _documentStore.library.path(_documentStore.library.currentId).map((file) => file.name).toList(),
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
      (_CanvasTool.text, 'text', 'Place text', LucideIcons.type, 'Text'),
      (_CanvasTool.code, 'code', 'Place code block', LucideIcons.codeXml, 'Code'),
      (_CanvasTool.media, 'media', 'Place media', LucideIcons.image, 'Media'),
      (_CanvasTool.shape, 'shape', 'Draw rounded rectangle', LucideIcons.squareRoundCorner, 'Rect'),
      (_CanvasTool.pen, 'draw', 'Draw with pen', LucideIcons.pencil, 'Draw'),
      (_CanvasTool.eraser, 'erase', 'Erase elements', LucideIcons.eraser, 'Erase'),
      (_CanvasTool.arrow, 'arrow', 'Draw an arrow', LucideIcons.arrowUpRight, 'Arrow'),
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
              onKindChanged: (kind) => _editElement(activeShape, () => activeShape.kind = kind),
              onStrokeColorChanged: (color) => _editElement(activeShape, () => activeShape.strokeColor = color),
              onFillColorChanged: (color) => _editElement(activeShape, () => activeShape.fillColor = color),
              onStrokeWidthChanged: (width) => _editElement(activeShape, () => activeShape.strokeWidth = width),
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
              onColorChanged: (color) => _editElement(activeArrow, () => activeArrow.color = color),
              onStrokeStyleChanged: (style) => _editElement(activeArrow, () => activeArrow.strokeStyle = style),
              onStrokeWidthChanged: (width) => _editElement(activeArrow, () => activeArrow.strokeWidth = width),
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
              onKindChanged: _shapeTool.setKind,
              onStrokeColorChanged: _setShapeStrokeColor,
              onFillColorChanged: _shapeTool.setFillColor,
              onStrokeWidthChanged: _shapeTool.setStrokeWidth,
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
    required this.onKindChanged,
    required this.onStrokeColorChanged,
    required this.onFillColorChanged,
    required this.onStrokeWidthChanged,
    required this.onOutlineColorPickerExpandedChanged,
  });

  final ShapeKind kind;
  final Color strokeColor;
  final Color? fillColor;
  final double strokeWidth;
  final bool outlineColorPickerExpanded;
  final ValueChanged<ShapeKind> onKindChanged;
  final ValueChanged<Color> onStrokeColorChanged;
  final ValueChanged<Color?> onFillColorChanged;
  final ValueChanged<double> onStrokeWidthChanged;
  final ValueChanged<bool> onOutlineColorPickerExpandedChanged;

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
          color: strokeColor,
          expanded: outlineColorPickerExpanded,
          onChanged: onStrokeColorChanged,
          onExpandedChanged: onOutlineColorPickerExpandedChanged,
        ),
        const SizedBox(height: 10),
        Text('Fill', style: theme.typo.label),
        const SizedBox(height: 6),
        _ColorSwatches(
          selectedColor: fillColor,
          keyPrefix: 'shape-fill',
          allowNone: true,
          onColorChanged: onFillColorChanged,
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
    this.streamline,
    this.onStreamlineChanged,
    super.key,
  });

  final Color color;
  final double width;
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

class _ColorSwatches extends StatelessWidget {
  const _ColorSwatches({
    required this.selectedColor,
    required this.keyPrefix,
    required this.onColorChanged,
    this.allowNone = false,
  });

  final Color? selectedColor;
  final String keyPrefix;
  final ValueChanged<Color?> onColorChanged;
  final bool allowNone;

  @override
  Widget build(BuildContext context) {
    final colors = BTheme.of(context).colors;
    return Wrap(
      children: [
        if (allowNone)
          Tooltip(
            message: 'No fill',
            child: ToolbarButton(
              key: ValueKey('$keyPrefix-none'),
              selected: selectedColor == null,
              onPressed: () => onColorChanged(null),
              child: const Icon(LucideIcons.ban, semanticLabel: 'No fill'),
            ),
          ),
        for (final swatch in _toolColorSwatches)
          Tooltip(
            message: swatch.label,
            child: Semantics(
              button: true,
              selected: selectedColor == swatch.color,
              label: swatch.label,
              child: InkWell(
                key: ValueKey('$keyPrefix-${swatch.label.toLowerCase()}'),
                customBorder: const CircleBorder(),
                onTap: () => onColorChanged(swatch.color),
                child: Padding(
                  padding: const EdgeInsets.all(5),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: swatch.color,
                      border: Border.all(
                        color: selectedColor == swatch.color ? colors.focusRing : colors.borderSubtle,
                        width: selectedColor == swatch.color ? 2 : 1,
                      ),
                    ),
                    child: const SizedBox.square(dimension: 22),
                  ),
                ),
              ),
            ),
          ),
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
  final ValueListenable<_CanvasTool> activeTool;
  final ValueListenable<bool> modifierPressed;
  final ValueChanged<PointerDownEvent> onPointerDown;
  final ValueChanged<PointerDownEvent> onSecondaryPointerDown;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final listener = Listener(
      onPointerDown: (event) {
        if (activeTool.value == _CanvasTool.select) {
          onSecondaryPointerDown(event);
          onPointerDown(event);
        }
      },
      child: ListenableBuilder(
        listenable: Listenable.merge([activeTool, modifierPressed]),
        builder: (context, child) => AbsorbPointer(
          absorbing: activeTool.value != _CanvasTool.select || modifierPressed.value && model is! PenStrokeModel,
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
