# iOS Real-Device QA

None of this has been run against a physical iPhone — this session had no
device attached, only an iOS Simulator (18.3 runtime; the machine's 26.3
runtime cannot install the app at all right now, see `FEATURE_PARITY.md`'s
toolchain section). Treat every box below as unchecked until someone with a
signed build and a device actually works through it. Written as a script one
person can run in an afternoon once TestFlight access exists
(`IMPLEMENTATION_PLAN.md` §1-§3 first).

## Setup

- [ ] Fresh install (device has never had Medicyn before)
- [ ] Upgrade install (device has a prior Medicyn version, if one ever ships)
- [ ] Confirm `flutter build ios --release --no-codesign` output matches what
      TestFlight actually distributes — build locally and compare app size /
      version as a sanity check before trusting a TestFlight build for the
      rest of this list

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
