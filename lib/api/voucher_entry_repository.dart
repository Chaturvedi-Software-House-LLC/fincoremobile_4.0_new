import 'pagination_helper.dart';
import 'tally_api_client.dart';

/// One page of a `/voucher-entries` list call - see [VoucherRepository]'s
/// `VoucherPage` (the same shape) for why a caller wanting real incremental
/// (infinite-scroll) loading needs this instead of [VoucherEntryRepository.listAll]'s
/// "fetch every page up front" behavior.
class VoucherEntryPage {
  VoucherEntryPage({
    required this.items,
    required this.page,
    required this.totalPages,
  });

  final List<Map<String, dynamic>> items;
  final int page;
  final int totalPages;
}

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

  /// One raw page of `/voucher-entries` (server's own `date DESC, id DESC`
  /// order - no server-side `voucherTypeMasterId` filter exists on this
  /// endpoint, unlike `/vouchers`, so a caller narrowing to one voucher
  /// type - the Pending*Entry screens' "my drafts of this type" view -
  /// must still filter client-side per page, same as before [listAll] was
  /// an option; this just lets that happen incrementally instead of
  /// fetching every page up front).
  Future<VoucherEntryPage> listPage({required int page, int limit = 20}) async {
    final result = await _client.getForCompany(
      '/voucher-entries?page=$page&limit=$limit',
    );
    return VoucherEntryPage(
      items: (result.data as List).cast<Map<String, dynamic>>(),
      page: page,
      // Same `lastPage`-not-`totalPages` naming quirk as VoucherRepository.listPage.
      totalPages: (result.meta?['lastPage'] as int?) ?? 1,
    );
  }

  /// `GET .../voucher-entries/voucher-numbers` - server-side "voucher
  /// numbers already in use" for [voucherTypeMasterId] in `[from, to]`,
  /// unioning this app's own draft `VoucherEntry.voucherNumber`s with the
  /// real Tally-synced `Voucher.number`s. Replaces the older client-side
  /// approach (fetching every `VoucherEntry` via [listAll] and filtering by
  /// voucher type/date) that every Registration/Modify screen's
  /// `fetchvchnos()` used to hand-roll - that approach only ever saw this
  /// app's own drafts, so it could suggest/allow a number Tally itself
  /// already has, causing a real collision once the outbound-push-to-Tally
  /// job (still not built - see this class's own doc-comment) eventually
  /// ships. [from]/[to] are `YYYY-MM-DD`; [to] is optional (defaults to
  /// unbounded on the server).
  Future<List<String>> voucherNumbers({
    required int voucherTypeMasterId,
    required String from,
    String? to,
  }) async {
    final query = <String, String>{
      'voucherTypeMasterId': '$voucherTypeMasterId',
      'from': from,
      if (to != null) 'to': to,
    };
    final queryString = query.entries
        .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    final result = await _client.getForCompany(
      '/voucher-entries/voucher-numbers?$queryString',
    );
    final data = result.data as Map<String, dynamic>;
    return (data['voucherNumbers'] as List? ?? const [])
        .map((v) => v.toString())
        .toList();
  }

  /// Server-computed suggested next voucher number for [voucherTypeMasterId]
  /// - replaces downloading the full [voucherNumbers] list and running the
  /// pattern-matching locally (`generateNextVchNo` in each registration
  /// notifier), which meant re-scanning a company's entire voucher history
  /// on every entry screen open. Same `from`/`to` semantics as
  /// [voucherNumbers].
  Future<String> nextVoucherNumber({
    required int voucherTypeMasterId,
    required String from,
    String? to,
  }) async {
    final query = <String, String>{
      'voucherTypeMasterId': '$voucherTypeMasterId',
      'from': from,
      if (to != null) 'to': to,
    };
    final queryString = query.entries
        .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    final result = await _client.getForCompany(
      '/voucher-entries/next-voucher-number?$queryString',
    );
    final data = result.data as Map<String, dynamic>;
    return data['voucherNumber'] as String? ?? '1';
  }

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
