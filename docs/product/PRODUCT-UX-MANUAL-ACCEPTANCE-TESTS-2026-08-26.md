# Dosely codex-master manual acceptance tests

**Build scope:** Phase 1, Phase 2, and the implemented Phase 3 lifecycle foundation on `codex-master`  
**Test date:** 26 August 2026  
**Primary device:** Samsung Android phone  
**Supabase prerequisite:** `20260826100000_phase3_lifecycle.sql` has been applied to the hosted project

## 1. Test setup

1. Install the signed/internal `codex-master` build on the Samsung phone.
2. Confirm the phone has internet access, notifications enabled, and the device is not in Do Not Disturb mode.
3. Prepare a second Android device or emulator for cross-device tests.
4. Prepare two test accounts: **Account A** and **Account B**.
5. Use a test medicine such as `Test Paracetamol`, strength `650 mg`, dose `1 tablet`.
6. For alarm tests, create a reminder two to five minutes in the future.
7. Record the result of every test as **Pass**, **Fail**, or **Blocked**, including screenshots and the test data used.

## 2. Automated pre-checks

From the repository:

```bash
cd /Users/sagnikdas/research/dosely/app
flutter analyze
flutter test
```

Expected result: analysis reports no issues and all tests pass.

## 3. Supabase migration verification

In Supabase SQL Editor, run:

```sql
select status, count(*)
from public.schedules
group by status
order by status;

select column_name, data_type
from information_schema.columns
where table_schema = 'public'
  and table_name = 'schedules'
  and column_name in ('status', 'start_date', 'end_date', 'pause_until')
order by column_name;
```

Expected result:

- The four lifecycle columns exist.
- Existing schedules have a valid `active`, `paused`, `completed`, or `asNeeded` status.
- No migration error is present in the Supabase dashboard.

## 4. Phase 1 acceptance tests

### P1-01 — Account consent isolation

1. On a fresh install, use local-only mode and confirm external processing is off.
2. Sign in as Account A.
3. Grant cloud backup and any other consent requested by the test flow.
4. Sign out.
5. Sign in as Account B on the same phone.
6. Open consent/settings screens.

Expected result: Account B starts with external processing disabled. No cloud sync, push-token registration, AI parsing, speech processing, or care call occurs until Account B explicitly grants the relevant consent.

7. Sign out of B and sign back in as A.

Expected result: only Account A's consent choices return.

### P1-02 — Sign-out and push listener isolation

1. Sign in as Account A and enable care sharing.
2. Leave the app open or backgrounded.
3. Sign out.
4. Sign in as Account B.
5. Trigger a test care notification for Account B, if configured.

Expected result: no notification callback, navigation, token, or data from Account A is handled in Account B's session.

### P1-03 — Contextual notification permission

1. Clear Dosely notification permission in Android Settings.
2. Open Dosely Home.

Expected result: no notification permission prompt appears merely on Home load.

3. Add a scheduled reminder and tap Save.

Expected result: the notification permission explanation appears at the point of saving the reminder.

4. Deny notification permission.

Expected result: the reminder is still saved and the app shows a clear degraded/fix state.

### P1-04 — Exact alarm and degraded scheduling

1. Reopen the reminder reliability screen.
2. Deny exact-alarm access when prompted, or disable it in Android Settings.
3. Return to Dosely.

Expected result: the app does not claim exact scheduling is active. It explains the fallback or fix path and does not silently substitute UTC.

4. Re-enable exact-alarm access.
5. Return to Dosely and refresh/reopen reliability.

Expected result: the permission state and armed reminder state update.

### P1-05 — Reminder health and test reminder

1. Open **Settings → Reminder reliability**.
2. Inspect notification permission, exact-alarm state, battery state, armed count, and last reconciliation.
3. Disable one relevant Android permission.
4. Return to Dosely.

Expected result: the affected reminder says **Not active—fix** or equivalent, not **Reminder active**.

5. Use **Send a test reminder**.

