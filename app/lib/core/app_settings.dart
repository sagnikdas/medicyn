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
  static const _showMedicineOnLockScreenKey = 'show_medicine_on_lock_screen';
  static const _localOnlyKey = 'local_only';
  static const _hasRecordedConsentsKey = 'has_recorded_consents';
  static const _consentCloudBackupKey = 'consent_cloud_backup';
  static const _consentAnthropicParseKey = 'consent_anthropic_parse';
  static const _consentGoogleSpeechKey = 'consent_google_speech';
  static const _consentCareShareKey = 'consent_care_share';

  /// The consent owner used before a Google account is selected. This is the
  /// same sentinel as the local-only encrypted database, kept here as a
  /// literal to avoid making core preferences depend on the data layer.
  static const localConsentOwnerId = 'local';

  /// Versioned prefix makes the ownership boundary inspectable in device
  /// backups and leaves room for a future migration without guessing which
  /// generation wrote a key.
  static const _ownerConsentPrefix = 'consent_owner_v1';

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

  /// Off by default so a locked phone never shows which medicine is due
  /// unless the user has chosen to. Existing installs inherit the private
  /// behaviour — this is a security fix, not a restoration of the old
  /// public notifications.
  bool _showMedicineOnLockScreen = false;
  bool get showMedicineOnLockScreen => _showMedicineOnLockScreen;

  /// True when the user chose to use the app without a Google account.
  /// Reminders stay on this phone; backup and family sharing stay off
  /// until they sign in.
  bool _localOnly = false;
  bool get localOnly => _localOnly;

  /// False until the consent screen's Continue is tapped — including on
  /// existing installs that already skipped onboarding. Implied consent is
  /// never grandfathered.
  bool _hasRecordedConsents = false;
  bool get hasRecordedConsents => _hasRecordedConsents;

  /// All four default off / unticked. Local-only until sign-in; the device
  /// is what the gates read.
  bool _consentCloudBackup = false;
  bool get consentCloudBackup => _consentCloudBackup;

  bool _consentAnthropicParse = false;
  bool get consentAnthropicParse => _consentAnthropicParse;

  bool _consentGoogleSpeech = false;
  bool get consentGoogleSpeech => _consentGoogleSpeech;

  bool _consentCareShare = false;
  bool get consentCareShare => _consentCareShare;

  bool _devicePreferencesLoaded = false;
  String? _consentOwnerId;

  /// The owner whose processing choices are currently active. Null means an
  /// owner switch is in progress, so every consent getter above remains at
  /// its fail-closed value until the new namespace has loaded.
  String? get consentOwnerId => _consentOwnerId;

  bool consentOwnerIs(String ownerId) => _consentOwnerId == ownerId;

  /// Loads device preferences once and activates [consentOwnerId]'s isolated
  /// processing choices. Calls that only need device preferences may omit the
  /// owner; the existing active owner is then preserved, or local-only is
  /// selected on the first load for backwards-compatible tests and startup.
  Future<void> init({String? consentOwnerId}) async {
    final prefs = await SharedPreferences.getInstance();
    if (!_devicePreferencesLoaded) {
      _textScale = normalizeTextScale(
        prefs.getDouble(_textScaleKey) ??
            _legacyTextScale(prefs.getString(_legacyTextSizeKey)),
      );
      final storedTheme = prefs.getString(_themeModeKey);
      _themeMode = ThemeMode.values.firstWhere(
        (m) => m.name == storedTheme,
        orElse: () => ThemeMode.system,
      );
      _hasSeenOnboarding = prefs.getBool(_hasSeenOnboardingKey) ?? false;
      _showMedicineOnLockScreen =
          prefs.getBool(_showMedicineOnLockScreenKey) ?? false;
      _localOnly = prefs.getBool(_localOnlyKey) ?? false;
      _devicePreferencesLoaded = true;
    }
    final requestedOwner =
        consentOwnerId ?? _consentOwnerId ?? localConsentOwnerId;
    if (_consentOwnerId == requestedOwner) return;
    await activateConsentOwner(requestedOwner, prefs: prefs);
  }

  /// Switches processing gates to exactly one person. All flags are cleared
  /// synchronously before the preference read, which prevents sync, AI,
  /// speech, or care code from observing the previous account during the
  /// asynchronous handover.
  Future<void> activateConsentOwner(
    String ownerId, {
    SharedPreferences? prefs,
  }) async {
    if (ownerId.isEmpty) {
      throw ArgumentError.value(ownerId, 'ownerId', 'Consent owner is empty');
    }
    if (!_devicePreferencesLoaded) {
      await init(consentOwnerId: ownerId);
      return;
    }
    if (_consentOwnerId == ownerId) return;

    _consentOwnerId = null;
    _clearConsentValues();
    notifyListeners();

    final store = prefs ?? await SharedPreferences.getInstance();
    await _migrateLegacyLocalConsentsIfNeeded(store, ownerId);
    _hasRecordedConsents =
        store.getBool(_ownerKey(ownerId, _hasRecordedConsentsKey)) ?? false;
    _consentCloudBackup =
        store.getBool(_ownerKey(ownerId, _consentCloudBackupKey)) ?? false;
    _consentAnthropicParse =
        store.getBool(_ownerKey(ownerId, _consentAnthropicParseKey)) ?? false;
    _consentGoogleSpeech =
        store.getBool(_ownerKey(ownerId, _consentGoogleSpeechKey)) ?? false;
    _consentCareShare =
        store.getBool(_ownerKey(ownerId, _consentCareShareKey)) ?? false;
    _consentOwnerId = ownerId;
    notifyListeners();
  }

  static String _ownerKey(String ownerId, String setting) =>
      '$_ownerConsentPrefix.${Uri.encodeComponent(ownerId)}.$setting';

  /// Legacy global choices can only become the local-only owner's choices.
  /// They are never copied into a Google account: a signed-in person must
  /// record their own choices, even on an upgraded install.
  Future<void> _migrateLegacyLocalConsentsIfNeeded(
    SharedPreferences prefs,
    String ownerId,
  ) async {
    if (ownerId != localConsentOwnerId) return;
    // A legacy key can still be present after an interrupted migration. It is
    // safe to replay it into the local namespace; signed-in owners never read
    // this path. Replaying also makes an upgraded local install converge if
    // the process was killed between individual preference writes.
    if (!prefs.containsKey(_hasRecordedConsentsKey)) return;

    for (final key in const [
      _hasRecordedConsentsKey,
      _consentCloudBackupKey,
      _consentAnthropicParseKey,
      _consentGoogleSpeechKey,
      _consentCareShareKey,
    ]) {
      final value = prefs.getBool(key);
      if (value != null) await prefs.setBool(_ownerKey(ownerId, key), value);
      await prefs.remove(key);
    }
  }

  void _clearConsentValues() {
    _hasRecordedConsents = false;
    _consentCloudBackup = false;
    _consentAnthropicParse = false;
    _consentGoogleSpeech = false;
    _consentCareShare = false;
  }

  /// Snaps to the nearest slider step and clamps into range, so a value
  /// coming from an old install (or a future range change) can never land
  /// off-scale.
  static double normalizeTextScale(double scale) {
    final steps = ((scale - minTextScale) / textScaleStep).round();
    final snapped = (minTextScale + steps * textScaleStep).clamp(
      minTextScale,
      maxTextScale,
    );
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

  Future<void> setShowMedicineOnLockScreen(bool value) async {
    if (value == _showMedicineOnLockScreen) return;
    _showMedicineOnLockScreen = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showMedicineOnLockScreenKey, value);
  }

  Future<void> setLocalOnly(bool value) async {
    if (value == _localOnly) return;
    _localOnly = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_localOnlyKey, value);
  }

  Future<void> setHasRecordedConsents() async {
    await _ensureConsentOwner();
    _hasRecordedConsents = true;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(
      _ownerKey(_consentOwnerId!, _hasRecordedConsentsKey),
      true,
    );
  }

  Future<void> setConsentCloudBackup(bool value) => _setConsentFlag(
    () => _consentCloudBackup = value,
    _consentCloudBackupKey,
    value,
    _consentCloudBackup,
  );

  Future<void> setConsentAnthropicParse(bool value) => _setConsentFlag(
    () => _consentAnthropicParse = value,
    _consentAnthropicParseKey,
    value,
    _consentAnthropicParse,
  );

  Future<void> setConsentGoogleSpeech(bool value) => _setConsentFlag(
    () => _consentGoogleSpeech = value,
    _consentGoogleSpeechKey,
    value,
    _consentGoogleSpeech,
  );

  Future<void> setConsentCareShare(bool value) => _setConsentFlag(
    () => _consentCareShare = value,
    _consentCareShareKey,
    value,
    _consentCareShare,
  );

  Future<void> _setConsentFlag(
    void Function() assign,
    String key,
    bool value,
    bool current,
  ) async {
    await _ensureConsentOwner();
    assign();
    if (value != current) notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_ownerKey(_consentOwnerId!, key), value);
  }

  Future<void> _ensureConsentOwner() async {
    if (_consentOwnerId != null) return;
    await init();
  }

  /// Clears in-memory state so a test can call [init] against a fresh
  /// SharedPreferences mock. Not used in production.
  @visibleForTesting
  void resetForTest() {
    _devicePreferencesLoaded = false;
    _consentOwnerId = null;
    _textScale = minTextScale;
    _themeMode = ThemeMode.system;
    _hasSeenOnboarding = false;
    _showMedicineOnLockScreen = false;
    _localOnly = false;
    _clearConsentValues();
  }
}
