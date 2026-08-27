import 'tally_api_client.dart';
import 'token_store.dart';

/// The tenant-schema `MasterRestrictionType` enum (tally-api
/// `prisma/tenant/schema.prisma`). Only [godown] and [voucherType] are
/// actually used by the Van Allocation feature (see
/// `lib/addVanAllocations.dart` / `lib/ModifyVanAllocation.dart` /
/// `lib/viewVanAllocations.dart` and the registration screens' locking
/// logic), but this wrapper is generic over all five since the underlying
/// tally-api resource is generic.
enum MasterRestrictionType { ledger, costCentre, stockItem, godown, voucherType }

extension _MasterRestrictionTypeWire on MasterRestrictionType {
  // The `:masterType` route segment is NOT the `MasterRestrictionType` enum
  // value (`GODOWN`/`VOUCHER_TYPE`/...) - tally-api's
  // `MasterRestrictionsService.resolveMasterType` maps a lowercase-hyphenated
  // URL segment (matching each master's own list-endpoint path, e.g.
  // `.../godowns`, `.../voucher-types`) to the enum internally. Passing the
  // enum spelling itself 400s with "Unknown master type".
  String get wireName {
    switch (this) {
      case MasterRestrictionType.ledger:
        return 'ledgers';
      case MasterRestrictionType.costCentre:
        return 'cost-centres';
      case MasterRestrictionType.stockItem:
        return 'stock-items';
      case MasterRestrictionType.godown:
        return 'godowns';
      case MasterRestrictionType.voucherType:
        return 'voucher-types';
    }
  }
}

/// Wraps tally-api's `licenses/:licenseId/company-users/:companyUserId/
/// restrictions/:masterType` endpoints (`master-restrictions.controller.ts`)
/// - the license-owner-only allow-list feature that Van Allocation is built
/// on top of (see the Van Allocation screens for the exact GODOWN/
/// VOUCHER_TYPE usage).
///
/// These routes sit on the tally-api host (same as every other master/report
/// endpoint - see [tallyApiApiRoot] in `api_config.dart`) but are guarded by
/// `LicenseOwnerGuard`, not `CompanyUserTokenGuard`: they need a `user`-scope
/// token belonging to the actual owner of the license (`tenant.userId ===
/// auth.sub`), not a company-user token, and their path has no
/// `/tally-data/companies/:companyGuid` prefix - so calls go through
/// [TallyApiClient.getAsUser]/[putAsUser]/[deleteAsUser] rather than the
/// company-scoped `getForCompany`/`postForCompany` helpers every other
/// tally-api repository in this app uses.
///
/// Semantics (see tally-api's CLAUDE.md "User-wise master restrictions"):
/// allow-list-only and opt-in. A company-user with zero restriction rows for
/// a master type is unrestricted (sees everything - the default); setting
/// even one row switches that type to "only these masterIds." [get] returns
/// an empty list for "unrestricted," never a sentinel/null.
class MasterRestrictionsRepository {
  MasterRestrictionsRepository._();
  static final MasterRestrictionsRepository instance =
      MasterRestrictionsRepository._();

  final TallyApiClient _client = TallyApiClient();

  Future<String> _path(String companyUserId, MasterRestrictionType type) async {
    final licenseId = await TokenStore.instance.activeLicenseId;
    if (licenseId == null) {
      throw StateError('No active licenseId - selectCompany() first.');
    }
    return '/licenses/$licenseId/company-users/$companyUserId'
        '/restrictions/${type.wireName}';
  }

  /// Current allow-list for [companyUserId]/[type]. Empty means
  /// unrestricted (sees every master of that type).
  Future<List<int>> get(String companyUserId, MasterRestrictionType type) async {
    final result = await _client.getAsUser(await _path(companyUserId, type));
    final data = result.data;
    if (data is Map<String, dynamic> && data['masterIds'] is List) {
      return (data['masterIds'] as List).cast<int>();
    }
    if (data is List) return data.cast<int>();
    return const [];
  }

  /// Full-replace PUT - always sends the *complete* allow-list for
  /// [companyUserId]/[type], never a partial add/remove. An empty
  /// [masterIds] clears restrictions entirely (back to unrestricted).
  Future<void> set(
    String companyUserId,
    MasterRestrictionType type,
    List<int> masterIds,
  ) async {
    await _client.putAsUser(
      await _path(companyUserId, type),
      body: {'masterIds': masterIds},
    );
  }

  /// Clears restrictions entirely for [companyUserId]/[type] (equivalent to
  /// `set(companyUserId, type, [])`, but calls the dedicated DELETE route).
  Future<void> clear(String companyUserId, MasterRestrictionType type) async {
    await _client.deleteAsUser(await _path(companyUserId, type));
  }
}
