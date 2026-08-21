/// One month's aggregated total, produced by [bucketByMonth].
class MonthlyBucket {
  MonthlyBucket({required this.monthStart, required this.total});

  /// The 1st of the bucketed month, in local time - use this (not [label])
  /// for chronological sorting/comparison.
  final DateTime monthStart;
  final double total;

  /// e.g. "Jan 2026" - matches the display format legacy's `getMonthSummary`
  /// (`mname`) used.
  String get label => '${_monthNames[monthStart.month - 1]} ${monthStart.year}';
}

const _monthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Buckets [rows] by calendar month, summing [amountOf] for every row whose
/// [dateOf] falls in that month. Used in place of legacy's server-side
/// `getMonthSummary`/`getTotalAmount` endpoints (no month-bucketed
/// equivalent exists on tally-api scoped to a single ledger/stock item -
/// see the migration plan's Phase 7 "Tier 2" notes) - callers fetch the raw
/// rows themselves (e.g. `VoucherRepository.listInRange`,
/// `StockRepository.stockItemMovement`) and bucket them here.
///
/// Returns buckets in chronological order, one per calendar month that has
/// at least one row - months with no activity are omitted (matching
/// legacy's behavior of only ever showing months the server actually
/// returned a row for).
List<MonthlyBucket> bucketByMonth<T>(
  List<T> rows, {
  required DateTime Function(T row) dateOf,
  required double Function(T row) amountOf,
}) {
  final totalsByMonth = <DateTime, double>{};

  for (final row in rows) {
    final date = dateOf(row);
    final monthStart = DateTime(date.year, date.month);
    totalsByMonth.update(
      monthStart,
      (existing) => existing + amountOf(row),
      ifAbsent: () => amountOf(row),
    );
  }

  final months = totalsByMonth.keys.toList()..sort();
  return [
    for (final month in months)
      MonthlyBucket(monthStart: month, total: totalsByMonth[month]!),
  ];
}

/// Parses a tally-api money field, which comes back as either a fixed
/// 4-decimal string (flat `Decimal` columns, e.g. voucher/ledger-entry
/// `amount`) or - inside a `json_agg` payload - a plain JS number. Never
/// throws: an unparseable/null value contributes `0.0`.
double parseMoneyField(dynamic value) {
  if (value == null) return 0.0;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString()) ?? 0.0;
}

/// Parses the app's compact `"yyyyMMdd"` date-range strings (e.g.
/// `startDateString`/`endDateString`, as built by every screen's
/// `_selectDateRange`/`_handleDate`). `DateFormat('yyyyMMdd').parse(...)`
/// (the obvious approach) throws `FormatException: Trying to read MM from
/// ... at 8` - `intl`'s parser treats `yyyy` as greedy/variable-width and
/// over-consumes the whole 8-digit string as the year for a
/// zero-separator pattern like this, leaving nothing for `MM`/`dd`. Manual
/// substring parsing sidesteps that parser quirk entirely.
DateTime parseCompactDate(String yyyyMMdd) {
  return DateTime(
    int.parse(yyyyMMdd.substring(0, 4)),
    int.parse(yyyyMMdd.substring(4, 6)),
    int.parse(yyyyMMdd.substring(6, 8)),
  );
}
