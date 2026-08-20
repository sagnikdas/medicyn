import 'package:flutter/material.dart';

import '../../data/local/database.dart';
import '../capture_ocr/ocr_capture_screen.dart';
import '../consent/consent_purpose.dart';
import '../consent/consent_service.dart';
import '../voice_capture/voice_capture_screen.dart';
import 'review_edit_screen.dart';

/// OCR, optional voice, then the review form. Shared by the patient's home
/// list and the caregiver's remote list so the two paths cannot drift.
///
/// Returns true when a reminder was saved.
Future<bool> pushCaptureThenReview({
  required BuildContext context,
  required AppDatabase db,
  String? ownerUserId,
  String? ownerDisplayName,
}) async {
  final ocrText = await Navigator.of(context).push<String>(
    MaterialPageRoute(builder: (_) => const OcrCaptureScreen()),
  );
  if (ocrText == null || !context.mounted) return false;

  var transcript = '';
  if (ConsentService.instance.isGranted(ConsentPurpose.googleSpeech)) {
    final spoken = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const VoiceCaptureScreen()),
    );
    if (spoken == null || !context.mounted) return false;
    transcript = spoken;
  }

  final saved = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => ReviewEditScreen(
        ocrText: ocrText,
        transcript: transcript,
        db: db,
        ownerUserId: ownerUserId,
        ownerDisplayName: ownerDisplayName,
      ),
    ),
  );
  return saved == true;
}
