# Privacy Policy for Dosely

**Last updated:** _[FILL IN before publishing]_
**Contact:** _[FILL IN — the support email you use on the Play listing]_

Dosely is a medication reminder app. It records what medicines you take and
when, so it can remind you and so you can look back at what you've taken.
That is health information, and this policy explains exactly what happens to
it.

This policy covers the Dosely Android app (package `com.sagnikdas.dosely`)
and its backend.

## What Dosely collects

**Your account.** When you sign in with Google, Dosely receives your email
address, your name, and a Google account identifier. Signing in with Google
is the only way to use the app. Dosely never sees or stores your Google
password.

**Your medicines and schedules.** The medicine name, strength, form, dose
amount, any notes you add, and the times and days you've set for reminders.

**Your dose history.** Each time you mark a dose as taken or snoozed, Dosely
records which reminder it was for, the time the dose was due, and the time
you responded.

**Nothing else.** Dosely does not collect your location, your contacts, your
device identifiers for advertising, your browsing activity, or any other
health information beyond what you enter as a medicine reminder.

## The camera and the microphone

**Label photos are never uploaded and never kept.** When you photograph a
medicine label, the image is read on your device to extract the text, and the
image file is deleted immediately afterwards. The photo does not leave your
phone and is not stored by Dosely.

**Voice input uses your device's speech recognition.** When you describe a
dosage out loud, Dosely uses the speech recognition service built into your
phone to turn it into text. On most Android devices that service is provided
by Google and the audio may be sent to Google's servers to be transcribed,
under Google's own privacy policy. Dosely itself does not store the audio and
never uploads a recording.

## What is sent off your device, and to whom

**Supabase** hosts Dosely's database and handles sign-in. Your medicines,
schedules, and dose history are stored there so that they survive losing or
replacing your phone. Access is restricted per account at the database level:
one account cannot read another account's data.

**Anthropic** receives the text — and only the text — from a label scan and a
voice description, when you use the automatic fill-in feature on the review
screen. It is used once, to turn that text into structured reminder fields
for you to check and correct. Neither the photo nor the audio is sent. If you
type the details in yourself instead, nothing is sent to Anthropic at all.

**Crash reporting** is included in the app but is switched off by default and
sends nothing. If it is ever enabled in a future release, this policy will be
updated first to say what it reports.

Dosely does not sell your data, does not share it with advertisers, and
contains no advertising or analytics SDKs.

## Where your data lives

Dosely keeps a copy of your reminders on your phone so that alarms still fire
without an internet connection, and a copy on Supabase as a backup. Both
copies contain the same information.

## How long it is kept

Your data is kept for as long as your account exists. Dose history is not
automatically deleted, because looking back over time is part of what the app
is for.

## Deleting your data

To delete everything, email the contact address at the top of this policy
from the address you signed in with, and your account and all associated
medicines, schedules, and dose history will be permanently deleted.
Uninstalling the app removes the copy on your phone but does not by itself
delete the backup.

## Children

Dosely is not intended for children and is not directed at anyone under 13.

## Permissions and why they are needed

- **Notifications, exact alarms** — to make a reminder fire at the right
  time. This is the core function of the app.
- **Ignore battery optimisations** — Android power saving can silently stop
  scheduled alarms. This permission is requested so reminders are not missed.
  You can decline it and the rest of the app still works.
- **Camera** — only to photograph a medicine label, as described above.
- **Microphone** — only to describe a dosage out loud, as described above.

## Changes to this policy

If what Dosely does with your data changes, this policy will be updated and
the date at the top will change.

## Contact

_[FILL IN — support email]_
