# Privacy Policy for Dosely

**Last updated:** 20 August 2026
**Contact:** sagnikd91@gmail.com

## Who is responsible

The controller is **Sagnik Das**, the sole developer of Dosely. Correspondence
is by email only, at **sagnikd91@gmail.com**. There is no other contact
address.

Dosely is a medication reminder app (Android package
`com.sagnikdas.dosely`). It records what medicines you take and when, so it
can remind you and so you can look back at what you've taken. That is health
information, and this policy explains exactly what happens to it.

This policy covers the Dosely Android app and its backend.

## What Dosely collects

**Your medicines and schedules.** The medicine name, strength, form, dose
amount, any notes you add, and the times and days you've set for reminders.
Dosely cannot remind you without this.

**Your dose history.** Each time you mark a dose as taken or snoozed, Dosely
records which reminder it was for, the time the dose was due, and the time you
responded. If a reminder goes unanswered for more than half an hour, Dosely
records that too, as a missed dose.

**Your account, if you sign in.** When you sign in with Google, Dosely
receives your email address, your name, and a Google account identifier.
Dosely never sees or stores your Google password. Signing in with Google is
**not** the only way to use the app: you can choose **Use without an
account** and keep reminders on this phone only. Backup and family sharing
need a Google account later.

**Your timezone, last-seen time, and whether reminders can fire, if you
sign in.** On sign-in Dosely writes the phone's IANA timezone (for example
`Asia/Kolkata`) to your profile. That is a coarse location — the region of
the clock you use, not a GPS pin. A linked family member can see it, so
their screens show your reminder times on your clock. Dosely also records
`last_seen_at` on the profile, which is when this signed-in app last
updated that profile, and a snapshot of whether this phone currently
allows notifications, exact alarms, and battery exemption, plus how many
alarms are armed. A linked family member can see that snapshot. It is
there so they are not left reading "no alerts" as "all is well" when the
phone cannot actually ring.

**A notification token for your phone, if you are signed in.** So that Dosely
can alert the person you have chosen to share with, it stores the identifier
Google's notification service uses to reach this install (an FCM token) and
a `push_install_id` that ties that token to this installation of the app,
not to you as a person and not to advertising. These are stored only if you
are signed in and you use, or may use, family alerts. They are not
advertising identifiers. We try to delete the token when you sign out; if
that attempt fails, it is dropped when the token goes stale or when someone
else signs in on the same phone.

**A record that a family alert was sent.** When Dosely notifies the person
you share with, it records that it did so and when, so the same missed dose
is not sent twice. There is no in-app list of those alerts today.

Dosely does **not** collect advertising identifiers, your contacts, your
browsing activity, GPS location, or any other health information beyond what
you enter as a medicine reminder. The timezone above is the only location
information, and it is the name of a clock zone, not a map position.

## The camera and the microphone

**Label photos are never uploaded and never kept.** When you photograph a
medicine label, the image is read on your device to extract the text, and the
image file is deleted immediately afterwards. The photo does not leave your
phone and is not stored by Dosely. Before any of that text is sent for AI
fill-in, this phone removes the patient's name, address, date of birth,
prescription number, and prescriber. What is sent is the remaining label
text — typically the medicine name, strength, and directions.

**Voice input uses your device's speech recognition.** When you describe a
dosage out loud, Dosely uses the speech recognition service built into your
phone to turn it into text. On most Android devices that service is provided
by Google and the audio may be sent to Google's servers to be transcribed,
under Google's own privacy policy. Dosely itself does not store the audio and
never uploads a recording. This happens only if you turn voice input on (see
"Why Dosely uses your information" below).

## Why Dosely uses your information

The law asks us to say the **legal basis** for each use. In plain words:
why we are allowed to do it.

**On-device reminders.** Keeping your medicines, schedules, and dose history
on this phone so the alarms can fire is what you asked the app to do. The
legal basis is GDPR Article 6(1)(b) (providing the reminder service) and, for
the health data itself, Article 9(2)(a) (your explicit consent, captured on
the consent screen).

**Cloud backup, AI fill-in, voice input, and family sharing.** Each of these
is a separate switch, off unless you turn it on:

- Cloud backup — store a copy of your medicines and dose history on
  Supabase, so they are not only on this phone.
- AI fill-in — send the label text (with name, address, date of birth,
  prescription number, and prescriber removed on this phone) and your spoken
  description to Anthropic to help fill in the reminder form.
