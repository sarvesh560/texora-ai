import 'package:flutter/material.dart';
import 'texora_design_system.dart';

class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: TexoraColors.workspaceBg,
      colorScheme: const ColorScheme.light(
        primary: TexoraColors.primaryBlue,
        onPrimary: Colors.white,
        surface: TexoraColors.cardBg,
        onSurface: TexoraColors.textPrimary,
        error: TexoraColors.critical,
        onError: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: TexoraColors.headerBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: TexoraTypography.screenTitle,
        iconTheme: IconThemeData(color: TexoraColors.textPrimary),
      ),
      cardTheme: CardThemeData(
        color: TexoraColors.cardBg,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(TexoraSpacing.radiusLg),
          side: const BorderSide(color: TexoraColors.cardBorder, width: 1),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: TexoraColors.cardBorder,
        thickness: 1,
        space: 1,
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w700,
          color: TexoraColors.textPrimary,
          letterSpacing: -0.5,
        ),
        headlineMedium: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: TexoraColors.textPrimary,
        ),
        titleLarge: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: TexoraColors.textPrimary,
        ),
        titleMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: TexoraColors.textPrimary,
        ),
        bodyLarge: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: TexoraColors.textPrimary,
        ),
        bodyMedium: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w400,
          color: TexoraColors.textSecondary,
        ),
        labelSmall: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: TexoraColors.textMuted,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

