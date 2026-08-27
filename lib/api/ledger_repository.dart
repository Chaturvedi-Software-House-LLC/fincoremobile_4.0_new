import 'pagination_helper.dart';
import 'tally_api_client.dart';

/// One page of a `/ledgers` list call - `items` plus enough of tally-api's
/// pagination `meta` to know whether to request another page. Used by
/// callers that want real incremental (infinite-scroll) loading instead of
/// [LedgerRepository.listLedgers]'s "fetch every page up front" behavior.
class LedgerPage {
  LedgerPage({required this.items, required this.page, required this.totalPages});

  final List<Map<String, dynamic>> items;
  final int page;
  final int totalPages;

  bool get hasMore => page < totalPages;
}

/// Legacy `Party` screen restricted its ledger list to a fixed set of
/// "party-like" group names (`ledgroups` in Party.dart) rather than every
/// ledger in the company. tally-api's ledgers list has no server-side group
/// filter, so this resolves the same restriction client-side: any group
/// whose name case-insensitively matches one of these, OR whose
/// `reservedName` is one of Tally's own two reserved party-type groups.
///
/// This is a best-effort match on name/reservedName, not a full group-
/// hierarchy walk - a custom sub-group several levels under "Sundry
/// Debtors" with an unrelated name won't be picked up. Flagged as a known
/// limitation versus the (unknown, server-side) exact behavior of the
/// legacy `ledGroups` filter.
///
/// `reservedName` values match tally-api's `GroupReservedName` Postgres
/// enum (`SUNDRY_DEBTORS`/`SUNDRY_CREDITORS`, screaming-snake-case), not
/// Tally's own mixed-case reservedName strings - a tally-api schema-
/// hardening migration (2026-08-21) changed this column to a strict enum
/// without updating the sync/report code that still compares against the
/// old-style strings, so tally-api itself doesn't correctly ingest or
/// report on this field right now either. Matching the new enum values
/// here is forward-looking - it's what the column will actually contain
/// once that's fixed, not a workaround for a Flutter-side bug.
const _legacyPartyGroupNames = {
  'sundry debtors',
  'sundry creditors',
  'customers',
  'suppliers',
  'creditors',
  'debtors',
};
const _reservedPartyGroupNames = {'SUNDRY_DEBTORS', 'SUNDRY_CREDITORS'};

String _dateOnly(DateTime d) => d.toIso8601String().split('T').first;

class LedgerRepository {
  LedgerRepository._();
  static final LedgerRepository instance = LedgerRepository._();

  final TallyApiClient _client = TallyApiClient();

  /// The "parent" filter dropdown (Party.dart's `getParent`) - only
  /// party-like groups, not every group in the company.
  Future<List<Map<String, dynamic>>> listPartyGroups() async {
    final groups = await fetchAllPages(
      (page) => _client.getForCompany('/groups?page=$page&limit=100'),
    );
    return groups.where(_isPartyGroup).toList();
  }

  bool _isPartyGroup(Map<String, dynamic> group) {
    final name = (group['name'] as String).trim().toLowerCase();
    final reservedName = group['reservedName'] as String?;
    return _legacyPartyGroupNames.contains(name) ||
        _reservedPartyGroupNames.contains(reservedName);
  }

  /// The main ledger list. [groupMasterId] narrows to one specific group
  /// (a specific "parent" chosen in the dropdown); when omitted, defaults
  /// to every ledger under a party-like group (matching legacy's "All
  /// Parties" - restricted, not literally every ledger in the company).
  Future<List<Map<String, dynamic>>> listLedgers({int? groupMasterId}) async {
    final partyGroupIds = groupMasterId == null
        ? (await listPartyGroups()).map((g) => g['masterId'] as int).toSet()
        : null;

    final ledgers = await fetchAllPages(
      (page) => _client.getForCompany('/ledgers?page=$page&limit=100'),
    );

    return ledgers.where((l) {
      final id = l['groupMasterId'] as int?;
      return groupMasterId != null
          ? id == groupMasterId
          : partyGroupIds!.contains(id);
    }).toList();
  }

  /// One page of ledgers restricted to a single [groupMasterId] (server-side
  /// `groupMasterId` equality filter - tally-api has no "in a set of group
  /// ids" filter, so this only ever narrows to one group at a time; the
  /// "All Parties" multi-group view pages through each party group's ids in
  /// turn rather than requesting them all in one call - see Party.dart).
  Future<LedgerPage> listLedgersPage({
    required int page,
    int limit = 30,
    required int groupMasterId,
  }) async {
    final result = await _client.getForCompany(
      '/ledgers?page=$page&limit=$limit&groupMasterId=$groupMasterId',
    );
    return LedgerPage(
      items: (result.data as List).cast<Map<String, dynamic>>(),
      page: page,
      totalPages: (result.meta?['totalPages'] as int?) ?? 1,
    );
  }

