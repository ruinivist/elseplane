// Enforces the session and history dependency boundary.
// Runs on the VM alongside the other source import checks.

@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// ---------- Editor logic ----------

void main() {
  test('session and history depend only on values, geometry, and notifier primitives', () {
    for (final path in ['lib/canvas/editor/editor_session.dart', 'lib/canvas/editor/editor_history.dart']) {
      final file = File(path);
      final directives = RegExp(r'^(?:import|export)\s+[^;]+;', multiLine: true);
      final strings = RegExp('''['"]([^'"]+)['"]''');
      for (final directive in directives.allMatches(file.readAsStringSync())) {
        for (final match in strings.allMatches(directive[0]!)) {
          final dependency = match[1]!;
          expect(
            dependency == 'dart:ui' ||
                dependency == 'dart:math' ||
                dependency == 'package:flutter/foundation.dart' ||
                dependency == 'editor_history.dart' ||
                dependency == 'package:elseplane/canvas/editor/editor_history.dart' ||
                dependency.startsWith('package:elseplane/canvas/document/') ||
                dependency.startsWith('package:elseplane/canvas/geometry/'),
            isTrue,
            reason: '$path: $dependency',
          );
        }
      }
    }
  });
  test('input, shortcuts, clipboard, and creation tools do not import presentation', () {
    final files = [
      File('lib/canvas/editor/canvas_input.dart'),
      File('lib/canvas/editor/canvas_shortcuts.dart'),
      File('lib/canvas/editor/canvas_clipboard.dart'),
      File('lib/canvas/editor/media_source.dart'),
      ...Directory('lib/canvas/editor/tools').listSync().whereType<File>().where((a) => a.path.endsWith('.dart')),
    ];
    for (final file in files) {
      final source = file.readAsStringSync();
      for (final directive in RegExp(r'^(?:import|export)\s+[^;]+;', multiLine: true).allMatches(source)) {
        final dependency = directive[0]!;
        expect(
          dependency.contains('/elements/') ||
              dependency.contains('/widgets/') ||
              dependency.contains('/theme/') ||
              dependency.contains('/ui/') ||
              dependency.contains('infinite_lazy_grid') ||
              dependency.contains('package:flutter/material.dart') ||
              dependency.contains('package:flutter/rendering.dart'),
          isFalse,
          reason: '${file.path}: $dependency',
        );
      }
      expect(RegExp('^part ', multiLine: true).hasMatch(source), isFalse, reason: file.path);
    }
  });
}
