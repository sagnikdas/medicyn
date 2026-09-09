/// Turns a Supabase edge function's machine-readable `error` into a sentence
/// a screen can show. Shared by every edge-function client in this app
/// (`medicine_parser.dart`, `prescription_parser.dart`) rather than each
/// reimplementing the same three cases: the error codes and their meaning
/// (`quota_exceeded` is a real limit, `quota_unavailable`/an unreachable
/// server is a connection problem, everything else is a generic parse
/// failure) are function-agnostic, only the exact wording for "you've hit
/// your limit" differs per caller.
String messageForEdgeFunctionError(
  Object? payload, {
  int? status,
  required String quotaExceededMessage,
}) {
  if (_errorCode(payload) == 'quota_exceeded') {
    return quotaExceededMessage;
  }
  if (status == 0 ||
      status == 503 ||
      _errorCode(payload) == 'quota_unavailable') {
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
