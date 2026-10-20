// Renders and resizes a persisted canvas text tool element.
// Used by the canvas element stack for text display and editing.

import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/editor/widgets/resize_handle.dart';
import 'package:elseplane/canvas/persistence/attachments/store.dart';
import 'package:elseplane/canvas/tools/text/text_block_model.dart';
import 'package:elseplane/canvas/tools/text/text_markdown_editor.dart';
import 'package:elseplane/canvas/tools/text/text_markdown_preview.dart';
import 'package:elseplane/theme/theme.dart';
import 'package:elseplane/ui/common/glass_surface.dart';
import 'package:elseplane/ui/common/icon_drag.dart';
import 'package:elseplane/ui/common/pointer_scroll_boundary.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

export 'text_block_model.dart';
export 'text_tool_settings.dart';

// ---------- Creation defaults ----------

const textNodeDefaultWidth = 420.0;
const textNodeDefaultHeight = 220.0;

// ---------- Text tool ----------

/// Switches a text element between Markdown editing and preview surfaces.
/// Used by the canvas element stack with resize and selection chrome.
class TextTool extends StatelessWidget {
  const TextTool({
    required this.model,
    required this.attachmentStore,
    required this.onEdit,
    required this.onMove,
    required this.onResize,
    this.onInteract,
    super.key,
  });

  final TextBlockModel model;
  final AttachmentStore attachmentStore;
  final VoidCallback onEdit;
  final VoidCallback? onInteract;
  final ValueChanged<Offset> onMove;
  final void Function(Size renderedSize, Offset delta) onResize;

  @override
  Widget build(BuildContext context) {
    final theme = BTheme.of(context);
    final colors = theme.colors;
    return Material(
      type: MaterialType.transparency,
      child: ListenableBuilder(
        listenable: model,
        builder: (context, _) {
          assert(model.active || !model.editing, 'An inactive text block cannot be editing.');
          final transparent = model.style.background == BlockBackgroundKind.transparent;
          final glass = model.style.background == BlockBackgroundKind.glass;
          final body = model.editing
              ? TextMarkdownEditor(model: model, attachmentStore: attachmentStore, onInteract: onInteract)
              : TextMarkdownPreview(
                  source: model.node.markdown,
                  style: model.style,
                  scrollController: model.node.height == null ? null : model.scrollController,
                  onEdit: onEdit,
                  onInteract: onInteract,
                  onMove: onMove,
                  attachmentStore: attachmentStore,
                );
          final configuredBody = ScrollConfiguration(
            behavior: const _TextBlockScrollBehavior(),
            child: body,
          );
          final visibleBody = model.node.height == null
              ? configuredBody
              : Scrollbar(
                  controller: model.scrollController,
                  thumbVisibility: true,
                  child: PointerScrollBoundary(child: configuredBody),
                );
          final resizeGestureFactory = immediateDragGestureFactory(
            (_) => CallbackDrag((delta) => onResize(context.size!, delta)),
          );
          const resizeRecognizer = ImmediateMultiDragGestureRecognizer;
          final surfaceBody = SizedBox(
            width: model.node.width,
            height: model.node.height,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: textNodeMinimumHeight),
              child: Stack(
                children: [
                  if (model.node.height != null) Positioned.fill(child: visibleBody) else visibleBody,
                  Positioned(
                    right: 2,
                    bottom: 2,
                    child: IgnorePointer(
                      ignoring: !model.active,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 260),
                        reverseDuration: const Duration(milliseconds: 180),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeOutCubic,
                        transitionBuilder: _resizeHandleTransition,
                        child: model.active
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
            type: transparent && !model.selected ? MaterialType.transparency : MaterialType.canvas,
            color: model.selected
                ? colors.accentSoft
                : transparent
                ? null
                : colors.surface,
            elevation: transparent ? 0 : theme.geo.elevationLow,
            shadowColor: colors.shadow,
            shape: RoundedRectangleBorder(
              borderRadius: theme.geo.radiusLarge,
              side: model.selected
                  ? BorderSide(color: colors.accent, width: 2)
                  : transparent && !model.editing
                  ? BorderSide.none
                  : BorderSide(color: colors.borderSubtle),
            ),
            child: surfaceBody,
          );
          return Semantics(
            container: true,
            selected: model.selected,
            child: glass
                ? GlassSurface(
                    key: const ValueKey('text-block-surface'),
                    selected: model.selected,
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
