import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'adherence_report.dart';

const _teal = PdfColor.fromInt(0xFF00685F);
const _ink = PdfColor.fromInt(0xFF2B2318);
const _muted = PdfColor.fromInt(0xFF5C4F3B);
const _rule = PdfColor.fromInt(0xFFD9CBAA);
const _paper = PdfColor.fromInt(0xFFFBF7EC);
const _banner = PdfColor.fromInt(0xFFEDE4CE);
// DESIGN.md's surface-container-low: one tonal step above the page, used
// only for zebra striping so a six-row table stays scannable without a
// second border weight.
const _stripe = PdfColor.fromInt(0xFFF6F0E1);
// The same two tokens DayDoseStyle.color resolves scheme.error / scheme.outline
// to for Missed / Not recorded, so the printed chart and the on-screen one
// agree on what each mark means.
const _missed = PdfColor.fromInt(0xFFBA1A1A);
const _notRecorded = PdfColor.fromInt(0xFF8A7A5E);

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

/// Builds an A4 PDF a clinic can print. Helvetica on purpose: a faxed chart
/// must survive without embedding a variable font, and it must not look
/// like a screenshot of the app.
Future<List<int>> buildAdherencePdf(AdherenceReport report) async {
  final doc = pw.Document(title: 'Medicyn adherence report', author: 'Medicyn');
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(48, 40, 48, 48),
      theme: pw.ThemeData.withFont(
        base: pw.Font.helvetica(),
        bold: pw.Font.helveticaBold(),
        italic: pw.Font.helveticaOblique(),
        boldItalic: pw.Font.helveticaBoldOblique(),
      ),
      footer: (context) => pw.Text(
        'Page ${context.pageNumber} of ${context.pagesCount}  ·  Medicyn  ·  Not a medical record',
        style: const pw.TextStyle(fontSize: 8, color: _muted),
      ),
      build: (context) => [
        _header(report),
        pw.SizedBox(height: 16),
        _disclaimer(),
        pw.SizedBox(height: 20),
        _sectionTitle('Current medicines'),
        if (report.currentSchedules.isEmpty)
          _body('No medicines on this device.')
        else
          _table(
            headers: const ['Medicine', 'Dose', 'Schedule', 'Status'],
            rows: [
              for (final row in report.currentSchedules)
                [
                  row.title,
                  row.dose.isEmpty ? '-' : row.dose,
                  row.scored ? row.schedule : '${row.schedule} (not scored)',
                  row.status,
                ],
            ],
          ),
        pw.SizedBox(height: 20),
        _sectionTitle('Adherence'),
        _body(
          report.overall.expected == 0
              ? 'Nothing was due in this window, so no percentage is shown.'
              : '${report.overall.taken} of ${report.overall.expected} due doses marked taken'
                    ' (${_pct(report.overall.taken, report.overall.expected)}).',
        ),
        pw.SizedBox(height: 4),
        _mutedLine(
          '${_shortDate(report.rangeStart)} - ${_shortDate(report.rangeEndInclusive)}'
          '  ·  As-needed (PRN) medicines are listed above but never counted here.',
        ),
        pw.SizedBox(height: 12),
        _subhead('By week'),
        _table(
          headers: const ['Week of', 'Taken', 'Due', '%'],
          rightAlign: const {1, 2, 3},
          rows: [
            for (final week in report.byWeek)
              [
                _shortDate(week.weekStart),
                '${week.counts.taken}',
                '${week.counts.expected}',
                week.counts.expected == 0
                    ? '-'
                    : _pct(week.counts.taken, week.counts.expected),
              ],
          ],
        ),
        pw.SizedBox(height: 12),
        _subhead('By medicine'),
        if (report.byMedicine.isEmpty)
          _body('No scheduled doses were due in this window.')
        else
          _table(
            headers: const ['Medicine', 'Taken', 'Due', '%'],
            rightAlign: const {1, 2, 3},
            rows: [
              for (final row in report.byMedicine)
                [
                  row.name,
                  '${row.taken}',
                  '${row.expected}',
                  row.expected == 0 ? '-' : _pct(row.taken, row.expected),
                ],
            ],
          ),
        pw.SizedBox(height: 20),
        // Both lists are "nothing to report" on the common good-adherence
        // report -- the two full sections below (title, explanation, table)
        // spent that document's entire second page saying so twice. One
        // compact line replaces both only when neither has anything to add;
        // real content still gets the full, separately-titled treatment.
        if (report.unanswered.isEmpty && report.corrections.isEmpty)
          _mutedLine('No unanswered doses or correction notes in this window.')
        else ...[
          _sectionTitle('Unanswered doses'),
          if (report.unanswered.isEmpty)
            _body('None in this window.')
          else ...[
            _table(
              headers: const ['When', 'Medicine', 'Status'],
              cellBuilder: _unansweredStatusCell,
              rows: [
                for (final row in report.unanswered)
                  [
                    _dateTime(row.scheduledAt),
                    row.medicineName,
                    row.statusLabel,
                  ],
              ],
            ),
            if (report.unansweredOmitted > 0) ...[
              pw.SizedBox(height: 6),
              _mutedLine(
                'And ${report.unansweredOmitted} more unanswered dose'
                '${report.unansweredOmitted == 1 ? '' : 's'} not printed.',
              ),
            ],
          ],
          pw.SizedBox(height: 20),
          _sectionTitle('Correction notes'),
          _mutedLine(
            'The original Taken / Missed / Snoozed mark is never edited. '
            'A note here is a later correction from the person or caregiver.',
          ),
          pw.SizedBox(height: 8),
          if (report.corrections.isEmpty)
            _body('None in this window.')
          else
            _table(
              headers: const ['When', 'Medicine', 'Note'],
              rows: [
                for (final row in report.corrections)
                  [_dateTime(row.scheduledAt), row.medicineName, row.note],
              ],
            ),
        ],
      ],
    ),
  );
  return doc.save();
}

