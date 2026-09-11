# iOS Implementation Plan

Companion to `FEATURE_PARITY.md`. Ordered by dependency, not by importance —
an item late in this list can still be a launch blocker; it is late because
something earlier has to exist first.

## Already done (this session)

1. `ios/Runner/Runner.entitlements` created (`aps-environment`), wired into
   all three Runner build configs via `CODE_SIGN_ENTITLEMENTS`.
2. `Info.plist`: added `UIBackgroundModes: [remote-notification]`.
3. `supabase/functions/notify-care/fcm.ts`: added the missing `apns` block
   (silent `content-available` for `data_changed`, `aps.sound` for visible
   alerts) — this was a real, silent, hard-to-diagnose delivery failure on
   iOS, not a documentation gap. Extracted `buildFcmRequestBody()` so it's
   unit-testable; two new Deno tests added.
4. `.github/workflows/ios-release.yml`: added a step that rewrites
   `Runner.entitlements`' `aps-environment` to match whatever the actual
   distribution provisioning profile grants, immediately before archiving —
   otherwise the archive would fail once billing/signing are restored,
   independent of everything else in this plan.
5. Verified (not assumed): `flutter analyze` clean, `flutter test` 552/552,
   `deno test` 16/16, `flutter build ios --release --no-codesign` succeeds
   (device-arch), `flutter build ios --debug --simulator` succeeds and the
   app runs and renders correctly on an iOS 18.3 Simulator.

## 0. Prerequisites this plan cannot satisfy itself

These block real device/TestFlight verification regardless of code state.
Listed here once; not repeated at every step that needs one.

- **A. Apple Developer Program account + team ID.** Needed for everything
  below. Owner action.
- **B. GitHub Actions billing restored** on the `sagnikdas/medicyn` repo —
  `ios-compile.yml` and `ios-release.yml` currently fail in ~7s at runner
  allocation, before touching any code. Owner action (Settings → Billing).
- **C. A physical iPhone**, or continued access to this machine's Simulator.
  No device was attached to this session.

## 1. Apple Developer Portal configuration (needs prerequisite A)

1. Register App ID `com.sagnikdas.medicyn` (if not already present — could
   not check without portal access).
2. Enable capabilities on that App ID: **Push Notifications**, and
   **Sign in with Apple only if the product later requires it** (Google
   Sign-In alone does not need it — see §3; Apple only *mandates* Sign in
   with Apple as an option when another third-party social login exists,
   which Google Sign-In is, so this is a real App Store Review risk worth a
   deliberate go/no-go, not an oversight to silently skip).
3. Create a **Distribution certificate** and a **distribution provisioning
   profile** (App Store type) for that App ID. Export the certificate as
   `.p12` with a password.
4. Base64-encode the certificate, its password, the profile, and set them as
   the `ios-release` GitHub Environment secrets `ios-release.yml` already
   expects: `IOS_CERTIFICATE_P12_BASE64`, `IOS_CERTIFICATE_PASSWORD`,
   `IOS_PROVISIONING_PROFILE_BASE64`, `IOS_PROVISIONING_PROFILE_NAME`,
   `IOS_TEAM_ID`. The workflow already validates all of these are present
   before doing anything else — a missing one fails fast with a named error,
   not a cryptic codesign failure.
5. Create the App Store Connect app record; set export-compliance
   classification (this app does no proprietary encryption beyond what
   `flutter_secure_storage`/SQLite3MultipleCiphers already use for at-rest
   encryption — standard iOS/HTTPS crypto exemption almost certainly
   applies, but the actual questionnaire is an App Store Connect action, not
   a code one).
6. For TestFlight upload via the existing `Upload IPA to TestFlight` step:
   create an App Store Connect API key, set `ASC_API_KEY_ID`,
   `ASC_ISSUER_ID`, `ASC_API_PRIVATE_KEY_BASE64`.

## 2. Google Sign-In on iOS (needs prerequisite A's team, not its cert)

Purely a Google Cloud Console + one-line code action — no Xcode capability
required, since it's ID-token exchange, not a redirect flow.

