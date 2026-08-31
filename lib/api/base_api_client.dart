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

  /// `POST {apiRoot}/auth/user/refresh` (or the company-user equivalent),
  /// implemented per-scope by the subclass since the endpoint and stored
  /// tokens differ between the two.
  Future<void> refresh(TokenScope scope);

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
    final headers = await _headers(scope);
    final encodedBody = body == null ? null : jsonEncode(body);

    late final http.Response response;
    switch (method) {
      case 'GET':
        response = await _http.get(uri, headers: headers);
        break;
      case 'POST':
        response = await _http.post(uri, headers: headers, body: encodedBody);
        break;
      case 'PATCH':
        response = await _http.patch(uri, headers: headers, body: encodedBody);
        break;
      case 'PUT':
        response = await _http.put(uri, headers: headers, body: encodedBody);
        break;
      case 'DELETE':
        response = await _http.delete(uri, headers: headers);
        break;
      default:
        throw ArgumentError('Unsupported method: $method');
    }

    if (response.statusCode == 401 && scope != TokenScope.none && !isRetry) {
      try {
        await refresh(scope);
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
        message: (error['message'] as String?) ?? 'Request failed',
      );
    }

    return ApiResult(
      decoded['data'],
      decoded['meta'] as Map<String, dynamic>?,
    );
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