Expected result: a test notification arrives on the Samsung phone.

### P1-06 — Sound, heads-up, and lock-screen privacy

1. Set the phone media volume to an audible level and disable silent mode.
2. Create a reminder two minutes ahead.
3. Lock the phone and wait for the reminder.

Expected result:

- The reminder makes an audible sound.
- It appears as a heads-up notification.
- Lock-screen content follows the configured privacy setting and does not expose medicine details when privacy is enabled.

### P1-07 — Reboot and cold-start resilience

1. Create a reminder five minutes ahead.
2. Reboot the Samsung phone.
3. Do not open Dosely after reboot.
4. Wait for the reminder.

Expected result: the reminder still fires, or the app clearly reports why it could not be armed.

5. Force-stop Dosely, reopen it, and check Reminder reliability.

Expected result: reconciliation runs and the armed state is accurate.

### P1-08 — Schedule replacement after edit

1. Create a reminder for a future time.
2. Edit it to a different future time.
3. Wait through both the old and new times.

Expected result: the old alarm does not fire; only the new schedule is active.

### P1-09 — Public privacy, deletion, and support routes

From a browser where Dosely is not installed, open the configured public HTTPS links:

1. Privacy page.
2. Account deletion page.
3. Support page.

Expected result: every page loads without repository access or authentication, explains the route clearly, and uses the same URLs documented in the app and Play materials.

### P1-10 — Share diagnostics redaction

1. Trigger a permission or scheduling failure.
2. Open **Share diagnostics**.
3. Inspect the generated content before sharing.

Expected result: diagnostics contain app/device/version/permission/arming/sync information only. They must not contain medicine names, dosage, OCR text, transcripts, email, care codes, raw IDs, or precise health timestamps.

## 5. Phase 2 acceptance tests

### P2-01 — First-session method chooser

1. Clear app data or use a fresh install.
2. Open Dosely.

Expected result: the Add flow offers **Scan label**, **Speak details**, and **Enter manually**.

3. Select **Enter manually**.

Expected result: camera and microphone permissions are not requested.

4. Enter the test medicine, frequency, and time.
5. Save it before signing in.

Expected result: the reminder is created locally without an account.

### P2-02 — Scan and voice capture recovery

1. Start the scan flow and grant camera access only after selecting Scan.
2. Test with a readable label.
3. Repeat with an unreadable/invalid label.
4. Start the voice flow and grant microphone access only after selecting Speak.
5. Repeat with an unintelligible input.

Expected result: successful capture opens the review form; failed capture offers retry and **Fill in manually**. Raw exceptions are not shown.

### P2-03 — Review and permission order

1. Capture or enter a medicine.
2. Confirm the medicine name, amount, frequency, and times before saving.
3. Save the reminder.

Expected result: notification and exact-timing permissions are requested one at a time at Save, not earlier. The next reminder and **Send a test reminder** action are visible after saving.

### P2-04 — Backup status and offline recovery

1. Sign in and enable cloud backup.
2. Open the backup/sync status area.

Expected result: Backup On/Off, last successful sync, pending work, and Retry are visible.

3. Disable network connectivity.
4. Edit a reminder and save.

Expected result: the local edit succeeds and the app remains usable; pending sync is visible.

5. Restore network connectivity and tap Retry or foreground the app.

Expected result: the edit syncs and pending work clears.

### P2-05 — Friendly loading, empty, and error states

1. View Plan with no reminders.
2. View Plan with reminders.
3. Simulate a temporary network failure while loading a cloud-backed screen.

Expected result: empty, loading, successful, and retryable-error states are distinct and provide a useful action.

### P2-06 — Accessibility and large text

1. Set Android text size to maximum and at least 200% where available.
2. Exercise Home, Plan, reminder editing, Settings, permissions, and Insights.
3. Enable TalkBack and inspect the main controls.

Expected result: no critical control is clipped or unreachable; buttons remain usable; interactive targets are comfortable; charts and statuses have meaningful labels.

