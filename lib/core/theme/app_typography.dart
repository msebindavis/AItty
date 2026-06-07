import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'obsidian_colors.dart';

abstract final class AppTypography {
  static TextStyle inter({
    double size = 14,
    FontWeight weight = FontWeight.w400,
    double? height,
    Color? color,
    double? letterSpacing,
  }) {
    return GoogleFonts.inter(
      fontSize: size,
      fontWeight: weight,
      height: height != null ? height / size : null,
      color: color ?? ObsidianColors.onSurface,
      letterSpacing: letterSpacing,
    );
  }

  static TextStyle mono({
    double size = 14,
    FontWeight weight = FontWeight.w400,
    double? lineHeight,
    Color? color,
  }) {
    return GoogleFonts.jetBrainsMono(
      fontSize: size,
      fontWeight: weight,
      height: lineHeight != null ? lineHeight / size : null,
      color: color ?? ObsidianColors.onSurfaceVariant,
    );
  }

  static TextTheme textTheme() {
    return TextTheme(
      headlineLarge: inter(size: 32, weight: FontWeight.w600, height: 40, letterSpacing: -0.02),
      headlineMedium: inter(size: 24, weight: FontWeight.w600, height: 32, letterSpacing: -0.01),
      headlineSmall: inter(size: 20, weight: FontWeight.w500, height: 28),
      titleLarge: inter(size: 20, weight: FontWeight.w600),
      titleMedium: inter(size: 16, weight: FontWeight.w500),
      bodyLarge: inter(size: 16, height: 24),
      bodyMedium: inter(size: 14, height: 20),
      labelLarge: mono(size: 14, weight: FontWeight.w500),
      labelSmall: mono(size: 12, lineHeight: 16),
    );
  }
}
