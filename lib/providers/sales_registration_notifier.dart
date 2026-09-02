import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../Items.dart' show formatlastsaledate;
import '../SalesRegistration.dart';
import '../api/api_exception.dart';
import '../api/monthly_bucket_helper.dart' show parseCompactDate, parseMoneyField;
import '../api/pagination_helper.dart';
import '../api/tally_api_client.dart';
import '../api/voucher_entry_dropdowns_repository.dart';
import '../api/voucher_entry_repository.dart';
import '../constants.dart' show vanSalesSerialNo, uniGasSerialNumber;

/// Riverpod migration of `SalesRegistration.dart`'s
/// `_SalesRegistrationPageState`.
///
/// Same verbatim-port `_commit`/`_snapshot` strategy as the other notifiers
/// in this app. This screen is the most entangled one migrated so far -
/// nearly every method mixes `BuildContext`, a modal dialog's own
/// `StatefulBuilder`-local state, and `TextEditingController`s together
/// with the actual voucher data - so the split here is stricter than usual:
///
/// - Network/business methods that touched `context` directly (via
///   `showAppMessage`) now return a result object/nullable error string
///   instead; the widget's same-named wrapper method makes the actual
///   `showAppMessage`/`Navigator`/dialog call based on that result. This
///   mirrors the `XActionResult`-style pattern already used for
///   button-triggered actions elsewhere in this migration.
/// - Every accumulator mutation (`addItem`/`addLedger`/delete/recalculate)
///   is a byte-for-byte port of the original method's math, collapsed from
///   the original's 2 sequential `setState` calls into 1 `_commit` (safe -
///   nothing renders between two synchronous setState calls in the same
///   function, so the observable end state is identical).
/// - Dialog-composition-only fields (the item-add/ledger-add dialog's own
///   currently-being-typed selection, e.g. `_selecteditem`/`_selectedunit`/
///   `selectedLocation`/`isVisibleUnit`/`isPriceLevelLoading`) stay
///   widget-local, unmigrated - they're meaningless outside an open dialog
///   and are already effectively local to it, exactly like this app's other
///   screens keep `TextEditingController`s local.
///
/// Dead fields dropped rather than ported (confirmed unreferenced outside
/// their own declaration/assignment): `isDashEnable`, `isUserEnable`,
/// `isRolesEnable`, `isVisibleNoUserFound`, `isRolesVisible`, `isUserVisible`
/// (write-only), `isVchEditable`, `user_email_fetched`, `unitValue`,
/// `HttpURL`, `jsonEntryData` (all pre-existing dead legacy fields, one of
/// them - `HttpURL` - a leftover from an entirely commented-out legacy
/// `loadData()` still sitting in the file).
class SalesRegistrationState {
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

  final String? hostname;
  final String? company;
  final String? companyLowercase;
  final String? serialNo;
  final String? username;
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
  final String email;

  final DateTime saledate;
  final DateTime refdate;
  final String saledatestring;
  final String saledatetxt;
  final String refdatestring;
  final String refdatetxt;

  final dynamic selectedVchTypeName;
  final dynamic selectedPartyLedger;
  final dynamic selectedSalesLedger;
  final dynamic selectedVatLedger;

  final String errorMessageVchNo;

  final String? selectedPartyMobile;
  final String? selectedPartyEmail;
  final String? selectedPartyLedgerPriceLevel;
  final Map<String, String?> partyLedgerPriceLevelMap;
  final Map<String, String?> partyLedgerCreditPeriodMap;

  const SalesRegistrationState({
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
    required this.hostname,
    required this.company,
    required this.companyLowercase,
    required this.serialNo,
    required this.username,
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
    required this.email,
    required this.saledate,
    required this.refdate,
    required this.saledatestring,
    required this.saledatetxt,
    required this.refdatestring,
    required this.refdatetxt,
    required this.selectedVchTypeName,
    required this.selectedPartyLedger,
    required this.selectedSalesLedger,
    required this.selectedVatLedger,
    required this.errorMessageVchNo,
    required this.selectedPartyMobile,
    required this.selectedPartyEmail,
    required this.selectedPartyLedgerPriceLevel,
    required this.partyLedgerPriceLevelMap,
    required this.partyLedgerCreditPeriodMap,
  });
}

