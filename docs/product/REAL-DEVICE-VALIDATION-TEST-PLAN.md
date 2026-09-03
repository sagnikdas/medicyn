# Medicyn real-device validation plan

**Status:** Canonical manual acceptance checklist  
**Build scope:** Current Android build on codex-master  
**Last reviewed:** 29 August 2026  
**Purpose:** Validate behavior that Flutter and backend tests cannot prove: Android permissions, alarms, notification rendering, reboot behavior, FCM delivery, account switching, device security, and real user flows.

This document consolidates the repository's manual acceptance plan, README device checks, launch audit gates, and behaviors covered by app/test. Follow it for every release candidate. A test is not passed merely because a unit or widget test passes.

## 1. Sign-off rules

Use these result values:

- **Pass:** expected behavior observed and evidence attached.
- **Fail:** behavior differs from the expected result, even if there is a workaround.
- **Blocked:** the test could not run because a documented external prerequisite was unavailable.
- **N/A:** intentionally outside this build's feature scope. Explain why.

Do not use real patient information, real medicine labels, personal phone numbers, or production caregiver accounts. Use disposable accounts and synthetic data.

The release candidate cannot be approved if any of these fail:

- A saved active reminder does not fire, or the app claims it is active when it is not.
- A timezone, permission, reboot, or schedule-edit failure silently changes or loses a reminder.
- Account A's data, consent, push events, or notifications appear after switching to Account B.
- A care alert exposes medicine details on a locked screen or reaches the wrong account.
- A dose action records the wrong dose, duplicates a dose, or cannot be recovered.
- The signed build cannot authenticate, receive required push messages, or preserve data across upgrade.

## 2. Test record

Copy this block into the test report before starting:

    Run ID:
    Tester:
    Date/time and timezone:
    Git commit:
    Version name/code:
    Build type: debug / profile / signed release / Play internal
    APK/AAB source:
    Supabase project/ref:
    Migrations/functions revision:
    Firebase project:

    Patient device:
      manufacturer/model:
      Android version/API:
      security patch:
      OEM battery mode:
      Google Play services version:
    Caregiver/second device:
      manufacturer/model:
      Android version/API:
    Second same-account device, if used:
      manufacturer/model:
      Android version/API:

    Network conditions exercised:
    Notification permission state at start:
    Exact-alarm access state at start:
    Screen lock configured: yes / no
    Do Not Disturb: off / exception documented
    Result summary:
    Known failures/blockers:
    Evidence folder/link:

For every case, record the test ID, result, timestamps, device, test data, and a screenshot or screen recording for failures. For notification tests, record scheduled time, actual arrival time, lock state, and whether the app was alive, backgrounded, force-stopped, or rebooted.

## 3. Required setup

### 3.1 Software and service preflight

Run from the repository before installing the candidate:

    cd /Users/sagnikdas/research/medicyn/app
    flutter analyze
    flutter test

Expected result: analyzer has no issues and all Flutter tests pass. The current baseline is 454 tests.

If backend behavior is in scope, run the root test command and confirm the hosted project has the migrations required by the candidate:

    cd /Users/sagnikdas/research/medicyn
    ./scripts/test_all.sh

Before two-device care tests, confirm:

- device_tokens, care_links, care_alerts, profiles, consent, and lifecycle migrations are applied to the test Supabase project;
- notify-care is deployed with the matching Firebase project and service account;
- google-services.json belongs to this Medicyn Firebase project;
- the build's Google OAuth client is registered for the signing certificate being tested;
- test accounts are allowed by Google's OAuth consent-screen test-user configuration if the app is still in Testing mode.

For a release test, use the signed AAB installed through Google Play Internal testing when possible. A sideloaded debug APK does not prove release signing, Play App Signing, release OAuth, or Play-delivered behavior.

### 3.2 Devices and fixtures

Prepare:

- **Device P:** patient/primary reminder device.
- **Device C:** caregiver device.
- **Device P2:** second device signed into the same account as Device P.
- **Account A** and **Account B:** two disposable Google accounts for account-isolation tests.
- A synthetic medicine such as Test Medicine, 650 mg, 1 tablet.
- A daily reminder two to five minutes in the future for alarm tests.
- A second reminder at a different time for edit and multi-card tests.
- A label image containing synthetic patient name, address, date of birth, Rx number, email, and phone text.
- A test phone number that opens the dialer but does not call a real person.

