import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Labels for the three theme choices offered in Settings. Flutter's own
/// [ThemeMode] is stored directly (rather than a parallel enum) so there's
/// no mapping layer between what's persisted and what `MaterialApp` wants —
/// this only adds the user-facing wording.
extension ThemeModeLabel on ThemeMode {
  String get label => switch (this) {
        ThemeMode.system => 'System',
        ThemeMode.light => 'Light',
        ThemeMode.dark => 'Dark',
      };
}

/// Cross-platform by construction (`shared_preferences` has first-class iOS
/// support) — nothing here is Android-specific, so it needs no stubbing to
/// run correctly once an iOS runner exists.
class AppSettings extends ChangeNotifier {
  AppSettings._();
  static final AppSettings instance = AppSettings._();

  static const _textScaleKey = 'text_scale';
  /// Legacy key: the setting used to be a three-way enum stored by name.
  /// Read once at startup so an existing install keeps its chosen size.
  static const _legacyTextSizeKey = 'text_size';
  static const _themeModeKey = 'theme_mode';
  static const _hasSeenOnboardingKey = 'has_seen_onboarding';

  /// Elderly-friendly text sizing, as a scale factor the Settings slider
  /// drives directly. It scales every screen's text (and, since buttons and
  /// fields size around their text, most touch targets along with it) rather
  /// than adding a separate "large touch target" toggle — one control that
  /// does the job elderly users actually need.
  ///
  /// The top of the range stays at 1.5: every screen's layout has been
  /// exercised at that scale, and going further starts to overflow the
  /// tighter rows (segmented buttons, list tiles) on narrow devices.
  static const minTextScale = 1.0;
  static const maxTextScale = 1.5;
  static const textScaleStep = 0.1;

  /// (max - min) / step, as a const the Slider can take directly.
  static const textScaleDivisions = 5;

  double _textScale = minTextScale;
  double get textScale => _textScale;

  /// Defaults to following the device — the least surprising behaviour, and
  /// the one that respects a system-wide dark schedule the user already set.
  ThemeMode _themeMode = ThemeMode.system;
  ThemeMode get themeMode => _themeMode;

  bool _hasSeenOnboarding = false;
  bool get hasSeenOnboarding => _hasSeenOnboarding;

  bool _loaded = false;

  Future<void> init() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _textScale = normalizeTextScale(
      prefs.getDouble(_textScaleKey) ?? _legacyTextScale(prefs.getString(_legacyTextSizeKey)),
    );
    final storedTheme = prefs.getString(_themeModeKey);
    _themeMode = ThemeMode.values.firstWhere(
      (m) => m.name == storedTheme,
      orElse: () => ThemeMode.system,
    );
    _hasSeenOnboarding = prefs.getBool(_hasSeenOnboardingKey) ?? false;
    _loaded = true;
  }

  /// Snaps to the nearest slider step and clamps into range, so a value
  /// coming from an old install (or a future range change) can never land
  /// off-scale.
  static double normalizeTextScale(double scale) {
    final steps = ((scale - minTextScale) / textScaleStep).round();
    final snapped = (minTextScale + steps * textScaleStep).clamp(minTextScale, maxTextScale);
    // Trims the float drift that repeated + 0.1 accumulates.
    return double.parse(snapped.toStringAsFixed(2));
  }

  /// "120%" — what the slider reads out, in the one place both the value
  /// label and the on-screen readout can share it.
  static String textScaleLabel(double scale) => '${(scale * 100).round()}%';

  static double _legacyTextScale(String? storedName) => switch (storedName) {
        'large' => 1.25,
        'extraLarge' => 1.5,
        _ => minTextScale,
      };

  Future<void> setTextScale(double scale) async {
    final normalized = normalizeTextScale(scale);
    // The slider fires continuously while dragging; without this every
    // pixel of travel would notify and write a pref for an unchanged value.
    if (normalized == _textScale) return;
    _textScale = normalized;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_textScaleKey, normalized);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeModeKey, mode.name);
  }

  Future<void> setHasSeenOnboarding() async {
    _hasSeenOnboarding = true;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hasSeenOnboardingKey, true);
  }
}
