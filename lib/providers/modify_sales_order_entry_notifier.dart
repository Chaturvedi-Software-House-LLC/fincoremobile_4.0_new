import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../Items.dart' show formatlastsaledate;
import '../ModifySalesOrderEntry.dart';
import '../api/api_exception.dart';
import '../api/godown_repository.dart';
import '../api/group_repository.dart';
import '../api/ledger_repository.dart';
import '../api/monthly_bucket_helper.dart' show parseMoneyField;
import '../api/stock_repository.dart';
import '../api/voucher_entry_repository.dart';
import '../api/voucher_type_repository.dart';

/// Riverpod migration of `ModifySalesOrderEntry.dart`'s
/// `_ModifySalesOrderEntryPageState`. Same verbatim `_commit`/`_snapshot`
/// port strategy as `sales_order_registration_notifier.dart` (its closest
/// sibling by far - read that file's doc-comment first; this Modify screen
/// shares the vast majority of its body-logic).
///
/// This is a "Modify" screen (edits an existing app-originated
/// `VoucherEntry` created via `SalesOrderRegistration.dart`'s create flow)
/// rather than a "Registration" screen (creates a new one), which drives
/// every structural deviation from that sibling:
///
/// - Uses the `.family` pattern (see `modify_user_notifier.dart`'s
///   `ModifyUserArgs`) instead of a plain `.autoDispose` provider, since
///   this notifier needs the `id`/`data` of the specific `VoucherEntry`
///   being edited - passed in as [ModifySalesOrderEntryArgs] from the
///   widget's own constructor-supplied `id`/`isSynced`/`type`/`data`.
///   `isSynced`/`type` are carried through unchanged but never read by
///   this screen (matches the original widget's own constructor fields).
/// - There is an initial-load-by-id step instead of starting blank:
///   [loadData] fetches the same master lists `SalesOrderRegistration.dart`
///   does (via `StockRepository`/`LedgerRepository`/`GroupRepository`/
///   `GodownRepository`/`VoucherTypeRepository` - the original widget's own
///   repository-based style, not the sibling's raw `TallyApiClient`/
///   `fetchAllPages` calls) and then calls the private
///   [_populateFromExistingEntry], which reshapes [args.data] (the same
///   shape `VoucherEntryRepository.getById`/`listAll` return) into every
///   editable field - the edit-mode equivalent of the sibling's blank
///   initial values. See that method's own doc-comment for exactly which
///   `data` fields are read and how the party/sales/VAT ledger rows are
///   re-identified (tally-api's `voucherEntrySchema` has no per-row
///   "ledgerType" tag, so VAT is re-identified by matching against
///   `vatLedgerData`, same as the create flow's own VAT-ledger dropdown
///   resolution).
/// - [loadData] does **not** set `_selecteditem`/`isVisibleLocation`/
///   `selectedLocation`/`unitdata` (dialog-composition-only fields, same
///   as the sibling's own `loadData()` doc-comment) - the widget performs
///   that itself (via `_updateUnitDropdown`) right after `loadData()`
///   resolves, exactly the sibling's pattern. Unlike the sibling, the
///   widget also seeds `_vchnoController`/`controller_narration`/
///   `controller_orderno`/`_partyLedgerController`/`_dateController`/
///   `controller_vatamt`/`controller_totalamt` text from the freshly
///   loaded state at that same point, since this screen must show the
///   *existing* entry's values rather than blank/first-item defaults.
/// - [updateEntry] calls `VoucherEntryRepository.update(args.id, body)`
///   instead of `.create(body)`; body construction otherwise mirrors the
///   sibling's `saveEntry()` exactly (same double-entry amount/isDebit
///   convention). Because this screen lets the user re-edit both the item
///   list and the ledger list, `ledgerEntries`/`inventoryEntries` are
///   always included in full (never omitted) - `update()`'s partial-update
///   semantics only preserve what's omitted from the body, so omitting
///   either here would leave the *old* line items in place server-side.
/// - [fetchVchNos] excludes this entry's own voucher number
///   ([ModifySalesOrderEntryState.originalVoucherNumber], captured by
///   [_populateFromExistingEntry]) from the existence list, so re-saving
///   with the number unchanged never flags itself as a duplicate. Unlike
///   the sibling's `fetchVchNos` (a brand-new entry, so it auto-fills the
///   next suggested number and returns it via `VchNosResult`), this method
///   returns just `Future<String?>` (an error message, or null) - the
///   field already holds the existing entry's own number from
///   `loadData()`, and this only refreshes the existence list
///   for `checkVchNoExistence` while the field is user-editable (see
///   `isVchEditable` below).
/// - There is no `resetAfterSave()` - unlike the sibling (a blank form the
///   user might fill in again), a successful update navigates the widget
///   away to the view screen instead of resetting fields in place (ported
///   unchanged in the widget's own `showSalesOrderDialog`).
/// - Two new state fields not present in the sibling, holding values read
///   once from `args.data` for the widget to seed its own
///   `TextEditingController`s from immediately after `loadData()`
///   resolves: [ModifySalesOrderEntryState.narration] and
///   [ModifySalesOrderEntryState.referenceNo].
/// - `addLedger(String ledgerName, String ledgerAmountText)` preserves a pre-existing
///   bug found while porting, left as-is per the migration's own rule
///   against fixing out-of-scope pre-existing bugs (confirmed via
///   `git show HEAD:lib/ModifySalesOrderEntry.dart` - not something
///   introduced by this migration): it reads
///   `specificLedger['vatapplicable']` (all-lowercase) into a non-nullable
///   `int`, but `ledgerData` rows only ever carry the camelCase
///   `vatApplicable` bool key (see `loadData()` below) - so this lookup is
///   always `null`, and assigning it to `int vatApplicable` throws a
///   runtime `TypeError` the first time a user actually adds a ledger on
///   this screen. `SalesOrderRegistration.dart`'s own `addLedger()` does
///   not have this bug (it already reads camelCase `vatApplicable` as a
///   bool directly) - this divergence is specific to
///   `ModifySalesOrderEntry.dart` and predates this Riverpod migration.
/// - Dialog-composition-only fields that stay widget-local (unmigrated,
///   same treatment as `TextEditingController`s), matching the sibling's
///   own list: `_selectedledger`, `_selecteditem`, `_selectedunit`,
///   `selectedLocation`, `isVisibleLocation`, `isVisibleUnit`, `unitdata`,
///   `selectedMultiplier`, `isVchEditable` (this last one is permanently
///   `false` here - nothing in the original widget ever sets it `true` -
///   so the voucher-number field is always read-only in practice; ported
///   unchanged rather than "fixed", per the same pre-existing-quirk rule
///   above). The `_isFocused_*` group of UI-focus-tracking booleans also
///   stays widget-local, matching how the sibling keeps them.
/// - Dead fields dropped rather than ported (declared/written but never
///   read for logic/UI, confirmed via grep before dropping): `isDashEnable`,
///   `isRolesVisible`, `isUserVisible`, `isUserEnable`, `isRolesEnable`,
///   `isVisibleNoUserFound`, `hostname` (write-only), `company_lowercase`
///   (write-only), `username` (write-only), `HttpURL`, `name`, `email`
///   (all write-only - fed from nav args but never read),
///   `SecuritybtnAcessHolder` (its only reader fed the now-dead
///   `isRolesVisible`/`isUserVisible` pair, so the whole chain is dead),
///   `jsonEntryData` (dead - only referenced inside the already-
///   block-commented legacy `saveEntry()`, same as the last two screens
///   this pattern showed up in), `controller_vchno` (declared, never used
///   anywhere - `_vchnoController` is the real, live voucher-number
///   controller), `progressDialog` (declared, never used),
///   `_isFocused_totalno` (declared, never read). `company` IS live (read
///   by the PDF generator) so it's kept, matching the sibling.
/// - `addItem()` and both copies of `_showItemDetailsPopup` (a
///   block-commented dead legacy copy plus a "live"-looking copy that
///   turned out to have zero call sites anywhere in the file - the
///   single-item-add flow was fully superseded by
///   `_showMultiItemSelectPopup`'s bulk-add flow, exactly as in the
///   sibling) were deleted outright from the widget rather than migrated -
///   confirmed via a whole-file grep for call sites before deleting either.
class ModifySalesOrderEntryArgs {
  final String id;
  final int isSynced;
  final String type;
  final Map<String, dynamic> data;

