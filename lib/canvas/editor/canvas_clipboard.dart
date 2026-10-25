// Encodes canvas elements and reads compatible clipboard content.
// Used by the editor's copy, cut, paste, and image insertion flows.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:elseplane/attachments/attachment_store.dart';
import 'package:elseplane/attachments/image_import.dart';
import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/editor/editor_session.dart';
import 'package:elseplane/canvas/editor/media_source.dart';
import 'package:elseplane/canvas/geometry/element_geometry.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:uuid/uuid.dart';

// ---------- Clipboard format ----------

const _format = 'elseplane-canvas-clipboard';
final _formatMarker = RegExp(
  r'"format"\s*:\s*"elseplane-canvas-clipboard"',
);

const canvasClipboardVersion = 3;

const _imageFormats = <FileFormat, String>{
  Formats.png: 'png',
  Formats.jpeg: 'jpg',
  Formats.gif: 'gif',
  Formats.webp: 'webp',
};

// ---------- Types ----------

typedef ClipboardImage = ({Uint8List bytes, String extension});
typedef CanvasClipboardSnapshot = ({String? text, ClipboardImage? image});

// ---------- Clipboard reading ----------

/// Reads preferred image bytes and plain text from a clipboard snapshot.
/// Used by canvas paste handling before interpreting internal payloads.
Future<CanvasClipboardSnapshot> readCanvasClipboard(
  ClipboardReader reader,
) async {
  ClipboardImage? image;
  final formats = reader.getFormats(_imageFormats.keys.toList());
  if (formats.isNotEmpty) {
    final format = formats.first as FileFormat;
    final bytes = await _readClipboardFile(reader, format);
    if (bytes != null) {
      image = (bytes: bytes, extension: _imageFormats[format]!);
    }
  }
  final text = reader.canProvide(Formats.plainText) ? await reader.readValue(Formats.plainText) : null;
  return (text: text, image: image);
}

// ---------- Element serialization ----------

String encodeCanvasClipboard(Iterable<CanvasElementData> elements) => jsonEncode(<String, Object>{
  'format': _format,
  'version': canvasClipboardVersion,
  'elements': elements.map((element) => element.toJson()).toList(),
});

List<CanvasElementData>? decodeCanvasClipboard(String text) {
  Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    if (_formatMarker.hasMatch(text)) {
      throw const FormatException('Malformed elseplane clipboard payload');
    }
    return null;
  }
  if (decoded is! Map || decoded['format'] != _format) return null;
  if (decoded.keys.any(
        (key) => !{'format', 'version', 'elements'}.contains(key),
      ) ||
      decoded['version'] != canvasClipboardVersion ||
      decoded['elements'] is! List) {
    throw const FormatException('Malformed elseplane clipboard payload');
  }
  final elements = (decoded['elements'] as List).map(CanvasElementData.fromJson).toList();
  if (elements.isEmpty) {
    throw const FormatException('Clipboard elements must not be empty');
  }
  return elements;
}

// ---------- Private helpers ----------

Future<Uint8List?> _readClipboardFile(
  ClipboardReader reader,
  FileFormat format,
) {
  final result = Completer<Uint8List?>();
  final progress = reader.getFile(
    format,
    (file) async {
      try {
        validateAttachmentSize(file.fileSize ?? 0, 'Image exceeds 10 MiB');
        final bytes = await file.readAll();
        validateAttachmentSize(bytes.length, 'Image exceeds 10 MiB');
        if (!result.isCompleted) result.complete(bytes);
      } on Object catch (error, stackTrace) {
        if (!result.isCompleted) result.completeError(error, stackTrace);
      }
    },
    onError: (error) {
      if (!result.isCompleted) result.completeError(error);
    },
  );
  if (progress == null) result.complete(null);
  return result.future;
}

// ---------- Canvas clipboard workflow ----------

/// Interprets clipboard values and commits accepted canvas edits.
/// Scoped to one editor lifetime; browser events and menus supply captured targets.
class CanvasClipboard {
  CanvasClipboard({
    required this.session,
    required this.attachments,
    required this.enabled,
    required this.menuOpen,
    required this.editing,
    required this.pointerPosition,
    required this.scale,
    required this.screenToCanvas,
    required this.viewportSize,
    required this.boundsOf,
    required this.mediaWidth,
    required this.clearEditing,
    required this.onError,
    this.readClipboard,
    this.writeClipboardText,
  });
  final EditorSession session;
  final AttachmentStore attachments;
  final bool Function() enabled;
  final bool Function() menuOpen;
  final bool Function() editing;
  final Offset? Function() pointerPosition;
  final double Function() scale;
  final Offset Function(Offset) screenToCanvas;
  final Size Function() viewportSize;
  final Rect Function(CanvasElementData) boundsOf;
  final double mediaWidth;
  final void Function() clearEditing;
  final void Function(String) onError;
  final Future<CanvasClipboardSnapshot> Function()? readClipboard;
  final Future<void> Function(String)? writeClipboardText;
  String? _lastPastedPayload;
  String? _cutPayload;
  Offset _pasteOffset = Offset.zero;
  (String, Offset?)? _pointerReference;

