# Medicyn iOS UI adaptation

**Review date:** 5 September 2026

## Decision

Medicyn keeps one shared visual system — the Bedside Chart colors, typography,
cards, dose glyphs, and content hierarchy — while using native interaction
idioms where users notice them. Android behavior remains on the existing
Material path. iOS behavior is selected through Flutter's platform-adaptive
widgets and `ThemeData.platform`, so the split is testable without duplicating
screens.

## Changes made

| Interaction | Android | iOS |
|---|---|---|
| Primary navigation | Existing Medicyn Material bottom bar | `CupertinoTabBar` with the same four destinations and state |
| Boolean settings | Material `Switch` | `CupertinoSwitch` via `SwitchListTile.adaptive` |
| Numeric settings | Material slider | Adaptive slider |
| Confirmation dialogs | Material dialog styling | Adaptive/Cupertino dialog styling |
| Capture choices | Material bottom sheet | Cupertino action sheet |
| Reminder pause choices | Material bottom sheet | Cupertino action sheet |
| Reminder time | Material time picker | Cupertino time picker with Done action |
| Explicit back/close controls | Arrow back | iOS chevron back affordance |
| Page transitions and app-bar titles | Material transition/leading title | Cupertino transition/centered title |

The implementation is concentrated in
[`medicyn_platform.dart`](../../app/lib/core/widgets/medicyn_platform.dart) and
[`medicyn_chrome.dart`](../../app/lib/core/widgets/medicyn_chrome.dart), with
feature-level branching only where the interaction model genuinely differs.

## Validation

- `flutter analyze --no-pub`: passed.
- Full Flutter test suite: 460 tests passed.
- Platform-adaptive widget tests: 4 tests passed.
- iOS 18.3 x86_64 simulator: app launched and rendered the Today screen with
  the Cupertino bottom navigation bar.
- iOS device release compilation: `flutter build ios --release --no-codesign`
  passed and produced `build/ios/iphoneos/Runner.app`.

## Remaining iOS-specific release work

The iOS 26.2 SDK is installed, but Apple did not provide an iOS 26.2 runtime
for this Xcode installation; iOS 26.3.1 is the available compatible runtime.
The iOS 26 simulator build is blocked by the current vendored Google ML Kit
framework: it contains an x86_64 simulator slice and an arm64 device slice,
but not an arm64 simulator slice. An Apple-Silicon iOS 26 simulator therefore
cannot link it. This is a dependency/toolchain blocker, not a Flutter UI
blocker.

Before TestFlight, validate on a signed physical iPhone: camera/OCR, speech,
local notifications and action buttons, permission prompts, Dynamic Type,
dark mode, VoiceOver, and the encrypted database runtime (`PRAGMA key`).

One cleanup item remains: move the brand mark from the Android resource path
to a shared Flutter branding asset before store asset finalization. It is not
currently a runtime blocker because Flutter bundles the declared asset path.