  /// Every ledger in the company, with no party-group narrowing - unlike
  /// [listLedgers] (which defaults to party-like groups only when
  /// [groupMasterId] is omitted). Used by the entry-registration screens
  /// to classify ledgers themselves (party/sales/VAT/cash/bank) by
  /// joining against [GroupRepository]'s `reservedName`s, since sales and
  /// VAT ledgers aren't party-like groups and would otherwise never appear.
  Future<List<Map<String, dynamic>>> listAllLedgers() => fetchAllPages(
        (page) => _client.getForCompany('/ledgers?page=$page&limit=100'),
      );

  /// Ledgers with no voucher activity since [asOf]
  /// (`reports/ledgers/inactive`), enriched with `alias`/contact fields the
  /// inactive report itself doesn't return (only the base ledger list has
  /// them) - merged in by `masterId`.
  Future<List<Map<String, dynamic>>> listInactiveLedgers({
    required DateTime asOf,
    int? groupMasterId,
  }) async {
    final query = groupMasterId != null
        ? '&groupMasterId=$groupMasterId'
        : '';
    final inactive = await fetchAllPages(
      (page) => _client.getForCompany(
        '/reports/ledgers/inactive?asOf=${_dateOnly(asOf)}$query&page=$page&limit=100',
      ),
    );

    // The endpoint's own groupMasterId param already narrows the result
    // when one was requested; "all inactive parties" still needs the same
    // party-like-group restriction listLedgers() applies, resolved here
    // since the inactive report has no equivalent multi-group filter.
    final result = groupMasterId != null
        ? inactive
        : await _filterToPartyGroups(inactive);

    final ledgersByMasterId = {
      for (final l in await listLedgers())
        l['masterId'] as int: l,
    };

    return result.map((inactiveLedger) {
      final full = ledgersByMasterId[inactiveLedger['masterId'] as int];
      return {
        ...inactiveLedger,
        'alias': full?['alias'] ?? const <String>[],
        'mobileNumber': full?['mobileNumber'],
        'phoneNumber': full?['phoneNumber'],
        'email': full?['email'],
      };
    }).toList();
  }

  Future<List<Map<String, dynamic>>> _filterToPartyGroups(
    List<Map<String, dynamic>> ledgers,
  ) async {
    final partyGroupIds = (await listPartyGroups())
        .map((g) => g['masterId'] as int)
        .toSet();
    return ledgers
        .where((l) => partyGroupIds.contains(l['groupMasterId'] as int?))
        .toList();
  }

  /// `reports/ledgers/:ledgerMasterId/summary` - per-voucher-type activity
  /// (invoiceCount/lastDate/totalAmount/averageAmount) for one ledger.
  /// PartyClicked.dart's Summary cards (Sales/Purchase/Receipt/Payment/
  /// Credit Note/Debit Note/Journal) - legacy's `getSummary` grouped by
  /// vchtype, which this endpoint already does server-side.
  Future<List<Map<String, dynamic>>> ledgerSummary(
    int ledgerMasterId, {
    DateTime? from,
    DateTime? to,
  }) async {
    final query = StringBuffer('?');
    if (from != null) query.write('from=${_dateOnly(from)}&');
    if (to != null) query.write('to=${_dateOnly(to)}');
    final result = await _client.getForCompany(
      '/reports/ledgers/$ledgerMasterId/summary$query',
    );
    return (result.data as List).cast<Map<String, dynamic>>();
  }

  /// `reports/ledgers/:ledgerMasterId/outstanding-total` - current total
  /// outstanding across bills tied to this ledger. Returns `{ledgerMasterId,
  /// outstanding}`.
  Future<Map<String, dynamic>> outstandingTotal(int ledgerMasterId) async {
    final result = await _client.getForCompany(
      '/reports/ledgers/$ledgerMasterId/outstanding-total',
    );
    return result.data as Map<String, dynamic>;
  }

