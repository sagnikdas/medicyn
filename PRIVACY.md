# Privacy Policy for Dosely

**Last updated:** 20 August 2026
**Contact:** sagnikd91@gmail.com

The controller is Sagnik Das, the sole developer of Dosely. Correspondence
is by email only.

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
records which reminder it was for, the time the dose was due, and the time you
responded. If a reminder goes unanswered for more than half an hour, Dosely
records that too, as a missed dose.

**A notification token for your phone.** So that Dosely can alert the person
you have chosen to share with (see below), it stores an identifier that
Google's notification service uses to reach your device. It is tied to this
installation of the app, not to you as a person, and it is deleted when you
sign out. It is not used for advertising or analytics, and it cannot be used to
locate you.

**A record of the alerts that were sent.** When Dosely notifies the person you
share with, it records that it did so and when. Both of you can see that
record — you are never told less about your own information than they are.

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
no other account can read your data unless you have connected it yourself, as
described in "Sharing with someone who helps you" below.

**Google** delivers Dosely's notifications between two connected phones, using
Firebase Cloud Messaging. Google receives the notification token for the
receiving device and the contents of the notification — which, for a missed
dose, includes the name of the medicine, the time it was due, and the display
name on your account. This is only used to deliver the message, under Google's
own privacy policy. If you have not connected your account to anyone, Dosely
sends no such notifications and nothing about your medicines is sent to
Google.

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

## Sharing with someone who helps you

Dosely can connect your account to **one** other person's — typically a family
member who wants to know that you are taking your medicines. Nothing is shared
until you set this up, and it works in two steps that both need you:

1. You show them a short code that Dosely generates for you.
2. They enter it, and then **you** confirm, by name, that it is really them.

Holding the code is not access. Until you confirm, the person who entered it
can see nothing at all.

**What they can see once connected.** Your medicines, your schedules, and your
dose history — including doses recorded as missed. They can also add and edit
medicines for you. **You see exactly the same screens about yourself that they
see about you**, and you can see every alert Dosely has sent them.

Access runs one way only. Connecting lets them see your medicines; it does not
let you see theirs — they may have prescriptions of their own that are none of
your business. And neither of you gains access to anybody else: an account can
be connected to at most one other.

**What they are told automatically.** If a reminder goes unanswered for more
than half an hour, Dosely sends them a notification naming the medicine and the
time it was due.

**Ending it.** Either of you can disconnect at any time, from inside the app,
and access stops immediately. Dosely keeps a record that the connection existed
and when it ended, so the question "who could see my medicines, and when" always
has an answer. Your medicines and dose history belong to your account and are
unaffected by disconnecting.

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
  time. This is the core function of the app. The same notification permission
  is what lets Dosely tell you if someone you help has missed a dose.
- **Ignore battery optimisations** — Android power saving can silently stop
  scheduled alarms. This permission is requested so reminders are not missed.
  You can decline it and the rest of the app still works.
- **Camera** — only to photograph a medicine label, as described above.
- **Microphone** — only to describe a dosage out loud, as described above.

## Changes to this policy

If what Dosely does with your data changes, this policy will be updated and
the date at the top will change.

## Contact

sagnikd91@gmail.com