Keep automatic date/time and the device's real timezone enabled except when deliberately testing timezone changes. Turn off Do Not Disturb, silent mode, battery saver, and data saver for the baseline run. Later suites deliberately change those states.

## 4. Suite A — install, startup, account and local security

### RD-A01 — Fresh install and first launch

1. Install the candidate on a clean device or clear only the test app's data.
2. Launch Medicyn and complete onboarding.

Expected:

- The app opens without a crash or blank screen.
- Onboarding explains offline reminders and that data leaves the phone only when chosen.
- The user reaches the add flow without being forced to sign in.
- No camera, microphone, notification, exact-alarm, or battery settings prompt appears before its relevant action.

### RD-A02 — Local-only first medicine

1. Choose local-only mode.
2. Add the synthetic medicine and a reminder.
3. Close and reopen the app.

Expected:

- The medicine and schedule remain available without an account or network.
- The local reminder is usable.
- The app does not attempt cloud sync, AI parsing, speech processing, care sharing, or push registration without consent.
- Settings identifies backup/family features as unavailable until sign-in and consent.

### RD-A03 — Account A/B data and consent isolation

1. Sign in as Account A and create a clearly named synthetic medicine.
2. Grant only the consents needed for the test and note the choices.
3. Sign out.
4. Sign in as Account B on the same phone.

Expected:

- B sees a separate local database and does not see A's medicine, schedules, history, care link, sync state, or consent choices.
- B's processing choices start off unless B explicitly grants them.
- No A sync, AI, speech, care, or push operation runs during B's session.

5. Sign out B and sign in A again.

Expected: A's data and only A's choices return.

### RD-A04 — Local-only to first-account handoff

1. Add a synthetic medicine in local-only mode and record its local consent choices.
2. Sign in as a new account for the first time.
3. Observe the handoff prompt.

Expected:

- The user is asked whether the local choices should follow the first account.
- The local database is adopted only for that first account when confirmed.
- A different existing account never inherits the local choices or local database.

### RD-A05 — Sign-out cleanup and push listener isolation

1. Sign in as A, enable care sharing, and leave the app backgrounded.
2. Sign out and sign in as B.
3. Trigger an A care event and a B care event if the test pair is configured.

Expected:

- A's token/listeners are detached before the session changes.
- A's notification, navigation, feed, and data do not appear in B's session.
- B receives only B-authorized events.

### RD-A06 — Device lock and re-unlock

Run once on a device with a PIN/pattern/biometric and once on a device without a screen lock.

1. Open Medicyn, background it briefly, and return.
2. Leave it in the background beyond the configured grace period and return.

Expected:

- A cold start does not show an unnecessary lock screen.
- A short absence does not lock the app.
- A protected device asks for the device credential after the grace period.
- A device without a screen lock remains usable rather than trapping the user.
- Unlocking returns to the correct screen without losing pending work.

### RD-A07 — Upgrade and local database preservation

1. Install the previous test build and create a medicine, schedule, dose response, and history entry.
2. Install the candidate over it without clearing data.
3. Open Home, Plan, History, and Settings.

Expected:

- The app opens and migration completes without a crash.
- Medicines, schedules, stock, dose history, consents, and settings remain correct.
- Existing alarms are reconciled rather than silently discarded.
- Android backup/device-to-device transfer remains disabled for the protected database.

## 5. Suite B — activation, capture, review and permissions

### RD-B01 — Add method chooser and manual entry

1. From a fresh local-only session, tap Add medicine.
2. Inspect the choices.
3. Select Enter manually.

Expected:

- The choices are Scan label, Speak details, and Enter manually.
- Camera and microphone permission prompts do not appear for manual entry.
- The user can enter name, strength, dose, frequency, and time, review them, and save locally.

### RD-B02 — Camera permission and rear-camera capture

1. Revoke camera permission in Android Settings.
2. Select Scan label.
3. Grant permission only when requested.
4. Confirm the preview uses the rear camera.
5. Scan the synthetic label.

Expected:

- No camera prompt appears before Scan is selected.
- The rear camera is selected when available.
- Successful OCR opens the review form.
- The review form requires confirmation before save.

6. Repeat with camera permission denied and with an unreadable label.

Expected: the flow offers a friendly retry/manual path and does not strand the user or show a raw exception.