  const ModifySalesOrderEntryArgs({
    required this.id,
    required this.isSynced,
    required this.type,
    required this.data,
  });

  @override
  bool operator ==(Object other) =>
      other is ModifySalesOrderEntryArgs && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

class ModifySalesOrderEntryState {
  final List<String> vchTypeNameData;
  final List<String> partyLedgerData;
  final List<String> vatLedgerData;
  final List<String> salesLedgerData;
  final List<dynamic> itemData;
  final List<String> locationsData;
  final List<Map<String, dynamic>> ledgerData;
  final List<String> vchNos;

  final List<SaleItem> saleItems;
  final List<LedgerEntry> ledgerEntries;

  final double totalPriceOfItems;
  final double totalAmountForVatAppEntries;
  final double totalAmountOfLedgers;
  final double itemsVatAmount;
  final double ledgerVatAmount;
  final double totalVatAmount;
  final double totalAmount;
  final double roundedTotalVatAmount;
  final double roundedTotalAmount;
  final String formattedVatAmount;
  final String formattedTotalAmount;

  final bool isVisibleItemHeading;
  final bool isVisibleLedgerHeading;

  final bool isLoading;
  final bool isInitialDataLoaded;

  final String? company;
  final String? serialNo;
  final String token;
  final String currencyCode;
  final double vatperc;
  final int? decimal;

  final DateTime saledate;
  final String saledatestring;
  final String saledatetxt;

  final DateTime yearStartDate;
  final DateTime yearEndDate;

  final dynamic selectedVchTypeName;
  final dynamic selectedPartyLedger;
  final dynamic selectedSalesLedger;
  final dynamic selectedVatLedger;

  final String errorMessageVchNo;

  /// This entry's own narration/reference, as loaded from `args.data` -
  /// read once by the widget to seed `controller_narration`/
  /// `controller_orderno` right after `loadData()` resolves.
  final String narration;
  final String referenceNo;

  /// This entry's own voucher number, as loaded from `args.data` -
  /// excluded from [vchNos] in [ModifySalesOrderEntryNotifier.fetchVchNos]
  /// so re-saving with the number unchanged never flags itself as a
  /// duplicate, and read once by the widget to seed `_vchnoController`.
  final String? originalVoucherNumber;

  /// Set when the *initial* [ModifySalesOrderEntryNotifier.loadData] call
  /// (triggered automatically by the notifier's own constructor - there is
  /// no widget-level call site to `await` it directly and show the error
  /// inline) fails. Surfaced via `ref.listenManual` in the widget's
  /// `initState`, then cleared with
  /// [ModifySalesOrderEntryNotifier.clearLoadError] - mirrors
  /// `modify_user_notifier.dart`'s `ModifyUserState.loadError`.
  final String? loadError;

