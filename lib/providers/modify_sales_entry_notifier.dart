import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../Items.dart' show formatlastsaledate;
import '../ModifySalesEntry.dart';
import '../api/api_exception.dart';
import '../api/currency_repository.dart';
import '../api/godown_repository.dart';
import '../api/monthly_bucket_helper.dart' show parseMoneyField, parseCompactDate;
import '../api/stock_repository.dart';
import '../api/voucher_entry_dropdowns_repository.dart';
import '../api/voucher_entry_repository.dart';
import '../api/voucher_type_repository.dart';

/// Identifies one [ModifySalesEntry] screen instance for the `.family`
/// provider below - this screen (unlike the create-flow siblings) is
/// parameterized per existing voucher entry, so a single global provider
/// can't work. Equality/hashCode are based on [id] alone (the tally-api
/// `VoucherEntry.id` this screen edits) - sufficient to distinguish any two
/// real instances of this screen, mirroring
/// `party_clicked_sale_purc_order_clicked_notifier.dart`'s
/// `PartyClickedSalePurcOrderClickedArgs` precedent for a family-provider
/// Args object in this app.
class ModifySalesEntryArgs {
  final String id;
  final int isSynced;
  final String type;
  final Map<String, dynamic> data;

  const ModifySalesEntryArgs({
    required this.id,
    required this.isSynced,
    required this.type,
    required this.data,
  });

  @override
  bool operator ==(Object other) =>
      other is ModifySalesEntryArgs && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Riverpod migration of `ModifySalesEntry.dart`'s
/// `_ModifySalesEntryPageState`. Closest sibling by far is
/// `sales_registration_notifier.dart` (this screen shares its `SaleItem`/
/// `Unit`/`LedgerEntry` model shapes and item+ledger accumulator logic
/// nearly verbatim) - read that file's doc-comment first. This is a
/// *Modify* screen though (edits an existing app-originated `VoucherEntry`
/// rather than creating one), so it deviates structurally in several
/// places documented below.
///
/// Structural deviations from `sales_registration_notifier.dart`:
/// - No price-level lookups, no UniGas "Receiver Information"/basic-user-
///   description/meter-reading fields at all - this screen never grew
///   those features (confirmed via a whole-file grep before assuming
///   otherwise - `priceLevel`/`creditPeriod`/`receiverName`/
///   `basicUserDescriptions`/`meterFrom`/`meterTo` have zero matches in the
///   pre-migration source). `isUniGasSerial(serialNo)` here only gates the
///   sale-date field (locked, can't be changed) and a couple of read-only
///   UI badges - much simpler than the sibling's UniGas handling.
/// - `loadData()` fetches full master lists directly (`StockRepository`,
///   `LedgerRepository.listLedgers()`/`listAllLedgers()`, `GroupRepository`,
///   `VoucherTypeRepository`, `GodownRepository`, `CurrencyRepository`) and
///   classifies ledgers/voucher-types by `reservedName` client-side, rather
///   than the sibling's single `VoucherEntryDropdownsRepository.salesData()`
///   bundle call - a pre-existing difference in this screen's own
///   pre-migration code, not something introduced by this migration.
/// - `loadData()` additionally prefills every field of the *existing*
///   voucher entry being edited from `data` (a `VoucherEntryRepository`
///   row) - the party ledger, sales ledger, VAT ledger/amount, manual
///   "other" ledger entries, and every sale item, all derived from
///   `data['ledgerEntries']`/`data['inventoryEntries']` per the doc-comment
///   on `loadData()` itself below. There is no equivalent step in any
///   create-flow sibling.
/// - `updateEntry(id, ...)` (`VoucherEntryRepository.update`) replaces
///   `saveEntry()`/`create()` - this screen always rebuilds
///   `ledgerEntries`/`inventoryEntries` wholesale from the current form
///   state on every update (matching the server's delete-then-reinsert
///   semantics), the same way `voucher_entries.service.ts`'s own `update`
///   handles a `PATCH` that includes those arrays.
/// - `fetchVchNos` excludes this entry's own original voucher number (one
///   occurrence) from the returned pool, via [_originalVoucherNumber] set
///   by `loadData()` - so re-saving this entry with its number unchanged
///   never flags itself as a duplicate. This entry's own voucher-number
///   *text* is never regenerated/auto-filled the way create-flow siblings
///   do (`isVchEditable` - a widget-local, always-false, half-wired toggle
///   whose "edit" button `onPressed` is a no-op in the pre-migration code -
///   kept exactly that way, not fixed) - `loadData()` seeds it once from
///   `data['voucherNumber']` and it's otherwise left alone.
/// - `addOrMergeLedger` originally preserved a genuine pre-existing bug
///   verbatim (matching the identical situation already documented in
///   `delivery_note_registration_notifier.dart`): this screen's own
///   `ledgerdata` rows were built by `loadData()` as bare `{'name': ...}`
///   maps with no `vatApplicable` key, and the lowercase
///   `'vatapplicable'` lookup was always `null` regardless - throwing a
///   runtime `TypeError` the moment a manual ledger was added via
///   `addLedger()`. Fixed: `loadData()` now carries `vatApplicable`
///   through into `ledgerdata`, and `addOrMergeLedger` reads the real
///   camelCase bool.
/// - `generateInvoicePDF`/`formatAmountInvoice`/`convertAmountToWords`/etc.
///   stay entirely widget-local (pure PDF/text-formatting UI with no
///   `setState` of their own) - `formatAmountInvoice` read `decimal` via a
///   fresh `prefs.getInt('decimalplace')` call in the pre-migration code
///   instead of the `decimal` field it sits right next to; since that
///   field is set from the very same pref once at startup and never
///   changes for the life of the screen, the widget now reads `_s.decimal`
///   there instead of re-fetching - a behaviorally-identical simplification
///   made necessary by `SharedPreferences` no longer being directly
///   reachable from the widget, not a fix to any observed bug.
///
/// Dialog-composition-only fields that stay widget-local (unmigrated, same
/// treatment as `TextEditingController`s, per this migration's established
/// convention): `_selectedledger`, `_selecteditem`, `_selectedunit`,
/// `selectedLocation`, `isVisibleUnit`, `isVisibleLocation`,
/// `selectedMultiplier`, `unitdata`, `isVchEditable` (always false - see
/// above).
///
/// Dead fields/methods dropped rather than ported (confirmed unreferenced
/// outside their own declaration/assignment via a whole-file grep):
/// `isDashEnable`, `isRolesVisible`, `isUserVisible`, `isUserEnable`,
/// `isRolesEnable`, `isVisibleNoUserFound`, `hostname`, `company_lowercase`,
/// `username`, `HttpURL`, `token`, `name`, `email` (all write-only -
/// `name`/`email` are fed from nav args but never read anywhere in this
/// screen, unlike some siblings where one of the pair turned out live -
/// verified here via a targeted grep before dropping),
/// `SecuritybtnAcessHolder` (its only reader fed the now-dead
/// `isRolesVisible`/`isUserVisible` pair, so the whole chain is dead),
/// `jsonEntryData` (only ever built by the fully dead legacy `saveEntry()`
/// - see below), `isValidEmail` (declared, zero call sites),
/// `extractQuantity` (declared, zero call sites), `updateRateAndAmount`/
/// `updateAmount` (both called only from the dead `_showItemDetailsPopup`
/// flow below), `controller_vchno` (declared, never used -
/// `_vchnoController` is the real one), `_scaffoldMessengerKey` (declared
/// and assigned, never read), every `_isFocused_*` field (nine of them -
/// all write-only, never read to affect any UI), `_itemFormkey` (used only
/// inside the dead single-item popup below), `_confirmLedgerDeletion`/
/// `_confirmItemDeletion` (both declared, zero call sites - the actual
/// delete buttons in `build()` call `_deleteLedger`/`_deleteSaleItem`
/// directly with no confirmation dialog).
///
/// The single-item add flow (`_showItemDetailsPopup`/`addItem()`, plus an
/// even-older block-commented copy of the popup and a commented-out legacy
/// Tally-XML-shaped `saveEntry()`) was confirmed to have **zero** live call
/// sites - fully superseded by the bulk multi-item picker
/// (`_showMultiItemSelectPopup`/`_addSelectedItemsInBulk`), the exact same
/// situation already documented in `sales_order_registration_notifier.dart`
/// and `delivery_note_registration_notifier.dart` - and was deleted outright
/// from the widget rather than migrated.
class ModifySalesEntryState {
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
  final String currencyCode;
  final String companyTrn;
  final String companyAddress;
  final String companyEmirate;
  final String companyCountry;
  final double vatperc;
  final int decimal;

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

