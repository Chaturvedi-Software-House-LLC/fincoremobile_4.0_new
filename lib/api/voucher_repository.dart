import 'pagination_helper.dart';
import 'tally_api_client.dart';

/// One page of a `/vouchers` list call - `items` (raw voucher rows, masterId
/// order) plus enough of tally-api's pagination `meta` to know whether to
/// request another page. Used by callers that want real incremental
/// (infinite-scroll) loading instead of [VoucherRepository.listAll]/
/// [VoucherRepository.listInRange]'s "fetch every page up front" behavior.
class VoucherPage {
  VoucherPage({required this.items, required this.page, required this.totalPages});

  final List<Map<String, dynamic>> items;
  final int page;
  final int totalPages;
}

/// Wraps tally-api's `vouchers` endpoints (full header + ledger/inventory/
/// cost-centre entries per voucher - see `VOUCHER_DETAIL_SELECT` on the
/// backend). Used by `DashboardClicked.dart`'s KPI-tile drill-down.
///
/// `GET vouchers` deliberately has no date-range or voucherTypeMasterId
/// filter server-side (only pagination + an `since`/alterId sync cursor),
/// so [listAll] always fetches every voucher in the company - callers
/// filter by date/voucher-type client-side afterward. This is a real
/// scalability caveat for companies with very large voucher counts; there's
/// no server-side filter to fall back on today (see the migration plan's
/// Phase 7 "Tier 2" notes).
class VoucherRepository {
  VoucherRepository._();
  static final VoucherRepository instance = VoucherRepository._();

  final TallyApiClient _client = TallyApiClient();

  Future<List<Map<String, dynamic>>> listAll() => fetchAllPages(
    (page) => _client.getForCompany('/vouchers?page=$page&limit=100'),
  );

  /// One raw page of `/vouchers` (masterId order), optionally narrowed
  /// server-side to one `voucherTypeMasterId`. **No date-range filter
  /// exists on this endpoint** (see this class's doc comment) - a caller
  /// wanting a date-bounded incremental list has to filter each page's
  /// rows itself, same as [listInRange] does for the full set.
  Future<VoucherPage> listPage({
    required int page,
    int limit = 30,
    int? voucherTypeMasterId,
  }) async {
    final query = StringBuffer('?page=$page&limit=$limit');
    if (voucherTypeMasterId != null) {
      query.write('&voucherTypeMasterId=$voucherTypeMasterId');
    }
    final result = await _client.getForCompany('/vouchers$query');
    return VoucherPage(
      items: (result.data as List).cast<Map<String, dynamic>>(),
      page: page,
      totalPages: (result.meta?['totalPages'] as int?) ?? 1,
    );
  }

  /// [listAll] filtered client-side to [from]..[to] (inclusive, by the
  /// voucher's own `date` field) and optionally to one
  /// `voucherTypeMasterId`.
  Future<List<Map<String, dynamic>>> listInRange({
    required DateTime from,
    required DateTime to,
    int? voucherTypeMasterId,
  }) async {
    final vouchers = await listAll();
    return vouchers.where((v) {
      final date = DateTime.tryParse(v['date'] as String? ?? '');
      if (date == null) return false;
      final inRange =
          !date.isBefore(DateTime(from.year, from.month, from.day)) &&
          !date.isAfter(DateTime(to.year, to.month, to.day, 23, 59, 59));
      if (!inRange) return false;
      if (voucherTypeMasterId != null &&
          v['voucherTypeMasterId'] != voucherTypeMasterId) {
        return false;
      }
      return true;
    }).toList();
  }

  Future<Map<String, dynamic>> getByMasterId(int voucherMasterId) async {
    final result = await _client.getForCompany('/vouchers/$voucherMasterId');
    return result.data as Map<String, dynamic>;
  }
}
