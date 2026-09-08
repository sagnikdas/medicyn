import 'dart:io';
import 'dart:ui' show Rect;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../local/database.dart';
import 'emergency_card_data.dart';
import 'emergency_card_pdf.dart';

/// Builds the printable emergency card PDF and opens the system share sheet
/// -- the same "print or hand your phone to someone" path as the doctor's
/// adherence report.
class EmergencyCardExportService {
  EmergencyCardExportService(this._db);

  final AppDatabase _db;

  Future<void> exportAndShare({
    DateTime? now,
    Rect? sharePositionOrigin,
  }) async {
    final data = await EmergencyCardData.fromDatabase(_db, now: now);
    final bytes = await buildEmergencyCardPdf(data);
    final dir = await getTemporaryDirectory();
    final stamp = data.generatedAt
        .toUtc()
        .toIso8601String()
        .replaceAll(':', '')
        .replaceAll('.', '');
    final file = File(p.join(dir.path, 'medicyn-emergency-card-$stamp.pdf'));
    await file.writeAsBytes(bytes, flush: true);
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/pdf')],
          subject: 'Medicyn emergency card',
          sharePositionOrigin: sharePositionOrigin,
        ),
      );
    } finally {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {
        // Best-effort cleanup. The PDF was already handed to the share sheet.
      }
    }
  }
}
