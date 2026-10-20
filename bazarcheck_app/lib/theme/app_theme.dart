import 'package:flutter/material.dart';

/// BazarCheck design system.
///
/// Every value below is taken verbatim from the Stitch export
/// (`DESIGN.md` → `colors:` / typography). Nothing is approximated, so the
/// built app matches the mockups rather than merely resembling them.
class AppTheme {
  AppTheme._();

  // --- Stitch palette ------------------------------------------------------
  static const primary                 = Color(0xFF005BBF);
  static const onPrimary               = Color(0xFFFFFFFF);
  static const primaryContainer        = Color(0xFF1A73E8);
  static const onPrimaryContainer      = Color(0xFFFFFFFF);
  static const primaryFixed            = Color(0xFFD8E2FF);
  static const onPrimaryFixed          = Color(0xFF001A41);
  static const onPrimaryFixedVariant   = Color(0xFF004493);
  static const inversePrimary          = Color(0xFFADC7FF);

  static const secondary               = Color(0xFF006E2C);
  static const onSecondary             = Color(0xFFFFFFFF);
  static const secondaryContainer      = Color(0xFF86F898);
  static const onSecondaryContainer    = Color(0xFF00722F);
  static const secondaryFixed          = Color(0xFF89FA9B);
  static const onSecondaryFixed        = Color(0xFF002108);

  static const tertiary                = Color(0xFF8F4D00);
  static const onTertiary              = Color(0xFFFFFFFF);
  static const tertiaryContainer       = Color(0xFFB36200);
  static const tertiaryFixed           = Color(0xFFFFDCC2);
  static const onTertiaryFixed         = Color(0xFF2E1500);

  static const error                   = Color(0xFFBA1A1A);
  static const onError                 = Color(0xFFFFFFFF);
  static const errorContainer          = Color(0xFFFFDAD6);
  static const onErrorContainer        = Color(0xFF93000A);

  static const surface                 = Color(0xFFF7F9FF);
  static const surfaceDim              = Color(0xFFD7DAE0);
  static const surfaceContainerLowest  = Color(0xFFFFFFFF);
  static const surfaceContainerLow     = Color(0xFFF1F4FA);
  static const surfaceContainer        = Color(0xFFEBEEF4);
  static const surfaceContainerHigh    = Color(0xFFE5E8EE);
  static const surfaceContainerHighest = Color(0xFFDFE3E8);
  static const onSurface               = Color(0xFF181C20);
  static const onSurfaceVariant        = Color(0xFF414754);
  static const inverseSurface          = Color(0xFF2D3135);
  static const inverseOnSurface        = Color(0xFFEEF1F7);
  static const outline                 = Color(0xFF727785);
  static const outlineVariant          = Color(0xFFC1C6D6);

  /// Semantic colours for price movement, matching the SPIKE / DROP / STABLE
  /// pills in the mockups.
  static const spike  = Color(0xFFBA1A1A); // price rising — bad for the buyer
  static const drop   = Color(0xFF006E2C); // price falling — good
  static const stable = Color(0xFF414754);

  static ThemeData light({bool isBangla = false}) => _build(Brightness.light, isBangla);
  static ThemeData dark({bool isBangla = false})  => _build(Brightness.dark, isBangla);