### RD-B03 — Speech permission and recovery

1. Revoke microphone permission.
2. Select Speak details.
3. Grant permission and speak synthetic dosage directions.

Expected:

- No microphone prompt appears before Speak is selected.
- The transcript is presented for review, not silently saved.
- The screen explains that platform speech recognition may process audio outside the device.

4. Deny permission or speak unintelligibly.

Expected: a retry/manual path appears and no incomplete reminder is saved.

### RD-B04 — OCR redaction and parser consent gate

1. Use the synthetic label containing identity and contact fields.
2. With Anthropic parsing consent off, complete capture.

Expected: no parse-medicine request is made; the user can continue manually.

3. Grant Anthropic parsing consent and retry parsing.

Expected:

- The review form can use the medicine/directions text.
- Synthetic name, address, date of birth, Rx number, email, and phone values are not sent as parser input. Validate through a safe test proxy/logging fixture if available; do not inspect production logs containing health data.
- Malformed or low-confidence extraction is editable/reviewable, never an unquestioned save.

### RD-B05 — Review form validation

1. Leave the medicine name, amount, frequency, or required time invalid or empty.
2. Attempt to save.

Expected: the form identifies the invalid field and does not create an unusable schedule.

3. Correct the values and save.

Expected: saved values match the reviewed values and the next reminder is visible.

### RD-B06 — Contextual notification permission

1. Revoke Medicyn notification permission in Android Settings.
2. Open Home and browse the app.

Expected: no notification prompt appears merely from opening Home.

3. Save the first scheduled reminder.

Expected: notification explanation/prompt appears at Save.

4. Deny it.

Expected: the medicine remains saved, but Home/Reminder reliability clearly shows notifications are off and provides a recovery action.

### RD-B07 — Exact-alarm degraded path

1. Open Settings → Reminder reliability.
2. Disable exact-alarm access or decline the request.
3. Refresh the screen.

Expected:

- The app distinguishes exact timing from inexact fallback.
- It never claims an exact alarm is active when access is unavailable.
- It does not substitute UTC or silently move the reminder.
- The screen explains how to improve timing or that Android may delay delivery.

4. Re-enable exact-alarm access, return to Medicyn, and tap Check again.

Expected: permission and schedule health update without requiring a reinstall.

### RD-B08 — Consent withdrawal

1. Grant cloud backup, speech, parser, and care sharing one at a time.
2. Confirm each feature works only after its consent.
3. Withdraw each consent in Settings.

Expected:

- The local toggle persists.
- Subsequent operations stop using that external service.
- Withdrawing care sharing revokes the live care link and unregisters the push token.
- Withdrawing cloud backup leaves local reminders usable.

## 6. Suite C — reminder delivery and notification actions

Use a reminder two to five minutes ahead. For every case, record scheduled time versus arrival time and the app process state.

### RD-C01 — Reminder reliability baseline and test notification

1. Open Settings → Reminder reliability.
2. Confirm the screen shows notification state, exact-alarm state, timezone state, schedule status, armed state, and last check.
3. Tap Send a test reminder.

Expected:

- The test notification arrives.
- The screen does not claim a schedule is active if an active schedule is unarmed.
- Check again, Enable, Improve timing, Retry, and Android settings actions work as applicable.

### RD-C02 — Normal background delivery

1. Create a scheduled reminder.
2. Put Medicyn in the background without force-stopping it.
3. Lock the phone and wait.

Expected: the reminder arrives at the intended local wall-clock time, with configured sound/vibration and heads-up behavior.

### RD-C03 — Lock-screen privacy

1. Keep Show medicine on lock screen disabled.
2. Wait for a patient reminder while the phone is locked.

Expected: the lock screen shows generic reminder copy and does not expose medicine name, strength, or dose.

3. Opt in to showing medicine on the lock screen and repeat.

Expected: only the patient's own reminder changes to named copy; the setting is explicit and reversible.

### RD-C04 — Patient notification actions

1. Trigger a reminder.
2. Tap Taken from the notification.
3. Open Medicyn and inspect Today/History.

Expected: exactly one dose is recorded for the scheduled occurrence, the attention card resolves, stock decrements once when tracking is enabled, and the alarm does not reappear for the same occurrence.

4. Trigger another reminder and tap Snooze.

Expected:

