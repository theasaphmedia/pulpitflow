import 'package:flutter/material.dart';

enum PulpitTheme { sacredDark, sacredLight, graceDark, graceLight }

extension PulpitThemeExtension on PulpitTheme {
  String get displayName {
    switch (this) {
      case PulpitTheme.sacredDark:
        return 'Sacred Dark';
      case PulpitTheme.sacredLight:
        return 'Sacred Light';
      case PulpitTheme.graceDark:
        return 'Grace Dark';
      case PulpitTheme.graceLight:
        return 'Grace Light';
    }
  }

  String get description {
    switch (this) {
      case PulpitTheme.sacredDark:
        return 'Deep & focused';
      case PulpitTheme.sacredLight:
        return 'Clean & bright';
      case PulpitTheme.graceDark:
        return 'Warm & intimate';
      case PulpitTheme.graceLight:
        return 'Soft & gentle';
    }
  }

  List<Color> get previewGradient {
    switch (this) {
      case PulpitTheme.sacredDark:
        return [const Color(0xFF1a1a1a), const Color(0xFF0f0f0f)];
      case PulpitTheme.sacredLight:
        return [const Color(0xFFF5F5F0), const Color(0xFFEAEAE0)];
      case PulpitTheme.graceDark:
        return [const Color(0xFF1A100F), const Color(0xFF120A09)];
      case PulpitTheme.graceLight:
        return [const Color(0xFFFFF5F0), const Color(0xFFFAEDE8)];
    }
  }
}

class PulpitColors {
  final Color background;
  final Color surface;
  final Color card;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color accent;
  final Color accentSoft;
  final Color chipBackground;
  final Color chipBorder;
  final Color error;
  final Color success;
  final bool isDark;

  const PulpitColors({
    required this.background,
    required this.surface,
    required this.card,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.accent,
    required this.accentSoft,
    required this.chipBackground,
    required this.chipBorder,
    required this.error,
    required this.success,
    required this.isDark,
  });

  static PulpitColors of(PulpitTheme theme) {
    switch (theme) {
      case PulpitTheme.sacredDark:
        return const PulpitColors(
          background: Color(0xFF0f0f0f),
          surface: Color(0xFF161616),
          card: Color(0xFF1a1a1a),
          border: Color(0xFF2a2a2a),
          textPrimary: Color(0xFFF5F5F5),
          textSecondary: Color(0xFFA0A0A0),
          accent: Color(0xFFE8E4D8),
          accentSoft: Color(0x1AE8E4D8),
          chipBackground: Color(0x1AE8E4D8),
          chipBorder: Color(0x40E8E4D8),
          error: Color(0xFFFF6B6B),
          success: Color(0xFF4CAF50),
          isDark: true,
        );
      case PulpitTheme.sacredLight:
        return const PulpitColors(
          background: Color(0xFFF8F8F5),
          surface: Color(0xFFFFFFFF),
          card: Color(0xFFF0F0EC),
          border: Color(0xFFDDDDD5),
          textPrimary: Color(0xFF1A1A1A),
          textSecondary: Color(0xFF6B6B6B),
          accent: Color(0xFF2C2C2C),
          accentSoft: Color(0x1A2C2C2C),
          chipBackground: Color(0x1A2C2C2C),
          chipBorder: Color(0x402C2C2C),
          error: Color(0xFFDC2626),
          success: Color(0xFF16A34A),
          isDark: false,
        );
      case PulpitTheme.graceDark:
        return const PulpitColors(
          background: Color(0xFF120F10),
          surface: Color(0xFF1A1518),
          card: Color(0xFF221D20),
          border: Color(0xFF2E2830),
          textPrimary: Color(0xFFF5EEF0),
          textSecondary: Color(0xFF9A8E92),
          accent: Color(0xFFC4817A),
          accentSoft: Color(0x1AC4817A),
          chipBackground: Color(0x1AC4817A),
          chipBorder: Color(0x40C4817A),
          error: Color(0xFFFF6B6B),
          success: Color(0xFF4CAF50),
          isDark: true,
        );
      case PulpitTheme.graceLight:
        return const PulpitColors(
          background: Color(0xFFFFF8F6),
          surface: Color(0xFFFFFFFF),
          card: Color(0xFFFFF0EC),
          border: Color(0xFFEED5CF),
          textPrimary: Color(0xFF2C1810),
          textSecondary: Color(0xFF8B6B65),
          accent: Color(0xFFC4817A),
          accentSoft: Color(0x1AC4817A),
          chipBackground: Color(0x1AC4817A),
          chipBorder: Color(0x40C4817A),
          error: Color(0xFFDC2626),
          success: Color(0xFF16A34A),
          isDark: false,
        );
    }
  }

  ThemeData toThemeData() {
    return ThemeData(
      brightness: isDark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: background,
      colorScheme: ColorScheme(
        brightness: isDark ? Brightness.dark : Brightness.light,
        primary: accent,
        onPrimary: background,
        secondary: accentSoft,
        onSecondary: textPrimary,
        error: error,
        onError: Colors.white,
        surface: surface,
        onSurface: textPrimary,
      ),
      useMaterial3: true,
    );
  }
}

