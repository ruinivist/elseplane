// Validates encoded attachment images and their storage limits.
// Used by image edits and project/library transfers before saving attachments.

import 'dart:typed_data';
import 'dart:ui';

import 'package:elseplane/attachments/attachment_store.dart';

// ---------- Image validation ----------

Future<void> validateCanvasAttachment(String path, Uint8List bytes) async {
  if (!attachmentPathPattern.hasMatch(path)) throw FormatException('Invalid attachment path: $path');
  validateAttachmentSize(bytes.length, 'Attachment exceeds 10 MiB: $path');
  try {
    await readCanvasImageSize(bytes);
  } catch (error) {
    throw FormatException('Invalid encoded image: $path ($error)');
  }
}

/// Decodes the first frame to validate and measure an image on every supported platform.
/// Used by attachment validation and clipboard/device image placement.
Future<Size> readCanvasImageSize(Uint8List bytes) async {
  validateAttachmentSize(bytes.length, 'Image exceeds 10 MiB');
  Codec? codec;
  FrameInfo? frame;
  try {
    codec = await instantiateImageCodec(bytes);
    frame = await codec.getNextFrame();
    return Size(frame.image.width.toDouble(), frame.image.height.toDouble());
  } catch (error) {
    throw FormatException('Invalid encoded image: $error');
  } finally {
    frame?.image.dispose();
    codec?.dispose();
  }
}
