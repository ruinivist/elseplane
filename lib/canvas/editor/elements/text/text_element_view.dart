// Renders and resizes a persisted canvas text tool element.
// Used by the canvas element stack for text display and editing.

import 'package:elseplane/attachments/attachment_store.dart';
import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/editor/elements/text/text_editor_resources.dart';
import 'package:elseplane/canvas/editor/elements/text/text_markdown_editor.dart';
import 'package:elseplane/canvas/editor/elements/text/text_markdown_preview.dart';
import 'package:elseplane/canvas/editor/widgets/resize_handle.dart';
import 'package:elseplane/theme/theme.dart';
import 'package:elseplane/ui/common/glass_surface.dart';
import 'package:elseplane/ui/common/icon_drag.dart';
import 'package:elseplane/ui/common/pointer_scroll_boundary.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

// ---------- Creation defaults ----------

const textNodeDefaultWidth = 420.0;
const textNodeDefaultHeight = 220.0;

// ---------- Text tool ----------

/// Switches a text element between Markdown editing and preview surfaces.
/// Used by the canvas element stack with resize and selection chrome.
class TextElementView extends StatelessWidget {
  const TextElementView({
    required this.resources,
    required this.data,
    required this.selected,
    required this.active,
    required this.attachmentStore,
    required this.onEdit,
    required this.onMove,
    required this.onResize,
    this.onInteract,
    this.onChangeEnd,
    super.key,
  });

  final TextEditorResources resources;
  final TextElementData data;
  final bool selected;
  final bool active;
  final AttachmentStore attachmentStore;
  final VoidCallback onEdit;
  final VoidCallback? onInteract;
  final ValueChanged<Offset> onMove;
  final VoidCallback? onChangeEnd;
  final void Function(Size renderedSize, Offset delta) onResize;

  @override
  Widget build(BuildContext context) {
    final model = resources;
    final theme = BTheme.of(context);
    final colors = theme.colors;
    return Material(
      type: MaterialType.transparency,
      child: ListenableBuilder(
        listenable: model,
        builder: (context, _) {
          assert(active || !model.editing, 'An inactive text block cannot be editing.');
          final transparent = data.style.background == BlockBackgroundKind.transparent;
          final glass = data.style.background == BlockBackgroundKind.glass;
          final body = model.editing
              ? TextMarkdownEditor(model: resources, attachmentStore: attachmentStore, onInteract: onInteract)
              : TextMarkdownPreview(
                  source: data.markdown,
                  style: data.style,
                  scrollController: data.height == null ? null : model.scrollController,
                  onEdit: onEdit,
                  onInteract: onInteract,
                  onMove: onMove,
                  onChangeEnd: onChangeEnd,
                  attachmentStore: attachmentStore,
                );
          final configuredBody = ScrollConfiguration(
            behavior: const _TextBlockScrollBehavior(),
            child: body,
          );
          final visibleBody = data.height == null
              ? configuredBody
              : Scrollbar(
                  controller: model.scrollController,
                  thumbVisibility: true,
                  child: PointerScrollBoundary(child: configuredBody),
                );
          final resizeGestureFactory = immediateDragGestureFactory(
            (_) => CallbackDrag((delta) => onResize(context.size!, delta), onEnd: onChangeEnd),
          );
          const resizeRecognizer = ImmediateMultiDragGestureRecognizer;
          final surfaceBody = SizedBox(
            width: data.width,
            height: data.height,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: textNodeMinimumHeight),
              child: Stack(
                children: [
                  if (data.height != null) Positioned.fill(child: visibleBody) else visibleBody,
                  Positioned(
                    right: 2,
                    bottom: 2,
                    child: IgnorePointer(
                      ignoring: !active,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 260),
                        reverseDuration: const Duration(milliseconds: 180),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeOutCubic,
                        transitionBuilder: _resizeHandleTransition,
                        child: active
                            ? TextFieldTapRegion(
                                child: ResizeHandle(
                                  key: const ValueKey('text-block-resize-handle'),
                                  semanticLabel: 'Resize text block',
                                  gestures: {resizeRecognizer: resizeGestureFactory},
                                ),
                              )
                            : const SizedBox(
                                key: ValueKey('text-block-resize-handle-hidden'),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
          final surface = Material(
            key: const ValueKey('text-block-surface'),
            type: transparent && !selected ? MaterialType.transparency : MaterialType.canvas,
            color: selected
                ? colors.accentSoft
                : transparent
                ? null
                : colors.surface,
            elevation: transparent ? 0 : theme.geo.elevationLow,
            shadowColor: colors.shadow,
            shape: RoundedRectangleBorder(
              borderRadius: theme.geo.radiusLarge,
              side: selected
                  ? BorderSide(color: colors.accent, width: 2)
                  : transparent && !model.editing
                  ? BorderSide.none
                  : BorderSide(color: colors.borderSubtle),
            ),
            child: surfaceBody,
          );
          return Semantics(
            container: true,
            selected: selected,
            child: glass
                ? GlassSurface(
                    key: const ValueKey('text-block-surface'),
                    selected: selected,
                    child: surfaceBody,
                  )
                : surface,
          );
        },
      ),
    );
  }
}

// ---------- Scrolling and transitions ----------

class _TextBlockScrollBehavior extends MaterialScrollBehavior {
  const _TextBlockScrollBehavior();

  @override
  Widget buildScrollbar(BuildContext context, Widget child, ScrollableDetails details) => child;
}

Widget _resizeHandleTransition(Widget child, Animation<double> animation) {
  return FadeTransition(
    opacity: animation,
    child: ScaleTransition(
      scale: Tween<double>(begin: 0.94, end: 1).animate(animation),
      alignment: Alignment.bottomRight,
      child: child,
    ),
  );
}
