// Provides media import, storage, sizing, rendering, and interaction.
// Used by the canvas media tool and persisted media elements.

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/editor/canvas_clipboard.dart';
import 'package:elseplane/canvas/editor/canvas_element_model.dart';
import 'package:elseplane/canvas/editor/widgets/resize_handle.dart';
import 'package:elseplane/canvas/persistence/attachments/store.dart';
import 'package:elseplane/theme/theme.dart';
import 'package:elseplane/ui/common/icon_drag.dart';
import 'package:elseplane/ui/common/surface.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:uuid/uuid.dart';

part 'media_image.dart';
part 'media_model.dart';
part 'media_source.dart';
part 'media_tool_helpers.dart';
part 'media_url_panel.dart';

// ---------- Media tool ----------

/// Renders a media element or its URL entry panel.
/// Used by the canvas element stack for persisted media models.
class MediaTool extends StatefulWidget {
  const MediaTool({
    required this.model,
    required this.onMove,
    required this.onResize,
    required this.onActivate,
    required this.onDeactivate,
    this.onPanelPointerDown,
    super.key,
  });

  final MediaModel model;
  final ValueChanged<Offset> onMove;
  final ValueChanged<Offset> onResize;
  final VoidCallback onActivate;
  final VoidCallback onDeactivate;
  final PointerDownEventListener? onPanelPointerDown;

  @override
  State<MediaTool> createState() => _MediaToolState();
}

class _MediaToolState extends State<MediaTool> {
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
    if (!widget.model.focusNode.hasFocus) return;
    unawaited(_paste(event.getClipboardReader()));
  }

  Future<void> _paste(Future<ClipboardReader> readerFuture) async {
    try {
      await widget.model.paste(readerFuture);
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not paste image')),
      );
    }
  }

  Future<void> _pickImage() async {
    final model = widget.model;
    final generation = model.asyncEditGeneration;
    try {
      final file = await openFile(acceptedTypeGroups: const [_imageTypes]);
      if (file == null || generation != model.asyncEditGeneration) return;
      final separator = file.name.lastIndexOf('.');
      if (separator < 0) throw const FormatException('Missing image type');
      final length = await file.length();
      if (generation != model.asyncEditGeneration) return;
      validateAttachmentSize(length, 'Image exceeds 10 MiB');
      final bytes = await file.readAsBytes();
      if (generation != model.asyncEditGeneration) return;
      await model.setDeviceImage(
        bytes,
        file.name.substring(separator + 1),
      );
    } on Object {
      if (!mounted || generation != model.asyncEditGeneration) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not open image')));
    }
  }

  // ---------- Rendering ----------

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.model,
      builder: (context, _) {
        final model = widget.model;
        return Semantics(
          container: true,
          image: model.hasImage,
          selected: model.selected,
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
                        ignoring: !model.active || !model.hasImage,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 260),
                          reverseDuration: const Duration(milliseconds: 180),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeOutCubic,
                          transitionBuilder: _mediaTransition,
                          child: model.active && model.hasImage
                              ? TapRegion(
                                  groupId: model,
                                  child: Listener(
                                    onPointerDown: widget.onPanelPointerDown,
                                    child: _MediaUrlPanel(
                                      model: model,
                                      onActivate: widget.onActivate,
                                      onPickImage: _pickImage,
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
                      model: model,
                      onActivate: widget.onActivate,
                      onMove: widget.onMove,
                      onResize: widget.onResize,
                    ),
                  )
                : _MediaUrlPanel(
                    model: model,
                    onActivate: widget.onActivate,
                    onMove: widget.onMove,
                    onPickImage: _pickImage,
                  ),
          ),
        );
      },
    );
  }
}
