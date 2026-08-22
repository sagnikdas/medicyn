# Closed testing — sequential steps

Google Play closed testing for Dosely (`com.sagnikdas.dosely`). This is the
calendar clock in `PLAN.md` Phase 4.

Do **every step in order**. Do not skip. Stop if a step fails; do not start
the next one.

When this list is finished, a signed AAB is live on **Closed testing**, at
least **12** people have used the Play **opt-in link** (not only an email
list), they installed **from Play** and **opened** the app, Google Sign-In
works on that Play install, and you keep 12+ opted in for **14 consecutive
days**. Recruit **15–20** testers so one dropout does not stop the clock.

Personal Play accounts created after 13 November 2023 typically need those
12 testers for 14 days before **Apply for production**. Confirm the current
rule in Console; Google has changed it before.

---

1. Confirm a Google Play Console developer account exists and the one-time
   fee is paid.

2. Check out the git branch testers should run (prefer `main` plus anything
   already merged).

3. List **15–20** people with Google accounts who will install from Play
   and use the app for two weeks. Tell them it is a medicine reminder and
   they must opt in via a Play link, not an APK you send.

4. Keep one or two of your own phones ready for the first Play install.

5. Host the legal pages on a **public** https site. The copies in this
   private repo 404 for Play. Do **not** use a private GitHub blob URL.

   1. Create a **public** GitHub repo (for example `dosely-legal`) or a
      public gist.
   2. Copy [`PRIVACY.md`](../PRIVACY.md) into it unchanged. That URL is the
      Play privacy-policy field.
   3. Copy [`docs/delete-account.md`](delete-account.md) into it unchanged.
      That URL is the Play account-deletion field.
   4. Optionally copy [`docs/MHMD.md`](MHMD.md) if you also want a public
      Washington consumer-health URL.
   5. Open each URL in a private browser window. If GitHub asks you to log
      in, Play cannot read it either — fix hosting before continuing.
   6. Write down the two (or three) public URLs. You paste them in steps 26
      and 33. Contact on the pages is already **sagnikd91@gmail.com**.

6. Understand the `.jks`: Play does **not** give you this file. You create
   it on this Mac with Java `keytool`. Play only receives the AAB you sign
   with it. After upload, Play re-signs tester installs with a different
   certificate (you copy it in step 44). Never commit the `.jks` or
   `key.properties`. Back
   up the `.jks` and passwords (password manager plus a second disk). If you
   publish and then lose the file, every later update needs a
   Google-assisted key reset.

7. In Terminal, run:

   ```sh
   keytool
   ```

   If that prints help text, go to step 9. If you get `command not found`,
   go to step 8.

8. Find `keytool` (use this same binary for generate and for `-list` later).

   1. Run `/usr/libexec/java_home -V`.
   2. If a JDK is listed, run `export JAVA_HOME=$(/usr/libexec/java_home)`
      then `"$JAVA_HOME/bin/keytool" -help`.
   3. If that fails, run:

      ```sh
      "/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/keytool" -help
      ```

   4. When `-help` works, use that full path in place of `keytool` in
      steps 9 and 11.

9. Generate the keystore. This creates **one new file** at
   `$HOME/dosely-upload-keystore.jks`. It does not exist until the command
   finishes.

   ```sh
   keytool -genkeypair -v \
     -keystore "$HOME/dosely-upload-keystore.jks" \
     -storetype JKS \
     -keyalg RSA -keysize 2048 -validity 10000 \
     -alias upload
   ```

10. Answer the prompts in this order:

    1. **Keystore password** — invent a long password and write it down.
       This is `storePassword`.
    2. **Re-enter password** — the same password again.
    3. **First and last name** — your name, e.g. `Sagnik Das`.
    4. **Organizational unit** — `Dosely`, or Return to leave blank.
    5. **Organization** — `Dosely` or your name.
    6. **City / locality** — your city.
    7. **State / province** — your state.
    8. **Country code** — two letters, e.g. `IN`.
    9. **Correct?** — `yes`.
    10. **Key password for `<upload>`** — press Return to reuse the
        keystore password (simplest). If you type a different one, that is
        `keyPassword`.

