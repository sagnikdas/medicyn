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
    } catch (e) {
      throw MedicineParseException('Could not reach the server. Check your connection and try again.');
    }

    final data = response.data;
    if (data is! Map || data['success'] != true || data['data'] is! Map) {
      throw MedicineParseException('Could not read that. Try again or fill it in yourself.');
    }
    return ParsedMedicine.fromJson((data['data'] as Map).cast<String, dynamic>());
  }
}
