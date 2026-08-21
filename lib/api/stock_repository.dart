import 'pagination_helper.dart';
import 'tally_api_client.dart';

String _dateOnly(DateTime d) => d.toIso8601String().split('T').first;

class StockRepository {
  StockRepository._();
  static final StockRepository instance = StockRepository._();

  final TallyApiClient _client = TallyApiClient();

  /// The "parent" filter dropdown (Items.dart's `getParent`) - every stock
  /// group in the company.
  Future<List<Map<String, dynamic>>> listStockGroups() =>
      fetchAllPages(
        (page) => _client.getForCompany('/stock-groups?page=$page&limit=100'),
      );

  /// The main item list. [stockGroupMasterId] narrows to one specific
  /// group; omit for every item.
  Future<List<Map<String, dynamic>>> listStockItems({
    int? stockGroupMasterId,
  }) async {
    final items = await fetchAllPages(
      (page) => _client.getForCompany('/stock-items?page=$page&limit=100'),
    );
    if (stockGroupMasterId == null) return items;
    return items
        .where((i) => i['stockGroupMasterId'] == stockGroupMasterId)
        .toList();
  }

  /// `reports/stock-items/movement-analysis` - fast/slow/inactive
  /// classification (Items.dart's `getMoving`).
  ///
  /// The report's own row shape is narrow (`masterId, name,
  /// closingQuantity, totalQuantitySold, totalAmountSold`) - unlike the
  /// legacy `getMoving` endpoint, which returned the same full item shape
  /// `getitem` does. Every other display field (unit/description/rate/
  /// lastSaleDate/etc) is merged in from the base stock-items list by
  /// masterId, matching legacy parity. `totalAmountSold` is deliberately
  /// NOT used as `closingAmount` - it's a period sales total, not the
  /// item's closing stock value, and using it in that field's place would
  /// silently show the wrong number.
  Future<List<Map<String, dynamic>>> movementAnalysis({
    required String status, // 'FAST' | 'SLOW' | 'INACTIVE'
    required DateTime asOf,
    double? threshold,
    int? stockGroupMasterId,
  }) async {
    final query = StringBuffer(
      '?status=$status&asOf=${asOf.toIso8601String().split('T').first}',
    );
    if (threshold != null) query.write('&threshold=$threshold');
    if (stockGroupMasterId != null) {
      query.write('&stockGroupMasterId=$stockGroupMasterId');
    }
    final rows = await fetchAllPages(
      (page) => _client.getForCompany(
        '/reports/stock-items/movement-analysis$query&page=$page&limit=100',
      ),
    );

    final itemsByMasterId = {
      for (final i in await listStockItems()) i['masterId'] as int: i,
    };

    return rows.map((row) {
      final full = itemsByMasterId[row['masterId'] as int];
      return {
        ...?full,
        ...row, // masterId/name/closingQuantity from the report win
        'totalQuantitySold': row['totalQuantitySold'],
        'totalAmountSold': row['totalAmountSold'],
      };
    }).toList();
  }

  /// `reports/stock-items/:stockItemMasterId/summary` - per-voucher-type
  /// invoice/rate/quantity summary for one item. ItemsClicked.dart's Sales/
  /// Purchase Summary cards (legacy's `getSummary`) - grouped by voucher
  /// type already, unlike legacy which needed a separate call per vchtype.
  Future<List<Map<String, dynamic>>> stockItemSummary(
    int stockItemMasterId, {
    DateTime? from,
    DateTime? to,
    int? voucherTypeMasterId,
  }) async {
    final query = StringBuffer('?');
    if (from != null) query.write('from=${_dateOnly(from)}&');
    if (to != null) query.write('to=${_dateOnly(to)}&');
    if (voucherTypeMasterId != null) {
      query.write('voucherTypeMasterId=$voucherTypeMasterId');
    }
    final result = await _client.getForCompany(
      '/reports/stock-items/$stockItemMasterId/summary$query',
    );
    return (result.data as List).cast<Map<String, dynamic>>();
  }

  /// `reports/stock-item-movement` - every voucher inventory entry for one
  /// item, paginated. No item-scoped monthly-trend endpoint exists on
  /// tally-api today - this is the raw feed `monthly_bucket_helper.dart`
  /// buckets client-side for ItemsClicked.dart's Month Wise Sales/Purchase
  /// list (legacy's `getTotalAmount`).
  Future<List<Map<String, dynamic>>> stockItemMovement(
    int stockItemMasterId, {
    DateTime? from,
    DateTime? to,
    int? voucherTypeMasterId,
    int? partyLedgerMasterId,
    int? costCentreMasterId,
  }) async {
    final query = StringBuffer('?stockItemMasterId=$stockItemMasterId');
    if (from != null) query.write('&from=${_dateOnly(from)}');
    if (to != null) query.write('&to=${_dateOnly(to)}');
    if (voucherTypeMasterId != null) {
      query.write('&voucherTypeMasterId=$voucherTypeMasterId');
    }
    if (partyLedgerMasterId != null) {
      query.write('&partyLedgerMasterId=$partyLedgerMasterId');
    }
    if (costCentreMasterId != null) {
      query.write('&costCentreMasterId=$costCentreMasterId');
    }
    return fetchAllPages(
      (page) => _client.getForCompany(
        '/reports/stock-item-movement$query&page=$page&limit=100',
      ),
    );
  }
}