- Voice input — use this phone's Google speech recogniser. The audio leaves
  the device.
- Family sharing — a linked person will see your medicines and dose history.

Each of those four is a separate consent (GDPR Article 6(1)(a) and, for
health data, Article 9(2)(a)). Withdrawing a consent takes effect
immediately: that processing stops. You can change any of them in
**Settings**.

**Your Google email, name, and account id.** If you sign in, we use these to
run a signed-in account (Article 6(1)(b)). You can use Dosely without
signing in.

**The notification token.** Only if you are signed in and you use, or may
use, family alerts, so a missed-dose message can reach the other phone.

## What is sent off your device, and to whom

If you use Dosely without an account, your medicines stay on this phone.
Nothing is backed up, and nothing is shared with family. Voice input and AI
fill-in still leave the phone if you turn those switches on.

**Supabase** hosts Dosely's database and handles sign-in. If you consent to
cloud backup, your medicines, schedules, and dose history are stored there so
that they survive losing or replacing your phone. Access is restricted per
account at the database level: no other account can read your data unless you
have connected it yourself, as described in "Sharing with someone who helps
you" below.

**Google** delivers Dosely's notifications between two connected phones,
using Firebase Cloud Messaging. Google receives the notification token for
the receiving device and the contents of the notification — which, for a
missed dose, includes the name of the medicine, the time it was due, and the
display name on your account. This is only used to deliver the message, under
Google's own privacy policy. If you have not connected your account to
anyone, Dosely sends no such notifications and nothing about your medicines
is sent to Google for that purpose. Google also receives your email, name,
and account id if you sign in, and may receive the audio if you use voice
input, as described above.

**Anthropic** receives the text — and only the text — from a label scan and a
voice description, when you have turned on AI fill-in and you use that
feature on the review screen. Name, address, date of birth, prescription
number, and prescriber are removed on this phone first. It is used once, to
turn that text into structured reminder fields for you to check and correct.
Neither the photo nor the audio is sent. If you type the details in yourself
instead, nothing is sent to Anthropic at all.

**Crash reporting** is included in the app but is switched off by default and
sends nothing. If it is ever enabled in a future release, this policy will be
updated first to say what it reports.

Dosely does not sell your data, does not share it with advertisers, and
contains no advertising or analytics SDKs.

## Where your data is sent (international transfers)

If information leaves this phone, it also leaves the European Economic Area
and the United Kingdom. All three recipients involve a transfer:

- **Supabase.** The database is in `ap-southeast-1` (Singapore).
- **Google.** Sign-In, Firebase Cloud Messaging, and usually the Android
  speech recogniser are in the United States.
- **Anthropic.** The parse request goes to `api.anthropic.com` in the United
  States.

Singapore has no EU adequacy decision. We are not claiming Standard
Contractual Clauses, Data Privacy Framework certification, or other transfer
paperwork that we have not yet put in place. Transfers happen; documenting
the safeguards is planned as Phase 3 of our compliance work. We are telling
you this now rather than waiting.

## Sharing with someone who helps you

Dosely can connect your account to **one** other person's — typically a
family member who wants to know that you are taking your medicines. Nothing
is shared until you set this up, and it works in two steps that both need
you:

- You show them a short code that Dosely generates for you.
- They enter it, and then **you** confirm, by name, that it is really them.

Holding the code is not access. Until you confirm, the person who entered it
can see nothing at all.

**What they can see once connected.** Your medicines, your schedules, and
your dose history — including doses recorded as missed. They can also add
and edit medicines for you. They cannot delete a medicine; only you can.
They can see a history of who added or changed each medicine. They can see
your timezone, so reminder times match your clock, and whether this phone
is currently able to fire reminders. **You see the same medicine, schedule,
and dose-history screens about yourself that they see about you.**

Access runs one way only. Connecting lets them see your medicines; it does
not let you see theirs — they may have prescriptions of their own that are
none of your business. And neither of you gains access to anybody else: an
account can be connected to at most one other.

**What they are told automatically.** If a reminder goes unanswered for more
than half an hour, Dosely sends them a notification naming the medicine and
the time it was due. Dosely records that it sent that alert so it is not
sent twice. There is no screen in the app today that lists those alerts.

**Ending it.** Either of you can disconnect at any time, from inside the
app, and access to your medicines, schedules, and dose history stops
immediately. Dosely keeps a record that the connection existed and when it
ended, for twelve months, so the question "who could see my medicines, and
when" has an answer. Your medicines and dose history belong to your account
and are unaffected by disconnecting.

