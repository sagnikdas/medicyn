import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_settings.dart';
import '../../core/ids.dart';
import '../../data/local/database.dart';
import '../notification_engine/notification_service.dart';
import 'push_events.dart';
import 'push_handlers.dart';

/// Registers this device to be reached, and handles what arrives.
///
/// Push is what makes three later features honest — a missed dose that reaches
/// the family while it still matters, and a caregiver's schedule change that
/// reaches the parent's alarms rather than waiting for them to open the app.
///
/// Everything here degrades to a no-op when Firebase is unconfigured
/// (google-services.json absent — see README's Push section). That is the state
/// of a fresh checkout, and it must build, run, and keep firing local alarms:
/// the app's actual job never depended on a network.
///
/// Does not call `Firebase.initializeApp()` itself — `MedicynTelemetry.init`
/// (in `main.dart`, ahead of this) already tried, so this only has to check
/// whether that succeeded.
class PushService {
  PushService._();
  static final PushService instance = PushService._();

  bool _initialized = false;
  bool _available = false;
  String? _registeredToken;
  String? _installId;
  StreamSubscription<String>? _refreshSubscription;
  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<RemoteMessage>? _openedSubscription;
  bool _consumedLaunchMessage = false;

  /// Whether push is usable in this build at all. False means Firebase could
  /// not be initialized, which on Android means google-services.json was not
  /// present when the APK was built.
  bool get isAvailable => _available;

