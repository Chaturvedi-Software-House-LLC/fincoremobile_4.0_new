import 'api/identity_repository.dart';
import 'api/master_restrictions_repository.dart';
import 'api/pagination_helper.dart';
import 'api/tally_api_client.dart';

/// Shared data-layer helpers for the Van Allocation ("Spectra") admin
/// screens - `addVanAllocations.dart`, `ModifyVanAllocation.dart`,
/// `viewVanAllocations.dart`. These three screens all need the same
/// company-user picker, godown/voucher-type option lists, and
/// GODOWN/VOUCHER_TYPE master-restriction reads/writes, so that logic is
/// centralized here rather than duplicated three times.
///
/// Design (see the task this was built against): a "vehicle" allocation is
/// a company-user's `GODOWN` master-restriction set to exactly one
/// `masterId`; the relevant Delivery Note/Sales/Receipt voucher types they
/// may use are that company-user's `VOUCHER_TYPE` master-restriction.
/// Sales/Cash ledger defaults are deliberately NOT part of this - see
/// `SalesRegistration.dart`/`ReceiptRegistration.dart`/
/// `DeliveryNoteRegistration.dart` for where those are derived instead
/// (company-wide Group.reservedName lookup, not a per-user restriction).

/// A tally-oauth CompanyUser, as returned by `IdentityRepository.
/// listCompanyUsers()` - `{id, user: {firstName, lastName, email,
/// userName}, role: {id, name}}` (see `UserView.dart`'s own `UserModel` for
/// the same shape already parsed elsewhere in this app).
class CompanyUserOption {
  final String id;
  final String name;
  final String username;

  CompanyUserOption({required this.id, required this.name, required this.username});

  factory CompanyUserOption.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>?;
    final firstName = user?['firstName']?.toString() ?? '';
    final lastName = user?['lastName']?.toString() ?? '';
    final fullName = '$firstName $lastName'.trim();
    final userName = user?['userName']?.toString() ?? '';
    return CompanyUserOption(
      id: json['id'] as String,
      name: fullName.isNotEmpty ? fullName : userName,
      username: userName,
    );
  }
}

/// A godown or voucher-type master option (`{masterId, name}` - the shape
/// tally-api's `/godowns`/`/voucher-types` list endpoints return).
class MasterOption {
  final int masterId;
  final String name;

  MasterOption({required this.masterId, required this.name});

  factory MasterOption.fromJson(Map<String, dynamic> json) => MasterOption(
    masterId: json['masterId'] as int,
    name: json['name']?.toString() ?? '',
  );

  @override
  String toString() => name;
}

class VanAllocationData {
  VanAllocationData._();

  static final TallyApiClient _client = TallyApiClient();

  /// Every godown for the current company (owner sees the full list to
  /// choose from - unfiltered, since restrictions apply to company-users,
  /// not to the owner's own session).
  static Future<List<MasterOption>> listAllGodowns() async {
    final rows = await fetchAllPages(
      (page) => _client.getForCompany('/godowns?page=$page&limit=100'),
    );
    return rows.map(MasterOption.fromJson).toList();
  }

  /// Voucher types for the current company matching one Tally
  /// `reservedName` (`SALES`/`RECEIPT`/`DELIVERY_NOTE`) - unfiltered by any
  /// master-restriction, for the same "owner sees everything" reason as
  /// [listAllGodowns].
  static Future<List<MasterOption>> listVoucherTypesByReservedName(
    String reservedName,
  ) async {
    final rows = await fetchAllPages(
      (page) => _client.getForCompany(
        '/voucher-types?reservedName=$reservedName&page=$page&limit=100',
      ),
    );
    return rows.map(MasterOption.fromJson).toList();
  }

  /// Every company-user for the current company (tally-oauth), a full,
  /// paginated list.
  static Future<List<CompanyUserOption>> listCompanyUsers() async {
    final rows = await fetchAllPages(
      (page) => IdentityRepository.instance.listCompanyUsers(page: page, limit: 100),
    );
    return rows.map(CompanyUserOption.fromJson).toList();
  }

  /// The single godown masterId currently allocated to [companyUserId], or
  /// null if unrestricted/none set. A restriction set to more than one
  /// godown (shouldn't happen via these screens, but possible if set
  /// elsewhere) is treated as "no single vehicle" - returns null rather
  /// than guessing one.
  static Future<int?> currentGodownMasterId(String companyUserId) async {
    final ids = await MasterRestrictionsRepository.instance.get(
      companyUserId,
      MasterRestrictionType.godown,
    );
    return ids.length == 1 ? ids.first : null;
  }

  static Future<List<int>> currentVoucherTypeMasterIds(String companyUserId) =>
      MasterRestrictionsRepository.instance.get(
        companyUserId,
        MasterRestrictionType.voucherType,
      );

  /// Saves a vehicle allocation: full-replaces both the GODOWN (single
  /// masterId) and VOUCHER_TYPE (the relevant Delivery Note/Sales/Receipt
  /// masterIds, deduped/nulls dropped) restrictions for [companyUserId].
  static Future<void> saveAllocation({
    required String companyUserId,
    required int godownMasterId,
    required List<int?> voucherTypeMasterIds,
  }) async {
    final repo = MasterRestrictionsRepository.instance;
    await repo.set(companyUserId, MasterRestrictionType.godown, [godownMasterId]);
    final vchIds = voucherTypeMasterIds.whereType<int>().toSet().toList();
    await repo.set(companyUserId, MasterRestrictionType.voucherType, vchIds);
  }

  /// Clears a company-user's vehicle allocation entirely (both GODOWN and
  /// VOUCHER_TYPE restrictions), back to unrestricted.
  static Future<void> clearAllocation(String companyUserId) async {
    final repo = MasterRestrictionsRepository.instance;
    await repo.clear(companyUserId, MasterRestrictionType.godown);
    await repo.clear(companyUserId, MasterRestrictionType.voucherType);
  }

  /// True if [godownMasterId] is already allocated (as the sole GODOWN
  /// restriction) to some company-user other than [excludingCompanyUserId] -
  /// preserves the legacy "don't double-assign the same vehicle to two
  /// users" UX. Accepts the N+1 GET-per-company-user cost since this is a
  /// low-frequency admin action, not a hot path (same allowance the view
  /// screen's own N+1 restriction-status lookup relies on).
  static Future<bool> isGodownAlreadyAllocated(
    int godownMasterId, {
    String? excludingCompanyUserId,
  }) async {
    final users = await listCompanyUsers();
    for (final user in users) {
      if (user.id == excludingCompanyUserId) continue;
      final current = await currentGodownMasterId(user.id);
      if (current == godownMasterId) return true;
    }
    return false;
  }
}
