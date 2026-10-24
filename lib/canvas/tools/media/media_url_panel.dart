// Renders media URL entry, file selection, and panel dragging.
// Used internally by the media tool before and after image loading.

part of 'media_tool.dart';

// ---------- URL panel ----------

class _MediaUrlPanel extends StatelessWidget {
  const _MediaUrlPanel({
    required this.model,
    required this.onActivate,
    required this.onPickImage,
    required this.onPaste,
    this.onMove,
  });

  final MediaModel model;
  final VoidCallback onActivate;
  final VoidCallback onPickImage;
  final VoidCallback onPaste;
  final ValueChanged<Offset>? onMove;

  @override
  Widget build(BuildContext context) {
    final theme = BTheme.of(context);
    final colors = theme.colors;
    return SizedBox(
      key: const ValueKey('media-url-panel'),
      width: model.urlPanelWidth,
      child: Surface(
        selected: model.selected,
        raised: false,
        child: Stack(
          children: [
            Actions(
              actions: {
                PasteTextIntent: CallbackAction<PasteTextIntent>(
                  onInvoke: (_) {
                    onPaste();
                    return null;
                  },
                ),
              },
              child: TextField(
                key: const ValueKey('media-url-field'),
                groupId: model,
                contextMenuBuilder: null,
                controller: model.controller,
                focusNode: model.focusNode,
                onTap: onActivate,
                onTapOutside: (_) {
                  model.session.invalidatePendingEdits();
                  model.commitUrl();
                  model.focusNode.unfocus();
                },
                onSubmitted: (_) {
                  model.session.invalidatePendingEdits();
                  model.commitUrl();
                },
                minLines: 1,
                maxLines: 3,
                textAlignVertical: TextAlignVertical.center,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.done,
                cursorColor: colors.accent,
                style: theme.typo.body.copyWith(color: colors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Paste link',
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  suffixIcon: IconButton(
                    key: const ValueKey('media-device-picker'),
                    tooltip: 'Choose image from device',
                    onPressed: onPickImage,
                    icon: const Icon(LucideIcons.imageUp, size: 20),
                  ),
                ),
              ),
            ),
            if (onMove case final move?)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 8,
                child: MouseRegion(
                  cursor: SystemMouseCursors.grab,
                  child: RawGestureDetector(
                    key: const ValueKey('media-panel-drag-strip'),
                    behavior: HitTestBehavior.opaque,
                    gestures: {
                      ImmediateMultiDragGestureRecognizer: immediateDragGestureFactory((_) => CallbackDrag(move)),
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
