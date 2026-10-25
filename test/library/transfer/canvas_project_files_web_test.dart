// Verifies real browser downloads for canvas exports and library backups.
// Cancels navigation while checking the filename, content type, and saved bytes.

@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:elseplane/library/transfer/canvas_project_files.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

void main() {
  for (final (name, mimeType, contents) in [
    ('canvas.elseplane.json', 'application/json', <int>[123, 125]),
    ('library.elseplane.zip', 'application/zip', <int>[80, 75, 3, 4]),
  ]) {
    test('downloads $name without requesting a native save location', () async {
      final downloads = <({String name, Future<web.Response> response})>[];
      final listener = (web.Event event) {
        final target = event.target;
        if (target == null || !target.isA<web.HTMLAnchorElement>()) return;
        final anchor = target as web.HTMLAnchorElement;
        event.preventDefault();
        downloads.add((name: anchor.download, response: web.window.fetch(anchor.href.toJS).toDart));
      }.toJS;
      web.document.addEventListener('click', listener);
      addTearDown(() => web.document.removeEventListener('click', listener));

      final bytes = Uint8List.fromList(contents);
      final saved = await createCanvasProjectFiles().save(bytes, suggestedName: name, mimeType: mimeType);

      expect(saved, isTrue);
      expect(downloads, hasLength(1));
      expect(downloads.single.name, name);
      final response = await downloads.single.response;
      expect(response.headers.get('content-type'), mimeType);
      expect((await response.arrayBuffer().toDart).toDart.asUint8List(), bytes);
    });
  }
}
