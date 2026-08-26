import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_settings.dart';
import '../../core/telemetry.dart';
import '../care/care_service.dart';
import '../push/push_service.dart';
import 'consent_purpose.dart';

/// Local prefs are the source of truth for gating. The server row is the
/// Article 7 record for a signed-in user, written best-effort — an RPC
/// failure must never block a toggle on the device.
class ConsentService {
  ConsentService._();
  static final ConsentService instance = ConsentService._();

  bool isGranted(ConsentPurpose purpose) {
    final settings = AppSettings.instance;
    return switch (purpose) {
      ConsentPurpose.cloudBackup => settings.consentCloudBackup,
      ConsentPurpose.anthropicParse => settings.consentAnthropicParse,
      ConsentPurpose.googleSpeech => settings.consentGoogleSpeech,
      ConsentPurpose.careShare => settings.consentCareShare,
    };
  }

  /// Persist locally first, then upsert the server row if a session exists.
  /// Withdrawing family sharing also ends any live Care Link — otherwise
  /// the toggle would lie while the other person still had access.
  Future<void> setGranted(ConsentPurpose purpose, bool granted) async {
    if (purpose == ConsentPurpose.careShare && !granted) {
      await _revokeLiveCareLink();
    }
    await _persistLocal(purpose, granted);
    await _recordOnServer(purpose, granted);
    await DoselyTelemetry.instance.record(
      DoselyEvent.permissionResult,
      properties: {
        'permission_type': 'consent_${purpose.id}',
        'result': granted ? 'granted' : 'withheld',
      },
    );
    if (purpose == ConsentPurpose.careShare) {
      if (granted) {
        await PushService.instance.registerToken();
      } else {
        await PushService.instance.unregisterToken();
        await PushService.instance.detachAccountListeners();
      }
    }
  }

  /// First-screen Continue: store the three choices (care-share is not
  /// asked here) and mark the screen as seen so it does not appear again.
  Future<void> recordFirstScreenChoices({
    required bool cloudBackup,
    required bool anthropicParse,
    required bool googleSpeech,
  }) async {
    await setGranted(ConsentPurpose.cloudBackup, cloudBackup);
    await setGranted(ConsentPurpose.anthropicParse, anthropicParse);
    await setGranted(ConsentPurpose.googleSpeech, googleSpeech);
    await AppSettings.instance.setHasRecordedConsents();
  }

  /// Best-effort upsert of the four local flags after a session exists.
  /// Safe to call more than once; the device remains the gating source.
  Future<void> syncToServer() async {
    if (!AppSettings.instance.hasRecordedConsents) return;
    for (final purpose in ConsentPurpose.values) {
      await _recordOnServer(purpose, isGranted(purpose));
    }
  }

  Future<void> _persistLocal(ConsentPurpose purpose, bool granted) {
    final settings = AppSettings.instance;
    return switch (purpose) {
      ConsentPurpose.cloudBackup => settings.setConsentCloudBackup(granted),
      ConsentPurpose.anthropicParse => settings.setConsentAnthropicParse(
        granted,
      ),
      ConsentPurpose.googleSpeech => settings.setConsentGoogleSpeech(granted),
      ConsentPurpose.careShare => settings.setConsentCareShare(granted),
    };
  }

  Future<void> _recordOnServer(ConsentPurpose purpose, bool granted) async {
    try {
      final client = Supabase.instance.client;
      if (client.auth.currentUser == null) return;
      await client.rpc(
        'record_consent',
        params: {
          'p_purpose': purpose.id,
          'p_granted': granted,
          'p_policy_version': kConsentPolicyVersion,
          'p_consent_text_hash': purpose.textHash,
          'p_app_version': kConsentAppVersion,
        },
      );
    } on AssertionError {
      // Supabase is not initialized (widget tests, and the consent screen
      // before sign-in still persists locally).
    } catch (e) {
      debugPrint('record_consent failed: $e');
    }
  }

  Future<void> _revokeLiveCareLink() async {
    try {
      if (Supabase.instance.client.auth.currentUser == null) return;
      final link = await CareService.instance.currentLink();
      if (link == null || link.status == CareLinkStatus.revoked) return;
      await CareService.instance.revokeLink(link.id);
    } on AssertionError {
      // Tests and the first-screen path have no session.
    } catch (e) {
      debugPrint('care_share withdraw did not revoke the link: $e');
    }
  }
}
