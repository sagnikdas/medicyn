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

/// Cross-platform by construction (`shared_preferences` has first-class iOS
/// support) — nothing here is Android-specific, so it needs no stubbing to
/// run correctly once an iOS runner exists.
class AppSettings extends ChangeNotifier {
  AppSettings._();
  static final AppSettings instance = AppSettings._();

  static const _textSizeKey = 'text_size';
  static const _hasSeenOnboardingKey = 'has_seen_onboarding';

  TextSize _textSize = TextSize.standard;
  TextSize get textSize => _textSize;

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
    _hasSeenOnboarding = prefs.getBool(_hasSeenOnboardingKey) ?? false;
    _loaded = true;
  }

  Future<void> setTextSize(TextSize size) async {
    _textSize = size;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_textSizeKey, size.name);
  }

  Future<void> setHasSeenOnboarding() async {
    _hasSeenOnboarding = true;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hasSeenOnboardingKey, true);
  }
}
