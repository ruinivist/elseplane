// Projects editor snapshots into the grid and retains element rendering resources.
// Used by CanvasPage beneath page chrome and application dialogs.

import 'dart:async';
import 'dart:math' as math;

import 'package:elseplane/attachments/attachment_store.dart';
import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/editor/canvas_background.dart';
import 'package:elseplane/canvas/editor/canvas_clipboard.dart';
import 'package:elseplane/canvas/editor/canvas_input.dart';
import 'package:elseplane/canvas/editor/canvas_shortcuts.dart';
import 'package:elseplane/canvas/editor/editor_session.dart';
import 'package:elseplane/canvas/editor/element_resources.dart';
import 'package:elseplane/canvas/editor/elements/arrow/arrow_element_view.dart';
import 'package:elseplane/canvas/editor/elements/code/code_editor_resources.dart';
import 'package:elseplane/canvas/editor/elements/code/code_element_view.dart';
import 'package:elseplane/canvas/editor/elements/code/code_layout.dart';
import 'package:elseplane/canvas/editor/elements/media/media_element_view.dart';
import 'package:elseplane/canvas/editor/elements/media/media_resources.dart';
import 'package:elseplane/canvas/editor/elements/pen/pen_element_view.dart';
import 'package:elseplane/canvas/editor/elements/pen/pen_preview.dart';
import 'package:elseplane/canvas/editor/elements/pen/pen_resources.dart';
import 'package:elseplane/canvas/editor/elements/shape/shape_element_view.dart';
import 'package:elseplane/canvas/editor/elements/shape/shape_preview.dart';
import 'package:elseplane/canvas/editor/elements/text/text_editor_resources.dart';
import 'package:elseplane/canvas/editor/elements/text/text_element_view.dart';
import 'package:elseplane/canvas/editor/media_source.dart';
import 'package:elseplane/canvas/editor/tools/arrow_tool.dart';
import 'package:elseplane/canvas/editor/tools/pen_tool.dart';
import 'package:elseplane/canvas/editor/tools/shape_tool.dart';
import 'package:elseplane/canvas/editor/widgets/element_transform_controls.dart';
import 'package:elseplane/canvas/editor/widgets/zoom_control.dart';
import 'package:elseplane/canvas/geometry/element_geometry.dart';
import 'package:elseplane/canvas/geometry/transforms.dart';
import 'package:elseplane/theme/fonts.dart';
import 'package:elseplane/theme/preset_colors.dart';
import 'package:elseplane/theme/theme.dart';
import 'package:elseplane/ui/common/context_menu.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:infinite_lazy_grid/infinite_lazy_grid.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:uuid/uuid.dart';

// ---------- Canvas workspace ----------

/// Projects the editor session into the canvas, tools, and workspace controls.
/// Used as the application's primary interactive workspace.
class CanvasView extends StatefulWidget {
  // ---------- Construction ----------

  const CanvasView({
    required this.session,
    required this.attachmentStore,
    required this.chromeBuilder,
    required this.onOpenLibrary,
    this.blocked = false,
    this.libraryOpen = false,
    this.readClipboard,
    this.writeClipboardText,
    super.key,
  });
  final EditorSession session;
  final AttachmentStore attachmentStore;
  final Widget Function(BuildContext, CanvasInput) chromeBuilder;
  final Future<void> Function(CanvasInput) onOpenLibrary;
  final bool blocked;
  final bool libraryOpen;
  final Future<CanvasClipboardSnapshot> Function()? readClipboard;
  final Future<void> Function(String)? writeClipboardText;

  @override
  State<CanvasView> createState() => _CanvasViewState();
}

class _CanvasViewState extends State<CanvasView> implements CanvasInputViewport {
  // ---------- Constants ----------

  final _canvasController = LazyCanvasController(
    minScale: 0.5,
    maxScale: 2,
    buildExtentMultiplier: 3.4,
    useIdsFromArgs: true,
  );
  EditorSession get _session => widget.session;
  CanvasBackgroundKind get _canvasBackgroundKind => _session.document.background;
  AttachmentStore get _attachmentStore => widget.attachmentStore;
  final _elements = <CanvasElementData>[];
  CanvasDocument? _projectedDocument;
  final MenuController _contextMenuController = MenuController();
  final GlobalKey _contextMenuKey = GlobalKey();
  final Object _contextMenuTapRegionGroup = Object();
  final _contextMenuFocusNode = FocusNode(debugLabel: 'Canvas context menu');
  List<CanvasElementData> _contextMenuTargets = const [];
  (Offset, double)? _contextMenuView;
  Offset? _contextMenuPosition;
  bool _arrangeMenuOpen = false;
  final _geometryListeners = <String, VoidCallback>{};
  final _resources = <String, ElementResources>{};
  final _declaredSizes = <String, Size>{};
  CanvasElementData? get _activeElement => _elements.where((a) => a.id == _session.activeId).firstOrNull;
  final ValueNotifier<CanvasElementData?> _editingChromeModel = ValueNotifier(null);
  final _selectionKeys = <Object, GlobalKey>{};
  final _controlsOverlayController = OverlayPortalController();
  final GlobalKey _controlsPortalKey = GlobalKey();
  late CanvasInput _input;
  final _targets = <String, CanvasInputTarget>{};
  CanvasInputTarget _target(CanvasElementData value) {
    final target = _targets[value.id];
    if (target != null && target.attached) return target;
    return _targets[value.id] = _input.target(value.id);
  }

