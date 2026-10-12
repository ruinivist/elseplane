// Defines the semantic color, typography, geometry, and theme contracts.
// Used by reusable foundation widgets and concrete application themes.

import 'package:flutter/material.dart';

export 'package:elseplane/theme/sizes.dart';

// ---------- Semantic tokens ----------

enum SurfaceStyle { solid, glass }

/// Holds semantic colors shared by elseplane components.
/// Supplied by concrete app themes and consumed through [BTheme].
@immutable
class BColors {
  // ---------- Construction ----------

  const BColors({
    required this.canvasBackground,
    required this.canvasGrid,
    required this.surface,
    required this.glassSurface,
    required this.glassBorder,
    required this.surfaceRaised,
    required this.surfaceSubtle,
    required this.surfaceHover,
    required this.surfacePressed,
    required this.textHeading,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.destructive,
    required this.resizeHandle,
    required this.borderSubtle,
    required this.accent,
    required this.accentHover,
    required this.accentPressed,
    required this.accentSoft,
    required this.accentSubtle,
    required this.focusRing,
    required this.shadow,
    required this.scrim,
  });

  final Color canvasBackground;
  final Color canvasGrid;
  final Color surface;
  final Color glassSurface;
  final Color glassBorder;
  final Color surfaceRaised;
  final Color surfaceSubtle;
  final Color surfaceHover;
  final Color surfacePressed;
  final Color textHeading;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color destructive;
  final Color resizeHandle;
  final Color borderSubtle;
  final Color accent;
  final Color accentHover;
  final Color accentPressed;
  final Color accentSoft;
  final Color accentSubtle;
  final Color focusRing;
  final Color shadow;
  final Color scrim;

  // ---------- Interpolation ----------

  BColors lerp(BColors? other, double t) {
    if (other == null) return this;
    return BColors(
      canvasBackground: Color.lerp(
        canvasBackground,
        other.canvasBackground,
        t,
      )!,
      canvasGrid: Color.lerp(canvasGrid, other.canvasGrid, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      glassSurface: Color.lerp(glassSurface, other.glassSurface, t)!,
      glassBorder: Color.lerp(glassBorder, other.glassBorder, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      surfaceSubtle: Color.lerp(surfaceSubtle, other.surfaceSubtle, t)!,
      surfaceHover: Color.lerp(surfaceHover, other.surfaceHover, t)!,
      surfacePressed: Color.lerp(surfacePressed, other.surfacePressed, t)!,
      textHeading: Color.lerp(textHeading, other.textHeading, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      destructive: Color.lerp(destructive, other.destructive, t)!,
      resizeHandle: Color.lerp(resizeHandle, other.resizeHandle, t)!,
      borderSubtle: Color.lerp(borderSubtle, other.borderSubtle, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentHover: Color.lerp(accentHover, other.accentHover, t)!,
      accentPressed: Color.lerp(accentPressed, other.accentPressed, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      accentSubtle: Color.lerp(accentSubtle, other.accentSubtle, t)!,
      focusRing: Color.lerp(focusRing, other.focusRing, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
      scrim: Color.lerp(scrim, other.scrim, t)!,
    );
  }
}

/// Holds semantic typography roles shared by elseplane components.
/// Supplied by concrete app themes and consumed through [BTheme].
@immutable
class BTypo {
  // ---------- Construction ----------

  const BTypo({
    required this.display,
    required this.heading,
    required this.title,
    required this.body,
    required this.label,
    required this.code,
  });

  final TextStyle display;
  final TextStyle heading;
  final TextStyle title;
  final TextStyle body;
  final TextStyle label;
  final TextStyle code;

  // ---------- Interpolation ----------

  BTypo lerp(BTypo? other, double t) {
    if (other == null) return this;
    return BTypo(
      display: TextStyle.lerp(display, other.display, t)!,
      heading: TextStyle.lerp(heading, other.heading, t)!,
      title: TextStyle.lerp(title, other.title, t)!,
      body: TextStyle.lerp(body, other.body, t)!,
      label: TextStyle.lerp(label, other.label, t)!,
      code: TextStyle.lerp(code, other.code, t)!,
    );
  }
}

/// Holds reusable geometry and elevation values for elseplane components.
/// Supplied by concrete app themes and consumed through [BTheme].
@immutable
class BGeo {
  // ---------- Construction ----------

  const BGeo({
    required this.radiusSmall,
    required this.radiusMedium,
    required this.radiusLarge,
    required this.elevationLow,
    required this.elevationMedium,
    required this.glassBlurSigma,
    required this.glassShadow,
  });

  final BorderRadius radiusSmall;
  final BorderRadius radiusMedium;
  final BorderRadius radiusLarge;
  final double elevationLow;
  final double elevationMedium;
  final double glassBlurSigma;
  final BoxShadow glassShadow;

  // ---------- Interpolation ----------

  BGeo lerp(BGeo? other, double t) {
    if (other == null) return this;
    return BGeo(
      radiusSmall: BorderRadius.lerp(radiusSmall, other.radiusSmall, t)!,
      radiusMedium: BorderRadius.lerp(radiusMedium, other.radiusMedium, t)!,
      radiusLarge: BorderRadius.lerp(radiusLarge, other.radiusLarge, t)!,
      elevationLow: elevationLow + (other.elevationLow - elevationLow) * t,
      elevationMedium: elevationMedium + (other.elevationMedium - elevationMedium) * t,
      glassBlurSigma: glassBlurSigma + (other.glassBlurSigma - glassBlurSigma) * t,
      glassShadow: BoxShadow.lerp(glassShadow, other.glassShadow, t)!,
    );
  }
}

/// Registers elseplane's semantic tokens as a Material theme extension.
/// Read by foundation and editor widgets from their build context.
@immutable
class BTheme extends ThemeExtension<BTheme> {
  // ---------- Construction ----------

  const BTheme({
    required this.colors,
    required this.typo,
    required this.geo,
    required this.syntaxTheme,
    this.surfaceStyle = SurfaceStyle.solid,
  });

  final BColors colors;
  final BTypo typo;
  final BGeo geo;
  final Map<String, TextStyle> syntaxTheme;
  final SurfaceStyle surfaceStyle;

  // ---------- Lookup ----------

  static BTheme of(BuildContext context) {
    final theme = Theme.of(context).extension<BTheme>();
    if (theme == null) {
      throw FlutterError(
        'BTheme.of() called without a BTheme extension in the nearest Theme.',
      );
    }
    return theme;
  }

  // ---------- Theme extension ----------

  @override
  BTheme copyWith({
    BColors? colors,
    BTypo? typo,
    BGeo? geo,
    Map<String, TextStyle>? syntaxTheme,
    SurfaceStyle? surfaceStyle,
  }) {
    return BTheme(
      colors: colors ?? this.colors,
      typo: typo ?? this.typo,
      geo: geo ?? this.geo,
      syntaxTheme: syntaxTheme ?? this.syntaxTheme,
      surfaceStyle: surfaceStyle ?? this.surfaceStyle,
    );
  }

  @override
  BTheme lerp(covariant BTheme? other, double t) {
    if (other == null) return this;
    return BTheme(
      colors: colors.lerp(other.colors, t),
      typo: typo.lerp(other.typo, t),
      geo: geo.lerp(other.geo, t),
      syntaxTheme: t < 0.5 ? syntaxTheme : other.syntaxTheme,
      surfaceStyle: t < 0.5 ? surfaceStyle : other.surfaceStyle,
    );
  }
}
