import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'cyberpunk_colors.dart';

/// The full [ThemeData] for GoHackMe.
class CyberpunkTheme {
  CyberpunkTheme._();

  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);
    final mono = GoogleFonts.shareTechMonoTextTheme(base.textTheme);

    return base.copyWith(
      colorScheme: const ColorScheme.dark(
        brightness: Brightness.dark,
        primary: CyberpunkColors.cyan,
        onPrimary: CyberpunkColors.background,
        secondary: CyberpunkColors.magenta,
        onSecondary: CyberpunkColors.background,
        surface: CyberpunkColors.surface,
        onSurface: CyberpunkColors.textPrimary,
        error: CyberpunkColors.error,
      ),
      scaffoldBackgroundColor: CyberpunkColors.background,
      textTheme: mono.copyWith(
        displayLarge: mono.displayLarge?.copyWith(
          color: CyberpunkColors.cyan,
          letterSpacing: 4,
          fontWeight: FontWeight.w700,
        ),
        titleLarge: mono.titleLarge?.copyWith(
          color: CyberpunkColors.cyan,
          letterSpacing: 2,
        ),
        bodyMedium: mono.bodyMedium?.copyWith(
          color: CyberpunkColors.textPrimary,
          letterSpacing: 0.5,
        ),
        labelSmall: mono.labelSmall?.copyWith(
          color: CyberpunkColors.textSecondary,
          letterSpacing: 1.5,
        ),
      ),
      cardTheme: CardThemeData(
        color: CyberpunkColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: const BorderSide(
            color: CyberpunkColors.cyanDim,
            width: 1,
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: CyberpunkColors.cyan,
          side: const BorderSide(color: CyberpunkColors.cyan, width: 1.5),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(2)),
          ),
          textStyle: GoogleFonts.shareTechMono(
            letterSpacing: 2,
            fontWeight: FontWeight.w700,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: CyberpunkColors.surfaceAlt,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(2),
          borderSide: const BorderSide(color: CyberpunkColors.cyanDim),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(2),
          borderSide: const BorderSide(color: CyberpunkColors.cyanDim),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(2),
          borderSide: const BorderSide(color: CyberpunkColors.cyan, width: 2),
        ),
        labelStyle: GoogleFonts.shareTechMono(
          color: CyberpunkColors.textSecondary,
        ),
        hintStyle: GoogleFonts.shareTechMono(
          color: CyberpunkColors.textDim,
        ),
      ),
      dividerColor: CyberpunkColors.cyanDim,
      dividerTheme: const DividerThemeData(
        color: CyberpunkColors.cyanDim,
        thickness: 1,
      ),
    );
  }
}