  ValueNotifier<bool> get _selectionModifierPressed => _input.modifierPressed;
  ValueNotifier<Offset?> get _canvasPointerPosition => _input.pointerPosition;
  bool get _spaceHeld => _input.spaceHeld;
  bool get _canvasInputBlocked => _input.blocked;
  bool get _documentLoaded => _session.isLive && !widget.blocked;
  bool get _filePickerOpen => widget.libraryOpen;

  PenTool get _penTool => _input.pen;
  ArrowTool get _arrowTool => _input.arrow;
  ShapeTool get _shapeTool => _input.shape;
  bool get _penEnabled => _session.tool == CanvasTool.pen;

  bool get _eraserEnabled => _session.tool == CanvasTool.eraser;

  ArrowElementData? get _activeArrow => switch (_activeElement) {
    final ArrowElementData a => a,
    _ => null,
  };
  ClipboardEvents? _clipboardEvents;
  late CanvasClipboard _clipboard;
  late CanvasShortcuts _shortcuts;

  // ---------- Lifecycle ----------

  @override
  void initState() {
    super.initState();
    _controlsOverlayController.show();
    _canvasController.addListener(_closeContextMenuOnNavigation);
    _attachSession();
  }

  void _attachSession() {
    _input = CanvasInput(
      session: _session,
      viewport: this,
      enabled: () => _documentLoaded,
      panSlop: (kind) => computePanSlop(kind, MediaQuery.maybeGestureSettingsOf(context)),
      onCloseMenu: _closeContextMenu,
      onOpenMenu: (id, position) => _openCanvasContextMenu(_element(id), position),
      onEndEditing: _clearElementEditing,
      onFocusElement: _focusElement,
      onPlace: (position) => switch (_session.tool) {
        CanvasTool.text => _addTextBlock(position),
        CanvasTool.code => _addCodeBlock(position),
        CanvasTool.media => _addMedia(position),
        _ => null,
      },
      onStroke: _addStroke,
      onArrow: _addArrow,
      onShape: _addShape,
    )..addListener(_handleDrawingToolChanged);
    _session.addListener(_sessionChanged);
    _canvasController
      ..rawPointerDownListener = _input.pointerDown
      ..rawPointerMoveListener = _input.pointerMove
      ..rawPointerUpListener = _input.pointerUp
      ..rawPointerCancelListener = _input.pointerCancel;
    _clipboard = CanvasClipboard(
      session: _session,
      attachments: _attachmentStore,
      enabled: () => mounted && _documentLoaded && ModalRoute.of(context)?.isCurrent != false,
      menuOpen: () => _contextMenuController.isOpen,
      editing: () => _editingElement,
      pointerPosition: () => _canvasPointerPosition.value,
      scale: () => _canvasController.scale,
      screenToCanvas: _screenToCanvas,
      viewportSize: () => _canvasController.canvasSize,
      boundsOf: (value) => elementBounds(
        value,
        codeTitleHeight: codeTitleHeight,
        mediaSize: const Size(mediaUrlPanelMinimumWidth, mediaUrlPanelCanvasHeight),
      ),
      mediaWidth: mediaNodeDefaultWidth,
      clearEditing: () {
        _clearTextEditing();
        _setActiveElement(null);
      },
      onError: _showClipboardError,
      readClipboard: widget.readClipboard,
      writeClipboardText: widget.writeClipboardText,
    );
    _shortcuts = CanvasShortcuts(
      input: _input,
      fieldForFocus: _fieldForFocus,
      macOS: () => Theme.of(context).platform == TargetPlatform.macOS,
      enabled: () => _documentLoaded,
      blocked: () => widget.libraryOpen,
      currentRoute: () => ModalRoute.of(context)?.isCurrent != false,
      editing: () => _editingElement,
      menuOpen: () => _contextMenuController.isOpen,
      foreignMenuOpen: () {
        final focus = FocusManager.instance.primaryFocus?.context;
        return focus != null && MenuController.maybeOf(focus)?.isOpen == true;
      },
      nativeClipboard: () => _clipboardEvents != null,
      openLibrary: () => widget.onOpenLibrary(_input),
      arrange: ({required forward, required toEnd}) {
        final targets = _arrangeTargets;
        if (_contextMenuController.isOpen) {
          _closeContextMenu();
        } else {
          if (_selectedInStackingOrder.isEmpty) _setSelection(targets.toSet());
          _clearElementEditing();
        }
        _arrange(
          forward
              ? (toEnd ? CanvasArrange.front : CanvasArrange.forward)
              : (toEnd ? CanvasArrange.back : CanvasArrange.backward),
          targets,
        );
      },
      copy: ({required cut}) {
        final targets = _contextMenuController.isOpen ? _contextMenuTargets : null;
        if (targets != null) _closeContextMenu();
        if (_canCopyDirectly) unawaited(_copySelection(null, cut: cut, targets: targets));
      },
      paste: () {
        final position = _contextMenuPosition;
        _closeContextMenu();
        if (_canPasteDirectly) unawaited(_pasteSelection(null, position: position));
      },
      delete: () {
        final selected = _selectedInStackingOrder;
        final targets = _contextMenuController.isOpen
            ? _contextMenuTargets
            : selected.isNotEmpty
            ? selected
            : [?_activeElement];
        _closeContextMenu();
        _removeElements(targets);
      },
      closeMenu: _closeContextMenu,
      escape: () {
        if (_editingElement || _activeElement != null) {
          _clearElementEditing();
        } else {
          _input.toggleTool(_session.tool);
        }
        _clearSelection();
      },
      selectAll: _selectAll,
    );
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    FocusManager.instance.addListener(_shortcuts.focusChanged);
    _clipboardEvents = widget.readClipboard == null && widget.writeClipboardText == null
        ? ClipboardEvents.instance
        : null;
    _clipboardEvents
      ?..registerCopyEventListener(_handleWebCopy)
      ..registerCutEventListener(_handleWebCut)
      ..registerPasteEventListener(_handleWebPaste);
  }

