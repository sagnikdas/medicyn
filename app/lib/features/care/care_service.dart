import 'package:flutter/foundation.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/local/database.dart';
import '../../data/local/tables.dart';
import '../notification_engine/device_health.dart';
import '../notification_engine/schedule_validation.dart';

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
    this.patientPhone,
    this.caregiverPhone,
  });

  final String id;
  final String patientId;
  final String? caregiverId;
  final CareLinkStatus status;

  /// Only ever populated while [status] is [CareLinkStatus.pending], and only
  /// visible to the patient who issued it.
  final String? inviteCode;
  final DateTime? expiresAt;

  /// Number the caregiver rings. Stored by the patient.
  final String? patientPhone;

  /// Number the patient rings. Stored by the caregiver.
  final String? caregiverPhone;

  bool isPatient(String userId) => patientId == userId;

  /// The other person in the pair, from [userId]'s point of view. Null while
  /// an invite is still unclaimed.
  String? otherPartyId(String userId) =>
      isPatient(userId) ? caregiverId : patientId;

  /// The number [userId] should dial to reach the other person.
  String? phoneToCall(String userId) =>
      isPatient(userId) ? caregiverPhone : patientPhone;

  /// The number [userId] themselves stored, so the form can show it back.
  String? ownPhone(String userId) =>
      isPatient(userId) ? patientPhone : caregiverPhone;

  static CareLink fromRow(Map<String, dynamic> row) => CareLink(
    id: row['id'] as String,
    patientId: row['patient_id'] as String,
    caregiverId: row['caregiver_id'] as String?,
    status: CareLinkStatus.values.byName(row['status'] as String),
    inviteCode: row['invite_code'] as String?,
    expiresAt: row['expires_at'] == null
        ? null
        : DateTime.parse(row['expires_at'] as String).toLocal(),
    patientPhone: row['patient_phone'] as String?,
    caregiverPhone: row['caregiver_phone'] as String?,
  );
}

/// The person who claimed a pending invite, as shown on the patient's
/// confirmation prompt. Both fields are required: a Google display name
/// alone is weak proof, and a missing email means we cannot name them.
class CareClaimant {
  const CareClaimant({required this.displayName, required this.email});

  final String displayName;
  final String email;

  /// Null unless both a name and an email are present. Confirmation must
  /// fail closed rather than invent a person.
  static CareClaimant? tryParse(Object? raw) {
    Map<String, dynamic>? row;
    if (raw is List) {
      if (raw.isEmpty) return null;
      final first = raw.first;
      if (first is Map) row = Map<String, dynamic>.from(first);
    } else if (raw is Map) {
      row = Map<String, dynamic>.from(raw);
    }
    if (row == null) return null;
    final name = (row['display_name'] as String?)?.trim();
    final email = (row['email'] as String?)?.trim();
    if (name == null || name.isEmpty || email == null || email.isEmpty) {
      return null;
    }
    return CareClaimant(displayName: name, email: email);
  }
}

/// Who someone is, as far as the other side of a link can see.
class CareProfile {
  const CareProfile({
    required this.userId,
    this.displayName,
    this.timezone,
    this.lastSeenAt,
    this.notificationsAllowed,
    this.exactAlarmsAllowed,
    this.batteryExemption,
    this.armedAlarmCount,
    this.healthCheckedAt,
  });

  final String userId;
  final String? displayName;

  /// IANA identifier, e.g. "Asia/Kolkata". Null on a profile written before
  /// this was captured, or where the device wouldn't say.
  final String? timezone;

  /// When this signed-in app last wrote the profile. The caregiver's
  /// "last check-in".
  final DateTime? lastSeenAt;

  final bool? notificationsAllowed;
  final bool? exactAlarmsAllowed;
  final bool? batteryExemption;
  final int? armedAlarmCount;
  final DateTime? healthCheckedAt;

  /// True when any of the things that actually make a reminder fire is off.
  bool get remindersMayNotFire {
    if (notificationsAllowed == false) return true;
    if (exactAlarmsAllowed == false) return true;
    if (batteryExemption == false) return true;
    if (armedAlarmCount == 0) return true;
    return false;
  }
}

/// One row of per-medicine change history. Append-only; the database writes
/// it, not the client.
class MedicineEdit {
  const MedicineEdit({
    required this.id,
    required this.medicineId,
    required this.ownerId,
    this.actorId,
    required this.summary,
    required this.createdAt,
  });

  final String id;
  final String medicineId;
  final String ownerId;
  final String? actorId;
  final String summary;
  final DateTime createdAt;

