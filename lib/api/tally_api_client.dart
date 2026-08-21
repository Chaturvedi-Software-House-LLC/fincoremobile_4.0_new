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

  @override
  Future<void> refresh(TokenScope scope) {
    if (scope != TokenScope.companyUser) {
      throw StateError('tally-api only ever uses company-user tokens.');
    }
    return TokenRefresher.refreshCompanyUserToken();
  }
}
