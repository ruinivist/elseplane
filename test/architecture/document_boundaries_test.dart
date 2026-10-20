// Enforces the dependency boundaries of saved values and pure geometry.
// Runs on the VM because it inspects source directives on disk.

@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// ---------- Tests ----------

void main() {
  test('document and geometry have no presentation, storage, or browser dependencies', () {
    final document = Directory('lib/canvas/document').absolute.uri;
    final geometry = Directory('lib/canvas/geometry').absolute.uri;
    final directives = RegExp(r'^(?:import|export|part)\s+[^;]+;', multiLine: true);
    final strings = RegExp('''['"]([^'"]+)['"]''');
    for (final directory in [document, geometry]) {
      for (final file in Directory.fromUri(directory).listSync().whereType<File>()) {
        if (!file.path.endsWith('.dart')) continue;
        for (final directive in directives.allMatches(file.readAsStringSync())) {
          for (final match in strings.allMatches(directive[0]!)) {
            final import = Uri.parse(match[1]!);
            final allowed = switch (import.scheme) {
              'dart' => {'ui', 'math', 'typed_data'}.contains(import.path),
              'package' =>
                import.path.startsWith('elseplane/canvas/document/') ||
                    (directory == geometry && import.path.startsWith('elseplane/canvas/geometry/')) ||
                    (directory == document
                        ? import.path == 'json_annotation/json_annotation.dart'
                        : import.path == 'perfect_freehand/perfect_freehand.dart'),
              '' => file.absolute.uri.resolveUri(import).toString().startsWith(directory.toString()),
              _ => false,
            };
            expect(allowed, isTrue, reason: '${file.path} depends on $import');
          }
        }
      }
    }
  });
}
