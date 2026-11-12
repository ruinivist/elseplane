// Encodes canvas elements and reads compatible clipboard content.
// Used by the editor's copy, cut, paste, and image insertion flows.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:elseplane/attachments/attachment_store.dart';
import 'package:elseplane/attachments/image_import.dart';
import 'package:elseplane/canvas/document/attachment_references.dart';
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

const canvasClipboardVersion = 4;

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

String encodeCanvasClipboard(
  Iterable<CanvasElementData> elements, {
  required String sourceDirectory,
}) {
  validateAttachmentDirectory(sourceDirectory);
  return jsonEncode(<String, Object>{
    'format': _format,
    'version': canvasClipboardVersion,
    'sourceDirectory': sourceDirectory,
    'elements': elements.map((element) => element.toJson()).toList(),
  });
}

({List<CanvasElementData> elements, String sourceDirectory})? decodeCanvasClipboard(String text) {
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
        (key) => !{'format', 'version', 'sourceDirectory', 'elements'}.contains(key),
      ) ||
      decoded['version'] != canvasClipboardVersion ||
      decoded['sourceDirectory'] is! String ||
      decoded['elements'] is! List) {
    throw const FormatException('Malformed elseplane clipboard payload');
  }
  final sourceDirectory = decoded['sourceDirectory'] as String;
  validateAttachmentDirectory(sourceDirectory);
  final elements = (decoded['elements'] as List).map(CanvasElementData.fromJson).toList();
  if (elements.isEmpty) {
    throw const FormatException('Clipboard elements must not be empty');
  }
  return (elements: elements, sourceDirectory: sourceDirectory);
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
    String canvasDirectory = '',
    this.invalidateAttachments,
    this.readClipboard,
    this.writeClipboardText,
  }) : _canvasDirectory = canvasDirectory {
    validateAttachmentDirectory(canvasDirectory);
  }
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
  String _canvasDirectory;
  String get canvasDirectory => _canvasDirectory;
  set canvasDirectory(String value) {
    validateAttachmentDirectory(value);
    _canvasDirectory = value;
  }

  final void Function() clearEditing;
  final void Function(String) onError;
  final void Function(Set<String>)? invalidateAttachments;
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
    if (selected.isEmpty) return;
    final sourceDirectory = canvasDirectory;
    final targetLifetimes = cut ? {for (final value in selected) value.id: session.elementLifetime(value.id)} : null;
    final payload = encodeCanvasClipboard(selected, sourceDirectory: sourceDirectory);
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
      if (!session.isLive) return;
      _lastPastedPayload = null;
      _pasteOffset = Offset.zero;
      _cutPayload = cut ? payload : null;
      _pointerReference = (payload, pointerPosition());
      if (cut) {
        session.finishOperation();
        session.remove([
          for (final entry in targetLifetimes!.entries)
            if (entry.value != null && identical(entry.value, session.elementLifetime(entry.key))) entry.key,
        ]);
        session.finishOperation();
      }
    } on Object {
      if (!session.isLive) return;
      onError(
        cut ? 'Could not cut canvas elements' : 'Could not copy canvas elements',
      );
    }
  }

  Future<void> paste(Future<ClipboardReader>? readerFuture, {Offset? position}) async {
    if (!enabled()) return;
    final destinationDirectory = canvasDirectory;
    final pointer = this.pointerPosition();
    final scale = this.scale();
    final pointerPosition = pointer == null ? null : screenToCanvas(pointer);
    final mediaPosition = position ?? pointerPosition ?? screenToCanvas(viewportSize().center(Offset.zero));
    try {
      final read = readClipboard;
      final clipboard = read != null
          ? await read()
          : await readCanvasClipboard(await (readerFuture ?? SystemClipboard.instance!.read()));
      if (!session.isLive) return;
      final text = clipboard.text;
      final decoded = text == null ? null : decodeCanvasClipboard(text);
      if (decoded == null) {
        if (clipboard.image case final image?) {
          await _pasteImage(image, mediaPosition, destinationDirectory);
        } else if (text case final source? when isCanvasLinkPasteCandidate(source)) {
          _pasteMediaUrl(source, mediaPosition);
        }
        return;
      }
      final payload = text!;
      final elements = decoded.elements;

      await _copyAttachments(decoded, destinationDirectory);
      if (!session.isLive) return;

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
      if (!session.isLive) return;
      onError('Could not paste canvas elements');
    }
  }

  Future<void> _copyAttachments(
    ({List<CanvasElementData> elements, String sourceDirectory}) clipboard,
    String destinationDirectory,
  ) async {
    if (clipboard.sourceDirectory == destinationDirectory) return;
    final pairs = <String, String>{
      for (final reference in canvasAttachmentPaths(clipboard.elements))
        resolveAttachmentPath(clipboard.sourceDirectory, reference): resolveAttachmentPath(
          destinationDirectory,
          reference,
        ),
    };
    final attempted = <String>{};
    late List<String> written;
    try {
      written = await copyAttachmentPaths(
        attachments,
        pairs,
        beforeWrite: attempted.add,
      );
    } on Object {
      if (attempted.isNotEmpty) invalidateAttachments?.call(Set.unmodifiable(attempted));
      rethrow;
    }
    if (written.isNotEmpty) invalidateAttachments?.call(written.toSet());
  }

  Future<void> _pasteImage(ClipboardImage image, Offset position, String destinationDirectory) async {
    final extension = image.extension.toLowerCase() == 'jpeg' ? 'jpg' : image.extension.toLowerCase();
    final reference = 'attachments/${const Uuid().v4()}.$extension';
    if (!attachmentPathPattern.hasMatch(reference)) throw const FormatException('Unsupported image type');
    final path = resolveAttachmentPath(destinationDirectory, reference);
    var published = false;
    try {
      final size = await readCanvasImageSize(image.bytes);
      if (!session.isLive) return;
      await attachments.write(path, image.bytes);
      if (!session.isLive) return;
      _placePastedMedia(
        _newMediaData(reference),
        position,
        imageSize: Size(mediaWidth, mediaWidth * size.height / size.width),
      );
      published = true;
    } finally {
      if (!published) {
        try {
          await attachments.delete(path);
        } on Object {
          // Cleanup must not hide the original failure.
        }
      }
    }
  }

  void _pasteMediaUrl(String url, Offset position) {
    if (!session.isLive) return;
    _placePastedMedia(_newMediaData(url), position);
  }

  MediaElementData _newMediaData(String url) => MediaElementData(
    id: const Uuid().v4(),
    position: Offset.zero,
    width: mediaWidth,
    url: url,
  );

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
