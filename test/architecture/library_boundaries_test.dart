// Enforces library ownership and browser implementation isolation.
// Runs on the VM alongside the document boundary checks.

@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// ---------- Tests ----------

void main() {
  test('settings receives capabilities without depending on app composition', () {
    for (final file in Directory('lib/settings').listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      for (final dependency in _dependencies(file)) {
        final resolved = file.absolute.uri.resolve(dependency).toString();
        expect(resolved.contains('/app/'), isFalse, reason: '${file.path}: $dependency');
        expect(resolved.endsWith('/main.dart'), isFalse, reason: '${file.path}: $dependency');
      }
    }
  });

  test('library and shared UI do not import editor implementation', () {
    for (final root in ['lib/library', 'lib/ui/common']) {
      for (final file in Directory(root).listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.dart')) continue;
        for (final dependency in _dependencies(file)) {
          final resolved = file.absolute.uri.resolve(dependency).toString();
          expect(resolved.contains('/canvas/editor/'), isFalse, reason: '${file.path}: $dependency');
          expect(resolved.contains('/canvas/tools/'), isFalse, reason: '${file.path}: $dependency');
          if (root == 'lib/ui/common') {
            expect(resolved.contains('/canvas/'), isFalse, reason: '${file.path}: $dependency');
            expect(resolved.contains('/library/'), isFalse, reason: '${file.path}: $dependency');
            expect(resolved.contains('/settings/'), isFalse, reason: '${file.path}: $dependency');
            expect(resolved.contains('/app/'), isFalse, reason: '${file.path}: $dependency');
            expect(resolved.contains('/attachments/'), isFalse, reason: '${file.path}: $dependency');
          }
        }
      }
    }
  });

  test('shared library and attachment code only import platform contracts', () {
    for (final root in ['lib/library', 'lib/attachments']) {
      for (final file in Directory(root).listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.dart') || file.path.endsWith('_web.dart')) continue;
        for (final dependency in _dependencies(file)) {
          expect(
            dependency == 'dart:js_interop' ||
                dependency == 'dart:html' ||
                dependency.startsWith('package:web/') ||
                dependency.endsWith('_web.dart'),
            isFalse,
            reason: '${file.path}: $dependency',
          );
        }
      }
    }
  });
}

// ---------- Source directives ----------

Iterable<String> _dependencies(File file) sync* {
  final directives = RegExp(r'^(?:import|export)\s+[^;]+;', multiLine: true);
  final strings = RegExp('''['"]([^'"]+)['"]''');
  for (final directive in directives.allMatches(file.readAsStringSync())) {
    for (final match in strings.allMatches(directive[0]!)) {
      yield match[1]!;
    }
  }
}
