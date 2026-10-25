// Defines accepted image formats, media geometry limits, and URL validation.
// Used by media selection, loading, layout, and import flows.

// ---------- Limits and formats ----------

const mediaUrlPanelMinimumWidth = 480.0;
const mediaUrlPanelCanvasHeight = 48.0;
// ---------- Validation ----------

/// Accepts secure, absolute image URLs without encoded hosts or whitespace.
/// Used before the media model attempts a network image load.
bool isSupportedMediaUrl(String source) {
  final uri = Uri.tryParse(source);
  return uri != null &&
      uri.scheme == 'https' &&
      uri.host.isNotEmpty &&
      !uri.host.contains('%') &&
      !RegExp(r'\s').hasMatch(source);
}
