# Medicyn — iOS TestFlight distribution checklist

**Prepared:** 4 September 2026
**Scope:** repository-local preparation only. This document does not submit
anything to Apple or answer legal/export-compliance questions on the
operator's behalf.

## Current repository evidence

Complete these checks before creating or uploading an App Store Connect
record:

- [ ] Run `plutil -lint app/ios/Runner/Info.plist`.
- [ ] Install pods and build the Runner target on an iOS simulator and a
  physical iPhone. Phase 0–4 launch gates still apply; a successful archive
  alone is not evidence that reminders work correctly.
- [ ] Confirm the archive resolves to bundle identifier
  `com.sagnikdas.medicyn` (the Xcode project currently uses this value).
- [ ] Confirm the archive's marketing version and build number match the
  release being uploaded. The current pubspec starts at `0.1.0+1`; do not
  reuse a build number that App Store Connect has already received.
- [ ] Confirm the display name is **Medicyn** and the final branded icon is
  installed. The checked-in icon catalog currently contains Flutter's default
  blue mark, not final Medicyn artwork.
- [ ] Confirm the bundled privacy policy is present at
  `assets/PRIVACY.md` and that its claims match the shipped iOS feature set.

The iOS plist includes camera, microphone, Face ID, and speech-recognition
purpose strings. Google Sign-In URL/client-ID entries are intentionally still
absent until the real iOS OAuth client exists; do not replace them with sample
values.

## Privacy and export-compliance preparation

Use the compliance pack as the source inventory, then re-check it against the
actual iOS archive:

- `docs/compliance/pack/ROPA.md` — processing purposes, recipients, transfers,
  and retention.
- `docs/compliance/pack/SCOPE.md` — target markets and representative gap.
- `docs/compliance/pack/DPIA.md` — health-data risks and residual controls.
- `docs/compliance/PRIVACY.md` — user-facing policy text.

In App Store Connect, complete the App Privacy questionnaire only after the
actual iOS build's sign-in, push, speech, OCR, sync, care-link, and telemetry
behavior is known. Do not copy the Play form mechanically: the platform,
permissions, and enabled SDK paths may differ.

For export compliance, the repository shows:

- encrypted local SQLite via the `sqlite3mc` native-assets hook;
- Keychain-backed session storage on iOS through `flutter_secure_storage`;
- TLS-backed Supabase/Firebase/Google service connections.

`ITSAppUsesNonExemptEncryption` is not currently set in `Info.plist`. Keep it
that way until the operator has made and recorded the appropriate Apple
self-classification. The repository must not guess whether the local database
encryption is exempt or non-exempt. After classification, add the matching
plist metadata and retain the App Store Connect answer with the release
records.

## Account deletion acceptance check

This is a required manual TestFlight check on iOS, not a claim that it has
already passed on an Apple device:

1. Sign in with a test account and create at least one local medicine and one
   synced record, if those features are enabled in the build.
2. Open **Settings → Delete account**.
3. Verify the first dialog explains permanent deletion and displays the
   external deletion URL.
4. Verify **Continue** is followed by a second confirmation,
   **Delete my account**.
5. Cancel at each step and confirm nothing is deleted.
6. Confirm a recoverable server/network failure says the account and local
   data were not deleted.
7. Confirm a successful deletion signs out, removes the signed-in account's
   encrypted local database, and returns to the signed-out state.
8. From a browser with the app unavailable, verify the public deletion page
   at `https://sagnikdas.github.io/medicyn/delete-account/` and follow its
   identity-verification instructions.

The implementation calls the `delete_account` function without accepting a
user ID in the request body; the server derives the target from the verified
session JWT. The page and the function still require live-service verification
before release.

## Apple Console and TestFlight sequence

These steps require Apple account access and must be completed by the
operator:

1. Register or confirm the App ID for `com.sagnikdas.medicyn` in the Apple
   Developer account.
2. Create the App Store Connect app record, choosing the final name, primary
   category, age rating, availability, privacy policy URL, support URL, and
   required store metadata. Legal/product owners must supply the answers.
3. Register the iOS Google OAuth client and add the real `GIDClientID` and
   reversed-client-ID URL scheme to `Info.plist`.
4. Configure the iOS Firebase app, APNs authentication, push entitlements,
   and the `GoogleService-Info.plist` required by the push workstream.
5. Provision a distribution signing certificate/profile, archive the Runner
   target, and upload the build with Xcode Organizer or Transporter.
6. Resolve the export-compliance prompt and App Privacy questionnaire for
   that exact build. Keep the submitted answers with the release record.
7. Add internal TestFlight testers, distribute the build, and record tester
   feedback and crash/launch evidence.
8. Before external testing, repeat the real-device launch plan, including
   notification permission denial/recovery, offline reminders, Taken/Snooze,
   lock-screen privacy, timezone behavior, account switching, and deletion.

## Remaining non-repository dependencies

- Apple Developer/App Store Connect account, team, certificates, profiles,
  app record, and export-compliance classification.
- iOS Google OAuth client and Firebase/APNs configuration.
- Public, working privacy, account-deletion, and support URLs; the existing
  Pages URLs need live verification.
- Final branded AppIcon artwork replacing the Flutter placeholder catalog.
- Final App Store screenshots and store copy at the sizes and locales selected
  in App Store Connect.
- Real-device verification of the iOS reminder, push, sign-in, and deletion
  paths after the preceding dependencies are available.
