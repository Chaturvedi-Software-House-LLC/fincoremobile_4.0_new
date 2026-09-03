import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'api_config.dart';
import 'api_exception.dart';
import 'base_api_client.dart';
import 'tally_oauth_client.dart';
import 'token_store.dart';

/// Same reasoning as `BaseApiClient._requestTimeout` - the raw `http` calls
/// in this file bypass that client, so they need their own bound.
const _requestTimeout = Duration(seconds: 20);

/// Thrown by [AuthRepository.selectCompany] when the chosen legacy
/// `(serialNo, companyName)` doesn't match any company/license pair
/// returned by tally-oauth for the current user. Surfaced separately from
/// [ApiException] because it isn't a backend failure - the two systems'
/// company records are simply out of sync for this account.
class CompanyMappingNotFoundException implements Exception {
  CompanyMappingNotFoundException(this.serialNo, this.companyName);
  final String serialNo;
  final String companyName;

  @override
  String toString() =>
      'CompanyMappingNotFoundException(serialNo: $serialNo, companyName: $companyName)';
}

/// Orchestrates the dual-backend login: a tally-oauth session (for
/// dashboards/reports/masters/users/roles/companies/licenses) established
/// alongside the legacy backend's own login, which callers keep driving
/// separately (its OTP/socket-approval UI flow is unchanged by this
/// migration - see Login.dart).
class AuthRepository {
  AuthRepository._();
  static final AuthRepository instance = AuthRepository._();

  final TallyOauthClient _oauth = TallyOauthClient();

  /// The `companies` array from the most recent `POST /auth/user/login`
  /// response - includes companies reached via `company_users` membership
  /// (e.g. a driver/employee role), not just companies under a license the
  /// account owns. [listLicenses]/[listCompanies] only ever see owned
  /// licenses (`GET /license/user`/`GET /company` are both filtered by
  /// `license.userId`), so an account with no owned license - only
  /// `company_users` rows - gets nothing from either; this is the only
  /// place that data reaches the app. In-memory only (not persisted),
  /// which is fine since login always happens earlier in the same app
  /// session as company selection.
  List<Map<String, dynamic>> _lastLoginCompanies = const [];

  /// `POST /auth/user/login`. Callers should treat a failure here as fatal
  /// to login even if the legacy `/api/login/getusers` call succeeds - most
  /// of the app now depends on this session, so proceeding with a
  /// half-authed state would just move the failure somewhere less obvious.
  Future<void> loginToTallyOauth({
    required String userName,
    required String password,
  }) async {
    final result = await _oauth.post(
      '/auth/user/login',
      body: {'userName': userName, 'password': password},
      scope: TokenScope.none,
    );
    final data = result.data as Map<String, dynamic>;
    final token = data['token'] as Map<String, dynamic>;
    await TokenStore.instance.saveUserTokens(
      accessToken: token['accessToken'] as String,
      refreshToken: token['refreshToken'] as String,
    );

    final companiesRaw = data['companies'];
    _lastLoginCompanies = companiesRaw is List
        ? companiesRaw.cast<Map<String, dynamic>>()
        : const [];

    // Phase 6 (making tally-oauth the sole login driver) dropped the
    // legacy socket flow that used to be the only thing writing the
    // `username`/`name` prefs keys - CompanySelectTallyOauth's account
    // header and app_bottom_nav.dart's account row both read those keys,
    // so a tally-oauth-only login left them blank. Populate them here,
    // straight from tally-oauth's own login response, so both places show
    // the real signed-in user regardless of whether they logged in with
    // their username or their email.
    final user = data['user'] as Map<String, dynamic>?;
    if (user != null) {
      final prefs = await SharedPreferences.getInstance();
      final email = user['email']?.toString();
      final displayUserName = (email != null && email.isNotEmpty)
          ? email
          : (user['userName']?.toString() ?? userName);
      await prefs.setString('username', displayUserName);

      final firstName = user['firstName']?.toString() ?? '';
      final lastName = user['lastName']?.toString() ?? '';
      final fullName = '$firstName $lastName'.trim();
      final resolvedName = fullName.isNotEmpty ? fullName : displayUserName;
      await prefs.setString('name', resolvedName);

      // `name_nav`/`email_nav` are the *only* keys ~30 screens (Dashboard,
      // Items, Party*, Transactions*, AssistantChat, admin screens, etc.)
      // actually read for the signed-in user's display name/email - each of
      // them falls back to its own legacy `/api/login/get` lookup whenever
      // these are unset. Populating them here from the real tally-oauth
      // response means every one of those call sites resolves correctly
      // without ever reaching its legacy fallback.
      await prefs.setString('name_nav', resolvedName);
      await prefs.setString(
        'email_nav',
        (email != null && email.isNotEmpty) ? email : displayUserName,
      );
    }
  }