  static MedicineEdit fromRow(Map<String, dynamic> row) => MedicineEdit(
    id: row['id'] as String,
    medicineId: row['medicine_id'] as String,
    ownerId: row['owner_id'] as String,
    actorId: row['actor_id'] as String?,
    summary: row['summary'] as String? ?? '',
    createdAt: DateTime.parse(row['created_at'] as String),
  );
}

/// One recorded response to a dose reminder.
class DoseEvent {
  const DoseEvent({
    required this.id,
    required this.scheduledAt,
    required this.loggedAt,
    required this.action,
    required this.drugName,
    required this.strength,
    required this.doseAmount,
    this.scheduleId,
    this.source,
    this.recordedBy,
  });

  final String id;

  /// The reminder this log belongs to. Null on a malformed row that
  /// omitted it — the feed still renders; the calendar cannot match
  /// the slot without it.
  final String? scheduleId;

  /// When the dose was due, and when the person actually answered. Both are
  /// absolute instants, so the gap between them means the same thing from any
  /// timezone — which is why the feed leads with it.
  final DateTime scheduledAt;
  final DateTime loggedAt;

  /// 'taken', 'snoozed' or 'missed'.
  final String action;

  final String drugName;
  final String strength;
  final String doseAmount;

  /// How the row was produced. The official app writes `notification` for a
  /// Taken/Snooze tap and `auto` for the missed-dose sweep. Anything else is
  /// unusual and worth a quiet note on the feed.
  final String? source;

  /// Who Postgres stamped as the writer (`dose_logs.recorded_by`). Null on
  /// rows from before that column existed, or on a malformed response.
  final String? recordedBy;

  /// How late the response was. Negative when answered early, which happens
  /// often and legitimately — people take a tablet when they remember it.
  Duration get lateness => loggedAt.difference(scheduledAt);

  String get title => strength.isEmpty ? drugName : '$drugName $strength';

  /// Punctuality in words, or null when the event isn't one that has any —
  /// a snoozed or missed dose was never "on time".
  ///
  /// A few minutes either way is reported as on time. Nobody takes a tablet
  /// the second an alarm sounds, and saying "3 minutes late" about every
  /// single dose would train someone to ignore the line that eventually says
  /// something worth reading.
  String? get punctuality {
    if (action != 'taken') return null;
    final minutes = lateness.inMinutes;
    if (minutes.abs() < 5) return 'On time';
    if (minutes < 0) return '${_span(-minutes)} early';
    return '${_span(minutes)} late';
  }

  static String _span(int minutes) {
    if (minutes < 60) return '$minutes minutes';
    final hours = minutes ~/ 60;
    if (hours < 24) return hours == 1 ? '1 hour' : '$hours hours';
    final days = hours ~/ 24;
    return days == 1 ? '1 day' : '$days days';
  }

  /// Sources the official app actually writes. Anything outside this set is
  /// worth a quiet note; `notification` on every Taken tap is not.
  static const _deviceSources = {'notification', 'auto', 'calendar'};

  /// A quiet line for the feed when this row wasn't a normal recording from
  /// the patient's own device. Null for ordinary Taken / Snooze / missed
  /// answers, so the card stays uncluttered.
  String? attributionNote(String patientId) {
    final loggedByOther = recordedBy != null && recordedBy != patientId;
    if (loggedByOther) return 'Logged by someone else';
    final sourceUnusual =
        source != null &&
        source!.isNotEmpty &&
        !_deviceSources.contains(source);
    if (sourceUnusual) return 'Not from the reminder';
    return null;
  }

