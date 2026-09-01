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

String _dateOnly(DateTime d) => d.toIso8601String().split('T').first;

/// Wraps tally-api's `vouchers` endpoints (full header + ledger/inventory/
/// cost-centre entries per voucher - see `VOUCHER_DETAIL_SELECT` on the
/// backend). Used by `DashboardClicked.dart`'s KPI-tile drill-down.
///
/// `GET vouchers` now accepts server-side `from`/`to` (added after this
/// class was first written against a date-filter-less endpoint - see
/// [listPage]/[listInRange]'s doc comments) in addition to pagination, an
/// optional `voucherTypeMasterId`, and the `since`/alterId sync cursor.
/// [listAll] (no date bound at all) still fetches every voucher in the
/// company - genuinely large companies should prefer [listInRange] or
/// [listPage] with a date bound instead.
class VoucherRepository {
  VoucherRepository._();
  static final VoucherRepository instance = VoucherRepository._();

  final TallyApiClient _client = TallyApiClient();

  Future<List<Map<String, dynamic>>> listAll() => fetchAllPages(
    (page) => _client.getForCompany('/vouchers?page=$page&limit=100'),
  );

  /// One raw page of `/vouchers` (masterId order unless [from]/[to] is set,
  /// see below), optionally narrowed server-side to one
  /// `voucherTypeMasterId` and/or a `from`/`to` date range - both filters
  /// are applied server-side now, so a caller wanting a date-bounded
  /// incremental list no longer needs to walk every page filtering client-
  /// side.
  Future<VoucherPage> listPage({
    required int page,
    int limit = 30,
    int? voucherTypeMasterId,
    DateTime? from,
    DateTime? to,
  }) async {
    final query = StringBuffer('?page=$page&limit=$limit');
    if (voucherTypeMasterId != null) {
      query.write('&voucherTypeMasterId=$voucherTypeMasterId');
    }
    if (from != null) query.write('&from=${_dateOnly(from)}');
    if (to != null) query.write('&to=${_dateOnly(to)}');
    final result = await _client.getForCompany('/vouchers$query');
    return VoucherPage(
      items: (result.data as List).cast<Map<String, dynamic>>(),
      page: page,
      // tally-api's pagination meta names this field `lastPage`, not
      // `totalPages` (see pagination_helper.dart's fetchAllPages for the
      // same bug/fix) - this made every incremental page-load in
      // Transactions.dart believe there was only ever 1 page.
      totalPages: (result.meta?['lastPage'] as int?) ?? 1,
    );
  }

  /// Every voucher in [from]..[to] (inclusive), optionally narrowed to one
  /// `voucherTypeMasterId` - both filters are applied server-side (see
  /// [listPage]'s doc comment), so this only fetches/paginates through the
  /// matching rows instead of the whole company's voucher history.
  Future<List<Map<String, dynamic>>> listInRange({
    required DateTime from,
    required DateTime to,
    int? voucherTypeMasterId,
  }) => fetchAllPages(
    (page) => _client.getForCompany(
      '/vouchers?page=$page&limit=100'
      '&from=${_dateOnly(from)}&to=${_dateOnly(to)}'
      '${voucherTypeMasterId != null ? '&voucherTypeMasterId=$voucherTypeMasterId' : ''}',
    ),
  );

  Future<Map<String, dynamic>> getByMasterId(int voucherMasterId) async {
    final result = await _client.getForCompany('/vouchers/$voucherMasterId');
    return result.data as Map<String, dynamic>;
  }
}
