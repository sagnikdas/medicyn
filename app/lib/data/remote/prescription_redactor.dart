import 'label_redactor.dart';

/// Strips patient/hospital/clinician identifiers from OCR'd prescription or
/// discharge-document text *before* it is sent to `parse-prescription`.
///
/// Runs [redactPharmacyLabel]'s existing patterns as a base pass -- name,
/// address, date of birth, phone, Rx number, email, NPI, DEA are all still
/// relevant on a prescription -- then adds patterns specific to a clinical
/// document that a dispensed pharmacy label has no reason to carry: the
/// hospital/clinic name, ward/department, medical record number, and the
/// treating clinician's identity. Diagnosis text is stripped too: nothing
/// downstream needs it to fill in a reminder, and it is the single most
/// sensitive field a prescription or discharge document carries.
///
/// Same best-effort caveat as [redactPharmacyLabel]: this is pattern
/// matching, not a guarantee against a weird layout. In particular, a
/// hospital letterhead is very often the first line or two of unlabeled
/// free text at the top of the page rather than a `Hospital:`-prefixed
/// line -- reliably telling that apart from a drug-name line without a lot
/// of false positives is not attempted here, and is a known gap rather
/// than something this function claims to solve.
String redactPrescriptionDocument(String ocrText) {
  if (ocrText.isEmpty) return ocrText;
  var text = redactPharmacyLabel(ocrText);
  text = _redactClinicalLabeledValues(text);
  return text;
}

/// `Label: value` lines whose label names a hospital, clinical identifier,
/// or clinician -- the prescription-specific counterpart to
/// [redactPharmacyLabel]'s `_colonLabeled`. Same
/// `(generic|brand|drug|medicine)` exemption prefix, so a "Generic Name:"
/// line is never caught here either.
final _clinicalLabeled = RegExp(
  r'^(\s*(?:(generic|brand|drug|medicine)\s+)?'
  r'(hospital|clinic|nursing\s+home|ward|department|dept\.?|'
  r'mrn|medical\s+record(?:\s*(?:no\.?|number|#))?|uhid|'
  r'patient\s*id|'
  r'diagnosis|dx|impression|'
  r'consultant|treating\s+doctor|attending(?:\s+physician)?|'
  r'admitting\s+doctor|referred\s+by)'
  r'\s*[:#]\s*)(.*)$',
  caseSensitive: false,
  multiLine: true,
);

String _redactClinicalLabeledValues(String text) {
  return text.replaceAllMapped(_clinicalLabeled, (match) {
    // Group 2 is the "generic/brand/drug/medicine" prefix. When present
    // this is a medicine-name field, never one of the labels above.
    if (match.group(2) != null) return match.group(0)!;
    final value = match.group(3)!.trim();
    if (value.isEmpty) return match.group(0)!;
    return '${match.group(1)}$kRedactedLabelToken';
  });
}
