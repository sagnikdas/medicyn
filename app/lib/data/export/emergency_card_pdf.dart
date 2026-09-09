import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'emergency_card_data.dart';

// Same tokens as adherence_pdf.dart's palette. Duplicated rather than
// shared: the two PDFs ship on separate branches/PRs and this card is
// short enough that a shared _pdf_theme.dart would be more indirection
// than the few lines it would save.
const _teal = PdfColor.fromInt(0xFF00685F);
const _ink = PdfColor.fromInt(0xFF2B2318);
const _muted = PdfColor.fromInt(0xFF5C4F3B);
const _rule = PdfColor.fromInt(0xFFD9CBAA);
const _paper = PdfColor.fromInt(0xFFFBF7EC);
const _banner = PdfColor.fromInt(0xFFEDE4CE);
const _stripe = PdfColor.fromInt(0xFFF6F0E1);
const _alert = PdfColor.fromInt(0xFFBA1A1A);
const _alertBg = PdfColor.fromInt(0xFFFFDAD6);

const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// Builds a single printable A4 page: the facts a first responder or a new
/// clinician needs at a glance. Helvetica, same reasoning as the adherence
/// report -- a printed or faxed copy must not depend on an embedded font.
Future<List<int>> buildEmergencyCardPdf(EmergencyCardData data) async {
  final doc = pw.Document(title: 'Medicyn emergency card', author: 'Medicyn');
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(48, 40, 48, 48),
      theme: pw.ThemeData.withFont(
        base: pw.Font.helvetica(),
        bold: pw.Font.helveticaBold(),
        italic: pw.Font.helveticaOblique(),
        boldItalic: pw.Font.helveticaBoldOblique(),
      ),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _header(data),
          pw.SizedBox(height: 16),
          _disclaimer(),
          pw.SizedBox(height: 20),
          _fact('Blood group', data.bloodGroup),
          pw.SizedBox(height: 12),
          _allergyFact(data.allergies, data.allergiesSevere),
          pw.SizedBox(height: 12),
          _fact('Conditions', data.conditions),
          if (data.notes.isNotEmpty) ...[
            pw.SizedBox(height: 12),
            _fact('Notes', data.notes),
          ],
          pw.SizedBox(height: 12),
          _fact('Caregiver', _caregiverLine(data)),
          if (data.insuranceNumber.isNotEmpty ||
              data.nationalId.isNotEmpty ||
              data.healthCardNumber.isNotEmpty) ...[
            pw.SizedBox(height: 20),
            _sectionTitle('Identification'),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: _fact('Insurance number', data.insuranceNumber),
                ),
                pw.SizedBox(width: 16),
                pw.Expanded(child: _fact('National ID', data.nationalId)),
                pw.SizedBox(width: 16),
                pw.Expanded(
                  child: _fact('Health card no.', data.healthCardNumber),
                ),
              ],
            ),
          ],
          pw.SizedBox(height: 20),
          _sectionTitle('Current medicines'),
          if (data.medicines.isEmpty)
            _body('No medicines on this device.')
          else
            _table(
              headers: const ['Medicine', 'Dose'],
              rows: [
                for (final row in data.medicines)
                  [row.title, row.dose.isEmpty ? '-' : row.dose],
              ],
            ),
          pw.Spacer(),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.only(top: 10),
            decoration: const pw.BoxDecoration(
              border: pw.Border(top: pw.BorderSide(color: _rule, width: 1)),
            ),
            child: pw.Text(
              'In an emergency, call your local emergency number first. '
              'Medicyn  ·  Not a medical record.',
              style: const pw.TextStyle(fontSize: 8, color: _muted),
            ),
          ),
        ],
      ),
    ),
  );
  return doc.save();
}

