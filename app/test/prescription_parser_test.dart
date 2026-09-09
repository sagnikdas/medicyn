import 'package:medicyn/data/remote/prescription_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('quota_exceeded is a calm limit, not a parse failure', () {
    expect(
      messageForParsePrescriptionError({
        'success': false,
        'data': null,
        'error': 'quota_exceeded',
      }),
      "You've scanned quite a few prescriptions today. Try again tomorrow.",
    );
  });

  test('quota_unavailable is a connection problem, not a bad document', () {
    expect(
      messageForParsePrescriptionError(
        {'error': 'quota_unavailable'},
        status: 503,
      ),
      'Could not reach the server. Check your connection and try again.',
    );
  });

  test('any other function error keeps the generic recovery wording', () {
    expect(
      messageForParsePrescriptionError({'error': 'empty_input'}, status: 400),
      'Could not read that. Try again or fill it in yourself.',
    );
  });
}
