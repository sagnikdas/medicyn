import 'package:flutter/material.dart';

import 'widgets/dosely_motion.dart';

/// Clinical Calm — the Stitch design system for Dosely.
///
/// Tokens come from the "Dosely App Redesign" project (primary teal
/// `#00685f`, Public Sans, 8px rhythm, 12px cards, ambient teal shadows).
/// Dark mode keeps the same seed so Settings → Theme still works; the
/// light scheme is the designed one.
class DoselyTheme {
  DoselyTheme._();

  static const primary = Color(0xFF00685F);
  static const primaryContainer = Color(0xFF008378);
  static const onPrimaryContainer = Color(0xFFF4FFFC);
  static const primaryFixedDim = Color(0xFF6BD8CB);
  static const secondary = Color(0xFF55615F);
  static const secondaryContainer = Color(0xFFD8E5E2);
  static const onSecondaryContainer = Color(0xFF5B6765);
  static const tertiary = Color(0xFF4648D4);
  static const surface = Color(0xFFF8F9FA);
  static const onSurface = Color(0xFF191C1D);
  static const onSurfaceVariant = Color(0xFF3D4947);
  static const outline = Color(0xFF6D7A77);
  static const outlineVariant = Color(0xFFBCC9C6);
  static const error = Color(0xFFBA1A1A);
  static const fontFamily = 'Public Sans';

  /// Soft teal-tinted drop shadow used on schedule cards.
  static List<BoxShadow> get ambientShadow => const [
    BoxShadow(color: Color(0x0A00685F), blurRadius: 12, offset: Offset(0, 4)),
  ];