1. Google Cloud Console → Credentials → **Create OAuth client ID → iOS**,
   bundle id `com.sagnikdas.medicyn` (no SHA-1 — iOS clients aren't keyed on
   one).
2. Uncomment the pre-written `GIDClientID` / `CFBundleURLTypes` block in
   `ios/Runner/Info.plist` (it already documents the exact keys and the
   reversed-client-ID URL scheme format — see the comment there).
3. Pass the same client id as `--dart-define=GOOGLE_IOS_CLIENT_ID=...` at
   build time (covers `GoogleAuthConfig.iosClientId`, which `auth_service.dart`
   already branches on via `Platform.isIOS`).
4. **Do not** add the new iOS client id to Supabase's Web/Android "Client
   IDs" list unless Supabase's docs say iOS clients belong there too — verify
   against current Supabase Auth docs before changing that list, since an
   unnecessary entry there could weaken the audience check for the *other*
   platforms.
5. Manual test once built: sign in, confirm a Supabase session is created,
   confirm `profiles`/`care_links` behave identically to Android (should —
   `auth_service.dart` and `care_service.dart` have zero platform branches
   downstream of the token exchange).

## 3. Push Notifications delivery (code is done; this is the remaining setup)

1. Complete §1.2 (enable Push Notifications capability on the App ID) — the
   new CI step (`Match aps-environment to the distribution profile`) will
   then successfully read a real `aps-environment` from the profile instead
   of failing with its explicit guard message.
