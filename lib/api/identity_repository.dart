import 'api_exception.dart';
import 'base_api_client.dart';
import 'tally_oauth_client.dart';
import 'token_store.dart';

/// Wraps tally-oauth's company-scoped identity endpoints - roles,
/// permissions, and company-users - used by the AddRole/ModifyRole/
/// RolesView and CreateUser/ModifyUser/UserView screens. All calls use
/// [TokenScope.companyUser]: most of these endpoints derive their
/// `companyId` from that token server-side (see company-role.controller.ts/
/// company-user.controller.ts), so a company-user session (established via
/// [AuthRepository.selectCompany]/[AuthRepository.selectCompanyById]) must
/// already exist before calling anything here. [createCompanyUser] is the
/// one exception - its Zod body schema requires `companyId` explicitly
/// (confirmed live: omitting it 400s with "Invalid input: expected string,
/// received undefined" at `path: ["companyId"]"`), so it reads
/// [TokenStore.activeCompanyGuid] itself rather than relying on the token.
class IdentityRepository {
  IdentityRepository._();
  static final IdentityRepository instance = IdentityRepository._();

  final TallyOauthClient _oauth = TallyOauthClient();

  // -- Company roles (AddRole / ModifyRole / RolesView) ----------------

  /// Each item's `permissions` is `[{permision: {id, name, displayName,
  /// description, group, resource, action}}, ...]` - note the misspelled
  /// `permision` key, which is the actual field name tally-oauth's
  /// RoleResponseSchema uses, not a typo introduced here.
  Future<ApiResult> listRoles({int page = 1, int limit = 20}) =>
      _oauth.get('/company-role?page=$page&limit=$limit', scope: TokenScope.companyUser);

  Future<Map<String, dynamic>> getRole(String id) async {
    final result = await _oauth.get('/company-role/$id', scope: TokenScope.companyUser);
    return result.data as Map<String, dynamic>;
  }

  /// `permissionIds` are Permission uuids (from [listPermissions]), not
  /// permission name strings.
  Future<Map<String, dynamic>> createRole({
    required String name,
    required List<String> permissionIds,
  }) async {
    final result = await _oauth.post(
      '/company-role',
      body: {'name': name, 'permissions': permissionIds},
      scope: TokenScope.companyUser,
    );
    return result.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateRole(
    String id, {
    String? name,
    List<String>? permissionIds,
  }) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (permissionIds != null) body['permissions'] = permissionIds;
    final result = await _oauth.patch('/company-role/$id', body: body, scope: TokenScope.companyUser);
    return result.data as Map<String, dynamic>;
  }

  Future<void> deleteRole(String id) =>
      _oauth.delete('/company-role/$id', scope: TokenScope.companyUser);

  // -- Permission catalog (read-only, for the role-builder UI) ----------

  Future<ApiResult> listPermissions({int page = 1, int limit = 100}) =>
      _oauth.get('/company-permission?page=$page&limit=$limit', scope: TokenScope.companyUser);

  // -- Company users (CreateUser / ModifyUser / UserView) ----------------

  Future<ApiResult> listCompanyUsers({int page = 1, int limit = 20}) =>
      _oauth.get('/company-user?page=$page&limit=$limit', scope: TokenScope.companyUser);

  Future<Map<String, dynamic>> getCompanyUser(String id) async {
    final result = await _oauth.get('/company-user/$id', scope: TokenScope.companyUser);
    return result.data as Map<String, dynamic>;
  }

  /// Creates (or, if a `User` with this `userName`/`email` already exists
  /// elsewhere, reuses) a `User` record and links it to the current
  /// company-user session's company with [roleId] - tally-oauth's
  /// `CompanyUserService.create` looks up by `userName` first, then
  /// `email`, before provisioning a new `User` (see company-user.service.ts).
  Future<Map<String, dynamic>> createCompanyUser({
    required String userName,
    required String firstName,
    required String lastName,
    required String password,
    required String roleId,
    String? phone,
    String? email,
  }) async {
    final companyGuid = await TokenStore.instance.activeCompanyGuid;
    if (companyGuid == null) {
      throw ApiException(
        statusCode: 0,
        code: 'NO_ACTIVE_COMPANY',
        message: 'No company selected - call selectCompany() first.',
      );
    }
    final body = <String, dynamic>{
      'companyId': companyGuid,
      'userName': userName,
      'firstName': firstName,
      'lastName': lastName,
      'password': password,
      'roleId': roleId,
      if (phone != null) 'phone': phone,
      if (email != null) 'email': email,
    };
    final result = await _oauth.post('/company-user', body: body, scope: TokenScope.companyUser);
    return result.data as Map<String, dynamic>;
  }

  /// Only `roleId`/`isActive` can be changed on an existing company-user -
  /// name/password/etc. belong to the underlying `User` record, which this
  /// endpoint doesn't touch (no equivalent exposed to a company-user today).
  Future<Map<String, dynamic>> updateCompanyUser(
    String id, {
    String? roleId,
    bool? isActive,
  }) async {
    final body = <String, dynamic>{};
    if (roleId != null) body['roleId'] = roleId;
    if (isActive != null) body['isActive'] = isActive;
    final result = await _oauth.patch('/company-user/$id', body: body, scope: TokenScope.companyUser);
    return result.data as Map<String, dynamic>;
  }

  Future<void> deleteCompanyUser(String id) =>
      _oauth.delete('/company-user/$id', scope: TokenScope.companyUser);
}
