import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/review_prescription/parsed_prescription.dart';
import 'edge_function_errors.dart';
import 'prescription_redactor.dart';

class PrescriptionParseException implements Exception {
  final String message;
  PrescriptionParseException(this.message);
  @override
  String toString() => message;
}

/// Calls the `parse-prescription` edge function, which does the actual
/// OCR-text -> structured medicines/care-items work server-side via Claude.
/// The API key never touches this device. Only text leaves it, and identifier
/// fields (patient, hospital, clinician, MRN, diagnosis) are stripped first
/// -- see [redactPrescriptionDocument].
class PrescriptionParser {
  Future<ParsedPrescription> parse({required String ocrText}) async {
    final FunctionResponse response;
    try {
      response = await Supabase.instance.client.functions.invoke(
        'parse-prescription',
        body: {'ocrText': redactPrescriptionDocument(ocrText)},
      );
    } on FunctionException catch (e) {
      throw PrescriptionParseException(
        messageForParsePrescriptionError(e.details, status: e.status),
      );
    } catch (e) {
      throw PrescriptionParseException(
        'Could not reach the server. Check your connection and try again.',
      );
    }

    final data = response.data;
    if (data is! Map || data['success'] != true || data['data'] is! Map) {
      throw PrescriptionParseException(messageForParsePrescriptionError(data));
    }
    return ParsedPrescription.fromJson(
      (data['data'] as Map).cast<String, dynamic>(),
    );
  }
}

/// Turns the function's machine-readable `error` into a sentence the review
/// screen can show. `quota_exceeded` is a real limit, not a parse failure --
/// worded for a prescription scan specifically, since it's a rarer action
/// than a routine label scan and carries its own, tighter daily cap.
String messageForParsePrescriptionError(Object? payload, {int? status}) =>
    messageForEdgeFunctionError(
      payload,
      status: status,
      quotaExceededMessage:
          "You've scanned quite a few prescriptions today. Try again tomorrow.",
    );
