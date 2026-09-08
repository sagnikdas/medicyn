# Consumer Health Data Privacy Policy (Washington MHMD / Nevada SB370)

**Last updated:** 20 August 2026  
**Contact:** contact@doezly.com

This policy is **only** about consumer health data. The general
[Privacy Policy](PRIVACY.md) still applies. Washington's My Health My
Data Act requires this separate document. Nevada SB370 is meant to be
satisfied by the same text.

"Consumer health data" here means: the names of your medicines, your
schedules, your dose history (taken, snoozed, missed), any correction
note you attach to a dose, and the fact that a missed-dose alert was
sent.

Medicyn is the Android app `com.sagnikdas.medicyn`. The controller is
Doezly.

## What we collect, and from where

- **From you, on the phone:** medicine details you type or confirm, dose
  actions you take, optional voice descriptions, optional photos of a
  label (the photo is read on the device and deleted; it is not kept).
- **From Google, if you sign in:** email, name, account id.
- **From the phone:** IANA timezone and a last-seen time if you sign in;
  an FCM notification token if family alerts may run; a
  `push_install_id` for that install.

We do not buy consumer health data. We do not collect it from a hospital
or pharmacy system.

## Why we collect it

To remind you, to show you your own history, to back it up if you ask,
to help fill the form if you ask, and to share with **one** person you
choose if you ask.

## Your consent

Washington requires **opt-in before collection** of consumer health data
and a **separate consent before sharing**.

- Collection for reminders on this phone is the consent screen you see
  before the app is used. Purposes start **unticked**.
- Sharing with family is a **second** consent (`care_share`), asked when
  you connect a Care Link, not bundled with "use the app."
- Cloud backup, AI fill-in, and voice input are each their own switch.

You can withdraw any of those in **Settings**. Withdrawing family
sharing tries to end the live link immediately.

## Who we share consumer health data with

We name them:

- **Supabase** — cloud backup of your medicines and history, if you
  turned backup on. Region: Singapore (`ap-southeast-1`).
- **Anthropic** — the text of a label and a voice description, if you
  turned AI fill-in on. United States.
- **Google (Firebase Cloud Messaging)** — the notification that a dose
  was missed, including the medicine name and due time, sent to the
  person you linked. United States.
- **Google (speech)** — the audio, if you turned voice input on. Google
  is not our processor for that audio; it is a service on your phone.
- **One linked family member** — your medicines, schedules, dose
  history, and timezone, after you confirm them by name.

We do not sell consumer health data. We do not share it for advertising.

## How long we keep it

Dose history: 24 months rolling. Care-alert records: 12 months. Revoked
family links: 12 months. Notification tokens: 90 days idle. Your account
and medicines: until you delete them. Details are in the general privacy
policy.

## Your rights (Washington / Nevada)

You can:

- **Access** what we hold — Settings → Download my data, or email.
- **Delete** — Settings → Delete account, or delete one medicine and its
  history, or email contact@doezly.com.
- **Withdraw consent** — Settings toggles.
- **Appeal** a refusal — email the same address and say it is an appeal.
  If we still refuse, Washington residents may complain to the Attorney
  General.

We will answer within the time those laws require (and within one month
for GDPR, which we already promise).

## How to contact us

contact@doezly.com only.
