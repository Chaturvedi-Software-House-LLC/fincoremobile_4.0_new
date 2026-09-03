import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../Login.dart';
import 'api_exception.dart';
import 'navigator_key.dart';
import 'token_store.dart';

/// Which token (if any) a request should be authorized with. tally-oauth
/// mixes user-token and company-user-token endpoints on the same base URL
/// (e.g. `/company` needs a user token, `/company-user` needs a
/// company-user token), so this is a per-call choice rather than a
/// per-client one. tally-api only ever needs [companyUser].
enum TokenScope { none, user, companyUser }

/// Shared request/response plumbing for tally-oauth and tally-api: attaches
/// the right bearer token, parses their shared `{success, data, meta}` /
/// `{success:false, error:{code,message}}` envelope, and on a 401 attempts
/// exactly one silent refresh before retrying the original request once.
///
/// The legacy backend is NOT routed through this client - its ~40 existing
/// call sites keep their current raw-body/`error`-key parsing untouched.
abstract class BaseApiClient {
  BaseApiClient(this.apiRoot, {http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  final String apiRoot;
  final http.Client _http;

  /// Every request (and the device-id/token lookups in [_headers]) is
  /// bounded by this - without it, a stalled connection or a hung
  /// secure-storage/keychain read leaves the caller's `await` (and with it
  /// the whole UI, since these are all awaited from button handlers) stuck
  /// forever with no error and no way to recover short of killing the app.
  static const _requestTimeout = Duration(seconds: 20);

  /// `POST {apiRoot}/auth/user/refresh` (or the company-user equivalent),
  /// implemented per-scope by the subclass since the endpoint and stored
  /// tokens differ between the two.
  Future<void> refresh(TokenScope scope);

  /// In-flight refresh, shared across every [BaseApiClient] instance (every
  /// repository builds its own `TallyApiClient`/`TallyOauthClient`, so this
  /// can't be instance state) - keyed by scope since a user-token refresh
  /// and a company-user-token refresh are independent.
  ///
  /// tally-oauth rotates the refresh token on every use, revoking the old
  /// one the instant a new pair is issued (see token_refresher.dart). If
  /// several requests 401 around the same time (routine - most screens
  /// fire multiple calls on load) and each independently called
  /// `refresh(scope)`, only the first would succeed; every other call
  /// would still be holding the refresh token that first call just
  /// rotated away, fail with a revoked-refresh-token error, and force a
  /// full logout - even though the session was actually fine. Coalescing
  /// concurrent 401s for the same scope onto one shared refresh call (and
  /// letting every caller await its result) closes that race.
  static final Map<TokenScope, Future<void>> _refreshInFlight = {};

  Future<void> _refreshOnce(TokenScope scope) {
    final existing = _refreshInFlight[scope];
    if (existing != null) return existing;

    final future = refresh(scope).whenComplete(() {
      _refreshInFlight.remove(scope);
    });
    _refreshInFlight[scope] = future;
    return future;
  }

  Future<String?> _tokenFor(TokenScope scope) {
    switch (scope) {
      case TokenScope.none:
        return Future.value(null);
      case TokenScope.user:
        return TokenStore.instance.userAccessToken;
      case TokenScope.companyUser:
        return TokenStore.instance.companyUserAccessToken;
    }
  }

  Future<Map<String, String>> _headers(TokenScope scope) async {
    final headers = {
      'Content-Type': 'application/json',
      // tally-oauth's login/refresh require this (single-active-session-
      // per-device tracking) - sent on every request, not just those two,
      // since it's harmless elsewhere and one place to maintain.
      'x-device-id': await TokenStore.instance.deviceId,
    };
    final token = await _tokenFor(scope);
    if (token != null) headers['Authorization'] = 'Bearer $token';
    return headers;
  }

  Future<ApiResult> get(String path, {TokenScope scope = TokenScope.companyUser}) =>
      _send('GET', path, scope: scope);

  Future<ApiResult> post(
    String path, {
    Object? body,
    TokenScope scope = TokenScope.companyUser,
  }) => _send('POST', path, body: body, scope: scope);

  Future<ApiResult> patch(
    String path, {
    Object? body,
    TokenScope scope = TokenScope.companyUser,
  }) => _send('PATCH', path, body: body, scope: scope);

  Future<ApiResult> put(
    String path, {
    Object? body,
    TokenScope scope = TokenScope.companyUser,
  }) => _send('PUT', path, body: body, scope: scope);

  Future<ApiResult> delete(String path, {TokenScope scope = TokenScope.companyUser}) =>
      _send('DELETE', path, scope: scope);

  Future<ApiResult> _send(
    String method,
    String path, {
    Object? body,
    required TokenScope scope,
    bool isRetry = false,
  }) async {
    final uri = Uri.parse('$apiRoot$path');
    final headers = await _headers(scope).timeout(_requestTimeout);
    final encodedBody = body == null ? null : jsonEncode(body);

    late final http.Response response;
    try {
      switch (method) {
        case 'GET':
          response = await _http.get(uri, headers: headers).timeout(_requestTimeout);
          break;
        case 'POST':
          response = await _http
              .post(uri, headers: headers, body: encodedBody)
              .timeout(_requestTimeout);
          break;
        case 'PATCH':
          response = await _http
              .patch(uri, headers: headers, body: encodedBody)
              .timeout(_requestTimeout);
          break;
        case 'PUT':
          response = await _http
              .put(uri, headers: headers, body: encodedBody)
              .timeout(_requestTimeout);
          break;
        case 'DELETE':
          response = await _http.delete(uri, headers: headers).timeout(_requestTimeout);
          break;
        default:
          throw ArgumentError('Unsupported method: $method');
      }
    } on TimeoutException {
      throw ApiException(
        statusCode: 0,
        code: 'TIMEOUT',
        message: 'The request timed out. Please check your connection and try again.',
      );
    }

    if (response.statusCode == 401 && scope != TokenScope.none && !isRetry) {
      try {
        await _refreshOnce(scope);
      } catch (_) {
        // The one-shot refresh itself failed (refresh token dead/expired,
        // not just the access token) - there's no path back to a valid
        // session short of a full re-login. Clear whatever's left of it and
        // force-navigate to Login from here (via the global navigatorKey)
        // rather than relying on every call site's catch block to notice
        // this specific exception type and redirect - most of them only
        // handle ApiException and would otherwise show a generic error
        // while silently leaving the user stuck on a dead session.
        await TokenStore.instance.clearAll();
        final navState = navigatorKey.currentState;
        if (navState != null) {
          navState.pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (context) => Login(username: '', password: ''),
            ),
            (route) => false,
          );
        }
        throw SessionExpiredException(
          'Session expired - please log in again.',
        );
      }
      return _send(method, path, body: body, scope: scope, isRetry: true);
    }

    final decoded = response.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;

    final success = decoded['success'] as bool? ?? (response.statusCode < 300);
    if (!success) {
      final error = decoded['error'] as Map<String, dynamic>? ?? const {};
      throw ApiException(
        statusCode: (decoded['statusCode'] as int?) ?? response.statusCode,
        code: (error['code'] as String?) ?? 'UNKNOWN',
        message: _detailedMessage(error) ?? (error['message'] as String?) ?? 'Request failed',
      );
    }

    return ApiResult(
      decoded['data'],
      decoded['meta'] as Map<String, dynamic>?,
    );
  }

  /// Builds a specific error message from `error.details` (tally-api's own
  /// convention) or `error.errors`/`error.aggregateErrors` (nestjs-zod's raw
  /// shape, seen coming straight through from tally-oauth for at least one
  /// endpoint) when present, joining every field's own message - e.g.
  /// "Username must be at least 8 characters" - instead of just the
  /// generic top-level "Validation failed" a Zod validation error's
  /// `message` field carries on its own. Returns null (falls back to that
  /// generic message) when no such per-field list is present or usable.
  static String? _detailedMessage(Map<String, dynamic> error) {
    final raw = error['details'] ?? error['errors'] ?? error['aggregateErrors'];
    if (raw is! List || raw.isEmpty) return null;
    final messages = <String>[];
    for (final item in raw) {
      if (item is Map && item['message'] is String) {
        messages.add(item['message'] as String);
      }
    }
    return messages.isEmpty ? null : messages.join('; ');
  }
}

/// A successful response's `data` payload plus its `meta` (pagination info
/// - `page`/`limit`/`total`/`totalPages` - present only on list endpoints
/// that return a `PaginatedResult`; `null` otherwise).
class ApiResult {
  ApiResult(this.data, this.meta);

  final dynamic data;
  final Map<String, dynamic>? meta;
}
