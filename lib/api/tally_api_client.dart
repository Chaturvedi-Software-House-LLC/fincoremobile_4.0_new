import 'api_config.dart';
import 'api_exception.dart';
import 'base_api_client.dart';
import 'token_refresher.dart';
import 'token_store.dart';

/// Client for the per-tenant Tally data backend (tally-api): master lists,
/// vouchers/bills, reports, dashboards. Every route lives under
/// `tally-data/companies/:companyGuid/...` and requires a company-user
/// token whose `company_id` claim matches that path segment exactly (a
/// mismatch 404s) - so this client injects the active companyGuid itself
/// via [_companyPath] rather than trusting each call site to build it,
/// which removes a whole class of "sent to the wrong company" bugs.
class TallyApiClient extends BaseApiClient {
  TallyApiClient() : super(tallyApiApiRoot);

  Future<String> _companyPath(String subPath) async {
    final companyGuid = await TokenStore.instance.activeCompanyGuid;
    if (companyGuid == null) {
      throw ApiException(
        statusCode: 0,
        code: 'NO_ACTIVE_COMPANY',
        message: 'No company selected - call selectCompany() first.',
      );
    }
    return '/tally-data/companies/$companyGuid$subPath';
  }

  Future<ApiResult> getForCompany(String subPath) async =>
      get(await _companyPath(subPath), scope: TokenScope.companyUser);

  Future<ApiResult> postForCompany(String subPath, {Object? body}) async =>
      post(await _companyPath(subPath), body: body, scope: TokenScope.companyUser);

  Future<ApiResult> patchForCompany(String subPath, {Object? body}) async =>
      patch(await _companyPath(subPath), body: body, scope: TokenScope.companyUser);

  Future<ApiResult> deleteForCompany(String subPath) async =>
      delete(await _companyPath(subPath), scope: TokenScope.companyUser);

  // -- User-scoped calls (master-restrictions) --------------------------
  //
  // Master-restrictions (`licenses/:licenseId/company-users/:companyUserId/
  // restrictions/:masterType`) also lives on the tally-api host, but is
  // owner-only (LicenseOwnerGuard requires a `user`-type token, not a
  // company-user one) and its path has no `/tally-data/companies/:companyGuid`
  // prefix - so these bypass [_companyPath] entirely and use
  // [TokenScope.user] instead of the company-user scope every other call on
  // this client uses.

  Future<ApiResult> getAsUser(String path) => get(path, scope: TokenScope.user);

  Future<ApiResult> putAsUser(String path, {Object? body}) =>
      put(path, body: body, scope: TokenScope.user);

  Future<ApiResult> deleteAsUser(String path) =>
      delete(path, scope: TokenScope.user);

  @override
  Future<void> refresh(TokenScope scope) {
    switch (scope) {
      case TokenScope.companyUser:
        return TokenRefresher.refreshCompanyUserToken();
      case TokenScope.user:
        return TokenRefresher.refreshUserToken();
      case TokenScope.none:
        throw StateError('Cannot refresh a request made with no token.');
    }
  }
}