  CanvasElementData? _element(String? id) => _elements.where((a) => a.id == id).firstOrNull;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_projectedDocument == null) _sessionChanged();
    _canvasController.background = _canvasBackgroundKind.build(BTheme.of(context).colors);
  }

  @override
  void didUpdateWidget(CanvasView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.session, widget.session)) {
      _detachSession(oldWidget.session);
      _attachSession();
      _sessionChanged();
    } else if (!oldWidget.blocked && widget.blocked) {
      _input.interrupt();
    }
  }

  void _detachSession(EditorSession session) {
    session
      ..invalidatePendingEdits()
      ..removeListener(_sessionChanged);
    FocusManager.instance.removeListener(_shortcuts.focusChanged);
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _closeContextMenu();
    _clipboardEvents
      ?..unregisterCopyEventListener(_handleWebCopy)
      ..unregisterCutEventListener(_handleWebCut)
      ..unregisterPasteEventListener(_handleWebPaste);
    _input.removeListener(_handleDrawingToolChanged);
    _input.dispose();
    _detachModels(List.of(_elements));
    _targets.clear();
    _projectedDocument = null;
  }

  FocusNode? _editorFocusNode(CanvasElementData value) => switch (_resources[value.id]) {
    final TextEditorResources resource => resource.focusNode,
    final CodeEditorResources resource => resource.focusNode,
    final MediaResources resource => resource.focusNode,
    _ => null,
  };

  EditorContext? _fieldForFocus(FocusNode node) {
    for (final value in _elements) {
      final resource = _resources[value.id];
      final field = switch (resource) {
        final TextEditorResources text when identical(node, text.focusNode) => EditorField.markdown,
        final CodeEditorResources code when identical(node, code.focusNode) => EditorField.source,
        final CodeEditorResources code when identical(node, code.titleFocusNode) => EditorField.title,
        final MediaResources media when identical(node, media.focusNode) => EditorField.mediaUrl,
        _ => null,
      };
      if (field != null) return (id: value.id, field: field);
    }
    return null;
  }

  void _invalidatePendingEdits() => _shortcuts.invalidatePendingEdits();

  @override
  void dispose() {
    _detachSession(_session);
    _contextMenuFocusNode.dispose();
    _editingChromeModel.dispose();
    _canvasController.removeListener(_closeContextMenuOnNavigation);
    _canvasController.dispose();
    super.dispose();
  }

  void _sessionChanged() {
    final document = _session.document;
    if (!identical(_projectedDocument, document)) {
      final previous = _projectedDocument;
      _projectedDocument = document;
      final values = {for (final value in document.elements) value.id: value};
      _detachModels(_elements.where((value) => values[value.id]?.runtimeType != value.runtimeType).toList());
      final oldIds = _elements.map((a) => a.id).toSet();
      _elements
        ..clear()
        ..addAll(document.elements);
      for (final value in _elements) {
        if (!oldIds.contains(value.id)) {
          _mountElement(value);
        } else {
          _syncGeometry(value);
        }
      }
      _canvasController.setChildOrder(document.elements.map((a) => a.id).toList());
      if (previous?.background != document.background) {
        _canvasController.background = document.background.build(BTheme.of(context).colors);
      }
    }
    if (_activeElement case final active?) _editingChromeModel.value = active;
    if (mounted) setState(() {});
  }

  // ---------- Input presentation effects ----------

  void _handleDrawingToolChanged() {
    if (mounted) setState(() {});
  }

  bool _canHandleCanvasPointer(PointerEvent event) => _input.canHandle(event);
  void _handleObjectControlPointerDown(PointerDownEvent event) {
    final active = _activeElement;
    if (active != null) _target(active).pointerDown(event, control: true);
  }

  void _focusElement(String id, {bool edit = false}) {
    final value = _element(id);
    if (value == null) return;
    _editingChromeModel.value = value;
    if (value is TextElementData && edit) {
      _session.editField((id: id, field: EditorField.markdown));
      _editorFocusNode(value)?.requestFocus();
    }
    if (value is CodeElementData) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _session.activeId == id && _session.element(id) is CodeElementData) {
          final focus = _editorFocusNode(value)!..unfocus();
          FocusManager.instance.applyFocusChangesIfNeeded();
          focus.requestFocus();
        }
      });
    }
  }

  void _startTextEditing(TextElementData model) {
    _setActiveElement(model);
    _focusElement(model.id, edit: true);
  }

  void _clearTextEditing() {
    if (_session.editing?.field == EditorField.markdown) _session.editField(null);
  }

  void _clearElementEditing({bool commitMediaDraft = true}) {
    _invalidatePendingEdits();
    if (commitMediaDraft) {
      for (final resource in _resources.values.whereType<MediaResources>()) {
        if (resource.focusNode.hasFocus) resource.commitUrl();
      }
    }
    _session.editField(null);
    FocusManager.instance.primaryFocus?.unfocus();
    _session.setActive(null);
  }

  void _setActiveElement(CanvasElementData? model) {
    if (model != null) _session.promoteAuto([model.id]);
    _session.setActive(model?.id);
    if (model != null) _editingChromeModel.value = model;
  }

  void _clearSelection() => _session.setSelection(const []);
  void _setSelection(Set<Object> values, {bool preserveContext = false}) =>
      _session.setSelection(values.cast<CanvasElementData>().map((a) => a.id), preserveContext: preserveContext);

  Offset _screenToCanvas(Offset position) => screenToCanvas(position);

  // ---------- Object context menu and ordering ----------

  List<CanvasElementData> get _arrangeTargets {
    if (_contextMenuController.isOpen) return _contextMenuTargets;
    final selected = _selectedInStackingOrder;
    return selected.isNotEmpty ? selected : [?_activeElement];
  }

  void _openArrangeMenu(CanvasElementData value, Rect buttonBounds) {
    if (_canvasInputBlocked || _session.element(value.id) == null || _session.tool != CanvasTool.select) return;
    final selection = _input.selectionBeforePointer;
    if (selection.contains(value.id) && selection.length > 1) {
      _session.setSelection(selection);
      // TODO(zero): Selected groups need their own menu for move, rotate, arrange, and delete.
      throw UnimplementedError('Arrange controls for selected groups');
    }
    _session.setSelection([value.id]);
    final left = buttonBounds.left - ContextMenu.width - 4;
    final position = Offset(
      left >= MediaQuery.paddingOf(context).left ? left : buttonBounds.right + 4,
      buttonBounds.top,
    );
    _openCanvasContextMenu(value, position, arrangeOnly: true);
  }

  void _openCanvasContextMenu(CanvasElementData? model, Offset position, {bool arrangeOnly = false}) {
    if ((model != null && _session.element(model.id) == null) || _session.tool != CanvasTool.select) return;
    _clearElementEditing();
    if (model != null) _promoteAuto([model]);
    _finishHistoryOperation();
    if (model != null && !_session.isSelected(model.id)) _setSelection({model});
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
    if (!_input.hasPointer(event.pointer) && event.buttons == kPrimaryButton && !_selectionModifierPressed.value) {
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
    _contextMenuController.close();
    _contextMenuClosed();
  }

  void _closeContextMenuOnNavigation() {
    if (_contextMenuView case final view? when view != (_canvasController.offset, _canvasController.scale)) {
      _closeContextMenu();
    }
  }

  bool _canArrange(CanvasArrange action, List<CanvasElementData> targets) {
    if (targets.isEmpty || targets.any((model) => _session.element(model.id) == null)) return false;
    try {
      return _canvasController.canArrange(targets.map((model) => model.id), action) ||
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

  void _arrange(CanvasArrange action, List<CanvasElementData> targets) {
    if (!_canArrange(action, targets)) return;
    _finishHistoryOperation();
    final ids = targets.map((model) => model.id).toList();
    _session.arrange(ids, _canvasController.arrangedOrder(ids, action));
    _finishHistoryOperation();
  }

  void _setAutoArrange(List<CanvasElementData> targets, bool value) {
    if (targets.isEmpty || targets.any((model) => _session.element(model.id) == null)) return;
    _finishHistoryOperation();
    _session.setAutoArrange(targets.map((model) => model.id), value: value);
    _finishHistoryOperation();
  }

  void _promoteAuto(Iterable<CanvasElementData> targets, {bool contentChanged = false}) {
    if (!_documentLoaded || (!contentChanged && _canvasInputBlocked)) return;
    _session.promoteAuto(targets.where((a) => _session.element(a.id) != null).map((model) => model.id));
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

  GlobalKey _selectionKey(CanvasElementData model) => _selectionKeys.putIfAbsent(model.id, GlobalKey.new);

  void _moveSelectedChildren(CanvasElementData model, Offset delta) => _target(model).move(delta);

  void _resizeTextBlock(TextElementData model, Size renderedSize, Offset screenDelta) {
    if (_canvasInputBlocked || !_documentLoaded || _session.element(model.id) == null) return;
    _target(
      model,
    ).transform(() => _session.resizeText(model.id, renderedSize, _localTransformDelta(_rotation(model), screenDelta)));
  }

  void _resizeCodeBlock(CodeElementData model, Offset localDelta) {
    if (_canvasInputBlocked || !_documentLoaded || _session.element(model.id) == null) return;
    _target(model).transform(
      () => _session.resizeCode(
        model.id,
        Size(
          (_session.element(model.id)! as CodeElementData).size.width + localDelta.dx,
          (_session.element(model.id)! as CodeElementData).size.height + localDelta.dy,
        ),
      ),
    );
  }

  void _resizeMedia(MediaElementData model, Offset screenDelta) {
    if (_canvasInputBlocked ||
        !_documentLoaded ||
        _session.element(model.id) == null ||
        (_resources[model.id]! as MediaResources).aspectRatio == null) {
      return;
    }
    _target(model).transform(
      () => _session.resizeMedia(
        model.id,
        _localTransformDelta(_rotation(model), screenDelta),
        (_resources[model.id]! as MediaResources).aspectRatio!,
      ),
    );
  }

  void _resizeShape(ShapeElementData model, Offset screenDelta) {
    if (_canvasInputBlocked || !_documentLoaded || _session.element(model.id) == null) return;
    _target(model).transform(() => _session.resizeShape(model.id, screenDelta / _canvasController.scale));
  }

  Offset _localTransformDelta(double rotation, Offset screenDelta) =>
      screenDeltaToLocal(screenDelta, scale: _canvasController.scale, rotation: rotation);

  void _rotateElement(CanvasElementData model, double angle) {
    if (_canvasInputBlocked || !_documentLoaded || _session.element(model.id) == null) return;
    _target(model).transform(() => _session.rotate(model.id, angle));
  }

  Offset _elementCenter(CanvasElementData model) {
    final renderObject = _selectionKey(
      model,
    ).currentContext?.findRenderObject();
    if (renderObject is! RenderBox) return Offset.zero;
    final center = model is CodeElementData
        ? Offset(model.size.width / 2, _bounds(model).size.height - model.size.height / 2)
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
    final model = _elements.whereType<TextElementData>().firstWhere((model) => model.id == node.id);
    _editorFocusNode(model)?.requestFocus();
    _startTextEditing(model);
  }

  void _addMedia(Offset position) {
    if (!_documentLoaded) return;
    final value = _newMediaData('').copyWith(position: position);
    _session.insert([value], returnToSelect: true);
    final model = _elements.firstWhere((model) => model.id == value.id);
    _setActiveElement(model);
    _editorFocusNode(model)?.requestFocus();
  }

  ElementResources? _createResources(CanvasElementData value) => switch (value) {
    final TextElementData a => TextEditorResources(_session, a),
    final CodeElementData a => CodeEditorResources(_session, a),
    final MediaElementData a => MediaResources(_session, a, _attachmentStore),
    final PenElementData a => PenResources(_session, a),
    _ => null,
  };

  void _mountElement(CanvasElementData value) {
    final resource = _createResources(value);
    if (resource != null) _resources[value.id] = resource;
    _declaredSizes[value.id] = _bounds(value).size;
    _canvasController.addChild(
      _bounds(value).topLeft,
      ListenableBuilder(
        key: ObjectKey(_session.elementLifetime(value.id)),
        listenable: Listenable.merge([_session, _input, _editingChromeModel, ?resource]),
        builder: (context, _) {
          final current = _session.element(value.id);
          if (current == null || current.runtimeType != value.runtimeType) return const SizedBox.shrink();
          return Stack(
            clipBehavior: Clip.none,
            children: [
              _buildElement(current),
              if (_editingChromeModel.value?.id == current.id) Positioned.fill(child: _buildControlsPortal()),
            ],
          );
        },
      ),
      id: value.id,
      childSize: _bounds(value).size,
      rotation: _rotation(value),
    );
    if (resource != null) {
      void sync() {
        final current = _session.element(value.id);
        if (current != null) _syncGeometry(current);
      }

      _geometryListeners[value.id] = sync;
      resource.addListener(sync);
    }
  }

  Widget _buildElement(CanvasElementData value) {
    final target = _target(value);
    final selected = _session.isSelected(value.id);
    final active = _session.activeId == value.id;
    final child = switch (value) {
      final TextElementData a => TextElementView(
        data: a,
        resources: _resources[a.id]! as TextEditorResources,
        selected: selected,
        active: active,
        attachmentStore: _attachmentStore,
        onEdit: () => target.activate(edit: true),
        onInteract: target.interact,
        onMove: target.move,
        onChangeEnd: target.finish,
        onResize: (size, delta) => _resizeTextBlock(a, size, delta),
      ),
      final CodeElementData a => CodeElementView(
        data: a,
        resources: _resources[a.id]! as CodeEditorResources,
        selected: selected,
        active: active,
        onEdit: () => target.activate(edit: true),
        onInteract: target.interact,
        onMove: target.move,
        onResize: (delta) => _resizeCodeBlock(a, delta),
        onChangeBoundary: target.finish,
        onControlPointerDown: (event) => target.pointerDown(event, control: true),
        canHandlePointer: _canHandleCanvasPointer,
      ),
      final MediaElementData a => MediaElementView(
        data: a,
        resources: _resources[a.id]! as MediaResources,
        selected: selected,
        active: active,
        onActivate: target.activate,
        onMove: target.move,
        onChangeEnd: target.finish,
        onResize: (delta) => _resizeMedia(a, delta),
        onPanelPointerDown: (event) => target.pointerDown(event, control: true),
        onDeactivate: () {
          if (!_contextMenuController.isOpen && _session.activeId == a.id) _setActiveElement(null);
        },
      ),
      final ShapeElementData a => ShapeElementView(
        data: a,
        selected: selected,
        active: active,
        onActivate: target.activate,
        onMove: target.move,
        onChangeEnd: target.finish,
        onResize: (delta) => _resizeShape(a, delta),
      ),
      final PenElementData a => PenElementView(
        data: a,
        resources: _resources[a.id]! as PenResources,
        selected: selected,
        active: active,
        onTap: target.interact,
        onMove: target.move,
      ),
      final ArrowElementData a => ArrowElementView(data: a, selected: selected, active: active),
    };
    return _CanvasElementHost(
      key: _selectionKey(value),
      model: value,
      session: _session,
      modifierPressed: _selectionModifierPressed,
      onPointerDown: target.pointerDown,
      child: child,
    );
  }

  Rect _bounds(CanvasElementData value) => elementBounds(
    value,
    codeTitleHeight: codeTitleHeight,
    mediaSize: value is MediaElementData
        ? (_resources[value.id] as MediaResources?)?.canvasSize ??
              const Size(mediaUrlPanelMinimumWidth, mediaUrlPanelCanvasHeight)
        : Size.zero,
  );
  double _rotation(CanvasElementData value) => switch (value) {
    TextElementData(:final rotation) ||
    CodeElementData(:final rotation) ||
    MediaElementData(:final rotation) => rotation,
    _ => 0,
  };
  bool _canRotate(CanvasElementData value) =>
      value is TextElementData ||
      value is CodeElementData ||
      value is MediaElementData && (_resources[value.id]! as MediaResources).hasImage;
  void _syncGeometry(CanvasElementData value) {
    final bounds = _bounds(value);
    _canvasController.update(
      value.id,
      position: bounds.topLeft,
      rotation: _rotation(value),
      childSize: bounds.size != _declaredSizes[value.id] ? bounds.size : null,
    );
    _declaredSizes[value.id] = bounds.size;
  }

  // ---------- Drawing tools ----------

  void _handleCanvasPointerExit(PointerExitEvent event) => _input.exit(event);

  void _handleCanvasPointerHover(PointerHoverEvent event) => _input.hover(event);

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
    final model = _elements.firstWhere((model) => model.id == value.id);
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
    _setActiveElement(_elements.firstWhere((model) => model.id == value.id));
  }

  void _addShape(ShapeElementData value) {
    if (!_documentLoaded) return;
    _session.insert([value], returnToSelect: true);
    _setActiveElement(_elements.firstWhere((model) => model.id == value.id));
  }

  void _startArrowPointEdit() {
    if (_canvasInputBlocked) return;
    _finishHistoryOperation();
    _clearSelection();
  }

  void _editArrowPoint(
    ArrowElementData model,
    int point,
    Offset position,
  ) {
    if (_canvasInputBlocked) return;
    if (!_documentLoaded || _session.activeId != model.id || _session.element(model.id) == null) return;
    _target(model).transform(() => _session.setArrowPoint(model.id, point, position));
  }

  // ---------- Editing commands ----------

  void _selectAll() {
    if (!_documentLoaded) return;
    _session.setSelection(_session.document.elements.map((value) => value.id));
  }

  // ---------- Clipboard ----------

  bool get _editingElement {
    final focusContext = FocusManager.instance.primaryFocus?.context;
    return focusContext?.widget is EditableText ||
        focusContext?.findAncestorWidgetOfExactType<EditableText>() != null ||
        _elements.whereType<TextElementData>().any(
          (model) => _editorFocusNode(model)?.hasFocus ?? false,
        ) ||
        _elements.whereType<CodeElementData>().any(
          (model) => _editorFocusNode(model)?.hasFocus ?? false,
        ) ||
        _elements.whereType<MediaElementData>().any(
          (model) => _editorFocusNode(model)?.hasFocus ?? false,
        );
  }

  List<CanvasElementData> get _selectedInStackingOrder =>
      _elements.where((model) => _session.isSelected(model.id)).toList();

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

  Future<void> _copySelection(ClipboardWriter? writer, {bool cut = false, List<CanvasElementData>? targets}) =>
      _clipboard.copy(writer, cut: cut, targets: targets?.map((a) => a.id).toList());
  Future<void> _pasteSelection(Future<ClipboardReader>? reader, {Offset? position}) =>
      _clipboard.paste(reader, position: position);
  MediaElementData _newMediaData(String url) => _clipboard.newMedia(url);

  // ---------- Erasing ----------

  void _removeElements(Iterable<CanvasElementData> models, {bool finishHistory = true}) {
    if (!_documentLoaded) return;
    final ids = models.where((a) => _session.element(a.id) != null).map((model) => model.id).toList();
    if (ids.isEmpty) return;
    if (finishHistory) _finishHistoryOperation();
    _session.remove(ids);
    if (finishHistory) _finishHistoryOperation();
  }

  void _detachModels(List<CanvasElementData> values) {
    if (values.isEmpty) return;
    final ids = values.map((a) => a.id).toSet();
    if (_contextMenuTargets.any((a) => ids.contains(a.id))) _closeContextMenu();
    if (ids.contains(_editingChromeModel.value?.id)) _editingChromeModel.value = null;
    final retired = <ElementResources>[];
    for (final id in ids) {
      final resource = _resources.remove(id);
      if (resource != null) {
        resource.detach();
        final listener = _geometryListeners.remove(id);
        if (listener != null) resource.removeListener(listener);
        retired.add(resource);
      }
      _canvasController.removeChild(id);
      _elements.removeWhere((a) => a.id == id);
      _targets.remove(id);
      _selectionKeys.remove(id);
      _declaredSizes.remove(id);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final resource in retired) {
        resource.dispose();
      }
    });
  }

  // ---------- Workspace presentation and replacement ----------

  void _showClipboardError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  // ---------- Keyboard commands ----------

  bool _handleKeyEvent(KeyEvent event) => _shortcuts.handle(event);

  // ---------- History ----------

  void _finishHistoryOperation() => _input.finishOperation();

  // ---------- Rendering ----------

  Widget _buildControlsPortal() => OverlayPortal.overlayChildLayoutBuilder(
    key: _controlsPortalKey,
    controller: _controlsOverlayController,
    overlayChildBuilder: (_, layout) {
      final anchor = _editingChromeModel.value;
      final bodyOffset = anchor is CodeElementData ? layout.childSize.height - anchor.size.height : 0.0;
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
                  final CanvasElementData editing => ListenableBuilder(
                    key: ValueKey(editing.id),
                    listenable: _session,
                    builder: (context, child) => IgnorePointer(
                      ignoring: !(_session.activeId == editing.id),
                      child: child,
                    ),
                    child: Listener(
                      onPointerDown: _handleObjectControlPointerDown,
                      child: ElementTransformControls(
                        key: ValueKey(editing.id),
                        elementName: editing.type,
                        rotation: _rotation(editing),
                        tapRegionGroupId: editing is MediaElementData ? _resources[editing.id] : null,
                        onMove: (delta) => _moveSelectedChildren(editing, delta),
                        onArrange: (bounds) => _openArrangeMenu(editing, bounds),
                        onRotate: switch (editing) {
                          final CanvasElementData model when _canRotate(model) => (angle) => _rotateElement(
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
                          if (editing is TextElementData) {
                            _clearTextEditing();
                          } else {
                            _finishHistoryOperation();
                          }
                        },
                        onTransformEnd: _target(editing).finish,
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
          if (_input.marquee case final rect?)
            Positioned.fromRect(
              key: const ValueKey('drag-selection-marquee'),
              rect: rect,
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
                listenable: Listenable.merge([_session, _canvasController]),
                builder: (context, _) => Listener(
                  onPointerDown: _handleObjectControlPointerDown,
                  child: ArrowEditor(
                    data: activeArrow,
                    selected: _session.isSelected(activeArrow.id),
                    active: true,
                    canvasOffset: _canvasController.offset,
                    canvasScale: _canvasController.scale,
                    onChangeStart: _startArrowPointEdit,
                    onPointChanged: (point, position) => _editArrowPoint(activeArrow, point, position),
                    onChangeEnd: _target(activeArrow).finish,
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
    return Stack(
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
                foregroundChildId: _activeElement?.id,
                touchNavigationMode: TouchNavigationMode.twoFinger,
                onTouchNavigationChanged: (active) => _input.navigationChanged(active: active),
                viewportBuilder: _buildCanvasViewport,
                mousePanButtons:
                    (_session.tool == CanvasTool.select ? 0 : kSecondaryMouseButton) |
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
        Positioned.fill(child: widget.chromeBuilder(context, _input)),
      ],
    );
  }

  // ---------- Measured viewport ----------
  @override
  Offset globalToScreen(Offset position) => (context.findRenderObject()! as RenderBox).globalToLocal(position);
  @override
  void stopAnimation() => _canvasController.stopAnimation();
  @override
  double get scale => _canvasController.scale;
  @override
  Offset screenToCanvas(Offset screenPosition) => _canvasController.offset + screenPosition / scale;
  @override
  Iterable<String> overlapping(Rect screenRect) => _canvasController.overlappingChildren(
    Rect.fromPoints(screenToCanvas(screenRect.topLeft), screenToCanvas(screenRect.bottomRight)),
  );

  @override
  Iterable<String> hitTest(Offset globalPosition) sync* {
    for (final model in _elements) {
      final box = _selectionKeys[model.id]?.currentContext?.findRenderObject();
      if (box is RenderBox && box.hitTest(BoxHitTestResult(), position: box.globalToLocal(globalPosition))) {
        yield model.id;
      }
    }
  }

  @override
  void startPan(Offset screenPosition) {
    _canvasController.onScaleStart(ScaleStartDetails(localFocalPoint: screenPosition));
  }

  @override
  void updatePan(Offset screenPosition, Offset screenDelta) {
    _canvasController.onScaleUpdate(ScaleUpdateDetails(localFocalPoint: screenPosition, focalPointDelta: screenDelta));
  }

  @override
  void endPan(Velocity velocity) {
    _canvasController.onScaleEnd(ScaleEndDetails(velocity: velocity));
  }
}

// ---------- Selection chrome ----------

class _CanvasElementHost extends StatelessWidget {
  const _CanvasElementHost({
    required this.model,
    required this.session,
    required this.modifierPressed,
    required this.onPointerDown,
    required this.child,
    super.key,
  });

  final CanvasElementData model;
  final EditorSession session;
  final ValueListenable<bool> modifierPressed;
  final ValueChanged<PointerDownEvent> onPointerDown;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final listener = Listener(
      onPointerDown: (event) {
        if (session.tool == CanvasTool.select) {
          onPointerDown(event);
        }
      },
      child: ListenableBuilder(
        listenable: Listenable.merge([session, modifierPressed]),
        builder: (context, child) => AbsorbPointer(
          absorbing: session.tool != CanvasTool.select || modifierPressed.value && model is! PenElementData,
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