  /// Companies owned by the logged-in user (`GET /company`), for the
  /// company switcher and for [selectCompany]'s legacy-name matching.
  ///
  /// Paginated (default limit 20); a user with more than 100 companies
  /// would need real pagination here, which is unlikely enough to defer -
  /// flagging so a silent truncation isn't mistaken for "no companies".
  Future<List<Map<String, dynamic>>> listCompanies() async {
    final result = await _oauth.get('/company?limit=100', scope: TokenScope.user);
    return (result.data as List).cast<Map<String, dynamic>>();
  }

  /// Every license owned by the current user (`GET /license/user`),
  /// including validity fields (`isActive`/`validUntil`/`suspendedAt`) and
  /// `tallySerialNumber` - each license is what legacy called a "serial
  /// number". [CompanySelectTallyOauth] fetches this alongside
  /// [listCompanies] to rebuild that screen's serial-then-company picker
  /// automatically, with no manual serial-number entry needed (tally-oauth
  /// already knows every license this account owns).
  ///
  /// Paginated (default limit 20); same truncation caveat as
  /// [listCompanies].
  Future<List<Map<String, dynamic>>> listLicenses() async {
    final result = await _oauth.get(
      '/license/user?limit=100',
      scope: TokenScope.user,
    );
    return (result.data as List).cast<Map<String, dynamic>>();
  }

  /// Companies reached via `company_users` membership under someone else's
  /// license (e.g. a driver/employee role) - captured off the login
  /// response since there's no endpoint that lists these directly yet. See
  /// [_lastLoginCompanies].
  List<Map<String, dynamic>> get companiesFromLastLogin => _lastLoginCompanies;

  /// One synthetic "license" per distinct `licenseId` in
  /// [companiesFromLastLogin] - lets [companiesFromLastLogin]'s entries
  /// slot into the same license-then-company picker
  /// ([CompanySelectNotifier.loadData]/[CompanySelectState.companiesFor])
  /// built around [listLicenses]'s owned-license shape, for an account
  /// that has none of its own. tally-oauth's login `companies[].license`
  /// sub-object doesn't expose `tallySerialNumber` yet (only
  /// `GET /license/user` does) - left blank here, which
  /// [CompanySelectNotifier.licenseLabel] already falls back from to the
  /// license name.
  List<Map<String, dynamic>> licensesFromLastLoginCompanies() {
    final seenLicenseIds = <String>{};
    final result = <Map<String, dynamic>>[];
    for (final company in _lastLoginCompanies) {
      final licenseId = company['licenseId'] as String?;
      if (licenseId == null || !seenLicenseIds.add(licenseId)) continue;
      final license = company['license'] as Map<String, dynamic>? ?? const {};
      result.add({'id': licenseId, 'tallySerialNumber': '', ...license});
    }
    return result;
  }

  /// Same checks tally-oauth itself enforces server-side at company-user
  /// login (active, not suspended, not past `validUntil`) - kept here as
  /// the single source of truth so [CompanySelectTallyOauth] and the
  /// login screen's pre-flight check ([checkAnyLicenseUsable]) can't drift
  /// out of agreement on what "valid" means.
  bool isLicenseUsable(Map<String, dynamic> license) {
    if (license['isActive'] != true) return false;
    if (license['suspendedAt'] != null) return false;
    final validUntil = DateTime.tryParse(
      license['validUntil']?.toString() ?? '',
    );
    if (validUntil != null && validUntil.isBefore(DateTime.now())) {
      return false;
    }
    return true;
  }

  /// A specific `(title, message)` pair describing why [license] isn't
  /// usable, or null if it is usable - a distinct title per cause
  /// ("License Expired" vs. "License Suspended" vs. "License Inactive")
  /// rather than one generic "unavailable" label, so the blocked-login
  /// dialog names the actual problem.
  (String title, String message)? licenseUnavailableReason(
    Map<String, dynamic> license,
  ) {
    if (license['suspendedAt'] != null) {
      final reason = license['suspendReason']?.toString();
      return (
        'License Suspended',
        (reason != null && reason.isNotEmpty)
            ? 'Your license has been suspended: $reason'
            : 'Your license has been suspended.',
      );
    }
    if (license['isActive'] != true) {
      return ('License Inactive', 'Your license is currently inactive.');
    }
    final validUntil = DateTime.tryParse(
      license['validUntil']?.toString() ?? '',
    );
    if (validUntil != null && validUntil.isBefore(DateTime.now())) {
      final d = validUntil;
      final expired =
          '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
      return ('License Expired', 'Your license expired on $expired.');
    }
    return null;
  }

