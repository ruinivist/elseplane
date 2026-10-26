// Verifies preview brightness and semantic theme roles.

import 'package:elseplane/theme/theme.dart';
import 'package:elseplane/ui/previews/theme_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------- Tests ----------

void main() {
  testWidgets('preview theme follows preview brightness and supplies app semantics', (tester) async {
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(platformBrightness: brightness),
          child: Builder(
            builder: (context) => previewTheme().apply(context, const SizedBox(key: ValueKey('preview-child'))),
          ),
        ),
      );
      final theme = Theme.of(tester.element(find.byKey(const ValueKey('preview-child'))));
      expect(theme.brightness, brightness);
      final semantics = theme.extension<BTheme>()!;
      expect(semantics.typo.heading.color, semantics.colors.textHeading);
      expect(semantics.typo.body.color, semantics.colors.textPrimary);
      if (brightness == Brightness.dark) {
        expect(
          semantics.colors.textHeading.computeLuminance(),
          greaterThan(semantics.colors.textPrimary.computeLuminance()),
        );
      }
    }
  });
}