  MediaElementData newMedia(String url) => _newMediaData(url);
  Future<void> copy(
    ClipboardWriter? writer, {
    bool cut = false,
    List<String>? targets,
  }) async {
    if (!enabled() || (targets == null && (menuOpen() || editing()))) {
      return;
    }
    final ids = (targets ?? session.selectedIds).toSet();
    final selected = session.document.elements.where((value) => ids.contains(value.id)).toList();
    final generation = session.captureEdit();
    if (selected.isEmpty) return;
    final payload = encodeCanvasClipboard(
      selected,
    );
    try {
      final write = writeClipboardText;
      if (write != null) {
        await write(payload);
      } else {
        final clipboard = writer ?? SystemClipboard.instance;
        if (clipboard == null) throw StateError('Clipboard unavailable');
        final item = DataWriterItem()..add(Formats.plainText(payload));
        await clipboard.write([item]);
      }
      if (!session.isLive || !generation.isCurrent) return;
      _lastPastedPayload = null;
      _pasteOffset = Offset.zero;
      _cutPayload = cut ? payload : null;
      _pointerReference = (payload, pointerPosition());
      if (cut) {
        session.finishOperation();
        session.remove(selected.map((a) => a.id));
        session.finishOperation();
      }
    } on Object {
      if (!session.isLive || !generation.isCurrent) return;
      onError(
        cut ? 'Could not cut canvas elements' : 'Could not copy canvas elements',
      );
    }
  }

  Future<void> paste(Future<ClipboardReader>? readerFuture, {Offset? position}) async {
    if (!enabled()) return;
    final generation = session.captureEdit();
    final pointer = this.pointerPosition();
    final scale = this.scale();
    final pointerPosition = pointer == null ? null : screenToCanvas(pointer);
    final mediaPosition = position ?? pointerPosition ?? screenToCanvas(viewportSize().center(Offset.zero));
    try {
      final read = readClipboard;
      late final CanvasClipboardSnapshot clipboard;
      try {
        clipboard = read != null
            ? await read()
            : await readCanvasClipboard(await (readerFuture ?? SystemClipboard.instance!.read()));
      } on FormatException {
        return;
      }
      if (!session.isLive || !enabled() || !generation.isCurrent) return;
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
      if (!session.isLive || !enabled()) return;
      final payload = text!;

      final placeAtPointer = position != null || (pointer != null && (payload, pointer) != _pointerReference);
      final pasted = [for (final element in elements) element.copyWith(id: const Uuid().v4())];
      session.finishOperation();
      if (placeAtPointer) {
        final bounds = pasted.map(boundsOf).reduce((bounds, next) => bounds.expandToInclude(next));
        _pasteOffset = (position ?? pointerPosition!) - bounds.center;
      } else if (_lastPastedPayload != payload) {
        _pasteOffset = payload == _cutPayload ? Offset.zero : const Offset(24, 24) / scale;
      } else {
        _pasteOffset += const Offset(24, 24) / scale;
      }
      _lastPastedPayload = payload;
      _pointerReference = (payload, pointer);
      clearEditing();
      session.insert([for (final value in pasted) moveElement(value, _pasteOffset)]);
      session.setSelection(pasted.map((value) => value.id));
    } on Object {
      if (!session.isLive || !generation.isCurrent) return;
      onError('Could not paste canvas elements');
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
      await attachments.write(path, image.bytes);
      if (!session.isLive || !generation.isCurrent) return;
      _placePastedMedia(
        _newMediaData(path),
        position,
        imageSize: Size(mediaWidth, mediaWidth * size.height / size.width),
      );
      published = true;
    } finally {
      if (!published) {
        try {
          await attachments.delete(path);
        } on Object {
          // Cleanup cannot hide the original failure or revive a canceled edit.
        }
      }
    }
  }

  void _pasteMediaUrl(String url, Offset position) {
    if (!session.isLive || !enabled()) return;
    _placePastedMedia(_newMediaData(url), position);
  }

  MediaElementData _newMediaData(String url) =>
      MediaElementData(id: const Uuid().v4(), position: Offset.zero, width: mediaWidth, url: url);

  void _placePastedMedia(MediaElementData value, Offset position, {Size? imageSize}) {
    session.finishOperation();
    final placed = value.copyWith(
      position: position - (imageSize?.center(Offset.zero) ?? boundsOf(value).center),
    );
    clearEditing();
    session
      ..insert([placed])
      ..setSelection([placed.id]);
  }
}