  /// Fetches every license this account owns and returns null if at least
  /// one is currently usable, or a `(title, message)` pair naming why none
  /// are.
  ///
  /// Used by [Login]'s `_directlogin`/`_otplogin` to catch an expired,
  /// suspended, or inactive license at the login screen itself - before
  /// the OTP step for an email login, before company selection for a
  /// direct login - instead of letting the user proceed one more screen
  /// only to hit the same error in [CompanySelectTallyOauth]. That screen
  /// still runs its own check too (defense-in-depth against the rare race
  /// of a license expiring between this call and company selection).
  Future<(String title, String message)?> checkAnyLicenseUsable() async {
    final ownedLicenses = await listLicenses();
    final ownedLicenseIds = ownedLicenses.map((l) => l['id']).toSet();
    final licenses = [
      ...ownedLicenses,
      ...licensesFromLastLoginCompanies()
          .where((l) => !ownedLicenseIds.contains(l['id'])),
    ];
    if (licenses.isEmpty) {
      return ('No License Found', 'No license was found for this account.');
    }
    if (licenses.any(isLicenseUsable)) return null;
    if (licenses.length == 1) {
      return licenseUnavailableReason(licenses.first) ??
          ('License Unavailable', 'Your license is not currently active.');
    }
    return (
      'Licenses Unavailable',
      'None of your licenses are currently active. Please contact your administrator.',
    );
  }

  /// Resolves the legacy `(serialNo, companyName)` the user just picked in
  /// SerialSelect to a tally-oauth `companyId`, then mints a company-user
  /// session scoped to it via [selectCompanyById].
  ///
  /// Matching heuristic (flagged in the migration plan as an assumption to
  /// confirm against a real account): a license's `tallySerialNumber` must
  /// equal [serialNo], and that license's company's `name` must equal
  /// [companyName] case-insensitively, ignoring whitespace - mirroring how
  /// the legacy backend derives its own company slug
  /// (`name.replaceAll(' ', '').toLowerCase()`, see TransactionClicked.dart).
  Future<void> selectCompany({
    required String serialNo,
    required String companyName,
  }) async {
    final companyId = await _resolveCompanyId(serialNo, companyName);
    await selectCompanyById(companyId);
  }

  /// Mints a company-user session for an already-known `companyId` (e.g.
  /// one the user picked directly from [listCompanies], as in the company
  /// switcher) - `POST /auth/company-user/login`.
  Future<void> selectCompanyById(String companyId) async {
    final result = await _oauth.post(
      '/auth/company-user/login',
      body: {'companyId': companyId},
      scope: TokenScope.user,
    );
    final data = result.data as Map<String, dynamic>;
    final token = data['token'] as Map<String, dynamic>;
    final user = data['user'] as Map<String, dynamic>;
    final company = user['company'] as Map<String, dynamic>;

    await TokenStore.instance.saveCompanyUserTokens(
      accessToken: token['accessToken'] as String,
      refreshToken: token['refreshToken'] as String,
      companyGuid: user['companyId'] as String,
      licenseId: company['licenseId'] as String,
    );
  }

  /// Decodes the `permissions` claim off the just-issued company-user
  /// access token - no network round trip, since tally-oauth's
  /// `company-user-auth.service.ts` embeds `permissions: string[]` (the
  /// resolved role's granted permission-catalog strings) directly in that
  /// JWT, alongside `token_type`/`company_id`/`license_id`. No
  /// `jwt_decoder`-style package is in this project's pubspec, so this
  /// decodes the standard base64url JWT payload segment by hand - a JWT
  /// needs no signature verification client-side (the app never trusts
  /// this claim for anything security-sensitive; the backend re-checks
  /// every permission-gated call itself), it's only used here to drive
  /// which legacy SharedPreferences screen-visibility flags get set.
  ///
  /// Returns null if there's no active company-user session, the token
  /// can't be parsed, or it carries no `permissions` claim at all (e.g. an
  /// older tally-oauth build that hasn't rolled the claim out yet) -
  /// callers must treat null as "unknown", distinct from a real empty
  /// list (a role with zero permissions granted).
  Future<List<String>?> currentCompanyUserPermissions() async {
    final token = await TokenStore.instance.companyUserAccessToken;
    if (token == null) return null;
    return _decodeJwtPermissions(token);
  }