  static ThemeData _build(Brightness brightness, bool isBangla) {
    final isLight = brightness == Brightness.light;

    final scheme = isLight
        ? const ColorScheme.light(
            primary: primary,
            onPrimary: onPrimary,
            primaryContainer: primaryContainer,
            onPrimaryContainer: onPrimaryContainer,
            secondary: secondary,
            onSecondary: onSecondary,
            secondaryContainer: secondaryContainer,
            onSecondaryContainer: onSecondaryContainer,
            tertiary: tertiary,
            onTertiary: onTertiary,
            tertiaryContainer: tertiaryContainer,
            onTertiaryContainer: onTertiary,
            error: error,
            onError: onError,
            errorContainer: errorContainer,
            onErrorContainer: onErrorContainer,
            surface: surface,
            onSurface: onSurface,
            onSurfaceVariant: onSurfaceVariant,
            surfaceContainerLowest: surfaceContainerLowest,
            surfaceContainerLow: surfaceContainerLow,
            surfaceContainer: surfaceContainer,
            surfaceContainerHigh: surfaceContainerHigh,
            surfaceContainerHighest: surfaceContainerHighest,
            outline: outline,
            outlineVariant: outlineVariant,
            inverseSurface: inverseSurface,
            onInverseSurface: inverseOnSurface,
            inversePrimary: inversePrimary,
          )
        : ColorScheme.fromSeed(
            // The export only defines a light scheme. Deriving dark from the
            // same seed keeps the brand hue consistent instead of inventing
            // a second palette.
            seedColor: primary,
            brightness: Brightness.dark,
          );

    // Inter for English, Hind Siliguri for Bangla.
    final String fontFamily = isBangla ? 'Hind Siliguri' : 'Inter';

    final text = TextTheme(
      // headline-lg / md / sm from DESIGN.md
      headlineLarge: _t(24, FontWeight.w700, 32, scheme.onSurface, isBangla),
      headlineMedium: _t(20, FontWeight.w700, 28, scheme.onSurface, isBangla),
      headlineSmall: _t(18, FontWeight.w600, 24, scheme.onSurface, isBangla),
      titleLarge: _t(18, FontWeight.w700, 24, scheme.onSurface, isBangla),
      titleMedium: _t(16, FontWeight.w600, 22, scheme.onSurface, isBangla),
      titleSmall: _t(14, FontWeight.w600, 20, scheme.onSurface, isBangla),
      // body-lg / md
      bodyLarge: _t(16, FontWeight.w400, 24, scheme.onSurface, isBangla),
      bodyMedium: _t(14, FontWeight.w400, 20, scheme.onSurface, isBangla),
      bodySmall: _t(12, FontWeight.w400, 16, scheme.onSurfaceVariant, isBangla),
      labelLarge: _t(14, FontWeight.w600, 20, scheme.onSurface, isBangla),
      labelMedium: _t(12, FontWeight.w600, 16, scheme.onSurfaceVariant, isBangla),
      // The tiny uppercase captions used for GOVT FIXED / LOCAL MARKET
      labelSmall: _t(11, FontWeight.w600, 14, scheme.onSurfaceVariant, isBangla),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: fontFamily,
      textTheme: text,
      scaffoldBackgroundColor: isLight ? surface : scheme.surface,

      appBarTheme: AppBarTheme(
        backgroundColor: isLight ? surface : scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: _t(20, FontWeight.w700, 28, isLight ? primary : const Color(0xFF90CAF9), isBangla),
      ),

      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: isLight ? surfaceContainerLowest : scheme.surfaceContainerHigh,
        // 12px radius, hairline border — the flat bordered card in the mockups.
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: isLight
                ? outlineVariant.withValues(alpha: 0.55)
                : scheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
        clipBehavior: Clip.antiAlias,
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isLight ? surfaceContainerLow : scheme.surfaceContainerHigh,
        hintStyle: _t(16, FontWeight.w400, 24, scheme.onSurfaceVariant, isBangla),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isLight ? primary : const Color(0xFF90CAF9),
            width: 2,
          ),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primaryContainer,
          foregroundColor: onPrimaryContainer,
          minimumSize: const Size(64, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: _t(16, FontWeight.w600, 24, onPrimaryContainer, isBangla),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 48),
          side: BorderSide(color: scheme.outlineVariant),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: isLight ? primary : const Color(0xFF90CAF9),
          minimumSize: const Size(48, 44),
          textStyle: _t(
            14,
            FontWeight.w600,
            20,
            isLight ? primary : const Color(0xFF90CAF9),
            isBangla,
          ),
        ),
      ),

      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        side: BorderSide(color: scheme.outlineVariant),
        backgroundColor: isLight ? surfaceContainerLowest : scheme.surfaceContainerHigh,
        labelStyle: _t(14, FontWeight.w600, 20, scheme.onSurface, isBangla),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      ),

      // Navigation bar with high-contrast, crystal-clear labels and icons in both modes
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        elevation: 0,
        backgroundColor: isLight ? surfaceContainerLowest : const Color(0xFF131720),
        indicatorColor: isLight ? primaryFixed : const Color(0xFF1D3B68),
        indicatorShape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) {
            final isSelected = states.contains(WidgetState.selected);
            final textColor = isLight
                ? (isSelected ? primary : const Color(0xFF475569))
                : (isSelected ? const Color(0xFF90CAF9) : const Color(0xFFCBD5E1));
            return _t(
              11,
              isSelected ? FontWeight.w700 : FontWeight.w600,
              14,
              textColor,
              isBangla,
            ).copyWith(letterSpacing: 0.3);
          },
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) {
            final isSelected = states.contains(WidgetState.selected);
            final iconColor = isLight
                ? (isSelected ? primary : const Color(0xFF475569))
                : (isSelected ? const Color(0xFF90CAF9) : const Color(0xFFCBD5E1));
            return IconThemeData(
              size: 23,
              color: iconColor,
            );
          },
        ),
      ),

      dividerTheme: DividerThemeData(
        color: isLight
            ? outlineVariant.withValues(alpha: 0.5)
            : scheme.outlineVariant.withValues(alpha: 0.3),
        space: 1,
        thickness: 1,
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),

      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
    );
  }

  static TextStyle _t(double size, FontWeight weight, double height, Color c, bool isBangla) {
    final base = TextStyle(
      fontSize: size,
      fontWeight: weight,
      height: height / size,
      color: c,
    );
    return base.copyWith(
      fontFamily: isBangla ? 'Hind Siliguri' : 'Inter',
    );
  }
}

/// Semantic price colours, resolved per brightness so they stay legible in
/// dark mode.
extension PriceColors on ColorScheme {
  /// Cheapest / saving / price falling.
  Color get savingsColor =>
      brightness == Brightness.light ? AppTheme.drop : const Color(0xFF6DDD81);

  /// Price getting stale.
  Color get warningColor =>
      brightness == Brightness.light ? AppTheme.tertiary : const Color(0xFFFFB77B);

  /// Dearest / price rising.
  Color get premiumColor =>
      brightness == Brightness.light ? AppTheme.spike : const Color(0xFFFFB4AB);

  /// Tint behind the government-fixed price block.
  Color get govtTint => brightness == Brightness.light
      ? AppTheme.primaryFixed.withValues(alpha: 0.55)
      : AppTheme.primary.withValues(alpha: 0.20);
}
