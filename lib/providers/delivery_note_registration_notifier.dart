import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../Items.dart' show formatlastsaledate;
import '../DeliveryNoteRegistration.dart';
import '../api/api_exception.dart';
import '../api/monthly_bucket_helper.dart' show parseCompactDate;
import '../api/pagination_helper.dart';
import '../api/stock_repository.dart';
import '../api/tally_api_client.dart';
import '../api/voucher_entry_repository.dart';
import '../constants.dart' show vanSalesSerialNo, isUniGasSerial;

/// Riverpod migration of `DeliveryNoteRegistration.dart`'s
/// `_DeliverynoteregistrationPageState`. Same verbatim `_commit`/`_snapshot`
/// port strategy as `sales_registration_notifier.dart` (its closest sibling
/// structurally - an item+ledger accumulator screen - read that file's
/// doc-comment first), with several screen-specific deviations below.
///
/// Structural deviations from `sales_registration_notifier.dart`:
/// - Delivery Note has no separate "Rate/VAT-on-sale" invoicing intent - it
///   still carries a VAT ledger/amount section (mirrored verbatim from
///   Sales), but is otherwise a stock-movement document. No meterFrom/meterTo
///   UniGas quirk from `SalesOrderRegistration` either... except it DOES: this
///   screen shares UniGas's van/gas-delivery serial concept but adds a
///   *third*, Delivery-Note-only wrinkle on top of Sales/SalesOrder's UniGas
///   handling - **bulk (tanker) gas deliveries** (`_isBulkDelivery`), which
///   are metered (single item, mandatory start/end meter reading, mandatory
///   Receiver Name/Signature, optional Receiver Mobile/EID#) as opposed to
///   normal counted cylinder deliveries. `_isBulkDelivery` is migrated state
///   (read by `saveEntry`'s validation-adjacent logic and by the bulk-add
///   flow) - resolved once per entry from the device's cached
///   "spectra_allocations" `is_bulk` allocation flag, reset to `null` after
///   each save/share so the next entry re-resolves it.
/// - This screen's item-add flow was refactored, in the pre-migration
///   source, from a single-item dialog (`_showItemDetailsPopup`/`addItem()`)
///   to a bulk multi-item picker (`_showMultiItemSelectPopup`/
///   `_addSelectedItemsInBulk`) wired as the *sole* way to add items - the
///   "+" button in `build()` calls `_onAddItemTapped` ->
///   `_showMultiItemSelectPopup` only. `_showItemDetailsPopup`/`addItem()`
///   (plus a commented-out even-older copy of the single-item dialog, and
///   the now-orphaned `resetItemDialogFields`/`updateRateAndAmount`/
///   `updateAmount`/`fetchPriceLevelDetailsForSelectedItem` helpers that only
///   the dead popup called) were confirmed to have **zero** live call sites
///   (grepped before removal - `_showItemDetailsPopup(` and `addItem()` only
///   ever matched their own definitions/comments) and were deleted outright
///   from the widget rather than migrated, mirroring the exact precedent
///   from `SalesOrderRegistration`'s own migration (its doc-comment notes
///   the identical "single-item flow fully superseded by bulk picker"
///   situation). `_selectDateRangeVchNo` (a voucher-no date-range picker) was
///   likewise confirmed dead - its only call site was inside an
///   already-block-commented `GestureDetector` in `build()` - and deleted;
///   `yearStartDate`/`yearEndDate` themselves stay (still read by
///   `_init`/`fetchVchNos`), just no longer interactively adjustable.
/// - `addBulkItems` (the notifier-side merge-or-append half of
///   `_addSelectedItemsInBulk`) takes fully-resolved [DnBulkEntry] rows -
///   the widget still does all the dialog-side resolution (unit/rate/qty/
///   meter-reading/description-controller reads, price-level lookups) since
///   those need `itemdata`/dialog-local `TextEditingController`s, then hands
///   plain values to the notifier, exactly mirroring
///   `sales_registration_notifier.dart`'s `BulkAddEntry`/`addSelectedItemsInBulk`.
/// - `addOrMergeLedger` preserves a genuine pre-existing bug verbatim rather
///   than fixing it (out of scope per this migration's rules): this screen's
///   own `ledgerdata` rows are built by `loadData()` as bare `{'name': ...}`
///   maps with **no** `'vatapplicable'` key at all (unlike
///   `sales_registration_notifier.dart`'s `ledgerdata`, which does carry
///   one) - so `ledgerRow['vatapplicable']` is always `null`, and assigning
///   that to the non-nullable `int vatApplicable` throws a runtime
///   `TypeError` the moment a ledger is actually added. This was true of the
///   pre-migration widget code too (`int vatApplicable =
///   specificLedger['vatapplicable'];` with no key ever populated) - kept
///   byte-for-byte here, not patched.
/// - `loadLedgerData` returns a [DnLedgerLookupResult] (or `null` on
///   "ledger not found") instead of calling `showDeliveryNoteDialog(context,
///   ...)` itself - that's pure UI (needs `context`), so the widget's own
///   `loadLedgerData()` wrapper makes that call using the result, mirroring
///   `sales_registration_notifier.dart`'s identically-shaped
///   `LedgerLookupResult`.
/// - `fetchVchNos` returns a [DnVchNosResult] (error + generated next
///   voucher number) instead of writing `_vchnoController.text` itself (a
///   widget-local controller) - mirrors
///   `sales_order_registration_notifier.dart`'s `VchNosResult`.
/// - `saveEntry` takes an already-resolved `referenceDate` (yyyyMMdd) rather
///   than reading `refdatestring`/a widget-local `_refdateController`
///   fallback itself - the pre-migration `saveEntry()` fell back to parsing
///   `_refdateController.text` (a widget-local field) when `refdatestring`
///   was blank; the widget resolves that exact fallback itself (unchanged
///   logic) and passes the final string in, since the notifier has no
///   access to widget-local controllers.
/// - The old Tally-XML-shaped `jsonEntryData` map `saveEntry()` used to
///   build in parallel with the real tally-api request body was dead code
///   (only ever read back by a commented-out `print(jsonEntryData)`) even
///   before this migration - dropped entirely here, along with the
///   `LEDGERENTRIES.LIST`/`INVENTORYENTRIES.LIST` construction blocks that
///   fed it. The `accountingAllocationList` default-fill loop is NOT dead
///   (its result feeds the real `inventoryEntries` payload's ledger lookup)
///   and is kept.
/// - Dialog-composition-only fields that stay widget-local (unmigrated,
///   same treatment as `TextEditingController`s, per this migration's
///   established convention): `_selectedledger`, `_selecteditem`,
///   `_selectedunit`, `selectedItemMasterId`, `unitdata`, `selectedLocation`,
///   `isVisibleUnit`, `isVisibleLocation`, `selectedMultiplier`,
///   `isRateFieldEnabled`, `showRateField`, `isPriceLevelLoading`,
///   `meterReadingError` (a validation-message field read/written by both
///   the item picker and an inline meter-reading check in the Save button,
///   always via the *outer* widget's own `setState` in the original - kept
///   exactly that way, still a plain widget field). `bulkReceiverNameController`/
///   `bulkReceiverMobileController`/`bulkReceiverEidController`/
///   `bulkReceiverSignatureBytes` (UniGas bulk-delivery "Receiver
///   Information", presentation-only until a future outbound Tally push)
///   stay widget-local alongside the other controllers.
///
/// Dead fields dropped rather than ported (confirmed unreferenced outside
/// their own declaration/assignment via a whole-file grep): `isDashEnable`,
/// `isUserEnable`, `isRolesEnable`, `isVisibleNoUserFound`,
/// `isRolesVisible`/`isUserVisible` (write-only - only ever assigned inside
/// `_initSharedPreferences`, never read), `user_email_fetched`, `unitValue`,
/// `HttpURL`, `company_lowercase`/`username` (write-only), `email`
/// (write-only - unlike `name`, which IS live, read by both non-UniGas and
/// UniGas PDF formats' "Delivered by"/"Driver / Operator" lines),
/// `isVchEditable` (declared, never read or written anywhere else),
/// `isValidEmail` (declared, never called), `jsonEntryData` (see above).
class DeliveryNoteRegistrationState {
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
  final bool isVoucherTypeLocked;
  final bool isSalesLedgerLocked;
  final bool isGodownLocked;

