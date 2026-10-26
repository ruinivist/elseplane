// Provides media import, storage, sizing, rendering, and interaction.
// Used by the canvas media tool and persisted media elements.

import 'dart:async';
import 'dart:typed_data';

import 'package:elseplane/attachments/attachment_store.dart';
import 'package:elseplane/attachments/image_import.dart';
import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/editor/canvas_clipboard.dart';
import 'package:elseplane/canvas/editor/elements/media/media_resources.dart';
import 'package:elseplane/canvas/editor/widgets/resize_handle.dart';
import 'package:elseplane/theme/theme.dart';
import 'package:elseplane/ui/common/icon_drag.dart';
import 'package:elseplane/ui/common/surface.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:uuid/uuid.dart';

const _imageTypes = XTypeGroup(
  label: 'images',
  extensions: ['png', 'jpg', 'jpeg', 'gif', 'webp'],
  mimeTypes: ['image/png', 'image/jpeg', 'image/gif', 'image/webp'],
  uniformTypeIdentifiers: [
    'public.png',
    'public.jpeg',
    'com.compuserve.gif',
    'org.webmproject.webp',
  ],
);

// ---------- Creation defaults ----------

const mediaNodeDefaultWidth = 480.0;

// ---------- Media tool ----------

/// Renders a media element or its URL entry panel.
/// Used by the canvas element stack for persisted media models.
class MediaElementView extends StatefulWidget {
  const MediaElementView({
    required this.resources,
    required this.data,
    required this.selected,
    required this.active,
    required this.onMove,
    required this.onResize,
    required this.onActivate,
    required this.onDeactivate,
    this.onPanelPointerDown,
    this.onChangeEnd,
    super.key,
  });

  final MediaResources resources;
  final MediaElementData data;
  final bool selected;
  final bool active;
  final ValueChanged<Offset> onMove;
  final VoidCallback? onChangeEnd;
  final ValueChanged<Offset> onResize;
  final VoidCallback onActivate;
  final VoidCallback onDeactivate;
  final PointerDownEventListener? onPanelPointerDown;

  @override
  State<MediaElementView> createState() => _MediaElementViewState();
}

class _MediaElementViewState extends State<MediaElementView> {
  // ---------- State ----------

  final _portalController = OverlayPortalController();
  ClipboardEvents? get _clipboardEvents => ClipboardEvents.instance;

  // ---------- Lifecycle and actions ----------

