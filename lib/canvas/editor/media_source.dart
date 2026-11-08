// Resolves external sources for use and classifies media presentation.
// Saved media values remain unchanged; normalization is runtime-only.

import 'package:elseplane/attachments/attachment_store.dart';

// ---------- Limits and formats ----------

const mediaUrlPanelMinimumWidth = 480.0;
const mediaUrlPanelCanvasHeight = 48.0;

// ---------- External sources ----------

Uri? resolveMediaUri(String source) {
  final value = source.trim();
  if (value.isEmpty) return null;

  final barePort = RegExp(
    r'^(?:localhost|[A-Za-z0-9.-]*\.[A-Za-z0-9.-]+|\[[0-9A-Fa-f:.]+\]):[0-9]+(?:[/?#]|$)',
    caseSensitive: false,
  ).hasMatch(value);
  final scheme = RegExp('^[A-Za-z][A-Za-z0-9+.-]*:').hasMatch(value);
  final address = value.startsWith('//')
      ? 'https:$value'
      : barePort
      ? 'https://$value'
      : scheme
      ? value
      : 'https://$value';

  try {
    final uri = Uri.tryParse(address);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty ||
        (uri.hasPort && (uri.port < 0 || uri.port > 65535))) {
      return null;
    }
    return uri;
  } on FormatException {
    return null;
  }
}

bool isCanvasLinkPasteCandidate(String source) {
  final value = source.trim();
  if (value.isEmpty || value.contains(RegExp(r'[\r\n]'))) return false;

  final explicit = RegExp('^(?:https?://|//)', caseSensitive: false).firstMatch(value);
  if (explicit != null) {
    final authority = RegExp('^(?:https?:)?//([^/?#]*)', caseSensitive: false).firstMatch(value)?.group(1);
    return authority != null && authority.isNotEmpty && !authority.contains(RegExp(r'\s'));
  }
  return RegExp(
    r'^(?:localhost|(?:[A-Za-z0-9-]+\.)+[A-Za-z0-9-]+|\[[0-9A-Fa-f:.]+\])(?::[0-9]+)?(?:[/?#].*)?$',
    caseSensitive: false,
  ).hasMatch(value);
}

bool isImageMediaSource(String source) {
  if (attachmentPathPattern.hasMatch(source)) return true;
  final uri = resolveMediaUri(source);
  return uri != null &&
      uri.scheme == 'https' &&
      RegExp(r'\.(png|jpe?g|gif|webp)$', caseSensitive: false).hasMatch(uri.path);
}

bool isLinkMediaSource(String source) =>
    !attachmentPathPattern.hasMatch(source) && resolveMediaUri(source) != null && !isImageMediaSource(source);
