import 'pagination_helper.dart';
import 'tally_api_client.dart';

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
const _legacyPartyGroupNames = {
  'sundry debtors',
  'sundry creditors',
  'customers',
  'suppliers',
  'creditors',
  'debtors',
};
const _reservedPartyGroupNames = {'Sundry Debtors', 'Sundry Creditors'};

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
}