  List<String>? _decodeJwtPermissions(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final payloadJson = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
      final payload = jsonDecode(payloadJson) as Map<String, dynamic>;
      final raw = payload['permissions'];
      if (raw is List) {
        return raw.map((e) => e.toString()).toList();
      }
      return null;
    } catch (_) {
      // Malformed/truncated token, or an unexpected payload shape - treat
      // exactly like "no claim present" rather than crashing company
      // selection over it.
      return null;
    }
  }

  Future<String> _resolveCompanyId(String serialNo, String companyName) async {
    final licenseByTallySerial = <String, dynamic>{};
    // /license/user is paginated (default limit 20); a user with more than
    // 100 licenses would need real pagination here, which is unlikely
    // enough for a Tally-serial-per-license model to defer for now - but
    // flagging so a silent truncation isn't mistaken for "no match found".
    final licenses = await _oauth.get('/license/user?limit=100', scope: TokenScope.user);
    for (final license in (licenses.data as List).cast<Map<String, dynamic>>()) {
      final tallySerialNumber = license['tallySerialNumber'] as String?;
      if (tallySerialNumber != null) {
        licenseByTallySerial[tallySerialNumber] = license;
      }
    }

    final matchedLicense = licenseByTallySerial[serialNo];
    if (matchedLicense == null) {
      throw CompanyMappingNotFoundException(serialNo, companyName);
    }
    final matchedLicenseId = matchedLicense['id'] as String;

    final normalizedTarget = _normalizeCompanyName(companyName);
    final companies = await listCompanies();
    for (final company in companies) {
      if (company['licenseId'] == matchedLicenseId &&
          _normalizeCompanyName(company['name'] as String) == normalizedTarget) {
        return company['id'] as String;
      }
    }

    throw CompanyMappingNotFoundException(serialNo, companyName);
  }

  String _normalizeCompanyName(String name) =>
      name.replaceAll(' ', '').toLowerCase();

  /// `POST /auth/user/reset-password` - public, no auth needed. tally-oauth
  /// has no "change password while logged in with your current password"
  /// endpoint; this OTP-based flow (also used for "forgot password") is the
  /// only password-change path it exposes, so `ChangePassword.dart` uses it
  /// for a tally-oauth-only session too. Sends an OTP to the account's
  /// email and returns a short-lived reset token (~15 min) that must be
  /// passed to [changePassword] along with that OTP.
  Future<String> requestPasswordResetOtp({required String username}) async {
    final decoded = await _publicPost('/auth/user/reset-password', {
      'username': username,
    });
    final data = decoded['data'] as Map<String, dynamic>;
    return data['token'] as String;
  }

  /// `POST /auth/user/change-password` - completes the flow started by
  /// [requestPasswordResetOtp]. Authorized by [resetToken] (that call's
  /// response token), NOT the normal user access token - bypasses
  /// [TallyOauthClient]'s [TokenScope] for the same reason [logout] does.
  Future<void> changePassword({
    required String resetToken,
    required String otp,
    required String password,
  }) async {
    await _publicPost(
      '/auth/user/change-password',
      {'password': password, 'confirmPassword': password, 'otp': otp},
      bearerToken: resetToken,
    );
  }

  /// Raw `http.post` against tally-oauth, bypassing [TallyOauthClient]'s
  /// [TokenScope]-based auth - shared by [requestPasswordResetOtp] (no auth)
  /// and [changePassword] (a one-off reset token, not a stored session
  /// token). Parses the same `{success, data, meta}` /
  /// `{success:false, error:{code,message}}` envelope [BaseApiClient] does.
  Future<Map<String, dynamic>> _publicPost(
    String path,
    Map<String, dynamic> body, {
    String? bearerToken,
  }) async {
    final deviceId = await TokenStore.instance.deviceId.timeout(_requestTimeout);
    http.Response response;
    try {
      response = await http
          .post(
            Uri.parse('$tallyOauthApiRoot$path'),
            headers: {
              'Content-Type': 'application/json',
              if (bearerToken != null) 'Authorization': 'Bearer $bearerToken',
              'x-device-id': deviceId,
            },
            body: jsonEncode(body),
          )
          .timeout(_requestTimeout);
    } on TimeoutException {
      throw ApiException(
        statusCode: 0,
        code: 'TIMEOUT',
        message: 'The request timed out. Please check your connection and try again.',
      );
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
    return decoded;
  }

  /// Revokes the tally-oauth session (alongside whatever the legacy
  /// session-kill logout already does) and clears the locally stored
  /// tokens. Safe to call even if only a subset of the new-backend session
  /// was ever established.
  ///
  /// `/auth/user/logout` is authorized by the REFRESH token, not the access
  /// token (`Bearer USER_REFRESH`, per tally-oauth's guard) - unlike every
  /// other authenticated call in this repository, so this bypasses
  /// [TallyOauthClient]'s normal [TokenScope] (which always attaches the
  /// access token) and sends the refresh token directly.
  Future<void> logout() async {
    final refreshToken = await TokenStore.instance.userRefreshToken;
    if (refreshToken != null) {
      try {
        await http
            .post(
              Uri.parse('$tallyOauthApiRoot/auth/user/logout'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $refreshToken',
                'x-device-id': await TokenStore.instance.deviceId,
              },
            )
            .timeout(_requestTimeout);
      } catch (_) {
        // Best-effort - still clear local tokens even if the revoke call
        // fails (e.g. already expired, or offline), so the app never gets
        // stuck thinking it's logged in.
      }
    }
    await TokenStore.instance.clearAll();
  }
}
