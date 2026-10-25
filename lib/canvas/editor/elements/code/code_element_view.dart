// Provides minimal, syntax-highlighted code blocks with inline editing controls.
// Used by the canvas code tool and element renderer.

import 'dart:async';

import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/editor/editor_session.dart';
import 'package:elseplane/canvas/editor/elements/code/code_editor_resources.dart';
import 'package:elseplane/canvas/editor/elements/code/code_language.dart';
import 'package:elseplane/canvas/editor/elements/code/code_layout.dart';
import 'package:elseplane/canvas/editor/widgets/resize_handle.dart';
import 'package:elseplane/theme/theme.dart';
import 'package:elseplane/ui/common/glass_surface.dart';
import 'package:elseplane/ui/common/labeled_switch.dart';
import 'package:elseplane/ui/common/pointer_scroll_boundary.dart';
import 'package:elseplane/ui/common/select.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:re_editor/re_editor.dart';

// ---------- Rendering ----------

/// Renders a movable preview or an editable code surface.
/// Used by the canvas element stack.
class CodeElementView extends StatefulWidget {
  const CodeElementView({
    required this.resources,
    required this.data,
    required this.selected,
    required this.active,
    required this.onEdit,
    required this.onMove,
    required this.onResize,
    required this.onChangeBoundary,
    this.onInteract,
    this.onControlPointerDown,
    this.canHandlePointer,
    super.key,
  });

  final CodeEditorResources resources;
  final CodeElementData data;
  final bool selected;
  final bool active;
  final VoidCallback onEdit;
  final VoidCallback? onInteract;
  final ValueChanged<Offset> onMove;
  final ValueChanged<Offset> onResize;
  final VoidCallback onChangeBoundary;
  final ValueChanged<PointerDownEvent>? onControlPointerDown;
  final bool Function(PointerEvent event)? canHandlePointer;

  @override
  State<CodeElementView> createState() => _CodeElementViewState();
}

class _CodeElementViewState extends State<CodeElementView> {
  int? _previewPointer;
  Offset? _previewPointerStart;
  Offset? _previewPointerPosition;
  double _previewDragSlop = 0;
  bool _previewDragging = false;
  bool _previewEditing = false;

