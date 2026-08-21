import 'pagination_helper.dart';
import 'tally_api_client.dart';

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