/// Status column for the unanswered-doses table: a glyph before the word,
/// the same triangle/ellipsis-and-color pairing DayDoseStyle uses on
/// screen for Missed / Not recorded, so the printed chart and the on-screen
/// one speak the same mark language. Only those two statuses ever reach
/// this table (see AdherenceReport.build), but an unrecognised label still
/// falls back to plain text rather than guessing at a glyph for it.
pw.Widget? _unansweredStatusCell(int index, dynamic data, int rowNum) {
  if (index != 2 || rowNum == 0) return null;
  final label = data as String;
  final pw.Widget? glyph = switch (label) {
    'Missed' => _triangleGlyph(),
    'Not recorded' => _ellipsisGlyph(),
    _ => null,
  };
  if (glyph == null) {
    return pw.Text(label, style: const pw.TextStyle(fontSize: 9, color: _ink));
  }
  return pw.Row(
    mainAxisSize: pw.MainAxisSize.min,
    crossAxisAlignment: pw.CrossAxisAlignment.center,
    children: [
      glyph,
      pw.SizedBox(width: 5),
      pw.Text(label, style: const pw.TextStyle(fontSize: 9, color: _ink)),
    ],
  );
}

pw.Widget _triangleGlyph() {
  return pw.CustomPaint(
    size: const PdfPoint(8, 8),
    painter: (canvas, size) {
      canvas
        ..setColor(_missed)
        ..moveTo(size.x / 2, size.y)
        ..lineTo(0, 0)
        ..lineTo(size.x, 0)
        ..closePath()
        ..fillPath();
    },
  );
}

pw.Widget _ellipsisGlyph() {
  return pw.CustomPaint(
    size: const PdfPoint(16, 8),
    painter: (canvas, size) {
      canvas.setColor(_notRecorded);
      for (final cx in [2.0, 8.0, 14.0]) {
        canvas
          ..drawEllipse(cx, size.y / 2, 1.5, 1.5)
          ..fillPath();
      }
    },
  );
}

pw.Widget _header(AdherenceReport report) {
  return pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.fromLTRB(16, 14, 16, 14),
    decoration: const pw.BoxDecoration(
      color: _banner,
      // A hairline under the block, not a colored accent bar down the side:
      // the same "structural, not brand" role DESIGN.md gives the app's own
      // top-bar hairline. Teal already carries the brand mark in the text.
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
          'Adherence report',
          style: pw.TextStyle(
            fontSize: 20,
            fontWeight: pw.FontWeight.bold,
            color: _ink,
          ),
        ),
        pw.SizedBox(height: 6),
        pw.Text(
          [
            if (report.patientName != null) report.patientName,
            'Generated ${_shortDate(report.generatedAt)}',
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
      'Patient-reported from this Medicyn device. Not a medical record and '
      'not a clinical database. A blank slot means the dose was not marked '
      'taken here - it does not prove the tablet was skipped.',
      style: const pw.TextStyle(fontSize: 9, color: _ink, lineSpacing: 2),
    ),
  );
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

pw.Widget _subhead(String text) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 6),
    child: pw.Text(
      text,
      style: pw.TextStyle(
        fontSize: 11,
        fontWeight: pw.FontWeight.bold,
        color: _ink,
      ),
    ),
  );
}

pw.Widget _body(String text) {
  return pw.Text(text, style: const pw.TextStyle(fontSize: 10, color: _ink));
}

pw.Widget _mutedLine(String text) {
  return pw.Text(text, style: const pw.TextStyle(fontSize: 9, color: _muted));
}

pw.Widget _table({
  required List<String> headers,
  required List<List<String>> rows,
  Set<int> rightAlign = const {},
  pw.OnCell? cellBuilder,
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
    // A step above the page per odd row: six-plus rows of otherwise-
    // identical white cells is where a table stops being scannable at a
    // glance, which is exactly the failure mode a clinician skimming this
    // during an appointment can't afford.
    oddRowDecoration: const pw.BoxDecoration(color: _stripe),
    border: pw.TableBorder.all(color: _rule, width: 0.4),
    cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
    // Column 0's header used the package default (centered) while every
    // body cell was left-aligned -- a heading over its own column should
    // agree with the text beneath it, so every column gets one explicit
    // alignment shared by header and cells alike.
    cellAlignments: {
      for (var i = 0; i < headers.length; i++)
        i: rightAlign.contains(i)
            ? pw.Alignment.centerRight
            : pw.Alignment.centerLeft,
    },
    headerAlignments: {
      for (var i = 0; i < headers.length; i++)
        i: rightAlign.contains(i)
            ? pw.Alignment.centerRight
            : pw.Alignment.centerLeft,
    },
    cellBuilder: cellBuilder,
  );
}

String _pct(int taken, int expected) {
  if (expected == 0) return '-';
  return '${((taken / expected) * 100).round()}%';
}

String _shortDate(DateTime value) {
  final local = value.toLocal();
  return '${local.day} ${_months[local.month - 1]} ${local.year}';
}

String _dateTime(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${_shortDate(local)} $hour:$minute';
}
