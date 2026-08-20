/// Strips pharmacy-label identifiers from OCR text *before* it is sent to
/// `parse-medicine`. A dispensed label routinely carries the patient's name,
/// address, date of birth, prescriber and Rx number — none of which Claude
/// needs to fill in a reminder, and all of which would otherwise leave the
/// phone. Drug name, strength, form, directions, quantity and expiry are
/// left intact.
///
/// This is best-effort pattern matching, not a guarantee against a weird
/// layout. A modified client can skip it; the official app cannot.
const kRedactedLabelToken = '[redacted]';

/// Returns [ocrText] with identifier fields replaced by [kRedactedLabelToken].
String redactPharmacyLabel(String ocrText) {
  if (ocrText.isEmpty) return ocrText;
  var text = ocrText;
  text = _redactLabeledValues(text);
  text = _redactRxNumbers(text);
  text = _redactInlineIdentifiers(text);
  return text;
}

/// `Label: value` lines whose label names a person or their identifiers.
///
/// `Generic Name:` / `Brand Name:` / `Drug Name:` / `Medicine Name:` are
/// left alone — those are the medicine, which is the whole point of the
/// call. `Rx only` is a legal statement, not a prescription number, and is
/// handled by requiring digits in the Rx pass below.
final _colonLabeled = RegExp(
  r'^(\s*(?:(generic|brand|drug|medicine)\s+)?'
  r'(patient(?:\s+(?:name|id))?|name|address|addr\.?|'
  r'd\.?o\.?b\.?|date\s+of\s+birth|birth(?:\s*date)?|'
  r'age(?:\s*/\s*sex)?|'
  r'phone(?:\s*(?:no\.?|number))?|tel(?:ephone)?|mobile|cell|'
  r'prescriber|prescribed\s+by|physician|doctor)'
  r'\s*[:#]\s*)(.*)$',
  caseSensitive: false,
  multiLine: true,
);

String _redactLabeledValues(String text) {
  return text.replaceAllMapped(_colonLabeled, (match) {
    // Group 2 is the "generic/brand/drug/medicine" prefix. When it is
    // present this is a medicine name field, not a patient name.
    if (match.group(2) != null) return match.group(0)!;
    final value = match.group(3)!.trim();
    if (value.isEmpty) return match.group(0)!;
    return '${match.group(1)}$kRedactedLabelToken';
  });
}

/// `Rx 1234567`, `Rx# AB-12`, `Prescription No: 99` — but not `Rx only`.
final _rxLabeled = RegExp(
  r'^(\s*(?:rx\s*(?:#|no\.?|number|id)?|prescription(?:\s*(?:#|no\.?|number))?)\s*[:#]?\s+)(\S.*)$',
  caseSensitive: false,
  multiLine: true,
);

final _rxInline = RegExp(
  r'\bRx\s*#\s*[A-Za-z0-9-]{4,}\b',
  caseSensitive: false,
);

String _redactRxNumbers(String text) {
  var out = text.replaceAllMapped(_rxLabeled, (match) {
    final value = match.group(2)!;
    // "Rx only" has no digits. A real Rx number always does.
    if (!RegExp(r'\d').hasMatch(value)) return match.group(0)!;
    return '${match.group(1)}$kRedactedLabelToken';
  });
  out = out.replaceAll(_rxInline, 'Rx# $kRedactedLabelToken');
  return out;
}

final _email = RegExp(r'\b[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}\b');

/// US `(555) 123-4567` / `555-123-4567` and Indian `+91 9876543210`.
final _phone = RegExp(
  r'(?:'
  r'\+91[\s.\-]?\d{10}'
  r'|\(\d{3}\)[\s.\-]?\d{3}[\s.\-]?\d{4}'
  r'|\b\d{3}[-.]\d{3}[-.]\d{4}\b'
  r')',
);

final _npi = RegExp(r'\bNPI\s*[:#]?\s*\d{10}\b', caseSensitive: false);

final _dea = RegExp(r'\bDEA\s*[:#]?\s*[A-Z]{2}\d{7}\b', caseSensitive: false);

/// `123 Main Street`, `12 MG Road`. `Dr.` as a street suffix is drive, not
/// a physician — those lines are unlabeled `Dr. Sharma` and are left alone
/// on purpose, because `Dr. Reddy's` is a manufacturer line we must keep.
final _street = RegExp(
  r"\b\d{1,5}\s+[A-Za-z][A-Za-z0-9.'\-]*"
  r"(?:\s+[A-Za-z][A-Za-z0-9.'\-]*){0,4}\s+"
  r"(?:street|st\.?|avenue|ave\.?|road|rd\.?|lane|ln\.?|drive|dr\.?|"
  r"boulevard|blvd\.?|way|court|ct\.?|place|pl\.?|circle|cir\.?|"
  r"highway|hwy\.?|parkway|pkwy\.?|nagar|marg)\b",
  caseSensitive: false,
);

/// `Springfield CA 90210` / `Springfield, CA 90210`.
final _cityStateZip = RegExp(
  r'\b[A-Z][a-z]+(?:\s+[A-Z][a-z]+)?,?\s+[A-Z]{2}\s+\d{5}(?:-\d{4})?\b',
);

String _redactInlineIdentifiers(String text) {
  var out = text;
  out = out.replaceAll(_email, kRedactedLabelToken);
  out = out.replaceAll(_phone, kRedactedLabelToken);
  out = out.replaceAll(_npi, kRedactedLabelToken);
  out = out.replaceAll(_dea, kRedactedLabelToken);
  out = out.replaceAll(_street, kRedactedLabelToken);
  out = out.replaceAll(_cityStateZip, kRedactedLabelToken);
  return out;
}
