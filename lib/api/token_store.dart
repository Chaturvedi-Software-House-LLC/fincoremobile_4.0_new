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
