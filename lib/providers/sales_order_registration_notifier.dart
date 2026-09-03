import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../Items.dart' show formatlastsaledate;
import '../SalesOrderRegistration.dart';
import '../api/api_exception.dart';
import '../api/monthly_bucket_helper.dart' show parseMoneyField;
import '../api/pagination_helper.dart';
import '../api/stock_repository.dart';
import '../api/tally_api_client.dart';
import '../api/voucher_entry_dropdowns_repository.dart';
import '../api/voucher_entry_repository.dart';
import '../constants.dart' show uniGasSerialNumber;

/// Riverpod migration of `SalesOrderRegistration.dart`'s
/// `_SalesOrderRegistrationPageState`. Same verbatim `_commit`/`_snapshot`
/// port strategy as `sales_registration_notifier.dart` (its closest
/// sibling - read that file's doc-comment first).
///
/// Deviations from that sibling, specific to this screen (see the
/// migration task notes for the full rationale):
/// - `saveEntry()` resolves `unitMasterId` straight off `itemdata`'s own
///   `unit` list (`{'name', 'multiplier', 'masterId'}`, built by
///   `loadData()`'s own reshape of the stock-item API response) rather than
///   through a separate helper - this screen's `Unit` class has no
///   `masterId` of its own, but `itemdata`'s raw unit maps do.
/// - There is no `referenceDate`/"Ref Date" concept here - only a single
///   `controller_orderno` ("Order No.") field, which becomes the
///   `'reference'` key in `saveEntry()`'s payload.
/// - `saledate`/`refdate` in the original: `refdate` is dead (never read
///   outside its own declaration) and is dropped entirely here.
/// - Dialog-composition-only fields that stay widget-local (unmigrated,
///   same treatment as `TextEditingController`s): `_selectedledger`,
///   `_selecteditem`, `_selectedunit`, `selectedLocation`,
///   `isVisibleLocation`, `isVisibleUnit`, `unitdata`, `selectedMultiplier`,
///   `isVchEditable`.
/// - Dead fields dropped rather than ported (declared/written but never
///   read for logic/UI, confirmed via grep before dropping): `isDashEnable`,
///   `isRolesVisible`, `isUserVisible`, `isUserEnable`, `isRolesEnable`,
///   `isVisibleNoUserFound`, `hostname` (write-only), `company_lowercase`
///   (write-only), `username` (write-only), `HttpURL`, `unitValue`, `name`,
///   `email` (all write-only - fed from nav args but never read),
///   `SecuritybtnAcessHolder` (its only reader fed the now-dead
///   `isRolesVisible`/`isUserVisible` pair, so the whole chain is dead).
///   `company` and `serial_no`/`securitybtnAccessHolder`... - `company` IS
///   live (read by the PDF generator) so it's kept.
/// - `addItem()` and both copies of `_showItemDetailsPopup` (a
///   block-commented dead legacy copy plus a "live"-looking copy that turned
///   out to have zero call sites anywhere in the file - the single-item-add
///   flow was fully superseded by `_showMultiItemSelectPopup`'s bulk-add
///   flow) were deleted outright from the widget rather than migrated -
///   confirmed via a whole-file grep for call sites before deleting either.
class SalesOrderRegistrationState {
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

  final String? hostname;
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

  const SalesOrderRegistrationState({
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
    required this.hostname,
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
  });
}

/// Result of [SalesOrderRegistrationNotifier.fetchVchNos] - the widget sets
/// `_vchnoController.text` itself from [nextVchNo] (mirrors
/// `sales_registration_notifier.dart`'s `fetchVchNos`).
class VchNosResult {
  final String? error;
  final String nextVchNo;
  VchNosResult({required this.error, required this.nextVchNo});
}

/// One resolved row for [SalesOrderRegistrationNotifier.addSelectedItemsInBulk]
/// - the widget resolves each selected item's editable rate/qty/unit/
/// location/meter-reading `TextEditingController`s into plain values before
/// calling, exactly like `BulkAddEntry` in the SalesRegistration sibling,
/// extended with this screen's `meterFrom`/`meterTo` UniGas fields.
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

