import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Holds the session state for the two new backends (tally-oauth,
/// tally-api) in encrypted storage - separate from the legacy backend's
/// existing SharedPreferences keys (`token`, `hostname`, `serial_no`,
/// `company_name`, `login_list`, etc.), which are untouched by this
/// migration so legacy-backend screens (entries, van allocation, assistant)
/// keep working exactly as before.
class TokenStore {
  TokenStore._();
  static final TokenStore instance = TokenStore._();

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  static const _kUserAccessToken = 'new_user_access_token';
  static const _kUserRefreshToken = 'new_user_refresh_token';
  static const _kCompanyUserAccessToken = 'new_company_user_access_token';
  static const _kCompanyUserRefreshToken = 'new_company_user_refresh_token';
  static const _kActiveCompanyGuid = 'new_active_company_guid';
  static const _kActiveLicenseId = 'new_active_license_id';
  static const _kDeviceId = 'new_device_id';

  Future<void> saveUserTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _storage.write(key: _kUserAccessToken, value: accessToken);
    await _storage.write(key: _kUserRefreshToken, value: refreshToken);
  }

  Future<void> saveCompanyUserTokens({
    required String accessToken,
    required String refreshToken,
    required String companyGuid,
    required String licenseId,
  }) async {
    await _storage.write(key: _kCompanyUserAccessToken, value: accessToken);
    await _storage.write(key: _kCompanyUserRefreshToken, value: refreshToken);
    await _storage.write(key: _kActiveCompanyGuid, value: companyGuid);
    await _storage.write(key: _kActiveLicenseId, value: licenseId);
  }

  Future<String?> get userAccessToken => _storage.read(key: _kUserAccessToken);
  Future<String?> get userRefreshToken =>
      _storage.read(key: _kUserRefreshToken);
  Future<String?> get companyUserAccessToken =>
      _storage.read(key: _kCompanyUserAccessToken);
  Future<String?> get companyUserRefreshToken =>
      _storage.read(key: _kCompanyUserRefreshToken);
  Future<String?> get activeCompanyGuid =>
      _storage.read(key: _kActiveCompanyGuid);
  Future<String?> get activeLicenseId =>
      _storage.read(key: _kActiveLicenseId);

  /// A random id generated once per install and persisted forever after
  /// (never cleared by [clearAll]/[clearCompanyUserSession] - it identifies
  /// this installation, not a session) - sent as the `x-device-id` header
  /// tally-oauth's login/refresh now require (single-active-session-per-
  /// device tracking). Must stay stable across logout/login on the same
  /// device, or every re-login would look like a brand new device and
  /// quickly exhaust the backend's per-account device cap.
  Future<String> get deviceId async {
    final existing = await _storage.read(key: _kDeviceId);
    if (existing != null && existing.isNotEmpty) return existing;

    final generated = _generateDeviceId();
    await _storage.write(key: _kDeviceId, value: generated);
    return generated;
  }

  static String _generateDeviceId() {
    final random = Random.secure();
    // A UUID-v4-shaped random id - the backend just needs a stable opaque
    // string, not a real UUID, but this format is a safe, recognizable
    // choice (matches what device_info_plus/most backends expect to see).
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 10xx
    String hex(int start, int end) => bytes
        .sublist(start, end)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
  }

  /// Clears only the new-backend session (user + company-user tokens and
  /// the active company/license pointers). Does not touch the legacy
  /// backend's SharedPreferences-based session.
  Future<void> clearAll() async {
    await _storage.delete(key: _kUserAccessToken);
    await _storage.delete(key: _kUserRefreshToken);
    await _storage.delete(key: _kCompanyUserAccessToken);
    await _storage.delete(key: _kCompanyUserRefreshToken);
    await _storage.delete(key: _kActiveCompanyGuid);
    await _storage.delete(key: _kActiveLicenseId);
  }

  /// Clears only the company-user session (kept when a user logs out of one
  /// company but stays logged in to switch to another).
  Future<void> clearCompanyUserSession() async {
    await _storage.delete(key: _kCompanyUserAccessToken);
    await _storage.delete(key: _kCompanyUserRefreshToken);
    await _storage.delete(key: _kActiveCompanyGuid);
    await _storage.delete(key: _kActiveLicenseId);
  }
}