  final bool isLoading;
  final bool isInitialDataLoaded;

  final String? company;
  final String? serialNo;
  final String token;
  final String currencyCode;
  final String startfrom;
  final String companyTrn;
  final String companyAddress;
  final String companyEmirate;
  final String companyCountry;
  final double vatperc;
  final int decimal;
  final String? securitybtnAccessHolder;
  final String name;

  final DateTime saledate;
  final DateTime refdate;
  final String saledatestring;
  final String saledatetxt;
  final String refdatestring;
  final String refdatetxt;

  final DateTime yearStartDate;
  final DateTime yearEndDate;

  final dynamic selectedVchTypeName;
  final dynamic selectedPartyLedger;
  final dynamic selectedSalesLedger;
  final dynamic selectedVatLedger;

  final String errorMessageVchNo;

  final String? selectedPartyMobile;
  final String? selectedPartyEmail;
  final String? selectedPartyLedgerPriceLevel;
  final Map<String, String?> partyLedgerPriceLevelMap;

  final bool? isBulkDelivery;

  const DeliveryNoteRegistrationState({
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
    required this.isVoucherTypeLocked,
    required this.isSalesLedgerLocked,
    required this.isGodownLocked,
    required this.isLoading,
    required this.isInitialDataLoaded,
    required this.company,
    required this.serialNo,
    required this.token,
    required this.currencyCode,
    required this.startfrom,
    required this.companyTrn,
    required this.companyAddress,
    required this.companyEmirate,
    required this.companyCountry,
    required this.vatperc,
    required this.decimal,
    required this.securitybtnAccessHolder,
    required this.name,
    required this.saledate,
    required this.refdate,
    required this.saledatestring,
    required this.saledatetxt,
    required this.refdatestring,
    required this.refdatetxt,
    required this.yearStartDate,
    required this.yearEndDate,
    required this.selectedVchTypeName,
    required this.selectedPartyLedger,
    required this.selectedSalesLedger,
    required this.selectedVatLedger,
    required this.errorMessageVchNo,
    required this.selectedPartyMobile,
    required this.selectedPartyEmail,
    required this.selectedPartyLedgerPriceLevel,
    required this.partyLedgerPriceLevelMap,
    required this.isBulkDelivery,
  });
}

/// Result of [DeliveryNoteRegistrationNotifier.loadLedgerData] - `null` means
/// "ledger not found" (the widget shows that message itself); otherwise the
/// widget calls `showDeliveryNoteDialog(context, ...)` with these values,
/// mirroring `sales_registration_notifier.dart`'s `LedgerLookupResult`.
class DnLedgerLookupResult {
  final String tin;
  final String address;
  final String emirate;
  final String country;
  DnLedgerLookupResult({
    required this.tin,
    required this.address,
    required this.emirate,
    required this.country,
  });
}

/// Result of [DeliveryNoteRegistrationNotifier.fetchVchNos] - the widget sets
/// `_vchnoController.text` itself from [nextVchNo], mirroring
/// `sales_order_registration_notifier.dart`'s `VchNosResult`.
class DnVchNosResult {
  final String? error;
  final String nextVchNo;
  DnVchNosResult({required this.error, required this.nextVchNo});
}

/// Result of [DeliveryNoteRegistrationNotifier.saveEntry]. Three distinct
/// outcomes, mirroring the pre-migration `saveEntry()`'s three branches
/// exactly: [success] (widget refreshes the party ledger and shows the
/// delivery-note dialog), [errorMessage] non-null (an `ApiException` - the
/// widget shows it via `showAppMessage`), or neither (a generic exception -
/// the original swallowed this silently with only a `print(e)`, no message
/// shown and no dialog opened; preserved verbatim rather than "improved").
class DnSaveResult {
  final bool success;
  final String? errorMessage;
  const DnSaveResult({required this.success, this.errorMessage});
}

