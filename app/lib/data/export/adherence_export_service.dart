import 'dart:io';
import 'dart:ui' show Rect;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../features/auth/auth_service.dart';
import '../../features/care/care_service.dart';
import '../local/database.dart';
import 'adherence_pdf.dart';
import 'adherence_report.dart';

/// Builds the 4-week clinician PDF and opens the system share sheet.
class AdherenceExportService {
  AdherenceExportService(this._db);

  final AppDatabase _db;

  Future<void> exportAndShare({
    DateTime? now,
    Rect? sharePositionOrigin,
  }) async {
    final report = await AdherenceReport.fromDatabase(
      _db,
      now: now,
      patientName: await _ownDisplayName(),
    );
    final bytes = await buildAdherencePdf(report);
    final dir = await getTemporaryDirectory();
    final stamp = report.generatedAt
        .toUtc()
        .toIso8601String()
        .replaceAll(':', '')
        .replaceAll('.', '');
    final file = File(p.join(dir.path, 'medicyn-adherence-$stamp.pdf'));
    await file.writeAsBytes(bytes, flush: true);
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/pdf')],
          subject: 'Medicyn adherence report',
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

  /// A clinic PDF should carry a person's name, not a login email.
  Future<String?> _ownDisplayName() async {
    try {
      final id = AuthService.instance.currentUser?.id;
      if (id == null) return null;
      final profile = await CareService.instance.profile(id);
      return profile?.displayName;
    } catch (_) {
      return null;
    }
  }
}
