// lib/app_theme.dart
import 'package:flutter/material.dart';

class AppColors extends ThemeExtension<AppColors> {
  final Color burgundy;   // accent
  final Color chartreuse; // accent
  final Color tealGreen;  // accent
  final Color ivory;      // main surface (dark gray)

  const AppColors({
    required this.burgundy,
    required this.chartreuse,
    required this.tealGreen,
    required this.ivory,
  });

  @override
  AppColors copyWith({
    Color? burgundy,
    Color? chartreuse,
    Color? tealGreen,
    Color? ivory,
  }) =>
      AppColors(
        burgundy: burgundy ?? this.burgundy,
        chartreuse: chartreuse ?? this.chartreuse,
        tealGreen: tealGreen ?? this.tealGreen,
        ivory: ivory ?? this.ivory,
      );

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      burgundy: Color.lerp(burgundy, other.burgundy, t)!,
      chartreuse: Color.lerp(chartreuse, other.chartreuse, t)!,
      tealGreen: Color.lerp(tealGreen, other.tealGreen, t)!,
      ivory: Color.lerp(ivory, other.ivory, t)!,
    );
  }

  // Dark palette (your values)
  static const dark = AppColors(
    burgundy:  Color(0xFF22242A), // single accent
    chartreuse:Color(0xFF22242A),
    tealGreen:  Color(0xFF22242A),
    ivory:      Color(0xFF22242A), // main surface (dark gray)
  );
}

class AppTheme {
  static const _heroMid  = Color(0xFF393D46); // cards/containers
  static const _heroDark = Color(0xFF22242A); // scaffold/background

  // Dark-only theme
  static ThemeData get theme {
    const brand = AppColors.dark;

    const scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: Color(0xFFDCF5E2),
      onPrimary: Colors.black,
      secondary: Color(0xFFF2F5F3),
      onSecondary: Colors.black,
      surface: _heroMid,
      onSurface: Colors.white,
      background: _heroDark,
      onBackground: Colors.white,
      error: Color(0xFFEF4444),
      onError: Colors.white,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.background,
      fontFamily: 'Roboto',
      extensions: const <ThemeExtension<dynamic>>[brand],

      appBarTheme: const AppBarTheme(
        backgroundColor: _heroMid,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 18,
        ),
        iconTheme: IconThemeData(color: Colors.white),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          minimumSize: const Size.fromHeight(44),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 0,
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.secondary,
          foregroundColor: scheme.onSecondary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.primary,
          side: BorderSide(color: scheme.primary, width: 1.2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _heroMid,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _heroMid),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _heroMid),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        floatingLabelStyle: TextStyle(color: scheme.primary),
        hintStyle: TextStyle(color: scheme.onSurface.withOpacity(0.6)),
        contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      ),

      cardTheme: CardThemeData(
        color: _heroMid,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        shadowColor: Colors.transparent,
      ),
    );
  }
}
