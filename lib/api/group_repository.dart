import 'pagination_helper.dart';
import 'tally_api_client.dart';

/// `tally-data/companies/:companyId/groups` - the full, unfiltered ledger
/// group list (party-like or not), keyed by `masterId` with a `reservedName`.
/// Unlike [LedgerRepository.listPartyGroups] (which narrows to party-like
/// groups only), this is the raw list - used by the entry-registration
/// screens to classify a ledger by which reservedName group it falls under
/// (party vs. sales vs. VAT vs. cash/bank), the same way tally-api's own
/// `dashboard-reports.service.ts` classifies ledgers server-side.
///
/// `reservedName` values are tally-api's `GroupReservedName` Postgres enum
/// labels (`SUNDRY_DEBTORS`, `SALES`, `DUTIES`, `CASH`, `BANK`, screaming-
/// snake-case) as of its 2026-08-21 schema-hardening migration - NOT
/// Tally's own mixed-case reservedName strings (`'Sundry Debtors'`,
/// `'Sales Accounts'`, `'Duties & Taxes'`, `'Cash-in-Hand'`,
/// `'Bank Accounts'`) that this doc comment used to cite and that older
/// call sites still compared against. That migration didn't update
/// tally-api's own sync/report code to match, so master syncing and any
/// server-side reservedName-based report is currently broken there too -
/// this repository's callers match the new enum values because that's
/// what the column will actually contain once that's fixed upstream, not
/// as a workaround for anything on the Flutter side.
class GroupRepository {
  GroupRepository._();
  static final GroupRepository instance = GroupRepository._();

  final TallyApiClient _client = TallyApiClient();

  Future<List<Map<String, dynamic>>> listAll() => fetchAllPages(
        (page) => _client.getForCompany('/groups?page=$page&limit=100'),
      );
}