11. Wait until the terminal says it is generating a 2,048 bit RSA key pair
    and `[Storing …jks]`. Then run:

    ```sh
    ls -l "$HOME/dosely-upload-keystore.jks"
    keytool -list -v \
      -keystore "$HOME/dosely-upload-keystore.jks" \
      -alias upload
    ```

    Enter the keystore password. You must see `Alias name: upload` and a
    `SHA1:` line. That SHA-1 is the **upload** certificate, not Play’s
    app-signing certificate. If `ls` says No such file, do not continue —
    step 9 did not finish.

12. From the **repo root**, run:

    ```sh
    cp app/android/key.properties.example app/android/key.properties
    ```

13. Edit `app/android/key.properties`. `storeFile` must be an **absolute**
    path with no `~`. On this Mac:

    ```properties
    storeFile=/Users/sagnikdas/dosely-upload-keystore.jks
    storePassword=the-password-you-typed
    keyAlias=upload
    keyPassword=the-same-password-unless-you-set-another
    ```

    The Gradle file switches to this keystore as soon as
    `key.properties` exists. A fake path fails the release build on
    purpose. Do not put this file in git (it is already gitignored).

14. Build the signed bundle:

    ```sh
    cd app
    flutter build appbundle --release
    ```

    The output must be
    `app/build/app/outputs/bundle/release/app-release.aab`. If the command
    asks for debug signing or succeeds without `key.properties`, stop. Do
    not upload that artifact.