/// Result of [SalesRegistrationNotifier.loadLedgerData] - the widget uses
/// these to call `showSalesInvoiceDialog(context, ...)` itself (that dialog
/// is pure UI, needs `context`).
class LedgerLookupResult {
  final String tin;
  final String address;
  final String emirate;
  final String country;
  LedgerLookupResult({
    required this.tin,
    required this.address,
    required this.emirate,
    required this.country,
  });
}

/// One resolved row for [SalesRegistrationNotifier.addSelectedItemsInBulk] -
/// the widget resolves each selected item's editable rate/qty/unit/location/
/// description `TextEditingController`s into plain values before calling.
class BulkAddEntry {
  final String name;
  final int quantity;
  final double rate;
  final String unit;
  final String location;
  final List<String> descriptions;
  BulkAddEntry({
    required this.name,
    required this.quantity,
    required this.rate,
    required this.unit,
    required this.location,
    required this.descriptions,
  });
}

class SalesRegistrationNotifier extends StateNotifier<SalesRegistrationState> {
  final Ref _ref;

  SalesRegistrationNotifier(this._ref)
    : super(
        SalesRegistrationState(
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
          hostname: '',
          company: '',
          companyLowercase: '',
          serialNo: '',
          username: '',
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
          email: '',
          saledate: DateTime.now(),
          refdate: DateTime.now(),
          saledatestring: '',
          saledatetxt: '',
          refdatestring: '',
          refdatetxt: '',
          selectedVchTypeName: null,
          selectedPartyLedger: null,
          selectedSalesLedger: null,
          selectedVatLedger: null,
          errorMessageVchNo: '',
          selectedPartyMobile: null,
          selectedPartyEmail: null,
          selectedPartyLedgerPriceLevel: null,
          partyLedgerPriceLevelMap: const {},
          partyLedgerCreditPeriodMap: const {},
        ),
      ) {
    _init();
  }

  void _commit(void Function() fn) {
    fn();
    state = _snapshot();
  }

