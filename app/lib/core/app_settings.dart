import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Elderly-friendly text sizing. Scales every screen's text (and, since
/// buttons/fields size around their text, most touch targets along with
/// it) rather than adding a separate "large touch target" toggle — one
/// control that does the job elderly users actually need, not a settings
/// screen full of switches.
enum TextSize {
  standard(1.0, 'Standard'),
  large(1.25, 'Large'),
  extraLarge(1.5, 'Extra large');

  const TextSize(this.scaleFactor, this.label);
  final double scaleFactor;
  final String label;
}

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

  static const _textSizeKey = 'text_size';
  static const _themeModeKey = 'theme_mode';
  static const _hasSeenOnboardingKey = 'has_seen_onboarding';

  TextSize _textSize = TextSize.standard;
  TextSize get textSize => _textSize;

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
    final stored = prefs.getString(_textSizeKey);
    _textSize = TextSize.values.firstWhere(
      (t) => t.name == stored,
      orElse: () => TextSize.standard,
    );
    final storedTheme = prefs.getString(_themeModeKey);
    _themeMode = ThemeMode.values.firstWhere(
      (m) => m.name == storedTheme,
      orElse: () => ThemeMode.system,
    );
    _hasSeenOnboarding = prefs.getBool(_hasSeenOnboardingKey) ?? false;
    _loaded = true;
  }

  Future<void> setTextSize(TextSize size) async {
    _textSize = size;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_textSizeKey, size.name);
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