## Where your data lives

Dosely keeps a copy of your reminders on your phone so that alarms still
fire without an internet connection. If you have consented to cloud backup,
a copy is also kept on Supabase. Both copies contain the same information.
If you use the app without an account, there is only the copy on this phone.

## How long it is kept

- **Your account, medicines, and schedules** — while the account exists, or
  until you delete that medicine.
- **Dose history** — 24 months, rolling. Older dose logs are removed.
- **Care alerts** (the record that a missed-dose notification was sent) —
  12 months.
- **Revoked family links** — 12 months after you disconnect, as an audit of
  who had access.
- **Notification tokens** — 90 days without being refreshed. We also try to
  delete the token when you sign out; if that fails, it is dropped when it
  goes stale or when someone else signs in on the same phone.

If you use the app without an account, there is no cloud copy to retain.
Uninstalling the app removes the copy on that phone.

## Your rights

You have the rights below. We will answer requests **within one month**
(GDPR Article 12(3)). Email **sagnikd91@gmail.com**, or use the in-app
paths where they exist.

- **Access and portability.** Open **Settings** and tap **Download my
  data**. You get a copy of what we hold about you, in a form you can take
  elsewhere.
- **Rectification.** Edit a medicine in the app. Dose logs are not rewritten
  — they are a record of what was marked at the time — but you can attach a
  correction note to a log.
- **Erasure.** Open **Settings** and tap **Delete account**, which removes
  the account and the cloud copy. You can also delete one medicine and its
  history.
- **Restriction and objection.** Email the controller. If the processing
  rests on consent, withdrawing that consent stops it immediately.
- **Withdraw consent.** Open **Settings** and use the toggles. Turning a
  switch off takes effect straight away.
- **Complain to a supervisory authority.** If you are in the EU or the UK,
  you can complain to your local data protection authority. In the UK that
  is the Information Commissioner's Office (ICO). You may do this without
  waiting for us, though we would rather fix the problem if you tell us
  first.

## Do you have to give us this information?

No. Using Dosely is not a legal requirement. Nobody is obliged by law to
enter their medicines here. The app simply cannot remind you unless you
enter the medicine and the schedule.

## Automated decisions

When you photograph a label or speak a dosage, an automated service (Claude)
may suggest the reminder fields. **That is not automated decision-making**
under GDPR Article 22. A human reviews and confirms every field before
anything is saved. You can change or type any field yourself. Nothing is
stored until you tap Save.

## Deleting your data

Signed-in users can delete their account in the app: open **Settings** and
tap **Delete account**. You will be asked twice, so it cannot happen by
accident.

If you cannot open the app, email **sagnikd91@gmail.com** from the Google
address you signed in with, or use this page:

https://github.com/sagnikdas/dosely/blob/main/docs/delete-account.md

That deletes your account, the cloud backup, any family link, and
notification tokens. Uninstalling the app removes the copy on your phone
but does not by itself delete the backup.

## Children

Dosely is not intended for children and is not directed at anyone under 13.

## Permissions and why they are needed

- **Notifications, exact alarms** — to make a reminder fire at the right
  time. This is the core function of the app. The same notification
  permission is what lets Dosely tell you if someone you help has missed a
  dose.
- **Ignore battery optimisations** — Android power saving can silently stop
  scheduled alarms. This permission is requested so reminders are not
  missed. You can decline it and the rest of the app still works.
- **Camera** — only to photograph a medicine label, as described above.
- **Microphone** — only to describe a dosage out loud, as described above.

## Changes to this policy

If what Dosely does with your data changes, this policy will be updated and
the date at the top will change.

## Data Protection Officer

Dosely has no Data Protection Officer. That role is not required at this
scale. Privacy questions still go to **sagnikd91@gmail.com**. There is
not yet an EU or UK representative (GDPR / UK GDPR Article 27). If you
are in the EEA or the UK, that gap is ours, not yours — you can still
write to the email above and to your supervisory authority.

## Washington and Nevada health privacy

If Washington's My Health My Data Act or Nevada SB370 applies to you,
there is a **separate** consumer health data policy in `docs/MHMD.md` in
the Dosely source tree. Ask for it by email if you cannot open that
file. It names Supabase, Anthropic, and Google, and it describes the
second consent before family sharing.

## Contact

sagnikd91@gmail.com