  SalesRegistrationState _snapshot() => SalesRegistrationState(
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
    hostname: hostname,
    company: company,
    companyLowercase: company_lowercase,
    serialNo: serial_no,
    username: username,
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
    email: email,
    saledate: saledate,
    refdate: refdate,
    saledatestring: saledatestring,
    saledatetxt: saledatetxt,
    refdatestring: refdatestring,
    refdatetxt: refdatetxt,
    selectedVchTypeName: _selectedvchtypename,
    selectedPartyLedger: _selectedpartyledger,
    selectedSalesLedger: _selectedsalesledger,
    selectedVatLedger: _selectedvatledger,
    errorMessageVchNo: errorMessageVchNo,
    selectedPartyMobile: _selectedPartyMobile,
    selectedPartyEmail: _selectedPartyEmail,
    selectedPartyLedgerPriceLevel: selectedPartyLedgerPriceLevel,
    partyLedgerPriceLevelMap: Map.unmodifiable(partyLedgerPriceLevelMap),
    partyLedgerCreditPeriodMap: Map.unmodifiable(partyLedgerCreditPeriodMap),
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
  bool isVoucherTypeLocked = false;
  bool isSalesLedgerLocked = false;
  bool isGodownLocked = false;

  bool _isLoading = true;
  bool _isInitialDataLoaded = false;

  String? hostname = '';
  String? company = '';
  String? company_lowercase = '';
  String? serial_no = '';
  String? username = '';
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
  String email = '';

  late DateTime saledate = DateTime.now();
  late DateTime refdate = DateTime.now();
  String saledatestring = '';
  String saledatetxt = '';
  String refdatestring = '';
  String refdatetxt = '';

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
  Map<String, String?> partyLedgerCreditPeriodMap = {};

  bool get isUniGasSerial {
    final currentSerial = serial_no?.trim() ?? '';
    return currentSerial == uniGasSerialNumber;
  }

  /// vatledgerdata[0] is always the synthetic "Not Applicable" entry added
  /// ahead of the API's real VAT ledgers. For UniGas, default to the first
  /// real ledger (vatledgerdata[1]) instead of "Not Applicable".
  String? _defaultVatLedger() {
    if (vatledgerdata.isEmpty) return null;
    if (isUniGasSerial && vatledgerdata.length > 1) {
      return vatledgerdata[1];
    }
    return vatledgerdata[0];
  }

  int? _findUnitMasterId(List<dynamic> unitJson, String unitName) {
    for (final u in unitJson) {
      if (u is Map && u['name'] == unitName) {
        return u['masterId'] as int?;
      }
    }
    return null;
  }

  String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

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

  /// Verbatim port of `addItem()`'s data-mutation half (merge-by name/price/
  /// unit via BigInt quantity addition, or append) plus the totals
  /// recompute - collapsed from the original's 2 sequential `setState`
  /// calls into 1 `_commit`.
  void addOrMergeSaleItem(SaleItem newItem) {
    _commit(() {
      final parsedPrice = newItem.itemPrice;
      int existingIndex = saleItems.indexWhere(
        (item) =>
            item.itemName == newItem.itemName &&
            double.parse(item.itemPrice.toStringAsFixed(decimal!)) ==
                parsedPrice &&
            item.itemUnit == newItem.itemUnit,
      );
      if (existingIndex != -1) {
        SaleItem existingItem = saleItems[existingIndex];
        String newQuantity =
            (BigInt.parse(existingItem.itemQuantity) +
                    BigInt.parse(newItem.itemQuantity))
                .toString();
        double newAmount = parsedPrice * BigInt.parse(newQuantity).toDouble();
        saleItems[existingIndex] = existingItem
            .updateQuantity(newQuantity)
            .updateItemAmount(newAmount);
      } else {
        saleItems.add(newItem);
      }
      _recalculateTotals();
    });
  }

  /// Verbatim port of `_deleteSaleItem`.
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

  /// Verbatim port of `addLedger()`'s data-mutation half (merge-by-name or
  /// append) plus the totals recompute.
  void addOrMergeLedger(String ledgerName, double amount) {
    _commit(() {
      final specificLedger = ledgerdata.firstWhere(
        (ledger) => ledger['name'] == ledgerName,
      );
      final int vatApplicable = specificLedger['vatapplicable'] ?? 0;
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

  /// Verbatim port of `_deleteLedger`.
  void deleteLedger(int index) {
    _commit(() {
      ledgerEntries.removeAt(index);
      isVisibleLedgerHeading = ledgerEntries.isNotEmpty;
      _recalculateTotals();
    });
  }

  /// Verbatim port of `_addSelectedItemsInBulk`'s merge-or-append loop
  /// (mirrors `addOrMergeSaleItem`'s per-item logic exactly, matching the
  /// original's own duplicated-but-equivalent bulk-add version), followed
  /// by the shared totals recompute (`_recalcTotalsAfterBulkAdd` in the
  /// original - unified here with `_recalculateTotals()` since both did the
  /// same computation, the bulk version just used shadowing locals instead
  /// of writing the outer accumulator fields, a divergence with no
  /// observable effect since every other mutator already overwrites them).
  void addSelectedItemsInBulk(List<BulkAddEntry> entries) {
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
              basicUserDescriptions: entry.descriptions,
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

  /// Verbatim port of the party-ledger `TypeAheadField.onSelected` body.
  void selectPartyLedger(String suggestion) {
    _commit(() {
      _selectedpartyledger = suggestion;
      selectedPartyLedgerPriceLevel = partyLedgerPriceLevelMap[suggestion];
    });
  }

  /// Verbatim port of the party-ledger clear ("x") button.
  void clearSelectedPartyLedger() {
    _commit(() {
      _selectedpartyledger = '';
      selectedPartyLedgerPriceLevel = null;
    });
  }

  /// Verbatim port of the VAT-ledger dropdown `onChanged` body (which
  /// duplicates `_recalculateTotals()`'s logic inline in the original -
  /// unified here, no observable difference).
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
      refdatestring = _dateFormat.format(refdate);
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

  /// Verbatim port of `generateNextVchNo` - groups voucher numbers by their
  /// "prefix#suffix" numeric-slot pattern (ignoring a trailing 4-digit
  /// year-like number, e.g. "2026", when another number is present),
  /// then finds the first gap in the dominant pattern's number sequence
  /// (or continues past the max if there's no gap).
  String generateNextVchNo() {
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

  // ---- network / data-loading methods (return result info, no context) --

  Future<String?> loadData() async {
    vchtypenamedata.clear();
    itemdata.clear();
    salesledger_data.clear();
    partyledgerdata.clear();
    vatledgerdata.clear();
    ledgerdata.clear();
    locationsdata.clear();
    _ledgerMasterIdByName.clear();
    _voucherTypeMasterIdByName.clear();
    _godownMasterIdByName.clear();
    _allLedgersCache = [];
    _currencyMasterId = null;

    _commit(() => _isLoading = true);

    String? error;
    try {
      final String currentSerialNo = serial_no?.trim() ?? '';
      final bool isUniGas = vanSalesSerialNo.contains(currentSerialNo);

      final results = await Future.wait([
        VoucherEntryDropdownsRepository.instance.salesData(),
        fetchAllPages(
          (page) => TallyApiClient().getForCompany(
            '/currencies?page=$page&limit=100',
          ),
        ),
      ]);

      final salesData = results[0] as Map<String, dynamic>;
      final currencies = results[1] as List<Map<String, dynamic>>;

      final voucherTypes = (salesData['vchTypes'] as List)
          .cast<Map<String, dynamic>>();
      final partyLedgers = (salesData['partyLedgers'] as List)
          .cast<Map<String, dynamic>>();
      final salesLedgers = (salesData['salesLedgers'] as List)
          .cast<Map<String, dynamic>>();
      final vatLedgers = (salesData['vatLedgers'] as List)
          .cast<Map<String, dynamic>>();
      final otherLedgersRaw = (salesData['otherLedgers'] as List)
          .cast<Map<String, dynamic>>();
      final stockItems = (salesData['items'] as List)
          .cast<Map<String, dynamic>>();
      final godowns = (salesData['godowns'] as List)
          .cast<Map<String, dynamic>>();

      String? trimOrNull(String? raw) =>
          (raw?.trim().isEmpty ?? true) ? null : raw!.trim();

      String? voucherTypeToFetch;

      _commit(() {
        vchtypenamedata = [for (final vt in voucherTypes) vt['name'] as String];
        _voucherTypeMasterIdByName
          ..clear()
          ..addAll({
            for (final vt in voucherTypes)
              vt['name'] as String: vt['masterId'] as int,
          });

        isVoucherTypeLocked = vchtypenamedata.length == 1;
        _selectedvchtypename = vchtypenamedata.isNotEmpty
            ? vchtypenamedata[0]
            : null;
        voucherTypeToFetch = _selectedvchtypename;

        _allLedgersCache = [
          ...partyLedgers,
          ...salesLedgers,
          ...vatLedgers,
          ...otherLedgersRaw,
        ];
        _ledgerMasterIdByName.clear();
        for (final ledger in _allLedgersCache) {
          _ledgerMasterIdByName[ledger['name'] as String] =
              ledger['masterId'] as int;
        }

        if (isUniGas) {
          partyledgerdata.clear();
          partyLedgerPriceLevelMap.clear();
          partyLedgerCreditPeriodMap.clear();

          for (final ledger in partyLedgers) {
            final String ledgerName = (ledger['name'] as String).trim();
            if (ledgerName.isEmpty) continue;

            if (!partyledgerdata.contains(ledgerName)) {
              partyledgerdata.add(ledgerName);
            }
            partyLedgerPriceLevelMap[ledgerName] = trimOrNull(
              ledger['priceLevel'] as String?,
            );
            partyLedgerCreditPeriodMap[ledgerName] = trimOrNull(
              ledger['creditPeriod'] as String?,
            );
          }
        } else {
          partyledgerdata = [
            for (final l in partyLedgers) (l['name'] as String),
          ];
        }
        partyledgerdata.sort(
          (a, b) => a.toLowerCase().compareTo(b.toLowerCase()),
        );

        salesledger_data = [for (final l in salesLedgers) l['name'] as String];

        final String? defaultSalesLedgerName = salesledger_data.length == 1
            ? salesledger_data.first
            : null;

        if (defaultSalesLedgerName != null &&
            defaultSalesLedgerName.isNotEmpty &&
            salesledger_data.contains(defaultSalesLedgerName)) {
          _selectedsalesledger = defaultSalesLedgerName;
        } else {
          _selectedsalesledger = salesledger_data.isNotEmpty
              ? salesledger_data[0]
              : null;
        }
        isSalesLedgerLocked = false;

        vatledgerdata.add('Not Applicable');
        vatledgerdata.addAll([for (final l in vatLedgers) l['name'] as String]);

        ledgerdata = [
          for (final l in otherLedgersRaw) {'name': l['name']},
        ];

        _selectedvatledger = _defaultVatLedger();

        itemdata = [
          for (final item in stockItems) _shapeStockItemForLegacyItemdata(item),
        ];

        locationsdata = [for (final g in godowns) g['name'] as String];
        _godownMasterIdByName
          ..clear()
          ..addAll({
            for (final g in godowns) g['name'] as String: g['masterId'] as int,
          });

        isGodownLocked = locationsdata.length == 1;

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
      });

      if (voucherTypeToFetch != null && voucherTypeToFetch!.isNotEmpty) {
        await fetchVchNos(voucherTypeToFetch!, DateTime(DateTime.now().year, 12, 31));
      }
    } on ApiException catch (e) {
      error = e.message;
    } catch (e) {
      error = 'Something went wrong!!!';
    }

    _commit(() => _isLoading = false);
    return error;
  }

  Map<String, dynamic> _shapeStockItemForLegacyItemdata(
    Map<String, dynamic> item,
  ) {
    final int? baseUnitMasterId = item['baseUnitMasterId'] as int?;
    final String? baseUnitSymbol = (item['baseUnitSymbol'] as String?)?.trim();
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

  /// Verbatim port of `loadLedgerData` minus the `showSalesInvoiceDialog`
  /// call - that's pure UI (needs `context`), so it's the widget's job to
  /// call it using this result.
  Future<LedgerLookupResult?> loadLedgerData() async {
    _commit(() => _isLoading = true);
    LedgerLookupResult? result;
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

      _commit(() {
        _selectedPartyMobile = ledger['mobileNumber']?.toString();
        _selectedPartyEmail = ledger['email']?.toString();
      });

      result = LedgerLookupResult(
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

  /// Verbatim port of `fetchvchnos`, minus the `_vchnoController.text`
  /// write (widget-local controller) - the widget reads
  /// `generateNextVchNo()`'s result via [state] after this resolves.
  Future<String?> fetchVchNos(String vchname, DateTime toDate) async {
    vchnos.clear();
    _commit(() => _isLoading = true);

    String? error;
    try {
      final int? voucherTypeMasterId = _voucherTypeMasterIdByName[vchname];

      if (voucherTypeMasterId != null) {
        final String fromParam = DateFormat(
          'yyyy-MM-dd',
        ).format(parseCompactDate(startfrom));
        final String toParam = DateFormat('yyyy-MM-dd').format(toDate);

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

    _commit(() => _isLoading = false);
    return error;
  }

  /// Verbatim port of `saveEntry()`'s payload-building/submit logic, minus
  /// the pre-save validation (which reads `context` via `showAppMessage` -
  /// the widget performs those checks itself before calling this, reading
  /// [state]) and minus the trailing `loadLedgerData()` refresh call (the
  /// widget does that itself on success, since it also needs to show the
  /// print dialog).
  Future<String?> saveEntry({
    required String narration,
    required String vchno,
    required String refno,
  }) async {
    _commit(() => _isLoading = true);

    final String currentSerialNo = serial_no?.trim() ?? '';
    final bool isUniGas = vanSalesSerialNo.contains(currentSerialNo);

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

    final List<Map<String, dynamic>> entryLedgers = [];

    final List<Map<String, dynamic>> partyBillAllocations = [];
    if (isUniGas) {
      final String? creditPeriodText =
          partyLedgerCreditPeriodMap[_selectedpartyledger];
      final int? creditDays = creditPeriodText == null
          ? null
          : int.tryParse(
              RegExp(r'\d+').firstMatch(creditPeriodText)?.group(0) ?? '',
            );
      final DateTime dueDate = creditDays != null
          ? saledate.add(Duration(days: creditDays))
          : saledate;

      final bool hasRefNo = refno.trim().isNotEmpty;
      final String billName = hasRefNo ? refno.trim() : vchno;
      final DateTime billDate = hasRefNo
          ? parseCompactDate(refdatestring)
          : parseCompactDate(saledatestring);

      partyBillAllocations.add({
        'billName': billName,
        'billType': 'New Ref',
        'amount': roundedtotalAmount,
        'date': _isoDate(billDate),
        'dueDate': _isoDate(dueDate),
      });
    }

    entryLedgers.add({
      'ledgerMasterId': partyLedgerMasterId,
      'amount': roundedtotalAmount,
      'isDebit': true,
      'isPartyLedger': true,
      if (partyBillAllocations.isNotEmpty) 'billAllocations': partyBillAllocations,
    });

    entryLedgers.add({
      'ledgerMasterId': salesLedgerMasterId,
      'amount': totalItemAmount,
      'isDebit': false,
      'isPartyLedger': false,
    });

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
      ) as Map<String, dynamic>?;
      final int? stockItemMasterId = itemInfo?['masterid'] as int?;
      final List<dynamic> unitJson = (itemInfo?['unit'] as List?) ?? const [];
      final int? unitMasterId = _findUnitMasterId(unitJson, item.itemUnit);

      if (stockItemMasterId == null || unitMasterId == null) {
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
        'description': item.basicUserDescriptions,
        if (godownMasterId != null)
          'batchAllocations': [
            {
              'godownMasterId': godownMasterId,
              'batchName': 'Primary Batch',
              'quantity': qty,
            },
          ],
      });
    }

    final Map<String, dynamic> voucherEntryBody = {
      'voucherTypeMasterId': voucherTypeMasterId,
      'date': _isoDate(parseCompactDate(saledatestring)),
      'currencyMasterId': _currencyMasterId,
      'narration': narration,
      if (refno.trim().isNotEmpty) 'reference': refno.trim(),
      'referenceDate': _isoDate(parseCompactDate(refdatestring)),
      if (vchno.trim().isNotEmpty) 'voucherNumber': vchno.trim(),
      'ledgerEntries': entryLedgers,
      'inventoryEntries': entryInventory,
    };

    String? error;
    try {
      await VoucherEntryRepository.instance.create(voucherEntryBody);
    } on ApiException catch (e) {
      error = e.message;
    } catch (e) {
      error = 'Something went wrong!!!';
    }

    _commit(() => _isLoading = false);
    return error;
  }

  /// Verbatim port of the post-save "No, Thanks" dialog button's data
  /// reset (voucher date/ref date back to today, party ledger/VAT ledger
  /// defaults, sale items/ledger entries/totals cleared) - the widget
  /// separately resets its own controllers/dialog-composition fields
  /// (`_selecteditem`/`_selectedledger`/`selectedLocation`/etc.) alongside
  /// this call, and re-fetches voucher numbers for the still-selected
  /// voucher type itself (needs the widget's own `fetchvchnos` wrapper).
  void resetAfterSave() {
    _commit(() {
      saledate = DateTime.now();
      saledatestring = _dateFormat.format(saledate);
      saledatetxt = formatlastsaledate(saledatestring);

      refdate = DateTime.now();
      refdatestring = _dateFormat.format(refdate);
      refdatetxt = formatlastsaledate(refdatestring);

      _selectedpartyledger = null;
      _selectedvatledger = _defaultVatLedger();

      saleItems.clear();
      ledgerEntries.clear();

      totalPriceOfItems = 0.0;
      totalAmountOfLedgers = 0.0;
      totalVatAmount = 0.0;
      roundedtotalVatAmount = 0.0;
      roundedtotalAmount = 0.0;

      isVisibleItemHeading = false;
      isVisibleLedgerHeading = false;
    });
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();

    hostname = prefs.getString('hostname');
    company = prefs.getString('company_name');
    company_lowercase = (company ?? '').replaceAll(' ', '').toLowerCase();
    serial_no = prefs.getString('serial_no');
    username = prefs.getString('username');
    token = prefs.getString('token') ?? '';
    currencycode = prefs.getString('currencycode') ?? 'AED';
    startfrom =
        prefs.getString('startfrom') ??
        DateFormat('yyyyMMdd').format(DateTime(DateTime.now().year, 1, 1));

    company_trn = prefs.getString("company_trn") ?? "null";
    company_address = prefs.getString("company_address") ?? "null";
    company_emirate = prefs.getString("company_emirate") ?? "null";
    company_country = prefs.getString("company_country") ?? "null";

    vatperc = prefs.getDouble('vatperc') ?? 5.0;
    decimal = prefs.getInt('decimalplace') ?? 2;

    saledate = DateTime.now();
    saledatestring = _dateFormat.format(saledate);
    saledatetxt = formatlastsaledate(saledatestring);

    refdate = saledate;
    refdatestring = saledatestring;
    refdatetxt = saledatetxt;

    SecuritybtnAcessHolder = prefs.getString('secbtnaccess');

    String? email_nav = prefs.getString('email_nav');
    String? name_nav = prefs.getString('name_nav');
    if (email_nav != null && name_nav != null) {
      name = name_nav;
      email = email_nav;
    }

    _commit(() {});

    await loadData();
    _commit(() => _isInitialDataLoaded = true);
  }
}

final salesRegistrationNotifierProvider = StateNotifierProvider.autoDispose<
    SalesRegistrationNotifier, SalesRegistrationState>(
  (ref) => SalesRegistrationNotifier(ref),
);