### P2-07 — Snooze behavior and duration

1. Trigger a reminder notification.
2. Open the notification.
3. Tap **Snooze**.

Expected result: the prompt closes immediately and the user can navigate elsewhere.

4. Check the reminder in Plan.

Expected result: it shows the selected snooze duration/time.

5. Repeat with 5-minute and 10-minute settings.
6. Edit the reminder while it is snoozed.

Expected result: the old snooze does not suppress the newly edited schedule.

7. Mark the snoozed reminder as taken.

Expected result: one dose is recorded, not multiple doses from repeated taps.

### P2-08 — Insights correctness

1. Record several taken, missed, and unanswered doses.
2. Open Insights.

Expected result: **Most consistent** and chart labels reflect the actual dose history and remain understandable with accessibility settings enabled.

## 6. Phase 3 acceptance tests currently in the build

### P3-01 — Active reminder lifecycle

1. Create a scheduled reminder.
2. Open Plan and edit it.

Expected result: the lifecycle status says **Active**.

### P3-02 — Pause indefinitely

1. From the reminder edit screen, select **Pause reminder → Indefinitely**.

Expected result:

- The edit screen closes.
- Plan shows **Paused**.
- Future notifications stop.
- Existing dose history remains available.

### P3-03 — Pause until tomorrow

1. Open the reminder again.
2. Select **Pause reminder → Until tomorrow**.

Expected result: Plan shows the pause window and no alarm fires during the pause.

3. After the window expires, foreground the app.

Expected result: reconciliation makes the reminder eligible for re-arming.

### P3-04 — Resume

1. Open a paused reminder.
2. Select **Resume reminder**.

Expected result: Plan shows **Active** and a future notification is armed.

### P3-05 — Complete and restart

1. Open an active reminder.
2. Select **Mark course complete**.

Expected result: Plan shows **Completed**, future alarms stop, and history remains available.

3. Select **Restart reminder**.

Expected result: Plan shows **Active** and the reminder is re-armed.

### P3-06 — As-needed reminder

1. Add a reminder with frequency **As needed**.
2. Save it.

Expected result: Plan shows **As needed** and no scheduled alarm is created.

### P3-07 — Lifecycle cloud sync

1. Sign into the same account on Device A and Device B.
2. Ensure cloud backup is enabled on both.
3. Pause a reminder on Device A.
4. Foreground Device B and allow sync to complete.

Expected result: Device B shows the reminder as paused and does not arm it.

5. Resume the reminder on Device A.
6. Foreground Device B again.

Expected result: Device B shows it as active and re-arms the reminder.

### P3-08 — Complete export

1. Open Settings and export Dosely data.
2. Inspect the JSON in the share preview or after saving a copy.

Expected result:

- `metadata.schema_version` is present.
- Schedule records include `status`, `start_date`, `end_date`, and `pause_until`.
- Medicine stock fields and sync fields are present.
- No encryption key, refresh token, FCM token, or other excluded secret is present.
- The temporary plaintext export is cleaned up after sharing.

## 7. Phase 3 items not yet acceptance-testable

Do not mark these as passed for the current build:

- PRN **Log dose now** with optional amount/reason.
- Excluding PRN logs from adherence denominators.
- Auditable dose corrections.
- Quantity/unit-based refill transactions and projected run-out.
- User-facing start-date/end-date editing controls.
- Locale-aware date/time formatting and fully externalized strings.
- SQLite foreign-key cleanup migration verification.
- Date-range history query optimization.

## 8. Release decision evidence

Before sign-off, attach:

1. `flutter analyze` output.
2. Full `flutter test` output.
3. Supabase migration query results.
4. Samsung screenshots/video for failed and recovered permissions.
5. Notification evidence after save, reboot, snooze, pause, resume, completion, and restart.
6. Two-device sync evidence.
7. Export redaction evidence.
8. A list of every failed, blocked, or untested item with a reproduction step and severity.