/// Shared elevation (shadow) tokens. Before this, every card/surface in the
/// app used a flat color + 1px border for depth — no shadows anywhere in
/// the theme, which is a big part of why the whole app reads as flat/
/// "beginner" rather than premium. These are deliberately soft/warm (low
/// opacity, larger blur) so they read as gentle lift rather than the harsh
/// drop-shadows of a typical Material default — consistent with keeping the
/// warm/sacred identity while still having real depth.
class PulpitElevation {
  /// Resting state for cards in a list (sermon cards, highlight rows, etc).
  static List<BoxShadow> card(PulpitColors colors) => [
    BoxShadow(
      color: colors.isDark
          ? Colors.black.withValues(alpha: 0.35)
          : Colors.black.withValues(alpha: 0.06),
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
  ];

  /// Pressed/active state — flatter, closer, communicates "being pushed".
  static List<BoxShadow> cardPressed(PulpitColors colors) => [
    BoxShadow(
      color: colors.isDark
          ? Colors.black.withValues(alpha: 0.25)
          : Colors.black.withValues(alpha: 0.04),
      blurRadius: 6,
      offset: const Offset(0, 1),
    ),
  ];

  /// Floating surfaces above the card layer (bottom sheets, FABs, dialogs).
  static List<BoxShadow> floating(PulpitColors colors) => [
    BoxShadow(
      color: colors.isDark
          ? Colors.black.withValues(alpha: 0.45)
          : Colors.black.withValues(alpha: 0.10),
      blurRadius: 24,
      offset: const Offset(0, 8),
    ),
  ];
}

/// Shared motion constants. Before this, animation was scattered and
/// one-off (a handful of screens each picked their own durations/curves) —
/// using the same values everywhere is what makes an app's motion feel
/// like a deliberate design language instead of an accident.
class PulpitMotion {
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration standard = Duration(milliseconds: 200);
  static const Duration slow = Duration(milliseconds: 350);
  static const Curve curve = Curves.easeOutCubic;
  static const double pressScale = 0.97;
}

// App spacing
class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
}

/// Locally-bundled fonts, as a drop-in replacement for the equivalent
/// `GoogleFonts.xxx()` calls this app used everywhere for headings.
///
/// `GoogleFonts.cormorantGaramond()` fetches the font file over the network
/// the first time each weight is used per device — fine on a fast
/// connection, a real problem for a pastor prepping somewhere with no
/// signal (see main.dart's `GoogleFonts.config.allowRuntimeFetching = false`
/// for the interim fix, and the memory notes for why). This bundles the
/// actual font files as local assets instead, so this specific typeface
/// always renders correctly and instantly with zero network dependency.
/// Signature intentionally mirrors `GoogleFonts.cormorantGaramond()`'s most
/// commonly used parameters so it's a mechanical find/replace at call
/// sites (`GoogleFonts.cormorantGaramond(` → `PulpitFonts.cormorantGaramond(`).
class PulpitFonts {
  static TextStyle cormorantGaramond({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
    FontStyle? fontStyle,
  }) {
    return TextStyle(
      fontFamily: 'CormorantGaramond',
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
      fontStyle: fontStyle,
    );
  }

  /// Replaces `GoogleFonts.inter()` — this app's body/UI font, used ~362
  /// times across the codebase for buttons, labels, and paragraph text.
  /// Bundled as **Open Sans**, not Inter — Inter itself was never provided
  /// as local font files, and every one of those 362 call sites would
  /// otherwise silently fall back to the phone's system font now that
  /// `GoogleFonts.config.allowRuntimeFetching = false` is set. Open Sans
  /// was chosen as the closest safe, freely-licensed (SIL OFL, same as
  /// Google Fonts) substitute available. If real Inter files are bundled
  /// later, only this one function needs to change — every call site
  /// already points here.
  static TextStyle inter({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
    FontStyle? fontStyle,
    TextDecoration? decoration,
    Color? decorationColor,
  }) {
    return TextStyle(
      fontFamily: 'OpenSans',
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
      fontStyle: fontStyle,
      decoration: decoration,
      decorationColor: decorationColor,
    );
  }

  /// The four alternate "Editor Font" choices in Settings (see
  /// editor_font_provider.dart). Same story as cormorantGaramond/inter:
  /// bundled locally so picking one of these doesn't silently fall back to
  /// the system font now that GoogleFonts.config.allowRuntimeFetching is
  /// disabled. Only Regular/Bold/Italic are bundled for each — every actual
  /// call site in this app uses the default weight, so that's full coverage
  /// of what's really exercised today.
  static TextStyle lora({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
    FontStyle? fontStyle,
  }) {
    return TextStyle(
      fontFamily: 'Lora',
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
      fontStyle: fontStyle,
    );
  }

  static TextStyle merriweather({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
    FontStyle? fontStyle,
  }) {
    return TextStyle(
      fontFamily: 'Merriweather',
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
      fontStyle: fontStyle,
    );
  }

  static TextStyle playfairDisplay({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
    FontStyle? fontStyle,
  }) {
    return TextStyle(
      fontFamily: 'PlayfairDisplay',
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
      fontStyle: fontStyle,
    );
  }

  static TextStyle literata({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
    FontStyle? fontStyle,
  }) {
    return TextStyle(
      fontFamily: 'Literata',
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
      fontStyle: fontStyle,
    );
  }
}
