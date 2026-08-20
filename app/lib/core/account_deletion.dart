import 'package:supabase_flutter/supabase_flutter.dart';

/// Play-required web URL for requesting account deletion without the app.
/// Rendered from `docs/delete-account.md` on GitHub.
const deleteAccountWebUrl =
    'https://github.com/sagnikdas/dosely/blob/main/docs/delete-account.md';

class AccountDeletionException implements Exception {
  const AccountDeletionException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Asks the `delete_account` edge function to erase the signed-in caller.
///
/// The function establishes identity from the session JWT; this client never
/// sends a user id. Throws [AccountDeletionException] on any failure so the
/// caller can leave the local database and the session untouched.
Future<void> requestServerAccountDeletion() async {
  final FunctionResponse response;
  try {
    response = await Supabase.instance.client.functions
        .invoke('delete_account', body: const <String, dynamic>{})
        .timeout(const Duration(seconds: 20));
  } on FunctionException catch (e) {
    throw AccountDeletionException(messageForAccountDeletionError(e.details, status: e.status));
  } catch (_) {
    throw const AccountDeletionException(
      'Could not reach the server. Check your connection and try again. Your account was not deleted.',
    );
  }

  final data = response.data;
  if (data is! Map || data['ok'] != true) {
    throw AccountDeletionException(messageForAccountDeletionError(data, status: response.status));
  }
}

String messageForAccountDeletionError(Object? payload, {int? status}) {
  final code = _errorCode(payload);
  if (status == 401 || code == 'not_authenticated') {
    return 'Please sign in again, then try deleting your account. Nothing was deleted.';
  }
  if (status == 0 || status == 503 || code == 'auth_unavailable') {
    return 'Could not reach the server. Check your connection and try again. Your account was not deleted.';
  }
  return 'Could not delete your account. Nothing on this phone was removed. Please try again.';
}

String? _errorCode(Object? payload) {
  if (payload is Map && payload['error'] is String) {
    return payload['error'] as String;
  }
  return null;
}
