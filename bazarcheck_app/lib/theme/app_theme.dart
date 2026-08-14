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

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark()  => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
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

    // Inter throughout, per the export. Falls back to the platform default if
    // Inter is not installed, which still renders Bangla correctly.
    const font = 'Inter';

    final text = TextTheme(
      // headline-lg / md / sm from DESIGN.md
      headlineLarge: _t(24, FontWeight.w700, 32, scheme.onSurface),
      headlineMedium: _t(20, FontWeight.w700, 28, scheme.onSurface),
      headlineSmall: _t(18, FontWeight.w600, 24, scheme.onSurface),
      titleLarge: _t(18, FontWeight.w700, 24, scheme.onSurface),
      titleMedium: _t(16, FontWeight.w600, 22, scheme.onSurface),
      titleSmall: _t(14, FontWeight.w600, 20, scheme.onSurface),
      // body-lg / md
      bodyLarge: _t(16, FontWeight.w400, 24, scheme.onSurface),
      bodyMedium: _t(14, FontWeight.w400, 20, scheme.onSurface),
      bodySmall: _t(12, FontWeight.w400, 16, scheme.onSurfaceVariant),
      labelLarge: _t(14, FontWeight.w600, 20, scheme.onSurface),
      labelMedium: _t(12, FontWeight.w600, 16, scheme.onSurfaceVariant),
      // The tiny uppercase captions used for GOVT FIXED / LOCAL MARKET
      labelSmall: _t(11, FontWeight.w600, 14, scheme.onSurfaceVariant),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: font,
      textTheme: text,
      scaffoldBackgroundColor: isLight ? surface : scheme.surface,

      appBarTheme: AppBarTheme(
        backgroundColor: isLight ? surface : scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: _t(20, FontWeight.w700, 28, primary),
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
        hintStyle: _t(16, FontWeight.w400, 24, scheme.onSurfaceVariant),
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
          borderSide: const BorderSide(color: primary, width: 2),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primaryContainer,
          foregroundColor: onPrimaryContainer,
          minimumSize: const Size(64, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: _t(16, FontWeight.w600, 24, onPrimaryContainer),
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
          foregroundColor: primary,
          minimumSize: const Size(48, 44),
          textStyle: _t(14, FontWeight.w600, 20, primary),
        ),
      ),

      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        side: BorderSide(color: scheme.outlineVariant),
        backgroundColor: isLight ? surfaceContainerLowest : scheme.surfaceContainerHigh,
        labelStyle: _t(14, FontWeight.w600, 20, scheme.onSurface),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      ),

      // The 5-tab bar: HOME · COMPARE · MAP · TRENDS · SETTINGS
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        elevation: 0,
        backgroundColor: isLight ? surfaceContainerLowest : scheme.surface,
        indicatorColor: primaryFixed,
        indicatorShape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => _t(
            10,
            FontWeight.w600,
            14,
            states.contains(WidgetState.selected) ? primary : onSurfaceVariant,
          ).copyWith(letterSpacing: 0.4),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 22,
            color: states.contains(WidgetState.selected)
                ? primary
                : onSurfaceVariant,
          ),
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

  static TextStyle _t(double size, FontWeight weight, double height, Color c) =>
      TextStyle(
        fontFamily: 'Inter',
        fontSize: size,
        fontWeight: weight,
        height: height / size,
        color: c,
      );
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
