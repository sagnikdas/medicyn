# Medicyn — implemented features

This is the inventory of user-facing features implemented in the current
codebase. It is a **test scope**, not a claim that every feature has passed
physical iPhone testing or is available in a store release. Every feature
links to its acceptance checks in the [iOS real-device QA guide](docs/ios/REAL_DEVICE_QA.md#feature-by-feature-acceptance). Keep future ideas and
unbuilt paid tiers out of this file; add a feature here when its working flow
exists in the app, then add its linked real-device checks.

Medicyn supports a person managing medicines alone and a one-to-one pair of
that person and a caregiver. Local medicine reminders work without sign-in;
family sharing and cloud features need accounts and network access. iOS
device behavior, iOS Google sign-in, and APNs caregiver alerts still need
physical-device and service configuration checks.

## Getting medicines into Medicyn

<a id="f01"></a>
### F01 — Local-first onboarding

The person can start using medicine reminders without a Google account and
can choose cloud/family features later. [Real-device test](docs/ios/REAL_DEVICE_QA.md#qa-f01).

<a id="f02"></a>
### F02 — Manual medicine entry and review

Add or edit a medicine's name, strength, dose, schedule, notes, and optional
tablet count; review the details before saving. [Real-device test](docs/ios/REAL_DEVICE_QA.md#qa-f02).

<a id="f03"></a>
### F03 — Medicine-label scan

Use the camera and on-device text recognition to read a label, then review
editable AI-suggested medicine details. The app does not save the suggestion
without confirmation. [Real-device test](docs/ios/REAL_DEVICE_QA.md#qa-f03).

<a id="f04"></a>
### F04 — Spoken medicine entry

Speak medicine and dosage details, then review and correct the suggested
fields before saving. [Real-device test](docs/ios/REAL_DEVICE_QA.md#qa-f04).

<a id="f05"></a>
### F05 — Prescription photo and PDF capture

Scan a prescription or import a multipage PDF. Review the extracted medicines
and other care items individually before saving. This flow is present in the
current app code but is absent from the older feature checklist; its full
device-to-service path needs QA. [Real-device test](docs/ios/REAL_DEVICE_QA.md#qa-f05).

## Daily medicines and other care

<a id="f06"></a>
### F06 — Flexible medicine schedules

Schedule daily doses, selected weekdays, or every specified number of hours.
The phone owns its reminder schedule. [Real-device test](docs/ios/REAL_DEVICE_QA.md#qa-f06).

<a id="f07"></a>
### F07 — Local reminder delivery and actions

Receive a medicine notification and mark it **Taken** or **Snooze**, including
from the lock screen. Snooze duration is adjustable. Scheduled local
notifications are designed to work without an open app or network connection.
[Real-device test](docs/ios/REAL_DEVICE_QA.md#qa-f07).

<a id="f08"></a>
### F08 — Today, calendar, and medicine plan

See due and upcoming doses on Today, navigate dates on the calendar, and see
all medicines and schedules in Plan. [Real-device test](docs/ios/REAL_DEVICE_QA.md#qa-f08).

<a id="f09"></a>
### F09 — Dose history and corrections

Review per-medicine dose events and add a correction or dispute note to a
logged dose. [Real-device test](docs/ios/REAL_DEVICE_QA.md#qa-f09).

<a id="f10"></a>
### F10 — As-needed medicine logging

Keep a medicine without scheduled alarms and use **Log now** to record an
as-needed dose in the same history and stock flow as scheduled doses.
[Real-device test](docs/ios/REAL_DEVICE_QA.md#qa-f10).

<a id="f11"></a>
### F11 — Pause, resume, complete, and restart

Pause a schedule temporarily or indefinitely, resume it, mark a course
complete, or restart it. Stopping reminders can retain dose history.
[Real-device test](docs/ios/REAL_DEVICE_QA.md#qa-f11).

<a id="f12"></a>
### F12 — Refill tracking

Optionally enter remaining tablets; Taken doses reduce the estimate and a
warning appears when the supply is estimated to run out within five days.
This does not order medicine or depend on a pharmacy.
[Real-device test](docs/ios/REAL_DEVICE_QA.md#qa-f12).

<a id="f13"></a>
### F13 — Other care reminders

Add dated reminders for tests, scans, therapy, appointments, and other care,
with optional location, notes, and reminder lead time. Other care uses sign-in
and cloud backup. [Real-device test](docs/ios/REAL_DEVICE_QA.md#qa-f13).

<a id="f14"></a>
### F14 — Reminder reliability checks

See notification access, scheduled reminder health, and a test-reminder
action, with recovery guidance when access is missing.
[Real-device test](docs/ios/REAL_DEVICE_QA.md#qa-f14).

## Family care and backup

<a id="f15"></a>
### F15 — Google sign-in and sign-out

Sign in with Google for cloud and family features, and sign out while keeping
local reminder behavior understandable. iOS OAuth still needs setup and
device verification. [Real-device test](docs/ios/REAL_DEVICE_QA.md#qa-f15).

<a id="f16"></a>
### F16 — Optional cloud backup and sync

With consent, sync medicine data and edits across the linked accounts, queue
changes when offline, and show backup status and retry controls. Cloud is not
the source of truth for when the patient's alarm fires.
[Real-device test](docs/ios/REAL_DEVICE_QA.md#qa-f16).

<a id="f17"></a>
### F17 — One-to-one family connection

Connect one person taking medicines to one caregiver through an invite,
confirmation, and disconnect flow. Multi-person family plans are not part of
the current feature. [Real-device test](docs/ios/REAL_DEVICE_QA.md#qa-f17).

<a id="f18"></a>
### F18 — Caregiver dose feed

The caregiver can see the linked person's dose activity and reminder list;
the patient's phone remains the device that schedules its own alarms.
[Real-device test](docs/ios/REAL_DEVICE_QA.md#qa-f18).

<a id="f19"></a>
### F19 — Missed-dose and refill alerts to the caregiver

The caregiver can receive an alert when a patient dose goes unanswered and
when refill supply is low. iOS push delivery depends on APNs configuration
and is not yet physically verified. [Real-device test](docs/ios/REAL_DEVICE_QA.md#qa-f19).

<a id="f20"></a>
### F20 — Caregiver edits and change history

The caregiver can add or edit the patient's reminders, inspect change history
and a delivered/pending sync status, and see the patient's reminder setup
health. The caregiver cannot delete the patient's medicine.
[Real-device test](docs/ios/REAL_DEVICE_QA.md#qa-f20).

<a id="f21"></a>
### F21 — Call the linked person

Open the phone dialer from the family view or a relevant care alert when a
number is available. [Real-device test](docs/ios/REAL_DEVICE_QA.md#qa-f21).

## Understanding and sharing information

<a id="f22"></a>
### F22 — Weekly adherence insights

See a weekly summary of recorded medicine-taking, including consistency and
time-of-day patterns. [Real-device test](docs/ios/REAL_DEVICE_QA.md#qa-f22).

<a id="f23"></a>
### F23 — Four-week doctor report

Generate and share a PDF of medicines and recorded doses for a clinic visit.
[Real-device test](docs/ios/REAL_DEVICE_QA.md#qa-f23).

<a id="f24"></a>
### F24 — Emergency card

Keep blood group, allergies, conditions, medicines, and an emergency contact
on the device; view, call, print, or share the card as a PDF. The card is
local-only and is included in the data export.
[Real-device test](docs/ios/REAL_DEVICE_QA.md#qa-f24).

## Privacy and preferences

<a id="f25"></a>
### F25 — Consent and private notifications

Control optional data sharing and keep medicine names off lock-screen
notifications by default. [Real-device test](docs/ios/REAL_DEVICE_QA.md#qa-f25).

<a id="f26"></a>
### F26 — Data export and account deletion

Export a copy of the person's data, including local and available cloud
records, and use the self-service account deletion flow.
[Real-device test](docs/ios/REAL_DEVICE_QA.md#qa-f26).

<a id="f27"></a>
### F27 — Display and accessibility settings

Choose theme and in-app text size, alongside the phone's own text scaling.
Dates follow the device locale. [Real-device test](docs/ios/REAL_DEVICE_QA.md#qa-f27).
