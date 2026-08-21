import 'tally_api_client.dart';

class DashboardRepository {
  DashboardRepository._();
  static final DashboardRepository instance = DashboardRepository._();

  final TallyApiClient _client = TallyApiClient();

  String _dateOnly(DateTime d) => d.toIso8601String().split('T').first;

  /// `reports/dashboard/summary` - company-wide totals, all fields are
  /// money strings: {sales, purchase, receipt, payment, cash, payable,
  /// receivable}. Not restricted by master-restrictions (company-wide).
  Future<Map<String, dynamic>> summary({DateTime? from, DateTime? to}) async {
    final query = StringBuffer('?');
    if (from != null) query.write('from=${_dateOnly(from)}&');
    if (to != null) query.write('to=${_dateOnly(to)}');
    final result = await _client.getForCompany('/reports/dashboard/summary$query');
    return result.data as Map<String, dynamic>;
  }

  /// `reports/dashboard/sales-chart` - `[{period, sales, receipt}]`,
  /// `period` formatted per [groupBy] ('day'|'month'|'year').
  Future<List<Map<String, dynamic>>> salesChart({
    required DateTime from,
    required DateTime to,
    String groupBy = 'day',
  }) async {
    final result = await _client.getForCompany(
      '/reports/dashboard/sales-chart?from=${_dateOnly(from)}&to=${_dateOnly(to)}&groupBy=$groupBy',
    );
    return (result.data as List).cast<Map<String, dynamic>>();
  }

  /// `reports/dashboard/voucher-type-breakdown` - `[{voucherTypeMasterId,
  /// voucherTypeName, sales, purchase}]`, one row per voucher type
  /// (Sales/Purchase/Credit Note/Debit Note). Used in place of the legacy
  /// per-ledger `/api/dashboard/piechart/...` endpoint (no tally-api
  /// equivalent grouped by ledger exists) - the dashboard's pie-chart
  /// section groups by voucher type instead, which is the closest
  /// dimension tally-api exposes.
  Future<List<Map<String, dynamic>>> voucherTypeBreakdown({
    DateTime? from,
    DateTime? to,
  }) async {
    final query = StringBuffer('?');
    if (from != null) query.write('from=${_dateOnly(from)}&');
    if (to != null) query.write('to=${_dateOnly(to)}');
    final result = await _client.getForCompany(
      '/reports/dashboard/voucher-type-breakdown$query',
    );
    return (result.data as List).cast<Map<String, dynamic>>();
  }
}
