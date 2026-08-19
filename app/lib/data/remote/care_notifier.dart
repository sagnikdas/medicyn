import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/push/push_events.dart';

/// Asks the server to tell the other side of a care link that something
/// happened. Never throws: a notification that failed to go out must not take a
/// sync, a save, or a foreground with it — the data is already in Postgres by
/// the time any of these are called, which is the part that had to work.
///
/// Deliberately fire-and-forget in *effect* but awaited in *shape*, so callers
/// that want to sequence it can, and callers that don't can `unawaited` it.
class CareNotifier {
  CareNotifier._();
  static final CareNotifier instance = CareNotifier._();

  /// Bounded like every other network call in the app (see SyncService): an
  /// unresolved await here would hang a foreground indefinitely.
  static const _timeout = Duration(seconds: 8);

  SupabaseClient get _client => Supabase.instance.client;

  /// Announces doses this device has just recorded as missed and pushed.
  ///
  /// Only the ids go up. The notification's wording is composed server-side
  /// from those rows, so what a family is told cannot be assembled here — and
  /// cannot be forged by anything that gets hold of a session token.
  ///
  /// Safe to call with ids that have already been announced: the server
  /// de-duplicates on (link, dose) and sends nothing the second time.
  Future<void> missedDoses(List<String> doseLogIds) async {
    if (doseLogIds.isEmpty) return;
    await _invoke({
      pushEventKey: pushEventMissedDose,
      'doseLogIds': doseLogIds,
    });
  }

  /// Announces that this device has pushed an edit to medicines or schedules.
  ///
  /// The server drops it unless the caller is the *caregiver* of the link —
  /// the patient's phone is the only one with alarms to re-arm, and a change
  /// the patient made is already applied on their own device. So today this is
  /// a no-op in practice: caregiver-side editing is Phase 2. It is wired now so
  /// that when the edit form lands, the rails under it already work.
  Future<void> dataChanged() async {
    await _invoke({pushEventKey: pushEventDataChanged});
  }

  Future<void> _invoke(Map<String, dynamic> body) async {
    if (_client.auth.currentUser == null) return;
    try {
      await _client.functions.invoke('notify-care', body: body).timeout(_timeout);
    } catch (_) {
      // Swallowed on purpose. Every caller has already committed the data this
      // was announcing; retrying is not possible from here (the dose logs are
      // marked synced) and surfacing it would put a failure in front of someone
      // who cannot act on it. The server-side `care_alerts.delivered_count` is
      // where an undelivered alert is actually visible.
    }
  }
}
