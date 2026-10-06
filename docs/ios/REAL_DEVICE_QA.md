# iOS Real-Device QA

None of this has been run against a physical iPhone — this session had no
device attached, only an iOS Simulator (18.3 runtime; the machine's 26.3
runtime cannot install the app at all right now, see `FEATURE_PARITY.md`'s
toolchain section). Treat every box below as unchecked until someone with a
signed build and a device actually works through it. For the first local
reminder pass, run directly from Xcode or Android Studio; TestFlight is not
required. Caregiver push tests need the Apple/Firebase setup in
`IMPLEMENTATION_PLAN.md` §1-§3.

## First run on a borrowed iPhone

The phone owner can keep their own Apple Account on the phone. Sign in with
**your** Apple Account in Xcode on **your Mac**, never on the borrowed phone.
Ask the owner to approve the phone's trust, passcode, and Developer Mode
prompts. Bring a USB cable and a phone running iOS 15.5 or newer (this
project's deployment target); make sure your Xcode supports its iOS version.

1. Connect the unlocked iPhone to the Mac by USB. On the phone, tap **Trust**
   when asked whether to trust this computer and enter its passcode.
2. On the phone, open **Settings → Privacy & Security → Developer Mode**, turn
   it on, and follow the restart and confirmation prompts. If Developer Mode
   is missing, open Xcode with the connected phone first, then check again.
3. On the Mac, open **Xcode → Settings → Accounts** and add your Apple Account.
   From the Flutter project directory (`app/`), open `ios/Runner.xcworkspace`
   in Xcode. Open the **workspace**, not `Runner.xcodeproj`.
4. In Xcode, select the **Runner** project, then the **Runner** target →
   **Signing & Capabilities**. Enable **Automatically manage signing** and
   choose your team. Select the connected iPhone as the run destination. Xcode
   should create a development signing profile and register the phone when
   needed. If signing fails, record the exact error before changing the bundle
   ID or entitlements; this app declares `aps-environment` for remote push,
   which may require a paid Apple Developer Program team. Changing the bundle
   ID also affects this project's Google iOS sign-in configuration.
5. Open `app/` (the folder containing `pubspec.yaml`) as the Flutter project
   in Android Studio. Select the iPhone in the device selector and click
   **Run**. The first iOS build can take time. Terminal alternative from
   `app/`: run `flutter devices`, then `flutter run -d <device-id>`. If the
   phone asks you to trust the developer certificate after installation,
   approve it under **Settings → General → VPN & Device Management**.
6. For the first smoke test, use Medicyn without signing in. Add a medicine
   manually, allow notifications, and schedule a reminder a few minutes
   ahead. Verify it arrives with the app open, then backgrounded. Schedule
   another one, swipe the app away, lock the phone, and verify the reminder
   still appears with **Taken/Snooze** actions. Continue with the checklist
   below, including a reboot test. For a force-quit test, run the installed
   app normally, with the debugger disconnected.

Local medicine reminders do **not** need APNs or TestFlight. Google Sign-In
needs the iOS OAuth client and URL scheme described in `IMPLEMENTATION_PLAN.md`
§2; caregiver push alerts additionally need the Push Notifications capability
and an APNs key uploaded to Firebase (§3). A free Xcode Personal Team may
allow basic on-device testing, but may not sign this app while its push
entitlement is present. TestFlight requires paid Apple Developer Program
membership; testers use their own Apple Accounts and do not need Developer
Mode.

References: [Flutter iOS setup](https://docs.flutter.dev/platform-integration/ios/setup),
[Flutter iOS signing](https://docs.flutter.dev/deployment/ios),
[Apple Developer Mode](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device),
[Apple TestFlight](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/).

## Setup

- [ ] Fresh install (device has never had Medicyn before)
- [ ] Upgrade install (device has a prior Medicyn version, if one ever ships)
- [ ] Confirm `flutter build ios --release --no-codesign` output matches what
      TestFlight actually distributes — build locally and compare app size /
      version as a sanity check before trusting a TestFlight build for the
      rest of this list

## Feature-by-feature acceptance

This section is the test partner to the current [implemented feature
inventory](../../FEATURES.md). Check each feature on a **physical iPhone**;
code, Simulator, and Android results do not tick these boxes. Use synthetic
medicine and identity data. Tests that need cloud, a second phone, Google iOS
OAuth, or APNs say so explicitly. Record device model, iOS version, app build,
result, and failure evidence for each run. The sections after this one probe
permissions, lifecycle, and edge cases in more depth.

<a id="qa-f01"></a>
### F01 — Local-first onboarding ([feature](../../FEATURES.md#f01))

- [ ] On a fresh install, finish onboarding without Google sign-in. Add a
      manual medicine and return to it after closing and reopening the app.
- [ ] Turn on airplane mode before opening the app again. Confirm the local
      medicine and its scheduled reminder remain usable.

<a id="qa-f02"></a>
### F02 — Manual medicine entry and review ([feature](../../FEATURES.md#f02))

- [ ] Add a medicine manually with name, strength, dose, notes, time, and
      optional remaining tablets. Confirm every value on the review form
      before Save, then reopen the saved medicine in Plan.
- [ ] Edit its dose or time and confirm the old time is no longer shown as
      the next reminder. Try invalid or missing required fields and confirm
      the form blocks an incomplete schedule.

<a id="qa-f03"></a>
### F03 — Medicine-label scan ([feature](../../FEATURES.md#f03))

- [ ] Allow camera access, photograph a sample label, and confirm readable
      text reaches the review form. Correct an intentionally wrong suggestion
      before saving; confirm the corrected value is what Plan shows.
- [ ] Cancel before Save and confirm no medicine was added. Repeat after
      denying camera access and confirm a useful Settings recovery path.

<a id="qa-f04"></a>
### F04 — Spoken medicine entry ([feature](../../FEATURES.md#f04))

- [ ] Allow microphone and speech access, speak a medicine and schedule,
      inspect the transcript and suggested fields, edit a field, and save.
- [ ] Deny speech or microphone access and confirm a clear manual-entry
      fallback. Repeat with no network and confirm a clear failure or fallback
      rather than an indefinite loading state.

<a id="qa-f05"></a>
### F05 — Prescription photo and PDF capture ([feature](../../FEATURES.md#f05))

- [ ] Scan a synthetic prescription containing two medicines and one dated
      care item. Confirm separate editable review rows, remove or correct one
      suggestion, and verify only approved items are saved.
- [ ] Import a multipage prescription PDF through the iOS document picker.
      Check page extraction, review, and saved reminders; cancel without
      saving and confirm nothing new appears in Plan or Today.
- [ ] On parse failure or declined AI consent, confirm retry and manual
      medicine/care entry remain available. Record whether the hosted
      `parse-prescription` function was reachable for this build.

<a id="qa-f06"></a>
### F06 — Flexible medicine schedules ([feature](../../FEATURES.md#f06))

- [ ] Create one daily, one selected-weekday, and one every-X-hours medicine.
      Confirm their next occurrences match the entered local times.
- [ ] Edit the weekday or interval, then change the phone timezone and
      foreground the app. Confirm future wall-clock times update correctly
      without duplicate or dropped doses.

<a id="qa-f07"></a>
### F07 — Local reminder delivery and actions ([feature](../../FEATURES.md#f07))

- [ ] With notification permission allowed, verify a short reminder arrives
      with the app foregrounded, backgrounded, and force-quit; repeat while
      locked, offline, and after reboot without reopening the app.
- [ ] Tap **Taken** and **Snooze** from lock-screen notifications. Confirm
      the dose log and next reminder reflect each action, including the
      selected snooze duration. Keep the debugger disconnected for the
      force-quit test.

<a id="qa-f08"></a>
### F08 — Today, calendar, and medicine plan ([feature](../../FEATURES.md#f08))

- [ ] With at least two medicines, compare Today and Plan against the saved
      schedules. Navigate to yesterday and tomorrow on the calendar and
      confirm due/taken/missed status follows the selected date.
- [ ] Mark a dose Taken, return to Today, and confirm the card and calendar
      update without duplicating or losing the occurrence.

<a id="qa-f09"></a>
### F09 — Dose history and corrections ([feature](../../FEATURES.md#f09))

- [ ] Record a Taken and a Snoozed event, open dose history, and verify
      medicine, due time, response, and ordering.
- [ ] Add a correction/dispute note to a logged dose, leave and reopen the
      screen, and confirm the note persists. With a linked caregiver, confirm
      the correction syncs and is attributed correctly.

<a id="qa-f10"></a>
### F10 — As-needed medicine logging ([feature](../../FEATURES.md#f10))

- [ ] Save an As needed medicine. Confirm it has no scheduled Today alarm and
      shows **Log now** in Plan.
- [ ] Tap **Log now** once and verify one dose-history entry and the expected
      tablet-count decrease, if a count was entered.

<a id="qa-f11"></a>
### F11 — Pause, resume, complete, and restart ([feature](../../FEATURES.md#f11))

- [ ] Pause an active reminder until tomorrow and then indefinitely; check
      its status and that no paused alarm fires. Resume and verify a new
      future alarm is armed.
- [ ] Mark a course complete, verify history remains and future alarms stop,
      then restart it and confirm the next alarm returns. Exercise **Stop
      reminding me** separately from permanent delete.

<a id="qa-f12"></a>
### F12 — Refill tracking ([feature](../../FEATURES.md#f12))

- [ ] Enter a small tablet count, mark a dose Taken, and confirm the estimate
      decreases and a warning appears at five days of supply or less.
- [ ] Edit the count and confirm the warning updates. Check that no pharmacy
      or ordering action is required to use refill tracking.

<a id="qa-f13"></a>
### F13 — Other care reminders ([feature](../../FEATURES.md#f13))

- [ ] With a signed-in test account, add a test, scan, therapy, appointment,
      and other item. Enter a date, optional location/notes, and lead time;
      confirm they appear on the right day in Today and can be edited.
- [ ] Complete one item and sync to a second device. Confirm its status is
      consistent there; check the sign-in message when trying the flow in
      local-only mode.

<a id="qa-f14"></a>
### F14 — Reminder reliability checks ([feature](../../FEATURES.md#f14))

- [ ] Open **Settings → Check reminder access** after saving a reminder.
      Confirm notification permission, next reminder, and armed status match
      the phone; send a test reminder.
- [ ] Deny then restore notification access in iOS Settings. Confirm the app
      shows an actionable problem and clears it after permission is restored.

<a id="qa-f15"></a>
### F15 — Google sign-in and sign-out ([feature](../../FEATURES.md#f15))

- [ ] After configuring the iOS OAuth client and URL scheme, sign in with a
      test Google account. Confirm the account appears in Settings and the
      app returns correctly from Google's account picker.
- [ ] Sign out, then sign in as a different test account on the same phone.
      Confirm the second account cannot see the first account's medicine or
      care data.

<a id="qa-f16"></a>
### F16 — Optional cloud backup and sync ([feature](../../FEATURES.md#f16))

- [ ] With backup consent and two test devices, add and edit a medicine;
      confirm the other device receives the current values and Settings
      reports a completed sync.
- [ ] Go offline, edit again, check pending/error backup status, reconnect,
      retry if offered, and confirm the change arrives once. Turn off backup
      and verify local reminders remain usable.

<a id="qa-f17"></a>
### F17 — One-to-one family connection ([feature](../../FEATURES.md#f17))

- [ ] With patient and caregiver test accounts on two phones, generate an
      invite, enter it on the second phone, verify the identities, confirm the
      link, and check both sides show the connection.
- [ ] While the link is active, check that linking a second
      caregiver/parent is rejected under the current one-to-one model. Then
      disconnect and confirm family data is no longer exposed to the former
      caregiver.

<a id="qa-f18"></a>
### F18 — Caregiver dose feed ([feature](../../FEATURES.md#f18))

- [ ] On the patient's phone, mark a dose Taken, Snoozed, and allow another
      to become missed. Confirm the caregiver feed shows each state and the
      correct medicine and times after sync.
- [ ] Open **Their reminders** on the caregiver phone; compare it with the
      patient's Plan. Confirm the caregiver phone does not arm the patient's
      medicine alarms.

<a id="qa-f19"></a>
### F19 — Missed-dose and refill alerts ([feature](../../FEATURES.md#f19))

- [ ] After enabling Push Notifications on the Apple App ID and uploading an
      APNs key to Firebase, trigger a missed dose and confirm the caregiver
      receives an alert foregrounded, backgrounded, and with the app closed.
- [ ] Trigger a low-refill alert and check the correct destination on tap.
      Verify notification text does not reveal medicine details unexpectedly.

<a id="qa-f20"></a>
### F20 — Caregiver edits and change history ([feature](../../FEATURES.md#f20))

- [ ] Edit the patient's reminder from the caregiver phone. Confirm the
      patient's phone receives the change, re-arms the new time, and shows
      attribution in change history; check **Pending** changes to
      **Delivered** after a successful patient sync.
- [ ] Inspect the caregiver setup-health panel after notification access is
      disabled on the patient phone. Confirm the caregiver can edit but cannot
      delete the patient's medicine.

<a id="qa-f21"></a>
### F21 — Call the linked person ([feature](../../FEATURES.md#f21))

- [ ] Add a test contact number and tap **Call them** in Family. Confirm the
      iPhone dialer opens with that number; cancel before placing a call.
- [ ] From a missed-dose alert, use its call action and verify the same
      number. Check the missing-number state does not dial an unrelated
      contact.

<a id="qa-f22"></a>
### F22 — Weekly adherence insights ([feature](../../FEATURES.md#f22))

- [ ] With known Taken and missed sample doses across a week, compare the
      Insights summary, streak, and time-of-day pattern with dose history.
- [ ] Check the empty state before any doses exist and refresh after logging
      a dose; numbers should change without a restart.

<a id="qa-f23"></a>
### F23 — Four-week doctor report ([feature](../../FEATURES.md#f23))

- [ ] From Settings or Insights, select **Share with my doctor**. Open the
      generated PDF in the iOS share/preview flow and compare medicines and
      marked doses with the last four weeks of app history.
- [ ] Check a name with punctuation and a longer note for readable layout;
      confirm cancelling the share sheet leaves app data untouched.

<a id="qa-f24"></a>
### F24 — Emergency card ([feature](../../FEATURES.md#f24))

- [ ] Enter blood group, allergies, conditions, medicines, and a test contact
      from Profile. Reopen the card and confirm all fields persist locally.
- [ ] Open its call action, cancel before dialing, and preview the printable
      PDF through **Print or share**. Confirm the card does not appear on the
      linked caregiver phone through normal sync.

<a id="qa-f25"></a>
### F25 — Consent and private notifications ([feature](../../FEATURES.md#f25))

- [ ] Review optional consent choices in Settings. Decline an optional
      purpose and confirm its feature handles that choice without blocking
      local reminders; grant it and verify the relevant flow can proceed.
- [ ] With the phone locked, check default notification copy hides medicine
      names. Enable **Lock screen medicine names**, repeat, then turn it off.

<a id="qa-f26"></a>
### F26 — Data export and account deletion ([feature](../../FEATURES.md#f26))

- [ ] Choose **Download my data** using a test account with medicine, dose,
      care, and emergency-card records. Open the export and verify the data
      and any remote-fetch gap indicator are understandable.
- [ ] With a disposable test account only, complete the in-app deletion
      confirmations. Confirm the account is removed, the app returns to a
      usable local state, and the former caregiver cannot access deleted
      linked data.

<a id="qa-f27"></a>
### F27 — Display and accessibility settings ([feature](../../FEATURES.md#f27))

- [ ] Switch light/dark/system theme, increase iOS Dynamic Type and Medicyn's
      text-size slider, and inspect Today, Add, Plan, Family, Insights, and
      Settings for clipped text or inaccessible controls.
- [ ] Use VoiceOver and Reduce Motion on the same primary flows. Change the
      phone locale and confirm calendar, history, and PDF dates follow it.

## Permissions

- [ ] Camera: allow, then scan a real label
- [ ] Camera: deny, confirm the "turn it on in Settings" copy in
      `ocr_capture_screen.dart` actually appears and the Settings deep-link
      (`permission_handler`'s `openAppSettings()`) opens the right screen
- [ ] Microphone + Speech Recognition: allow, then speak a dosage
- [ ] Microphone + Speech Recognition: deny, confirm graceful fallback to
      manual entry
- [ ] Notifications: allow at first prompt
- [ ] Notifications: deny at first prompt, then re-enable from Settings —
      confirm `ReminderHealthStore`/`reminder_reliability_screen.dart`
      detects the change on next foreground and the health banner clears
- [ ] Push (background alerts): confirm the caregiver consent flow only
      requests this after explicit care-share consent (`consentCareShare`),
      not at first launch

## Connectivity

- [ ] Airplane mode at first launch — confirm local-only mode still lets you
      scan/save/get reminders (the core "offline, no account" promise)
- [ ] Airplane mode after signing in — confirm sync queues and catches up
      when connectivity returns (`SyncStatusStore`)
- [ ] Intermittent connectivity during a caregiver push round-trip — confirm
      no duplicate alerts and no lost missed-dose report

## App lifecycle (the core reliability claim)

- [ ] Reminder rings with app foregrounded
- [ ] Reminder rings with app backgrounded (not terminated)
- [ ] **Reminder rings with app force-quit** — this is the one behavior the
      whole notification architecture exists to guarantee; confirm it
      before trusting anything else in this list
- [ ] Reminder rings after a device reboot with the app never reopened
- [ ] Device locked when a reminder fires — confirm lock-screen copy matches
      the `showMedicineOnLockScreen` setting (redacted vs. named)
- [ ] Answer Taken/Snooze from the lock screen notification actions
      (not by opening the app)
- [ ] Multiple reminders due back-to-back — confirm the 3-attempt re-ring
      budget and the 60-slot iOS pending-notification cap both behave
      (create enough medicines to approach, not necessarily hit, 60 pending
      requests, then check none silently vanished)

## Time

- [ ] Change device timezone with reminders pending, confirm next foreground
      re-arms at correct wall-clock time
- [ ] Daylight-saving transition (simulate by setting the clock across a
      known DST boundary if the test window doesn't naturally include one)

## Camera / OCR / voice

- [ ] Scan a real medicine label end-to-end: capture → OCR → review/edit →
      save, confirm extracted fields are editable before save
- [ ] Cancel mid-scan, confirm no orphaned camera session (background the
      app mid-permission-prompt, per the comment in `ocr_capture_screen.dart`
      about the resumed→inactive→resumed cycle — this exact sequence caused
      a real first-scan bug on Android and deserves the same check on iOS)
- [ ] Voice capture: speak a full dosage instruction, confirm transcript is
      editable, confirm cancel/retry both work
- [ ] Voice capture with no network — `speech_to_text`'s `onDevice` is
      `false` on both platforms today, so expect this to fail visibly rather
      than silently; confirm it fails with a clear message, not a hang

## Push notifications (caregiver side)

- [ ] Missed-dose alert: foreground, background, terminated (see
      `IMPLEMENTATION_PLAN.md` §3.3 for the dependency order)
- [ ] Silent `data_changed` re-arm after a remote schedule edit, app
      terminated on the receiving device — confirms this session's `apns`
      fix in `fcm.ts` actually delivers
- [ ] Refill-low alert
- [ ] Tap a push notification, confirm it opens the correct screen
      (`handleCareAlertTap`)
- [ ] Call action on a missed-dose alert opens the dialer with the right
      number

## Accessibility & display

- [ ] VoiceOver: full walk of Today, Add-medicine (all three capture
      methods), Care, Settings, Insights
- [ ] Dynamic Type at the largest accessibility size, combined with the
      in-app text-scale slider at max — check every screen for clipped or
      truncated text, not just the ones `MEDICYN.md` already flagged on
      Android
- [ ] Dark mode across every screen, including mid-flow (camera preview,
      dialogs, action sheets)
- [ ] Reduce Motion enabled — confirm fades/transitions shorten or disable
- [ ] Bold Text / Increased Contrast — not exercised by any test in this
      repo on either platform; spot-check Settings and Today

## Subscriptions / IAP
Not applicable — no purchase flow exists in the app on either platform as of
this session (confirmed by grep, not assumed). Remove this section's
"not applicable" note once F9/F10 monetization actually ships, and replace it
with real purchase/restore test cases at that point.

## Sign-out / account

- [ ] Sign out, confirm push token is unregistered before the session clears
      (`PushService.unregisterToken` must run before Supabase's session
      clears, per its own doc comment — worth confirming in practice, not
      just trusting the comment)
- [ ] Account deletion end-to-end
- [ ] Sign back in as a different Google account on the same device, confirm
      no data from the previous account leaks (each account's Drift database
      is `medicyn-<userId>.sqlite`, so this should be clean by construction —
      confirm it actually is)