- The notification/prompt closes immediately.
- The dose is not falsely marked taken or missed while snooze is live.
- A one-off reminder returns at the configured duration.
- Repeated taps do not create duplicate dose logs or stacked snoozes.

5. Set snooze to 5, 10, 20, and 30 minutes in Settings and repeat once for each value.

### RD-C05 — Notification body tap and cold-start action

1. Force-stop Medicyn.
2. Trigger a reminder and tap the notification body, not an action button.

Expected: the app cold-starts and opens the correct Taken/Snooze confirmation after the app is ready.

3. Repeat the same tap by launching Medicyn normally afterward.

Expected: the old launch is not replayed indefinitely. A different notification opens, and the same daily slot can open again on the next civil day.

### RD-C06 — Attention deck and missed-dose handling

1. Create at least three reminders due close together, or use one due and one previously missed test dose.
2. Open Today.

Expected:

- The front attention card is interactive.
- Preview cards are secondary and are not independently actionable.
- Taken removes the front card and reveals the next.
- Snooze is unavailable for statuses that cannot be snoozed.
- Yesterday's missed dose remains answerable where the product allows it.

### RD-C07 — Reboot resilience

1. Create a reminder five minutes in the future.
2. Reboot the device.
3. Do not open Medicyn after reboot.
4. Wait for the reminder.

Expected: the alarm survives reboot and fires, or the app later shows an explicit degraded/fix state. It must not silently disappear.

5. Open Medicyn after the test and inspect Reminder reliability.

### RD-C08 — App update and process death

1. Schedule a future reminder.
2. Force-stop the app, then install the candidate/update if this is an upgrade test.
3. Do not open the app until after the scheduled time.

Expected: boot/update receivers and reconciliation preserve the intended alarm. A process death during normal use does not leave the UI claiming success while the schedule is unarmed.

### RD-C09 — Edit replaces the old alarm

1. Create a reminder at time T1.
2. Edit it to T2, both in the future.
3. Wait through T1 and T2.

Expected: T1 does not fire; T2 fires once. The old alarm is cancelled and the new schedule is visible in health status.

### RD-C10 — Timezone and wall-clock changes

1. Create a reminder in the current timezone.
2. Change the device timezone to another valid timezone and foreground Medicyn.
3. Confirm the displayed schedule and next alarm.

Expected: the app reconciles using the new local timezone and does not silently use UTC.

4. If safe for the test device, exercise a DST-transition timezone using a test clock/device configuration or a scheduled transition window.

Expected: a daily wall-clock reminder stays at the same local hour across the transition; no duplicate or one-hour-shifted alarm appears.

5. Restore automatic timezone and verify again.

### RD-C11 — Invalid or unavailable scheduling state

Use a test build/fixture that can supply an invalid timezone or malformed schedule, if available.

Expected:

- The schedule is not armed using a guessed timezone.
- Other healthy schedules continue to arm.
- Reminder reliability shows a recoverable error state.
- Retrying after the platform state is fixed succeeds.

## 7. Suite D — lifecycle, stock, history and insights

### RD-D01 — Active reminder and edit attribution

1. Create a reminder and edit it on the patient device.
2. If care is enabled, edit it from the caregiver device.

Expected: lifecycle state is clear, and the UI identifies whether the latest change was made by you or the other person with an understandable date.

### RD-D02 — Pause until tomorrow

1. Open an active reminder and choose Pause reminder → Until tomorrow.

Expected:

- Reminder shows paused with a pause window.
- No future alarm fires during the pause.
- Existing history remains visible.

2. Return after the window expires or move the test clock forward and foreground the app.

Expected: reconciliation makes the reminder eligible for arming again.

### RD-D03 — Pause for one week and indefinitely

Repeat pause with For one week and Indefinitely.

Expected: each state is displayed accurately, future alarms stop, and dose history is preserved. An indefinite pause does not become active until explicitly resumed.

### RD-D04 — Resume

1. Open a paused reminder and choose Resume reminder.

Expected: state returns to Active and a future alarm is armed. Verify in Reminder reliability and with a short test reminder.

### RD-D05 — Complete and restart

1. Mark an active course complete.

Expected: reminder is Completed, future alarms stop, and history remains available.

2. Choose Restart reminder.

Expected: it becomes Active and re-arms without deleting earlier history.

### RD-D06 — As-needed reminder

