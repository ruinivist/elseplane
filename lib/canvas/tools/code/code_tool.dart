// Provides minimal, syntax-highlighted code blocks with inline editing controls.
// Used by the canvas code tool and element renderer.

import 'dart:math' as math;

import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/editor/canvas_element_model.dart';
import 'package:elseplane/canvas/editor/widgets/pointer_scroll_boundary.dart';
import 'package:elseplane/canvas/editor/widgets/resize_handle.dart';
import 'package:elseplane/canvas/tools/code/code_language.dart';
import 'package:elseplane/theme/theme.dart';
import 'package:elseplane/ui/common/glass_surface.dart';
import 'package:elseplane/ui/common/labeled_switch.dart';
import 'package:elseplane/ui/common/select.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';
import 'package:scroll_animator/scroll_animator.dart';

export 'code_language.dart';

part 'code_tool_helpers.dart';
part 'code_tool_model.dart';

// ---------- Rendering ----------

/// Renders a movable preview or an editable code surface.
/// Used by the canvas element stack.
class CodeTool extends StatefulWidget {
  const CodeTool({
    required this.model,
    required this.onEdit,
    required this.onMove,
    required this.onResize,
    required this.onChangeBoundary,
    this.onInteract,
    this.onControlPointerDown,
    this.canHandlePointer,
    super.key,
  });

  final CodeBlockModel model;
  final VoidCallback onEdit;
  final VoidCallback? onInteract;
  final ValueChanged<Offset> onMove;
  final ValueChanged<Offset> onResize;
  final VoidCallback onChangeBoundary;
  final ValueChanged<PointerDownEvent>? onControlPointerDown;
  final bool Function(PointerEvent event)? canHandlePointer;

  @override
  State<CodeTool> createState() => _CodeToolState();
}

class _CodeToolState extends State<CodeTool> {
  int? _previewPointer;
  Offset? _previewPointerStart;
  Offset? _previewPointerPosition;
  double _previewDragSlop = 0;
  bool _previewDragging = false;
  bool _previewEditing = false;

  void _handlePreviewPointerDown(PointerDownEvent event) {
    if (widget.canHandlePointer?.call(event) == false) return;
    if (event.buttons != kPrimaryButton || _previewPointer != null) return;
    _previewPointer = event.pointer;
    _previewPointerStart = event.position;
    _previewPointerPosition = event.position;
    _previewDragSlop = computePanSlop(
      event.kind,
      MediaQuery.maybeGestureSettingsOf(context),
    );
    _previewDragging = false;
    _previewEditing = widget.model.active;
  }

  void _handlePreviewPointerMove(PointerMoveEvent event) {
    if (event.pointer != _previewPointer) return;
    if (widget.canHandlePointer?.call(event) == false) {
      _clearPreviewPointer();
      return;
    }
    final start = _previewPointerStart!;
    final previous = _previewPointerPosition!;
    if (_previewEditing) {
      if (!_previewDragging && (event.position - start).distance > _previewDragSlop) {
        _previewDragging = true;
        widget.onInteract?.call();
      }
      return;
    }
    if (!_previewDragging) {
      if ((event.position - start).distance <= _previewDragSlop) return;
      _previewDragging = true;
      widget.model.focusNode.unfocus();
      widget.onMove(event.position - start);
    } else {
      widget.onMove(event.position - previous);
    }
    // re_editor still performs text-selection drags while read-only.
    // Collapse that transient selection after every canvas drag update.
    widget.model.controller.cancelSelection();
    _previewPointerPosition = event.position;
  }

  void _handlePreviewPointerUp(PointerUpEvent event) {
    if (event.pointer != _previewPointer) return;
    final dragging = _previewDragging;
    final editing = _previewEditing;
    _clearPreviewPointer();
    if (widget.canHandlePointer?.call(event) == false) return;
    if (editing) {
      if (!dragging) widget.onInteract?.call();
      return;
    }
    if (dragging) {
      widget.model
        ..focusNode.unfocus()
        ..controller.cancelSelection();
    } else {
      widget.onEdit();
    }
  }

  void _handlePreviewPointerCancel(PointerCancelEvent event) {
    if (event.pointer != _previewPointer) return;
    final editing = _previewEditing;
    _clearPreviewPointer();
    if (editing || widget.canHandlePointer?.call(event) == false) return;
    widget.model
      ..focusNode.unfocus()
      ..controller.cancelSelection();
  }

  void _clearPreviewPointer() {
    _previewPointer = null;
    _previewPointerStart = null;
    _previewPointerPosition = null;
    _previewDragging = false;
    _previewEditing = false;
  }

