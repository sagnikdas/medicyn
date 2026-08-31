import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_settings.dart';
import '../../core/supabase_init.dart';
import '../../data/local/database.dart';
import '../../data/remote/sync_service.dart';
import '../care/care_remote_refresh.dart';
import '../care/dose_feed_screen.dart';
import '../notification_engine/notification_service.dart';
import 'push_events.dart';

/// Runs in a fresh background isolate when a message arrives with the app
/// backgrounded or dead — the case the inbound push exists for. A parent whose
/// phone is in their pocket is exactly who needs a caregiver's schedule change
/// applied, and none of the app's state exists here: no Firebase app, no
/// Supabase client, no database, no widget tree.
///
/// Follows the same pattern as [notificationTapBackground] in
/// notification_engine/notification_actions.dart, including its rule that
/// nothing here may throw. An uncaught exception on this isolate is invisible —
/// no error reporter is attached — and takes the whole re-arm with it.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // A `missed_dose` message carries a notification block, which Android draws
  // itself; this handler fires for it too and has nothing to add.
  if (message.data[pushEventKey] != pushEventDataChanged) return;

  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
    await initializeSupabase();
    // This isolate is fresh, so AppSettings is an unloaded singleton whose
    // consent flags all read false. SyncService.pullAll returns on its very
    // first line without it, which made the silent data_changed message a
    // no-op in exactly the case it exists for: the app not in the
    // foreground. reconcile would then re-arm from an unchanged database,
    // so an edit made on the other phone never reached this one until
    // someone happened to open the app.
    final ownerId = Supabase.instance.client.auth.currentUser?.id;
    if (ownerId == null) return;
    await AppSettings.instance.init(consentOwnerId: ownerId);
  } catch (_) {
    // Already initialized (Android sometimes reuses a warm isolate), or
    // genuinely unavailable. Either way the pull below will tell us.
  }
  await applyRemoteDataChange();
}

/// Pulls whatever changed and re-arms the alarms to match — the whole point of
/// the silent message.
///
/// Opens its own short-lived database rather than reaching for an app-wide
/// singleton, because on the background isolate there isn't one. SQLite
/// serialises the two connections; this is the same trade
/// `notificationTapBackground` already makes to record a Taken tap.
///
/// [db] is passed in from the foreground path, where a live `AppDatabase`
/// already exists and its `.watch()` streams are what refresh the UI — a second
/// connection's writes would not reach them.
Future<void> applyRemoteDataChange({AppDatabase? db}) async {
  final database = db ?? AppDatabase();
  try {
    if (Supabase.instance.client.auth.currentUser == null) return;
    final sync = SyncService(database);
    await sync.pullAll();
    // Unconditional rather than gated on `sync.schedulesChanged`: the message
    // said something changed, and reconcile is idempotent. Gating it would mean
    // a pull that lost a version comparison — or failed silently, as pullAll is
    // designed to — leaves the alarms as they were with nothing to notice it.
    await NotificationService.instance.reconcile(database);
    CareRemoteRefresh.instance.ping();
  } catch (_) {
    // Nothing here can be surfaced or retried from a background isolate. The
    // next app foreground runs the identical pull-and-reconcile, so a failure
    // costs latency rather than correctness.
  } finally {
    if (db == null) await database.close();
  }
}

/// The patient whose feed a missed-dose tap should open, or null when this
/// message is not that tap.
///
/// Kept as a function so the cold-start (`getInitialMessage`) and
/// already-running (`onMessageOpenedApp`) paths cannot disagree, and so a
/// renamed data key fails a test rather than opening nothing with no error.
String? careAlertPatientIdFromData(Map<String, dynamic> data) {
  final event = data[pushEventKey];
  if (event != pushEventMissedDose &&
      event != pushEventDeviceSilent &&
      event != pushEventRefillLow) {
    return null;
  }
  final id = data[pushPatientIdKey];
  if (id is! String || id.isEmpty) return null;
  return id;
}

/// Routes a tapped missed-dose message. Shared by the cold-start and
/// already-running paths so they cannot drift.
void handleCareAlertTap(RemoteMessage message) {
  final patientId = careAlertPatientIdFromData(message.data);
  if (patientId == null) return;
  openFeedForPatient(patientId);
}