1. Create an As needed reminder.
2. Open Today, Plan, History, and Insights.

Expected:

- It is clearly identified as As needed.
- No scheduled alarm is created.
- It is not counted as an unanswered scheduled dose.
- If Log dose now is not present in this build, mark the test N/A and record it as a product gap rather than inventing a pass.

### RD-D07 — Dose history and corrections/contest path

1. Record Taken, Snoozed, Missed, and unanswered test occurrences.
2. Open History and inspect entries.
3. If correction/contest UI is present, add and edit a note on a dose.

Expected:

- The original dose action remains distinguishable from a note or correction.
- A note does not turn Taken into another action.
- The feed attributes unusual or other-device entries without cluttering normal reminders.

### RD-D08 — Stock and refill warning

1. Enable tracking with a synthetic starting count and tablets-per-dose.
2. Record Taken doses.

Expected: derived remaining count decrements by dose amount, never becomes negative, and does not decrement for Snoozed/Missed alone.

3. Test counts around the five-day warning threshold and an empty bottle.

Expected: warning appears at the intended threshold and says when no tablets remain. As-needed schedules do not produce a daily-rate warning.

### RD-D09 — Insights and calendar semantics

1. Build a small known history across morning, afternoon, and evening, including taken and missed doses.
2. Open Insights and the Today calendar.

Expected:

- Most consistent reflects the period with the best supported adherence, not always morning.
- Weekly totals and percentages match known history.
- A 100% day visibly reads 100%, not a clipped value.
- Calendar marks and dose statuses correspond to the selected date.
- History and chart labels remain understandable with large text and TalkBack.

### RD-D10 — Stop reminder versus delete history

1. Stop/deactivate a reminder.

Expected: future alarms stop and the medicine is not presented as active; existing history remains available.

2. Delete the medicine/history only in a disposable test account.

Expected: deletion is explicit, local history disappears as described, and later sync does not resurrect the deleted item.

## 8. Suite E — offline, sync and multi-device behavior

### RD-E01 — Backup status and offline recovery

1. Sign in and enable cloud backup.
2. Confirm Profile/Settings shows Backup On, last successful sync, pending work, and Retry where applicable.
3. Disable Wi-Fi and mobile data.
4. Edit a reminder and record a dose.

Expected: local changes succeed and the app remains usable. Pending sync is visible; the UI does not claim the change reached the server.

5. Restore connectivity and foreground Medicyn or tap Retry.

Expected: pending work clears after successful sync and the remote copy matches local state.

### RD-E02 — Fresh-device restore

1. Create and sync a medicine/schedule on Device P.
2. Install Medicyn on clean Device P2 and sign in as the same account.
3. Grant cloud-backup consent.

Expected: the first pull restores data before reconciliation, and P2 arms the restored active schedule during the same foreground pass.

### RD-E03 — Caregiver edit reaches patient alarm

1. Link Device P and Device C.
2. On Device C, edit the patient's reminder time or pause it.
3. Keep Device P backgrounded with network available.

Expected:

- Device C shows the edit and attribution.
- Device P receives the silent data-change message or applies it on the documented next-foreground fallback.
- Device P pulls the change and re-arms/cancels alarms accordingly.
- The caregiver's local copy does not itself arm the patient's reminder.

### RD-E04 — Last-write-wins conflict

1. Disconnect both same-account devices from the network.
2. Edit the same reminder differently on each device.
3. Reconnect and sync both devices in a known order.

Expected: the newer client-stamped edit wins, both devices converge after sync, and an older edit does not overwrite a newer one. The final alarm state matches the winning schedule.

### RD-E05 — Remote delete propagation

1. Create and sync a medicine on two devices.
2. Delete it on Device P.
3. Sync/foreground Device P2.

Expected: the item is not resurrected by stale remote data, its schedules stop arming, and deletion/history behavior matches the confirmation shown to the user.

### RD-E06 — Network interruption during sync

1. Start a sync with several pending changes.
2. Interrupt connectivity during the operation.
3. Restore connectivity and retry.

Expected: no indefinite spinner, partial failures remain retryable, one table failing does not silently discard unrelated changes, and eventual sync is idempotent.

## 9. Suite F — family care and FCM

These tests require deployed notify-care, Firebase configuration, two accounts, and two or three physical devices. Verify server state in the test project using device_tokens, care_links, and care_alerts; never paste tokens or real health data into the report.