  /// One-shot values `loadData()` resolves for this existing entry - the
  /// widget seeds its own widget-local controllers/dialog-composition
  /// fields from these exactly once, the first time [isInitialDataLoaded]
  /// flips `true` (same "seed once, guarded by a bool, read in `build()`"
  /// pattern `ModifyRole.dart`/`ModifyUser.dart` already use for their own
  /// one-time controller seeding), rather than clobbering in-progress
  /// edits on every rebuild.
  final String initialVoucherNumber;
  final String initialNarration;
  final String initialReference;
  final String? initialItemName;
  final String? initialLocationName;

  const ModifySalesEntryState({
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
    required this.currencyCode,
    required this.companyTrn,
    required this.companyAddress,
    required this.companyEmirate,
    required this.companyCountry,
    required this.vatperc,
    required this.decimal,
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
    required this.initialVoucherNumber,
    required this.initialNarration,
    required this.initialReference,
    required this.initialItemName,
    required this.initialLocationName,
  });
}

/// Result of [ModifySalesEntryNotifier.loadLedgerData] - the widget uses
/// this to call `showSalesInvoiceDialogUpdated(context, ...)` itself (pure
/// UI, needs `context`), mirroring `sales_registration_notifier.dart`'s
/// identically-shaped `LedgerLookupResult`.
class ModifyLedgerLookupResult {
  final String tin;
  final String address;
  final String emirate;
  final String country;
  ModifyLedgerLookupResult({
    required this.tin,
    required this.address,
    required this.emirate,
    required this.country,
  });
}

/// One resolved row for [ModifySalesEntryNotifier.addSelectedItemsInBulk] -
/// the widget resolves each selected item's editable rate/qty/unit
/// `TextEditingController`s (plus the currently-selected godown) into plain
/// values before calling, mirroring
/// `sales_registration_notifier.dart`'s `BulkAddEntry` (this screen has no
/// `basicUserDescriptions`/meter-reading fields to carry along - see this
/// file's doc-comment).
class ModifyBulkAddEntry {
  final String name;
  final int quantity;
  final double rate;
  final String unit;
  final String location;
  ModifyBulkAddEntry({
    required this.name,
    required this.quantity,
    required this.rate,
    required this.unit,
    required this.location,
  });
}

class ModifySalesEntryNotifier extends StateNotifier<ModifySalesEntryState> {
  final Ref _ref;
  final ModifySalesEntryArgs _args;

