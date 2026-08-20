import 'package:url_launcher/url_launcher.dart';

/// Digits the phone app will accept, or null if [raw] is not a number
/// worth offering a Call button for.
///
/// Keeps a leading `+` and digits only. Shorter than eight digits is almost
/// never a real mobile number and would still open the dialer, which looks
/// like the app is broken rather than the field being empty.
String? dialablePhone(String? raw) {
  if (raw == null) return null;
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;

  final out = StringBuffer();
  for (final unit in trimmed.runes) {
    final ch = String.fromCharCode(unit);
    if (ch == '+' && out.isEmpty) {
      out.write(ch);
      continue;
    }
    if (unit >= 48 && unit <= 57) out.write(ch);
  }
  final cleaned = out.toString();
  final digits = cleaned.startsWith('+') ? cleaned.substring(1) : cleaned;
  if (digits.length < 8 || digits.length > 15) return null;
  return cleaned;
}

/// Opens the system dialer with [phone]. Uses `tel:` / ACTION_DIAL, which
/// does not need the CALL_PHONE permission.
Future<bool> openDialer(String phone) {
  final uri = Uri(scheme: 'tel', path: phone);
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}