### RD-F01 — Invite, claim and patient confirmation

1. On Device P, enable care sharing and create an invite.
2. Transfer the code to Account C using the intended code/read-aloud path.
3. Claim on Device C.
4. Confirm the named claimant on Device P.

Expected:

- Possession of the code alone does not activate access.
- The patient sees the claimant's name and email before confirmation.
- A missing name/email fails closed.
- Both devices show connected only after confirmation.

### RD-F02 — Invalid, expired, repeated and throttled invite

Exercise a wrong code, an expired code, repeated claims, and the documented attempt limit using disposable accounts.

Expected: the app gives a clear invalid/expired/throttled message, does not disclose another person's data, and does not create a partial live link.

### RD-F03 — Caregiver feed and attribution

1. With an active link, open the caregiver's feed.
2. Compare it with the patient's known dose history.
3. Edit a medicine from the caregiver device.

Expected:

- The caregiver sees only the linked patient's permitted data.
- Dose times, actions, punctuality, refill state, and editor attribution are correct.
- Caregiver edits sync to the patient but do not create local alarms on the caregiver phone.

### RD-F04 — Missed-dose alert

1. Create a short reminder on Device P and do not answer it beyond the grace period.
2. Ensure Device P has connectivity and the care link is active.

Expected:

- P records one missed dose.
- C receives one visible care alert with useful, non-clinical wording.
- The alert uses the care channel, not the looping patient-alarm channel.
- The alert does not contain medicine details on a locked caregiver phone.
- A taken or snoozed dose does not generate a missed-dose alert.

3. Foreground the patient again or repeat the sweep.

Expected: the same missed dose is not announced repeatedly; an alert lost to transient network failure remains eligible within the documented window.

### RD-F05 — Two devices, one account, one alert

1. Sign the same patient account into Device P and P2.
2. Link a caregiver and register both patient tokens.
3. Let one patient reminder become missed.

Expected: caregiver receives one alert, not one per patient device, and care_alerts has one row for the dose/link combination.

### RD-F06 — Silent-device alert

1. Configure the test account/link for silent-device detection.
2. Leave the patient device without opening Medicyn for the required threshold.
3. Observe the caregiver device and test project logs.

Expected: a silent-device alert is distinguishable from a missed-dose alert, does not expose medicine details, and is not sent when the patient device has recently checked in.

### RD-F07 — Low-refill alert and care call

1. Drive a synthetic medicine below the refill threshold.
2. Observe the caregiver alert and Care screen.

Expected: refill warning is distinct from a missed-dose alert and contains no unnecessary medicine detail on the lock screen.

3. Tap Call them using the synthetic number.

Expected: dialer opens with a sanitized dialable number; letters and unusably short numbers are rejected.

### RD-F08 — Care alert tap while alive and cold-started

1. With Device C unlocked and Medicyn alive/backgrounded, tap a care alert.

Expected: linked patient's feed opens after the app is ready.

2. Force-stop Medicyn on C, lock the phone, deliver another care alert, and tap it.

Expected:

- Alert remains private on lock screen.
- After unlocking and any device-credential check, the correct patient feed opens.
- The same launch is not replayed on a later ordinary app start.

### RD-F09 — Sign-out, handed-back phone and token ownership

1. On Device C, sign out of the caregiver account and sign in as another disposable account or the patient account.
2. Trigger an alert for the original caregiver account.

Expected: handed-back phone stays silent for the former account. Its token is moved/unregistered only according to the documented install-ownership flow, and the new account receives only its own authorized events.

### RD-F10 — Uninstall and stale token

1. Uninstall the caregiver app without first signing out.
2. Trigger a new alert from the patient device.
3. Inspect notify-care logs and device_tokens in the test project.

Expected: stale token is pruned when FCM reports it invalid; transient server errors do not cause a valid token to be deleted permanently.

### RD-F11 — Revoke/disconnect care link

1. Revoke the link from the authorized side.
2. Attempt to open the former patient's feed and alert history from the former caregiver account.
3. Trigger a new patient alert.

Expected:

- Former caregiver loses access after refresh/sync.
- No new alert is delivered to the revoked account.
- Patient retains their history and can create a new link through the documented flow.

## 10. Suite G — privacy, export, deletion and policy surfaces

