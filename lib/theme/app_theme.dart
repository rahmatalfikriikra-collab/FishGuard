import 'package:flutter/material.dart';

/// Design tokens ported from the FishGuard web prototype (style.css),
/// extended with the PRD's readability targets (text >= 18 sp on key data,
/// status conveyed by icon + text, never colour alone).
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.primary,
    required this.primaryLight,
    required this.accent,
    required this.danger,
    required this.warning,
    required this.textMain,
    required this.textMuted,
    required this.cardBg,
    required this.border,
    required this.bgBody,
    required this.bgApp,
    required this.navBg,
    required this.mapBg,
    required this.land,
  });

  final Color primary;
  final Color primaryLight;
  final Color accent;
  final Color danger;
  final Color warning;
  final Color textMain;
  final Color textMuted;
  final Color cardBg;
  final Color border;
  final Color bgBody;
  final Color bgApp;
  final Color navBg;
  final Color mapBg;
  final Color land;

  static const AppColors light = AppColors(
    primary: Color(0xFF0077B6),
    primaryLight: Color(0xFF00B4D8),
    accent: Color(0xFF10B981),
    danger: Color(0xFFEF4444),
    warning: Color(0xFFF59E0B),
    textMain: Color(0xFF03045E),
    textMuted: Color(0xFF6C757D),
    cardBg: Color(0xFFFFFFFF),
    border: Color(0xFFE2E8F0),
    bgBody: Color(0xFFEEF7FC),
    bgApp: Color(0xFFF8FBFF),
    navBg: Color(0xFFFFFFFF),
    mapBg: Color(0xFFE0F2FE),
    land: Color(0xFFD8EEDC),
  );

  static const AppColors dark = AppColors(
    primary: Color(0xFF0EA5E9),
    primaryLight: Color(0xFF38BDF8),
    accent: Color(0xFF10B981),
    danger: Color(0xFFF87171),
    warning: Color(0xFFFBBF24),
    textMain: Color(0xFFF8FAFC),
    textMuted: Color(0xFF94A3B8),
    cardBg: Color(0xFF1E293B),
    border: Color(0xFF334155),
    bgBody: Color(0xFF0F172A),
    bgApp: Color(0xFF020617),
    navBg: Color(0xFF1E293B),
    mapBg: Color(0xFF0F172A),
    land: Color(0xFF1B3A2B),
  );

  @override
  AppColors copyWith({
    Color? primary,
    Color? primaryLight,
    Color? accent,
    Color? danger,
    Color? warning,
    Color? textMain,
    Color? textMuted,
    Color? cardBg,
    Color? border,
    Color? bgBody,
    Color? bgApp,
    Color? navBg,
    Color? mapBg,
    Color? land,
  }) {
    return AppColors(
      primary: primary ?? this.primary,
      primaryLight: primaryLight ?? this.primaryLight,
      accent: accent ?? this.accent,
      danger: danger ?? this.danger,
      warning: warning ?? this.warning,
      textMain: textMain ?? this.textMain,
      textMuted: textMuted ?? this.textMuted,
      cardBg: cardBg ?? this.cardBg,
      border: border ?? this.border,
      bgBody: bgBody ?? this.bgBody,
      bgApp: bgApp ?? this.bgApp,
      navBg: navBg ?? this.navBg,
      mapBg: mapBg ?? this.mapBg,
      land: land ?? this.land,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      primary: mix(primary, other.primary),
      primaryLight: mix(primaryLight, other.primaryLight),
      accent: mix(accent, other.accent),
      danger: mix(danger, other.danger),
      warning: mix(warning, other.warning),
      textMain: mix(textMain, other.textMain),
      textMuted: mix(textMuted, other.textMuted),
      cardBg: mix(cardBg, other.cardBg),
      border: mix(border, other.border),
      bgBody: mix(bgBody, other.bgBody),
      bgApp: mix(bgApp, other.bgApp),
      navBg: mix(navBg, other.navBg),
      mapBg: mix(mapBg, other.mapBg),
      land: mix(land, other.land),
    );
  }
}

extension AppColorsX on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}

class AppTheme {
  static ThemeData build({required bool dark}) {
    final AppColors c = dark ? AppColors.dark : AppColors.light;
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: c.primary,
      brightness: dark ? Brightness.dark : Brightness.light,
    ).copyWith(
      primary: c.primary,
      secondary: c.primaryLight,
      surface: c.cardBg,
      error: c.danger,
      onSurface: c.textMain,
    );

    final TextTheme text = ThemeData(
      brightness: dark ? Brightness.dark : Brightness.light,
    ).textTheme.apply(bodyColor: c.textMain, displayColor: c.textMain).copyWith(
      bodyLarge: TextStyle(fontSize: 18, color: c.textMain, height: 1.35),
      bodyMedium: TextStyle(fontSize: 16, color: c.textMain, height: 1.35),
      bodySmall: TextStyle(fontSize: 14, color: c.textMuted, height: 1.3),
      labelLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.textMain),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.bgApp,
      textTheme: text,
      extensions: <ThemeExtension<dynamic>>[c],
      splashFactory: InkRipple.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: c.cardBg,
        foregroundColor: c.textMain,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: c.cardBg,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: c.border),
        ),
      ),
      dividerTheme: DividerThemeData(color: c.border, thickness: 1, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.bgBody,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c.primary, width: 1.6),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.textMain,
        contentTextStyle: TextStyle(color: c.cardBg, fontSize: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.cardBg,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.cardBg,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }
}

/// Shared spacing / radius constants used across screens.
class Insets {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 28;
}
