import 'package:flutter/foundation.dart';
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

  /// How far back a foreground re-offers missed doses for announcement.
  ///
  /// Long enough to recover an alert lost to a failed call — the phone simply
  /// offers it again next time, and the server's de-duplication means only the
  /// first offer ever rings anyone. Short enough that a dose missed last week
  /// does not ring a phone today: by then nobody can act on it, and the feed is
  /// where history belongs.
  static const announceWindow = Duration(hours: 24);

  SupabaseClient get _client => Supabase.instance.client;

  /// Announces doses this device has just recorded as missed and pushed.
  ///
  /// Only the ids go up. The notification's wording is composed server-side
  /// from those rows, so what a family is told cannot be assembled here — and
  /// cannot be forged by anything that gets hold of a session token.
  ///
  /// Safe — and expected — to call with ids that have already been announced:
  /// the server de-duplicates on (link, dose) and sends nothing the second
  /// time. That is what lets the caller re-offer the same window on every
  /// foreground instead of having to get one call right.
  Future<void> missedDoses(List<String> doseLogIds) async {
    if (doseLogIds.isEmpty) return;
    await _invoke({
      pushEventKey: pushEventMissedDose,
      'doseLogIds': doseLogIds,
    });
  }

  /// Announces that this device has pushed an edit to medicines or schedules.
  ///
  /// Either side of an active link may raise it. The server delivers a silent
  /// data message to the other person: the parent re-arms, the caregiver
  /// refreshes the remote list. There is still no visible notification.
  Future<void> dataChanged() async {
    await _invoke({pushEventKey: pushEventDataChanged});
  }

  /// Announces that a tracked bottle on this device would last five days or
  /// fewer. The server de-duplicates to one ping per link per day.
  Future<void> refillLow() async {
    await _invoke({pushEventKey: pushEventRefillLow});
  }

  Future<void> _invoke(Map<String, dynamic> body) async {
    if (_client.auth.currentUser == null) return;
    try {
      await _client.functions.invoke('notify-care', body: body).timeout(_timeout);
    } catch (error) {
      // Never rethrown: every caller has already committed the data this was
      // announcing, and putting a failure in front of someone who cannot act on
      // it helps nobody. The next foreground offers the same doses again.
      //
      // Logged, though, and that is not decoration. A silent catch here meant a
      // failure to tell a family about a missed dose left no trace anywhere —
      // not on the device, and not in `care_alerts`, which only ever records
      // what *did* go out. Debugging one cost a round trip through the database,
      // the deployed function and the device's own sqlite before it could even
      // be localised to this line.
      debugPrint('[dosely] notify-care failed: $error');
    }
  }
}
