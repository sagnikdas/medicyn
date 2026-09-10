# 3.4 — Record of processing (GDPR Art. 30)

**Controller:** Doezly, contact@doezly.com.
**Date:** 20 August 2026.
**Version:** 1. Against `main` @ `f73aed5`.

The Art. 30(5) small-organisation exemption does **not** apply. Processing
includes special categories of data (Art. 9 health). This record is
mandatory regardless of headcount.

Medicyn is not a processor for anyone else. There is no Art. 30(2) section.

## A. Identity

| | |
|---|---|
| Controller | Doezly |
| Contact | contact@doezly.com |
| DPO | None — see [SCOPE.md](SCOPE.md) |
| EU / UK representative | None appointed — see [SCOPE.md](SCOPE.md) |
| Joint controllers | None. Google is an independent controller of Sign-In, Play, and (typically) speech audio. |

## B. Purposes, categories, recipients, transfers, retention

### B1. On-device medication reminders

- **Purpose:** Fire alarms and keep a history of taken / snoozed / missed doses.
- **Data subjects:** The person using the app (adults; not directed at children).
- **Categories of personal data:** Medicine name, strength, form, dose, notes,
  schedule, dose logs, contest notes.
- **Special categories:** Health (Art. 9).
- **Recipients:** None (stays on the device).
- **Transfers:** None.
- **Retention:** While the app is installed, or 24 months rolling for dose
  logs. Uninstall removes the local copy.
- **Security:** Encrypted SQLite (`sqlite3mc`) keyed from Android Keystore;
  `allowBackup="false"`; session (if any) in Keystore-backed storage.

### B2. Account (Google Sign-In)

- **Purpose:** Identify a cloud account so backup and Care Link can exist.
- **Categories:** Email, name, Google account identifier.
- **Special categories:** No, by itself.
- **Recipients:** Google (Sign-In), Supabase Auth.
- **Transfers:** US (Google), Singapore (Supabase Auth).
- **Retention:** While the account exists; deleted with the account.
- **Legal basis:** Art. 6(1)(b). Optional — local-only mode exists.

### B3. Cloud backup

- **Purpose:** Survive losing or replacing the phone.
- **Categories:** Same as B1, plus `user_id`.
- **Special categories:** Health.
- **Recipients:** Supabase (processor).
- **Transfers:** Singapore (`ap-southeast-1`).
- **Retention:** While the account exists; medicines until deleted; dose
  logs 24 months (`prune_expired_data`).
- **Legal basis:** Art. 6(1)(a) + 9(2)(a). Consent `cloud_backup`, off by
  default.

### B4. AI fill-in (parse-medicine)

- **Purpose:** Turn label text and a spoken description into reminder fields
  for the user to check.
- **Categories:** OCR text and transcript, up to 4,000 characters. May
  incidentally include name, address, DoB, Rx number.
- **Special categories:** Health, and possibly other identifiers in the blob.
- **Recipients:** Anthropic (intended processor).
- **Transfers:** United States.
- **Retention:** Anthropic's side is a single request. Medicyn does not keep
  the photo. Request zero-retention in writing — see [DPA.md](DPA.md).
- **Legal basis:** Art. 6(1)(a) + 9(2)(a). Consent `anthropic_parse`, off by
  default.

### B5. Voice input

- **Purpose:** Fill a description without typing.
- **Categories:** Audio of the user speaking; the resulting transcript on
  the device.
- **Special categories:** Health (content of the utterance).
- **Recipients:** Google as **controller** of the platform speech service on
  most Android devices. Medicyn does not upload a recording.
- **Transfers:** United States (typical).
- **Retention:** Medicyn does not store the audio.
- **Legal basis:** Art. 6(1)(a) + 9(2)(a). Consent `google_speech`, off by
  default.

### B6. Family Care Link

- **Purpose:** One other person can see and edit medicines and be told of a
  missed dose.
- **Categories:** B1 data; profile display name, timezone, `last_seen_at`;
  FCM notification body (name, medicine, due time); `care_links` and
  `care_alerts` metadata.
- **Special categories:** Health.
- **Recipients:** The linked Google account; Google FCM (processor for
  delivery); Supabase.
- **Transfers:** Singapore (database), US (FCM).
- **Retention:** Live link until revoked; revoked rows 12 months; alerts 12
  months; tokens 90 days idle.
- **Legal basis:** Art. 6(1)(a) + 9(2)(a). Consent `care_share` at invite /
  claim. Second, named confirmation by the patient.

### B7. Crash reporting

- **Purpose:** App stability — diagnosing crashes and unhandled errors.
- **Data:** Stack trace, app version, device manufacturer/OS version, and an
  anonymous Firebase installation id. Never name, email, account id,
  medicines, doses, or schedules — enforced by an allow-list in
  `MedicynTelemetry` (`app/lib/core/telemetry.dart`), not by trusting the
  vendor's default collection scope.
- **Recipients:** Google (Firebase Crashlytics), as a processor.
- **Transfers:** United States.
- **Retention:** 90 days (Crashlytics' standard retention; not configurable
  by us).
- **Legal basis:** Art. 6(1)(f), legitimate interest in diagnosing crashes
  in an app that manages medication reminders. No special-category data is
  processed in this record.
- **Live status:** Wired in code (`firebase_crashlytics`, replacing Sentry
  as of this change), but gated on the same `google-services.json` /
  `GoogleService-Info.plist` as push — CI does not currently materialize
  either file for a release build, so it is not yet live in a shipped
  artifact. Update this record's status once an operator adds those files
  to a release pipeline.

## C. Technical and organisational measures (summary)

RLS on every table; security-definer RPCs with pinned `search_path`;
encrypted local DB; Keystore session; backup disabled; consents recorded
with hashed on-screen sentences; deletion in-app; breach plan in
[BREACH.md](BREACH.md). Solo operator: one Google account to Supabase,
Google Cloud, and Firebase — MFA on that account is an organisational
control and is the operator's to enable (see COMPLIANCE.md 4.4).