  Future<void> _paste({bool intoTitle = false}) async {
    try {
      await widget.resources.paste(intoTitle: intoTitle);
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not paste code')));
    }
  }

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
    _previewEditing = widget.resources.active;
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
      widget.resources.focusNode.unfocus();
      widget.onMove(event.position - start);
    } else {
      widget.onMove(event.position - previous);
    }
    // re_editor still performs text-selection drags while read-only.
    // Collapse that transient selection after every canvas drag update.
    widget.resources.controller.cancelSelection();
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
      widget.onChangeBoundary();
      widget.resources
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
    widget.resources
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
      listenable: widget.resources,
      builder: (context, _) {
        final model = widget.resources;
        final theme = BTheme.of(context);
        final colors = theme.colors;
        final codeStyle = theme.typo.code.copyWith(color: colors.textPrimary);
        final background = _codeSurfaceColor(colors, widget.data, widget.selected, widget.active);
        final transparent = widget.data.background == BlockBackgroundKind.transparent;
        final card = widget.data.background == BlockBackgroundKind.card;
        final editing = widget.active;
        final showTitle = editing || widget.data.title.trim().isNotEmpty;
        final titleTab = _CodeTitleTab(
          resources: model,
          data: widget.data,
          selected: widget.selected,
          active: widget.active,
          editing: editing,
          onInteract: widget.onInteract,
          onPaste: () => unawaited(_paste(intoTitle: true)),
        );
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
                    shortcutOverrideActions: editing
                        ? {
                            CodeShortcutPasteIntent: CallbackAction<CodeShortcutPasteIntent>(
                              onInvoke: (_) {
                                if (!model.controller.isComposing) unawaited(_paste());
                                return null;
                              },
                            ),
                          }
                        : null,
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
                      codeTheme: widget.data.language.theme(theme.syntaxTheme),
                    ),
                    indicatorBuilder: widget.data.showLineNumbers
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
                          value: widget.data.language,
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
                            model.session.setCodeLanguage(model.data.id, language);
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
                        recognizer
                          ..onUpdate = (details) {
                            widget.onResize(details.focalPointDelta);
                          }
                          ..onEnd = (_) => widget.onChangeBoundary();
                      },
                    ),
                  },
                ),
              ),
          ],
        );
        return Semantics(
          container: true,
          selected: widget.selected,
          child: SizedBox.fromSize(
            size: model.canvasSize,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: codeTitleHeight,
                  child: IgnorePointer(
                    ignoring: !showTitle,
                    child: AnimatedSwitcher(
                      duration: widget.data.title.trim().isEmpty ? _codeControlAnimationDuration : Duration.zero,
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
                  size: widget.data.size,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: widget.data.background == BlockBackgroundKind.glass
                            ? GlassSurface(
                                key: const ValueKey('code-block-surface'),
                                selected: widget.selected,
                                borderRadius: theme.geo.radiusMedium,
                                child: codeBody,
                              )
                            : Material(
                                key: const ValueKey('code-block-surface'),
                                type: transparent && !widget.selected ? MaterialType.transparency : MaterialType.canvas,
                                color: transparent && !widget.selected ? null : background,
                                elevation: card ? theme.geo.elevationLow : 0,
                                shadowColor: colors.shadow,
                                shape: RoundedRectangleBorder(
                                  borderRadius: theme.geo.radiusMedium,
                                  side: _codeSurfaceBorder(colors, widget.data, widget.selected, widget.active),
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

// Provides the code tool's compact title, language, and settings controls.
// Used internally by code rendering and by the active-element settings panel.

// ---------- Geometry ----------

const _codeControlInset = 8.0;
const _codeEditorPadding = 10.0;
const _codeControlAnimationDuration = Duration(milliseconds: 220);

Widget _codeControlTransition(Widget child, Animation<double> animation) {
  return FadeTransition(
    opacity: animation,
    child: SlideTransition(
      position: Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero).animate(animation),
      child: child,
    ),
  );
}

// ---------- Backgrounds ----------

Color _codeSurfaceColor(BColors colors, CodeElementData data, bool selected, bool active) {
  if (selected) return colors.accentSoft;
  return data.background == BlockBackgroundKind.transparent ? Colors.transparent : colors.surface;
}

BorderSide _codeSurfaceBorder(BColors colors, CodeElementData data, bool selected, bool active) {
  if (selected) return BorderSide(color: colors.accent, width: 2);
  if (data.background == BlockBackgroundKind.transparent && !active) return BorderSide.none;
  return BorderSide(
    color: colors.borderSubtle,
  );
}

// ---------- Title ----------

class _CodeTitleTab extends StatelessWidget {
  const _CodeTitleTab({
    required this.resources,
    required this.data,
    required this.selected,
    required this.active,
    required this.editing,
    required this.onPaste,
    this.onInteract,
  });

  final CodeEditorResources resources;
  final CodeElementData data;
  final bool selected;
  final bool active;
  final bool editing;
  final VoidCallback onPaste;
  final VoidCallback? onInteract;

  @override
  Widget build(BuildContext context) {
    final theme = BTheme.of(context);
    final colors = theme.colors;
    final style = theme.typo.body.copyWith(color: colors.textHeading);
    final border = _codeSurfaceBorder(colors, data, selected, active);
    final borderRadius = BorderRadius.only(
      topLeft: theme.geo.radiusMedium.topLeft,
      topRight: theme.geo.radiusMedium.topRight,
    );
    return IntrinsicWidth(
      child: Stack(
        key: ValueKey(editing ? 'code-title-input-tab' : 'code-title-tab'),
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            bottom: -theme.geo.radiusMedium.topLeft.y,
            child: data.background == BlockBackgroundKind.glass
                ? GlassSurface(
                    key: ValueKey(editing ? 'code-title-input-tab-surface' : 'code-title-tab-surface'),
                    selected: selected,
                    borderRadius: borderRadius,
                    clipper: _CodeTitleSurfaceClipper(
                      theme.geo.radiusMedium.toRRect(const Offset(0, codeTitleHeight) & data.size),
                    ),
                    child: const SizedBox.expand(),
                  )
                : ClipPath(
                    clipper: _CodeTitleSurfaceClipper(
                      theme.geo.radiusMedium.toRRect(const Offset(0, codeTitleHeight) & data.size),
                    ),
                    child: Container(
                      key: ValueKey(editing ? 'code-title-input-tab-surface' : 'code-title-tab-surface'),
                      decoration: BoxDecoration(
                        color: _codeSurfaceColor(colors, data, selected, active),
                        border: Border(top: border, left: border, right: border),
                        borderRadius: borderRadius,
                      ),
                    ),
                  ),
          ),
          Container(
            constraints: BoxConstraints(minWidth: 76, maxWidth: data.size.width),
            height: codeTitleHeight,
            alignment: Alignment.centerLeft,
            padding: EdgeInsets.fromLTRB(12 + border.width, border.width, 12 + border.width, 0),
            child: Semantics(
              label: editing ? null : data.title,
              child: ExcludeSemantics(
                excluding: !editing,
                child: IgnorePointer(
                  ignoring: !editing,
                  child: Actions(
                    actions: {
                      PasteTextIntent: CallbackAction<PasteTextIntent>(
                        onInvoke: (_) {
                          if (editing) onPaste();
                          return null;
                        },
                      ),
                    },
                    child: TextFormField(
                      key: ValueKey(editing ? 'code-title-input' : 'code-title-text'),
                      contextMenuBuilder: null,
                      onTap: onInteract,
                      onTapAlwaysCalled: true,
                      controller: resources.titleController,
                      focusNode: resources.titleFocusNode,
                      style: style,
                      cursorColor: colors.accent,
                      readOnly: !editing,
                      canRequestFocus: editing,
                      showCursor: editing,
                      enableInteractiveSelection: editing,
                      decoration: InputDecoration(
                        hintText: 'Untitled',
                        hintStyle: style.copyWith(color: colors.textMuted),
                        border: InputBorder.none,
                        isCollapsed: true,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Keeps the extended title surface outside the body's rounded outline.
class _CodeTitleSurfaceClipper extends CustomClipper<Path> {
  const _CodeTitleSurfaceClipper(this.body);

  final RRect body;

  @override
  Path getClip(Size size) => Path.combine(
    PathOperation.difference,
    Path()..addRect(Offset.zero & size),
    Path()..addRRect(body),
  );

  @override
  bool shouldReclip(_CodeTitleSurfaceClipper oldClipper) => body != oldClipper.body;
}

// ---------- Settings ----------

/// Presents line-number and background settings for the active code block.
class CodeToolSettings extends StatelessWidget {
  const CodeToolSettings({
    required this.session,
    required this.id,
    required this.onChangeBoundary,
    super.key,
  });

  final EditorSession session;
  final String id;
  CodeElementData get data => session.element(id)! as CodeElementData;
  final VoidCallback onChangeBoundary;

  @override
  Widget build(BuildContext context) {
    final theme = BTheme.of(context);
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        if (session.element(id) is! CodeElementData) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            LabeledSwitch(
              key: const ValueKey('code-show-line-numbers'),
              label: 'Line numbers',
              value: data.showLineNumbers,
              onChanged: _setShowLineNumbers,
            ),
            const SizedBox(height: 10),
            Text('Background', style: theme.typo.label),
            const SizedBox(height: 6),
            Select<BlockBackgroundKind>(
              key: const ValueKey('code-background-select'),
              value: data.background,
              options: const [
                SelectOption(value: BlockBackgroundKind.transparent, label: 'Transparent'),
                SelectOption(value: BlockBackgroundKind.card, label: 'Card'),
                SelectOption(value: BlockBackgroundKind.glass, label: 'Glass'),
              ],
              onChanged: (background) {
                onChangeBoundary();
                session.setCodeBackground(id, background);
                onChangeBoundary();
              },
            ),
          ],
        );
      },
    );
  }

  void _setShowLineNumbers(bool value) {
    onChangeBoundary();
    session.setLineNumbers(id, value: value);
    onChangeBoundary();
  }
}

// ---------- Clipboard edits ----------

extension CodeClipboardEdits on CodeEditorResources {
  Future<void> paste({bool intoTitle = false}) async {
    final token = session.captureEdit(data.id);
    try {
      final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
      if (!token.isCurrent || !attached) return;
      final text = clipboard?.text;
      if (text == null || text.isEmpty) return;
      if (intoTitle) {
        final value = titleController.value;
        final selection = value.selection.isValid
            ? value.selection
            : TextSelection.collapsed(offset: value.text.length);
        titleController.value = FilteringTextInputFormatter.singleLineFormatter.formatEditUpdate(
          value,
          value
              .replaced(selection, text)
              .copyWith(
                selection: TextSelection.collapsed(offset: selection.start + text.length),
              ),
        );
      } else {
        controller.replaceSelection(text);
      }
    } on Object {
      if (!token.isCurrent || !attached) return;
      rethrow;
    }
  }
}