15. Open [Play Console](https://play.google.com/console) and choose
    **Create app**.

16. Set the name to **Dosely**. Pick the default language your testers
    actually read.

17. Choose **App**, **Free**, and accept that you meet Play policies and
    this is not a government app.

18. Do **not** enable EEA/UK **production** countries yet.
    `COMPLIANCE/SCOPE.md` still has no Art. 27 EU representative. Closed
    testing uses named testers; you do not need a worldwide production
    listing today. You cannot start a test track until Play’s dashboard
    says setup is complete enough to create a release — that is the
    following listing and policy steps.

19. Open **Grow users** → **Store presence** → **Main store listing**.
    Write copy for the adult child who sets the app up, not the parent.
    The first line is the job.

20. Set **App name** to `Dosely`.

21. Paste this **short description** (80 characters max):

    ```
    Know if they missed a dose, even if you are in another city.
    ```

22. Paste this **full description**:

    ```
    Dosely is a medicine reminder for one parent and one adult child.

    The parent gets alarms on their phone. The child sees whether a dose was
    taken, snoozed, or missed — including when they are in another city.

    Either person can add or change a reminder. Only the parent’s phone fires
    the alarm. The child cannot delete a medicine.

    You can use reminders on one phone with no Google account. Backup and
    family sharing need Google Sign-In.

    Not a clinic, not a diagnosis, not connected to a hospital record. You
    confirm every AI-filled label before it is saved.
    ```

23. Export a **512×512 PNG** app icon. Play will not accept the launcher
    mipmaps in `app/android/app/src/main/res/` as-is. Upload it.

24. Create and upload a **1024×500** feature graphic.

25. Capture at least **two** phone screenshots on a real device (Today, a
    reminder, Care / missed dose, Settings). Upload them. Add a tablet set
    only if you tick tablet support.

26. Paste the **public privacy-policy URL** from step 5.

27. Set category to Medical or Health & fitness (pick one; keep it
    consistent with the Health apps form). Set contact email to
    **sagnikd91@gmail.com**.

28. Save the store listing. You can polish wording during the 14 days. You
    cannot start a test track without the policy URL and screenshots.

29. Open **Monitor and improve** → **Policy and programmes** → **App
    content** (labels move; find Ads, Target audience, Content rating,
    Data safety, Health, Restricted permissions, App access). Fill the
    next steps in that order. For Data safety, copy
    [`COMPLIANCE/PLAY-DATA-SAFETY.md`](../COMPLIANCE/PLAY-DATA-SAFETY.md)
    so it still matches `PRIVACY.md`. Do not invent extra data types.

30. Ads: declare that the app does **not** contain ads.

31. Target audience: not for children under 13. Do **not** tick Families /
    Designed for children.

32. Content rating: complete the IARC questionnaire (medicine reminder, no
    public chat, no violence). Save the rating.

33. Data safety — declare **collected** and **shared** as in
    `PLAY-DATA-SAFETY.md`:

    1. Health info (medicines, schedules, dose history).
    2. Name, email, user IDs (if they sign in with Google).
    3. Device IDs (FCM token, install id — not an advertising ID).
    4. Approximate location (IANA timezone, not GPS).
    5. Audio (voice path; Dosely does not keep the recording).
    6. Encrypted in transit: **Yes**. Deletion: **Yes**. Sold: **No**.
       Account not required: **Yes** (Use without an account).
    7. Paste the **public account-deletion URL** from step 5.
    8. If `app/lib/core/sentry_config.dart` still has an empty DSN, do
       **not** declare crash-reporting collection.

34. Health apps: medication reminder; stores what the user entered; **not**
    a medical device, **not** a clinical decision system, **not** connected
    to an EHR; a human confirms every AI-filled field.

35. Restricted permissions — declare each of these, using the same
    justifications as `PLAY-DATA-SAFETY.md`:

    1. `SCHEDULE_EXACT_ALARM` / `USE_EXACT_ALARM` — alarm at the wall-clock
       time, screen locked, no live process.
    2. `USE_FULL_SCREEN_INTENT` — patient reminder is an alarm. Care alerts
       must **not** use this.
    3. `POST_NOTIFICATIONS` — reminders and care alerts.
    4. `CAMERA` — label OCR; photo not kept.
    5. `RECORD_AUDIO` — voice input, only if that consent is on.
    6. `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` — OEMs otherwise kill exact
       alarms; the user can refuse.

36. App access / login: state that local reminders work without an account,
    backup and family sharing use Google Sign-In, and you are not providing
    a shared demo password (there is none). Reviewers can tap **Use without
    an account**.

37. Open **Test and release** → **Testing** → **Internal testing**. Internal
    testing is how Play **creates the app-signing certificate**. Google
    Sign-In on a Play install will fail until step 52. That is expected on
    this first build.

38. Create a new release and upload
    `app/build/app/outputs/bundle/release/app-release.aab`.

39. Set the release name to `0.1.0 (1)` so it matches `version: 0.1.0+1` in
    `app/pubspec.yaml` (versionName `0.1.0`, versionCode `1`). Every later
    upload must bump `versionCode` (`0.1.0+2`, then `+3`, …).

40. Paste these release notes:

    ```
    First Play build. Reminders, Google Sign-In, and Care Link. Sign-in may
    fail until the Play signing key is registered — sideload is not this test.
    ```

41. Save, review, and **Start rollout to Internal testing**.

42. Add **yourself** as an internal tester, open the opt-in link, tap
    Become a tester, and install **from Play** (not a sideloaded APK).

43. Open **Test and release** → **Setup** → **App signing** (or **App
    integrity** / **App signing**).

44. Copy the **App signing key** SHA-1 (colon-separated hex). This is what
    testers install from Play. You will register it so Sign-In works in
    Play.

45. Copy the **Upload key** SHA-1. This is what you build locally. You will
    register it so Sign-In works on a local `apk --release`. You already
    have a **debug** Android OAuth client for `flutter run`; these two are
    extra.

46. Open Google Cloud project `decent-digit-135023` → **APIs & Services** →
    **Credentials** → **Create credentials** → **OAuth client ID** →
    **Android**. Without this step, closed testers get a dead or cancelled
    Google button on the Play build. A USB debug install uses a different
    certificate and does not prove Play.

47. Create the first Android client:

    1. Package name: `com.sagnikdas.dosely`.
    2. SHA-1: the **app signing** fingerprint from step 44.
    3. Name: `Dosely Android — Play app signing`.
    4. Save and copy the Android client ID.

48. Create the second Android client the same way, using the **upload**
    SHA-1 from step 45, named `Dosely Android — upload key`. Copy that
    client ID.

49. If the OAuth consent screen is still **Testing**, either add every
    tester Google account under **Audience → Test users**, or publish the
    consent screen. A tester not on that list gets “access blocked”, which
    looks like a broken app.

50. Open Supabase project `twybepxnqayypzljhcnx` → **Authentication** →
    **Providers** → **Google** → **Client IDs**.

51. Append the new IDs. Web stays first:

    ```
    <web-client-id>,<android-debug-id>,<android-play-app-signing-id>,<android-upload-id>
    ```

52. Wait until Play has finished processing the internal release, then
    open the Play-installed app and tap **Continue with Google**. It must
    complete. If you see a signing-certificate error, the SHA-1 you
    registered is not the **app signing** key — fix that before inviting
    twelve people.

53. Open **Testing** → **Closed testing**. Use the default closed track
    (create one if none exists).

54. Create a closed-testing release: promote the internal AAB, or upload a
    new AAB. OAuth-only changes do not require a new binary, but bump
    `versionCode` if testers already installed a build whose Sign-In was
    broken.

55. Add **15–20** tester emails (or a Google Group).

56. Save and **Start rollout to Closed testing**.

57. Copy the opt-in URL. It looks like
    `https://play.google.com/apps/testing/com.sagnikdas.dosely`.

58. Send testers this, with the real URL:

    ```
    Please help test Dosely on Google Play for 14 days.

    1. Open this link while signed into the Google account I listed:
       <OPT-IN URL>
    2. Tap Become a tester.
    3. Install Dosely from the Play Store button on that page
       (not an APK I send you).
    4. Open the app at least once. You can use “Use without an account”
       or Google Sign-In.

    Stay opted in for two weeks. If you leave the test, tell me.
    ```

59. Watch Play Console until **12 testers show as opted in**. A spreadsheet
    of emails is not 12 testers. The 14-day clock does not count until
    this number is real.

60. Ask each opted-in tester to do this, in order, at least once:

    1. Install from Play (after opt-in).
    2. Open the app.
    3. Create a reminder (local-only is enough).
    4. Accept or deny notification / exact-alarm / battery screens on
       purpose so you see setup health.
    5. Optionally: Google Sign-In, then Care Link on a second phone.

    Play must see **install + open**. A sideloaded debug APK does not count.

61. For the next 14 days, in order whenever you check:

    1. Confirm the opted-in count is still 12+. Replace dropouts the same
       day.
    2. Leave the closed release **live**. Do not halt the track.
    3. If you ship a crash fix, bump `versionCode` and upload a new AAB.
       A new binary does not reset the 14 days by itself; losing testers
       does.
    4. Write a few bullets of feedback (who you asked, what they found,
       what you changed). You will need them for production-access
       questions.

62. After Console lets you **Apply for production** (not this week):

    1. Confirm 12 testers were opted in continuously for the preceding
       14 days.
    2. Answer the production-access questions with specifics (what you
       tested, not “it works”).
    3. Wait for production review (often several days).
    4. Do not apply until Sign-In on the Play build, Data Safety, and the
       public URLs are still true.

---

If you are stuck, these files match the steps above:

- Why this runs in parallel with other work: [`PLAN.md`](../PLAN.md) Phase 4
- Upload keystore (same commands): [`app/README.md`](../app/README.md),
  [`README.md`](../README.md) “Before shipping a release build”
- Data Safety / health / permissions:
  [`COMPLIANCE/PLAY-DATA-SAFETY.md`](../COMPLIANCE/PLAY-DATA-SAFETY.md)
- Privacy policy source: [`PRIVACY.md`](../PRIVACY.md)
- Account deletion source: [`docs/delete-account.md`](delete-account.md)
- EEA / Art. 27: [`COMPLIANCE/SCOPE.md`](../COMPLIANCE/SCOPE.md)
