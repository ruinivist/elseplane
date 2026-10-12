// Defines elseplane's concrete themes, typography, colors, and shared geometry.
// Used by the app shell and themed editor widgets.

import 'package:elseplane/theme/fonts.dart';
import 'package:elseplane/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:re_highlight/styles/atom-one-light.dart';

// ---------- Palette and geometry ----------

const _starlessLightColors = BColors(
  canvasBackground: Color(0xfffbf9f7),
  canvasGrid: Color(0xffded7d2),
  surface: Color(0xffffffff),
  glassSurface: Color(0x7affffff),
  glassBorder: Color(0xb8ffffff),
  surfaceRaised: Color(0xfffffefd),
  surfaceSubtle: Color(0xfff7f3f0),
  surfaceHover: Color(0xfff8f4f1),
  surfacePressed: Color(0xfff2ece8),
  textHeading: Color(0xff201c1a),
  textPrimary: Color(0xff201c1a),
  textSecondary: Color(0xff655a53),
  textMuted: Color(0xff887b73),
  destructive: Color(0xff914534),
  resizeHandle: Color(0xff6b6b6b),
  borderSubtle: Color(0xffeae3de),
  accent: Color(0xffc66b53),
  accentHover: Color(0xffae5742),
  accentPressed: Color(0xff914534),
  accentSoft: Color(0xfffdf4f1),
  accentSubtle: Color(0xfff9e4de),
  focusRing: Color(0xffe5a48f),
  shadow: Color(0x1f302a27),
  scrim: Color(0x52201c1a),
);

const _starlessDarkColors = BColors(
  canvasBackground: Color(0xff16191e),
  canvasGrid: Color(0xff262b32),
  surface: Color(0xff252930),
  glassSurface: Color(0x99252930),
  glassBorder: Color(0x29d0d0d0),
  surfaceRaised: Color(0xff2b3038),
  surfaceSubtle: Color(0xff1e2229),
  surfaceHover: Color(0xff30363f),
  surfacePressed: Color(0xff38414c),
  textHeading: Color(0xffd0d0d0),
  textPrimary: Color(0xffb8b8b8),
  textSecondary: Color(0xffa3a3a3),
  textMuted: Color(0xff989898),
  destructive: Color(0xffd09a9a),
  resizeHandle: Color(0xff9da6b1),
  borderSubtle: Color(0xff393e46),
  accent: Color(0xff879db8),
  accentHover: Color(0xff9cafc6),
  accentPressed: Color(0xff73879f),
  accentSoft: Color(0xff252f3b),
  accentSubtle: Color(0xff303d4d),
  focusRing: Color(0xffa3b5c9),
  shadow: Color(0x80000000),
  scrim: Color(0x80000000),
);

const _starlessGeo = BGeo(
  radiusSmall: BorderRadius.all(Radius.circular(4)),
  radiusMedium: BorderRadius.all(Radius.circular(8)),
  radiusLarge: BorderRadius.all(Radius.circular(10)),
  elevationLow: 4,
  elevationMedium: 8,
  glassBlurSigma: 16,
  glassShadow: BoxShadow(blurRadius: 16, offset: Offset(0, 4)),
);

// ---------- Typography ----------

BTypo _starlessTypo(BColors colors) => BTypo(
  display: TextStyle(
    fontFamily: defaultFontFamily,
    fontSize: 40,
    fontWeight: FontWeight.w600,
    height: 1.1,
    color: colors.textHeading,
  ),
  heading: TextStyle(
    fontFamily: defaultFontFamily,
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.3,
    color: colors.textHeading,
  ),
  title: TextStyle(fontFamily: defaultFontFamily, fontSize: 13, fontWeight: FontWeight.w600, color: colors.textHeading),
  body: TextStyle(fontFamily: defaultFontFamily, fontSize: 13, fontWeight: FontWeight.w400, color: colors.textPrimary),
  label: TextStyle(fontFamily: defaultFontFamily, fontSize: 13, fontWeight: FontWeight.w600, color: colors.textHeading),
  code: TextStyle(
    fontFamily: defaultFontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.4,
    color: colors.textPrimary,
  ),
);

// ---------- Theme instances ----------

final Map<String, TextStyle> _starlessDarkSyntaxTheme = atomOneDarkTheme.map(
  (name, style) => MapEntry(
    name,
    style.copyWith(
      color: switch (style.color?.toARGB32()) {
        0xffabb2bf => _starlessDarkColors.textPrimary,
        0xff5c6370 => const Color(0xff97999f),
        0xffc678dd => const Color(0xffb2a5be),
        0xffe06c75 => const Color(0xffbc9ea5),
        0xff56b6c2 || 0xff61aeee => _starlessDarkColors.focusRing,
        0xff98c379 => const Color(0xffa5b8a3),
        0xffd19a66 || 0xffe6c07b => const Color(0xffb7adb8),
        _ => style.color,
      },
      backgroundColor: name == 'root' ? _starlessDarkColors.surface : style.backgroundColor,
    ),
  ),
);

