import 'pagination_helper.dart';
import 'tally_api_client.dart';

/// `tally-data/companies/:companyId/voucher-entries` - the app-originated
/// voucher family tally-api added alongside its Tally-synced `Voucher`
/// table (see tally-api's CLAUDE.md, "App-originated vouchers: the
/// VoucherEntry family"). This is the write path Sales/Receipt/Sales-Order/
/// Delivery-Note Registration (+ their Modify/Pending siblings) move onto
/// when migrated off the legacy backend.
///
/// **Known gap, deliberately accepted**: a `VoucherEntry` created here does
/// NOT yet reach real Tally data - tally-api has no outbound-push-to-Tally
/// job built yet (per the same doc section). It's visible via this
/// repository's own `list`/`getById`, but not in Tally itself, and not in
/// Dashboard/report totals (which read the Tally-synced `Voucher` table).
/// Migrating screens onto this repository was an explicit, informed choice
/// made with that tradeoff understood - not an oversight.
///
/// Request/response bodies here are plain `Map<String, dynamic>` matching
/// tally-api's `voucherEntrySchema` field-for-field (see
/// `voucher-entries/dto/voucher-entry.schema.ts`) rather than a typed model
/// - every calling screen already builds its own header/ledger/inventory
/// maps to match whichever backend it's talking to (legacy today, this one
/// once migrated), so a typed wrapper here would just be an extra
/// translation step with nothing to validate against on the Dart side.
class VoucherEntryRepository {
  VoucherEntryRepository._();
  static final VoucherEntryRepository instance = VoucherEntryRepository._();

  final TallyApiClient _client = TallyApiClient();

  /// [body] must match `voucherEntrySchema`: `voucherTypeMasterId`, `date`
  /// (`YYYY-MM-DD`), `currencyMasterId`, plus whichever of
  /// `ledgerEntries`/`inventoryEntries` (and their nested
  /// bill/cost-centre/bank/batch allocations) the voucher type needs -
  /// see the schema doc-comment for the full field list. Returns the
  /// created entry (server-shaped, with resolved names).
  Future<Map<String, dynamic>> create(Map<String, dynamic> body) async {
    final result = await _client.postForCompany('/voucher-entries', body: body);
    return result.data as Map<String, dynamic>;
  }

  /// Partial update - only the header fields present in [body] are
  /// changed. If `ledgerEntries`/`inventoryEntries` are included, they
  /// wholesale-replace the existing ones (delete-then-reinsert, same
  /// semantics as a Tally re-sync); omitting them leaves the existing
  /// entries untouched.
  Future<Map<String, dynamic>> update(
    String voucherEntryId,
    Map<String, dynamic> body,
  ) async {
    final result = await _client.patchForCompany(
      '/voucher-entries/$voucherEntryId',
      body: body,
    );
    return result.data as Map<String, dynamic>;
  }

  Future<void> remove(String voucherEntryId) async {
    await _client.deleteForCompany('/voucher-entries/$voucherEntryId');
  }

  Future<Map<String, dynamic>> getById(String voucherEntryId) async {
    final result = await _client.getForCompany('/voucher-entries/$voucherEntryId');
    return result.data as Map<String, dynamic>;
  }

  /// Every voucher entry for the active company, newest first (matches the
  /// server's own `ORDER BY date DESC, id DESC`) - used by the
  /// Pending-entry screens' "list of my own draft entries" view.
  Future<List<Map<String, dynamic>>> listAll() => fetchAllPages(
        (page) => _client.getForCompany('/voucher-entries?page=$page&limit=100'),
      );

  /// Bill allocations against [ledgerMasterId] from this app's own
  /// not-yet-synced-to-Tally entries (`GET .../voucher-entries/pending-bills`)
  /// - e.g. a Sales entry created in FincoreGo that hasn't reached Tally
  /// yet, so it has no row in tally-api's Tally-synced `bills` table and
  /// won't show up in `LedgerRepository.outstandingBills`. Used to surface
  /// those bills alongside the real Tally ones when picking bills to settle
  /// on a Receipt/Payment entry against the same party.
  Future<List<Map<String, dynamic>>> pendingBills({
    required int ledgerMasterId,
  }) async {
    final result = await _client.getForCompany(
      '/voucher-entries/pending-bills?ledgerMasterId=$ledgerMasterId',
    );
    return (result.data as List).cast<Map<String, dynamic>>();
  }
}
