// Validates externally supplied HTTPS media URLs without presentation or I/O.

const mediaUrlMaximumLength = 2048;

/// Accepts secure absolute URLs without credentials, encoded hosts, or whitespace.
bool isSupportedMediaUrl(String source) {
  if (source.length > mediaUrlMaximumLength) return false;
  final uri = Uri.tryParse(source);
  return uri != null &&
      uri.scheme == 'https' &&
      uri.hasAuthority &&
      uri.host.isNotEmpty &&
      !uri.host.contains('%') &&
      !RegExp('^https://[^/?#]*@', caseSensitive: false).hasMatch(source) &&
      uri.userInfo.isEmpty &&
      !RegExp(r'\s').hasMatch(source);
}