  static DoseEvent fromRow(Map<String, dynamic> row) {
    // PostgREST nests the embedded rows; a dose log cannot exist without its
    // schedule and medicine, and the query inner-joins both, so anything
    // missing here is a malformed response rather than a normal absence.
    final schedule = (row['schedules'] as Map?)?.cast<String, dynamic>();
    final medicine = (schedule?['medicines'] as Map?)?.cast<String, dynamic>();
    return DoseEvent(
      id: row['id'] as String,
      scheduleId:
          (row['schedule_id'] as String?) ?? (schedule?['id'] as String?),
      scheduledAt: DateTime.parse(row['scheduled_at'] as String),
      loggedAt: DateTime.parse(row['logged_at'] as String),
      action: row['action'] as String,
      drugName: (medicine?['drug_name'] as String?) ?? 'Medicine',
      strength: (medicine?['strength'] as String?) ?? '',
      doseAmount: (medicine?['dose_amount'] as String?) ?? '',
      source: row['source'] as String?,
      recordedBy: row['recorded_by'] as String?,
    );
  }
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
  /// something to show besides an opaque id, and so a shared view can render
  /// times in the zone the person actually lives in. Safe to call on every
  /// launch.
  ///
  /// The timezone is the IANA identifier ("Asia/Kolkata"), not
  /// `DateTime.timeZoneName`. The latter yields an abbreviation like "IST",
  /// which is ambiguous — India and Ireland both claim it — and cannot be
  /// converted with. Whole-country offsets are exactly what a family split
  /// across cities needs to get right.
  Future<void> upsertOwnProfile() async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    final metadata = user.userMetadata ?? const {};
    final name = (metadata['full_name'] ?? metadata['name']) as String?;
    String? timezone;
    try {
      timezone = (await FlutterTimezone.getLocalTimezone()).identifier;
    } catch (_) {
      // Leave it null rather than storing something unusable.
    }
    try {
      await _client.from('profiles').upsert({
        'user_id': user.id,
        'display_name': name?.trim().isNotEmpty == true
            ? name!.trim()
            : user.email,
        'timezone': ?timezone,
        'last_seen_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (_) {
      // Never block sign-in on this. A missing profile costs a display name,
      // not a working app.
    }
  }

  /// Name and timezone for someone the caller is allowed to see. Null when
  /// there is no profile row rather than a guessed one.
  Future<CareProfile?> profile(String userId) async {
    try {
      final rows = await _client
          .from('profiles')
          .select(
            'user_id, display_name, timezone, last_seen_at, '
            'notifications_allowed, exact_alarms_allowed, battery_exemption, '
            'armed_alarm_count, health_checked_at',
          )
          .eq('user_id', userId)
          .limit(1);
      if (rows.isEmpty) return null;
      final row = rows.first;
      return CareProfile(
        userId: row['user_id'] as String,
        displayName: row['display_name'] as String?,
        timezone: row['timezone'] as String?,
        lastSeenAt: _asDate(row['last_seen_at']),
        notificationsAllowed: row['notifications_allowed'] as bool?,
        exactAlarmsAllowed: row['exact_alarms_allowed'] as bool?,
        batteryExemption: row['battery_exemption'] as bool?,
        armedAlarmCount: _asInt(row['armed_alarm_count']),
        healthCheckedAt: _asDate(row['health_checked_at']),
      );
    } catch (_) {
      return null;
    }
  }

  /// Dose activity for [userId], newest first — the other half of a link's
  /// point.
  ///
  /// Read straight from Supabase rather than the local Drift database: this
  /// is deliberately *someone else's* data, and the local database holds only
  /// the signed-in person's own reminders. Row-level security is what decides
  /// whether this returns anything.
  Future<List<DoseEvent>> doseFeed(String userId, {int limit = 200}) async {
    try {
      final rows = await _client
          .from('dose_logs')
          .select(
            'id, schedule_id, scheduled_at, logged_at, action, source, recorded_by, '
            'schedules!inner(id, medicines!inner(drug_name, strength, dose_amount))',
          )
          .eq('user_id', userId)
          .order('scheduled_at', ascending: false)
          .limit(limit);
      return rows.map(DoseEvent.fromRow).toList();
    } catch (e) {
      throw CareLinkFailure(_describe(e));
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
  /// inventing a name. Does **not** resolve a claimed (unconfirmed) claimant;
  /// use [claimedLinkClaimant] for that.
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

  /// Name and email of the person who claimed [linkId], usable only by the
  /// patient while the link is still [CareLinkStatus.claimed]. Null when the
  /// RPC returns nothing or either field is empty — the confirm prompt must
  /// not invent an identity.
  Future<CareClaimant?> claimedLinkClaimant(String linkId) async {
    try {
      final raw = await _client.rpc(
        'claimed_care_link_claimant',
        params: {'link_id': linkId},
      );
      return CareClaimant.tryParse(raw);
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
      final raw = await _client.rpc(
        'claim_care_invite',
        params: {'code': code},
      );
      final error = claimInviteError(raw);
      if (error != null) throw CareLinkFailure(_describe(error));
    } on CareLinkFailure {
      rethrow;
    } catch (e) {
      throw CareLinkFailure(_describe(e));
    }
  }

  /// Error code from [claim_care_invite]'s jsonb payload, or null on success.
  /// Hosted Postgres cannot RAISE on a failed guess (the attempt ledger would
  /// roll back), so refusal is a committed `{"error": ...}` instead.
  @visibleForTesting
  static String? claimInviteError(Object? raw) {
    if (raw is Map) {
      final error = raw['error'];
      if (error is String && error.isNotEmpty) return error;
    }
    return null;
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

  /// Stores this person's own number on the active link so the other side
  /// can ring it. Pass empty to clear.
  Future<void> setOwnPhone(String phone) async {
    try {
      await _client.rpc('set_own_care_phone', params: {'phone': phone});
    } catch (e) {
      throw CareLinkFailure(_describe(e));
    }
  }

  /// The patient's medicines and schedules, read from Supabase — not Drift.
  ///
  /// A caregiver's local database is *their* reminders. Writing the patient's
  /// schedules there would arm alarms on the wrong phone. Row-level security
  /// is what decides whether this returns anything.
  Future<List<ScheduleWithMedicine>> patientReminders(String patientId) async {
    try {
      final rows = await _client
          .from('schedules')
          .select(
            'id, medicine_id, user_id, frequency_type, times, days_of_week, '
            'interval_hours, active, created_at, updated_at, updated_by, '
            // tablets_remaining / tablets_per_dose have to be here even
            // though this screen does not show a pill count: reminderFromRow
            // reads them, the edit screen fills its fields from what it
            // reads, and savePatientReminder writes those fields straight
            // back. Leaving them out of the select made every caregiver
            // edit — a strength correction, a time change — silently null
            // the patient's refill tracking, which is what the refill_low
            // alert is computed from.
            'medicines!inner(id, drug_name, strength, form, dose_amount, notes, '
            'tablets_remaining, tablets_per_dose, '
            'created_at, updated_at, updated_by)',
          )
          .eq('user_id', patientId)
          .eq('active', true);
      final out = <ScheduleWithMedicine>[];
      for (final row in rows) {
        final parsed = reminderFromRow(Map<String, dynamic>.from(row));
        if (parsed != null) out.add(parsed);
      }
      out.sort((a, b) => b.schedule.updatedAt.compareTo(a.schedule.updatedAt));
      return out;
    } catch (e) {
      throw CareLinkFailure(_describe(e));
    }
  }

  /// Writes a medicine and its schedule under [patientId]. Does not arm
  /// alarms on this phone — that is the patient's device's job, via the
  /// silent `data_changed` push.
  Future<void> savePatientReminder({
    required String patientId,
    required String medicineId,
    required String scheduleId,
    required String drugName,
    required String strength,
    required String form,
    required String doseAmount,
    int? tabletsRemaining,
    int? tabletsPerDose,
    required String notes,
    required String frequencyType,
    required List<String> times,
    required List<int> daysOfWeek,
    required int? intervalHours,
    String? status,
    DateTime? startDate,
    DateTime? endDate,
    DateTime? pauseUntil,
    required DateTime savedAt,
    DateTime? medicineCreatedAt,
    DateTime? scheduleCreatedAt,
  }) async {
    final caller = _userId;
    if (caller == null) throw const CareLinkFailure('Please sign in again.');
    final stamp = _isoUtc(savedAt);
    final medicineCreated = _isoUtc(medicineCreatedAt ?? savedAt);
    final scheduleCreated = _isoUtc(scheduleCreatedAt ?? savedAt);
    try {
      await _client.from('medicines').upsert({
        'id': medicineId,
        'user_id': patientId,
        'drug_name': drugName,
        'strength': strength,
        'form': form,
        'dose_amount': doseAmount,
        'tablets_remaining': tabletsRemaining,
        'tablets_per_dose': tabletsPerDose,
        'notes': notes,
        'created_at': medicineCreated,
        'updated_at': stamp,
        'updated_by': caller,
      });
      await _client.from('schedules').upsert({
        'id': scheduleId,
        'medicine_id': medicineId,
        'user_id': patientId,
        'frequency_type': frequencyType,
        'times': times,
        'days_of_week': daysOfWeek,
        'interval_hours': intervalHours,
        'status': status,
        'start_date': startDate == null ? null : _isoUtc(startDate),
        'end_date': endDate == null ? null : _isoUtc(endDate),
        'pause_until': pauseUntil == null ? null : _isoUtc(pauseUntil),
        'active':
            status == null ||
            status == ReminderStatus.active.name ||
            status == ReminderStatus.asNeeded.name,
        'created_at': scheduleCreated,
        'updated_at': stamp,
        'updated_by': caller,
      });
    } catch (e) {
      debugPrint('[medicyn] savePatientReminder failed: $e');
      throw CareLinkFailure(_describe(e));
    }
  }

  /// Newest first. Both sides of an active link may read; nobody inserts
  /// from the client — a trigger does.
  Future<List<MedicineEdit>> medicineEdits(String medicineId) async {
    try {
      final rows = await _client
          .from('medicine_edits')
          .select('id, medicine_id, owner_id, actor_id, summary, created_at')
          .eq('medicine_id', medicineId)
          .order('created_at', ascending: false)
          .limit(100);
      return rows
          .map((r) => MedicineEdit.fromRow(Map<String, dynamic>.from(r)))
          .toList();
    } catch (e) {
      throw CareLinkFailure(_describe(e));
    }
  }

  /// Writes this phone's permission / armed-count snapshot onto the caller's
  /// own profile. Safe to skip: a missed report leaves the previous one.
  Future<void> reportOwnDeviceHealth(DeviceHealthSnapshot health) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    try {
      await _client
          .from('profiles')
          .update({
            'notifications_allowed': health.notificationsAllowed,
            'exact_alarms_allowed': health.exactAlarmsAllowed,
            'battery_exemption': health.batteryExemption,
            'armed_alarm_count': health.armedAlarmCount,
            'health_checked_at': _isoUtc(health.checkedAt),
            'last_seen_at': _isoUtc(health.checkedAt),
          })
          .eq('user_id', user.id);
    } catch (_) {
      // Same as upsertOwnProfile: never block a foreground on this.
    }
  }

  /// Turns a PostgREST schedule+medicine row into the same shape the home
  /// list uses. Null when the schedule cannot be armed — skip it rather
  /// than crash the caregiver's list.
  @visibleForTesting
  static ScheduleWithMedicine? reminderFromRow(Map<String, dynamic> row) {
    final medicineRow = (row['medicines'] as Map?)?.cast<String, dynamic>();
    if (medicineRow == null) return null;
    final fields = sanitiseScheduleFields(
      frequencyType: row['frequency_type'] as String?,
      times: (row['times'] as List?)?.whereType<String>().toList() ?? const [],
      daysOfWeek:
          (row['days_of_week'] as List?)
              ?.whereType<num>()
              .map((e) => e.toInt())
              .toList() ??
          const [],
      intervalHours: _asInt(row['interval_hours']),
    );
    if (fields == null) return null;
    final medicineUpdated =
        _asDate(medicineRow['updated_at']) ??
        DateTime.fromMillisecondsSinceEpoch(0);
    final scheduleUpdated = _asDate(row['updated_at']) ?? medicineUpdated;
    final medicineCreated =
        _asDate(medicineRow['created_at']) ?? medicineUpdated;
    final scheduleCreated = _asDate(row['created_at']) ?? scheduleUpdated;
    final medicine = Medicine(
      id: medicineRow['id'] as String,
      drugName: (medicineRow['drug_name'] as String?) ?? 'Medicine',
      strength: (medicineRow['strength'] as String?) ?? '',
      form: (medicineRow['form'] as String?) ?? '',
      doseAmount: (medicineRow['dose_amount'] as String?) ?? '',
      notes: (medicineRow['notes'] as String?) ?? '',
      tabletsRemaining: _asInt(medicineRow['tablets_remaining']),
      tabletsPerDose: _asInt(medicineRow['tablets_per_dose']),
      createdAt: medicineCreated,
      updatedAt: medicineUpdated,
      updatedBy: medicineRow['updated_by'] as String?,
      pendingSync: false,
      deleted: false,
    );
    final schedule = Schedule(
      id: row['id'] as String,
      medicineId: medicine.id,
      frequencyType: fields.frequency.name,
      times: fields.times,
      daysOfWeek: fields.daysOfWeek,
      intervalHours: fields.intervalHours,
      status: row['status'] as String?,
      startDate: _asDate(row['start_date']),
      endDate: _asDate(row['end_date']),
      pauseUntil: _asDate(row['pause_until']),
      active: row['active'] as bool? ?? true,
      createdAt: scheduleCreated,
      updatedAt: scheduleUpdated,
      updatedBy: row['updated_by'] as String? ?? medicine.updatedBy,
      pendingSync: false,
      deleted: false,
    );
    return ScheduleWithMedicine(schedule, medicine);
  }

  static DateTime? _asDate(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return null;
  }

  static String _isoUtc(DateTime value) => value.toUtc().toIso8601String();

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
    if (raw.contains('too_many_attempts')) {
      return 'Too many tries. Wait a few minutes and ask for a fresh number.';
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
    if (raw.contains('no_active_link')) {
      return "You're not connected to anyone right now.";
    }
    if (raw.contains('phone_too_long')) {
      return 'That number is too long. Use a mobile number with the country code.';
    }
    if (raw.contains('not_authenticated')) {
      return 'Please sign in again.';
    }
    if (raw.contains('cannot_reassign_owner')) {
      return 'That reminder belongs to their account and cannot be moved.';
    }
    return 'Could not reach the server. Check your connection and try again.';
  }
}