  @override
  void initState() {
    super.initState();
    _clipboardEvents?.registerPasteEventListener(_onWebPaste);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _portalController.show();
    });
  }

  @override
  void dispose() {
    _clipboardEvents?.unregisterPasteEventListener(_onWebPaste);
    super.dispose();
  }

  void _onWebPaste(ClipboardReadEvent event) {
    if (!widget.resources.focusNode.hasFocus) return;
    unawaited(_paste(event.getClipboardReader()));
  }

  Future<void> _paste(Future<ClipboardReader> readerFuture) async {
    try {
      await widget.resources.paste(readerFuture);
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not paste image')),
      );
    }
  }

  void _pasteFromClipboard() {
    final clipboard = SystemClipboard.instance;
    if (clipboard != null) unawaited(_paste(clipboard.read()));
  }

  Future<void> _pickImage() async {
    widget.onActivate();
    final model = widget.resources;
    final token = model.session.captureEdit(model.data.id);
    try {
      final file = await openFile(acceptedTypeGroups: const [_imageTypes]);
      if (file == null || !token.isCurrent || !model.attached) return;
      final separator = file.name.lastIndexOf('.');
      if (separator < 0) throw const FormatException('Missing image type');
      final length = await file.length();
      if (!token.isCurrent || !model.attached) return;
      validateAttachmentSize(length, 'Image exceeds 10 MiB');
      final bytes = await file.readAsBytes();
      if (!token.isCurrent || !model.attached) return;
      await model.setDeviceImage(
        bytes,
        file.name.substring(separator + 1),
      );
    } on Object {
      if (!mounted || !token.isCurrent || !model.attached) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not open image')));
    }
  }

  // ---------- Rendering ----------

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.resources,
      builder: (context, _) {
        final model = widget.resources;
        return Semantics(
          container: true,
          image: model.hasImage,
          selected: widget.selected,
          label: model.hasImage ? 'Image media' : 'Image URL',
          child: OverlayPortal.overlayChildLayoutBuilder(
            controller: _portalController,
            overlayChildBuilder: (context, layout) {
              final panelWidth = model.urlPanelWidth;
              return Positioned(
                left: 0,
                top: 0,
                child: Transform(
                  transform: layout.childPaintTransform,
                  alignment: Alignment.topLeft,
                  child: Transform.translate(
                    offset: Offset(
                      (layout.childSize.width - panelWidth) / 2,
                      layout.childSize.height + 8,
                    ),
                    child: SizedBox(
                      width: panelWidth,
                      child: IgnorePointer(
                        ignoring: !widget.active || !model.hasImage,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 260),
                          reverseDuration: const Duration(milliseconds: 180),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeOutCubic,
                          transitionBuilder: _mediaTransition,
                          child: widget.active && model.hasImage
                              ? TapRegion(
                                  groupId: model,
                                  child: Listener(
                                    onPointerDown: widget.onPanelPointerDown,
                                    child: _MediaUrlPanel(
                                      resources: model,
                                      selected: widget.selected,
                                      active: widget.active,
                                      onActivate: widget.onActivate,
                                      onPickImage: _pickImage,
                                      onPaste: _pasteFromClipboard,
                                    ),
                                  ),
                                )
                              : const SizedBox(
                                  key: ValueKey('media-url-panel-hidden'),
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
            child: model.hasImage
                ? TapRegion(
                    groupId: model,
                    onTapOutside: (_) => widget.onDeactivate(),
                    child: _MediaImage(
                      resources: model,
                      data: widget.data,
                      selected: widget.selected,
                      active: widget.active,
                      onActivate: widget.onActivate,
                      onMove: widget.onMove,
                      onChangeEnd: widget.onChangeEnd,
                      onResize: widget.onResize,
                    ),
                  )
                : _MediaUrlPanel(
                    resources: model,
                    selected: widget.selected,
                    active: widget.active,
                    onActivate: widget.onActivate,
                    onMove: widget.onMove,
                    onChangeEnd: widget.onChangeEnd,
                    onPickImage: _pickImage,
                    onPaste: _pasteFromClipboard,
                  ),
          ),
        );
      },
    );
  }
}

// Renders a loaded media image with selection and resize affordances.
// Used internally by the media tool after image resolution succeeds.

// ---------- Image ----------

class _MediaImage extends StatefulWidget {
  const _MediaImage({
    required this.resources,
    required this.data,
    required this.selected,
    required this.active,
    required this.onActivate,
    required this.onMove,
    required this.onResize,
    this.onChangeEnd,
  });

  final MediaResources resources;
  final MediaElementData data;
  final bool selected;
  final bool active;
  final VoidCallback onActivate;
  final ValueChanged<Offset> onMove;
  final VoidCallback? onChangeEnd;
  final ValueChanged<Offset> onResize;

  @override
  State<_MediaImage> createState() => _MediaImageState();
}

class _MediaImageState extends State<_MediaImage> {
  Offset? _dragPosition;

  @override
  Widget build(BuildContext context) {
    final theme = BTheme.of(context);
    final colors = theme.colors;
    final model = widget.resources;
    final image = model.image!;
    return SizedBox.fromSize(
      size: model.canvasSize,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        dragStartBehavior: DragStartBehavior.down,
        onTap: widget.onActivate,
        onPanStart: (details) => _dragPosition = details.globalPosition,
        onPanUpdate: (details) {
          final position = details.globalPosition;
          widget.onMove(position - _dragPosition!);
          _dragPosition = position;
        },
        onPanEnd: (_) {
          _dragPosition = null;
          widget.onChangeEnd?.call();
        },
        onPanCancel: () {
          if (_dragPosition == null) return;
          _dragPosition = null;
          widget.onChangeEnd?.call();
        },
        child: Stack(
          children: [
            Positioned.fill(
              child: ClipRRect(
                borderRadius: theme.geo.radiusSmall,
                clipBehavior: Clip.antiAliasWithSaveLayer,
                child: Image(
                  key: const ValueKey('media-image'),
                  image: image,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            if (widget.selected)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: theme.geo.radiusSmall,
                      border: Border.all(color: colors.accent, width: 2),
                    ),
                  ),
                ),
              ),
            Positioned(
              right: 0,
              bottom: 0,
              child: IgnorePointer(
                ignoring: !widget.active,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  reverseDuration: const Duration(milliseconds: 180),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeOutCubic,
                  transitionBuilder: (child, animation) => _mediaTransition(child, animation, Alignment.bottomRight),
                  child: widget.active
                      ? ResizeHandle(
                          key: const ValueKey('media-resize-handle'),
                          semanticLabel: 'Resize media',
                          showCornerSurface: true,
                          gestures: {
                            ImmediateMultiDragGestureRecognizer: immediateDragGestureFactory(
                              (_) => CallbackDrag(widget.onResize, onEnd: widget.onChangeEnd),
                            ),
                          },
                        )
                      : const SizedBox(
                          key: ValueKey('media-resize-handle-hidden'),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Renders media URL entry, file selection, and panel dragging.
// Used internally by the media tool before and after image loading.

// ---------- URL panel ----------

class _MediaUrlPanel extends StatefulWidget {
  const _MediaUrlPanel({
    required this.resources,
    required this.selected,
    required this.active,
    required this.onActivate,
    required this.onPickImage,
    required this.onPaste,
    this.onMove,
    this.onChangeEnd,
  });

  final MediaResources resources;
  final bool selected;
  final bool active;
  final VoidCallback onActivate;
  final VoidCallback onPickImage;
  final VoidCallback onPaste;
  final ValueChanged<Offset>? onMove;
  final VoidCallback? onChangeEnd;

  @override
  State<_MediaUrlPanel> createState() => _MediaUrlPanelState();
}

class _MediaUrlPanelState extends State<_MediaUrlPanel> {
  Offset? _dragPosition;

  void _edit() {
    widget.onActivate();
    // The inactive field must rebuild before it can accept focus.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.resources.active) widget.resources.focusNode.requestFocus();
    });
  }

  void _finishDrag() {
    if (_dragPosition == null) return;
    _dragPosition = null;
    widget.onChangeEnd?.call();
  }

  @override
  Widget build(BuildContext context) {
    final theme = BTheme.of(context);
    final colors = theme.colors;
    final panel = SizedBox(
      key: const ValueKey('media-url-panel'),
      width: widget.resources.urlPanelWidth,
      child: Surface(
        selected: widget.selected,
        raised: false,
        child: Stack(
          children: [
            Row(
              children: [
                Expanded(
                  child: IgnorePointer(
                    ignoring: !widget.active,
                    child: Actions(
                      actions: {
                        PasteTextIntent: CallbackAction<PasteTextIntent>(
                          onInvoke: (_) {
                            widget.onPaste();
                            return null;
                          },
                        ),
                      },
                      child: TextField(
                        key: const ValueKey('media-url-field'),
                        groupId: widget.resources,
                        contextMenuBuilder: null,
                        controller: widget.resources.controller,
                        focusNode: widget.resources.focusNode,
                        readOnly: !widget.active,
                        canRequestFocus: widget.active,
                        onTap: widget.onActivate,
                        onTapOutside: (_) {
                          widget.resources.session.invalidatePendingEdits();
                          widget.resources.commitUrl();
                          widget.resources.focusNode.unfocus();
                        },
                        onSubmitted: (_) {
                          widget.resources.session.invalidatePendingEdits();
                          widget.resources.commitUrl();
                        },
                        minLines: 1,
                        maxLines: 3,
                        textAlignVertical: TextAlignVertical.center,
                        keyboardType: TextInputType.url,
                        textInputAction: TextInputAction.done,
                        cursorColor: colors.accent,
                        style: theme.typo.body.copyWith(color: colors.textPrimary),
                        decoration: const InputDecoration(
                          hintText: 'Paste link',
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.fromLTRB(12, 0, 12, 8),
                        ),
                      ),
                    ),
                  ),
                ),
                TextFieldTapRegion(
                  groupId: widget.resources,
                  child: IconButton(
                    key: const ValueKey('media-device-picker'),
                    tooltip: 'Choose image from device',
                    onPressed: widget.onPickImage,
                    icon: const Icon(LucideIcons.imageUp, size: 20),
                  ),
                ),
              ],
            ),
            if (widget.active && widget.onMove != null)
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
                      ImmediateMultiDragGestureRecognizer: immediateDragGestureFactory(
                        (_) => CallbackDrag(widget.onMove!, onEnd: widget.onChangeEnd),
                      ),
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    if (widget.active || widget.onMove == null) return panel;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      dragStartBehavior: DragStartBehavior.down,
      onTap: _edit,
      onPanStart: (details) => _dragPosition = details.globalPosition,
      onPanUpdate: (details) {
        final position = details.globalPosition;
        widget.onMove!(position - _dragPosition!);
        _dragPosition = position;
      },
      onPanEnd: (_) => _finishDrag(),
      onPanCancel: _finishDrag,
      child: panel,
    );
  }
}

// Provides shared media transitions, drag handling, and image decoding.
// Used by the media tool, image surface, URL panel, and media resources.

// ---------- Transitions ----------

Widget _mediaTransition(
  Widget child,
  Animation<double> animation, [
  Alignment alignment = Alignment.topCenter,
]) => FadeTransition(
  opacity: animation,
  child: ScaleTransition(
    scale: Tween<double>(begin: 0.94, end: 1).animate(animation),
    alignment: alignment,
    child: child,
  ),
);

// ---------- Clipboard and device edits ----------

extension MediaClipboardEdits on MediaResources {
  Future<void> paste(Future<ClipboardReader> readerFuture) async {
    final token = session.captureEdit(data.id);
    try {
      final reader = await readerFuture;
      if (!token.isCurrent || !attached) return;
      final clipboard = await readCanvasClipboard(reader);
      if (!token.isCurrent || !attached) return;
      if (clipboard.image case final image?) {
        await setDeviceImage(image.bytes, image.extension);
      } else if (clipboard.text case final text?) {
        insertPastedText(text);
        if (!focusNode.hasFocus) commitUrl();
      }
    } on Object {
      if (!token.isCurrent || !attached) return;
      rethrow;
    }
  }

  Future<void> setDeviceImage(Uint8List bytes, String extension) async {
    final token = session.captureEdit(data.id);
    try {
      final normalizedExtension = extension.toLowerCase() == 'jpeg' ? 'jpg' : extension.toLowerCase();
      if (!const {'png', 'jpg', 'gif', 'webp'}.contains(normalizedExtension)) {
        throw const FormatException('Unsupported image type');
      }
      validateAttachmentSize(bytes.length, 'Image exceeds 10 MiB');

      final path = 'attachments/${const Uuid().v4()}.$normalizedExtension';
      final ratio = (await readCanvasImageSize(bytes)).aspectRatio;
      if (!token.isCurrent || !attached) return;
      var written = false;
      try {
        await attachmentStore.write(path, bytes);
        written = true;
      } finally {
        if (!written || !token.isCurrent || !attached) {
          try {
            await attachmentStore.delete(path);
          } on Object {
            // Cleanup cannot revive a canceled edit or hide the write failure.
          }
        }
      }
      if (!token.isCurrent || !attached) return;

      applyDeviceImage(bytes, ratio, path);
    } on Object {
      if (!token.isCurrent || !attached) return;
      rethrow;
    }
  }
}
