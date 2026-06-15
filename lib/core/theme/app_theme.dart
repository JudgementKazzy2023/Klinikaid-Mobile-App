import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

// Design tokens adopted from the KlinikAid web team's globals.css (light
// theme). Forest green primary (#3F6146) on warm cream background
// (#F6EBD4). Inter typography. Aligned 2026-06-11.

class AppTheme {
  static const Color background = Color(0xFFF6EBD4);
  static const Color foreground = Color(0xFF0A0E1A);
  static const Color primary = Color(0xFF3F6146);
  static const Color primaryForeground = Color(0xFFFAF7EF);
  static const Color card = Color(0xFFFFFFFF);
  static const Color cardForeground = Color(0xFF0A0E1A);
  static const Color secondary = Color(0xFFE6DDCC);
  static const Color secondaryForeground = Color(0xFF0F172A);
  static const Color muted = Color(0xFFEAE2D2);
  static const Color mutedForeground = Color(0xFF64748B);
  static const Color accent = Color(0xFFE6DDCC);
  static const Color destructive = Color(0xFFEF4444);
  static const Color border = Color(0xFFD5CDBF);
  static const Color inputBorder = Color(0xFFD5CDBF);
  static const Color ring = Color(0xFF3F6146);
  static const Color accentBlue = Color(0xFF1F6DD2);

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: background,
      colorScheme: const ColorScheme.light(
        primary: primary,
        onPrimary: primaryForeground,
        secondary: secondary,
        onSecondary: secondaryForeground,
        surface: card,
        onSurface: foreground,
        error: destructive,
        onError: Colors.white,
        outline: border,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        iconTheme: IconThemeData(color: foreground),
        titleTextStyle: TextStyle(
          color: foreground,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      textTheme: GoogleFonts.interTextTheme().apply(
        bodyColor: foreground,
        displayColor: foreground,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: primaryForeground,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: border, width: 1),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: card,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: inputBorder, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: inputBorder, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
        labelStyle: const TextStyle(color: mutedForeground),
        hintStyle: const TextStyle(color: mutedForeground),
      ),
    );
  }
}
