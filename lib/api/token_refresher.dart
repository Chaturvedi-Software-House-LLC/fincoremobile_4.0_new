import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'api_exception.dart';
import 'token_store.dart';

/// Only tally-oauth mints/refreshes tokens - tally-api has no refresh
/// endpoint of its own. Both [TallyOauthClient] and [TallyApiClient] call
/// into here for their `refresh()` override, so a company-user token used
/// against tally-api still refreshes via tally-oauth.
///
/// Uses a bare `http.Client` rather than going through `BaseApiClient` to
/// avoid the 401->refresh->retry logic recursing into itself.
///
/// tally-oauth rotates refresh tokens on every use - `/auth/*/refresh`
/// returns a FULL new `{token: {accessToken, refreshToken, ...}}` pair, not
/// just a fresh access token, and the old refresh token is revoked
/// server-side the moment the new pair is issued. Both tokens must be
/// persisted here or the *next* refresh attempt will fail against an
/// already-revoked refresh token.
class TokenRefresher {
  TokenRefresher._();

  static Future<void> refreshUserToken() async {
    final refreshToken = await TokenStore.instance.userRefreshToken;
    if (refreshToken == null) {
      throw SessionExpiredException('No user refresh token stored.');
    }
    final token = await _post('/auth/user/refresh', refreshToken);
    await TokenStore.instance.saveUserTokens(
      accessToken: token['accessToken'] as String,
      refreshToken: token['refreshToken'] as String,
    );
  }

  /// Company-user refresh additionally needs the active companyGuid/
  /// licenseId re-persisted alongside the rotated tokens, since
  /// [TokenStore.saveCompanyUserTokens] writes all four together - reads
  /// them back from the still-valid (not-yet-cleared) store rather than
  /// requiring the caller to pass them in.
  static Future<void> refreshCompanyUserToken() async {
    final refreshToken = await TokenStore.instance.companyUserRefreshToken;
    final companyGuid = await TokenStore.instance.activeCompanyGuid;
    final licenseId = await TokenStore.instance.activeLicenseId;
    if (refreshToken == null || companyGuid == null || licenseId == null) {
      throw SessionExpiredException('No company-user session stored.');
    }
    final token = await _post('/auth/company-user/refresh', refreshToken);
    await TokenStore.instance.saveCompanyUserTokens(
      accessToken: token['accessToken'] as String,
      refreshToken: token['refreshToken'] as String,
      companyGuid: companyGuid,
      licenseId: licenseId,
    );
  }

  /// Returns the `token` sub-object (`{accessToken, refreshToken, ...}`)
  /// from the `{data: {token, type, user}}` envelope both refresh endpoints
  /// share with their corresponding login endpoints.
  static Future<Map<String, dynamic>> _post(
    String path,
    String refreshToken,
  ) async {
    final response = await http.post(
      Uri.parse('$tallyOauthApiRoot$path'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $refreshToken',
        // Required by tally-oauth's refresh endpoint (single-active-
        // session-per-device tracking) - must be the same id [saveUserTokens]/
        // [saveCompanyUserTokens] logged in with, or the refresh would look
        // like a different device and fail the single-session check.
        'x-device-id': await TokenStore.instance.deviceId,
      },
    );

    final decoded =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final success = decoded['success'] as bool? ?? false;
    if (!success) {
      throw SessionExpiredException('Refresh token rejected.');
    }
    final data = decoded['data'] as Map<String, dynamic>;
    return data['token'] as Map<String, dynamic>;
  }
}
