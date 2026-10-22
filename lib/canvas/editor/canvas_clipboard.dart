// Encodes canvas elements and reads compatible clipboard content.
// Used by the editor's copy, cut, paste, and image insertion flows.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:elseplane/attachments/attachment_store.dart';
import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:super_clipboard/super_clipboard.dart';

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
