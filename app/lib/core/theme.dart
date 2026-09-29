import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'widgets/medicyn_motion.dart';

/// The Bedside Chart — Medicyn's design system, evolved from the original
/// "Clinical Calm" Stitch tokens (primary teal `#00685f`, Public Sans, 8px
/// rhythm, 12px cards) into a warmer material world: a chart clipped at
/// someone's bedside, not a hospital monitor. Teal stays the one brand/
/// confirming color; the ground shifts from clinical white to a warm
/// linen/kraft paper, cards read as pages sitting on that ground, and every
/// dose status carries a persistent glyph alongside its color (see
/// `DayDoseStyle` in `features/reminders_home/day_dose_style.dart`) so
/// state never depends on hue alone.
///
/// Dark mode is hand-tuned to the same gradient/glass "Premium Wellness"
/// treatment as light (see `_darkScheme`), not a `ColorScheme.fromSeed`
/// placeholder.
class MedicynTheme {
  MedicynTheme._();

  static const primary = Color(0xFF00685F);
  static const primaryContainer = Color(0xFF008378);
  static const onPrimaryContainer = Color(0xFFF4FFFC);
  static const primaryFixedDim = Color(0xFF6BD8CB);
  static const secondary = Color(0xFF55615F);
  static const secondaryContainer = Color(0xFFD8E5E2);
  static const onSecondaryContainer = Color(0xFF5B6765);
  static const tertiary = Color(0xFF4648D4);

  /// Warm linen/kraft ground — the "chart backing" the app sits on. Darker
  /// and warmer than the paper cards float above it, so a page always
  /// reads as clipped onto the surface rather than painted the same as it.
  static const surface = Color(0xFFF3ECDB);
  static const onSurface = Color(0xFF2B2318);
  static const onSurfaceVariant = Color(0xFF5C4F3B);
  static const outline = Color(0xFF8A7A5E);
  static const outlineVariant = Color(0xFFD9CBAA);
  static const error = Color(0xFFBA1A1A);
  static const fontFamily = 'Public Sans';

  /// Chart-grid rule color — the faint ruled lines behind Today's list.
  /// Ink at low alpha rather than a separate hue, so it always reads as
  /// "the same ink, fainter" instead of a competing color.
  static const chartGridLine = Color(0x142B2318);

  /// The warm paper fleck used by [ChartPaperTexture]'s grain.
  static const paperGrain = Color(0xFFE6D9B8);

  /// Soft warm-ink drop shadow used on schedule cards — the system's one
  /// recurring shadow (The One Shadow Rule), retuned from the original
  /// teal-tinted version to sit against the warm ground and read with a
  /// bit more presence at rest.
  static List<BoxShadow> get ambientShadow => const [
    BoxShadow(color: Color(0x1A2B2318), blurRadius: 16, offset: Offset(0, 6)),
  ];

  /// The same shadow, deepened — used transiently while a card is actively
  /// pressed, so touch reads as physically lifting the page before the tap
  /// registers. See `AmbientCard`.
  static List<BoxShadow> get liftedShadow => const [
    BoxShadow(color: Color(0x262B2318), blurRadius: 24, offset: Offset(0, 10)),
  ];

  // --- Vibrant gradient ground (teal → warm amber) ------------------------
  // Brand teal stays the one anchor, unchanged; the ground now reads as a
  // warm wellness wash instead of flat linen. The muted mid-stop keeps the
  // teal→amber transition from muddying into brown.
  static const gradientTeal = primary;
  static const gradientTealSoft = Color(0xFF3D8C7D);
  static const gradientAmber = Color(0xFFF2A65A);
  static const gradientAmberDeep = Color(0xFFE8874A);

  static const gradientTealDark = Color(0xFF04211D);
  static const gradientTealSoftDark = Color(0xFF16453C);
  // Deep umber rather than bright amber in dark mode — avoids night glare.
  static const gradientAmberDark = Color(0xFF4A2E1A);

