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
///
/// Sales Ledger / Cash Ledger (legacy per-user fields) are stored as a
/// `LEDGER` master-restriction - the one master-restriction type that's
/// genuinely all-or-nothing per user (unlike GODOWN/VOUCHER_TYPE, which this
/// screen already fully replaces via a single value each). Restricting
/// `LEDGER` to *just* the chosen Sales/Cash ledger would also hide every
/// customer/party ledger from that user everywhere else in the app (the
/// registration screens' Party Ledger picker, reports, etc.), so the
/// allow-list this writes is always [salesLedger, cashLedger, ...every
/// SUNDRY_DEBTORS ledger in the company] - preserving normal party-ledger
/// visibility while still pinning a van-sales default. See
/// [_listAllPartyLedgerMasterIds]/[saveAllocation].

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

  /// Every ledger for the current company, each annotated with its own
  /// group's `reservedName` - the shared fetch behind [listSalesLedgers]/
  /// [listCashLedgers]/[_listAllPartyLedgerMasterIds] (one `/ledgers` +
  /// `/groups` pair, classified client-side, same pattern the registration
  /// screens used before they moved to the server-classified
  /// `voucher-entry-dropdowns` endpoint - not worth that endpoint's overhead
  /// here since this is an unfiltered, owner-level, low-frequency admin
  /// fetch, not a per-voucher-entry form).
  static Future<List<Map<String, dynamic>>> _fetchAllLedgersWithGroup() async {
    final results = await Future.wait([
      fetchAllPages((page) => _client.getForCompany('/ledgers?page=$page&limit=100')),
      fetchAllPages((page) => _client.getForCompany('/groups?page=$page&limit=100')),
    ]);
    final ledgers = results[0];
    final groups = results[1];
    final reservedNameByGroupId = {
      for (final g in groups) g['masterId'] as int: g['reservedName'] as String?,
    };
    return ledgers
        .map((l) => {
              ...l,
              'groupReservedName': reservedNameByGroupId[l['groupMasterId']],
            })
        .toList();
  }

  /// Ledgers under the `SALES` group - the "Sales Ledger" picker's options.
  static Future<List<MasterOption>> listSalesLedgers() async {
    final ledgers = await _fetchAllLedgersWithGroup();
    return ledgers
        .where((l) => l['groupReservedName'] == 'SALES')
        .map(MasterOption.fromJson)
        .toList();
  }

  /// Ledgers under `CASH`/`BANK`/`BANK_OD` - the "Cash Ledger" picker's
  /// options (same reservedName set `ReceiptRegistration.dart` treats as
  /// "bank/cash").
  static const _cashGroupReservedNames = {'CASH', 'BANK', 'BANK_OD'};

  static Future<List<MasterOption>> listCashLedgers() async {
    final ledgers = await _fetchAllLedgersWithGroup();
    return ledgers
        .where((l) => _cashGroupReservedNames.contains(l['groupReservedName']))
        .map(MasterOption.fromJson)
        .toList();
  }

  /// Every `SUNDRY_DEBTORS` ledger's masterId - merged into the `LEDGER`
  /// restriction allow-list ([saveAllocation]) so pinning a Sales/Cash
  /// ledger for a user never hides their ability to pick a customer ledger
  /// elsewhere in the app.
  static Future<List<int>> _listAllPartyLedgerMasterIds() async {
    final ledgers = await _fetchAllLedgersWithGroup();
    return ledgers
        .where((l) => l['groupReservedName'] == 'SUNDRY_DEBTORS')
        .map((l) => l['masterId'] as int)
        .toList();
  }

  /// The company-user's currently-restricted Sales/Cash ledger, re-derived
  /// from their `LEDGER` restriction by intersecting it against
  /// [listSalesLedgers]/[listCashLedgers] - the restriction itself also
  /// contains every party ledger (see the class doc-comment), so this is
  /// how the two "real" selections are told apart from the merged-in party
  /// ledgers. Both null when unrestricted (no Sales/Cash ledger chosen yet).
  static Future<({int? salesLedgerMasterId, int? cashLedgerMasterId})>
      currentLedgerSelection(String companyUserId) async {
    final restricted = await MasterRestrictionsRepository.instance.get(
      companyUserId,
      MasterRestrictionType.ledger,
    );
    if (restricted.isEmpty) {
      return (salesLedgerMasterId: null, cashLedgerMasterId: null);
    }
    final restrictedSet = restricted.toSet();
    final salesIds = (await listSalesLedgers()).map((m) => m.masterId).toSet();
    final cashIds = (await listCashLedgers()).map((m) => m.masterId).toSet();
    int? firstMatch(Set<int> ids) {
      for (final id in restrictedSet) {
        if (ids.contains(id)) return id;
      }
      return null;
    }

    return (
      salesLedgerMasterId: firstMatch(salesIds),
      cashLedgerMasterId: firstMatch(cashIds),
    );
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

  /// Saves a vehicle allocation: full-replaces the GODOWN (single
  /// masterId), VOUCHER_TYPE (the relevant Delivery Note/Sales/Receipt
  /// masterIds, deduped/nulls dropped), and - when either is given - LEDGER
  /// (chosen Sales/Cash ledger plus every party ledger, see the class
  /// doc-comment) restrictions for [companyUserId]. Omitting both
  /// [salesLedgerMasterId]/[cashLedgerMasterId] clears any existing LEDGER
  /// restriction instead of leaving a stale one behind.
  static Future<void> saveAllocation({
    required String companyUserId,
    required int godownMasterId,
    required List<int?> voucherTypeMasterIds,
    int? salesLedgerMasterId,
    int? cashLedgerMasterId,
  }) async {
    final repo = MasterRestrictionsRepository.instance;
    await repo.set(companyUserId, MasterRestrictionType.godown, [godownMasterId]);
    final vchIds = voucherTypeMasterIds.whereType<int>().toSet().toList();
    await repo.set(companyUserId, MasterRestrictionType.voucherType, vchIds);

    if (salesLedgerMasterId != null || cashLedgerMasterId != null) {
      final partyLedgerIds = await _listAllPartyLedgerMasterIds();
      final ledgerIds = <int>{
        ...partyLedgerIds,
        if (salesLedgerMasterId != null) salesLedgerMasterId,
        if (cashLedgerMasterId != null) cashLedgerMasterId,
      };
      await repo.set(companyUserId, MasterRestrictionType.ledger, ledgerIds.toList());
    } else {
      await repo.clear(companyUserId, MasterRestrictionType.ledger);
    }
  }

  /// Clears a company-user's vehicle allocation entirely (GODOWN,
  /// VOUCHER_TYPE, and LEDGER restrictions), back to unrestricted.
  static Future<void> clearAllocation(String companyUserId) async {
    final repo = MasterRestrictionsRepository.instance;
    await repo.clear(companyUserId, MasterRestrictionType.godown);
    await repo.clear(companyUserId, MasterRestrictionType.voucherType);
    await repo.clear(companyUserId, MasterRestrictionType.ledger);
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
