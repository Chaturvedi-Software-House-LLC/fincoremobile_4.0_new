import 'tally_api_client.dart';

/// `tally-data/companies/:companyId/voucher-entry-dropdowns` - server-side
/// classified dropdown option lists for building a Sales/Receipt
/// voucher-entry form, replacing the old pattern of fetching every
/// `/ledgers`/`/groups`/`/voucher-types`/`/godowns`/stock-items list and
/// re-classifying it client-side by `GroupReservedName`/`VoucherReservedName`
/// (see the doc-comments this replaced on `SalesRegistration.loadData()`/
/// `ReceiptRegistration.loadData()`). Ported server-side from the legacy
/// `tally-server` app's `getSalesData`/`getReceiptData` endpoints - see
/// tally-api's `voucher-entry-dropdowns.service.ts`.
///
/// Every list here is already scoped to the caller's master-restrictions
/// (Van Allocation) - a company-user locked to one godown/voucher type gets
/// exactly one row back for that list, same as the individual master-list
/// endpoints did before.
class VoucherEntryDropdownsRepository {
  VoucherEntryDropdownsRepository._();
  static final VoucherEntryDropdownsRepository instance =
      VoucherEntryDropdownsRepository._();

  final TallyApiClient _client = TallyApiClient();

  /// `{vchTypes, partyLedgers, salesLedgers, vatLedgers, otherLedgers,
  /// items, godowns}` - everything needed to build a Sales/Sales-Order
  /// voucher-entry form. No `currencies` - fetch that separately.
  Future<Map<String, dynamic>> salesData() async {
    final result = await _client.getForCompany(
      '/voucher-entry-dropdowns/sales-data',
    );
    return result.data as Map<String, dynamic>;
  }

  /// `{vchTypes, partyLedgers, cashLedgers}` - everything needed to build a
  /// Receipt voucher-entry form. No `currencies` - fetch that separately.
  Future<Map<String, dynamic>> receiptData() async {
    final result = await _client.getForCompany(
      '/voucher-entry-dropdowns/receipt-data',
    );
    return result.data as Map<String, dynamic>;
  }

  /// `{voucherTypes, ledgers, stockItems, units, costCentres, godowns,
  /// currencies}` - the generic, unfiltered-by-classification bundle
  /// covering every master a voucher-entry form for any voucher type could
  /// need (unlike [salesData]/[receiptData], not restricted to
  /// Sales/Receipt group-reservedName sets). Not yet wired into any screen.
  Future<Map<String, dynamic>> dropdowns() async {
    final result = await _client.getForCompany('/voucher-entry-dropdowns');
    return result.data as Map<String, dynamic>;
  }
}
