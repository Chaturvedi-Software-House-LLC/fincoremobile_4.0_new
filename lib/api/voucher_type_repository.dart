import 'pagination_helper.dart';
import 'tally_api_client.dart';

/// `tally-data/companies/:companyId/voucher-types` - Tally's own voucher
/// type list, keyed by `masterId` with a `reservedName`. The entry-
/// registration screens use this to resolve the `voucherTypeMasterId` a
/// [VoucherEntryRepository.create] call needs, by matching on
/// `reservedName` rather than the user-editable `name` - the same
/// stability rationale tally-api's own report queries use (see tally-api's
/// CLAUDE.md).
///
/// `reservedName` values are tally-api's `VoucherReservedName` Postgres
/// enum labels (`SALES`, `RECEIPT`, `PAYMENT`, `PURCHASE`, `SALES_ORDER`,
/// `DELIVERY_NOTE`, screaming-snake-case) as of its 2026-08-21 schema-
/// hardening migration - NOT Tally's own mixed-case reservedName strings
/// (`'Sales'`, `'Receipt'`, `'Sales Order'`, etc) this doc comment used to
/// cite. That migration didn't update tally-api's own sync/report code to
/// match, so voucher-type syncing and any server-side reservedName-based
/// report is currently broken there too - [byReservedName] matches the
/// new enum values because that's what the column will actually contain
/// once that's fixed upstream, not as a workaround for anything here.
class VoucherTypeRepository {
  VoucherTypeRepository._();
  static final VoucherTypeRepository instance = VoucherTypeRepository._();

  final TallyApiClient _client = TallyApiClient();

  Future<List<Map<String, dynamic>>> listAll() => fetchAllPages(
        (page) => _client.getForCompany('/voucher-types?page=$page&limit=100'),
      );

  /// The active voucher type(s) matching tally-api's `VoucherReservedName`
  /// enum label (case-sensitive, exact - e.g. `'SALES'`, not `'Sales'`).
  Future<List<Map<String, dynamic>>> byReservedName(String reservedName) async {
    final all = await listAll();
    return all
        .where((v) => v['reservedName'] == reservedName && v['isActive'] == true)
        .toList();
  }
}
