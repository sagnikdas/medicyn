# Firebase Crashlytics — operator setup

Everything Crashlytics needs from the codebase landed in
[#111](https://github.com/sagnikdas/medicyn/pull/111) (`chore/crashlytics-migration`):
`MedicynTelemetry.init` (`app/lib/core/telemetry.dart`) wires
`FlutterError.onError` / `PlatformDispatcher.instance.onError` into
Crashlytics, and the Android Gradle plugin is applied. None of it does
anything yet — like Sentry before it, Crashlytics is gated on
`google-services.json` / `GoogleService-Info.plist` being present, both
git-ignored, and CI does not currently write either file into a release
build. This document is the remaining work, and it is all outside the
codebase: Firebase Console clicks, one Xcode step, and CI secrets, done by
whoever has access to those consoles ("the operator").

Do the parts in order — Part B depends on Part A, Part F depends on Parts B
and D.

---

## Part A — Firebase Console

### A.1 Android — verify, don't create

`app/android/app/google-services.json` already exists in a working
checkout (git-ignored, machine-local). It points at an existing Firebase
project registered for package `com.sagnikdas.medicyn`. There is nothing to
create here — Crashlytics reuses this project and this app registration
automatically once the dependency is in the binary (already true as of
PR #111).

If you don't have this file on your machine: Firebase Console → the
project → **Project settings** (gear icon) → **Your apps** → the Android
app → **Download google-services.json** → save it to
`app/android/app/google-services.json`.

### A.2 iOS — register a new app

iOS push was never started for this app (see `PushService`'s comments), so
there is no iOS app registered in this Firebase project yet. Crashlytics
needs one:

1. Firebase Console → the same project used for Android → **Project
   settings** → **Your apps** → **Add app** → **iOS**.
2. **iOS bundle ID:** `com.sagnikdas.medicyn` (confirmed against
   `PRODUCT_BUNDLE_IDENTIFIER` in `app/ios/Runner.xcodeproj/project.pbxproj`
   — must match exactly, or the app won't be recognized at runtime).
3. App nickname: anything (e.g. "Medicyn iOS"). App Store ID: leave blank,
   fill in later if you publish to the App Store.
4. **Download `GoogleService-Info.plist`.** Do not commit it — save it
   somewhere temporary; Part B moves it into place.
5. Skip the SDK-installation instructions Firebase shows next — the
   `firebase_crashlytics` / `firebase_core` Flutter plugins already bring in
   the native SDKs via CocoaPods (`flutter pub get` + `pod install`, no
   manual `Podfile` edit). Click through to "Continue to console."

### A.3 There is no separate "enable Crashlytics" toggle

Unlike some Firebase products, Crashlytics activates itself on first
ingest. The Console shows "waiting for your first crash" until one arrives
— see Part G to trigger and confirm one. Nothing to click here.

---

## Part B — Add `GoogleService-Info.plist` to the Xcode project (one-time, local, iOS only)

Dropping the file into `app/ios/Runner/` is **not** sufficient on iOS,
unlike Android's `google-services.json` (which the Gradle plugin reads
straight off disk at build time). Xcode only bundles a resource it knows
about — the file has to be added as a member of the `Runner` target, which
changes `project.pbxproj`, a change that has to be made once, by hand, in
Xcode, on a Mac:

1. Open `app/ios/Runner.xcworkspace` (not `.xcodeproj`) in Xcode.
2. In the Project Navigator, right-click the **Runner** group (the one
   containing `AppDelegate.swift`, `Info.plist`) → **Add Files to
   "Runner"...**
3. Select the `GoogleService-Info.plist` downloaded in A.2.
4. In the dialog: check **Copy items if needed**, and under **Add to
   targets** check **Runner** only (not `RunnerTests`).
5. Click **Add**.
6. Verify: `grep GoogleService-Info app/ios/Runner.xcodeproj/project.pbxproj`
   should now show a `PBXFileReference` and a `PBXBuildFile` entry (Copy
   Bundle Resources).

**Commit the `project.pbxproj` change** (the reference), but confirm
`GoogleService-Info.plist` itself is **not** staged —
`app/.gitignore:60` already excludes it by path, but double-check
`git status` before pushing, the same discipline this repo already applies
to `google-services.json`. Open this as its own small PR; it's a genuine
Xcode-authored change I can't make blind from the CLI.

---

## Part C — iOS dSYM upload build phase (Xcode)

Without this, iOS crashes still reach Crashlytics but show raw memory
addresses instead of symbolicated stack traces — file names and line
numbers.

1. In the same Xcode workspace, select the **Runner** project → **Runner**
   target → **Build Phases** tab.
2. Click **+** (top left of the phase list) → **New Run Script Phase**.
3. Drag the new phase so it runs **after** "Embed Pods Frameworks" (last
   phase, or close to it).
4. Rename it (double-click the title) to something like "Upload Crashlytics
   dSYMs."
5. Paste into the script box:
   ```
   "${PODS_ROOT}/FirebaseCrashlytics/run"
   ```
6. Expand **Input Files** and add two entries:
   ```
   ${DWARF_DSYM_FOLDER_PATH}/${DWARF_DSYM_FILE_NAME}
   $(SRCROOT)/$(BUILT_PRODUCTS_DIR)/$(INFOPLIST_PATH)
   ```
7. Save. This is also a `project.pbxproj` change — commit it alongside (or
   in the same PR as) Part B's file reference.

---

## Part D — Accept the Google Cloud DPA

One acceptance covers Crashlytics and FCM both — see `docs/compliance/pack/DPA.md`.

1. Google Cloud Console → the project backing this Firebase project →
   **Legal** (or **IAM & Admin → Privacy & Security**, Google moves this
   occasionally) → find the **Cloud Data Processing Addendum**.
2. Accept it as the account that owns the project.
3. Update the **Done?** column for the "Google (Firebase Cloud Messaging)"
   and "Google (Firebase Crashlytics)" rows in `DPA.md` the same day (that
   file's own instruction — don't let the tracker drift from reality).

---

## Part E — CI secrets

Add two new secrets. Neither is cryptographically sensitive the way a
signing key is — `google-services.json` / `GoogleService-Info.plist` ship
inside every installed build already — but they're project-identifying, so
they follow the same base64-secret pattern this repo already uses for the
Android keystore.

1. **Android** — plain repository secret (matches `ANDROID_KEYSTORE_BASE64`
   and friends, which aren't environment-scoped either):
   - GitHub → repo → **Settings → Secrets and variables → Actions → New
     repository secret**.
   - Name: `GOOGLE_SERVICES_JSON_BASE64`.
   - Value: `base64 -i app/android/app/google-services.json | pbcopy`, paste.

2. **iOS** — scoped to the `ios-release` environment (matches
   `IOS_CERTIFICATE_P12_BASE64` and friends):
   - GitHub → repo → **Settings → Environments → ios-release → Add
     secret**.
   - Name: `IOS_GOOGLE_SERVICE_INFO_PLIST_BASE64`.
   - Value: `base64 -i app/ios/Runner/GoogleService-Info.plist | pbcopy`
     (on macOS; run from the machine holding the file from Part B), paste.

---

## Part F — CI workflow changes

Both release workflows currently ship an artifact with Firebase entirely
unconfigured — the same dormant state Sentry was always in. The steps below
make each workflow write the real config file when the secret from Part E
is set, and silently skip it (build proceeds without push/crash reporting,
exactly like a fresh local checkout) when it isn't — deliberately a soft
gate, not a hard failure like the signing-secret checks. Missing Firebase
config is a missing feature, not a security problem, so it shouldn't block
a release the way a missing keystore does.

### F.1 `.github/workflows/android-release.yml`

Insert a new step **after** "Materialize signing inputs outside Git" and
**before** "Build signed AAB":

```yaml
      - name: Materialize Firebase config (optional)
        if: ${{ secrets.GOOGLE_SERVICES_JSON_BASE64 != '' }}
        working-directory: app/android/app
        env:
          GOOGLE_SERVICES_JSON_BASE64: ${{ secrets.GOOGLE_SERVICES_JSON_BASE64 }}
        run: |
          echo "$GOOGLE_SERVICES_JSON_BASE64" | base64 --decode > google-services.json
```

### F.2 `.github/workflows/ios-release.yml`

Insert a new step **after** "Set up Flutter" and **before** "Resolve Dart
and CocoaPods inputs" (the plist has to exist before `pod install` /
`xcodebuild archive` run; earlier is simplest). This workflow runs on
`macos-latest`, so it uses `base64 -D` like the existing certificate step,
not `base64 --decode`:

```yaml
      - name: Materialize Firebase config (optional)
        if: ${{ secrets.IOS_GOOGLE_SERVICE_INFO_PLIST_BASE64 != '' }}
        shell: bash
        env:
          IOS_GOOGLE_SERVICE_INFO_PLIST_BASE64: ${{ secrets.IOS_GOOGLE_SERVICE_INFO_PLIST_BASE64 }}
        run: |
          printf '%s' "$IOS_GOOGLE_SERVICE_INFO_PLIST_BASE64" | base64 -D > app/ios/Runner/GoogleService-Info.plist
```

This step only writes the *file*; the `project.pbxproj` reference from
Part B must already be committed on `main` for Xcode to pick it up during
the archive step — the workflow can't add project membership on the fly.

---

## Part G — Verify it's actually working

Do this after Parts A–C are done, on a debug build (no need to wait for a
signed release to test):

1. `flutter run` on a device or simulator with `google-services.json` (and,
   for iOS, the Part B/C changes) in place.
2. Trigger an uncaught exception — temporarily, e.g. a button's `onPressed`
   that does `throw Exception('crashlytics test')` — then **fully close and
   reopen the app** (Crashlytics batches a report and sends it on the
   *next* launch, not the crashing one).
3. Firebase Console → **Crashlytics** → wait a few minutes → the test crash
   should appear with a stack trace pointing at the throwing line (not raw
   addresses, if Part C's dSYM phase ran on iOS).
4. Remove the temporary `throw` before shipping.
5. Confirm no medicine names, doses, schedules, or account identifiers
   appear anywhere in the reported crash — `MedicynTelemetry`'s allow-list
   (`app/lib/core/telemetry.dart`) is what's supposed to guarantee this for
   the `.log()` breadcrumbs and named `recordError` codes, but an uncaught
   exception's own message and stack trace are not filtered by that
   allow-list, so check what a real crash in this app's screens actually
   says before trusting it in production.

---

## Part H — Turning it back off

If you need Crashlytics off again (e.g. to re-test the "unconfigured"
degrade path):

- **Locally:** delete `app/android/app/google-services.json` (and, for
  iOS, remove the Part B file reference or the physical
  `GoogleService-Info.plist`). `MedicynTelemetry.init` catches the
  resulting `Firebase.initializeApp()` failure and every crash-reporting
  call becomes a no-op — same as a fresh checkout.
- **In CI:** delete or empty the two secrets from Part E; the `if:` guards
  in Part F skip materializing the files and the build proceeds as before.
- There is no separate "off" flag in Dart — unlike Sentry's empty-DSN
  toggle, Crashlytics's only on/off switch is whether Firebase is
  configured at all.

---

## Related files

- `app/README.md` — "Crash reporting (Firebase Crashlytics)" section.
- `docs/compliance/pack/ROPA.md` — B7, records what's actually collected
  and its legal basis; update the "Live status" line once Parts A–F are
  done and a real build is shipping crash reports.
- `docs/compliance/pack/DPA.md` — the Crashlytics/FCM processor row; update
  its **Done?** column after Part D.
- `docs/compliance/pack/PLAY-DATA-SAFETY.md` — Crash logs rows in both the
  collected and shared tables; already anticipates this in its "After
  submit" note.
- `docs/play-store/closed-testing.md` — step 33.8, the Data Safety
  crash-reporting checkbox.
- `docs/compliance/SECURITY-AUDIT.md` — the Sentry → Crashlytics changelog
  entry appended after finding #35.