  /// The fixed, full-bleed wash painted behind every screen's cards by
  /// [MedicynGradientBackground]. Dark mode gets its own tuned stops, not a
  /// dimmed copy of the light ones, so near-opaque glass cards stay legible.
  static LinearGradient backgroundGradient(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      stops: const [0, 0.55, 1],
      colors: dark
          ? const [gradientTealDark, gradientTealSoftDark, gradientAmberDark]
          : const [gradientTeal, gradientTealSoft, gradientAmber],
    );
  }

  /// A soft colored halo, additive on top of [ambientShadow]/[liftedShadow]
  /// — never a replacement. Used behind primary icons, the active/"taken"
  /// status avatar, and opted-in hero cards.
  static List<BoxShadow> glow(
    Color color, {
    double opacity = 0.38,
    double blur = 22,
  }) => [
    BoxShadow(
      color: color.withValues(alpha: opacity),
      blurRadius: blur,
      spreadRadius: 1,
    ),
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
    // Lighter and warmer than [surface] on purpose: cards are pages sitting
    // on the linen ground, not the same material as it.
    surfaceContainerLowest: Color(0xFFFBF7EC),
    surfaceContainerLow: Color(0xFFF6F0E1),
    surfaceContainer: Color(0xFFEDE4CE),
    surfaceContainerHigh: Color(0xFFE6DBC1),
    surfaceContainerHighest: Color(0xFFDED1B0),
    inverseSurface: Color(0xFF332B1D),
    onInverseSurface: Color(0xFFF4EFE3),
    inversePrimary: primaryFixedDim,
    surfaceTint: Color(0xFF006A61),
  );

  // Hand-tuned, mirroring `_lightScheme`'s field list — replaces the old
  // `ColorScheme.fromSeed` placeholder now that dark mode gets the same
  // gradient/glass treatment as light. `primary` here is the seafoam tone
  // (`primaryFixedDim`) rather than the deep teal: standard Material 3
  // practice puts a light tone of the brand hue in a dark scheme, since deep
  // teal has too little contrast as icon/text color on a dark ground.
  static const _darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: primaryFixedDim,
    onPrimary: Color(0xFF00382F),
    primaryContainer: Color(0xFF00504A),
    onPrimaryContainer: Color(0xFFB6F5E9),
    secondary: Color(0xFFB9C8C4),
    onSecondary: Color(0xFF243330),
    secondaryContainer: Color(0xFF3B4A47),
    onSecondaryContainer: Color(0xFFD8E5E2),
    tertiary: Color(0xFFC2C1FF),
    onTertiary: Color(0xFF2224A0),
    tertiaryContainer: Color(0xFF3335BD),
    onTertiaryContainer: Color(0xFFE3E2FF),
    error: Color(0xFFFFB4AB),
    onError: Color(0xFF690005),
    errorContainer: Color(0xFF93000A),
    onErrorContainer: Color(0xFFFFDAD6),
    // Deep teal-charcoal rather than pure black, so the brand still reads.
    surface: Color(0xFF14201D),
    onSurface: Color(0xFFE6E1D6),
    onSurfaceVariant: Color(0xFFC4C7C3),
    outline: Color(0xFF8D9490),
    outlineVariant: Color(0xFF3F4844),
    surfaceContainerLowest: Color(0xFF0D1614),
    surfaceContainerLow: Color(0xFF17211E),
    surfaceContainer: Color(0xFF1C2825),
    surfaceContainerHigh: Color(0xFF27332F),
    surfaceContainerHighest: Color(0xFF323E3A),
    inverseSurface: Color(0xFFE6E1D6),
    onInverseSurface: Color(0xFF14201D),
    inversePrimary: primary,
    surfaceTint: primaryFixedDim,
  );

  static ThemeData light() => _build(_lightScheme);

  static ThemeData dark() => _build(_darkScheme);

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
          TargetPlatform.android: MedicynPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: MedicynPageTransitionsBuilder(),
          TargetPlatform.windows: MedicynPageTransitionsBuilder(),
          TargetPlatform.fuchsia: MedicynPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        // iOS conventionally centers navigation-bar titles; Android keeps
        // the existing leading-title treatment.
        centerTitle:
            defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS,
        scrolledUnderElevation: 0,
        titleTextStyle: text.titleLarge?.copyWith(
          color: scheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        // Frosted, not flat opaque — cards now read as glass sitting over
        // the gradient ground rather than paper pages.
        color: scheme.surfaceContainerLowest.withValues(alpha: 0.86),
        shape: const RoundedRectangleBorder(borderRadius: radius16),
        margin: EdgeInsets.zero,
        shadowColor: const Color(0x1A2B2318),
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
