// Classifies media sources and defines URL-panel geometry.
// Used by media loading, layout, and editor validation.

import 'package:elseplane/attachments/attachment_store.dart';
import 'package:elseplane/canvas/document/media_url.dart';

// ---------- Limits and formats ----------

const mediaUrlPanelMinimumWidth = 480.0;
const mediaUrlPanelCanvasHeight = 48.0;

// ---------- Validation ----------

bool isValidMediaSource(String source) =>
    source.isEmpty || attachmentPathPattern.hasMatch(source) || isSupportedMediaUrl(source);

bool isImageMediaSource(String source) {
  if (attachmentPathPattern.hasMatch(source)) return true;
  final uri = Uri.tryParse(source);
  return isSupportedMediaUrl(source) &&
      uri != null &&
      RegExp(r'\.(png|jpe?g|gif|webp)$', caseSensitive: false).hasMatch(uri.path);
}

bool isLinkMediaSource(String source) => isSupportedMediaUrl(source) && !isImageMediaSource(source);
