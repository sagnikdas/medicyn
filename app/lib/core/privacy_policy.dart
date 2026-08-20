import 'package:url_launcher/url_launcher.dart';

/// Stable URL of the published policy. Sign-in and Settings both open this
/// rather than a copy that could drift.
const privacyPolicyUrl =
    'https://github.com/sagnikdas/dosely/blob/main/PRIVACY.md';

/// Opens [privacyPolicyUrl] in the device's browser so the user is reading
/// the published document, not an in-app snapshot.
Future<void> openPrivacyPolicy() {
  return launchUrl(
    Uri.parse(privacyPolicyUrl),
    mode: LaunchMode.externalApplication,
  );
}