### RD-G01 — In-app privacy policy

1. Open Privacy policy from sign-in and Settings.

Expected: bundled policy opens without requiring a private repository, and claims match the current build's actual processing, retention, speech, parser, FCM, backup, and deletion behavior.

### RD-G02 — Public privacy, deletion and support pages

From a browser where Medicyn is not installed or signed in, open the configured HTTPS Privacy, Delete account, and Support URLs.

Expected: each route is public, loads without repository access, explains the action and support path, and matches the URLs in app and Play materials.

### RD-G03 — Export completeness and temporary-file cleanup

1. Create synthetic medicine, schedule, stock, dose, consent, sync, and care records.
2. Export Medicyn data and inspect the shared JSON in a safe location.

Expected:

- Export identifies its schema version.
- It includes persisted fields the product promises, including schedule lifecycle and stock fields.
- It does not include encryption keys, refresh tokens, FCM tokens, raw credentials, or unintended secrets.
- Temporary plaintext export is removed after sharing where the platform permits verification.

### RD-G04 — Share diagnostics redaction

1. Create a permission/scheduling failure and an offline sync condition.
2. Use Share diagnostics if present.
3. Inspect the content before sharing.

Expected: it contains only app version, device/OEM/API, permission state, last arm result, and coarse sync state. It must not contain medicine names, dosage, OCR text, speech transcript, email, care codes, raw database IDs, or precise health timestamps.

### RD-G05 — Local storage and backup inspection

On a test device and test account only, inspect with approved Android debugging tools.

Expected:

- Medical database file is not a plaintext SQLite file.
- Supabase session material is not left in ordinary shared preferences after secure-storage migration.
- Android backup/device-transfer flags remain disabled.
- Account A and Account B encrypted databases are distinct.

Do not attach raw storage dumps to a ticket if they contain test secrets; retain only the minimum evidence needed.

### RD-G06 — Account deletion

1. Use a disposable signed-in account with synthetic data.
2. Start deletion from Settings and complete both confirmation steps.

Expected:

- App explains deletion is permanent and what happens to local/cloud/care data.
- Server deletion route completes or gives a clear recoverable error.
- Local account database, session, token, and account-specific state are removed as documented.
- A later sign-in does not restore deleted local data.

3. Repeat using the public web deletion route while the app is uninstalled, following its identity-verification instructions.

## 11. Suite H — accessibility, layout and presentation

Run on a small phone, a normal phone, and a tablet/foldable if available. Repeat critical flows with TalkBack.

### RD-H01 — Text scaling

1. Set Android system font/display size to the largest available value and at least 200% where supported.
2. Set Medicyn text scale to 100%, then 150%.
3. Exercise onboarding, add/review/save, Today, Plan, Insights, Settings, Reminder reliability, care, history, and deletion.

Expected: text reflows without clipped critical content, horizontal overflow, inaccessible buttons, or hidden confirmation actions. The app setting does not silently defeat Android system scale.

### RD-H02 — TalkBack and touch targets

With TalkBack enabled, traverse every critical screen.

Expected:

- Every action has a meaningful spoken label and state.
- Calendar cells, adherence bars, dose cards, health warnings, and permission states communicate their meaning.
- Taken, Snooze, Save, Retry, Enable, Delete, and navigation controls are reachable and predictable.
- Controls have comfortable touch areas, targeting at least 48dp.

### RD-H03 — Compact layouts and keyboard

1. Test a 320×568 or similarly small device.
2. Open the keyboard on review, manual entry, care code, phone, and Settings fields.
3. Rotate if the candidate supports rotation.

Expected: content remains reachable, keyboard does not hide the primary action, and no overflow/error banner appears.

### RD-H04 — Theme and reduced motion

1. Test System, Light, and Dark themes.
2. Enable Android reduced-motion/animation settings if available.

Expected: contrast remains readable, status colors are not the only signal, transitions do not block actions, and reduced motion does not leave an empty or frozen screen.

## 12. Suite I — release and device-matrix proof

### RD-I01 — Signed release authentication

1. Install the Play Internal-testing or signed release build.
2. Sign in with a test account.

Expected: native Google account picker works, correct release SHA is registered, no browser/deep-link flow is required, and cancellation is distinct from configuration/network failure.

### RD-I02 — Release notification smoke test

On the exact signed build, repeat RD-C01, RD-C02, RD-C04, RD-C07, and RD-C09.

