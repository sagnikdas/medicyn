import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/review_edit/parsed_medicine.dart';

class MedicineParseException implements Exception {
  final String message;
  MedicineParseException(this.message);
  @override
  String toString() => message;
}

/// Calls the `parse-medicine` edge function, which does the actual OCR/voice
/// -> structured-fields work server-side via Claude. The API key never
/// touches this device — only the raw text does, and only for this one call.
class MedicineParser {
  Future<ParsedMedicine> parse({required String ocrText, required String transcript}) async {
    final FunctionResponse response;
    try {
      response = await Supabase.instance.client.functions.invoke(
        'parse-medicine',
        body: {'ocrText': ocrText, 'transcript': transcript},
      );
    } on FunctionException catch (e) {
      throw MedicineParseException(messageForParseMedicineError(e.details, status: e.status));
    } catch (e) {
      throw MedicineParseException('Could not reach the server. Check your connection and try again.');
    }

    final data = response.data;
    if (data is! Map || data['success'] != true || data['data'] is! Map) {
      throw MedicineParseException(messageForParseMedicineError(data));
    }
    return ParsedMedicine.fromJson((data['data'] as Map).cast<String, dynamic>());
  }
}

/// Turns the function's machine-readable `error` into a sentence the review
/// screen can show. `quota_exceeded` is a real limit, not a parse failure,
/// so it gets its own wording; everything else stays the same generic
/// "could not read that" the form already recovered from with Fill in manually.
String messageForParseMedicineError(Object? payload, {int? status}) {
  if (_errorCode(payload) == 'quota_exceeded') {
    return "You've scanned quite a few times today. Try again tomorrow.";
  }
  if (status == 0 || status == 503 || _errorCode(payload) == 'quota_unavailable') {
    return 'Could not reach the server. Check your connection and try again.';
  }
  return 'Could not read that. Try again or fill it in yourself.';
}

String? _errorCode(Object? payload) {
  if (payload is Map && payload['error'] is String) {
    return payload['error'] as String;
  }
  return null;
}
