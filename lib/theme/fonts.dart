// Owns the bundled default and Google Fonts catalog, loading, and style resolution.
// Used by app typography, text previews, the font picker, and document validation.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts_lite.dart';
import 'package:http/http.dart' as http;

// ---------- Catalog ----------

const defaultFontFamily = 'JetBrains Mono';
final Set<String> textNodeFontFamilies = Set.unmodifiable({defaultFontFamily, ...GoogleFontsLite.fontsMap.keys});

// ---------- Loading and styles ----------

final _loads = <String, Future<void>>{};
final _styles = <String, Map<(FontWeight, FontStyle), TextStyle>>{};
Future<void> _loadQueue = Future<void>.value();

/// Loads just the variants used by Markdown, sharing concurrent requests.
/// Used before committing a picker choice and when saved previews appear.
Future<void> loadTextFont(String family) {
  if (family == defaultFontFamily) return Future<void>.value();
  if (!textNodeFontFamilies.contains(family)) return Future<void>.error(ArgumentError.value(family, 'family'));
  return _loads.putIfAbsent(family, () async {
    // pendingFonts observes all requests, so serialize families to isolate failures.
    final load = _loadQueue.then<void>((_) async {
      final client = GoogleFontsLite.config.httpClient;
      if (client is! _FontHttpClient) GoogleFontsLite.config.httpClient = _FontHttpClient(client ?? http.Client());
      final styles = <(FontWeight, FontStyle), TextStyle>{
        for (final weight in [FontWeight.w400, FontWeight.w600])
          for (final style in FontStyle.values)
            (weight, style): GoogleFontsLite.getFont(family, fontWeight: weight, fontStyle: style),
      };
      await GoogleFontsLite.pendingFonts();
      _styles[family] = styles;
    });
    _loadQueue = load.catchError((Object _) {
      unawaited(_loads.remove(family));
    });
    await load;
  });
}

TextStyle textFontStyle(String family, TextStyle base) {
  final style = _styles[family]?[(base.fontWeight ?? FontWeight.w400, base.fontStyle ?? FontStyle.normal)];
  return base.copyWith(
    fontFamily: style?.fontFamily ?? defaultFontFamily,
    fontFamilyFallback: style?.fontFamilyFallback,
  );
}

// ---------- Download timeout ----------

class _FontHttpClient extends http.BaseClient {
  _FontHttpClient(this._inner);

  final http.Client _inner;

  @override
  Future<http.Response> get(Uri url, {Map<String, String>? headers}) {
    final abort = Completer<void>();
    final request = http.AbortableRequest('GET', url, abortTrigger: abort.future);
    if (headers != null) request.headers.addAll(headers);
    // Buffer inside the deadline so a stalled body also releases the font queue.
    return _inner
        .send(request)
        .then(http.Response.fromStream)
        .timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            abort.complete();
            throw TimeoutException('Font download timed out', const Duration(seconds: 10));
          },
        );
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => _inner.send(request);

  @override
  void close() => _inner.close();
}