  const ModifySalesOrderEntryState({
    required this.vchTypeNameData,
    required this.partyLedgerData,
    required this.vatLedgerData,
    required this.salesLedgerData,
    required this.itemData,
    required this.locationsData,
    required this.ledgerData,
    required this.vchNos,
    required this.saleItems,
    required this.ledgerEntries,
    required this.totalPriceOfItems,
    required this.totalAmountForVatAppEntries,
    required this.totalAmountOfLedgers,
    required this.itemsVatAmount,
    required this.ledgerVatAmount,
    required this.totalVatAmount,
    required this.totalAmount,
    required this.roundedTotalVatAmount,
    required this.roundedTotalAmount,
    required this.formattedVatAmount,
    required this.formattedTotalAmount,
    required this.isVisibleItemHeading,
    required this.isVisibleLedgerHeading,
    required this.isLoading,
    required this.isInitialDataLoaded,
    required this.company,
    required this.serialNo,
    required this.token,
    required this.currencyCode,
    required this.vatperc,
    required this.decimal,
    required this.saledate,
    required this.saledatestring,
    required this.saledatetxt,
    required this.yearStartDate,
    required this.yearEndDate,
    required this.selectedVchTypeName,
    required this.selectedPartyLedger,
    required this.selectedSalesLedger,
    required this.selectedVatLedger,
    required this.errorMessageVchNo,
    required this.narration,
    required this.referenceNo,
    required this.originalVoucherNumber,
    required this.loadError,
  });
}

/// One resolved row for
/// [ModifySalesOrderEntryNotifier.addSelectedItemsInBulk] - the widget
/// resolves each selected item's editable rate/qty/unit/location/
/// meter-reading `TextEditingController`s into plain values before
/// calling, exactly like `SoBulkAddEntry` in the
/// `sales_order_registration_notifier.dart` sibling.
class SoBulkAddEntry {
  final String name;
  final int quantity;
  final double rate;
  final String unit;
  final String location;
  final String meterFrom;
  final String meterTo;
  SoBulkAddEntry({
    required this.name,
    required this.quantity,
    required this.rate,
    required this.unit,
    required this.location,
    this.meterFrom = '',
    this.meterTo = '',
  });
}

class ModifySalesOrderEntryNotifier
    extends StateNotifier<ModifySalesOrderEntryState> {
  final Ref _ref;
  final ModifySalesOrderEntryArgs args;

  ModifySalesOrderEntryNotifier(this._ref, this.args)
    : super(
        ModifySalesOrderEntryState(
          vchTypeNameData: const [],
          partyLedgerData: const [],
          vatLedgerData: const [],
          salesLedgerData: const [],
          itemData: const [],
          locationsData: const [],
          ledgerData: const [],
          vchNos: const [],
          saleItems: const [],
          ledgerEntries: const [],
          totalPriceOfItems: 0,
          totalAmountForVatAppEntries: 0,
          totalAmountOfLedgers: 0,
          itemsVatAmount: 0,
          ledgerVatAmount: 0,
          totalVatAmount: 0,
          totalAmount: 0,
          roundedTotalVatAmount: 0,
          roundedTotalAmount: 0,
          formattedVatAmount: '0',
          formattedTotalAmount: '0',
          isVisibleItemHeading: false,
          isVisibleLedgerHeading: false,
          isLoading: true,
          isInitialDataLoaded: false,
          company: '',
          serialNo: '',
          token: '',
          currencyCode: '',
          vatperc: 0,
          decimal: 2,
          saledate: DateTime.now(),
          saledatestring: '',
          saledatetxt: '',
          yearStartDate: DateTime(DateTime.now().year, 1, 1),
          yearEndDate: DateTime(DateTime.now().year, 12, 31),
          selectedVchTypeName: null,
          selectedPartyLedger: null,
          selectedSalesLedger: null,
          selectedVatLedger: null,
          errorMessageVchNo: '',
          narration: '',
          referenceNo: '',
          originalVoucherNumber: null,
          loadError: null,
        ),
      ) {
    _init();
  }

  void _commit(void Function() fn) {
    fn();
    state = _snapshot();
  }

  ModifySalesOrderEntryState _snapshot() => ModifySalesOrderEntryState(
    vchTypeNameData: List.unmodifiable(vchtypenamedata),
    partyLedgerData: List.unmodifiable(partyledgerdata),
    vatLedgerData: List.unmodifiable(vatledgerdata),
    salesLedgerData: List.unmodifiable(salesledger_data),
    itemData: List.unmodifiable(itemdata),
    locationsData: List.unmodifiable(locationsdata),
    ledgerData: List.unmodifiable(ledgerdata),
    vchNos: List.unmodifiable(vchnos),
    saleItems: List.unmodifiable(saleItems),
    ledgerEntries: List.unmodifiable(ledgerEntries),
    totalPriceOfItems: totalPriceOfItems,
    totalAmountForVatAppEntries: totalAmountForVatAppEntries,
    totalAmountOfLedgers: totalAmountOfLedgers,
    itemsVatAmount: itemsVatAmount,
    ledgerVatAmount: ledgerVatAmount,
    totalVatAmount: totalVatAmount,
    totalAmount: totalAmount,
    roundedTotalVatAmount: roundedtotalVatAmount,
    roundedTotalAmount: roundedtotalAmount,
    formattedVatAmount: _formatDecimal(roundedtotalVatAmount),
    formattedTotalAmount: _formatDecimal(roundedtotalAmount),
    isVisibleItemHeading: isVisibleItemHeading,
    isVisibleLedgerHeading: isVisibleLedgerHeading,
    isLoading: _isLoading,
    isInitialDataLoaded: _isInitialDataLoaded,
    company: company,
    serialNo: serial_no,
    token: token,
    currencyCode: currencycode,
    vatperc: vatperc,
    decimal: decimal ?? 2,
    saledate: saledate,
    saledatestring: saledatestring,
    saledatetxt: saledatetxt,
    yearStartDate: yearStartDate,
    yearEndDate: yearEndDate,
    selectedVchTypeName: _selectedvchtypename,
    selectedPartyLedger: _selectedpartyledger,
    selectedSalesLedger: _selectedsalesledger,
    selectedVatLedger: _selectedvatledger,
    errorMessageVchNo: errorMessageVchNo,
    narration: narration,
    referenceNo: referenceNo,
    originalVoucherNumber: _originalVoucherNumber,
    loadError: loadError,
  );

  String _formatDecimal(double value) {
    final d = decimal ?? 2;
    return NumberFormat('#,##0.${'0' * d}', 'en_US').format(value);
  }

  // ---- verbatim-ported mutable fields (same names as the original State) ----

  List<String> vchtypenamedata = [];
  List<String> partyledgerdata = [];
  List<String> vatledgerdata = [];
  List<String> salesledger_data = [];
  List<dynamic> itemdata = [];
  List<String> locationsdata = [];
  List<Map<String, dynamic>> ledgerdata = [];
  List<String> vchnos = [];

  // tally-api migration lookup maps (mirrors SalesOrderRegistration.dart's
  // loadData()) - resolve a display name back to the masterId
  // VoucherEntryRepository.update's body needs.
  final Map<String, int> _ledgerMasterIdByName = {};
  final Map<String, int> _godownMasterIdByName = {};
  final Map<String, int> _voucherTypeMasterIdByName = {};
  int? _currencyMasterId;

  List<SaleItem> saleItems = [];
  List<LedgerEntry> ledgerEntries = [];

  double totalPriceOfItems = 0;
  double totalAmountForVatAppEntries = 0;
  double totalAmountOfLedgers = 0;
  double itemsVatAmount = 0;
  double ledgerVatAmount = 0;
  double totalVatAmount = 0;
  double totalAmount = 0;
  double roundedtotalVatAmount = 0;
  double roundedtotalAmount = 0;

  bool isVisibleItemHeading = false;
  bool isVisibleLedgerHeading = false;

  bool _isLoading = true;
  bool _isInitialDataLoaded = false;

  String? company = '';
  String? serial_no = '';
  String token = '';
  String currencycode = '';
  double vatperc = 0;
  int? decimal = 2;

  late DateTime saledate = DateTime.now();
  String saledatestring = '';
  String saledatetxt = '';

  late DateTime now = DateTime.now();
  late DateTime yearStartDate = DateTime(now.year, 1, 1);
  late DateTime yearEndDate = DateTime(now.year, 12, 31);

  final DateFormat _dateFormat = DateFormat('yyyyMMdd');

  dynamic _selectedvchtypename;
  dynamic _selectedpartyledger;
  dynamic _selectedsalesledger;
  dynamic _selectedvatledger;

  String errorMessageVchNo = '';

  String narration = '';
  String referenceNo = '';
  String? _originalVoucherNumber;
  String? loadError;

  /// Clears [loadError] once the widget has surfaced it via
  /// `showAppMessage` - see [ModifySalesOrderEntryState.loadError]'s
  /// doc-comment.
  void clearLoadError() => _commit(() => loadError = null);

  // ---- totals accumulator (highest-risk part, verbatim-ported from the
  // widget's own `_recalculateTotals()`, which itself unified several
  // byte-for-byte-identical duplicate blocks scattered across
  // `_deleteLedger`/`_deleteSaleItem`/`addLedger`/the two reset blocks/
  // `_recalcTotalsAfterBulkAdd`) ---------------------------------------

  void _recalculateTotals() {
    isVisibleItemHeading = saleItems.isNotEmpty;

    totalPriceOfItems = saleItems.fold(0.0, (double previousAmount, SaleItem item) {
      return previousAmount + (item.itemPrice * double.parse(item.itemQuantity));
    });

    if (_selectedvatledger != 'Not Applicable') {
      double vatPerc = vatperc / 100;

      totalAmountForVatAppEntries = ledgerEntries
          .where((entry) => entry.vatApp)
          .fold(0.0, (double prev, LedgerEntry entry) {
            return prev + entry.ledgerAmount;
          });

      ledgerVatAmount = totalAmountForVatAppEntries * vatPerc;
      itemsVatAmount = double.parse(
        (totalPriceOfItems * vatPerc).toStringAsFixed(decimal!),
      );
      totalVatAmount = itemsVatAmount + ledgerVatAmount;

      roundedtotalVatAmount = double.parse(
        totalVatAmount.toStringAsFixed(decimal!),
      );
    } else {
      totalVatAmount = 0;
      roundedtotalVatAmount = double.parse(
        totalVatAmount.toStringAsFixed(decimal!),
      );
    }

    totalAmountOfLedgers = ledgerEntries.fold(
      0.0,
      (double prev, entry) => prev + entry.ledgerAmount,
    );

    totalAmount = totalPriceOfItems + totalAmountOfLedgers + totalVatAmount;
    roundedtotalAmount = double.parse(totalAmount.toStringAsFixed(decimal!));
  }

  /// Verbatim port of the item-card stepper's `onIncrement` body.
  void incrementItemQuantity(int index) {
    _commit(() {
      final item = saleItems[index];
      final currentQty = int.tryParse(item.itemQuantity) ?? 0;
      item.itemQuantity = (currentQty + 1).toString();
      _recalculateTotals();
    });
  }

  /// Verbatim port of the item-card stepper's `onDecrement` body (removes
  /// the line entirely once quantity would drop to 0, matching the
  /// original's `currentQty > 1` guard).
  void decrementItemQuantity(int index) {
    _commit(() {
      final item = saleItems[index];
      final currentQty = int.tryParse(item.itemQuantity) ?? 0;
      if (currentQty > 1) {
        item.itemQuantity = (currentQty - 1).toString();
      } else {
        saleItems.removeAt(index);
      }
      _recalculateTotals();
    });
  }

  /// Verbatim port of `_deleteLedger`'s data-mutation half.
  void deleteLedger(int index) {
    _commit(() {
      ledgerEntries.removeAt(index);
      isVisibleLedgerHeading = ledgerEntries.isNotEmpty;
      _recalculateTotals();
    });
  }

  /// Verbatim port of `_deleteSaleItem`'s data-mutation half.
  void deleteSaleItem(int index) {
    _commit(() {
      saleItems.removeAt(index);
      _recalculateTotals();
    });
  }

  /// Verbatim port of `addLedger()`'s data-mutation half (merge-by-name or
  /// append). The widget resolves [ledgerName]/[ledgerAmountText] from its
  /// dialog-local `_selectedledger`/`ledgerAmountController` before
  /// calling.
  ///
  /// Preserves a pre-existing bug (see this file's own doc-comment above):
  /// reads `specificLedger['vatapplicable']` (all-lowercase) into a
  /// non-nullable `int`, which is always `null` since `ledgerdata` rows
  /// only carry the camelCase `vatApplicable` bool - this throws a runtime
  /// `TypeError` the first time it actually runs. Confirmed pre-existing
  /// via `git show HEAD:lib/ModifySalesOrderEntry.dart` and left
  /// unfixed, per this migration's rule against fixing out-of-scope
  /// pre-existing bugs.
  void addLedger(String ledgerName, String ledgerAmountText) {
    _commit(() {
      Map<String, dynamic>? specificLedger = ledgerdata.firstWhere(
        (ledger) => ledger['name'] == ledgerName,
      );

      final int vatApplicable = specificLedger['vatapplicable'];
      final vatApp = vatApplicable == 1 ? true : false;

      if (ledgerName.isNotEmpty && ledgerAmountText.isNotEmpty) {
        double parsedAmount = double.parse(ledgerAmountText.replaceAll(',', ''));
        int existingIndex = ledgerEntries.indexWhere(
          (entry) => entry.ledgerName == ledgerName,
        );

        if (existingIndex != -1) {
          LedgerEntry existingLedger = ledgerEntries[existingIndex];
          double newAmount = existingLedger.ledgerAmount + parsedAmount;
          ledgerEntries[existingIndex] = existingLedger.updateAmount(
            newAmount,
            vatApp,
          );
        } else {
          ledgerEntries.add(
            LedgerEntry(
              ledgerName: ledgerName,
              ledgerAmount: parsedAmount,
              vatApp: vatApp,
            ),
          );
        }
        isVisibleLedgerHeading = ledgerEntries.isNotEmpty;
        _recalculateTotals();
      }
    });
  }

  /// Verbatim port of `_addSelectedItemsInBulk`'s merge-or-append loop
  /// followed by `_recalcTotalsAfterBulkAdd`'s totals recompute - unified
  /// into the same `_recalculateTotals()` every other mutator uses, same
  /// as the sibling.
  void addSelectedItemsInBulk(List<SoBulkAddEntry> entries) {
    _commit(() {
      for (final entry in entries) {
        final String qty = (entry.quantity < 1 ? 1 : entry.quantity).toString();
        final double amount = double.parse(
          (entry.rate * double.parse(qty)).toStringAsFixed(decimal!),
        );

        final int existingIndex = saleItems.indexWhere(
          (i) =>
              i.itemName == entry.name &&
              double.parse(i.itemPrice.toStringAsFixed(decimal!)) ==
                  double.parse(entry.rate.toStringAsFixed(decimal!)) &&
              i.itemUnit == entry.unit,
        );

        if (existingIndex != -1) {
          final existing = saleItems[existingIndex];
          final String newQty =
              (BigInt.parse(existing.itemQuantity) + BigInt.from(entry.quantity))
                  .toString();
          saleItems[existingIndex] = existing
              .updateQuantity(newQty)
              .updateItemAmount(entry.rate * BigInt.parse(newQty).toDouble());
        } else {
          saleItems.add(
            SaleItem(
              itemName: entry.name,
              itemQuantity: qty,
              itemPrice: entry.rate,
              itemAmount: amount,
              itemLocation: entry.location,
              itemUnit: entry.unit,
              accountingAllocationList: {},
              batchAllocationList: {
                'GODOWNNAME': entry.location,
                'AMOUNT': amount,
                'ACTUALQTY': '$qty ${entry.unit}',
                'BILLEDQTY': '$qty ${entry.unit}',
              },
              meterFrom: entry.meterFrom,
              meterTo: entry.meterTo,
            ),
          );
        }
      }
      _recalculateTotals();
    });
  }

  void setSelectedVchType(String value) {
    _commit(() => _selectedvchtypename = value);
  }

  void setSelectedSalesLedger(String value) {
    _commit(() => _selectedsalesledger = value);
  }

  void setSelectedPartyLedger(String value) {
    _commit(() => _selectedpartyledger = value);
  }

  /// Verbatim port of the VAT-ledger dropdown `onChanged` body.
  void setSelectedVatLedgerAndRecalculate(String value) {
    _commit(() {
      _selectedvatledger = value;
      _recalculateTotals();
    });
  }

  void setSaleDate(DateTime picked) {
    _commit(() {
      saledate = picked;
      saledatestring = _dateFormat.format(saledate);
      saledatetxt = formatlastsaledate(saledatestring);
    });
  }

  /// Verbatim port of `_selectDateRangeVchNo`'s data-mutation half (minus
  /// the trailing, deliberately-not-awaited `fetchvchnos(_selectedvchtypename)`
  /// call - the widget does that itself right after this).
  void setVchNoDateRange(DateTime start, DateTime end) {
    _commit(() {
      yearStartDate = start;
      yearEndDate = end;
    });
  }

  void checkVchNoExistence(String vchNo) {
    _commit(() {
      if (vchNo.isEmpty) {
        errorMessageVchNo = 'Voucher No. cannot be empty';
      } else if (vchnos.contains(vchNo)) {
        errorMessageVchNo =
            'Voucher no: $vchNo against $_selectedvchtypename already exists';
      } else {
        errorMessageVchNo = '';
      }
    });
  }

  // ---- network / data-loading methods (return result info, no context) --

  /// Verbatim port of `loadData()`, minus the `_selecteditem`/
  /// `_itemController.text`/`isVisibleLocation`/`selectedLocation`/
  /// `_updateUnitDropdown(...)` writes at the tail of
  /// `_populateFromExistingEntry()` (widget-local dialog-composition
  /// fields - the widget syncs those, plus all its
  /// `TextEditingController`s, itself right after this resolves).
  Future<String?> loadData() async {
    vchtypenamedata.clear();
    itemdata.clear();
    salesledger_data.clear();
    partyledgerdata.clear();
    vatledgerdata.clear();
    saleItems.clear();
    ledgerEntries.clear();

    ledgerdata.clear();
    locationsdata.clear();
    _ledgerMasterIdByName.clear();
    _godownMasterIdByName.clear();
    _voucherTypeMasterIdByName.clear();

    _commit(() => _isLoading = true);

    try {
      final results = await Future.wait([
        StockRepository.instance.listStockItems(),
        LedgerRepository.instance.listAllLedgers(),
        LedgerRepository.instance.listLedgers(),
        GroupRepository.instance.listAll(),
        GodownRepository.instance.listAll(),
        VoucherTypeRepository.instance.listAll(),
      ]);

      final stockItems = results[0];
      final allLedgers = results[1];
      final partyLedgers = results[2];
      final groups = results[3];
      final godowns = results[4];
      final voucherTypes = results[5];

      // masterIds of every group with tally-api's `'SALES'` GroupReservedName
      // enum label - used to classify "sales ledgers" the same way
      // tally-api's own reports classify sales activity.
      final salesAccountGroupIds = groups
          .where((g) => g['reservedName'] == 'SALES')
          .map((g) => g['masterId'] as int)
          .toSet();

      for (final l in allLedgers) {
        _ledgerMasterIdByName[l['name'] as String] = l['masterId'] as int;
      }
      for (final g in godowns) {
        _godownMasterIdByName[g['name'] as String] = g['masterId'] as int;
      }
      // Only "Sales Order" (Tally's own reservedName, stable regardless of
      // any custom voucher-type naming).
      final salesOrderTypes = voucherTypes
          .where((v) => v['reservedName'] == 'SALES_ORDER')
          .toList();
      for (final v in salesOrderTypes) {
        _voucherTypeMasterIdByName[v['name'] as String] = v['masterId'] as int;
      }

      _commit(() {
        vchtypenamedata = salesOrderTypes.map((v) => v['name'] as String).toList();

        partyledgerdata = partyLedgers.map((l) => l['name'] as String).toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

        // "Sales ledgers" - every ledger under a 'Sales Accounts' group.
        salesledger_data = allLedgers
            .where((l) => salesAccountGroupIds.contains(l['groupMasterId']))
            .map((l) => l['name'] as String)
            .toList();

        // "Other ledgers" (the free-pick "Add Ledger" dropdown) - every
        // ledger not already offered via the Party or Sales Ledger
        // dropdowns above.
        final partyNames = partyledgerdata.toSet();
        final salesNames = salesledger_data.toSet();
        ledgerdata = allLedgers
            .where(
              (l) =>
                  !partyNames.contains(l['name']) &&
                  !salesNames.contains(l['name']),
            )
            .toList();

        // VAT ledgers - tally-api exposes a direct `vatApplicable` flag per
        // ledger.
        vatledgerdata.add('Not Applicable');
        vatledgerdata.addAll(
          allLedgers
              .where((l) => l['vatApplicable'] == true)
              .map((l) => l['name'] as String),
        );

        // Reshapes tally-api's stock-item row into the `name`/`saleprice`/
        // `standardprice`/`unit` shape `_updateUnitDropdown`/
        // `_addSelectedItemsInBulk` already expect - same shaping
        // SalesOrderRegistration.dart's loadData() does.
        itemdata = stockItems.map((item) {
          final List<Map<String, dynamic>> units = [];
          final baseUnitMasterId = item['baseUnitMasterId'] as int?;
          if (baseUnitMasterId != null) {
            units.add({
              'name': item['baseUnitSymbol'] ?? '',
              'multiplier': 1.0,
              'masterId': baseUnitMasterId,
            });
          }
          final additionalUnitMasterId = item['additionalUnitMasterId'] as int?;
          if (additionalUnitMasterId != null) {
            final denominator = parseMoneyField(item['denominator']);
            units.add({
              'name': item['additionalUnitSymbol'] ?? '',
              'multiplier': denominator == 0 ? 1.0 : denominator,
              'masterId': additionalUnitMasterId,
            });
          }
          return {
            'masterId': item['masterId'],
            'name': item['name'],
            'saleprice': item['lastSalePrice'],
            'standardprice': item['stardardPrice'],
            'unit': units,
          };
        }).toList();

        locationsdata = godowns.map((g) => g['name'] as String).toList();

        // Now populate every field from the existing entry being edited.
        _populateFromExistingEntry();
      });
    } on ApiException catch (e) {
      _commit(() {
        _isLoading = false;
        loadError = e.message;
      });
      return e.message;
    } catch (e) {
      const message = 'Could not reach the server. Please try again.';
      _commit(() {
        _isLoading = false;
        loadError = message;
      });
      return message;
    }

    _commit(() => _isLoading = false);
    return null;
  }

  // Populates every editable field from `args.data` (this screen's
  // constructor-supplied entry, shaped like
  // VoucherEntryRepository.getById's response) once the master lists above
  // are loaded - the edit-mode equivalent of the sibling's blank initial
  // values, now reading tally-api's own field names.
  void _populateFromExistingEntry() {
    final data = args.data;
    final ledgerEntriesData =
        ((data['ledgerEntries'] as List?) ?? const [])
            .cast<Map<String, dynamic>>();
    final inventoryEntriesData =
        ((data['inventoryEntries'] as List?) ?? const [])
            .cast<Map<String, dynamic>>();

    final String oldvchname = (data['voucherTypeName'] as String?) ??
        (vchtypenamedata.isNotEmpty ? vchtypenamedata[0] : '');
    final String oldvchno = (data['voucherNumber'] as String?) ?? '';
    final String oldnarration = (data['narration'] as String?) ?? '';
    final String oldrefno = (data['reference'] as String?) ?? '';

    _originalVoucherNumber = oldvchno;
    _selectedvchtypename = oldvchname;
    fetchVchNos(_selectedvchtypename);

    narration = oldnarration;
    referenceNo = oldrefno;

    saledate = DateTime.parse(data['date'] as String);
    saledatestring = _dateFormat.format(saledate);
    saledatetxt = formatlastsaledate(saledatestring);

    _currencyMasterId = data['currencyMasterId'] as int?;

    // Party ledger - the ledgerEntries row flagged isPartyLedger.
    final Map<String, dynamic> partyEntry = ledgerEntriesData.firstWhere(
      (e) => e['isPartyLedger'] == true,
      orElse: () => const {},
    );
    final String oldpartyledger = (partyEntry['ledgerName'] as String?) ??
        (partyledgerdata.isNotEmpty ? partyledgerdata[0] : '');
    _selectedpartyledger = oldpartyledger;

    // Sales ledger - the ledgerMasterId booked against the first inventory
    // entry (mirrors legacy reading ACCOUNTINGALLOCATIONS.LIST[0].LEDGERNAME
    // on the first item).
    if (inventoryEntriesData.isNotEmpty) {
      final String? saleLedgerName =
          inventoryEntriesData.first['ledgerName'] as String?;
      if (saleLedgerName != null) {
        _selectedsalesledger = saleLedgerName;
      }
    }
    _selectedsalesledger ??=
        (salesledger_data.isNotEmpty ? salesledger_data[0] : null);
    final int? salesLedgerMasterId = inventoryEntriesData.isNotEmpty
        ? inventoryEntriesData.first['ledgerMasterId'] as int?
        : null;

    // Remaining ledgerEntries rows (excluding party and sales ledger rows)
    // are either the designated VAT ledger or a free "Add Ledger" entry.
    // tally-api's voucherEntrySchema has no equivalent of legacy's per-row
    // "ledgerType" tag, so the VAT ledger is re-identified here by matching
    // against vatledgerdata (built above from each ledger's own
    // `vatApplicable` flag) - the first such match is treated as "the" VAT
    // ledger row (matches the create flow, which only ever adds one); any
    // further rows fall back to the free "Add Ledger" list, with `vatApp`
    // resolved the same way the "Add Ledger" UI itself resolves it (from
    // the ledger's own `vatApplicable` flag in `ledgerdata`).
    ledgerEntries.clear();
    bool vatLedgerFound = false;
    totalVatAmount = 0;
    for (final entry in ledgerEntriesData) {
      final int? ledgerMasterId = entry['ledgerMasterId'] as int?;
      if (ledgerMasterId == null) continue;
      if (entry['isPartyLedger'] == true) continue;
      if (salesLedgerMasterId != null && ledgerMasterId == salesLedgerMasterId) {
        continue;
      }

      final String ledgerName = (entry['ledgerName'] as String?) ?? '';
      final double amount = parseMoneyField(entry['amount']);

      if (!vatLedgerFound && vatledgerdata.contains(ledgerName)) {
        vatLedgerFound = true;
        _selectedvatledger = ledgerName;
        totalVatAmount = amount;
        continue;
      }

      final Map<String, dynamic> ledgerInfo = ledgerdata
          .cast<Map<String, dynamic>>()
          .firstWhere((l) => l['name'] == ledgerName, orElse: () => const {});
      final bool vatApp = ledgerInfo['vatApplicable'] == true;

      ledgerEntries.add(
        LedgerEntry(ledgerName: ledgerName, ledgerAmount: amount, vatApp: vatApp),
      );
    }
    if (!vatLedgerFound) {
      _selectedvatledger = (vatledgerdata.isNotEmpty ? vatledgerdata[0] : null);
    }

    roundedtotalVatAmount = double.parse(totalVatAmount.toStringAsFixed(decimal!));

    isVisibleLedgerHeading = ledgerEntries.isNotEmpty;

    // Total amount - the party ledger's own (debited) amount is the
    // invoice total.
    totalAmount = parseMoneyField(partyEntry['amount']);
    roundedtotalAmount = double.parse(totalAmount.toStringAsFixed(decimal!));

    // Items
    saleItems.clear();
    for (final itemData in inventoryEntriesData) {
      final String itemName = (itemData['stockItemName'] as String?) ?? '';
      final double quantity = parseMoneyField(itemData['quantity']);
      final String parsedQuantity = _trimTrailingZeros(quantity);
      final double itemPrice = parseMoneyField(itemData['rate']);
      final String itemUnit = (itemData['unitSymbol'] as String?) ?? '';
      final double itemAmount = parseMoneyField(itemData['amount']);

      final batchAllocations =
          ((itemData['batchAllocations'] as List?) ?? const [])
              .cast<Map<String, dynamic>>();
      final String itemLocation = batchAllocations.isNotEmpty
          ? (batchAllocations.first['godownName'] as String?) ?? ''
          : '';

      // accountingAllocationList/batchAllocationList are kept only for
      // shape-compatibility with SaleItem's constructor - updateEntry()
      // below rebuilds the ledgerEntries/inventoryEntries payload fresh
      // from saleItems/ledgerEntries rather than round-tripping these.
      final Map<String, dynamic> accountingAllocationList = {
        'LEDGERNAME': itemData['ledgerName'] ?? _selectedsalesledger,
        'AMOUNT': itemAmount.toStringAsFixed(decimal!),
        'ISDEEMEDPOSITIVE': 'No',
      };
      final Map<String, dynamic> batchAllocationList = {
        'GODOWNNAME': itemLocation,
        'AMOUNT': itemAmount,
        'ACTUALQTY': '$parsedQuantity $itemUnit',
        'BILLEDQTY': '$parsedQuantity $itemUnit',
      };

      saleItems.add(
        SaleItem(
          itemName: itemName,
          itemQuantity: parsedQuantity,
          itemPrice: itemPrice,
          itemAmount: itemAmount,
          itemLocation: itemLocation,
          itemUnit: itemUnit,
          accountingAllocationList: accountingAllocationList,
          batchAllocationList: batchAllocationList,
        ),
      );
    }
    isVisibleItemHeading = saleItems.isNotEmpty;
  }

  // "12.0000" -> "12", "12.5000" -> "12.5" - keeps a reconstructed
  // SaleItem.itemQuantity/rate string looking like something a user would
  // have actually typed, rather than tally-api's raw fixed 4-decimal money-
  // field formatting.
  String _trimTrailingZeros(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    String s = value.toString();
    if (s.contains('.')) {
      s = s.replaceFirst(RegExp(r'0+$'), '');
      s = s.replaceFirst(RegExp(r'\.$'), '');
    }
    return s;
  }

  // Backed by tally-api's `GET .../voucher-entries/voucher-numbers` (see
  // `VoucherEntryRepository.voucherNumbers`'s doc-comment). Unlike the
  // sibling's `fetchVchNos` (a brand-new entry, so it auto-fills the next
  // suggested number), this Modify screen already has the existing entry's
  // own voucher number set by `loadData()` - this only refreshes the
  // existence list for `checkVchNoExistence` while the field is
  // user-editable (`isVchEditable`, checked by the widget's own thin
  // wrapper - see this file's doc-comment above). This entry's own
  // [_originalVoucherNumber] is excluded (one occurrence) so re-saving
  // with it unchanged never flags itself as a duplicate.
  Future<String?> fetchVchNos(String vchname) async {
    vchnos.clear();
    _commit(() => _isLoading = true);

    try {
      final int? voucherTypeMasterId = _voucherTypeMasterIdByName[vchname];

      if (voucherTypeMasterId != null) {
        final String fromParam = DateFormat('yyyy-MM-dd').format(yearStartDate);
        final String toParam = DateFormat('yyyy-MM-dd').format(yearEndDate);

        final fetched = await VoucherEntryRepository.instance.voucherNumbers(
          voucherTypeMasterId: voucherTypeMasterId,
          from: fromParam,
          to: toParam,
        );

        vchnos = List<String>.from(fetched);
        final ownNumber = _originalVoucherNumber;
        if (ownNumber != null) {
          final ownIndex = vchnos.indexOf(ownNumber);
          if (ownIndex != -1) vchnos.removeAt(ownIndex);
        }
      }

      _commit(() {
        vchnos.sort((a, b) {
          RegExp regExp = RegExp(r'(\d+)(?!.*\d)');
          int numA = int.tryParse(regExp.firstMatch(a)?.group(0) ?? '0') ?? 0;
          int numB = int.tryParse(regExp.firstMatch(b)?.group(0) ?? '0') ?? 0;
          return numA.compareTo(numB);
        });
      });
    } on ApiException catch (e) {
      vchnos.clear();
      _commit(() => _isLoading = false);
      return e.message;
    } catch (e) {
      vchnos.clear();
      _commit(() => _isLoading = false);
      return 'Could not reach the server. Please try again.';
    }

    _commit(() => _isLoading = false);
    return null;
  }

  /// Verbatim port of `updateEntry()`'s payload-building/submit logic,
  /// minus the pre-save validation (party ledger/sale-items-empty checks,
  /// which read `context` via `showAppMessage` - the widget performs those
  /// itself before calling this) and minus the trailing
  /// `showSalesOrderDialog(...)` call (pure UI). Calls
  /// `VoucherEntryRepository.update(args.id, body)` instead of
  /// `SalesOrderRegistration.dart`'s `.create(body)` - see this file's
  /// doc-comment above for why `ledgerEntries`/`inventoryEntries` are
  /// always sent in full.
  Future<String?> updateEntry({
    required String narration,
    required String vchno,
    required String refno,
  }) async {
    _commit(() => _isLoading = true);

    double totalItemAmount = 0.0;
    for (SaleItem item in saleItems) {
      totalItemAmount += item.itemAmount;
    }

    final int? voucherTypeMasterId = _voucherTypeMasterIdByName[_selectedvchtypename];
    final int? partyLedgerMasterId = _ledgerMasterIdByName[_selectedpartyledger];
    final int? salesLedgerMasterId = _ledgerMasterIdByName[_selectedsalesledger];
    final int? currencyMasterId = _currencyMasterId;

    if (voucherTypeMasterId == null) {
      _commit(() => _isLoading = false);
      return 'Please select a Voucher Type';
    }
    if (partyLedgerMasterId == null) {
      _commit(() => _isLoading = false);
      return 'Unknown Party Ledger - please reselect it';
    }
    if (salesLedgerMasterId == null) {
      _commit(() => _isLoading = false);
      return 'Please select a Sales Ledger';
    }
    if (currencyMasterId == null) {
      _commit(() => _isLoading = false);
      return 'Could not resolve the company currency';
    }

    // Builds each inventory entry - resolves stockItemMasterId/unitMasterId
    // from the same itemdata list the item/unit dropdowns use.
    // godownMasterId comes from the item's chosen location; when the
    // company has no godowns at all, batchAllocations is omitted for that
    // item entirely rather than guessing, since tally-api requires a real
    // godownMasterId on every batch row.
    final List<Map<String, dynamic>> inventoryEntries = [];
    for (final item in saleItems) {
      final Map<String, dynamic> itemInfo = itemdata
          .cast<Map<String, dynamic>>()
          .firstWhere((i) => i['name'] == item.itemName, orElse: () => {});
      final int? stockItemMasterId = itemInfo['masterId'] as int?;
      final List<Map<String, dynamic>> units =
          ((itemInfo['unit'] as List?) ?? const []).cast<Map<String, dynamic>>();
      final Map<String, dynamic> unitInfo = units.firstWhere(
        (u) => u['name'] == item.itemUnit,
        orElse: () => {},
      );
      final int? unitMasterId = unitInfo['masterId'] as int?;

      if (stockItemMasterId == null || unitMasterId == null) {
        _commit(() => _isLoading = false);
        return 'Could not resolve item/unit for "${item.itemName}" - please re-add it';
      }

      final int? godownMasterId = _godownMasterIdByName[item.itemLocation];
      final quantity = double.tryParse(item.itemQuantity) ?? 0;

      inventoryEntries.add({
        'stockItemMasterId': stockItemMasterId,
        'quantity': quantity,
        'rate': item.itemPrice,
        'unitMasterId': unitMasterId,
        'amount': item.itemAmount,
        'ledgerMasterId': salesLedgerMasterId,
        'isDebitQuantity': false,
        if (godownMasterId != null)
          'batchAllocations': [
            {
              'godownMasterId': godownMasterId,
              // tally-api requires a batchName on every allocation row;
              // this screen has no batch-tracking UI of its own, so
              // 'Primary' - Tally's own default batch name for
              // non-batch-tracked stock items - is used here.
              'batchName': 'Primary',
              'quantity': quantity,
            },
          ],
      });
    }

    double totalLedgerAmount = 0.0;
    for (LedgerEntry ledger in ledgerEntries) {
      totalLedgerAmount += ledger.ledgerAmount;
    }

    // Double-entry ledgerEntries: the Party ledger is debited for the full
    // invoice value; the Sales ledger, any additional ledgers, and VAT
    // (when applicable) are credited for their respective shares.
    final double partyLedgerAmount =
        totalVatAmount + totalItemAmount + totalLedgerAmount;

    final List<Map<String, dynamic>> ledgerEntriesPayload = [
      {
        'ledgerMasterId': partyLedgerMasterId,
        'amount': partyLedgerAmount,
        'isDebit': true,
        'isPartyLedger': true,
      },
      {
        'ledgerMasterId': salesLedgerMasterId,
        'amount': totalItemAmount,
        'isDebit': false,
        'isPartyLedger': false,
      },
    ];

    for (final entry in ledgerEntries) {
      final int? ledgerMasterId = _ledgerMasterIdByName[entry.ledgerName];
      if (ledgerMasterId == null) {
        _commit(() => _isLoading = false);
        return 'Could not resolve one of the added ledgers';
      }
      ledgerEntriesPayload.add({
        'ledgerMasterId': ledgerMasterId,
        'amount': entry.ledgerAmount,
        'isDebit': false,
        'isPartyLedger': false,
      });
    }

    if (_selectedvatledger != 'Not Applicable') {
      final int? vatLedgerMasterId = _ledgerMasterIdByName[_selectedvatledger];
      if (vatLedgerMasterId == null) {
        _commit(() => _isLoading = false);
        return 'Could not resolve the VAT ledger';
      }
      ledgerEntriesPayload.add({
        'ledgerMasterId': vatLedgerMasterId,
        'amount': roundedtotalVatAmount,
        'isDebit': false,
        'isPartyLedger': false,
      });
    }

    final Map<String, dynamic> body = {
      'voucherTypeMasterId': voucherTypeMasterId,
      'date': DateFormat('yyyy-MM-dd').format(saledate),
      'currencyMasterId': currencyMasterId,
      'narration': narration,
      'reference': refno,
      if (vchno.isNotEmpty) 'voucherNumber': vchno,
      'ledgerEntries': ledgerEntriesPayload,
      'inventoryEntries': inventoryEntries,
    };

    String? error;
    try {
      await VoucherEntryRepository.instance.update(args.id, body);
    } on ApiException catch (e) {
      error = e.message;
    } catch (e) {
      error = 'Could not reach the server. Please try again.';
    }

    _commit(() => _isLoading = false);
    return error;
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();

    company = prefs.getString('company_name');
    serial_no = prefs.getString('serial_no');
    token = prefs.getString('token') ?? '';
    currencycode = prefs.getString('currencycode') ?? 'AED';

    vatperc = prefs.getDouble('vatperc') ?? 5.0;
    decimal = prefs.getInt('decimalplace') ?? 2;

    // `data['date']` (camelCase, ISO date string) - loadData() (called just
    // below) re-derives this from the same field once master data is
    // loaded via `_populateFromExistingEntry()`, so this is only the
    // initial value used before that finishes.
    saledate = DateTime.parse(args.data['date'] as String);
    saledatestring = _dateFormat.format(saledate);
    saledatetxt = formatlastsaledate(saledatestring);

    _commit(() {});

    await loadData();
    _commit(() => _isInitialDataLoaded = true);
  }
}

final modifySalesOrderEntryNotifierProvider = StateNotifierProvider.autoDispose
    .family<ModifySalesOrderEntryNotifier, ModifySalesOrderEntryState, ModifySalesOrderEntryArgs>(
  (ref, args) => ModifySalesOrderEntryNotifier(ref, args),
);