  ModifySalesEntryNotifier(this._ref, this._args)
    : super(
        ModifySalesEntryState(
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
          currencyCode: '',
          companyTrn: 'null',
          companyAddress: 'null',
          companyEmirate: 'null',
          companyCountry: 'null',
          vatperc: 0,
          decimal: 2,
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
          initialVoucherNumber: '',
          initialNarration: '',
          initialReference: '',
          initialItemName: null,
          initialLocationName: null,
        ),
      ) {
    _init();
  }

  void _commit(void Function() fn) {
    fn();
    state = _snapshot();
  }

  ModifySalesEntryState _snapshot() => ModifySalesEntryState(
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
    currencyCode: currencycode,
    companyTrn: company_trn,
    companyAddress: company_address,
    companyEmirate: company_emirate,
    companyCountry: company_country,
    vatperc: vatperc,
    decimal: decimal ?? 2,
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
    initialVoucherNumber: _initialVoucherNumber,
    initialNarration: _initialNarration,
    initialReference: _initialReference,
    initialItemName: _initialItemName,
    initialLocationName: _initialLocationName,
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

  final Map<String, int> _ledgerMasterIdByName = {};
  final Map<String, int> _voucherTypeMasterIdByName = {};
  final Map<String, int> _godownMasterIdByName = {};
  List<Map<String, dynamic>> _allLedgersCache = [];
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
  String currencycode = '';
  String company_trn = 'null';
  String company_address = 'null';
  String company_emirate = 'null';
  String company_country = 'null';
  double vatperc = 0;
  int? decimal = 2;

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

  /// This entry's own voucher number as loaded by `loadData()` - excluded
  /// from [vchnos] in `fetchVchNos()` so re-saving with the number
  /// unchanged never flags itself as a duplicate.
  String? _originalVoucherNumber;

  // One-shot values `loadData()` resolves for the widget to seed its own
  // controllers/dialog-composition fields from - see [ModifySalesEntryState]'s
  // doc-comment.
  String _initialVoucherNumber = '';
  String _initialNarration = '';
  String _initialReference = '';
  String? _initialItemName;
  String? _initialLocationName;

  /// `YYYY-MM-DD`, the `z.iso.date()` shape every voucherEntrySchema date
  /// field expects.
  String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// Resolves [unitName] back to its tally-api unitMasterId, by matching
  /// against the item's own `unit` list (as shaped by
  /// `_shapeStockItemForLegacyItemdata`).
  int? _findUnitMasterId(List<dynamic> unitJson, String unitName) {
    for (final u in unitJson) {
      if (u is Map && u['name'] == unitName) {
        return u['masterId'] as int?;
      }
    }
    return null;
  }

  /// Reshapes one tally-api stock-items row into the legacy key names this
  /// screen's item picker/bulk-add code already reads (`name`/`masterid`/
  /// `saleprice`/`standardprice`/`unit`/`part`) - mirrors
  /// SalesRegistration.dart's identically-named method exactly.
  Map<String, dynamic> _shapeStockItemForLegacyItemdata(
    Map<String, dynamic> item,
  ) {
    final int? baseUnitMasterId = item['baseUnitMasterId'] as int?;
    final String? baseUnitSymbol = (item['baseUnitSymbol'] as String?)
        ?.trim();
    final int? additionalUnitMasterId = item['additionalUnitMasterId'] as int?;
    final String? additionalUnitSymbol =
        (item['additionalUnitSymbol'] as String?)?.trim();
    final double denominator = parseMoneyField(item['denominator']);

    final units = <Map<String, dynamic>>[];
    if (baseUnitMasterId != null &&
        baseUnitSymbol != null &&
        baseUnitSymbol.isNotEmpty) {
      units.add({
        'name': baseUnitSymbol,
        'multiplier': '1',
        'masterId': baseUnitMasterId,
      });
    }
    if (additionalUnitMasterId != null &&
        additionalUnitSymbol != null &&
        additionalUnitSymbol.isNotEmpty) {
      units.add({
        'name': additionalUnitSymbol,
        'multiplier': (denominator == 0 ? 1 : denominator).toString(),
        'masterId': additionalUnitMasterId,
      });
    }
    if (units.isEmpty) {
      units.add({'name': '', 'multiplier': '1', 'masterId': null});
    }

    return {
      'name': item['name'],
      'masterid': item['masterId'],
      'saleprice': item['lastSalePrice']?.toString() ?? 'null',
      'standardprice': item['stardardPrice']?.toString() ?? 'null',
      'unit': units,
      'part': (item['partNo'] as List?)?.cast<String>().join(', ') ?? '',
    };
  }

  // ---- totals accumulator (highest-risk part, verbatim-ported) ----------

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
            return prev +
                double.parse(entry.ledgerAmount.toStringAsFixed(decimal!));
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
  /// append). The widget's own `addLedger()` wrapper validates
  /// `ledgerName`/`ledgerAmount` are non-empty and pops the dialog before
  /// calling this, matching the original's
  /// `if (ledgerName.isNotEmpty && ledgerAmount.isNotEmpty)` guard order.
  void addOrMergeLedger(String ledgerName, double amount) {
    _commit(() {
      final specificLedger = ledgerdata.firstWhere(
        (ledger) => ledger['name'] == ledgerName,
      );

      // tally-api's `/ledgers` returns this as a camelCase boolean
      // (`vatApplicable`), not legacy's lowercase 1/0 `vatapplicable` -
      // fixed to actually read the real field (`loadData()` now carries
      // it through into `ledgerdata` too; this used to crash with a
      // TypeError the moment a manual ledger was added).
      final bool vatApp = specificLedger['vatApplicable'] == true;

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
  /// followed by `_recalcTotalsAfterBulkAdd`'s totals recompute - unified
  /// into the same `_recalculateTotals()` every other mutator uses here
  /// (same safe, non-observable unification already applied in every other
  /// screen's notifier - see `sales_registration_notifier.dart`'s
  /// `_recalculateTotals()` comment for why).
  void addSelectedItemsInBulk(List<ModifyBulkAddEntry> entries) {
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
    _commit(() => _selectedpartyledger = suggestion);
  }

  void clearSelectedPartyLedger() {
    _commit(() => _selectedpartyledger = "");
  }

  /// Verbatim port of the VAT-ledger dropdown `onChanged` body (which
  /// duplicates `_recalculateTotals()`'s logic inline in the original -
  /// unified here, no observable difference, matching every other screen's
  /// notifier).
  void setSelectedVatLedgerAndRecalculate(String value) {
    _commit(() {
      _selectedvatledger = value;
      _recalculateTotals();
    });
  }

  /// Verbatim port of `_selectsaleDate`'s data-mutation half - the
  /// UniGas-locked early return (no date picker shown at all) and the
  /// dead `_isFocused_refno`/`_isFocused_narration` resets stay/are dropped
  /// on the widget side (see this file's doc-comment).
  void setSaleDate(DateTime picked) {
    _commit(() {
      saledate = picked;
      saledatestring = _dateFormat.format(saledate);
      saledatetxt = formatlastsaledate(saledatestring);
    });
  }

  /// Verbatim port of `_selectrefDate`'s data-mutation half.
  void setRefDate(DateTime picked) {
    _commit(() {
      refdate = picked;
      refdatestring = _dateFormat.format(refdate);
      refdatetxt = formatlastsaledate(refdatestring);
    });
  }

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

  /// Replaces legacy's `GET /api/entry/getSalesData/:company/:serial` (same
  /// master-data bundle SalesRegistration.dart's `loadData()` fetches,
  /// though sourced here via direct repository calls - see this file's
  /// doc-comment) plus the existing-entry prefill legacy's `data`
  /// (Tally-XML-shaped) carried inline. [ModifySalesEntryArgs.data] (from
  /// `VoucherEntryRepository.getById`/`listAll`) is this method's *only*
  /// source for the entry being edited - every "old..." value below is read
  /// straight off it:
  ///
  ///  * `data['voucherTypeName']`/`voucherNumber`/`narration`/`reference`/
  ///    `date`/`referenceDate` replace legacy's uppercase
  ///    `VOUCHERTYPENAME`/`VOUCHERNUMBER`/`NARRATION`/`REFERENCE`/`DATE`/
  ///    `REFERENCEDATE`.
  ///  * The party ledger (legacy's top-level `PARTYLEDGERNAME`) is now
  ///    derived from whichever `data['ledgerEntries']` row has
  ///    `isPartyLedger == true`.
  ///  * The per-item sales ledger (legacy's first item's
  ///    `ACCOUNTINGALLOCATIONS.LIST.LEDGERNAME`) is now
  ///    `data['inventoryEntries'].first['ledgerName']`.
  ///  * The VAT ledger/amount (legacy's `LEDGERENTRIES.LIST` row with
  ///    `ledgerType == 'VAT'`) is now whichever `ledgerEntries` row's
  ///    `ledgerName` falls under the `'DUTIES'` reserved group - same
  ///    classification `vatledgerdata` itself uses below.
  ///  * Legacy's top-level `totalAmount` has no equivalent field on the new
  ///    schema - it's recomputed here from the loaded items/ledgers/VAT.
  ///
  /// **Known gap**: legacy's per-manual-ledger `VATAPPLICABLE` flag has no
  /// equivalent on `entryLedgerEntryRowSchema` - every manual ledger entry
  /// loaded below gets `vatApp: false` (not a data-loss from *this* change -
  /// it was already lost the first time this voucher was written under the
  /// new schema).
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
    _voucherTypeMasterIdByName.clear();
    _godownMasterIdByName.clear();
    _allLedgersCache = [];
    _currencyMasterId = null;

    _commit(() => _isLoading = true);

    final data = _args.data;
    String? error;

    try {
      final results = await Future.wait([
        StockRepository.instance.listStockItems(),
        VoucherEntryDropdownsRepository.instance.salesData(type: 'sales'),
        VoucherTypeRepository.instance.listAll(),
        GodownRepository.instance.listAll(),
        CurrencyRepository.instance.listAll(),
      ]);

      final stockItems = results[0] as List<Map<String, dynamic>>;
      final salesData = results[1] as Map<String, dynamic>;
      final voucherTypes = results[2] as List<Map<String, dynamic>>;
      final godowns = results[3] as List<Map<String, dynamic>>;
      final currencies = results[4] as List<Map<String, dynamic>>;

      // Same server-side classification `SalesRegistration.dart` uses (via
      // `VoucherEntryDropdownsRepository.salesData()`), not this screen's
      // own former client-side re-derivation - that ad hoc logic
      // (`LedgerRepository.listLedgers()`'s party-like-group heuristic
      // included Sundry Creditors alongside Debtors and excluded Bank/Cash/
      // Branches that the server's actual "sales-data" party-ledger set
      // includes) disagreed with the server, producing a different ledger
      // set than the create-flow screen for the same company.
      final partyLedgers = (salesData['partyLedgers'] as List)
          .cast<Map<String, dynamic>>();
      final salesLedgers = (salesData['salesLedgers'] as List)
          .cast<Map<String, dynamic>>();
      final vatLedgers = (salesData['vatLedgers'] as List)
          .cast<Map<String, dynamic>>();
      final otherLedgersRaw = (salesData['otherLedgers'] as List)
          .cast<Map<String, dynamic>>();

      _commit(() {
        // tally-api's VoucherReservedName enum (2026-08-21 schema-hardening
        // migration) uses screaming-snake-case labels ('SALES'), not
        // Tally's own mixed-case reservedName string ('Sales').
        vchtypenamedata = [
          for (final vt in voucherTypes)
            if (vt['reservedName'] == 'SALES') vt['name'] as String,
        ];
        _voucherTypeMasterIdByName
          ..clear()
          ..addAll({
            for (final vt in voucherTypes)
              if (vt['reservedName'] == 'SALES')
                vt['name'] as String: vt['masterId'] as int,
          });

        _allLedgersCache = [
          ...partyLedgers,
          ...salesLedgers,
          ...vatLedgers,
          ...otherLedgersRaw,
        ];
        for (final ledger in _allLedgersCache) {
          _ledgerMasterIdByName[ledger['name'] as String] =
              ledger['masterId'] as int;
        }

        partyledgerdata = [for (final l in partyLedgers) (l['name'] as String)]
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

        salesledger_data = [for (final l in salesLedgers) l['name'] as String];

        vatledgerdata.add('Not Applicable');
        vatledgerdata.addAll([for (final l in vatLedgers) l['name'] as String]);
        final vatLedgerNames = vatledgerdata.toSet();

        ledgerdata = [
          for (final l in otherLedgersRaw)
            {'name': l['name'], 'vatApplicable': l['vatApplicable']},
        ];

        itemdata = [
          for (final item in stockItems) _shapeStockItemForLegacyItemdata(item),
        ];

        locationsdata = [for (final g in godowns) g['name'] as String];
        _godownMasterIdByName
          ..clear()
          ..addAll({
            for (final g in godowns) g['name'] as String: g['masterId'] as int,
          });

        // Resolve the voucher-entry currency once here - matches the
        // company's configured `currencycode` (prefs), falling back to
        // whatever currency tally-api returns first.
        Map<String, dynamic>? matchedCurrency;
        for (final c in currencies) {
          final iso = (c['isoCurrencyCode'] as String?)?.toUpperCase();
          final symbol = (c['symbol'] as String?)?.toUpperCase();
          if (iso == currencycode.toUpperCase() ||
              symbol == currencycode.toUpperCase()) {
            matchedCurrency = c;
            break;
          }
        }
        matchedCurrency ??= currencies.isNotEmpty ? currencies.first : null;
        _currencyMasterId = matchedCurrency?['masterId'] as int?;

        // ---- Prefill this existing voucher entry's own fields ---------
        final List<dynamic> existingLedgerEntries =
            (data['ledgerEntries'] as List?) ?? const [];
        final List<dynamic> existingInventoryEntries =
            (data['inventoryEntries'] as List?) ?? const [];

        final String oldvchname =
            (data['voucherTypeName'] as String?) ??
            (vchtypenamedata.isNotEmpty ? vchtypenamedata[0] : '');
        final String oldvchno = (data['voucherNumber'] as String?) ?? '';
        final String oldnarration = (data['narration'] as String?) ?? '';
        final String oldrefno = (data['reference'] as String?) ?? '';

        _initialVoucherNumber = oldvchno;
        _originalVoucherNumber = oldvchno;
        _initialNarration = oldnarration;
        _initialReference = oldrefno;

        saledate = DateTime.parse(data['date'] as String);
        saledatestring = _dateFormat.format(saledate);
        saledatetxt = formatlastsaledate(saledatestring);

        final String? referenceDateIso = data['referenceDate'] as String?;
        refdate = referenceDateIso != null
            ? DateTime.parse(referenceDateIso)
            : saledate;
        refdatestring = _dateFormat.format(refdate);
        refdatetxt = formatlastsaledate(refdatestring);

        _selectedvchtypename = oldvchname;

        // Party ledger - the ledgerEntries row flagged isPartyLedger.
        final dynamic partyEntry = existingLedgerEntries.firstWhere(
          (e) => e is Map && e['isPartyLedger'] == true,
          orElse: () => null,
        );
        final String? oldpartyledger = partyEntry is Map
            ? partyEntry['ledgerName'] as String?
            : null;
        _selectedpartyledger = oldpartyledger;

        // Sales ledger - the first inventory entry's own ledgerMasterId/
        // ledgerName.
        String? salesLedgerName;
        if (existingInventoryEntries.isNotEmpty &&
            existingInventoryEntries.first is Map) {
          salesLedgerName =
              (existingInventoryEntries.first as Map)['ledgerName']
                  as String?;
        }
        _selectedsalesledger =
            salesLedgerName ??
            (salesledger_data.isNotEmpty ? salesledger_data[0] : null);

        // VAT ledger - a ledgerEntries row whose ledgerName falls under the
        // 'Duties & Taxes' reserved group (matches vatledgerdata's own
        // classification above).
        final dynamic vatEntry = existingLedgerEntries.firstWhere(
          (e) => e is Map && vatLedgerNames.contains(e['ledgerName']),
          orElse: () => null,
        );
        if (vatEntry is Map) {
          _selectedvatledger = vatEntry['ledgerName'] as String?;
          totalVatAmount = parseMoneyField(vatEntry['amount']);
        } else {
          _selectedvatledger = vatledgerdata.isNotEmpty
              ? vatledgerdata[0]
              : 'Not Applicable';
          totalVatAmount = 0.0;
        }
        roundedtotalVatAmount = double.parse(
          totalVatAmount.toStringAsFixed(decimal!),
        );

        // Manual "other" ledger entries - everything left over (not party,
        // not sales, not VAT).
        final Set<String> salesLedgerNameSet = salesLedgerName != null
            ? {salesLedgerName}
            : <String>{};
        for (final e in existingLedgerEntries) {
          if (e is! Map) continue;
          final String? ledgerName = e['ledgerName'] as String?;
          if (ledgerName == null) continue;
          if (e['isPartyLedger'] == true) continue;
          if (vatLedgerNames.contains(ledgerName)) continue;
          if (salesLedgerNameSet.contains(ledgerName)) continue;
          ledgerEntries.add(
            LedgerEntry(
              ledgerName: ledgerName,
              ledgerAmount: parseMoneyField(e['amount']),
              // No new-schema equivalent for legacy's per-ledger
              // VATAPPLICABLE flag - see this method's doc comment.
              vatApp: false,
            ),
          );
        }
        isVisibleLedgerHeading = ledgerEntries.isNotEmpty;

        // Sale items from inventoryEntries.
        for (final e in existingInventoryEntries) {
          if (e is! Map) continue;
          final String itemName = (e['stockItemName'] as String?) ?? '';
          final double qty = parseMoneyField(e['quantity']);
          final double rate = parseMoneyField(e['rate']);
          final double amount = parseMoneyField(e['amount']);
          final String unitSymbol = (e['unitSymbol'] as String?) ?? '';
          final List<dynamic> batchAllocations =
              (e['batchAllocations'] as List?) ?? const [];
          String itemLocation = '';
          if (batchAllocations.isNotEmpty && batchAllocations.first is Map) {
            itemLocation =
                (batchAllocations.first as Map)['godownName'] as String? ??
                '';
          }

          saleItems.add(
            SaleItem(
              itemName: itemName,
              // itemQuantity is used as an int-parseable string everywhere
              // downstream (int.tryParse/BigInt.parse) - matches legacy's
              // own `extractQuantity` (digits-only, no decimal) behavior.
              itemQuantity: qty.truncate().toString(),
              itemPrice: rate,
              itemAmount: amount,
              itemLocation: itemLocation,
              itemUnit: unitSymbol,
              accountingAllocationList: const {},
              batchAllocationList: const {},
            ),
          );
        }
        isVisibleItemHeading = saleItems.isNotEmpty;

        // Legacy's top-level `totalAmount` has no new-schema equivalent -
        // recompute from the loaded items/ledgers/VAT.
        totalPriceOfItems = saleItems.fold(0.0, (
          double previousAmount,
          SaleItem item,
        ) {
          return previousAmount +
              (double.parse(item.itemPrice.toStringAsFixed(decimal!)) *
                  double.parse(item.itemQuantity));
        });
        totalAmountOfLedgers = ledgerEntries.fold(0.0, (
          double previousAmount,
          LedgerEntry entry,
        ) {
          return previousAmount + entry.ledgerAmount;
        });
        totalAmount = totalPriceOfItems + totalAmountOfLedgers + totalVatAmount;
        roundedtotalAmount = double.parse(
          totalAmount.toStringAsFixed(decimal!),
        );

        if (itemdata.isNotEmpty) {
          _initialItemName = '${itemdata[0]['name']}';
        }

        if (locationsdata.isNotEmpty) {
          _initialLocationName = locationsdata[0];
        }
      });

      if (_selectedvchtypename != null &&
          (_selectedvchtypename as String).isNotEmpty) {
        await fetchVchNos(_selectedvchtypename);
      }
    } on ApiException catch (e) {
      error = e.message;
    } catch (e) {
      error = 'Something went wrong!!!';
    }

    _commit(() => _isLoading = false);
    return error;
  }

  /// Replaces legacy's `GET /api/ledger/getLedger/:company/:serial` with a
  /// local lookup against `_allLedgersCache` (populated by loadData())
  /// instead of a network call - mirrors SalesRegistration.dart's
  /// identically-named method. Returns `null` on lookup failure (matches
  /// original: swallowed, logged only).
  Future<ModifyLedgerLookupResult?> loadLedgerData() async {
    _commit(() => _isLoading = true);
    ModifyLedgerLookupResult? result;
    try {
      final ledger = _allLedgersCache.firstWhere(
        (l) => l['name'] == _selectedpartyledger,
        orElse: () => const {},
      );

      final String tinValue = ledger['tinNumber']?.toString() ?? 'null';
      final String address =
          (ledger['address'] as List?)?.cast<String>().join(', ') ?? 'null';
      final String emirate = ledger['stateName']?.toString() ?? 'null';
      final String country = ledger['countryName']?.toString() ?? 'null';

      result = ModifyLedgerLookupResult(
        tin: tinValue,
        address: address,
        emirate: emirate,
        country: country,
      );
    } catch (e) {
      // matches original: swallowed, logged only
    }

    _commit(() => _isLoading = false);
    return result;
  }

  /// Replaces legacy's `GET /api/entry/nos/:company/:serial` - backed by
  /// tally-api's `GET .../voucher-entries/voucher-numbers`. This entry's
  /// own [_originalVoucherNumber] is excluded from the pool (one
  /// occurrence) so re-saving with it unchanged never flags itself as a
  /// duplicate. Unlike the create-flow siblings, this never auto-fills the
  /// voucher-number field - the existing entry's own number (loaded by
  /// `loadData()`) is left as-is unless the user edits it (which, per this
  /// file's doc-comment, is currently impossible - `isVchEditable`'s edit
  /// button is a no-op).
  Future<String?> fetchVchNos(String vchname) async {
    vchnos.clear();
    _commit(() => _isLoading = true);

    String? error;
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

        // Exclude one occurrence of this entry's own original number so
        // re-saving with it unchanged never flags itself as a duplicate.
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
      error = e.message;
    } catch (e) {
      vchnos.clear();
    }

    _commit(() => _isLoading = false);
    return error;
  }

  /// Replaces legacy's `POST /api/entry/updateEntry/:company/:serial` with
  /// `VoucherEntryRepository.update`, building the request body the same
  /// way SalesRegistration.dart's `saveEntry()` builds its create body
  /// (same `voucherEntrySchema` field mapping) - this screen lets the user
  /// re-edit `ledgerEntries`/`inventoryEntries` in full (add/remove items
  /// and manual ledgers), so both are always rebuilt wholesale from the
  /// current form state and included on every update, matching the
  /// server's delete-then-reinsert semantics for those two arrays. Minus
  /// the pre-save validation (party ledger/empty-items checks, which read
  /// `context` via `showAppMessage` - the widget performs those itself
  /// before calling this) and minus the trailing `loadLedgerData()` call
  /// (the widget does that itself on success, since it also needs to show
  /// the share dialog). [narration]/[vchno]/[refno] come from this
  /// screen's freely-editable `controller_narration`/`_vchnoController`/
  /// `controller_refno` - the widget reads their `.text` and passes it in,
  /// same as every create-flow sibling's `saveEntry()`. Returns `null` on
  /// success, an error message otherwise.
  Future<String?> updateEntry(
    String voucherEntryId, {
    required String narration,
    required String vchno,
    required String refno,
  }) async {
    _commit(() => _isLoading = true);

    roundedtotalAmount = double.parse(totalAmount.toStringAsFixed(decimal!));

    double totalItemAmount = 0.0;
    for (SaleItem item in saleItems) {
      totalItemAmount += double.parse(item.itemAmount.toStringAsFixed(decimal!));
    }

    final int? voucherTypeMasterId =
        _voucherTypeMasterIdByName[_selectedvchtypename];
    final int? partyLedgerMasterId =
        _ledgerMasterIdByName[_selectedpartyledger];
    final int? salesLedgerMasterId =
        _ledgerMasterIdByName[_selectedsalesledger];
    final int? vatLedgerMasterId = _selectedvatledger != 'Not Applicable'
        ? _ledgerMasterIdByName[_selectedvatledger]
        : null;

    if (voucherTypeMasterId == null ||
        partyLedgerMasterId == null ||
        salesLedgerMasterId == null ||
        _currencyMasterId == null) {
      _commit(() => _isLoading = false);
      return 'Could not resolve voucher type/party ledger/sales ledger/currency - please reload and try again.';
    }

    // Legacy encoded debit/credit via a signed AMOUNT plus a redundant
    // "ISDEEMEDPOSITIVE" string; the new schema separates that into a
    // plain positive `amount` and a single `isDebit` boolean.
    final List<Map<String, dynamic>> entryLedgers = [];

    entryLedgers.add({
      'ledgerMasterId': partyLedgerMasterId,
      'amount': roundedtotalAmount,
      'isDebit': true,
      'isPartyLedger': true,
    });

    // Aggregate sales-ledger credit entry - see
    // SalesRegistration.dart's `saveEntry()` doc comment for why this one
    // aggregate row replaces legacy's per-item ACCOUNTINGALLOCATIONS.LIST.
    entryLedgers.add({
      'ledgerMasterId': salesLedgerMasterId,
      'amount': totalItemAmount,
      'isDebit': false,
      'isPartyLedger': false,
    });

    // Manual "other" ledger entries (freight/discount/etc). Any entry
    // whose ledger name doesn't resolve to a masterId (shouldn't
    // normally happen - names come from the same loadData() lists) is
    // skipped rather than sent broken.
    for (final item in ledgerEntries) {
      final int? ledgerMasterId = _ledgerMasterIdByName[item.ledgerName];
      if (ledgerMasterId == null) continue;
      entryLedgers.add({
        'ledgerMasterId': ledgerMasterId,
        'amount': item.ledgerAmount,
        'isDebit': false,
        'isPartyLedger': false,
      });
    }

    if (vatLedgerMasterId != null) {
      entryLedgers.add({
        'ledgerMasterId': vatLedgerMasterId,
        'amount': roundedtotalVatAmount,
        'isDebit': false,
        'isPartyLedger': false,
      });
    }

    final List<Map<String, dynamic>> entryInventory = [];
    for (final item in saleItems) {
      final Map<String, dynamic>? itemInfo = itemdata.firstWhere(
            (i) => i['name'] == item.itemName,
            orElse: () => null,
          )
          as Map<String, dynamic>?;
      final int? stockItemMasterId = itemInfo?['masterid'] as int?;
      final List<dynamic> unitJson =
          (itemInfo?['unit'] as List?) ?? const [];
      final int? unitMasterId = _findUnitMasterId(unitJson, item.itemUnit);

      if (stockItemMasterId == null || unitMasterId == null) {
        // Can't build a valid inventory entry without both masterIds -
        // skip rather than send a request the server will reject.
        continue;
      }

      final double qty = double.tryParse(item.itemQuantity) ?? 0;
      final int? godownMasterId = _godownMasterIdByName[item.itemLocation];

      entryInventory.add({
        'stockItemMasterId': stockItemMasterId,
        'quantity': qty,
        'rate': item.itemPrice,
        'unitMasterId': unitMasterId,
        'amount': item.itemAmount,
        'ledgerMasterId': salesLedgerMasterId,
        'isDebitQuantity': false,
        if (godownMasterId != null)
          'batchAllocations': [
            {
              'godownMasterId': godownMasterId,
              // Tally's own default batch name for a godown-only
              // (non-lot-tracked) allocation.
              'batchName': 'Primary Batch',
              'quantity': qty,
            },
          ],
      });
    }

    final String narrationValue = narration.trim();
    final String refnoValue = refno;
    final String vchnoValue = vchno;

    final Map<String, dynamic> voucherEntryBody = {
      'voucherTypeMasterId': voucherTypeMasterId,
      'date': _isoDate(parseCompactDate(saledatestring)),
      'currencyMasterId': _currencyMasterId,
      'narration': narrationValue,
      if (refnoValue.trim().isNotEmpty) 'reference': refnoValue.trim(),
      'referenceDate': _isoDate(parseCompactDate(refdatestring)),
      if (vchnoValue.trim().isNotEmpty) 'voucherNumber': vchnoValue.trim(),
      'ledgerEntries': entryLedgers,
      'inventoryEntries': entryInventory,
    };

    String? error;
    try {
      await VoucherEntryRepository.instance.update(
        voucherEntryId,
        voucherEntryBody,
      );
    } on ApiException catch (e) {
      error = e.message;
    } catch (e) {
      error = 'Something went wrong!!!';
    }

    _commit(() => _isLoading = false);
    return error;
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();

    company = prefs.getString('company_name');
    serial_no = prefs.getString('serial_no');
    currencycode = prefs.getString('currencycode') ?? 'AED';

    company_trn = prefs.getString("company_trn") ?? "null";
    company_address = prefs.getString("company_address") ?? "null";
    company_emirate = prefs.getString("company_emirate") ?? "null";
    company_country = prefs.getString("company_country") ?? "null";

    vatperc = prefs.getDouble('vatperc') ?? 5.0;
    decimal = prefs.getInt('decimalplace') ?? 2;

    // Placeholder value only - `loadData()` (called right below) is the
    // real source of truth for this existing entry's date, sourced from
    // `data['date']` (the tally-api `voucherEntrySchema` field name)
    // rather than legacy's uppercase `DATE`.
    final String? initialDateIso = _args.data['date'] as String?;
    saledate = initialDateIso != null
        ? DateTime.parse(initialDateIso)
        : DateTime.now();
    saledatestring = _dateFormat.format(saledate);
    saledatetxt = formatlastsaledate(saledatestring);

    refdate = DateTime.now();
    refdatestring = _dateFormat.format(refdate);
    refdatetxt = formatlastsaledate(refdatestring);

    _commit(() {});

    await loadData();
    _commit(() => _isInitialDataLoaded = true);
  }
}

final modifySalesEntryNotifierProvider = StateNotifierProvider.autoDispose
    .family<ModifySalesEntryNotifier, ModifySalesEntryState, ModifySalesEntryArgs>(
  (ref, args) => ModifySalesEntryNotifier(ref, args),
);
