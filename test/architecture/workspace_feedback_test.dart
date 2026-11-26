@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('app source uses workspace cards or inline feedback instead of Material snackbars', () {
    final snackbarApi = RegExp(
      r'\b(?:SnackBar(?:Action|Behavior|ClosedReason|Theme(?:Data)?)?|'
      r'showSnackBar|hideCurrentSnackBar|removeCurrentSnackBar|clearSnackBars|snackBarTheme)\b',
    );
    final files = Directory('lib').listSync(recursive: true, followLinks: false).whereType<File>();
    final violations = <String>[];
    for (final file in files.where((file) => file.path.endsWith('.dart'))) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (snackbarApi.hasMatch(lines[i])) violations.add('${file.path}:${i + 1}: ${lines[i].trim()}');
      }
    }
    expect(violations..sort(), isEmpty, reason: 'Use workspace cards or inline feedback:\n${violations.join('\n')}');
  });
}