pw.Widget _header(EmergencyCardData data) {
  return pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.fromLTRB(16, 14, 16, 14),
    decoration: const pw.BoxDecoration(
      color: _banner,
      border: pw.Border(bottom: pw.BorderSide(color: _rule, width: 1)),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'MEDICYN',
          style: pw.TextStyle(
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
            letterSpacing: 1.4,
            color: _teal,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'Emergency card',
          style: pw.TextStyle(
            fontSize: 20,
            fontWeight: pw.FontWeight.bold,
            color: _ink,
          ),
        ),
        pw.SizedBox(height: 6),
        pw.Text(
          [
            if (data.patientName != null) data.patientName,
            'Generated ${_shortDate(data.generatedAt)}',
          ].whereType<String>().join('  ·  '),
          style: const pw.TextStyle(fontSize: 10, color: _muted),
        ),
      ],
    ),
  );
}

pw.Widget _disclaimer() {
  return pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.all(10),
    decoration: pw.BoxDecoration(
      color: _paper,
      border: pw.Border.all(color: _rule),
    ),
    child: pw.Text(
      'Patient-reported from this Medicyn device, kept for quick reference '
      'only. Confirm anything critical with the person or their caregiver '
      'when possible.',
      style: const pw.TextStyle(fontSize: 9, color: _ink, lineSpacing: 2),
    ),
  );
}

pw.Widget _fact(String label, String value) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        label.toUpperCase(),
        style: pw.TextStyle(
          fontSize: 9,
          fontWeight: pw.FontWeight.bold,
          letterSpacing: 0.6,
          color: _teal,
        ),
      ),
      pw.SizedBox(height: 3),
      pw.Text(
        value.isEmpty ? 'Not recorded' : value,
        style: pw.TextStyle(fontSize: 12, color: value.isEmpty ? _muted : _ink),
      ),
    ],
  );
}

/// The allergies fact, called out in a red-bordered box when marked severe
/// -- the one field on this card where a first responder reading past it
/// too quickly is dangerous.
pw.Widget _allergyFact(String allergies, bool severe) {
  if (!severe) return _fact('Allergies', allergies);
  return pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.all(10),
    decoration: pw.BoxDecoration(
      color: _alertBg,
      border: pw.Border.all(color: _alert, width: 1),
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'ALLERGIES -- SEVERE / ANAPHYLAXIS RISK',
          style: pw.TextStyle(
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
            letterSpacing: 0.6,
            color: _alert,
          ),
        ),
        pw.SizedBox(height: 3),
        pw.Text(
          allergies.isEmpty ? 'Not recorded' : allergies,
          style: pw.TextStyle(fontSize: 12, color: _ink),
        ),
      ],
    ),
  );
}

String _caregiverLine(EmergencyCardData data) {
  final phone = data.caregiverPhone;
  if (phone == null) return 'Not set';
  final name = data.caregiverName;
  return name == null ? phone : '$name  ·  $phone';
}

pw.Widget _sectionTitle(String text) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 8),
    child: pw.Text(
      text.toUpperCase(),
      style: pw.TextStyle(
        fontSize: 10,
        fontWeight: pw.FontWeight.bold,
        letterSpacing: 0.8,
        color: _teal,
      ),
    ),
  );
}

pw.Widget _body(String text) {
  return pw.Text(text, style: const pw.TextStyle(fontSize: 10, color: _ink));
}

pw.Widget _table({
  required List<String> headers,
  required List<List<String>> rows,
}) {
  return pw.TableHelper.fromTextArray(
    headers: headers,
    data: rows,
    headerStyle: pw.TextStyle(
      fontSize: 8,
      fontWeight: pw.FontWeight.bold,
      color: _ink,
    ),
    cellStyle: const pw.TextStyle(fontSize: 9, color: _ink),
    headerDecoration: const pw.BoxDecoration(color: _banner),
    oddRowDecoration: const pw.BoxDecoration(color: _stripe),
    border: pw.TableBorder.all(color: _rule, width: 0.4),
    cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
    cellAlignments: {
      for (var i = 0; i < headers.length; i++) i: pw.Alignment.centerLeft,
    },
    headerAlignments: {
      for (var i = 0; i < headers.length; i++) i: pw.Alignment.centerLeft,
    },
  );
}

String _shortDate(DateTime value) {
  final local = value.toLocal();
  return '${local.day} ${_months[local.month - 1]} ${local.year}';
}
