// Validates encoded attachment images and their storage limits.
// Used by project and library transfers before preparing attachments.

import 'dart:typed_data';
import 'dart:ui';

import 'package:elseplane/attachments/attachment_store.dart';

// ---------- Image validation ----------

Future<void> validateCanvasAttachment(String path, Uint8List bytes) async {
  if (!attachmentPathPattern.hasMatch(path)) throw FormatException('Invalid attachment path: $path');
  validateAttachmentSize(bytes.length, 'Attachment exceeds 10 MiB: $path');
  ImmutableBuffer? buffer;
  ImageDescriptor? descriptor;
  try {
    buffer = await ImmutableBuffer.fromUint8List(bytes);
    descriptor = await ImageDescriptor.encoded(buffer);
  } catch (error) {
    throw FormatException('Invalid encoded image: $path ($error)');
  } finally {
    descriptor?.dispose();
    buffer?.dispose();
  }
}

/// Decodes the first frame to measure an image on every supported platform.
/// Used when clipboard and device images need dimensions before placement.
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