/// One resolved row for [DeliveryNoteRegistrationNotifier.addBulkItems] - the
/// widget resolves each selected item's editable rate/qty/unit/meter-reading/
/// description `TextEditingController`s (plus the currently-selected godown)
/// into plain values before calling, mirroring
/// `sales_registration_notifier.dart`'s `BulkAddEntry`.
class DnBulkEntry {
  final String name;
  final String unitName;
  final int quantity;
  final double rate;
  final String location;
  final String meterFrom;
  final String meterTo;
  final List<String> descriptions;
  final int? itemMasterId;
  DnBulkEntry({
    required this.name,
    required this.unitName,
    required this.quantity,
    required this.rate,
    required this.location,
    required this.meterFrom,
    required this.meterTo,
    required this.descriptions,
    required this.itemMasterId,
  });
}

class DeliveryNoteRegistrationNotifier
    extends StateNotifier<DeliveryNoteRegistrationState> {
  final Ref _ref;

  DeliveryNoteRegistrationNotifier(this._ref)
    : super(
        DeliveryNoteRegistrationState(
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
          isVoucherTypeLocked: false,
          isSalesLedgerLocked: false,
          isGodownLocked: false,
          isLoading: true,
          isInitialDataLoaded: false,
          company: '',
          serialNo: '',
          token: '',
          currencyCode: '',
          startfrom: '',
          companyTrn: 'null',
          companyAddress: 'null',
          companyEmirate: 'null',
          companyCountry: 'null',
          vatperc: 0,
          decimal: 2,
          securitybtnAccessHolder: '',
          name: '',
          saledate: DateTime.now(),
          refdate: DateTime.now(),
          saledatestring: '',
          saledatetxt: '',
          refdatestring: '',
          refdatetxt: '',
          yearStartDate: DateTime(DateTime.now().year, 1, 1),
          yearEndDate: DateTime(DateTime.now().year, 12, 31),
          selectedVchTypeName: null,
          selectedPartyLedger: null,
          selectedSalesLedger: null,
          selectedVatLedger: null,
          errorMessageVchNo: '',
          selectedPartyMobile: null,
          selectedPartyEmail: null,
          selectedPartyLedgerPriceLevel: null,
          partyLedgerPriceLevelMap: const {},
          isBulkDelivery: null,
        ),
      ) {
    _init();
  }

  void _commit(void Function() fn) {
    fn();
    state = _snapshot();
  }

  DeliveryNoteRegistrationState _snapshot() => DeliveryNoteRegistrationState(
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
    isVoucherTypeLocked: isVoucherTypeLocked,
    isSalesLedgerLocked: isSalesLedgerLocked,
    isGodownLocked: isGodownLocked,
    isLoading: _isLoading,
    isInitialDataLoaded: _isInitialDataLoaded,
    company: company,
    serialNo: serial_no,
    token: token,
    currencyCode: currencycode,
    startfrom: startfrom,
    companyTrn: company_trn,
    companyAddress: company_address,
    companyEmirate: company_emirate,
    companyCountry: company_country,
    vatperc: vatperc,
    decimal: decimal ?? 2,
    securitybtnAccessHolder: SecuritybtnAcessHolder,
    name: name,
    saledate: saledate,
    refdate: refdate,
    saledatestring: saledatestring,
    saledatetxt: saledatetxt,
    refdatestring: refdatestring,
    refdatetxt: refdatetxt,
    yearStartDate: yearStartDate,
    yearEndDate: yearEndDate,
    selectedVchTypeName: _selectedvchtypename,
    selectedPartyLedger: _selectedpartyledger,
    selectedSalesLedger: _selectedsalesledger,
    selectedVatLedger: _selectedvatledger,
    errorMessageVchNo: errorMessageVchNo,
    selectedPartyMobile: _selectedPartyMobile,
    selectedPartyEmail: _selectedPartyEmail,
    selectedPartyLedgerPriceLevel: selectedPartyLedgerPriceLevel,
    partyLedgerPriceLevelMap: Map.unmodifiable(partyLedgerPriceLevelMap),
    isBulkDelivery: _isBulkDelivery,
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

  final TallyApiClient _tallyApiClient = TallyApiClient();
  List<Map<String, dynamic>> _stockItemsRaw = [];
  List<Map<String, dynamic>> _ledgersRaw = [];
  List<Map<String, dynamic>> _groupsRaw = [];
  List<Map<String, dynamic>> _unitsRaw = [];
  List<Map<String, dynamic>> _godownsRaw = [];
  List<Map<String, dynamic>> _voucherTypesRaw = [];
  List<Map<String, dynamic>> _currenciesRaw = [];

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
  bool isVoucherTypeLocked = false;
  bool isSalesLedgerLocked = false;
  bool isGodownLocked = false;

  bool _isLoading = true;
  bool _isInitialDataLoaded = false;

  String? company = '';
  String? serial_no = '';
  String token = '';
  String currencycode = '';
  String startfrom = '';
  String company_trn = 'null';
  String company_address = 'null';
  String company_emirate = 'null';
  String company_country = 'null';
  double vatperc = 0;
  int? decimal = 2;
  String? SecuritybtnAcessHolder = '';
  String name = '';

  late DateTime saledate = DateTime.now();
  late DateTime refdate = DateTime.now();
  String saledatestring = '';
  String saledatetxt = '';
  String refdatestring = '';
  String refdatetxt = '';

  late DateTime now = DateTime.now();
  late DateTime yearStartDate = DateTime(now.year, 1, 1);
  late DateTime yearEndDate = DateTime(now.year, 12, 31);

  final DateFormat _dateFormat = DateFormat('yyyyMMdd');

  dynamic _selectedvchtypename;
  dynamic _selectedpartyledger;
  dynamic _selectedsalesledger;
  dynamic _selectedvatledger;

  String errorMessageVchNo = '';

  String? _selectedPartyMobile;
  String? _selectedPartyEmail;
  String? selectedPartyLedgerPriceLevel;
  Map<String, String?> partyLedgerPriceLevelMap = {};

  bool? _isBulkDelivery;

  bool get isUniGasMeterReadingSerial => isUniGasSerial(serial_no);

  int? _masterIdByName(List<Map<String, dynamic>> rows, String? name) {
    if (name == null || name.trim().isEmpty) return null;
    for (final row in rows) {
      if (row['name']?.toString() == name) return row['masterId'] as int?;
    }
    return null;
  }

  int? _unitMasterIdBySymbol(String? symbol) {
    if (symbol == null || symbol.trim().isEmpty) return null;
    for (final unit in _unitsRaw) {
      if (unit['symbol']?.toString() == symbol) return unit['masterId'] as int?;
    }
    return null;
  }

  int? _stockItemMasterIdByName(String? name) {
    if (name == null || name.trim().isEmpty) return null;
    for (final item in _stockItemsRaw) {
      if (item['name']?.toString() == name) return item['masterId'] as int?;
    }
    return null;
  }

  int? _currencyMasterIdForCode(String code) {
    for (final c in _currenciesRaw) {
      if ((c['isoCurrencyCode']?.toString() ?? '').toUpperCase() ==
          code.toUpperCase()) {
        return c['masterId'] as int?;
      }
    }
    return _currenciesRaw.isNotEmpty
        ? _currenciesRaw.first['masterId'] as int?
        : null;
  }

  /// vatledgerdata[0] is always the synthetic "Not Applicable" entry added
  /// ahead of the API's real VAT ledgers. For UniGas, default to the first
  /// real ledger (vatledgerdata[1]) instead of "Not Applicable".
  String? _defaultVatLedger() {
    if (vatledgerdata.isEmpty) return null;
    if (isUniGasMeterReadingSerial && vatledgerdata.length > 1) {
      return vatledgerdata[1];
    }
    return vatledgerdata[0];
  }

  String _isoDate(String yyyyMMdd) =>
      DateFormat('yyyy-MM-dd').format(parseCompactDate(yyyyMMdd));

  // ---- totals accumulator (highest-risk part, verbatim-ported from the
  // widget's own `_recalculateTotals()`, which itself unified several
  // byte-for-byte-identical duplicate blocks scattered across
  // `_deleteLedger`/`_deleteSaleItem`/`addItem`/`addLedger`/the reset
  // methods/`_recalcTotalsAfterBulkAdd` - same unification already applied
  // in `sales_registration_notifier.dart`) ------------------------------

  void _recalculateTotals() {
    isVisibleItemHeading = saleItems.isNotEmpty;

    totalPriceOfItems = saleItems.fold(0.0, (double previousAmount, SaleItem item) {
      return previousAmount +
          (double.parse(item.itemPrice.toStringAsFixed(decimal!)) *
              double.parse(item.itemQuantity));
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

  /// Verbatim port of `_deleteSaleItem`'s data-mutation half.
  void deleteSaleItem(int index) {
    _commit(() {
      saleItems.removeAt(index);
      _recalculateTotals();
    });
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

  /// Verbatim port of `addLedger()`'s data-mutation half (merge-by-name or
  /// append). Preserves a genuine pre-existing bug verbatim - see this
  /// file's doc-comment: `ledgerdata` rows never carry a `'vatapplicable'`
  /// key, so this throws a runtime `TypeError` the moment it actually runs,
  /// exactly as the pre-migration widget code did.
  void addOrMergeLedger(String ledgerName, double amount) {
    _commit(() {
      final specificLedger = ledgerdata.firstWhere(
        (ledger) => ledger['name'] == ledgerName,
      );

      final int vatApplicable = specificLedger['vatapplicable'];
      final bool vatApp = vatApplicable == 1;

      int existingIndex = ledgerEntries.indexWhere(
        (entry) => entry.ledgerName == ledgerName,
      );

      if (existingIndex != -1) {
        LedgerEntry existingLedger = ledgerEntries[existingIndex];
        double newAmount = existingLedger.ledgerAmount + amount;
        ledgerEntries[existingIndex] = existingLedger.updateAmount(
          newAmount,
          vatApp,
        );
      } else {
        ledgerEntries.add(
          LedgerEntry(ledgerName: ledgerName, ledgerAmount: amount, vatApp: vatApp),
        );
      }
      isVisibleLedgerHeading = ledgerEntries.isNotEmpty;
      _recalculateTotals();
    });
  }

  /// Verbatim port of `_addSelectedItemsInBulk`'s merge-or-append loop
  /// followed by `_recalcTotalsAfterBulkAdd`'s totals recompute (unified
  /// into the same `_recalculateTotals()` every other mutator uses - see
  /// that method's own comment for why this is a safe, non-observable
  /// unification).
  void addBulkItems(List<DnBulkEntry> entries) {
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
              i.itemUnit == entry.unitName,
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
              itemUnit: entry.unitName,
              accountingAllocationList: {},
              batchAllocationList: {
                'GODOWNNAME': entry.location,
                'AMOUNT': amount,
                'ACTUALQTY': '$qty ${entry.unitName}',
                'BILLEDQTY': '$qty ${entry.unitName}',
              },
              meterFrom: entry.meterFrom,
              meterTo: entry.meterTo,
              basicUserDescriptions: entry.descriptions,
              itemMasterId: entry.itemMasterId,
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

  void selectPartyLedger(String suggestion) {
    _commit(() {
      _selectedpartyledger = suggestion;
      selectedPartyLedgerPriceLevel = partyLedgerPriceLevelMap[suggestion];
    });
  }

  void clearSelectedPartyLedger() {
    _commit(() {
      _selectedpartyledger = '';
      selectedPartyLedgerPriceLevel = null;
    });
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

  void setRefDate(DateTime picked) {
    _commit(() {
      refdate = picked;
      refdatestring = _dateFormat.format(picked);
      refdatetxt = formatlastsaledate(refdatestring);
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

  /// Verbatim port of `generateNextVchNo`.
  String generateNextVchNo(List<String> vchnos) {
    if (vchnos.isEmpty) return "1";

    Map<String, List<Map<String, dynamic>>> patternGroups = {};

    for (String vch in vchnos) {
      List<RegExpMatch> matches = RegExp(r'\d+').allMatches(vch).toList();

      if (matches.isNotEmpty) {
        RegExpMatch selectedMatch = matches.last;

        if (matches.length > 1) {
          for (int i = matches.length - 1; i >= 0; i--) {
            String val = matches[i].group(0)!;
            int num = int.tryParse(val) ?? 0;

            if (!(val.length == 4 && num >= 2000 && num <= 2099)) {
              selectedMatch = matches[i];
              break;
            }
          }
        }

        String numberPart = selectedMatch.group(0)!;
        int number = int.tryParse(numberPart) ?? 0;

        String prefix = vch.substring(0, selectedMatch.start);
        String suffix = vch.substring(selectedMatch.end);

        String patternKey = prefix + "#" + suffix;

        patternGroups.putIfAbsent(patternKey, () => []);

        bool exists = patternGroups[patternKey]!.any(
          (e) => e["number"] == number,
        );

        if (!exists) {
          patternGroups[patternKey]!.add({
            "original": vch,
            "number": number,
            "length": numberPart.length,
          });
        }
      }
    }

    if (patternGroups.isEmpty) {
      return vchnos.last + "1";
    }

    String selectedPattern = patternGroups.entries
        .reduce((a, b) => a.value.length > b.value.length ? a : b)
        .key;

    List<Map<String, dynamic>> selectedList = patternGroups[selectedPattern]!;

    List<int> numbers = selectedList.map((e) => e["number"] as int).toList();
    numbers = numbers.toSet().toList();
    numbers.sort();

    int length = selectedList.first["length"];

    int expected = numbers.first;
    int nextNumber = numbers.last + 1;

    for (int num in numbers) {
      if (num != expected) {
        nextNumber = expected;
        break;
      }
      expected++;
    }

    String newNumber = nextNumber.toString().padLeft(length, '0');

    List<String> parts = selectedPattern.split("#");
    String prefix = parts[0];
    String suffix = parts[1];

    return prefix + newNumber + suffix;
  }

  // UniGas-only: resolves once per entry whether this is a bulk (tanker) gas
  // delivery. The widget's `_onAddItemTapped` resolves the actual answer
  // (from the cached "spectra_allocations" `is_bulk` flag - needs
  // `SharedPreferences`, read widget-side) and calls this to commit it.
  void setBulkDelivery(bool value) {
    _commit(() => _isBulkDelivery = value);
  }

  // ---- network / data-loading methods (return result info, no context) --

  /// tally-api migration: replaces legacy's `GET
  /// /api/entry/getSalesData/:company/:serial` the same way
  /// `sales_registration_notifier.dart`'s own `loadData()` replaces its
  /// Sales equivalent - see that file's doc-comment for the shared
  /// `StockRepository`/`LedgerRepository`/raw `/groups`, `/units`,
  /// `/godowns`, `/voucher-types`, `/currencies` calls this is built from.
  /// Ledger classification here additionally recognizes a party group by
  /// name (not just `GroupReservedName`) as a fallback - kept from the
  /// pre-migration widget code verbatim.
  Future<String?> loadData() async {
    vchtypenamedata.clear();
    itemdata.clear();
    salesledger_data.clear();
    partyledgerdata.clear();
    vatledgerdata.clear();
    ledgerdata.clear();
    locationsdata.clear();

    _commit(() => _isLoading = true);

    String? error;
    try {
      final String currentSerialNo = serial_no?.trim() ?? '';
      final bool isVanSalesSerial = vanSalesSerialNo.contains(currentSerialNo);

      final results = await Future.wait([
        StockRepository.instance.listStockItems(),
        fetchAllPages(
          (page) => _tallyApiClient.getForCompany('/ledgers?page=$page&limit=100'),
        ),
        fetchAllPages(
          (page) => _tallyApiClient.getForCompany('/groups?page=$page&limit=100'),
        ),
        fetchAllPages(
          (page) => _tallyApiClient.getForCompany('/units?page=$page&limit=100'),
        ),
        fetchAllPages(
          (page) => _tallyApiClient.getForCompany('/godowns?page=$page&limit=100'),
        ),
        fetchAllPages(
          (page) => _tallyApiClient.getForCompany(
            '/voucher-types?page=$page&limit=100',
          ),
        ),
        fetchAllPages(
          (page) => _tallyApiClient.getForCompany(
            '/currencies?page=$page&limit=100',
          ),
        ),
      ]);

      _stockItemsRaw = results[0];
      _ledgersRaw = results[1];
      _groupsRaw = results[2];
      _unitsRaw = results[3];
      _godownsRaw = results[4];
      _voucherTypesRaw = results[5];
      _currenciesRaw = results[6];

      final Set<int> partyGroupIds = _groupsRaw
          .where(
            (g) =>
                const {'SUNDRY_DEBTORS', 'SUNDRY_CREDITORS'}.contains(
                  g['reservedName']?.toString(),
                ) ||
                const {
                  'sundry debtors',
                  'sundry creditors',
                  'customers',
                  'suppliers',
                  'creditors',
                  'debtors',
                }.contains((g['name']?.toString() ?? '').trim().toLowerCase()),
          )
          .map((g) => g['masterId'] as int)
          .toSet();
      final Set<int> salesGroupIds = _groupsRaw
          .where((g) => g['reservedName']?.toString() == 'SALES')
          .map((g) => g['masterId'] as int)
          .toSet();
      final Set<int> vatGroupIds = _groupsRaw
          .where((g) => g['reservedName']?.toString() == 'DUTIES')
          .map((g) => g['masterId'] as int)
          .toSet();

      String? voucherTypeToFetch;

      _commit(() {
        vchtypenamedata = _voucherTypesRaw
            .where(
              (vt) =>
                  vt['reservedName']?.toString() == 'DELIVERY_NOTE' &&
                  vt['isActive'] != false,
            )
            .map((vt) => vt['name'].toString())
            .toList();

        if (vchtypenamedata.length == 1) {
          _selectedvchtypename = vchtypenamedata[0];
          isVoucherTypeLocked = true;
        } else {
          _selectedvchtypename = vchtypenamedata.isNotEmpty
              ? vchtypenamedata[0]
              : null;
          isVoucherTypeLocked = false;
        }
        voucherTypeToFetch = _selectedvchtypename;

        partyledgerdata.clear();
        partyLedgerPriceLevelMap.clear();

        for (final ledger in _ledgersRaw) {
          if (!partyGroupIds.contains(ledger['groupMasterId'] as int?)) {
            continue;
          }
          final String ledgerName = ledger['name']?.toString().trim() ?? '';
          if (ledgerName.isEmpty) continue;
          if (!partyledgerdata.contains(ledgerName)) {
            partyledgerdata.add(ledgerName);
          }
          if (isVanSalesSerial) {
            final String? rawPriceLevel = ledger['priceLevel']?.toString();
            partyLedgerPriceLevelMap[ledgerName] =
                (rawPriceLevel == null || rawPriceLevel.trim().isEmpty)
                ? null
                : rawPriceLevel.trim();
          }
        }
        partyledgerdata.sort(
          (a, b) => a.toLowerCase().compareTo(b.toLowerCase()),
        );

        salesledger_data = _ledgersRaw
            .where((l) => salesGroupIds.contains(l['groupMasterId'] as int?))
            .map((l) => l['name'].toString())
            .toList();

        final List<String> distinctSalesLedgerNames = salesledger_data
            .toSet()
            .toList();
        if (distinctSalesLedgerNames.length == 1) {
          _selectedsalesledger = distinctSalesLedgerNames.first;
        } else {
          _selectedsalesledger = salesledger_data.isNotEmpty
              ? salesledger_data[0]
              : null;
        }
        isSalesLedgerLocked = false;

        ledgerdata = _ledgersRaw
            .where(
              (l) =>
                  !partyGroupIds.contains(l['groupMasterId'] as int?) &&
                  !salesGroupIds.contains(l['groupMasterId'] as int?) &&
                  !vatGroupIds.contains(l['groupMasterId'] as int?),
            )
            .map((l) => {'name': l['name'].toString()})
            .toList();

        vatledgerdata.add('Not Applicable');
        vatledgerdata.addAll(
          _ledgersRaw
              .where((l) => vatGroupIds.contains(l['groupMasterId'] as int?))
              .map((l) => l['name'].toString()),
        );

        _selectedvatledger = _defaultVatLedger();

        itemdata = _stockItemsRaw.map((item) {
          final List<Map<String, dynamic>> units = [];
          if (item['baseUnitSymbol'] != null) {
            units.add({'name': item['baseUnitSymbol'], 'multiplier': '1'});
          }
          if (item['additionalUnitSymbol'] != null) {
            units.add({
              'name': item['additionalUnitSymbol'],
              'multiplier': item['conversion']?.toString() ?? '0',
            });
          }
          return {
            'name': item['name'],
            'masterid': item['masterId']?.toString(),
            'part': (item['partNo'] as List?)?.isNotEmpty == true
                ? (item['partNo'] as List).first.toString()
                : '',
            'saleprice': item['lastSalePrice'],
            'standardprice': item['stardardPrice'],
            'unit': units,
          };
        }).toList();

        locationsdata = _godownsRaw.map((g) => g['name'].toString()).toList();

        if (locationsdata.length == 1) {
          isGodownLocked = true;
        } else {
          isGodownLocked = false;
        }
      });

      if (voucherTypeToFetch != null && voucherTypeToFetch!.isNotEmpty) {
        await fetchVchNos(voucherTypeToFetch!);
      }
    } on ApiException catch (e) {
      error = e.message;
    } catch (e) {
      error = 'Something went wrong!!!';
    }

    _commit(() => _isLoading = false);
    return error;
  }

  /// tally-api migration: `loadData()` already fetched the full ledger list
  /// into `_ledgersRaw` - this is a pure client-side lookup by name, no
  /// network round-trip needed. Returns `null` on "ledger not found" (the
  /// widget shows that itself); otherwise the widget calls
  /// `showDeliveryNoteDialog(context, ...)` with the result.
  Future<DnLedgerLookupResult?> loadLedgerData() async {
    _commit(() => _isLoading = true);
    DnLedgerLookupResult? result;
    try {
      final ledger = _ledgersRaw.firstWhere(
        (l) => l['name']?.toString() == _selectedpartyledger,
        orElse: () => const {},
      );

      if (ledger.isNotEmpty) {
        final String tinValue = ledger['tinNumber']?.toString() ?? 'null';
        final String address =
            (ledger['address'] as List?)?.join(', ') ?? 'null';
        final String emirate = ledger['stateName']?.toString() ?? 'null';
        final String country = ledger['countryName']?.toString() ?? 'null';

        _commit(() {
          _selectedPartyMobile = ledger['mobileNumber']?.toString();
          _selectedPartyEmail = ledger['email']?.toString();
        });

        result = DnLedgerLookupResult(
          tin: tinValue,
          address: address,
          emirate: emirate,
          country: country,
        );
      }
    } catch (e) {
      // matches original: swallowed, logged only
    }

    _commit(() => _isLoading = false);
    return result;
  }

  /// Backed by tally-api's `GET .../voucher-entries/voucher-numbers` - see
  /// `sales_order_registration_notifier.dart`'s identically-shaped
  /// `fetchVchNos`. `startfrom`/`yearEndDate` bound the search window,
  /// matching the pre-migration `fetchvchnos(vchname)`.
  Future<DnVchNosResult> fetchVchNos(String vchname) async {
    final DateTime rangeStart = parseCompactDate(startfrom);
    final DateTime rangeEnd = yearEndDate;

    vchnos.clear();
    _commit(() => _isLoading = true);

    String? error;
    try {
      final int? voucherTypeMasterId = _masterIdByName(
        _voucherTypesRaw,
        vchname,
      );

      if (voucherTypeMasterId != null) {
        final String fromParam = DateFormat('yyyy-MM-dd').format(rangeStart);
        final String toParam = DateFormat('yyyy-MM-dd').format(rangeEnd);

        vchnos = await VoucherEntryRepository.instance.voucherNumbers(
          voucherTypeMasterId: voucherTypeMasterId,
          from: fromParam,
          to: toParam,
        );
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
      error = e.message;
    } catch (e) {
      vchnos.clear();
    }

    final String nextVch = generateNextVchNo(vchnos);
    _commit(() => _isLoading = false);
    return DnVchNosResult(error: error, nextVchNo: nextVch);
  }

  /// Verbatim port of `saveEntry()`'s payload-building/submit logic, minus
  /// the pre-save validation (party ledger/UniGas receiver/meter-reading/EID
  /// checks, which read `context` via `showAppMessage` - the widget performs
  /// those itself before calling this) and minus the trailing
  /// `loadLedgerData()` call (the widget does that itself on success, since
  /// it also needs to show the delivery-note dialog). [referenceDate] is
  /// already resolved by the widget (yyyyMMdd) - see this file's
  /// doc-comment for why. The dead `jsonEntryData` construction from the
  /// pre-migration code is dropped entirely (see doc-comment).
  Future<DnSaveResult> saveEntry({
    required String narration,
    required String vchno,
    required String refno,
    required String referenceDate,
  }) async {
    _commit(() => _isLoading = true);

    roundedtotalAmount = double.parse(totalAmount.toStringAsFixed(decimal!));

    double totalItemAmount = 0.0;
    for (SaleItem item in saleItems) {
      totalItemAmount += double.parse(item.itemAmount.toStringAsFixed(decimal!));
    }

    for (var saleItem in saleItems) {
      if (saleItem.accountingAllocationList.isEmpty) {
        saleItem.accountingAllocationList = {
          "LEDGERNAME": _selectedsalesledger,
          "AMOUNT": saleItem.itemAmount.toStringAsFixed(decimal!),
          "ISDEEMEDPOSITIVE": "No",
        };
      }
    }

    double totalLedgerAmount = 0.0;
    for (LedgerEntry ledger in ledgerEntries) {
      totalLedgerAmount += double.parse(ledger.ledgerAmount.toStringAsFixed(decimal!));
    }

    double partyLedgerAmount = double.parse(
      (double.parse(totalVatAmount.toStringAsFixed(decimal!)) +
              double.parse(totalItemAmount.toStringAsFixed(decimal!)) +
              double.parse(totalLedgerAmount.toStringAsFixed(decimal!)))
          .toStringAsFixed(decimal!),
    );
    partyLedgerAmount = partyLedgerAmount * -1;

    try {
      final int? voucherTypeMasterId = _masterIdByName(
        _voucherTypesRaw,
        _selectedvchtypename,
      );
      final int? partyLedgerMasterId = _masterIdByName(
        _ledgersRaw,
        _selectedpartyledger?.toString(),
      );
      final int? currencyMasterId = _currencyMasterIdForCode(currencycode);

      if (voucherTypeMasterId == null) {
        _commit(() => _isLoading = false);
        return const DnSaveResult(
          success: false,
          errorMessage: 'Unknown voucher type - please reselect it',
        );
      }
      if (partyLedgerMasterId == null) {
        _commit(() => _isLoading = false);
        return const DnSaveResult(
          success: false,
          errorMessage: 'Unknown party ledger - please reselect it',
        );
      }
      if (currencyMasterId == null) {
        _commit(() => _isLoading = false);
        return const DnSaveResult(
          success: false,
          errorMessage: 'No currency configured for this company',
        );
      }

      final List<Map<String, dynamic>> ledgerEntriesBody = [];

      ledgerEntriesBody.add({
        'ledgerMasterId': partyLedgerMasterId,
        'amount': partyLedgerAmount.abs(),
        'isDebit': partyLedgerAmount < 0,
        'isPartyLedger': true,
      });

      for (final entry in ledgerEntries) {
        final int? ledgerMasterId = _masterIdByName(
          _ledgersRaw,
          entry.ledgerName,
        );
        if (ledgerMasterId == null) continue;
        ledgerEntriesBody.add({
          'ledgerMasterId': ledgerMasterId,
          'amount': entry.ledgerAmount.abs(),
          'isDebit': false,
          'isPartyLedger': false,
        });
      }

      if (_selectedvatledger != 'Not Applicable') {
        final int? vatLedgerMasterId = _masterIdByName(
          _ledgersRaw,
          _selectedvatledger?.toString(),
        );
        if (vatLedgerMasterId != null) {
          ledgerEntriesBody.add({
            'ledgerMasterId': vatLedgerMasterId,
            'amount': roundedtotalVatAmount.abs(),
            'isDebit': false,
            'isPartyLedger': false,
          });
        }
      }

      final List<Map<String, dynamic>> inventoryEntriesBody = [];
      for (final item in saleItems) {
        final int? stockItemMasterId =
            item.itemMasterId ?? _stockItemMasterIdByName(item.itemName);
        if (stockItemMasterId == null) {
          throw ApiException(
            statusCode: 0,
            code: 'UNKNOWN_ITEM',
            message: 'Unknown stock item: ${item.itemName}',
          );
        }

        int? unitMasterId = _unitMasterIdBySymbol(item.itemUnit);
        if (unitMasterId == null) {
          final stockRow = _stockItemsRaw.firstWhere(
            (i) => i['masterId'] == stockItemMasterId,
            orElse: () => const {},
          );
          unitMasterId = stockRow['baseUnitMasterId'] as int?;
        }
        if (unitMasterId == null) {
          throw ApiException(
            statusCode: 0,
            code: 'UNKNOWN_UNIT',
            message: 'Unknown unit for item: ${item.itemName}',
          );
        }

        final String? salesLedgerName =
            item.accountingAllocationList['LEDGERNAME']?.toString();
        final int? inventoryLedgerMasterId = _masterIdByName(
          _ledgersRaw,
          salesLedgerName,
        );
        if (inventoryLedgerMasterId == null) {
          throw ApiException(
            statusCode: 0,
            code: 'UNKNOWN_SALES_LEDGER',
            message: 'Unknown sales ledger: ${salesLedgerName ?? ''}',
          );
        }

        final List<Map<String, dynamic>> batchAllocations = [];
        final int? godownMasterId = _masterIdByName(
          _godownsRaw,
          item.itemLocation,
        );
        if (godownMasterId != null) {
          batchAllocations.add({
            'godownMasterId': godownMasterId,
            'batchName': 'Primary Batch',
            'quantity': double.tryParse(item.itemQuantity) ?? 0,
          });
        }

        inventoryEntriesBody.add({
          'stockItemMasterId': stockItemMasterId,
          'quantity': double.tryParse(item.itemQuantity) ?? 0,
          'rate': item.itemPrice,
          'unitMasterId': unitMasterId,
          'amount': item.itemAmount,
          'ledgerMasterId': inventoryLedgerMasterId,
          'isDebitQuantity': false,
          'batchAllocations': batchAllocations,
          if (item.basicUserDescriptions.isNotEmpty)
            'description': item.basicUserDescriptions,
        });
      }

      final Map<String, dynamic> body = {
        'voucherTypeMasterId': voucherTypeMasterId,
        'date': _isoDate(saledatestring),
        'currencyMasterId': currencyMasterId,
        if (narration.isNotEmpty) 'narration': narration,
        if (vchno.trim().isNotEmpty) 'voucherNumber': vchno.trim(),
        if (refno.trim().isNotEmpty) 'reference': refno.trim(),
        if (referenceDate.trim().isNotEmpty)
          'referenceDate': _isoDate(referenceDate),
        'ledgerEntries': ledgerEntriesBody,
        'inventoryEntries': inventoryEntriesBody,
      };

      await VoucherEntryRepository.instance.create(body);
    } on ApiException catch (e) {
      _commit(() => _isLoading = false);
      return DnSaveResult(success: false, errorMessage: e.message);
    } catch (e) {
      _commit(() => _isLoading = false);
      return const DnSaveResult(success: false);
    }

    _commit(() => _isLoading = false);
    return const DnSaveResult(success: true);
  }

  /// Verbatim port of the shared post-share/print reset block (the same
  /// data-mutation both `_resetDeliveryNoteFormAfterShare` and
  /// `showDeliveryNoteDialog`'s "No, Thanks" button apply) - the widget
  /// separately resets its own controllers/dialog-composition fields
  /// (`_selectedledger`/`_selecteditem`/`selectedLocation`/etc., plus focus
  /// handling that differs slightly between the two call sites - see this
  /// file's doc-comment) alongside this call, and re-fetches voucher numbers
  /// for the still-selected voucher type itself.
  void resetAfterShare() {
    _commit(() {
      saledate = DateTime.now();
      saledatestring = _dateFormat.format(saledate);
      saledatetxt = formatlastsaledate(saledatestring);

      refdate = DateTime.now();
      refdatestring = _dateFormat.format(refdate);
      refdatetxt = formatlastsaledate(refdatestring);

      _selectedpartyledger = null;
      _isBulkDelivery = null;

      // Don't reassign _selectedsalesledger on UniGas - it's locked to the
      // allocation-assigned sales ledger and shouldn't fall back to the
      // first option on reset.
      if (!isUniGasSerial(serial_no)) {
        _selectedsalesledger = salesledger_data.isNotEmpty
            ? salesledger_data[0]
            : null;
      }

      _selectedvatledger = _defaultVatLedger();

      saleItems.clear();
      ledgerEntries.clear();
      _recalculateTotals();

      isVisibleItemHeading = saleItems.isNotEmpty;
      isVisibleLedgerHeading = ledgerEntries.isNotEmpty;
    });
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();

    company = prefs.getString('company_name');
    serial_no = prefs.getString('serial_no');
    token = prefs.getString('token') ?? '';
    currencycode = prefs.getString('currencycode') ?? 'AED';
    startfrom =
        prefs.getString('startfrom') ??
        DateFormat('yyyyMMdd').format(yearStartDate);

    company_trn = prefs.getString("company_trn") ?? "null";
    company_address = prefs.getString("company_address") ?? "null";
    company_emirate = prefs.getString("company_emirate") ?? "null";
    company_country = prefs.getString("company_country") ?? "null";

    vatperc = prefs.getDouble('vatperc') ?? 5.0;
    decimal = prefs.getInt('decimalplace') ?? 2;

    saledate = DateTime.now();
    saledatestring = _dateFormat.format(saledate);
    saledatetxt = formatlastsaledate(saledatestring);

    refdate = DateTime.now();
    refdatestring = _dateFormat.format(refdate);
    refdatetxt = formatlastsaledate(refdatestring);

    SecuritybtnAcessHolder = prefs.getString('secbtnaccess');

    String? name_nav = prefs.getString('name_nav');
    String? email_nav = prefs.getString('email_nav');
    if (email_nav != null && name_nav != null) {
      name = name_nav;
    }

    _commit(() {});

    await loadData();
    _commit(() => _isInitialDataLoaded = true);
  }
}

final deliveryNoteRegistrationNotifierProvider = StateNotifierProvider.autoDispose<
    DeliveryNoteRegistrationNotifier, DeliveryNoteRegistrationState>(
  (ref) => DeliveryNoteRegistrationNotifier(ref),
);