  /// Brings up Firebase and starts listening. Safe to call repeatedly; only
  /// the first call does anything.
  ///
  /// Must run before `runApp` for one specific reason: the background message
  /// handler has to be registered while the main isolate is starting up, or a
  /// message arriving with the app dead has nowhere to go.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    if (Firebase.apps.isEmpty) {
      // No google-services.json in this build, or Firebase.initializeApp()
      // failed in MedicynTelemetry.init. Local alarms are unaffected; only
      // the care link's push is.
      _available = false;
      return;
    }
    _available = true;

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // Android's notification permission is already requested by
    // NotificationService (POST_NOTIFICATIONS covers both local alarms and
    // FCM), so asking again here would show the same dialog twice. iOS needs
    // its own ask, and does not have one yet — see PLAN.md, iOS not started.
    if (Platform.isIOS) {
      try {
        await FirebaseMessaging.instance.requestPermission();
      } catch (_) {
        // Declined or unavailable; registration below simply finds no token.
      }
    }
  }

  /// Attaches the listeners that need a live app: a message arriving while the
  /// user is looking at the screen, and a notification tap.
  ///
  /// Separate from [init] because [init] runs before `runApp` — there is no
  /// navigator to open a feed on at that point.
  Future<void> attachForegroundListeners({required AppDatabase db}) async {
    if (!_available) return;
    final ownerId = Supabase.instance.client.auth.currentUser?.id;
    if (ownerId == null ||
        !AppSettings.instance.consentOwnerIs(ownerId) ||
        !AppSettings.instance.hasRecordedConsents ||
        !AppSettings.instance.consentCareShare) {
      await detachAccountListeners();
      return;
    }
    // Cancel first: signing out and back in builds a fresh HomeScreen state,
    // and two live listeners would apply every arriving change twice.
    await _foregroundSubscription?.cancel();
    await _openedSubscription?.cancel();

    _foregroundSubscription = FirebaseMessaging.onMessage.listen((message) {
      if (!_isCurrentOwner(ownerId)) return;
      unawaited(_handleForeground(message, db, ownerId));
    });
    _openedSubscription = FirebaseMessaging.onMessageOpenedApp.listen((
      message,
    ) {
      if (_isCurrentOwner(ownerId)) handleCareAlertTap(message);
    });

    // A tap that cold-started the process is not delivered to the stream
    // above — it is waiting here instead, exactly as with a local
    // notification's launch response. Consumed once: signing out and back
    // in rebuilds HomeScreen and would otherwise call getInitialMessage
    // again, which Firebase still answers with the same launch message.
    await _consumeLaunchMessage();
  }

  Future<void> _consumeLaunchMessage() async {
    if (_consumedLaunchMessage) return;
    _consumedLaunchMessage = true;
    try {
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial == null) return;
      // The navigator may not be attached on this microtask — the same
      // deferral MedicynApp makes for a local-notification cold start. The
      // feed is pushed onto the existing navigator, so a device-credential
      // lock (if the phone has been away) still covers it until unlock.
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => handleCareAlertTap(initial),
      );
    } catch (_) {
      // Not worth a failed launch.
    }
  }

  Future<void> _handleForeground(
    RemoteMessage message,
    AppDatabase db,
    String ownerId,
  ) async {
    if (!_isCurrentOwner(ownerId)) return;
    switch (message.data[pushEventKey]) {
      case pushEventDataChanged:
        // Passing the app's own database matters: the foreground UI is driven
        // by `.watch()` streams on this connection, and a pull written through
        // a second one would not reach them.
        await applyRemoteDataChange(db: db);
      case pushEventMissedDose:
      case pushEventDeviceSilent:
      case pushEventRefillLow:
        // Android does not draw a notification message while the app is in the
        // foreground, so this does it — otherwise a caregiver sitting in the
        // app is the one person who never hears about a missed dose.
        final notification = message.notification;
        if (notification == null) return;
        await NotificationService.instance.showCareAlert(
          title: notification.title ?? 'A dose was missed',
          body: notification.body ?? '',
          patientId: message.data[pushPatientIdKey],
        );
    }
  }

  /// Records this install's FCM token against the signed-in user, so the server
  /// knows where to send. Call on sign-in and on every foreground: a token can
  /// be reissued while the app is not running, and there is no notification of
  /// that beyond the token itself having changed.
  Future<void> registerToken() async {
    if (!_available) return;
    final ownerId = Supabase.instance.client.auth.currentUser?.id;
    if (ownerId == null ||
        !AppSettings.instance.consentOwnerIs(ownerId) ||
        !AppSettings.instance.hasRecordedConsents ||
        !AppSettings.instance.consentCareShare) {
      return;
    }

    // Only ever set up once. Doing it inside register rather than init is
    // deliberate: the stream fires with a *new* token, which is useless before
    // there is a session to attach it to.
    await _refreshSubscription?.cancel();
    _refreshSubscription = FirebaseMessaging.instance.onTokenRefresh.listen((
      token,
    ) {
      if (_isCurrentOwner(ownerId)) unawaited(_upsert(token, ownerId));
    });

    String? token;
    try {
      token = await FirebaseMessaging.instance.getToken();
    } catch (_) {
      // No Play services, or FCM registration is failing on this device. There
      // is nothing to retry here; the next foreground tries again.
      return;
    }
    if (token == null || token.isEmpty) return;
    await _upsert(token, ownerId);
  }

  Future<void> _upsert(String token, String ownerId) async {
    if (!_isCurrentOwner(ownerId)) return;
    try {
      // Through an RPC rather than a table write, and that is load-bearing: an
      // FCM token belongs to an app *install*, not an account, so signing in as
      // a second person on one phone has to move the existing row. RLS cannot
      // express that — the update arm is checked against the row being
      // replaced, which belongs to whoever signed out — so the upsert lives in
      // a security-definer function. The install id is what stops a different
      // phone that has only the token string from doing the same move. See the
      // device-token-possession migration.
      await Supabase.instance.client.rpc(
        'register_device_token',
        params: {
          'p_token': token,
          'p_platform': Platform.isIOS ? 'ios' : 'android',
          'p_install_id': await _ensureInstallId(),
        },
      );
      if (!_isCurrentOwner(ownerId)) return;
      _registeredToken = token;
    } catch (_) {
      // Best-effort. A device that fails to register receives no alerts, which
      // is a degraded care link rather than a broken app, and the next
      // foreground retries.
    }
  }

  /// Stable id for *this* app install, minted once and kept across sign-out.
  ///
  /// SharedPreferences is enough here: the value is not a secret so much as a
  /// proof that this process is the same install that last registered the
  /// token, and F-5 is what stops prefs leaving the device. A new id on every
  /// launch would break the handed-back-phone move, because the second account
  /// would look like a stranger who merely knows the token.
  Future<String> _ensureInstallId() async {
    if (_installId != null) return _installId!;
    final prefs = await SharedPreferences.getInstance();
    const key = 'push_install_id';
    var id = prefs.getString(key);
    if (id == null || id.isEmpty) {
      id = newUuid();
      await prefs.setString(key, id);
    }
    _installId = id;
    return id;
  }

  /// Drops this device's token on sign-out, so a phone handed back stops
  /// receiving the previous account's alerts immediately rather than at
  /// whatever point FCM next reissues its token.
  ///
  /// Must run *before* the Supabase session is cleared — the delete is
  /// authorised by row-level security against the signed-in user.
  Future<void> unregisterToken() async {
    if (!_available) return;
    final token = _registeredToken ?? await _currentTokenQuietly();
    if (token == null) return;
    try {
      await Supabase.instance.client
          .from('device_tokens')
          .delete()
          .eq('token', token);
    } catch (_) {
      // If it survives, the server's first send to it after the next person
      // signs in will move or prune it anyway — a re-registration reassigns
      // the row, and an uninstall makes FCM report it stale.
    }
    _registeredToken = null;
  }

  /// Cancels every callback that captured an account or its open database.
  /// Kept separate from token deletion because sign-out must delete while its
  /// authenticated session still exists, then detach regardless of whether
  /// that network request succeeded.
  Future<void> detachAccountListeners() async {
    final subscriptions = [
      _foregroundSubscription,
      _openedSubscription,
      _refreshSubscription,
    ];
    _foregroundSubscription = null;
    _openedSubscription = null;
    _refreshSubscription = null;
    for (final subscription in subscriptions) {
      await subscription?.cancel();
    }
  }

  bool _isCurrentOwner(String ownerId) =>
      Supabase.instance.client.auth.currentUser?.id == ownerId &&
      AppSettings.instance.consentOwnerIs(ownerId) &&
      AppSettings.instance.hasRecordedConsents &&
      AppSettings.instance.consentCareShare;

  Future<String?> _currentTokenQuietly() async {
    try {
      return await FirebaseMessaging.instance.getToken();
    } catch (_) {
      return null;
    }
  }
}
