import 'package:supabase_flutter/supabase_flutter.dart';

/// Where a link is in its life. Mirrors the `care_link_status` enum in
/// Postgres — see the care_links migration for what each state permits.
enum CareLinkStatus {
  /// A code has been issued and nobody has entered it yet.
  pending,

  /// Someone entered the code. This grants no access whatsoever; the patient
  /// still has to confirm who it is.
  claimed,

  /// Confirmed. The caregiver can now read and write the patient's data.
  active,

  /// Ended by either side. Kept rather than deleted so "who could see my
  /// medicines, and when" stays answerable.
  revoked,
}

/// Raised for every failure the user should be told about. [message] is
/// written to be shown as-is.
class CareLinkFailure implements Exception {
  const CareLinkFailure(this.message);
  final String message;

  @override
  String toString() => message;
}

/// One person's side of a care link.
class CareLink {
  const CareLink({
    required this.id,
    required this.patientId,
    required this.caregiverId,
    required this.status,
    this.inviteCode,
    this.expiresAt,
  });

  final String id;
  final String patientId;
  final String? caregiverId;
  final CareLinkStatus status;

  /// Only ever populated while [status] is [CareLinkStatus.pending], and only
  /// visible to the patient who issued it.
  final String? inviteCode;
  final DateTime? expiresAt;

  bool isPatient(String userId) => patientId == userId;

  /// The other person in the pair, from [userId]'s point of view. Null while
  /// an invite is still unclaimed.
  String? otherPartyId(String userId) => isPatient(userId) ? caregiverId : patientId;

  static CareLink fromRow(Map<String, dynamic> row) => CareLink(
        id: row['id'] as String,
        patientId: row['patient_id'] as String,
        caregiverId: row['caregiver_id'] as String?,
        status: CareLinkStatus.values.byName(row['status'] as String),
        inviteCode: row['invite_code'] as String?,
        expiresAt: row['expires_at'] == null
            ? null
            : DateTime.parse(row['expires_at'] as String).toLocal(),
      );
}

/// The care link and the profile behind it.
///
/// Every state change goes through a Postgres function rather than a direct
/// write — the `care_links` table has no insert/update/delete policy at all,
/// so these RPCs are the only way to change a link, and each enforces who is
/// allowed to make that particular change. Reads are ordinary selects, which
/// row-level security already scopes to links the caller is part of.
class CareService {
  CareService._();
  static final CareService instance = CareService._();

  SupabaseClient get _client => Supabase.instance.client;

  String? get _userId => _client.auth.currentUser?.id;

  /// Records the signed-in user's name and timezone, so the other side has
  /// something to show besides an opaque id, and so times in a shared view
  /// can be rendered in the right zone. Safe to call on every launch.
  Future<void> upsertOwnProfile() async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    final metadata = user.userMetadata ?? const {};
    final name = (metadata['full_name'] ?? metadata['name']) as String?;
    try {
      await _client.from('profiles').upsert({
        'user_id': user.id,
        'display_name': name?.trim().isNotEmpty == true ? name!.trim() : user.email,
        'timezone': DateTime.now().timeZoneName,
        'last_seen_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (_) {
      // Never block sign-in on this. A missing profile costs a display name,
      // not a working app.
    }
  }

  /// The caller's live link, if any. Revoked links are excluded — they are
  /// history, not state.
  Future<CareLink?> currentLink() async {
    if (_userId == null) return null;
    try {
      final rows = await _client
          .from('care_links')
          .select()
          .neq('status', 'revoked')
          .limit(1);
      if (rows.isEmpty) return null;
      return CareLink.fromRow(rows.first);
    } catch (e) {
      throw CareLinkFailure(_describe(e));
    }
  }

  /// Display name for someone the caller is allowed to see — the other half
  /// of an active link, or themselves. Falls back to null rather than
  /// inventing a name.
  Future<String?> displayName(String userId) async {
    try {
      final rows = await _client
          .from('profiles')
          .select('display_name')
          .eq('user_id', userId)
          .limit(1);
      if (rows.isEmpty) return null;
      return rows.first['display_name'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Issues an invite code, as the person needing help. Replaces any invite
  /// not yet completed, so tapping "show my code" again is always safe.
  Future<String> createInvite() async {
    try {
      final code = await _client.rpc('create_care_invite');
      return code as String;
    } catch (e) {
      throw CareLinkFailure(_describe(e));
    }
  }

  /// Claims someone's invite, as the person helping. Succeeding does **not**
  /// grant access — the link waits in [CareLinkStatus.claimed] until they
  /// confirm it really is you.
  Future<void> claimInvite(String code) async {
    try {
      await _client.rpc('claim_care_invite', params: {'code': code});
    } catch (e) {
      throw CareLinkFailure(_describe(e));
    }
  }

  /// The consent step. Only the patient can do this.
  Future<void> confirmLink(String linkId) async {
    try {
      await _client.rpc('confirm_care_link', params: {'link_id': linkId});
    } catch (e) {
      throw CareLinkFailure(_describe(e));
    }
  }

  /// Ends the link. Either side may, at any point, and it frees both of them
  /// to pair with someone else.
  Future<void> revokeLink(String linkId) async {
    try {
      await _client.rpc('revoke_care_link', params: {'link_id': linkId});
    } catch (e) {
      throw CareLinkFailure(_describe(e));
    }
  }

  /// Turns the database's error codes into something worth reading. The
  /// codes are raised by the lifecycle functions; anything unrecognised is
  /// reported as a connection problem, which is what it almost always is.
  static String _describe(Object error) {
    final raw = error is PostgrestException ? error.message : error.toString();
    if (raw.contains('already_linked')) {
      return "You're already connected to someone. Disconnect first to invite a different person.";
    }
    if (raw.contains('already_a_caregiver')) {
      return "You're already helping someone. Disconnect from them first.";
    }
    if (raw.contains('already_a_patient')) {
      return "Someone is already helping you, so you can't also help someone else.";
    }
    if (raw.contains('invalid_or_expired_code')) {
      return "That code didn't work. Codes last 15 minutes — ask for a fresh one.";
    }
    if (raw.contains('cannot_link_to_self')) {
      return "That's your own code.";
    }
    if (raw.contains('no_link_to_confirm')) {
      return 'That invitation is no longer waiting to be confirmed.';
    }
    if (raw.contains('no_link_to_revoke')) {
      return 'That connection has already ended.';
    }
    if (raw.contains('not_authenticated')) {
      return 'Please sign in again.';
    }
    return 'Could not reach the server. Check your connection and try again.';
  }
}