class SalesOrderRegistrationNotifier
    extends StateNotifier<SalesOrderRegistrationState> {
  final Ref _ref;

  SalesOrderRegistrationNotifier(this._ref)
    : super(
        SalesOrderRegistrationState(
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
          hostname: '',
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
        ),
      ) {
    _init();
  }

  void _commit(void Function() fn) {
    fn();
    state = _snapshot();
  }

  SalesOrderRegistrationState _snapshot() => SalesOrderRegistrationState(
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
    hostname: hostname,
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

  String? hostname = '';
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

  bool get isUniGasSerial {
    final currentSerial = serial_no?.trim() ?? '';
    return currentSerial == uniGasSerialNumber;
  }

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

  /// Verbatim port of the item-card stepper's `onIncrement` body (build()'s
  /// inline `_recalculateTotals()` call, unified into the same helper).
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
  /// append, using `ledgerdata`'s `vatApplicable` bool). The widget resolves
  /// [ledgerName]/[amount] from its dialog-local `_selectedledger`/
  /// `ledgerAmountController` before calling.
  void addLedger(String ledgerName, double amount) {
    _commit(() {
      final specificLedger = ledgerdata.firstWhere(
        (ledger) => ledger['name'] == ledgerName,
      );
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
  /// (the live "Add Item" flow, via `_showMultiItemSelectPopup`) followed by
  /// `_recalcTotalsAfterBulkAdd`'s totals recompute - unified into the same
  /// `_recalculateTotals()` every other mutator uses (see that method's own
  /// comment for why this is a safe, non-observable unification).
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
  /// call - the widget does that itself right after this, matching the
  /// original's fire-and-forget behaviour).
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

  /// Verbatim port of `generateNextVchNo` (a pure function of its
  /// argument - kept as a method taking [vchnos] explicitly, same as the
  /// original, rather than reading the field implicitly).
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

  // ---- network / data-loading methods (return result info, no context) --

  /// Verbatim port of `loadData()`, minus the `_partyLedgerController.text`/
  /// `_itemController.text`/`_updateUnitDropdown(...)` calls at the end
  /// (widget-local controllers/dialog-composition fields - the widget syncs
  /// those itself right after this resolves, same pattern as
  /// `sales_registration_notifier.dart`'s own `loadData()`).
  Future<String?> loadData() async {
    vchtypenamedata.clear();
    itemdata.clear();
    salesledger_data.clear();
    partyledgerdata.clear();
    vatledgerdata.clear();
    ledgerdata.clear();
    locationsdata.clear();
    _ledgerMasterIdByName.clear();
    _godownMasterIdByName.clear();
    _voucherTypeMasterIdByName.clear();

    _commit(() => _isLoading = true);

    String? error;
    try {
      final results = await Future.wait([
        StockRepository.instance.listStockItems(),
        VoucherEntryDropdownsRepository.instance.salesData(type: 'salesOrder'),
        _fetchGodowns(),
        _fetchVoucherTypes(),
        _fetchCurrencyMasterId(currencycode),
      ]);

      final stockItems = results[0] as List<Map<String, dynamic>>;
      final salesData = results[1] as Map<String, dynamic>;
      final godowns = results[2] as List<Map<String, dynamic>>;
      final voucherTypes = results[3] as List<Map<String, dynamic>>;
      _currencyMasterId = results[4] as int?;

      // Same server-side classification `SalesRegistration.dart` uses (via
      // `VoucherEntryDropdownsRepository.salesData()`), not this screen's
      // own now-removed client-side re-derivation - that ad hoc logic
      // (raw `/ledgers` + `/groups` fetch, `LedgerRepository.listLedgers()`
      // for "party ledgers") disagreed with the server's actual
      // classification (party ledgers included Sundry Creditors alongside
      // Debtors; VAT ledgers included every VAT-applicable ledger company-
      // wide instead of just the DUTIES group), producing different
      // dropdown contents than the Sales screen for the same company.
      final partyLedgers = (salesData['partyLedgers'] as List)
          .cast<Map<String, dynamic>>();
      final salesLedgers = (salesData['salesLedgers'] as List)
          .cast<Map<String, dynamic>>();
      final vatLedgers = (salesData['vatLedgers'] as List)
          .cast<Map<String, dynamic>>();
      final otherLedgersRaw = (salesData['otherLedgers'] as List)
          .cast<Map<String, dynamic>>();

      final allLedgers = [
        ...partyLedgers,
        ...salesLedgers,
        ...vatLedgers,
        ...otherLedgersRaw,
      ];
      for (final l in allLedgers) {
        _ledgerMasterIdByName[l['name'] as String] = l['masterId'] as int;
      }
      for (final g in godowns) {
        _godownMasterIdByName[g['name'] as String] = g['masterId'] as int;
      }
      final salesOrderTypes = voucherTypes
          .where((v) => v['reservedName'] == 'SALES_ORDER')
          .toList();
      for (final v in salesOrderTypes) {
        _voucherTypeMasterIdByName[v['name'] as String] = v['masterId'] as int;
      }

      _commit(() {
        vchtypenamedata = salesOrderTypes.map((v) => v['name'] as String).toList();
        _selectedvchtypename = (vchtypenamedata.isNotEmpty ? vchtypenamedata[0] : null);

        partyledgerdata = partyLedgers.map((l) => l['name'] as String).toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
        _selectedpartyledger = (partyledgerdata.isNotEmpty ? partyledgerdata[0] : null);

        salesledger_data = salesLedgers.map((l) => l['name'] as String).toList();
        _selectedsalesledger = (salesledger_data.isNotEmpty ? salesledger_data[0] : null);

        ledgerdata = [
          for (final l in otherLedgersRaw)
            {'name': l['name'], 'vatApplicable': l['vatApplicable']},
        ];

        vatledgerdata.add('Not Applicable');
        vatledgerdata.addAll(vatLedgers.map((l) => l['name'] as String));
        _selectedvatledger = (vatledgerdata.isNotEmpty ? vatledgerdata[0] : null);

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
      });

      if (_selectedvchtypename != null) {
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

  Future<List<Map<String, dynamic>>> _fetchGodowns() => fetchAllPages(
    (page) => _tallyApiClient.getForCompany('/godowns?page=$page&limit=100'),
  );

  Future<List<Map<String, dynamic>>> _fetchVoucherTypes() => fetchAllPages(
    (page) => _tallyApiClient.getForCompany('/voucher-types?page=$page&limit=100'),
  );

  Future<int?> _fetchCurrencyMasterId(String isoCode) async {
    final currencies = await fetchAllPages(
      (page) => _tallyApiClient.getForCompany('/currencies?page=$page&limit=100'),
    );
    if (currencies.isEmpty) return null;
    final match = currencies.firstWhere(
      (c) =>
          (c['isoCurrencyCode'] as String?)?.toUpperCase() ==
          isoCode.toUpperCase(),
      orElse: () => currencies.first,
    );
    return match['masterId'] as int?;
  }

  /// Verbatim port of `fetchvchnos`, minus the `_vchnoController.text`
  /// write - the widget sets it from [VchNosResult.nextVchNo] itself.
  Future<VchNosResult> fetchVchNos(String vchname) async {
    vchnos.clear();
    _commit(() => _isLoading = true);

    String? error;
    try {
      final int? voucherTypeMasterId = _voucherTypeMasterIdByName[vchname];

      if (voucherTypeMasterId != null) {
        final String fromParam = DateFormat('yyyy-MM-dd').format(yearStartDate);
        final String toParam = DateFormat('yyyy-MM-dd').format(yearEndDate);

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
      error = 'Could not reach the server. Please try again.';
    }

    final String nextVch = generateNextVchNo(vchnos);
    _commit(() => _isLoading = false);
    return VchNosResult(error: error, nextVchNo: nextVch);
  }

  /// Verbatim port of `saveEntry()`'s payload-building/submit logic, minus
  /// the pre-save validation (party ledger/sale-items-empty checks, which
  /// read `context` via `showAppMessage` - the widget performs those itself
  /// before calling this) and minus the trailing `showSalesOrderDialog(...)`
  /// call (pure UI). [narration]/[vchno]/[refno] come from this screen's
  /// `controller_narration`/`_vchnoController`/`controller_orderno` - `refno`
  /// becomes the `'reference'` payload key (this screen has no separate
  /// reference-date field, unlike its SalesRegistration sibling).
  ///
  /// `unitMasterId` resolution: `itemdata`'s own `unit` list already carries
  /// each unit's `masterId` (built by `loadData()`'s reshape of the raw
  /// stock-item API response above) - looked up here by matching
  /// `item.itemUnit` against `unit['name']`, same as the original.
  Future<String?> saveEntry({
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
      if (vchno.trim().isNotEmpty) 'voucherNumber': vchno.trim(),
      'ledgerEntries': ledgerEntriesPayload,
      'inventoryEntries': inventoryEntries,
    };

    String? error;
    try {
      await VoucherEntryRepository.instance.create(body);
    } on ApiException catch (e) {
      error = e.message;
    } catch (e) {
      error = 'Could not reach the server. Please try again.';
    }

    _commit(() => _isLoading = false);
    return error;
  }

  /// Verbatim port of the shared post-save reset block (identical in the
  /// original between `generateSalesOrderPDF()`'s tail and
  /// `showSalesOrderDialog`'s "No, Thanks" button), minus the
  /// `_partyLedgerController`/`_itemController`/`_dateController` writes,
  /// `_updateUnitDropdown(...)` call, dialog-local `_selectedledger`/
  /// `_selecteditem`/`selectedLocation`/`isVisibleLocation` resets, and the
  /// `fetchvchnos(...)` re-fetch - all widget-side concerns the widget's own
  /// `_resetAfterSave()` wrapper performs right after calling this.
  void resetAfterSave() {
    _commit(() {
      saledate = DateTime.now();
      saledatestring = _dateFormat.format(saledate);
      saledatetxt = formatlastsaledate(saledatestring);

      _selectedvchtypename = (vchtypenamedata.isNotEmpty ? vchtypenamedata[0] : null);
      _selectedpartyledger = (partyledgerdata.isNotEmpty ? partyledgerdata[0] : null);
      _selectedsalesledger = (salesledger_data.isNotEmpty ? salesledger_data[0] : null);
      _selectedvatledger = (vatledgerdata.isNotEmpty ? vatledgerdata[0] : null);

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

    vatperc = prefs.getDouble('vatperc') ?? 5.0;
    decimal = prefs.getInt('decimalplace') ?? 2;

    saledate = DateTime.now();
    saledatestring = _dateFormat.format(saledate);
    saledatetxt = formatlastsaledate(saledatestring);

    _commit(() {});

    await loadData();
    _commit(() => _isInitialDataLoaded = true);
  }
}

final salesOrderRegistrationNotifierProvider = StateNotifierProvider.autoDispose<
    SalesOrderRegistrationNotifier, SalesOrderRegistrationState>(
  (ref) => SalesOrderRegistrationNotifier(ref),
);
