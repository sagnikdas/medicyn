# 3.2 — Processor contracts

**Date:** 20 August 2026.
**Status:** Tracker only. No DPA has been accepted in a vendor console from
this pack. Do not tick these rows until you have done it.

Google's speech recogniser is **not** a processor of Medicyn. It is a
controller. There is no DPA to sign for it. Consent (`google_speech`) or
`onDevice: true` are the only tools.

## Map

| Party | Role | Receives | Contract | Where to execute | Done? |
|---|---|---|---|---|---|
| Supabase | Processor | Account, medicines, schedules, dose logs, contests, consents, profiles, care links, alerts, device tokens | [Supabase DPA](https://supabase.com/legal/dpa) (includes SCCs) | Supabase Dashboard → Organization → Legal / DPA | No |
| Anthropic | Processor (confirm in writing) | OCR text + transcript, ≤ 4,000 characters | Commercial DPA; **request zero data retention** | Anthropic Console / sales legal | No |
| Google (Firebase Cloud Messaging) | Processor for delivery | FCM token + notification body (display name, medicine, due time) | [Google Cloud DPA](https://cloud.google.com/terms/data-processing-addendum) / Firebase | Google Cloud Console → Account → Legal / GDPR | No |
| Google (speech) | **Controller** | Raw audio | None available | — | N/A |
| Google (Sign-In, Play) | Independent controller | Account identity, install / store data | Google's own policies | Disclose in `PRIVACY.md` (done) | N/A |
| Sentry | Not processing | Nothing (SDK off) | Would need a DPA before enable | — | N/A |

## Operator steps (do in this order)

1. **Supabase.** Sign in as the org owner (`kgeamhakgmnfhsythhrx`). Execute
   the DPA. Confirm the named controller is Doezly / Medicyn, not a
   placeholder company. Keep a PDF of the executed copy next to this file
   (do not commit it if it contains signatures you do not want in git).
2. **Google Cloud / Firebase** for project `twybepxnqayypzljhcnx`. Accept
   the Cloud DPA. FCM is in scope.
3. **Anthropic.** Execute the commercial DPA. Email legal and ask, in
   writing, for **zero data retention** on API inputs for the
   `parse-medicine` workspace, and for written confirmation that Anthropic
   is a processor for this traffic. Do not treat marketing pages as that
   confirmation.
4. Update the Done? column in this file the same day.
5. Speech stays a Google-controller path. Do not tell a user it is covered
   by "our processors."

## Sub-processors

Supabase and Google publish sub-processor lists. Anthropic's list is in
their DPA. Review them when you execute. Material new sub-processors that
see health data need a line here and a `PRIVACY.md` pass.

## HIPAA

A DPA is not a BAA. BAAs are Phase 4.2 and need a term sheet. The Android
speech path will never have a BAA.
