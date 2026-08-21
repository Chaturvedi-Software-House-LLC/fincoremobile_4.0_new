/// Thrown by [BaseApiClient] for any non-2xx response or an envelope with
/// `success: false`, from either tally-oauth or tally-api (they share the
/// same `{success, data}` / `{success:false, error:{code,message}}` shape).
class ApiException implements Exception {
  ApiException({required this.statusCode, required this.code, required this.message});

  final int statusCode;
  final String code;
  final String message;

  @override
  String toString() => 'ApiException($statusCode, $code, $message)';
}

/// Thrown when a request gets a 401, the one-shot refresh attempt also
/// fails, and the caller needs to force a full re-login rather than retry
/// again or silently keep using stale/absent auth.
class SessionExpiredException implements Exception {
  SessionExpiredException(this.message);
  final String message;

  @override
  String toString() => 'SessionExpiredException($message)';
}