2. Firebase Console → Project Settings → Cloud Messaging → Apple app
   configuration → upload an **APNs Authentication Key** (preferred over a
   certificate — doesn't expire, covers all apps on the team). Needs
   prerequisite A.
3. Manual device test, in this order (each depends on the last actually
   working, so don't skip ahead if one fails):
   a. Foreground: sign in on two devices, link them, trigger a missed dose
      on the patient device, confirm the caregiver device shows the alert
      via `PushService._handleForeground` (calls
      `NotificationService.showCareAlert`, since Android/iOS both suppress
      the OS's own foreground banner by design here).
   b. Backgrounded: same test, caregiver app backgrounded not terminated —
      confirms the OS draws the FCM `notification` block directly.
   c. Terminated: same test, caregiver app force-quit — confirms APNs
      delivery reaches a fully-dead process, which is the one path
      `showTestReminder()`/local testing cannot substitute for.
   d. Silent re-arm: edit a schedule from the caregiver dashboard, confirm
      the patient device's alarms update **without opening the app** —
      exercises the `apns.payload.aps.content-available` fix from this
      session end-to-end, which nothing in this repo can verify without a
      real APNs round-trip.

## 4. Local-notification reliability on a physical device

Everything here is Blocked-on-hardware per `FEATURE_PARITY.md`, not
Blocked-on-code. Suggested device script, cheapest-to-most-expensive:

1. Install, grant notification permission, create one `daily` medicine,
   confirm it rings at the scheduled time with the app foregrounded.
2. Background the app (swipe to home, don't force-quit), confirm the same
   reminder rings on schedule.
3. **Force-quit the app**, confirm the reminder still rings — this is the
   single claim the whole notification system exists to make true, and nothing
   short of a real device can confirm it (a Simulator's local-notification
   delivery while "terminated" behaves differently from a real device's).
4. Change the device's timezone (Settings → General → Date & Time), confirm
   `retryTimezoneInitialization()` picks it up and the next `reconcile()`
   re-arms at the correct wall-clock time — this is exactly the class of bug
   `nextWallClockDay`'s doc comment describes fixing for Android; nothing in
   the iOS branches of `notification_service.dart` suggests it would behave
   differently, but it has never run on an iOS device.
5. Create 20+ reminders across several medicines (approaching but not
   exceeding the 60-slot iOS budget) and confirm `_availableReminderSlots()`
   degrades attempts-per-reminder rather than dropping schedules outright —
   this logic is exercised by nothing except manual creation, since it reads
   live `pendingNotificationRequests()` state no test harness fakes.
6. Reboot the device with reminders pending, confirm they still fire
   (iOS reschedules local notifications automatically; unlike Android there
   is no `BOOT_COMPLETED` receiver to write, but this should still be
   observed once, not merely assumed from platform documentation).
7. Answer a reminder from the lock screen via the `Taken`/`Snooze`
   notification actions (`_iosReminderCategoryId` category) — confirms
   `handleNotificationResponse`/`notificationTapBackground` fire correctly
   from the Darwin action path, which is structurally different from
   Android's `ActionBroadcastReceiver`.

## 5. Visual/accessibility QA (needs prerequisite C, device or Simulator)

Simulator can cover most of this without waiting on Apple Developer setup —
only §3/§4 above need a real device.

1. Every major screen in light mode, dark mode, and at 150% in-app text
   scale × the accessibility-large OS setting stacked (the same combined
   scale `MEDICYN.md`'s "Known gaps" section already flags a real bug for on
   Android — `ProfileMenuRow`'s hardcoded `maxLines: 3` — check whether the
   same widget is reachable from the iOS body and whether it has the same
   problem, since `medicyn_chrome.dart` is shared).
2. VoiceOver: enable it in Simulator (`Cmd+F5`), walk Today, Add-medicine,
   Care, Settings — confirm every interactive element has a label, the
   Taken/Snooze dialog reads sensibly, and focus order matches visual order
   on the iOS-specific `CustomScrollView` body (untested — this layout does
   not exist on Android, so nothing about Android VoiceOver/TalkBack parity
   transfers).
3. Reduce Motion: confirm `MedicynMotion`/`MedicynFadeIn` already respect it
   (`motion_test.dart` tests "fade-in is a no-op when animations are
   disabled" — check whether that test's flag is wired to the OS Reduce
   Motion setting on iOS specifically, or only to the app's own animation
   toggle).
4. Small phone (SE-class, 4.7") and largest current iPhone, both orientations
   if the app allows landscape (`Info.plist` declares landscape support on
   phone, not just iPad — confirm nothing actually breaks in landscape,
   since Android-first development means this may never have been tried).
5. iPad: `Info.plist` already has a distinct
   `UISupportedInterfaceOrientations~ipad` key allowing portrait-upside-down
   and both landscapes — decide deliberately whether iPad is supported
   (current `TARGETED_DEVICE_FAMILY = "1,2"` means yes, universal) or should
   be restricted to iPhone-only (`"1"`) if no one intends to test iPad
   layouts before launch. This is a product decision, not inferable safely —
   flagging rather than choosing.

## 6. App Store Connect listing

1. Branded App Icon artwork — updated 2026-09-11: the stock Flutter logo
   that was here is gone. All 15 `AppIcon.appiconset` sizes are regenerated
   from Medicyn's actual brand icon. Remaining gap: the source is only
   192×192, so the 1024×1024 App Store marketing slot is a ~5.3x upscale
   and will look soft at full size — still needs a properly produced
   1024×1024 master before actual submission.
2. Screenshots for required device sizes, App Store copy — outstanding per
   `MEDICYN.md`.
3. Privacy nutrition label (App Store's equivalent of Play's Data Safety
   form) — cross-reference against `compliance/pack/PLAY-DATA-SAFETY.md`,
   which already has the answers prepared for the Android equivalent; the
   underlying data-collection facts are the same app, so this should mostly
   be a format translation, not new research.
4. Age rating, App Store category, support URL (already live at
   `medicyn.doezly.com/support`).

## 7. Compliance re-read (owned by `compliance/COMPLIANCE.md`, not this doc)

Out of scope for this implementation pass, but flagged since it's a real
dependency: `MEDICYN.md` already notes the DPIA needs re-reading when
"the four flows change" and separately when the controller changed to
Doezly. Shipping iOS is exactly this kind of change (a new platform means
new device/OS-level data — APNs tokens are a new category alongside FCM
tokens) and should trigger that re-read before an iOS listing goes live, not
after.
