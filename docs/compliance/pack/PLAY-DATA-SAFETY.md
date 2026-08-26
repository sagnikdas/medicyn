# 3.8 — Play Console copy (Data Safety, Health apps, restricted permissions)

**Date:** 26 August 2026.
**Matches:** `app/assets/PRIVACY.md` and the Phase 1 permission model.
**Status:** Answers for the operator to paste. Nothing in this file submits
the form. Do not submit until it still matches the policy.

The public-page source is deployed by `.github/workflows/pages.yml`. The
operator must enable GitHub Pages for the repository and verify the URLs before
submitting the Play listing.

## Data Safety — collected

Declare **collected** for:

| Category | Type | Notes |
|---|---|---|
| Health | Health info | Medicines, schedules, dose history, contest notes |
| Personal info | Name | Google Sign-In, if used |
| Personal info | Email | Google Sign-In, if used |
| Personal info | User IDs | Google account id; Dosely `user_id` |
| Device or other IDs | Device or other IDs | FCM token; `push_install_id` (not an advertising ID) |
| Location | Approximate location | IANA timezone on the profile if signed in. Not GPS. |
| Audio | Voice or sound recordings | Microphone path. Dosely does not store the recording. On most devices Google's speech service receives the audio. |

Do **not** declare: contacts, browsing history, advertising ID, precise
location, photos **as stored** (the label image is OCR'd and deleted; only
text may leave).

## Data Safety — shared

Declare **shared** for:

| Category | With | Why |
|---|---|---|
| Health info | Supabase (backup), Anthropic (if AI fill-in on), the linked family account, Google FCM (missed-dose notification body) | App functionality |
| Name / email / user IDs | Google Sign-In, Supabase Auth; display name on a missed-dose FCM body | App functionality |
| Device IDs | Google FCM | Deliver the family alert |
| Approximate location | Linked family account sees timezone | Show reminder times on the patient's clock |
| Audio | Google (platform speech), if voice input is on | App functionality |

Encrypted in transit: **Yes** (TLS; cleartext disallowed).
Users can request deletion: **Yes** (Settings → Delete account and the public
Pages URL `https://sagnikdas.github.io/dosely/delete-account/`).
Data collected for app functionality: **Yes**.
Sold: **No**.
Optional, account-creation not required: **Yes** (local-only mode).

## Health apps declaration

This is a medication-reminder app. It displays and stores medication
information the user enters. It is **not** a device, not a clinical
decision system, and not connected to an EHR. Human confirms every
AI-filled field.

## Restricted / sensitive permissions

Declare, with the same justification already used in `PLAN.md` / the
manifest:

- `SCHEDULE_EXACT_ALARM` — requested only when a saved reminder needs exact
  timing. If it is unavailable, Dosely uses Android's inexact-while-idle
  fallback and tells the user that timing may be delayed.
- `POST_NOTIFICATIONS`
- `CAMERA` — label OCR only; photo deleted.
- `RECORD_AUDIO` — voice input only, and only if that consent is on.

## After submit

If `PRIVACY.md` gains a processor, a new identifier, or crash reporting
is switched on, **resubmit Data Safety before the store listing ships
that build.**