  static const _lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: primary,
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: primaryContainer,
    onPrimaryContainer: onPrimaryContainer,
    secondary: secondary,
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: secondaryContainer,
    onSecondaryContainer: onSecondaryContainer,
    tertiary: tertiary,
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFF6063EE),
    onTertiaryContainer: Color(0xFFFFFBFF),
    error: error,
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFFFDAD6),
    onErrorContainer: Color(0xFF93000A),
    surface: surface,
    onSurface: onSurface,
    onSurfaceVariant: onSurfaceVariant,
    outline: outline,
    outlineVariant: outlineVariant,
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFF3F4F5),
    surfaceContainer: Color(0xFFEDEEEF),
    surfaceContainerHigh: Color(0xFFE7E8E9),
    surfaceContainerHighest: Color(0xFFE1E3E4),
    inverseSurface: Color(0xFF2E3132),
    onInverseSurface: Color(0xFFF0F1F2),
    inversePrimary: primaryFixedDim,
    surfaceTint: Color(0xFF006A61),
  );

  static ThemeData light() => _build(_lightScheme);

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.dark,
    );
    return _build(scheme);
  }

  static ThemeData _build(ColorScheme scheme) {
    final text = _textTheme(scheme);
    const radius12 = BorderRadius.all(Radius.circular(12));
    const radius16 = BorderRadius.all(Radius.circular(16));
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      fontFamily: fontFamily,
      textTheme: text,
      // InkSparkle uses a fragment shader; InkRipple is the same language
      // on a 2018 phone as on a flagship, and still Material.
      splashFactory: InkRipple.splashFactory,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: DoselyPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: DoselyPageTransitionsBuilder(),
          TargetPlatform.windows: DoselyPageTransitionsBuilder(),
          TargetPlatform.fuchsia: DoselyPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 0,
        titleTextStyle: text.titleLarge?.copyWith(
          color: scheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLowest,
        shape: const RoundedRectangleBorder(borderRadius: radius12),
        margin: EdgeInsets.zero,
        shadowColor: const Color(0x0A00685F),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          textStyle: text.labelLarge,
          shape: const StadiumBorder(),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          foregroundColor: scheme.primary,
          textStyle: text.labelLarge,
          side: BorderSide(color: scheme.outlineVariant, width: 2),
          shape: const RoundedRectangleBorder(borderRadius: radius12),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          textStyle: text.labelLarge,
          minimumSize: const Size(48, 48),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLowest,
        floatingLabelBehavior: FloatingLabelBehavior.always,
        labelStyle: text.bodySmall?.copyWith(color: scheme.secondary),
        border: OutlineInputBorder(
          borderRadius: radius16,
          borderSide: BorderSide(color: scheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: radius16,
          borderSide: BorderSide(color: scheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: radius16,
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      chipTheme: ChipThemeData(
        selectedColor: scheme.primaryContainer,
        labelStyle: text.labelLarge,
        shape: const StadiumBorder(),
        side: BorderSide(color: scheme.outline),
        showCheckmark: false,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainer,
        indicatorColor: scheme.primaryContainer,
        elevation: 0,
        height: 72,
        labelTextStyle: WidgetStatePropertyAll(text.labelSmall),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 2,
        shape: const StadiumBorder(),
        extendedTextStyle: text.labelLarge,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: scheme.primary,
        thumbColor: scheme.primary,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        circularTrackColor: scheme.secondaryContainer,
        linearTrackColor: scheme.secondaryContainer,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return scheme.onPrimary;
          return scheme.outline;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return scheme.primary;
          return scheme.surfaceContainerHighest;
        }),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        shape: const RoundedRectangleBorder(borderRadius: radius16),
      ),
      visualDensity: VisualDensity.comfortable,
    );
  }

  /// Phone-sized type, not the Stitch mockup tokens.
  ///
  /// The HTML screens use 24px "headline-md" on every medicine card and
  /// 48px display type on the next-dose name. Those sizes are for a 780px
  /// artboard; at Settings 100% they fill a real phone. This scale matches
  /// Material 3 so 100% is the previous comfortable default, and the
  /// Appearance slider still goes up to 150%.
  static TextTheme _textTheme(ColorScheme scheme) {
    const family = fontFamily;
    TextStyle base({
      required double size,
      required double height,
      FontWeight weight = FontWeight.w400,
      double letterSpacing = 0,
      Color? color,
    }) {
      return TextStyle(
        fontFamily: family,
        fontSize: size,
        height: height / size,
        fontWeight: weight,
        letterSpacing: letterSpacing,
        color: color ?? scheme.onSurface,
      );
    }

    return TextTheme(
      displayLarge: base(
        size: 40,
        height: 48,
        weight: FontWeight.w700,
        letterSpacing: -0.4,
      ),
      displayMedium: base(
        size: 32,
        height: 40,
        weight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
      displaySmall: base(
        size: 28,
        height: 36,
        weight: FontWeight.w700,
        letterSpacing: -0.25,
      ),
      headlineLarge: base(
        size: 28,
        height: 36,
        weight: FontWeight.w700,
        letterSpacing: -0.25,
      ),
      headlineMedium: base(size: 24, height: 32, weight: FontWeight.w600),
      headlineSmall: base(size: 22, height: 28, weight: FontWeight.w700),
      titleLarge: base(size: 20, height: 26, weight: FontWeight.w600),
      titleMedium: base(size: 16, height: 22, weight: FontWeight.w600),
      titleSmall: base(
        size: 14,
        height: 20,
        weight: FontWeight.w600,
        letterSpacing: 0.1,
      ),
      bodyLarge: base(size: 16, height: 24, color: scheme.onSurface),
      bodyMedium: base(size: 14, height: 20, color: scheme.onSurface),
      bodySmall: base(size: 12, height: 16, color: scheme.onSurfaceVariant),
      labelLarge: base(
        size: 14,
        height: 20,
        weight: FontWeight.w600,
        letterSpacing: 0.1,
      ),
      labelMedium: base(
        size: 12,
        height: 16,
        weight: FontWeight.w600,
        letterSpacing: 0.2,
      ),
      labelSmall: base(
        size: 11,
        height: 14,
        weight: FontWeight.w600,
        letterSpacing: 0.2,
      ),
    );
  }
}
