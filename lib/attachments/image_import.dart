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