  Widget _previewInteraction(Widget editor, {Key? key}) {
    return Listener(
      key: key ?? const ValueKey('code-block-preview-surface'),
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handlePreviewPointerDown,
      onPointerMove: _handlePreviewPointerMove,
      onPointerUp: _handlePreviewPointerUp,
      onPointerCancel: _handlePreviewPointerCancel,
      child: editor,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.model,
      builder: (context, _) {
        final model = widget.model;
        final theme = BTheme.of(context);
        final colors = theme.colors;
        final codeStyle = theme.typo.code.copyWith(color: colors.textPrimary);
        final background = _codeSurfaceColor(colors, model);
        final transparent = model.background == BlockBackgroundKind.transparent;
        final card = model.background == BlockBackgroundKind.card;
        final editing = model.active;
        final showTitle = editing || model.title.trim().isNotEmpty;
        final titleTab = _CodeTitleTab(model: model, editing: editing, onInteract: widget.onInteract);
        final codeBody = Stack(
          children: [
            Positioned.fill(
              child: _previewInteraction(
                PointerScrollBoundary(
                  child: CodeEditor(
                    controller: model.controller,
                    scrollController: model.scrollController,
                    focusNode: model.focusNode,
                    autofocus: false,
                    readOnly: !editing,
                    showCursorWhenReadOnly: false,
                    padding: const EdgeInsets.fromLTRB(
                      _codeEditorPadding,
                      _codeEditorPadding,
                      _codeEditorPadding,
                      _codeEditorPadding,
                    ),
                    style: CodeEditorStyle(
                      fontFamily: codeStyle.fontFamily,
                      fontFamilyFallback: codeStyle.fontFamilyFallback,
                      fontSize: codeStyle.fontSize,
                      fontHeight: codeStyle.height,
                      textColor: colors.textPrimary,
                      backgroundColor: Colors.transparent,
                      cursorColor: colors.accent,
                      selectionColor: colors.accentSubtle,
                      codeTheme: model.language.theme(theme.syntaxTheme),
                    ),
                    indicatorBuilder: model.showLineNumbers
                        ? (context, controller, chunkController, notifier) => ColoredBox(
                            key: const ValueKey('code-line-numbers'),
                            color: card ? colors.surfaceSubtle : Colors.transparent,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              child: DefaultCodeLineNumber(
                                controller: controller,
                                notifier: notifier,
                                minNumberCount: 1,
                                textStyle: codeStyle.copyWith(color: colors.textMuted),
                                focusedTextStyle: codeStyle.copyWith(color: colors.textSecondary),
                              ),
                            ),
                          )
                        : null,
                  ),
                ),
              ),
            ),
            Positioned(
              right: _codeControlInset,
              top: _codeControlInset,
              child: IgnorePointer(
                ignoring: !editing,
                child: AnimatedSwitcher(
                  duration: _codeControlAnimationDuration,
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeOutCubic,
                  transitionBuilder: _codeControlTransition,
                  child: editing
                      ? SearchableSelect<CodeLanguage>(
                          key: const ValueKey('code-language-picker'),
                          value: model.language,
                          preferredValues: CodeLanguage.values,
                          searchHint: 'Search languages…',
                          onMenuPointerDown: widget.onControlPointerDown,
                          options: [
                            for (final language in CodeLanguage.values)
                              SelectOption(value: language, label: language.label),
                          ],
                          showBorder: false,
                          onChanged: (language) {
                            widget.onChangeBoundary();
                            model.language = language;
                            widget.onChangeBoundary();
                          },
                        )
                      : const SizedBox(key: ValueKey('code-language-picker-hidden')),
                ),
              ),
            ),
            if (editing)
              Positioned(
                right: 0,
                bottom: 0,
                child: ResizeHandle(
                  key: const ValueKey('code-block-resize-handle'),
                  semanticLabel: 'Resize code block',
                  gestures: {
                    ScaleGestureRecognizer: GestureRecognizerFactoryWithHandlers<ScaleGestureRecognizer>(
                      () => ScaleGestureRecognizer(
                        allowedButtonsFilter: (buttons) => buttons == kPrimaryButton,
                      ),
                      (recognizer) {
                        recognizer.onUpdate = (details) => widget.onResize(details.focalPointDelta);
                      },
                    ),
                  },
                ),
              ),
          ],
        );
        return Semantics(
          container: true,
          selected: model.selected,
          child: SizedBox.fromSize(
            size: model.canvasSize,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: _codeTitleHeight,
                  child: IgnorePointer(
                    ignoring: !showTitle,
                    child: AnimatedSwitcher(
                      duration: model.title.trim().isEmpty ? _codeControlAnimationDuration : Duration.zero,
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeOutCubic,
                      transitionBuilder: _codeControlTransition,
                      child: showTitle
                          ? editing
                                ? titleTab
                                : _previewInteraction(titleTab, key: const ValueKey('code-title-preview-surface'))
                          : const SizedBox(key: ValueKey('code-title-hidden')),
                    ),
                  ),
                ),
                SizedBox.fromSize(
                  size: model.size,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: model.background == BlockBackgroundKind.glass
                            ? GlassSurface(
                                key: const ValueKey('code-block-surface'),
                                selected: model.selected,
                                borderRadius: theme.geo.radiusMedium,
                                child: codeBody,
                              )
                            : Material(
                                key: const ValueKey('code-block-surface'),
                                type: transparent && !model.selected ? MaterialType.transparency : MaterialType.canvas,
                                color: transparent && !model.selected ? null : background,
                                elevation: card ? theme.geo.elevationLow : 0,
                                shadowColor: colors.shadow,
                                shape: RoundedRectangleBorder(
                                  borderRadius: theme.geo.radiusMedium,
                                  side: _codeSurfaceBorder(colors, model),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: codeBody,
                              ),
                      ),
                      if (!editing)
                        // re_editor hardcodes a text cursor in its code-field renderer.
                        // Keep inactive blocks on the normal canvas pointer instead.
                        const Positioned.fill(
                          child: MouseRegion(
                            cursor: SystemMouseCursors.basic,
                            opaque: false,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
