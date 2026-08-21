import 'api_config.dart';
import 'base_api_client.dart';
import 'token_refresher.dart';

/// Client for the identity backend (tally-oauth): user/company-user
/// login, refresh, logout, and the self-service company/license/user/role
/// endpoints. Most calls use [TokenScope.user]; a few (company-user
/// management, company-scoped roles) use [TokenScope.companyUser] - pass
/// the right scope per call, this client doesn't assume one.
class TallyOauthClient extends BaseApiClient {
  TallyOauthClient() : super(tallyOauthApiRoot);

  @override
  Future<void> refresh(TokenScope scope) {
    switch (scope) {
      case TokenScope.user:
        return TokenRefresher.refreshUserToken();
      case TokenScope.companyUser:
        return TokenRefresher.refreshCompanyUserToken();
      case TokenScope.none:
        throw StateError('Cannot refresh a request made with no token.');
    }
  }
}