final ThemeData starlessLightThemeData = _starlessThemeData(
  _starlessLightColors,
  Brightness.light,
  atomOneLightTheme,
);

final ThemeData starlessDarkThemeData = _starlessThemeData(
  _starlessDarkColors,
  Brightness.dark,
  _starlessDarkSyntaxTheme,
);

// ---------- Theme construction ----------

ThemeData _starlessThemeData(BColors colors, Brightness brightness, Map<String, TextStyle> syntaxTheme) {
  final isDark = brightness == Brightness.dark;
  final onAccent = isDark ? colors.canvasBackground : colors.surface;
  final onAccentContainer = isDark ? colors.textPrimary : colors.accentPressed;
  final typo = _starlessTypo(colors);
  final theme = BTheme(
    colors: colors,
    typo: typo,
    geo: _starlessGeo,
    syntaxTheme: syntaxTheme,
  );
  final colorScheme = ColorScheme(
    brightness: brightness,
    primary: colors.accent,
    onPrimary: onAccent,
    primaryContainer: colors.accentSoft,
    onPrimaryContainer: onAccentContainer,
    primaryFixed: colors.accentSoft,
    primaryFixedDim: colors.accentSubtle,
    onPrimaryFixed: onAccentContainer,
    onPrimaryFixedVariant: isDark ? colors.textSecondary : colors.accentHover,
    secondary: colors.accent,
    onSecondary: onAccent,
    secondaryContainer: colors.accentSoft,
    onSecondaryContainer: onAccentContainer,
    secondaryFixed: colors.accentSoft,
    secondaryFixedDim: colors.accentSubtle,
    onSecondaryFixed: onAccentContainer,
    onSecondaryFixedVariant: isDark ? colors.textSecondary : colors.accentHover,
    tertiary: colors.accent,
    onTertiary: onAccent,
    tertiaryContainer: colors.accentSoft,
    onTertiaryContainer: onAccentContainer,
    tertiaryFixed: colors.accentSoft,
    tertiaryFixedDim: colors.accentSubtle,
    onTertiaryFixed: onAccentContainer,
    onTertiaryFixedVariant: isDark ? colors.textSecondary : colors.accentHover,
    error: colors.destructive,
    onError: onAccent,
    errorContainer: isDark ? const Color(0xff3b2b2c) : colors.accentSoft,
    onErrorContainer: isDark ? const Color(0xffeccccc) : colors.accentPressed,
    surface: colors.surface,
    onSurface: colors.textPrimary,
    surfaceDim: colors.surfacePressed,
    surfaceBright: colors.surfaceRaised,
    surfaceContainerLowest: colors.surfaceRaised,
    surfaceContainerLow: colors.surface,
    surfaceContainer: colors.surfaceSubtle,
    surfaceContainerHigh: colors.surfaceHover,
    surfaceContainerHighest: colors.surfacePressed,
    onSurfaceVariant: colors.textSecondary,
    outline: colors.borderSubtle,
    outlineVariant: colors.borderSubtle,
    shadow: colors.shadow,
    scrim: colors.scrim,
    inverseSurface: colors.textPrimary,
    onInverseSurface: colors.surface,
    inversePrimary: colors.focusRing,
    surfaceTint: Colors.transparent,
  );

  return ThemeData(
    fontFamily: defaultFontFamily,
    brightness: brightness,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: colors.canvasBackground,
    extensions: [theme],
    textTheme: TextTheme(
      displayLarge: typo.display,
      displayMedium: typo.display,
      displaySmall: typo.display.copyWith(fontSize: 28),
      headlineLarge: typo.heading,
      headlineMedium: typo.heading,
      headlineSmall: typo.heading,
      titleLarge: typo.title.copyWith(fontSize: 14),
      titleMedium: typo.title,
      titleSmall: typo.title,
      bodyLarge: typo.body.copyWith(fontSize: 14),
      bodyMedium: typo.body,
      bodySmall: typo.body.copyWith(fontSize: 12),
      labelLarge: typo.label,
      labelMedium: typo.label,
      labelSmall: typo.label,
    ),
    iconTheme: IconThemeData(color: colors.textSecondary),
    dividerTheme: DividerThemeData(color: colors.borderSubtle, thickness: 1),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: colors.accent,
      selectionColor: colors.accentSubtle,
      selectionHandleColor: colors.accent,
    ),
    inputDecorationTheme: InputDecorationTheme(
      hintStyle: TextStyle(color: colors.textMuted),
    ),
    focusColor: colors.focusRing,
    hoverColor: colors.surfaceHover,
    splashColor: colors.surfacePressed,
    splashFactory: NoSplash.splashFactory,
    snackBarTheme: SnackBarThemeData(
      backgroundColor: colors.textPrimary,
      contentTextStyle: typo.body.copyWith(color: colors.surface),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: colors.textPrimary,
        borderRadius: _starlessGeo.radiusSmall,
      ),
      textStyle: typo.body.copyWith(
        color: colors.surface,
        fontSize: 12,
      ),
    ),
  );
}
