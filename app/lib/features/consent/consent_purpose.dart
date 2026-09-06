import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Policy text these hashes were computed against. Bump both together when
/// the on-screen sentences change.
const kConsentPolicyVersion = '2026-09-06';

/// The app version written onto each `record_consent` row. Matches
/// `pubspec.yaml`.
const kConsentAppVersion = '0.1.0+1';

/// One processing purpose, with the exact on-screen sentence that is hashed
/// into the Article 7 record. Changing [sentence] changes the hash; tests
/// pin both.
enum ConsentPurpose {
  cloudBackup,
  anthropicParse,
  googleSpeech,
  careShare;

  String get id => switch (this) {
    cloudBackup => 'cloud_backup',
    anthropicParse => 'anthropic_parse',
    googleSpeech => 'google_speech',
    careShare => 'care_share',
  };

  /// Short label on the switch itself.
  String get title => switch (this) {
    cloudBackup => 'Keep a backup in the cloud',
    anthropicParse => 'Let AI read the label',
    googleSpeech => 'Use voice input',
    careShare => 'Share with family',
  };

  /// The sentence shown under the switch. SHA-256 of this exact string is
  /// what `consents.consent_text_hash` stores.
  String get sentence => switch (this) {
    cloudBackup =>
      'Store your medicines, dose history and other care plans in cloud backup on Supabase, so they are not only on this phone.',
    anthropicParse =>
      'Send the label text and your spoken description to Anthropic in the United States to help fill in the reminder form.',
    googleSpeech =>
      'Use this phone\'s Google speech recogniser. The audio leaves the device.',
    careShare => 'A linked person will see your medicines and dose history.',
  };

  /// Hex SHA-256 of [sentence], utf8. Stable for a given sentence.
  String get textHash => sha256.convert(utf8.encode(sentence)).toString();

  static const firstScreen = [cloudBackup, anthropicParse, googleSpeech];
}

/// Whether the review screen should call the parse-medicine edge function.
/// Unticked Anthropic consent, or nothing to parse, both skip the call —
/// same empty/manual form either way.
bool shouldParseMedicine({
  required bool anthropicGranted,
  required String ocrText,
  required String transcript,
}) {
  if (!anthropicGranted) return false;
  return ocrText.isNotEmpty || transcript.isNotEmpty;
}
