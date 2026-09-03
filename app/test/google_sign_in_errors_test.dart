import 'package:medicyn/features/auth/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';

void main() {
  test('backs out of the picker is a cancellation', () {
    const e = GoogleSignInException(
      code: GoogleSignInExceptionCode.canceled,
      description: 'activity is cancelled by the user.',
    );
    expect(googleSignInIsUserCancellation(e), isTrue);
    expect(googleSignInCanceledIsStaleAccount(e), isFalse);
  });

  test('account reauth failed is not a cancellation', () {
    const e = GoogleSignInException(
      code: GoogleSignInExceptionCode.canceled,
      description: '[16] Account reauth failed.',
    );
    expect(googleSignInCanceledIsStaleAccount(e), isTrue);
    expect(googleSignInIsUserCancellation(e), isFalse);
  });

  test('a configuration error is not a cancellation', () {
    const e = GoogleSignInException(
      code: GoogleSignInExceptionCode.clientConfigurationError,
      description: 'missing SHA-1',
    );
    expect(googleSignInIsUserCancellation(e), isFalse);
    expect(googleSignInCanceledIsStaleAccount(e), isFalse);
  });
}
