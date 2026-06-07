import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/spacing.dart';
import 'app_typography.dart';
import 'obsidian_colors.dart';

abstract final class ObsidianTheme {
  static ThemeData dark() {
    const scheme = ColorScheme.dark(
      surface: ObsidianColors.surface,
      onSurface: ObsidianColors.onSurface,
      onSurfaceVariant: ObsidianColors.onSurfaceVariant,
      primary: ObsidianColors.primary,
      onPrimary: ObsidianColors.onPrimary,
      primaryContainer: ObsidianColors.primaryContainer,
      onPrimaryContainer: ObsidianColors.onPrimaryContainer,
      secondary: ObsidianColors.secondary,
      onSecondary: ObsidianColors.onSecondary,
      secondaryContainer: ObsidianColors.secondaryContainer,
      tertiary: ObsidianColors.tertiary,
      error: ObsidianColors.error,
      onError: ObsidianColors.onError,
      outline: ObsidianColors.outline,
      outlineVariant: ObsidianColors.outlineVariant,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: ObsidianColors.background,
      textTheme: AppTypography.textTheme(),
      appBarTheme: AppBarTheme(
        backgroundColor: ObsidianColors.surface,
        foregroundColor: ObsidianColors.primary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: AppTypography.inter(
          size: 20,
          weight: FontWeight.w600,
          color: ObsidianColors.primary,
        ),
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
      cardTheme: CardThemeData(
        color: ObsidianColors.surfaceContainer,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
          side: const BorderSide(color: ObsidianColors.outlineVariant),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: ObsidianColors.background,
        hintStyle: AppTypography.inter(color: ObsidianColors.outline),
        labelStyle: AppTypography.mono(size: 12, color: ObsidianColors.onSurfaceVariant),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          borderSide: const BorderSide(color: ObsidianColors.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          borderSide: const BorderSide(color: ObsidianColors.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          borderSide: const BorderSide(color: ObsidianColors.primary, width: 2),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: ObsidianColors.surfaceContainerLow,
        indicatorColor: ObsidianColors.secondaryContainer.withValues(alpha: 0.35),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return AppTypography.inter(
            size: 12,
            weight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? ObsidianColors.secondary : ObsidianColors.onSurfaceVariant,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? ObsidianColors.secondary : ObsidianColors.onSurfaceVariant,
            size: 24,
          );
        }),
        height: 72,
        elevation: 0,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: ObsidianColors.primary,
        foregroundColor: ObsidianColors.onPrimary,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppSpacing.radiusLg)),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: ObsidianColors.outlineVariant,
        thickness: 1,
      ),
      listTileTheme: const ListTileThemeData(
        tileColor: ObsidianColors.surface,
        selectedTileColor: ObsidianColors.surfaceContainerHigh,
        iconColor: ObsidianColors.outline,
        textColor: ObsidianColors.onSurface,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: ObsidianColors.surfaceContainerHigh,
        contentTextStyle: AppTypography.inter(size: 14),
      ),
    );
  }
}
