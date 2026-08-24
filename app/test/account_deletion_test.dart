import 'package:dosely/core/account_deletion.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the Play web URL points at the GitHub-rendered deletion page', () {
    expect(
      deleteAccountWebUrl,
      'https://github.com/sagnikdas/dosely/blob/main/docs/play-store/delete-account.md',
    );
  });

  test('maps not_authenticated to a sign-in-again message', () {
    expect(
      messageForAccountDeletionError({'error': 'not_authenticated'}, status: 401),
      contains('sign in again'),
    );
  });

  test('maps an unreachable server distinctly from a generic failure', () {
    expect(
      messageForAccountDeletionError({'error': 'auth_unavailable'}, status: 503),
      contains('Check your connection'),
    );
    expect(
      messageForAccountDeletionError({'error': 'delete_failed'}, status: 500),
      contains('Nothing on this phone was removed'),
    );
  });
}