  /// `reports/ledgers/outstanding-bills` - bill-wise outstanding list.
  /// [ledgerMasterId] narrows to one ledger (PartyClicked.dart's ageing
  /// breakdown); omit for company-wide (DashboardClicked.dart's Receivable/
  /// Payable tile). Each row already carries a server-computed `overdueDays`,
  /// replacing the client's own ageing-bucket date math.
  Future<List<Map<String, dynamic>>> outstandingBills({
    int? ledgerMasterId,
    bool overdueOnly = false,
  }) async {
    final query = StringBuffer('?overdueOnly=$overdueOnly');
    if (ledgerMasterId != null) query.write('&ledgerMasterId=$ledgerMasterId');
    return fetchAllPages(
      (page) => _client.getForCompany(
        '/reports/ledgers/outstanding-bills$query&page=$page&limit=100',
      ),
    );
  }

  /// `reports/ledgers/:ledgerMasterId/item-summary` - stock items transacted
  /// with this ledger as counterparty. PartyClicked.dart's Items Sold/
  /// Purchased list (legacy's `getItemSummary`).
  Future<List<Map<String, dynamic>>> itemSummary(
    int ledgerMasterId, {
    DateTime? from,
    DateTime? to,
  }) async {
    final query = StringBuffer('?');
    if (from != null) query.write('from=${_dateOnly(from)}&');
    if (to != null) query.write('to=${_dateOnly(to)}');
    final result = await _client.getForCompany(
      '/reports/ledgers/$ledgerMasterId/item-summary$query',
    );
    return (result.data as List).cast<Map<String, dynamic>>();
  }

  // Note: `reports/ledger-statement` (every voucher ledger entry for one
  // ledger) was considered for PartyClicked.dart's Monthly Breakdown, but
  // its response rows carry no voucherTypeMasterId/voucherTypeName - the
  // breakdown needs a per-vchtype split, which that endpoint can't provide.
  // `VoucherRepository.listInRange` (which returns full voucher headers
  // including voucherTypeName) plus client-side ledgerEntries matching is
  // used for that instead - see PartyClicked.dart's `_fetchLedgerMonthly`.

  /// `reports/ledgers/:ledgerMasterId/pending-orders` - item-wise pending
  /// quantity/amount for this party's Sales Orders or Purchase Orders not
  /// yet fully fulfilled by a later Delivery Note/Receipt Note. Replaces
  /// legacy's `getOrderSummary`, consumed by
  /// `PartyClickedSalePurcOrder.dart`. Rows: `{stockItemMasterId,
  /// stockItemName, pendingQuantity, pendingAmount}` - amounts are
  /// `formatMoney`-formatted strings, parse with `parseMoneyField`.
  ///
  /// **Known limitation** (server-side, not fixable here): fulfilment
  /// matching only works for batch-tracked stock items - tally-api's
  /// 2026-08-21 schema-hardening migration moved `orderNumber` off a plain
  /// inventory-entry column into the per-line `batchAllocations` JSON
  /// array, so a non-batch-tracked item's fulfilling voucher is never
  /// matched and its orders always show fully pending even once fulfilled.
  Future<List<Map<String, dynamic>>> pendingOrdersByItem(
    int ledgerMasterId, {
    required bool isSales,
    DateTime? from,
    DateTime? to,
  }) async {
    final query = StringBuffer('?voucherType=${isSales ? 'sales' : 'purchase'}');
    if (from != null) query.write('&from=${_dateOnly(from)}');
    if (to != null) query.write('&to=${_dateOnly(to)}');
    final result = await _client.getForCompany(
      '/reports/ledgers/$ledgerMasterId/pending-orders$query',
    );
    return (result.data as List).cast<Map<String, dynamic>>();
  }

  /// `reports/ledgers/:ledgerMasterId/pending-orders/:stockItemMasterId` -
  /// order-wise breakdown of [pendingOrdersByItem] for one specific stock
  /// item. Replaces legacy's per-item order drill-down, consumed by
  /// `PartyClickedSalePurcOrderClicked.dart`. Rows: `{voucherMasterId,
  /// voucherNumber, date, pendingQuantity, pendingAmount}`.
  Future<List<Map<String, dynamic>>> pendingOrdersByVoucher(
    int ledgerMasterId,
    int stockItemMasterId, {
    required bool isSales,
    DateTime? from,
    DateTime? to,
  }) async {
    final query = StringBuffer('?voucherType=${isSales ? 'sales' : 'purchase'}');
    if (from != null) query.write('&from=${_dateOnly(from)}');
    if (to != null) query.write('&to=${_dateOnly(to)}');
    final result = await _client.getForCompany(
      '/reports/ledgers/$ledgerMasterId/pending-orders/$stockItemMasterId$query',
    );
    return (result.data as List).cast<Map<String, dynamic>>();
  }
}