Expected: release behavior matches debug/profile behavior for alarm scheduling, action buttons, reboot receivers, lock-screen privacy, and reconciliation.

### RD-I03 — OEM and Android coverage

Where available, run the minimum smoke set on:

- Pixel or AOSP device
- Samsung
- Motorola
- Xiaomi/Redmi
- Oppo/Realme
- Android API 24/7, 12, 13, 14, 15, and 16, prioritizing beta devices

At minimum, run install, sign-in/local-only, save reminder, notification permission denial/recovery, exact-alarm denial/recovery, background alarm, Taken/Snooze, reboot, lock-screen privacy, and app update.

Record OEM battery restrictions, notification-channel settings, and any manual exception required. An OEM-specific workaround must be shown to the user and documented before sign-off.

### RD-I04 — Play track installation

1. Install from the Play Internal/Closed testing track, not a sideloaded APK.
2. Confirm displayed version/build and update over the prior track build.
3. Repeat release smoke tests.

Expected: Google Sign-In, FCM, notification channels, database migration, and alarm behavior work from the Play-delivered artifact.

## 13. Final evidence bundle

Attach these items to the release record:

1. Candidate commit, version, signing/build source, and device matrix.
2. flutter analyze output and complete flutter test result.
3. Backend migration/function verification and relevant test-project query results.
4. Screenshots/video for notification delivery, Taken/Snooze, permission denial/recovery, reboot, edit replacement, lock-screen privacy, and reminder health.
5. Two-device evidence for invite/confirm, caregiver edit, silent data-change re-arm, missed-dose alert, cold-start tap, revocation, and account switching.
6. Export and diagnostics redaction evidence.
7. A result table with every ID marked Pass, Fail, Blocked, or N/A.
8. For every failure: reproduction steps, device/build, logs without health data, severity, owner, and retest result.

## 14. Coverage map

This plan was derived from these repository sources:

| Source | Device scenarios represented here |
|---|---|
| app/test/phase2_activation_test.dart, consent_test.dart, google_sign_in_errors_test.dart | onboarding, local-only, consent gates, account handoff, sign-in failure handling |
| app/test/encrypted_database_test.dart, secure_supabase_local_storage_test.dart, device_lock_test.dart | account database isolation, secure session storage, device-credential re-unlock, backup expectations |
| app/test/notification_launch_test.dart, snooze_and_alarm_test.dart, dose_attention_panel_test.dart | cold-start routing, Taken/Snooze, deduplication, attention deck, alarm responses |
| app/test/reminder_health_test.dart, schedule_validation_test.dart, expected_doses_test.dart, interval_dose_sequence_test.dart, missed_doses_test.dart | reminder health, malformed schedules, intervals, missed-dose boundaries, no silent fallback |
| app/test/lifecycle_test.dart, day_occurrences_test.dart, reminder_delete_test.dart | pause, resume, complete, active/as-needed behavior, delete/stop semantics |
| app/test/refill_test.dart, stock_derivation_test.dart, dose_feed_test.dart, dose_contest_test.dart | stock, refill warning, attribution, history and notes |
| app/test/sync_service_test.dart, sync_conflict_test.dart, remote_delete_propagation_test.dart | offline recovery, last-write-wins, tombstones, no resurrection |
| app/test/care_link_test.dart, care_parsing_test.dart, care_alert_tap_test.dart, push_alert_test.dart, push_contract_test.dart, push_background_consent_test.dart | invite/confirmation, care feed parsing, FCM event routing, alert dedupe, background consent loading |
| app/test/label_redactor_test.dart, data_export_test.dart, privacy_policy_test.dart, account_deletion_test.dart | privacy disclosures, OCR redaction, export, deletion URLs and behavior |
| app/test/responsive_layout_test.dart, insights_layout_test.dart, daily_progress_test.dart, dose_calendar_test.dart, theme_type_scale_test.dart, motion_test.dart | large text, compact layouts, calendar/chart semantics, themes, reduced motion |
| supabase/tests/*.sql, supabase/functions/*/*_test.ts | backend/RLS contracts supplemented by real two-device and hosted-service tests |

The automated tests establish logic and contracts. The manual cases establish whether the running Android artifact delivers the core promise: a private reminder that remains understandable, recoverable, and correctly routed across real devices.

