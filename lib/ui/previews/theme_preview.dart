// Previews the app's semantic colors and typography.
// Also provides the shared app theme for component previews.

import 'package:elseplane/theme/starless.dart';
import 'package:elseplane/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

// ---------- Preview theme ----------

PreviewThemeData previewTheme() => const _AppPreviewTheme();

final class _AppPreviewTheme extends PreviewThemeData {
  const _AppPreviewTheme();

  @override
  Widget apply(BuildContext context, Widget child) => Theme(
    data: MediaQuery.platformBrightnessOf(context) == Brightness.dark ? starlessDarkThemeData : starlessLightThemeData,
    child: child,
  );
}

// ---------- Theme preview ----------

@Preview(
  name: 'Theme dark',
  size: Size(1100, 700),
  theme: previewTheme,
  brightness: Brightness.dark,
)
@Preview(
  name: 'Theme',
  size: Size(1100, 700),
  theme: previewTheme,
  brightness: Brightness.light,
)
Widget themePreview() => const _ThemePreview();

class _ThemePreview extends StatelessWidget {
  const _ThemePreview();

  @override
  Widget build(BuildContext context) {
    final theme = BTheme.of(context);
    return ColoredBox(
      color: theme.colors.canvasBackground,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Colors', style: theme.typo.heading),
            const SizedBox(height: 16),
            _Colors(theme),
            const SizedBox(height: 40),
            Text('Typography', style: theme.typo.heading),
            const SizedBox(height: 16),
            _Typography(theme),
          ],
        ),
      ),
    );
  }
}

class _Colors extends StatelessWidget {
  const _Colors(this.theme);

  final BTheme theme;

  @override
  Widget build(BuildContext context) {
    final colors = theme.colors;
    final swatches = [
      ('Canvas', colors.canvasBackground),
      ('Grid', colors.canvasGrid),
      ('Surface', colors.surface),
      ('Raised', colors.surfaceRaised),
      ('Subtle', colors.surfaceSubtle),
      ('Hover', colors.surfaceHover),
      ('Pressed', colors.surfacePressed),
      ('Heading', colors.textHeading),
      ('Body', colors.textPrimary),
      ('Secondary', colors.textSecondary),
      ('Muted', colors.textMuted),
      ('Border subtle', colors.borderSubtle),
      ('Accent', colors.accent),
      ('Accent hover', colors.accentHover),
      ('Accent pressed', colors.accentPressed),
      ('Accent soft', colors.accentSoft),
      ('Accent subtle', colors.accentSubtle),
      ('Focus', colors.focusRing),
      ('Shadow', colors.shadow),
      ('Scrim', colors.scrim),
    ];
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final (label, color) in swatches)
          SizedBox(
            width: 108,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: theme.geo.radiusMedium,
                    border: Border.all(color: colors.borderSubtle),
                  ),
                ),
                const SizedBox(height: 4),
                Text(label, style: theme.typo.body.copyWith(fontSize: 12)),
                Text(
                  _hex(color),
                  style: theme.typo.code.copyWith(
                    color: colors.textMuted,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  String _hex(Color color) {
    final argb = color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase();
    return argb.startsWith('FF') ? '#${argb.substring(2)}' : '#$argb';
  }
}

class _Typography extends StatelessWidget {
  const _Typography(this.theme);

  final BTheme theme;

  @override
  Widget build(BuildContext context) {
    final styles = [
      ('Display', theme.typo.display),
      ('Heading', theme.typo.heading),
      ('Title', theme.typo.title),
      ('Body', theme.typo.body),
      ('Label', theme.typo.label),
      ('Code', theme.typo.code),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (label, style) in styles) ...[
          Text('$label · The quick brown fox jumps over the lazy dog', style: style),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}
