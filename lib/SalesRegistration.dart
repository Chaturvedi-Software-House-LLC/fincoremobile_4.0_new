import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:FincoreGo/Items.dart';
import 'package:FincoreGo/PendingSalesEntry.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'constants.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:FincoreGo/widgets/app_bottom_nav.dart';
import 'widgets/entry_widgets.dart';
import 'widgets/searchable_selector.dart';
import 'widgets/signature_capture.dart';
import 'api/api_exception.dart';
import 'api/voucher_entry_repository.dart';
import 'api/voucher_entry_dropdowns_repository.dart';
import 'api/price_level_repository.dart';
import 'api/pagination_helper.dart';
import 'api/tally_api_client.dart';
import 'api/monthly_bucket_helper.dart' show parseMoneyField, parseCompactDate;

class SalesRegistration extends StatefulWidget {
  const SalesRegistration({Key? key}) : super(key: key);
  @override
  _SalesRegistrationPageState createState() => _SalesRegistrationPageState();
}

// Debug helper for the bulk multi-item add: records which source
// (Price Level / Item Rate / Manual) an item's rate came from.
class _ResolvedRateInfo {
  final double? rate;
  final String source;
  final bool loading;

  _ResolvedRateInfo({
    required this.rate,
    required this.source,
    required this.loading,
  });
}

class SaleItem {
  final String itemName;
  String itemQuantity;
  double itemPrice;
  final double itemAmount;
  final String itemLocation;
  final String itemUnit;
  late Map<String, dynamic> accountingAllocationList;
  late Map<String, dynamic> batchAllocationList;
  // UniGas-only, user-typed free-text description lines for this item
  // (Tally's "Basic User Description" on a stock item) - each entry here
  // becomes its own BASICUSERDESCRIPTION.LIST object, one item can have
  // several (matching the multiple separate single-line boxes in the UI).
  // Empty list when none entered - no BASICUSERDESCRIPTION.LIST is sent.
  final List<String> basicUserDescriptions;

  SaleItem({
    required this.itemName,
    required this.itemQuantity,
    required this.itemPrice,
    required this.itemAmount,
    required this.itemLocation,
    required this.itemUnit,
    required this.accountingAllocationList,
    required this.batchAllocationList,
    this.basicUserDescriptions = const [],
  });

  SaleItem updateQuantity(String newQuantity) {
    return SaleItem(
      itemName: this.itemName,
      itemQuantity: newQuantity,
      itemPrice: this.itemPrice,
      itemAmount: this.itemPrice * double.parse(newQuantity),
      itemLocation: this.itemLocation,
      itemUnit: this.itemUnit,
      accountingAllocationList: this.accountingAllocationList,
      batchAllocationList: this.batchAllocationList,
      basicUserDescriptions: this.basicUserDescriptions,
    );
  }

  SaleItem updateItemAmount(double newAmount) {
    return SaleItem(
      itemName: this.itemName,
      itemQuantity: this.itemQuantity,
      itemPrice: this.itemPrice,
      itemAmount: newAmount,
      itemLocation: this.itemLocation,
      itemUnit: this.itemUnit,
      accountingAllocationList: this.accountingAllocationList,
      batchAllocationList: this.batchAllocationList,
      basicUserDescriptions: this.basicUserDescriptions,
    );
  }
}

class Unit {
  final String name;
  final double multiplier;
  // tally-api's unitMasterId for this unit (base or additional unit of the
  // stock item) - populated only by the tally-api-backed itemdata shape
  // built in loadData(); null for any other caller that doesn't supply it.
  // Needed at submit time to resolve the selected unit name back to the
  // masterId voucherEntrySchema's inventoryEntries[].unitMasterId requires.
  final int? masterId;

  Unit({required this.name, required this.multiplier, this.masterId});

  factory Unit.fromJson(Map<String, dynamic> json) {
    return Unit(
      name: json['name'],
      multiplier: double.parse(json['multiplier']),
      masterId: json['masterId'] as int?,
    );
  }
}

class LedgerEntry {
  final String ledgerName;
  final double ledgerAmount;
  final bool vatApp;

  LedgerEntry({
    required this.ledgerName,
    required this.ledgerAmount,
    required this.vatApp,
  });

  LedgerEntry updateAmount(double newAmount, bool vatApp) {
    return LedgerEntry(
      ledgerName: this.ledgerName,
      ledgerAmount: newAmount,
      vatApp: vatApp,
    );
  }
}

class _SalesRegistrationPageState extends State<SalesRegistration>
    with TickerProviderStateMixin {
  bool isDashEnable = true,
      isRolesVisible = true,
      isUserEnable = true,
      isUserVisible = true,
      isRolesEnable = true,
      _isLoading = true,
      isVisibleNoUserFound = false;

  bool _isInitialDataLoaded = false;

  bool isVchEditable = false; // state variable

  TextEditingController _itemController = TextEditingController();
  TextEditingController _partyLedgerController = TextEditingController();

  // UniGas only - Receiver Information shown on the printed Tax Invoice.
  // Same fields as the Delivery Note's Receiver Information (minus EID#) -
  // Name is mandatory before saving, Mobile/Signature are optional.
  final TextEditingController receiverNameController = TextEditingController();
  final TextEditingController receiverMobileController = TextEditingController();
  Uint8List? receiverSignatureBytes;

  String? selectedPartyLedgerPriceLevel;
  String? selectedItemMasterId;

  // Customer mobile/email for the selected party ledger - fetched in
  // loadLedgerData() alongside TRN/address/emirate/country, used by the
  // UniGas POS Tax Invoice PDF format.
  String? _selectedPartyMobile;
  String? _selectedPartyEmail;

  bool isPriceLevelLoading = false;
  bool isRateFieldEnabled = true;
  bool showRateField = true;

  bool isVoucherTypeLocked = false;
  bool isSalesLedgerLocked = false;
  bool isGodownLocked = false;

  String startfrom = '';

  Map<String, String?> partyLedgerPriceLevelMap = {};
  // Party ledger name -> raw "credit_period" text from the backend (e.g.
  // "30 Days", or null when the ledger has none) - used to compute
  // BILLCREDITPERIOD for UniGas's New Ref bill allocation.
  Map<String, String?> partyLedgerCreditPeriodMap = {};

  // --- tally-api migration state -------------------------------------
  //
  // The dropdowns/lists throughout this screen (partyledgerdata,
  // salesledger_data, vatledgerdata, ledgerdata, vchtypenamedata,
  // locationsdata) are all still plain `List<String>`/name-keyed - kept
  // exactly as-is to avoid touching the many widgets that read them.
  // tally-api's voucher-entries write endpoint needs numeric masterIds
  // instead of names, so loadData() additionally populates these
  // name->masterId lookup maps, consulted only when building the
  // create-entry payload (see the submit handler).
  final TallyApiClient _tallyApiClient = TallyApiClient();
  final Map<String, int> _ledgerMasterIdByName = {};
  final Map<String, int> _voucherTypeMasterIdByName = {};
  final Map<String, int> _godownMasterIdByName = {};
  // Every ledger row (name, masterId, tinNumber, address, mobileNumber,
  // email, stateName, countryName, creditPeriod, ...), cached from
  // loadData() so loadLedgerData() (legacy: a separate `getLedger` POST
  // per party selection) can resolve the selected party's contact/TRN
  // details with a local lookup instead of another round trip.
  List<Map<String, dynamic>> _allLedgersCache = [];
  int? _currencyMasterId;

  double ledgerVatAmount = 0,
      itemsVatAmount = 0,
      totalVatAmount = 0,
      totalAmount = 0;

  double totalPriceOfItems = 0,
      totalAmountForVatAppEntries = 0,
      totalAmountOfLedgers = 0;
  final FocusNode _textFieldFocusNodeNarration = FocusNode();

  late AnimationController _animationController;
  late Animation<double> _animation;

  void resetItemDialogFields() {
    _selecteditem = null;
    selectedItemMasterId = null;
    _selectedunit = null;

    _itemController.clear();
    itemQuantityController.clear();
    itemRateController.clear();
    itemAmountController.clear();

    selectedMultiplier = 0.0;
    selectedLocation = '';

    isVisibleLocation = false;
    isVisibleUnit = false;
    isPriceLevelLoading = false;
    isRateFieldEnabled = true;
  }

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
    required List<Color> gradientColors,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.poppins(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      prefixIcon: Container(
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: gradientColors),
          borderRadius: const BorderRadius.all(Radius.circular(8)),
        ),
        child: Icon(icon, color: Colors.white),
      ),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Theme.of(context).dividerColor),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Theme.of(context).dividerColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: app_color, width: 1.5),
      ),
    );
  }

  InputDecoration _currencyDecoration({
    required String label,
    required bool enabled,
  }) {
    return InputDecoration(
      labelText: label,
      filled: !enabled,
      fillColor: !enabled
          ? (Theme.of(context).brightness == Brightness.dark
                ? Theme.of(context).colorScheme.surfaceContainerHighest
                : Colors.grey.shade100)
          : null,
      labelStyle: GoogleFonts.poppins(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: enabled
            ? Theme.of(context).colorScheme.onSurfaceVariant
            : Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      prefix: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: enabled
                ? const [Colors.blue, Colors.blue]
                : const [Colors.grey, Colors.grey],
          ),
          borderRadius: const BorderRadius.all(Radius.circular(8)),
        ),
        child: currencySymbolWidget(
          currencycode,
          getCurrencySymbol(currencycode),
          GoogleFonts.poppins(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Theme.of(context).dividerColor),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Theme.of(context).dividerColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: app_color, width: 1.5),
      ),
    );
  }

  /// `YYYY-MM-DD`, the `z.iso.date()` shape every voucherEntrySchema date
  /// field expects.
  String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// Resolves [unitName] (the display name currently selected on a
  /// [SaleItem]) back to its tally-api unitMasterId, by matching against
  /// the item's own `unit` list (as shaped by
  /// `_shapeStockItemForLegacyItemdata`, each entry carrying a `masterId`).
  int? _findUnitMasterId(List<dynamic> unitJson, String unitName) {
    for (final u in unitJson) {
      if (u is Map && u['name'] == unitName) {
        return u['masterId'] as int?;
      }
    }
    return null;
  }

  /// Parses tally-api's compound "value/unit" price-level rate string (e.g.
  /// "100.00/Nos") into just the numeric value - same shape as batches'
  /// closingRate/openingRate.
  double? _parsePriceLevelRateString(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    return double.tryParse(raw.split('/').first.trim());
  }

  /// Replaces legacy's `GET /api/item/getPriceLevelDetails/:company/:serial`
  /// (which took `date`/`itemId`/`name` and server-side picked the matching
  /// row). `PriceLevelRepository.ratesForItem` only narrows by
  /// `stockMasterId` server-side - the `priceLevelName`/effective-date match
  /// legacy did server-side is replicated here: every row for
  /// [priceLevelName], picking the latest one whose `date` is on/before
  /// [asOf] (Tally price-lists are effective-dated, so a later price
  /// shouldn't apply to an earlier voucher date). Returns null when there's
  /// no price level, or no row for this item/level/date - same "clear the
  /// rate field" outcome the empty-list legacy response produced.
  Future<double?> _priceLevelRate({
    required int stockItemMasterId,
    required String priceLevelName,
    required DateTime asOf,
  }) async {
    final rows = await PriceLevelRepository.instance.ratesForItem(
      stockItemMasterId,
    );
    Map<String, dynamic>? best;
    DateTime? bestDate;
    for (final row in rows) {
      if (row['priceLevelName'] != priceLevelName) continue;
      final rowDate = DateTime.tryParse(row['date']?.toString() ?? '');
      if (rowDate == null || rowDate.isAfter(asOf)) continue;
      if (bestDate == null || rowDate.isAfter(bestDate)) {
        bestDate = rowDate;
        best = row;
      }
    }
    if (best == null) return null;
    return _parsePriceLevelRateString(best['rate']?.toString());
  }

  Future<void> fetchPriceLevelDetailsForSelectedItem(
    StateSetter setStateDialog,
  ) async {
    if (serial_no == null ||
        serial_no!.trim().isEmpty ||
        !vanSalesSerialNo.contains(serial_no!.trim())) {
      return;
    }

    if (selectedItemMasterId == null || selectedItemMasterId!.trim().isEmpty) {
      debugPrint(
        'Price level API skipped: selected item masterid is null/empty',
      );
      return;
    }

    if (selectedPartyLedgerPriceLevel == null ||
        selectedPartyLedgerPriceLevel.toString().trim().isEmpty) {
      setStateDialog(() {
        isRateFieldEnabled = true;
        showRateField = true;
      });
      return;
    }

    setStateDialog(() {
      isPriceLevelLoading = true;
    });

    try {
      final DateTime selectedDate = saledatestring.isNotEmpty
          ? parseCompactDate(saledatestring)
          : DateTime.now();

      final int? itemMasterId = int.tryParse(selectedItemMasterId!);
      final double? apiRate = itemMasterId == null
          ? null
          : await _priceLevelRate(
              stockItemMasterId: itemMasterId,
              priceLevelName: selectedPartyLedgerPriceLevel!,
              asOf: selectedDate,
            );

      if (apiRate != null) {
        final double qty =
            double.tryParse(
              itemQuantityController.text.trim().isEmpty
                  ? '1'
                  : itemQuantityController.text.trim(),
            ) ??
            1.0;

        final double amount = apiRate * qty;

        setStateDialog(() {
          itemRateController.text = apiRate.toStringAsFixed(decimal ?? 2);
          itemAmountController.text = amount.toStringAsFixed(decimal ?? 2);
          isRateFieldEnabled = false;
          showRateField = true;
        });
      } else {
        setStateDialog(() {
          itemRateController.clear();
          itemAmountController.clear();
          isRateFieldEnabled = true;
          showRateField = true;
        });
      }
    } catch (e) {
      setStateDialog(() {
        isRateFieldEnabled = true;
        showRateField = true;
      });
    } finally {
      setStateDialog(() {
        isPriceLevelLoading = false;
      });
    }
  }

  void _deleteLedger(int index) {
    setState(() {
      ledgerEntries.removeAt(index);

      // Calculate the total amount for VAT-applicable entries
      totalAmountForVatAppEntries = ledgerEntries
          .where((entry) => entry.vatApp)
          .fold(0.0, (double previousAmount, LedgerEntry entry) {
            return previousAmount + entry.ledgerAmount;
          });

      // Calculate the total amount of ledgers
      totalAmountOfLedgers = ledgerEntries.fold(0.0, (
        double previousAmount,
        LedgerEntry entry,
      ) {
        return previousAmount + entry.ledgerAmount;
      });

      // Calculate VAT if applicable
      if (_selectedvatledger != 'Not Applicable') {
        double vatPerc = vatperc / 100;
        ledgerVatAmount = totalAmountForVatAppEntries * vatPerc;

        totalVatAmount = itemsVatAmount + ledgerVatAmount;
        roundedtotalVatAmount = double.parse(
          totalVatAmount.toStringAsFixed(decimal!),
        );
        NumberFormat formatter = NumberFormat(
          '#,##0.${'0' * decimal!}',
          'en_US',
        );
        String formattedVat = formatter.format(roundedtotalVatAmount);
        controller_vatamt.text = formattedVat.toString();
      } else {
        totalVatAmount = 0;
        roundedtotalVatAmount = double.parse(
          totalVatAmount.toStringAsFixed(decimal!),
        );
        NumberFormat formatter = NumberFormat(
          '#,##0.${'0' * decimal!}',
          'en_US',
        );
        String formattedVat = formatter.format(roundedtotalVatAmount);
        controller_vatamt.text = formattedVat.toString();
      }

      // Calculate the total amount
      totalAmount = totalPriceOfItems + totalAmountOfLedgers + totalVatAmount;
      roundedtotalAmount = double.parse(totalAmount.toStringAsFixed(decimal!));
      NumberFormat formatter = NumberFormat('#,##0.${'0' * decimal!}', 'en_US');
      String formattedTotal = formatter.format(roundedtotalAmount);
      controller_totalamt.text = formattedTotal.toString();

      isVisibleLedgerHeading = ledgerEntries.isNotEmpty;
    });
  }

  void _deleteSaleItem(int index) {
    setState(() {
      saleItems.removeAt(index);

      // Calculate the total price of items
      totalPriceOfItems = saleItems.fold(0.0, (
        double previousAmount,
        SaleItem item,
      ) {
        return previousAmount +
            (double.parse(item.itemPrice.toStringAsFixed(decimal!)) *
                double.parse(item.itemQuantity));
      });

      if (_selectedvatledger != 'Not Applicable') {
        double vat_perc = vatperc / 100;
        itemsVatAmount = double.parse(
          (totalPriceOfItems * vat_perc).toStringAsFixed(decimal!),
        );
        totalVatAmount = itemsVatAmount + ledgerVatAmount;
        roundedtotalVatAmount = double.parse(
          totalVatAmount.toStringAsFixed(decimal!),
        );
        NumberFormat formatter = NumberFormat(
          '#,##0.${'0' * decimal!}',
          'en_US',
        );
        String formattedVat = formatter.format(roundedtotalVatAmount);
        controller_vatamt.text = formattedVat.toString();
      } else {
        totalVatAmount = 0;
        roundedtotalVatAmount = double.parse(
          totalVatAmount.toStringAsFixed(decimal!),
        );
        NumberFormat formatter = NumberFormat(
          '#,##0.${'0' * decimal!}',
          'en_US',
        );
        String formattedVat = formatter.format(roundedtotalVatAmount);
        controller_vatamt.text = formattedVat.toString();
      }

      totalAmountOfLedgers = ledgerEntries.fold(0.0, (
        double previousAmount,
        LedgerEntry entry,
      ) {
        return previousAmount + entry.ledgerAmount;
      });
      totalAmount = totalPriceOfItems + totalAmountOfLedgers + totalVatAmount;
      roundedtotalAmount = double.parse(totalAmount.toStringAsFixed(decimal!));
      NumberFormat formatter = NumberFormat('#,##0.${'0' * decimal!}', 'en_US');
      String formattedTotal = formatter.format(roundedtotalAmount);
      controller_totalamt.text = formattedTotal.toString();

      isVisibleItemHeading = saleItems.isNotEmpty;
    });
  }

  String formatitemKey(int key) {
    key++;
    String keyy = key.toString();
    return keyy;
  }

  String convertAmountToWords(num amount) {
    if (amount == null) return "Invalid input";

    List<String> units = [
      '',
      'One',
      'Two',
      'Three',
      'Four',
      'Five',
      'Six',
      'Seven',
      'Eight',
      'Nine',
    ];
    List<String> teens = [
      'Ten',
      'Eleven',
      'Twelve',
      'Thirteen',
      'Fourteen',
      'Fifteen',
      'Sixteen',
      'Seventeen',
      'Eighteen',
      'Nineteen',
    ];
    List<String> tens = [
      '',
      '',
      'Twenty',
      'Thirty',
      'Forty',
      'Fifty',
      'Sixty',
      'Seventy',
      'Eighty',
      'Ninety',
    ];

    NumberFormat formatter = NumberFormat.decimalPatternDigits(
      locale: 'en_us',
      decimalDigits: decimal,
    );
    String formattedAmount = formatter.format(amount);

    int integerPart = amount.toInt();
    String decimalPartStr = formattedAmount.split('.')[1] ?? "0";
    int decimalPart = int.parse(decimalPartStr);

    String currencyWords = getCurrencyWords(currencycode);
    String fractionalUnit = getFractionalUnit(currencycode);

    String integerWords = convertIntegerToWords(
      units,
      teens,
      tens,
      integerPart,
    );
    String result = '$currencyWords $integerWords';

    if (decimalPart > 0) {
      String decimalWords = convertIntegerToWords(
        units,
        teens,
        tens,
        decimalPart,
      );
      result += ' and $decimalWords $fractionalUnit Only';
    } else {
      result += ' Only';
    }

    return result;
  }

  String getCurrencyWords(String currencyCode) {
    switch (currencyCode.toLowerCase()) {
      case 'aed':
        return 'UAE dirham';
      case 'usd':
        return 'US dollar';
      case 'inr':
        return 'Indian rupee';
      case 'pkr':
        return 'Pakistani rupee';
      case 'eur':
        return 'Euro';
      case 'lkr':
        return 'Sri Lankan rupee';
      case 'sar':
        return 'Saudi riyal';
      case 'omr':
        return 'Omani rial';
      case 'bhd':
        return 'Bahraini dinar';
      case 'qar':
        return 'Qatari riyal';
      case 'kwd':
        return 'Kuwaiti dinar';
      case 'sle':
        return 'Sierra Leonean leone';
      default:
        return '';
    }
  }

  String getFractionalUnit(String currencyCode) {
    switch (currencyCode.toLowerCase()) {
      case 'aed':
        return 'fils';
      case 'usd':
        return 'cents';
      case 'inr':
        return 'paise';
      case 'pkr':
        return 'paisa';
      case 'eur':
        return 'cents';
      case 'lkr':
        return 'cents';
      case 'sar':
        return 'halala';
      case 'omr':
        return 'baisa';
      case 'bhd':
        return 'fils';
      case 'qar':
        return 'dirham';
      case 'kwd':
        return 'fils';
      case 'sle':
        return 'cents';
      default:
        return '';
    }
  }

  String convertIntegerToWords(
    List<String> units,
    List<String> teens,
    List<String> tens,
    int amount,
  ) {
    if (amount == 0) return 'zero';

    String words = '';

    if (amount >= 1000000000) {
      words +=
          '${convertIntegerToWords(units, teens, tens, amount ~/ 1000000000)} billion ';
      amount %= 1000000000;
    }

    if (amount >= 1000000) {
      words +=
          '${convertIntegerToWords(units, teens, tens, amount ~/ 1000000)} million ';
      amount %= 1000000;
    }

    if (amount >= 1000) {
      words +=
          '${convertIntegerToWords(units, teens, tens, amount ~/ 1000)} thousand ';
      amount %= 1000;
    }

    if (amount >= 100) {
      words += '${units[amount ~/ 100]} hundred ';
      amount %= 100;
    }

    if (amount >= 10 && amount < 20) {
      words += '${teens[amount - 10]}';
      return words;
    } else if (amount >= 20) {
      words += '${tens[amount ~/ 10]}';
      if (amount % 10 != 0) words += ' ';
      amount %= 10;
    }
    if (amount > 0) {
      words += '${units[amount]}';
    }
    return words.trim();
  }

  Map<String, dynamic> jsonEntryData = {
    "DATE": "",
    "VOUCHERTYPENAME": "",
    "PARTYLEDGERNAME": "",
    "NARRATION": "",
    "VOUCHERNUMBER": "",
    "REFERENCE": "",
    "REFERENCEDATE": "",
    "INVENTORYENTRIES.LIST": [],
    "LEDGERENTRIES.LIST": [],
  };

  bool isVisibleItemHeading = false, isVisibleLedgerHeading = false;

  bool isVisibleUnit = true;

  final _formKey = GlobalKey<FormState>();

  bool isVisibleLocation = false;

  GlobalKey<FormState> _itemFormkey = GlobalKey<FormState>();

  double roundedtotalVatAmount = 0.0;

  double roundedtotalAmount = 0.0;

  GlobalKey<FormState> _ledgerFormkey = GlobalKey<FormState>();

  List<String> salesledger_data = [];

  int? decimal = 2;
  late List<String> vchtypenamedata = [];
  late List<String> partyledgerdata = [];
  late List<String> vatledgerdata = [];

  List<dynamic> itemdata = [];
  double vatperc = 0.0;

  List<String> locationsdata = []; // Store the locations here
  late String selectedLocation = ''; // Store the selected location here

  List<Unit> unitdata = [];

  List<Map<String, dynamic>> ledgerdata = [];

  String user_email_fetched = "", token = '';

  String name = "",
      email = "",
      saledatestring = '',
      saledatetxt = '',
      refdatestring = '',
      refdatetxt = '';

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  late GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey;

  late SharedPreferences prefs;

  dynamic _selectedledger,
      _selecteditem,
      _selectedunit,
      _selectedsalesledger,
      _selectedvchtypename,
      _selectedpartyledger,
      _selectedvatledger;

  late final TextEditingController controller_narration =
      TextEditingController();
  late final TextEditingController controller_vatamt = TextEditingController();
  late final TextEditingController controller_totalamt =
      TextEditingController();

  String formatAmountInvoice(String amount) {
    int? decimal = prefs?.getInt('decimalplace') ?? 2;

    if (amount == "null" || amount.isEmpty) {
      amount = "0";
    }
    double amount_double = double.parse(amount);

    NumberFormat formatter = NumberFormat.decimalPatternDigits(
      locale: 'en_us',
      decimalDigits: decimal,
    );
    String formattedAmount = formatter.format(amount_double);

    return formattedAmount;
  }

  bool _isFocused_vchno = false,
      _isFocused_item = false,
      _isFocused_unit = false,
      _isFocused_ledger = false,
      _isFocused_narration = false,
      _isFocused_vatamt = false,
      _isFocused_totalamt = false,
      _isFocused_refno = false;

  String? hostname = "",
      company = "",
      company_lowercase = "",
      serial_no = "",
      username = "",
      HttpURL = "",
      SecuritybtnAcessHolder = "";

  late DateTime saledate, refdate;
  // The legacy HttpURL_loadData/loadLedgerData/fetchvchnos/salesEntry
  // fields (and their `_initSharedPreferences()` assignments) were removed
  // as part of the tally-api migration - every call site now goes through
  // lib/api/ repositories instead of a hand-built legacy URL.
  List<String> vchnos = [];

  double selectedMultiplier = 0.0;

  final DateFormat _dateFormat = DateFormat('yyyyMMdd');

  List<SaleItem> saleItems = [];
  List<LedgerEntry> ledgerEntries = [];
  String currencycode = '';

  final TextEditingController itemQuantityController = TextEditingController();
  final TextEditingController itemRateController = TextEditingController();
  final TextEditingController itemAmountController = TextEditingController();
  // UniGas-only free-text "Basic User Description" boxes for the
  // single-item add flow (see SaleItem.basicUserDescriptions) - one
  // single-line controller per box, "+" adds another.
  List<TextEditingController> itemDescriptionControllers = [
    TextEditingController(),
  ];
  final TextEditingController ledgerAmountController = TextEditingController();
  final TextEditingController _dateController = TextEditingController();
  final TextEditingController controller_refno = TextEditingController();
  final TextEditingController _refdateController = TextEditingController();

  final TextEditingController _vchnoController = TextEditingController();
  String errorMessageVchNo = '';
  int? unitValue;

  late DateTime now = DateTime.now();

  // Current year start date
  late DateTime yearStartDate = DateTime(now.year, 1, 1);

  // Current year end date
  late DateTime yearEndDate = DateTime(now.year, 12, 31);

  Future<void> _selectDateRangeVchNo(BuildContext context) async {
    final initialDateRange = DateTimeRange(
      start: yearStartDate,
      end: yearEndDate,
    );

    DateTimeRange? selectedDateRange = await showDateRangePicker(
      context: context,
      initialDateRange: initialDateRange,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
      builder: (BuildContext context, Widget? child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: app_color, // main accent color
              onPrimary: Colors.white,
              surface: Theme.of(context).colorScheme.surface,
              onSurface: Theme.of(context).colorScheme.onSurface,
            ),
            datePickerTheme: DatePickerThemeData(
              rangeSelectionBackgroundColor: app_color.withOpacity(
                0.15,
              ), // 🔹 light shade of your app_color
              rangeSelectionOverlayColor: MaterialStatePropertyAll(
                app_color.withOpacity(0.15),
              ),
            ),
          ),
          child: child!,
        );
      },
    );

    if (selectedDateRange != null && selectedDateRange != initialDateRange) {
      setState(() {
        yearStartDate = selectedDateRange.start;
        yearEndDate = selectedDateRange.end;
      });

      fetchvchnos(_selectedvchtypename);
    }
  }

  void checkVchNoExistence(String vchNo) {
    if (vchNo.isEmpty || vchNo == '') {
      setState(() {
        errorMessageVchNo = 'Voucher No. cannot be empty';
      });
    } else {
      if (vchnos.contains(vchNo)) {
        setState(() {
          errorMessageVchNo =
              'Voucher no: $vchNo against $_selectedvchtypename already exists';
        });
      } else {
        setState(() {
          errorMessageVchNo = '';
        });
      }
    }
  }

  String generateNextVchNo(List<String> vchnos) {
    if (vchnos.isEmpty) return "1";

    Map<String, List<Map<String, dynamic>>> patternGroups = {};

    for (String vch in vchnos) {
      List<RegExpMatch> matches = RegExp(r'\d+').allMatches(vch).toList();

      if (matches.isNotEmpty) {
        RegExpMatch selectedMatch = matches.last;

        // 🔥 Ignore year like 2026
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

    // ✅ Dominant pattern
    String selectedPattern = patternGroups.entries
        .reduce((a, b) => a.value.length > b.value.length ? a : b)
        .key;

    List<Map<String, dynamic>> selectedList = patternGroups[selectedPattern]!;

    // 🔥 STEP 1: Extract & sort numbers
    List<int> numbers = selectedList.map((e) => e["number"] as int).toList();
    numbers = numbers.toSet().toList();

    numbers.sort();

    int length = selectedList.first["length"];

    // 🔥 STEP 2: Find missing number (gap)
    int expected = numbers.first;

    int nextNumber = numbers.last + 1; // fallback

    for (int num in numbers) {
      if (num != expected) {
        nextNumber = expected;
        break;
      }
      expected++;
    }

    // 🔥 STEP 3: Format number
    String newNumber = nextNumber.toString().padLeft(length, '0');

    // reconstruct
    List<String> parts = selectedPattern.split("#");
    String prefix = parts[0];
    String suffix = parts[1];

    return prefix + newNumber + suffix;
  }

  double _estimateInvoiceLastRowFillerPadding(int itemCount) {
    // Calibrated against actual rendered output on an A4 page (same
    // technique as the Delivery Note PDF), re-measured after the header
    // was compacted (logo moved to the top-left corner instead of a
    // standalone 110pt-tall centered block). With the shorter header, a
    // single item's content now ends ~557pt from the top with no filler,
    // so there's real room to stretch the last row down to fill the page.
    const double targetContentEnd = 700.0;
    const double baselineForOneItem = 557.4;
    const double perItemHeight = 33.0;

    final double baseline =
        baselineForOneItem + (itemCount - 1) * perItemHeight;
    final double remaining = targetContentEnd - baseline;
    return remaining.clamp(5.0, 260.0);
  }

  Future<void> generateInvoicePDF(
    String trn,
    String address,
    String emirate,
    String country,
  ) async {
    // UniGas uses a completely separate POS Tax Invoice format (the old
    // A4-style layout is retired for this serial type) - see
    // _generateUniGasTaxInvoicePDF.
    if (isUniGasSerial) {
      await _generateUniGasTaxInvoicePDF(trn, address, emirate, country);
      return;
    }

    final pdf = pw.Document();

    // BigInt, not int - a manually-typed quantity can run past int64 range
    // and int.parse() throws FormatException on that instead of silently
    // erroring, crashing PDF generation outright.
    BigInt totalQuantity = BigInt.zero;
    double totalitemAmount = 0;
    for (var item in saleItems) {
      String qty = item.itemQuantity;
      BigInt qty_int = BigInt.parse(qty);
      totalQuantity += qty_int;

      totalitemAmount += double.parse(
        item.itemAmount.toStringAsFixed(decimal!),
      );
    }

    pw.MemoryImage? uniGasLogo;
    if (isUniGasSerial) {
      final logoBytes = await rootBundle.load("assets/uigas-logo.jpeg");
      uniGasLogo = pw.MemoryImage(logoBytes.buffer.asUint8List());
    }

    pdf.addPage(
      pw.MultiPage(
        footer: (pw.Context context) {
          return pw.Container(
            padding: pw.EdgeInsets.fromLTRB(5, 5, 5, 5),
            alignment: pw.Alignment.center,
            child: pw.Text(
              'Created in Fincore Go',
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                fontSize: 10,
                color: PdfColor.fromInt(0xFFCCCCCC),
              ),
            ),
          );
        },
        build: (pw.Context context) {
          return [
            // Logo is pinned to the top-left corner, sitting directly
            // above the details table's left edge - independent of the
            // "Tax Invoice" heading, which stays centered on its own.
            // A Stack keeps both compact (~50pt tall) instead of the old
            // standalone centered 110pt-tall logo stacked above the text.
            if (uniGasLogo != null)
              pw.SizedBox(
                height: 50,
                child: pw.Stack(
                  children: [
                    pw.Positioned(
                      left: 0,
                      top: 0,
                      child: pw.Image(uniGasLogo, height: 50),
                    ),
                    pw.Positioned.fill(
                      child: pw.Center(
                        child: pw.Text(
                          'Tax Invoice',
                          textAlign: pw.TextAlign.center,
                          style: pw.TextStyle(fontSize: 18),
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              pw.Header(
                level: 0,
                decoration: pw.BoxDecoration(
                  border: pw.Border(bottom: pw.BorderSide.none),
                ),

                child: pw.Center(
                  child: pw.Text(
                    'Tax Invoice',
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(fontSize: 18),
                  ),
                ),
              ),
            pw.SizedBox(height: 5),

            pw.Container(
              decoration: pw.BoxDecoration(
                border: pw.Border(
                  right: pw.BorderSide(width: 1.0),
                  top: pw.BorderSide(width: 1.0),
                  left: pw.BorderSide(width: 1.0),
                  bottom: pw.BorderSide(width: 1.0),
                ),
              ),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                mainAxisAlignment: pw.MainAxisAlignment.start,
                children: [
                  // Left column
                  pw.Expanded(
                    flex: 1,
                    child: pw.Container(
                      padding: pw.EdgeInsets.only(
                        left: 5,
                        top: 2,
                        bottom: 2,
                        right: 5,
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        mainAxisAlignment: pw.MainAxisAlignment.start,
                        children: [
                          pw.Text(company!),

                          if (company_address != "null" ||
                              company_address != "Not Available")
                            pw.Column(
                              children: [
                                pw.SizedBox(height: 2),

                                pw.Text(company_address),
                              ],
                            ),

                          if (company_emirate != "null" ||
                              company_emirate != "Not Available")
                            pw.Column(
                              children: [
                                pw.SizedBox(height: 2),

                                pw.Row(
                                  children: [
                                    pw.Text("Emirate "),

                                    pw.SizedBox(width: 20),
                                    pw.Text(company_emirate),
                                  ],
                                ),
                              ],
                            ),

                          if (company_country != "null" ||
                              company_country != "Not Available")
                            pw.Column(
                              children: [
                                pw.SizedBox(height: 2),

                                pw.Row(
                                  children: [
                                    pw.Text("Country "),

                                    pw.SizedBox(width: 20),
                                    pw.Text(company_country),
                                  ],
                                ),
                              ],
                            ),

                          if (company_trn != "null" ||
                              company_trn != "Not Available")
                            pw.Column(
                              children: [
                                pw.SizedBox(height: 2),

                                pw.Row(
                                  children: [
                                    pw.Text("TRN "),

                                    pw.SizedBox(width: 35),
                                    pw.Text(company_trn),
                                  ],
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),

                  // Right column
                  pw.Expanded(
                    flex: 1,
                    child: pw.Container(
                      decoration: pw.BoxDecoration(
                        border: pw.Border(
                          right: pw.BorderSide(width: 1.0),
                          top: pw.BorderSide(width: 1.0),

                          bottom: pw.BorderSide(width: 1.0),
                          left: pw.BorderSide(width: 1.0),
                        ),
                      ),

                      child: pw.Column(
                        children: [
                          // first row right column
                          pw.Container(
                            decoration: pw.BoxDecoration(
                              border: pw.Border.all(width: 1),
                            ),
                            child: pw.Row(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              mainAxisAlignment: pw.MainAxisAlignment.start,
                              children: [
                                // invoice no
                                pw.Expanded(
                                  child: pw.Container(
                                    decoration: pw.BoxDecoration(
                                      border: pw.Border(
                                        right: pw.BorderSide(width: 1),
                                      ),
                                    ),
                                    padding: pw.EdgeInsets.only(
                                      left: 5,
                                      top: 5,
                                      bottom: 5,
                                      right: 5,
                                    ),

                                    child: pw.Column(
                                      crossAxisAlignment:
                                          pw.CrossAxisAlignment.start,
                                      mainAxisAlignment:
                                          pw.MainAxisAlignment.start,
                                      children: [
                                        pw.Text('Invoice No:'),
                                        pw.SizedBox(height: 2),
                                        pw.Text(_vchnoController.text),
                                      ],
                                    ),
                                  ),
                                ),

                                pw.Expanded(
                                  child: pw.Container(
                                    decoration: pw.BoxDecoration(
                                      border: pw.Border(
                                        left: pw.BorderSide(width: 1),
                                      ),
                                    ),
                                    padding: pw.EdgeInsets.only(
                                      left: 5,
                                      top: 5,
                                      bottom: 5,
                                      right: 5,
                                    ),
                                    child: pw.Column(
                                      crossAxisAlignment:
                                          pw.CrossAxisAlignment.start,
                                      mainAxisAlignment:
                                          pw.MainAxisAlignment.start,
                                      children: [
                                        pw.Text('Dated:'),
                                        pw.SizedBox(height: 2),
                                        pw.Text(
                                          formatlastsaledate(saledatestring),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          //second row right column
                          pw.Container(
                            decoration: pw.BoxDecoration(
                              border: pw.Border.all(width: 1),
                            ),
                            child: pw.Row(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              mainAxisAlignment: pw.MainAxisAlignment.start,
                              children: [
                                pw.Expanded(
                                  child: pw.Container(
                                    decoration: pw.BoxDecoration(
                                      border: pw.Border(
                                        right: pw.BorderSide(width: 1),
                                      ),
                                    ),
                                    padding: pw.EdgeInsets.only(
                                      left: 5,
                                      top: 5,
                                      bottom: 5,
                                      right: 5,
                                    ),

                                    child: pw.Column(
                                      crossAxisAlignment:
                                          pw.CrossAxisAlignment.start,
                                      mainAxisAlignment:
                                          pw.MainAxisAlignment.start,

                                      children: [
                                        pw.Text('Reference No:'),
                                        pw.SizedBox(height: 2),
                                        pw.Text(controller_refno.text),
                                      ],
                                    ),
                                  ),
                                ),

                                pw.Expanded(
                                  child: pw.Container(
                                    decoration: pw.BoxDecoration(
                                      border: pw.Border(
                                        left: pw.BorderSide(width: 1),
                                      ),
                                    ),
                                    padding: pw.EdgeInsets.only(
                                      left: 5,
                                      top: 5,
                                      bottom: 5,
                                      right: 5,
                                    ),
                                    child: pw.Column(
                                      crossAxisAlignment:
                                          pw.CrossAxisAlignment.start,
                                      mainAxisAlignment:
                                          pw.MainAxisAlignment.start,
                                      children: [
                                        pw.Text('Reference Date:'),
                                        pw.SizedBox(height: 2),
                                        pw.Text(
                                          formatlastsaledate(refdatestring),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // third row right column
                          pw.Container(
                            decoration: pw.BoxDecoration(
                              border: pw.Border(
                                top: pw.BorderSide(width: 1),
                                left: pw.BorderSide(width: 1),
                              ),
                            ),
                            child: pw.Row(
                              children: [
                                pw.Expanded(
                                  child: pw.Container(
                                    padding: pw.EdgeInsets.only(
                                      left: 5,
                                      top: 5,
                                      bottom: 5,
                                      right: 5,
                                    ),

                                    child: pw.Column(
                                      crossAxisAlignment:
                                          pw.CrossAxisAlignment.start,
                                      children: [
                                        pw.Text('Remarks:'),
                                        pw.SizedBox(height: 2),
                                        pw.Text(controller_narration.text),
                                      ],
                                    ),
                                  ),
                                ),

                                /* pw.Expanded(child: pw.Container(
                                            decoration: pw.BoxDecoration(
                                              border: pw.Border(left: pw.BorderSide(width: 1)
                                              ),
                                            ),
                                            padding: pw.EdgeInsets.only(left: 5,top: 5,bottom: 25,right: 5),
                                            child: pw.Column(
                                                crossAxisAlignment: pw.CrossAxisAlignment.start,
                                                children: [

                                                  pw.Text('Other Reference(s)'),

                                                ]


                                            )
                                        ),)*/
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            pw.Container(
              decoration: pw.BoxDecoration(
                border: pw.Border(
                  right: pw.BorderSide(width: 1.0),

                  left: pw.BorderSide(width: 1.0),
                  bottom: pw.BorderSide(width: 1.0),
                ),
              ),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                mainAxisAlignment: pw.MainAxisAlignment.start,
                children: [
                  // Left column
                  pw.Expanded(
                    flex: 1,
                    child: pw.Container(
                      padding: pw.EdgeInsets.only(
                        left: 5,
                        top: 2,
                        bottom: 2,
                        right: 5,
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        mainAxisAlignment: pw.MainAxisAlignment.start,
                        children: [
                          pw.Text("Buyer's Name"),

                          pw.Column(
                            children: [
                              pw.SizedBox(height: 2),

                              pw.Text(
                                _selectedpartyledger!,
                                style: pw.TextStyle(
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                            ],
                          ),

                          if (address != "null")
                            pw.Column(
                              children: [
                                pw.SizedBox(height: 2),

                                pw.Text(address),
                              ],
                            ),

                          if (emirate != "null")
                            pw.Column(
                              children: [
                                pw.SizedBox(height: 2),

                                pw.Row(
                                  children: [
                                    pw.Text("Emirate "),

                                    pw.SizedBox(width: 20),
                                    pw.Text(emirate),
                                  ],
                                ),
                              ],
                            ),

                          if (country != "null")
                            pw.Column(
                              children: [
                                pw.SizedBox(height: 2),

                                pw.Row(
                                  children: [
                                    pw.Text("Country "),

                                    pw.SizedBox(width: 20),
                                    pw.Text(country),
                                  ],
                                ),
                              ],
                            ),

                          if (trn != "null")
                            pw.Column(
                              children: [
                                pw.SizedBox(height: 2),

                                pw.Row(
                                  children: [
                                    pw.Text("TRN "),

                                    pw.SizedBox(width: 35),
                                    pw.Text(trn),
                                  ],
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                  // Right column
                  /*pw.Expanded(
                      flex: 1,
                      child: pw.Container(
                          decoration: pw.BoxDecoration(
                            border: pw.Border(
                              right: pw.BorderSide(
                                  width: 1.0
                              ),
                              top: pw.BorderSide(
                                  width: 1.0
                              ),

                              bottom: pw.BorderSide(
                                  width: 1.0
                              ),
                              left:pw.BorderSide(
                                  width: 1.0
                              ), ),
                          ),

                          child: pw.Column(
                              children: [
                                // first row right column

                                pw.Container(
                                  decoration: pw.BoxDecoration(
                                    border: pw.Border.all(width: 1

                                    ),
                                  ),
                                  child: pw.Row(

                                      children: [


                                        // invoice no
                                        pw.Expanded(child: pw.Container(
                                            decoration: pw.BoxDecoration(
                                              border: pw.Border(right: pw.BorderSide(width: 1)
                                              ),
                                            ),
                                            padding: pw.EdgeInsets.only(left: 5,top: 5,bottom: 5,right: 5),

                                            child: pw.Column(
                                                crossAxisAlignment: pw.CrossAxisAlignment.start,
                                                children: [

                                                  pw.Text('Buyers Order No.'),
                                                ]
                                            ))
                                        ),

                                        pw.Expanded(child: pw.Container(
                                            padding: pw.EdgeInsets.only(left: 5,top: 5,bottom: 5,right: 5),
                                            child: pw.Column(
                                                crossAxisAlignment: pw.CrossAxisAlignment.start,
                                                children: [
                                                  pw.Text('Dated:'),
                                                ]
                                            )
                                        ),)
                                      ]
                                  ),
                                ),

                                //second row right column
                                pw.Container(
                                  decoration: pw.BoxDecoration(
                                    border: pw.Border.all(width: 1
                                    ),
                                  ),
                                  child: pw.Row(
                                      children: [
                                        pw.Expanded(child: pw.Container(
                                            padding: pw.EdgeInsets.only(left: 5,top: 5,bottom: 5,right: 5),
                                            decoration: pw.BoxDecoration(
                                              border: pw.Border(right: pw.BorderSide(width: 1)
                                              ),
                                            ),
                                            child: pw.Column(
                                                crossAxisAlignment: pw.CrossAxisAlignment.start,
                                                children: [

                                                  pw.Text('Dispatch Document No.'),

                                                ]


                                            ))
                                        ),



                                        pw.Expanded(child: pw.Container(

                                            padding: pw.EdgeInsets.only(left: 5,top: 5,bottom: 5,right: 5),
                                            child: pw.Column(
                                                crossAxisAlignment: pw.CrossAxisAlignment.start,
                                                mainAxisAlignment: pw.MainAxisAlignment.start,
                                                children: [

                                                  pw.Text('Delivery Note Date.'),
                                                  pw.Text(''),
                                                ]


                                            )
                                        ),)

                                      ]
                                  ),
                                ),

                                // third row right column

                                pw.Container(
                                  decoration: pw.BoxDecoration(
                                    border: pw.Border.all(width: 1

                                    ),
                                  ),
                                  child: pw.Row(

                                      children: [


                                        pw.Expanded(child: pw.Container(

                                            padding: pw.EdgeInsets.only(left: 5,top: 5,bottom: 25,right: 5),

                                            child: pw.Column(
                                                crossAxisAlignment: pw.CrossAxisAlignment.start,
                                                children: [

                                                  pw.Text('Dispatched through.'),

                                                ]



                                            ))
                                        ),



                                        pw.Expanded(child: pw.Container(
                                            decoration: pw.BoxDecoration(
                                              border: pw.Border(left: pw.BorderSide(width: 1)
                                              ),
                                            ),
                                            padding: pw.EdgeInsets.only(left: 5,top: 5,bottom: 25,right: 5),
                                            child: pw.Column(
                                                crossAxisAlignment: pw.CrossAxisAlignment.start,
                                                children: [

                                                  pw.Text('Destination'),

                                                ]


                                            )
                                        ),)

                                      ]
                                  ),
                                ),
                              ]
                          )
                      ),),*/
                ],
              ),
            ),

            /*pw.Container(
                decoration: pw.BoxDecoration(
                  border: pw.Border(
                      right: pw.BorderSide(
                          width: 1.0
                      ),

                      left: pw.BorderSide(
                          width: 1.0
                      ),
                      bottom: pw.BorderSide(
                          width: 1.0
                      )),
                ),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  mainAxisAlignment: pw.MainAxisAlignment.start,
                  children: [
                    // Left column
                    pw.Expanded(
                        flex: 1,
                        child: pw.Container(
                          decoration: pw.BoxDecoration(
                            border: pw.Border(
                              right: pw.BorderSide(
                                  width: 1.0
                              ),
                            ),
                          ),
                          padding: pw.EdgeInsets.only(left: 5,top: 2,bottom: 10,right: 5),
                          child: pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              mainAxisAlignment: pw.MainAxisAlignment.start,
                              children: [
                                pw.Text('Buyer'),
                                pw.Text(_selectedpartyledger!),
                              ]
                          ),)),

                    // Right column
                    pw.Expanded(
                      flex: 1,
                      child: pw.Container(
                          child: pw.Expanded(child: pw.Container(
                              decoration: pw.BoxDecoration(
                                border: pw.Border(right: pw.BorderSide(width: 1)
                                ),
                              ),
                              padding: pw.EdgeInsets.only(left: 5,top: 2,bottom: 20,right: 5),
                              child: pw.Column(
                                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                                  children: [
                                    pw.Text('Buyers Order No.'),
                                  ]
                              ))
                          ),
                      ),),
                  ],
                ),
              ),*/
            pw.Container(
              decoration: pw.BoxDecoration(
                border: pw.Border(
                  right: pw.BorderSide(width: 1.0),
                  left: pw.BorderSide(width: 1.0),
                  bottom: pw.BorderSide(width: 1.0),
                ),
              ),
              child: pw.Column(
                mainAxisSize: pw.MainAxisSize.min,
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                mainAxisAlignment: pw.MainAxisAlignment.start,
                children: [
                  pw.Row(
                    children: [
                      pw.Expanded(
                        flex: 1,
                        child: pw.Container(
                          padding: pw.EdgeInsets.fromLTRB(
                            5,
                            5,
                            5,
                            5,
                          ), // Left, Top, Right, Bottom
                          alignment: pw.Alignment.center,
                          decoration: pw.BoxDecoration(
                            border: pw.Border(
                              right: pw.BorderSide(width: 1.0),
                              bottom: pw.BorderSide(width: 1.0),
                            ),
                          ),
                          child: pw.Text(
                            'Sr No.',
                            style: pw.TextStyle(fontSize: 10),
                          ),
                        ),
                      ),
                      pw.Expanded(
                        flex: 3,
                        child: pw.Container(
                          padding: pw.EdgeInsets.fromLTRB(5, 5, 5, 5),
                          alignment: pw.Alignment.center,
                          decoration: pw.BoxDecoration(
                            border: pw.Border(
                              right: pw.BorderSide(width: 1.0),
                              bottom: pw.BorderSide(width: 1.0),
                            ),
                          ),
                          child: pw.Text(
                            'Description of Goods/Services',
                            style: pw.TextStyle(fontSize: 10),
                          ),
                        ),
                      ),
                      pw.Expanded(
                        flex: 1,
                        child: pw.Container(
                          padding: pw.EdgeInsets.fromLTRB(5, 5, 5, 5),
                          alignment: pw.Alignment.center,
                          decoration: pw.BoxDecoration(
                            border: pw.Border(
                              right: pw.BorderSide(width: 1.0),
                              bottom: pw.BorderSide(width: 1.0),
                            ),
                          ),
                          child: pw.Text(
                            'Quantity',
                            style: pw.TextStyle(fontSize: 10),
                          ),
                        ),
                      ),
                      pw.Expanded(
                        flex: 1,
                        child: pw.Container(
                          padding: pw.EdgeInsets.fromLTRB(5, 5, 5, 5),
                          alignment: pw.Alignment.center,
                          decoration: pw.BoxDecoration(
                            border: pw.Border(
                              right: pw.BorderSide(width: 1.0),
                              bottom: pw.BorderSide(width: 1.0),
                            ),
                          ),
                          child: pw.Text(
                            'Rate',
                            style: pw.TextStyle(fontSize: 10),
                          ),
                        ),
                      ),
                      pw.Expanded(
                        flex: 1,
                        child: pw.Container(
                          padding: pw.EdgeInsets.fromLTRB(5, 5, 5, 5),
                          alignment: pw.Alignment.center,
                          decoration: pw.BoxDecoration(
                            border: pw.Border(
                              right: pw.BorderSide(width: 1.0),
                              bottom: pw.BorderSide(width: 1.0),
                            ),
                          ),
                          child: pw.Text(
                            'per',
                            style: pw.TextStyle(fontSize: 10),
                          ),
                        ),
                      ),
                      pw.Expanded(
                        flex: 1,
                        child: pw.Container(
                          padding: pw.EdgeInsets.fromLTRB(5, 5, 5, 5),
                          alignment: pw.Alignment.center,
                          decoration: pw.BoxDecoration(
                            border: pw.Border(
                              right: pw.BorderSide(width: 1.0),
                              bottom: pw.BorderSide(width: 1.0),
                            ),
                          ),
                          child: pw.Text(
                            'Disc. %',
                            style: pw.TextStyle(fontSize: 10),
                          ),
                        ),
                      ),
                      pw.Expanded(
                        flex: 2,
                        child: pw.Container(
                          padding: pw.EdgeInsets.fromLTRB(5, 5, 5, 5),
                          alignment: pw.Alignment.center,
                          decoration: pw.BoxDecoration(
                            border: pw.Border(
                              right: pw.BorderSide(width: 1.0),
                              bottom: pw.BorderSide(width: 1.0),
                            ),
                          ),
                          child: pw.Text(
                            'Amount',
                            style: pw.TextStyle(fontSize: 10),
                          ),
                        ),
                      ),
                      // FTA UAE VAT requires the VAT % and VAT amount to be
                      // shown per line item, not just as an invoice total.
                      pw.Expanded(
                        flex: 1,
                        child: pw.Container(
                          padding: pw.EdgeInsets.fromLTRB(5, 5, 5, 5),
                          alignment: pw.Alignment.center,
                          decoration: pw.BoxDecoration(
                            border: pw.Border(
                              right: pw.BorderSide(width: 1.0),
                              bottom: pw.BorderSide(width: 1.0),
                            ),
                          ),
                          child: pw.Text(
                            'VAT %',
                            style: pw.TextStyle(fontSize: 10),
                          ),
                        ),
                      ),
                      pw.Expanded(
                        flex: 2,
                        child: pw.Container(
                          padding: pw.EdgeInsets.fromLTRB(5, 5, 5, 5),
                          alignment: pw.Alignment.center,
                          decoration: pw.BoxDecoration(
                            border: pw.Border(
                              bottom: pw.BorderSide(width: 1.0),
                            ),
                          ),
                          child: pw.Text(
                            'VAT Amt',
                            style: pw.TextStyle(fontSize: 10),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // NOTE: these tables are direct top-level widgets (not
            // wrapped in a Container/Column) — pw.MultiPage can only
            // split a pw.Table row-by-row across pages when the Table
            // is top-level; wrapping it defers every row to the next
            // page instead. Left/right border lines are added on each
            // Table's own TableBorder so the box still looks unified.
            ...[
              pw.Table(
                border: pw.TableBorder(
                  left: pw.BorderSide(width: 1.0),
                  right: pw.BorderSide(width: 1.0),
                  horizontalInside: pw.BorderSide.none,
                  verticalInside: pw.BorderSide(
                    color: PdfColor.fromHex('#050400'),
                  ),
                  bottom: pw.BorderSide.none,
                  top: pw.BorderSide(width: 1.0),
                ),
                children: [
                  for (var item in saleItems.asMap().entries)
                    pw.TableRow(
                      children: [
                        pw.Expanded(
                          flex: 1,
                          child: pw.Container(
                            padding: pw.EdgeInsets.fromLTRB(
                              5,
                              5,
                              5,
                              (item.key == saleItems.length - 1
                                  ? _estimateInvoiceLastRowFillerPadding(
                                      saleItems.length,
                                    )
                                  : 5.0),
                            ), // Left, Top, Right, Bottom
                            alignment: pw.Alignment.center,

                            child: pw.Text(
                              formatitemKey(item.key),
                              style: pw.TextStyle(fontSize: 10),
                            ),
                          ),
                        ),

                        pw.Expanded(
                          flex: 3,
                          child: pw.Container(
                            // Left/right margin trimmed to 2 (from 5) so long
                            // item names get more usable width and wrap onto
                            // fewer lines; top/bottom untouched.
                            padding: pw.EdgeInsets.fromLTRB(
                              2,
                              5,
                              2,
                              (item.key == saleItems.length - 1
                                  ? _estimateInvoiceLastRowFillerPadding(
                                      saleItems.length,
                                    )
                                  : 5.0),
                            ),
                            alignment: pw.Alignment.centerLeft,

                            child: pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                pw.Text(
                                  item.value.itemName,
                                  style: pw.TextStyle(fontSize: 10),
                                ),
                              ],
                            ),
                          ),
                        ),
                        pw.Expanded(
                          flex: 1,
                          child: pw.Container(
                            padding: pw.EdgeInsets.fromLTRB(
                              5,
                              5,
                              5,
                              (item.key == saleItems.length - 1
                                  ? _estimateInvoiceLastRowFillerPadding(
                                      saleItems.length,
                                    )
                                  : 5.0),
                            ),
                            alignment: pw.Alignment.centerRight,

                            child: pw.Row(
                              mainAxisAlignment: pw.MainAxisAlignment.center,
                              crossAxisAlignment: pw.CrossAxisAlignment.center,
                              children: [
                                pw.Text(
                                  item.value.itemQuantity,
                                  textAlign: pw.TextAlign.right,
                                  style: pw.TextStyle(fontSize: 10),
                                ),
                              ],
                            ),
                          ),
                        ),
                        pw.Expanded(
                          flex: 1,
                          child: pw.Container(
                            padding: pw.EdgeInsets.fromLTRB(
                              5,
                              5,
                              5,
                              (item.key == saleItems.length - 1
                                  ? _estimateInvoiceLastRowFillerPadding(
                                      saleItems.length,
                                    )
                                  : 5.0),
                            ),
                            alignment: pw.Alignment.center,

                            child: pw.Text(
                              formatAmountInvoice(
                                item.value.itemPrice.toString(),
                              ),
                              textAlign: pw.TextAlign.center,
                              style: pw.TextStyle(fontSize: 10),
                            ),
                          ),
                        ),
                        pw.Expanded(
                          flex: 1,
                          child: pw.Container(
                            padding: pw.EdgeInsets.fromLTRB(
                              5,
                              5,
                              5,
                              (item.key == saleItems.length - 1
                                  ? _estimateInvoiceLastRowFillerPadding(
                                      saleItems.length,
                                    )
                                  : 5.0),
                            ),
                            alignment: pw.Alignment.center,
                            child: pw.Text(
                              item.value.itemUnit,
                              textAlign: pw.TextAlign.center,
                              style: pw.TextStyle(fontSize: 10),
                            ),
                          ),
                        ),
                        pw.Expanded(
                          flex: 1,
                          child: pw.Container(
                            padding: pw.EdgeInsets.fromLTRB(
                              5,
                              5,
                              5,
                              (item.key == saleItems.length - 1
                                  ? _estimateInvoiceLastRowFillerPadding(
                                      saleItems.length,
                                    )
                                  : 5.0),
                            ),
                            alignment: pw.Alignment.center,
                            child: pw.Text(
                              '',
                              style: pw.TextStyle(fontSize: 10),
                            ),
                          ),
                        ),
                        pw.Expanded(
                          flex: 2,
                          child: pw.Container(
                            padding: pw.EdgeInsets.fromLTRB(
                              5,
                              5,
                              5,
                              (item.key == saleItems.length - 1
                                  ? _estimateInvoiceLastRowFillerPadding(
                                      saleItems.length,
                                    )
                                  : 5.0),
                            ),
                            alignment: pw.Alignment.centerRight,
                            child: pw.Text(
                              formatAmountInvoice(
                                item.value.itemAmount.toStringAsFixed(decimal!),
                              ),
                              textAlign: pw.TextAlign.right,
                              style: pw.TextStyle(fontSize: 10),
                            ),
                          ),
                        ),
                        // FTA UAE VAT requires the VAT % and VAT amount to
                        // be shown per line item. VAT is a single flat rate
                        // for the whole invoice (vatperc), gated by whether
                        // a VAT ledger is selected at all.
                        pw.Expanded(
                          flex: 1,
                          child: pw.Container(
                            padding: pw.EdgeInsets.fromLTRB(
                              5,
                              5,
                              5,
                              (item.key == saleItems.length - 1
                                  ? _estimateInvoiceLastRowFillerPadding(
                                      saleItems.length,
                                    )
                                  : 5.0),
                            ),
                            alignment: pw.Alignment.center,
                            child: pw.Text(
                              _selectedvatledger != 'Not Applicable'
                                  ? '${vatperc.toStringAsFixed(vatperc.truncateToDouble() == vatperc ? 0 : 2)}%'
                                  : '0%',
                              textAlign: pw.TextAlign.center,
                              style: pw.TextStyle(fontSize: 10),
                            ),
                          ),
                        ),
                        pw.Expanded(
                          flex: 2,
                          child: pw.Container(
                            padding: pw.EdgeInsets.fromLTRB(
                              5,
                              5,
                              5,
                              (item.key == saleItems.length - 1
                                  ? _estimateInvoiceLastRowFillerPadding(
                                      saleItems.length,
                                    )
                                  : 5.0),
                            ),
                            alignment: pw.Alignment.centerRight,
                            child: pw.Text(
                              formatAmountInvoice(
                                (_selectedvatledger != 'Not Applicable'
                                        ? item.value.itemAmount *
                                              (vatperc / 100)
                                        : 0.0)
                                    .toStringAsFixed(decimal!),
                              ),
                              textAlign: pw.TextAlign.right,
                              style: pw.TextStyle(fontSize: 10),
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),

              pw.Table(
                border: pw.TableBorder(
                  left: pw.BorderSide(width: 1.0),
                  right: pw.BorderSide(width: 1.0),
                  horizontalInside: pw.BorderSide.none,
                  verticalInside: pw.BorderSide(
                    color: PdfColor.fromHex('#050400'),
                  ),
                  top: pw.BorderSide(color: PdfColor.fromHex('#050400')),
                  bottom: pw.BorderSide(color: PdfColor.fromHex('#050400')),
                ),
                children: [
                  pw.TableRow(
                    children: [
                      pw.Expanded(
                        flex: 1,
                        child: pw.Container(
                          padding: pw.EdgeInsets.fromLTRB(
                            5,
                            5,
                            5,
                            5,
                          ), // Left, Top, Right, Bottom
                          alignment: pw.Alignment.center,
                        ),
                      ),

                      pw.Expanded(
                        flex: 3,
                        child: pw.Container(
                          padding: pw.EdgeInsets.fromLTRB(5, 5, 5, 5),
                          alignment: pw.Alignment.centerRight,
                          child: pw.Text('', style: pw.TextStyle(fontSize: 10)),
                        ),
                      ),

                      pw.Expanded(
                        flex: 1,
                        child: pw.Container(
                          padding: pw.EdgeInsets.fromLTRB(5, 5, 5, 5),
                          alignment: pw.Alignment.center,
                          child: pw.Text('', style: pw.TextStyle(fontSize: 10)),
                        ),
                      ),
                      pw.Expanded(
                        flex: 1,
                        child: pw.Container(
                          padding: pw.EdgeInsets.fromLTRB(5, 5, 5, 5),
                          alignment: pw.Alignment.centerRight,
                        ),
                      ),
                      pw.Expanded(
                        flex: 1,
                        child: pw.Container(
                          padding: pw.EdgeInsets.fromLTRB(5, 5, 5, 5),
                          alignment: pw.Alignment.centerRight,
                        ),
                      ),
                      pw.Expanded(
                        flex: 1,
                        child: pw.Container(
                          padding: pw.EdgeInsets.fromLTRB(5, 5, 5, 5),
                          alignment: pw.Alignment.centerRight,
                        ),
                      ),
                      pw.Expanded(
                        flex: 2,
                        child: pw.Container(
                          padding: pw.EdgeInsets.fromLTRB(5, 5, 5, 5),
                          alignment: pw.Alignment.centerRight,
                          child: pw.Text(
                            formatAmountInvoice(
                              totalitemAmount.toStringAsFixed(decimal!),
                            ),
                            textAlign: pw.TextAlign.right,
                            style: pw.TextStyle(fontSize: 10),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              if (ledgerEntries.isNotEmpty)
                for (var ledger in ledgerEntries.asMap().entries)
                  pw.Table(
                    border: pw.TableBorder(
                      left: pw.BorderSide(width: 1.0),
                      right: pw.BorderSide(width: 1.0),
                      horizontalInside: pw.BorderSide(
                        color: PdfColor.fromHex('#050400'),
                      ),
                      verticalInside: pw.BorderSide(
                        color: PdfColor.fromHex('#050400'),
                      ),
                      bottom: pw.BorderSide(color: PdfColor.fromHex('#050400')),
                      top: pw.BorderSide(color: PdfColor.fromHex('#050400')),
                    ),
                    children: [
                      pw.TableRow(
                        children: [
                          pw.Expanded(
                            flex: 1,
                            child: pw.Container(
                              padding: pw.EdgeInsets.fromLTRB(
                                5,
                                5,
                                5,
                                5,
                              ), // Left, Top, Right, Bottom
                              alignment: pw.Alignment.center,
                            ),
                          ),

                          pw.Expanded(
                            flex: 3,
                            child: pw.Container(
                              padding: pw.EdgeInsets.fromLTRB(5, 5, 5, 5),
                              alignment: pw.Alignment.centerRight,

                              child: pw.Text(
                                ledger.value.ledgerName,
                                style: pw.TextStyle(fontSize: 10),
                              ),
                            ),
                          ),
                          pw.Expanded(
                            flex: 1,
                            child: pw.Container(
                              padding: pw.EdgeInsets.fromLTRB(5, 5, 5, 5),
                              alignment: pw.Alignment.centerRight,
                            ),
                          ),
                          pw.Expanded(
                            flex: 1,
                            child: pw.Container(
                              padding: pw.EdgeInsets.fromLTRB(5, 5, 5, 5),
                              alignment: pw.Alignment.centerRight,
                            ),
                          ),
                          pw.Expanded(
                            flex: 1,
                            child: pw.Container(
                              padding: pw.EdgeInsets.fromLTRB(5, 5, 5, 5),
                              alignment: pw.Alignment.centerRight,
                            ),
                          ),
                          pw.Expanded(
                            flex: 1,
                            child: pw.Container(
                              padding: pw.EdgeInsets.fromLTRB(5, 5, 5, 5),
                              alignment: pw.Alignment.centerRight,
                            ),
                          ),
                          pw.Expanded(
                            flex: 2,
                            child: pw.Container(
                              padding: pw.EdgeInsets.fromLTRB(5, 5, 5, 5),
                              alignment: pw.Alignment.centerRight,
                              child: pw.Text(
                                formatAmountInvoice(
                                  ledger.value.ledgerAmount.toString(),
                                ),
                                textAlign: pw.TextAlign.right,
                                style: pw.TextStyle(fontSize: 10),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

              if (vatledgerdata.isNotEmpty &&
                  _selectedvatledger != 'Not Applicable')
                pw.Table(
                  border: pw.TableBorder(
                    left: pw.BorderSide(width: 1.0),
                    right: pw.BorderSide(width: 1.0),
                    horizontalInside: pw.BorderSide(
                      color: PdfColor.fromHex('#050400'),
                    ),
                    verticalInside: pw.BorderSide(
                      color: PdfColor.fromHex('#050400'),
                    ),
                    bottom: pw.BorderSide(color: PdfColor.fromHex('#050400')),
                    top: pw.BorderSide(color: PdfColor.fromHex('#050400')),
                  ),
                  children: [
                    pw.TableRow(
                      children: [
                        pw.Expanded(
                          flex: 1,
                          child: pw.Container(
                            padding: pw.EdgeInsets.fromLTRB(
                              5,
                              5,
                              5,
                              5,
                            ), // Left, Top, Right, Bottom
                            alignment: pw.Alignment.center,
                          ),
                        ),

                        pw.Expanded(
                          flex: 3,
                          child: pw.Container(
                            padding: pw.EdgeInsets.fromLTRB(5, 5, 5, 5),
                            alignment: pw.Alignment.centerRight,

                            child: pw.Text(
                              _selectedvatledger,
                              style: pw.TextStyle(fontSize: 10),
                            ),
                          ),
                        ),
                        pw.Expanded(
                          flex: 1,
                          child: pw.Container(
                            padding: pw.EdgeInsets.fromLTRB(5, 5, 5, 5),
                            alignment: pw.Alignment.centerRight,
                          ),
                        ),
                        pw.Expanded(
                          flex: 1,
                          child: pw.Container(
                            padding: pw.EdgeInsets.fromLTRB(5, 5, 5, 5),
                            alignment: pw.Alignment.centerRight,
                          ),
                        ),
                        pw.Expanded(
                          flex: 1,
                          child: pw.Container(
                            padding: pw.EdgeInsets.fromLTRB(5, 5, 5, 5),
                            alignment: pw.Alignment.centerRight,
                          ),
                        ),
                        pw.Expanded(
                          flex: 1,
                          child: pw.Container(
                            padding: pw.EdgeInsets.fromLTRB(5, 5, 5, 5),
                            alignment: pw.Alignment.centerRight,
                          ),
                        ),
                        pw.Expanded(
                          flex: 2,
                          child: pw.Container(
                            padding: pw.EdgeInsets.fromLTRB(5, 5, 5, 5),
                            alignment: pw.Alignment.centerRight,

                            child: pw.Text(
                              formatAmountInvoice(totalVatAmount.toString()),
                              textAlign: pw.TextAlign.right,
                              style: pw.TextStyle(fontSize: 10),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

              pw.Table(
                border: pw.TableBorder(
                  left: pw.BorderSide(width: 1.0),
                  right: pw.BorderSide(width: 1.0),
                  horizontalInside: pw.BorderSide(
                    color: PdfColor.fromHex('#050400'),
                  ),
                  verticalInside: pw.BorderSide(
                    color: PdfColor.fromHex('#050400'),
                  ),
                  bottom: pw.BorderSide.none,
                ),
                children: [
                  pw.TableRow(
                    children: [
                      pw.Expanded(
                        flex: 1,
                        child: pw.Container(
                          padding: pw.EdgeInsets.fromLTRB(
                            5,
                            5,
                            5,
                            5,
                          ), // Left, Top, Right, Bottom
                          alignment: pw.Alignment.center,
                        ),
                      ),

                      pw.Expanded(
                        flex: 3,
                        child: pw.Container(
                          padding: pw.EdgeInsets.fromLTRB(5, 5, 5, 5),
                          alignment: pw.Alignment.centerRight,

                          child: pw.Text(
                            'Total',
                            style: pw.TextStyle(fontSize: 10),
                          ),
                        ),
                      ),

                      pw.Expanded(
                        flex: 1,
                        child: pw.Container(
                          padding: pw.EdgeInsets.fromLTRB(5, 5, 5, 5),
                          alignment: pw.Alignment.center,
                          child: pw.Text(
                            totalQuantity.toString(),
                            style: pw.TextStyle(fontSize: 10),
                          ),
                        ),
                      ),
                      pw.Expanded(
                        flex: 1,
                        child: pw.Container(
                          padding: pw.EdgeInsets.fromLTRB(5, 5, 5, 5),
                          alignment: pw.Alignment.centerRight,
                        ),
                      ),
                      pw.Expanded(
                        flex: 1,
                        child: pw.Container(
                          padding: pw.EdgeInsets.fromLTRB(5, 5, 5, 5),
                          alignment: pw.Alignment.centerRight,
                        ),
                      ),
                      pw.Expanded(
                        flex: 1,
                        child: pw.Container(
                          padding: pw.EdgeInsets.fromLTRB(5, 5, 5, 5),
                          alignment: pw.Alignment.centerRight,
                        ),
                      ),
                      pw.Expanded(
                        flex: 2,
                        child: pw.Container(
                          padding: pw.EdgeInsets.fromLTRB(5, 5, 5, 5),
                          alignment: pw.Alignment.centerRight,

                          child: pw.Text(
                            formatAmountInvoice(roundedtotalAmount.toString()),
                            textAlign: pw.TextAlign.right,
                            style: pw.TextStyle(fontSize: 10),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              pw.Table(
                border: pw.TableBorder(
                  left: pw.BorderSide(width: 1.0),
                  right: pw.BorderSide(width: 1.0),
                  horizontalInside: pw.BorderSide.none,
                  verticalInside: pw.BorderSide.none,
                  bottom: pw.BorderSide.none,
                  top: pw.BorderSide(color: PdfColor.fromHex('#050400')),
                ),
                children: [
                  pw.TableRow(
                    children: [
                      pw.Expanded(
                        flex: 1,
                        child: pw.Container(
                          padding: pw.EdgeInsets.fromLTRB(
                            5,
                            5,
                            5,
                            5,
                          ), // Left, Top, Right, Bottom
                          alignment: pw.Alignment.centerLeft,

                          child: pw.Column(
                            mainAxisAlignment: pw.MainAxisAlignment.start,
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(
                                'Amount Chargeable (in words)',
                                textAlign: pw.TextAlign.left,
                                style: pw.TextStyle(fontSize: 10),
                              ),

                              pw.Text(
                                convertAmountToWords(totalAmount),
                                textAlign: pw.TextAlign.left,
                                style: pw.TextStyle(fontSize: 10),
                              ),

                              pw.SizedBox(height: 10),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              // declaration table - both this table's bottom border AND
              // the note container's top border below are real (not
              // none), so the box closes properly whether they land on
              // the same page (the two lines just overlap into one) or
              // get split across a page break (each half still closes
              // cleanly on its own).
              pw.Table(
                border: pw.TableBorder(
                  left: pw.BorderSide(width: 1.0),
                  right: pw.BorderSide(width: 1.0),
                  horizontalInside: pw.BorderSide.none,
                  verticalInside: pw.BorderSide(width: 1.0),
                  bottom: pw.BorderSide(width: 1.0),
                  top: pw.BorderSide(color: PdfColor.fromHex('#050400')),
                ),
                children: [
                  pw.TableRow(
                    children: [
                      pw.Expanded(
                        flex: 1,
                        child: pw.Container(
                          padding: pw.EdgeInsets.fromLTRB(
                            5,
                            5,
                            5,
                            5,
                          ), // Left, Top, Right, Bottom
                          alignment: pw.Alignment.centerLeft,

                          child: pw.Column(
                            mainAxisAlignment: pw.MainAxisAlignment.start,
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.SizedBox(height: 4),

                              pw.Text(
                                'Declaration',
                                textAlign: pw.TextAlign.left,
                                style: pw.TextStyle(fontSize: 10),
                              ),

                              pw.Text(
                                'We declare that this invoice shows the actual price of the goods described and that all particulars are true and correct',
                                textAlign: pw.TextAlign.left,
                                style: pw.TextStyle(fontSize: 10),
                              ),

                              pw.SizedBox(height: 4),
                            ],
                          ),
                        ),
                      ),

                      pw.Expanded(
                        flex: 1,
                        child: pw.Container(
                          padding: pw.EdgeInsets.fromLTRB(5, 5, 5, 5),
                          alignment: pw.Alignment.center,

                          child: pw.Column(
                            mainAxisAlignment: pw.MainAxisAlignment.center,
                            crossAxisAlignment: pw.CrossAxisAlignment.center,
                            children: [
                              pw.Text(
                                'for $company',
                                textAlign: pw.TextAlign.center,
                                style: pw.TextStyle(fontSize: 10),
                              ),

                              pw.SizedBox(height: 30),

                              pw.Text(
                                'Authorised Signatory',
                                textAlign: pw.TextAlign.left,
                                style: pw.TextStyle(fontSize: 10),
                              ),

                              pw.SizedBox(height: 2),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              pw.Container(
                padding: pw.EdgeInsets.fromLTRB(
                  5,
                  2,
                  5,
                  2,
                ), // Left, Top, Right, Bottom
                decoration: pw.BoxDecoration(
                  border: pw.Border(
                    left: pw.BorderSide(width: 1.0),
                    right: pw.BorderSide(width: 1.0),
                    top: pw.BorderSide(width: 1.0),
                    bottom: pw.BorderSide(width: 1.0),
                  ),
                ),
                alignment: pw.Alignment.center,

                child: pw.Text(
                  'This is a System Generated Document',
                  textAlign: pw.TextAlign.left,
                  style: pw.TextStyle(fontSize: 10),
                ),
              ),
            ],
          ];
        },
      ),
    );

    // 🗂 Save to temp file
    final pdfData = await pdf.save();

    final dir = await getApplicationDocumentsDirectory();
    final filePath = '${dir.path}/SaleInvoice.pdf';

    final file = File(filePath);
    await file.writeAsBytes(pdfData);

    await Share.shareXFiles([
      XFile(filePath, mimeType: 'application/pdf'),
    ], text: 'Sharing Sale Invoice for $_selectedpartyledger');

    _dropFocusBeforeReset();

    setState(() {
      controller_narration.clear();
      controller_refno.clear();

      _textFieldFocusNodeNarration.unfocus(); // Unfocus the TextField

      saledate = DateTime.now();
      saledatestring = _dateFormat.format(saledate);
      saledatetxt = formatlastsaledate(saledatestring);
      _dateController.text = saledatetxt;
      refdate = DateTime.now();
      refdatestring = _dateFormat.format(refdate);
      refdatetxt = formatlastsaledate(refdatestring);
      _refdateController.text = refdatetxt;
      // _selectedvchtypename = vchtypenamedata[0];
      fetchvchnos(_selectedvchtypename);
      _selectedpartyledger = null;
      _partyLedgerController.clear();
      // _selectedsalesledger = salesledger_data[0];

      _selectedledger = ledgerdata.isNotEmpty ? ledgerdata[0]['name'] : null;

      _selectedvatledger = _defaultVatLedger();

      _selecteditem = '${itemdata[0]['name']}';
      _itemController.text = _selecteditem;
      if (locationsdata.isNotEmpty) {
        selectedLocation = locationsdata[0];
        isVisibleLocation = true;
      } else {
        isVisibleLocation = false;
      }
      _updateUnitDropdown(_selecteditem);

      saleItems.clear();
      ledgerEntries.clear();

      // making sales list empty and setting values

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

      if (_selectedvatledger != 'Not Applicable') {
        double vat_perc = vatperc / 100;
        itemsVatAmount = double.parse(
          (totalPriceOfItems * vat_perc).toStringAsFixed(decimal!),
        );
        totalVatAmount = itemsVatAmount + ledgerVatAmount;

        roundedtotalVatAmount = double.parse(
          totalVatAmount.toStringAsFixed(decimal!),
        );
        NumberFormat formatter = NumberFormat(
          '#,##0.${'0' * decimal!}',
          'en_US',
        );
        String formattedVat = formatter.format(roundedtotalVatAmount);
        controller_vatamt.text = formattedVat.toString();
      } else {
        totalVatAmount = 0;

        roundedtotalVatAmount = double.parse(
          totalVatAmount.toStringAsFixed(decimal!),
        );
        NumberFormat formatter = NumberFormat(
          '#,##0.${'0' * decimal!}',
          'en_US',
        );
        String formattedVat = formatter.format(roundedtotalVatAmount);
        controller_vatamt.text = formattedVat.toString();
      }
      if (saleItems.isEmpty) {
        isVisibleItemHeading = false;
      } else {
        isVisibleItemHeading = true;
      }
      // making ledger list empty and setting values
      totalAmountForVatAppEntries = ledgerEntries
          .where((entry) => entry.vatApp)
          .fold(0.0, (double previousAmount, LedgerEntry entry) {
            return previousAmount + entry.ledgerAmount;
          });

      if (_selectedvatledger != 'Not Applicable') {
        double vat_perc = vatperc / 100;
        ledgerVatAmount = totalAmountForVatAppEntries * vat_perc;
        totalVatAmount = itemsVatAmount + ledgerVatAmount;
        roundedtotalVatAmount = double.parse(
          totalVatAmount.toStringAsFixed(decimal!),
        );
        NumberFormat formatter = NumberFormat(
          '#,##0.${'0' * decimal!}',
          'en_US',
        );
        String formattedVat = formatter.format(roundedtotalVatAmount);
        controller_vatamt.text = formattedVat.toString();
      } else {
        totalVatAmount = 0;
        roundedtotalVatAmount = double.parse(
          totalVatAmount.toStringAsFixed(decimal!),
        );
        NumberFormat formatter = NumberFormat(
          '#,##0.${'0' * decimal!}',
          'en_US',
        );
        String formattedVat = formatter.format(roundedtotalVatAmount);
        controller_vatamt.text = formattedVat.toString();
      }
      if (ledgerEntries.isEmpty) {
        isVisibleLedgerHeading = false;
      } else {
        isVisibleLedgerHeading = true;
      }
      totalAmount = totalPriceOfItems + totalAmountOfLedgers + totalVatAmount;
      roundedtotalAmount = double.parse(totalAmount.toStringAsFixed(decimal!));
      NumberFormat formatter = NumberFormat('#,##0.${'0' * decimal!}', 'en_US');
      String formattedtotal = formatter.format(roundedtotalAmount);
      controller_totalamt.text = formattedtotal.toString();
      _isFocused_vchno = false;
      _isFocused_item = false;
      _isFocused_unit = false;
      _isFocused_ledger = false;
      _isFocused_narration = false;
      _isFocused_totalamt = false;
      _isFocused_vatamt = false;
    });
  }

  // Narrow POS Tax Invoice format required by UniGas for their thermal
  // printer/POS device (~76mm / 216pt wide, single continuous page).
  // Company header details (name, tagline, branch locations, tel/email/
  // web/TRN) are hardcoded here because this format is only ever used
  // when the device's serial is a UniGas serial - i.e. the company is
  // always United Gas Co. LLC.
  Future<void> _generateUniGasTaxInvoicePDF(
    String trn,
    String address,
    String emirate,
    String country,
  ) async {
    // Resolve the van (vehicle) allocated to this device's serial number
    // from the locally-cached 'spectra_allocations' SharedPreferences
    // value rather than making a fresh network call.
    String vehicleName = '';
    try {
      final String? spectraAllocationsString = prefs.getString(
        'spectra_allocations',
      );
      debugPrint(
        "UNIGAS TAX INVOICE VEHICLE LOOKUP (prefs): $spectraAllocationsString",
      );

      if (spectraAllocationsString != null &&
          spectraAllocationsString.isNotEmpty) {
        final List<dynamic> spectraAllocations = jsonDecode(
          spectraAllocationsString,
        );
        if (spectraAllocations.isNotEmpty) {
          final first = Map<String, dynamic>.from(spectraAllocations.first);
          vehicleName = first['godown']?.toString() ?? '';
        }
      }
    } catch (e) {
      debugPrint("UNIGAS TAX INVOICE VEHICLE LOOKUP ERROR: $e");
    }

    final logoBytes = await rootBundle.load("assets/uigas-logo.jpeg");
    final uniGasLogo = pw.MemoryImage(logoBytes.buffer.asUint8List());

    // Arabic-capable font for "فاتورة ضريبية" / "توقيع العميل" -
    // NotoSans.ttf (used for everything else) has no Arabic glyphs.
    final arabicFontData = await rootBundle.load(
      "assets/fonts/NotoSansArabic.ttf",
    );
    final arabicFont = pw.Font.ttf(arabicFontData);

    // Any party-ledger detail that's missing/null/empty shows as
    // "Not Available" rather than a blank line or the literal word "null".
    String cleanOrNotAvailable(String? value) {
      if (value == null) return 'Not Available';
      final trimmed = value.trim();
      return (trimmed.isEmpty || trimmed.toLowerCase() == 'null')
          ? 'Not Available'
          : trimmed;
    }

    List<String> placeParts = [];
    if (address != "null" && address.trim().isNotEmpty) {
      placeParts.add(address.trim());
    }
    if (emirate != "null" && emirate.trim().isNotEmpty) {
      placeParts.add(emirate.trim());
    }
    if (country != "null" && country.trim().isNotEmpty) {
      placeParts.add(country.trim());
    }
    final String customerAddress = placeParts.isEmpty
        ? 'Not Available'
        : placeParts.join(", ");

    final String customerTrn = cleanOrNotAvailable(trn);
    final String customerMobile = cleanOrNotAvailable(_selectedPartyMobile);
    final String customerEmail = cleanOrNotAvailable(_selectedPartyEmail);

    final now = DateTime.now();
    final dateTimeText =
        '${DateFormat('yyyy-MM-dd').format(now)}  ${DateFormat('HH:mm').format(now)}';

    pw.Widget leftText(String text, {double size = 9, pw.FontWeight? weight}) {
      return pw.Align(
        alignment: pw.Alignment.centerLeft,
        child: pw.Text(
          text,
          style: pw.TextStyle(fontSize: size, fontWeight: weight),
        ),
      );
    }

    // Bold "Label:" followed by the value, for the customer details box.
    pw.Widget detailLine(
      String label,
      String value, {
      double size = 8,
      bool boldLabel = true,
    }) {
      return pw.Align(
        alignment: pw.Alignment.centerLeft,
        child: pw.RichText(
          text: pw.TextSpan(
            children: [
              pw.TextSpan(
                text: '$label: ',
                style: pw.TextStyle(
                  fontSize: size,
                  fontWeight: boldLabel ? pw.FontWeight.bold : null,
                ),
              ),
              pw.TextSpan(
                text: value,
                style: pw.TextStyle(fontSize: size),
              ),
            ],
          ),
        ),
      );
    }

    // Label on the left, value on the right - used for Delivered
    // by/Vehicle.
    pw.Widget spaceBetweenLine(
      String label,
      String value, {
      bool bold = true,
      double size = 9,
    }) {
      return pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: size,
              fontWeight: bold ? pw.FontWeight.bold : null,
            ),
          ),
          pw.SizedBox(width: 6),
          pw.Flexible(
            child: pw.Text(
              value,
              textAlign: pw.TextAlign.right,
              style: pw.TextStyle(
                fontSize: size,
                fontWeight: bold ? pw.FontWeight.bold : null,
              ),
            ),
          ),
        ],
      );
    }

    // A dotted line under the item table headers, matching the reference
    // exactly - the pdf package has no built-in dashed-border widget, so
    // this is faked with a clipped run of periods. Must be wrapped in an
    // explicit-width SizedBox at the call site (same as the Delivery
    // Note's dots()) - a bare pw.Text has no bounded width to clip against
    // here, so the dashes never actually appeared.
    pw.Widget dots({int count = 400}) {
      return pw.Text(
        '.' * count,
        maxLines: 1,
        softWrap: false,
        overflow: pw.TextOverflow.clip,
        style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600, height: 1),
      );
    }

    // One cell in an item-table row. Only ITEM/UNIT text can span more
    // than one line (long item names) - every other cell is short enough
    // to stay single-line in practice.
    pw.Widget cell(
      String text,
      double flex, {
      bool bold = false,
      bool center = false,
      bool right = false,
      double fontSize = 9,
      // Fixed-pixel nudge, not a flex change - shifts the rendered text
      // within its own box without touching the column's own flex share/
      // boundary/width, so the column's true position (and anything
      // aligned to it, like a sibling row's matching column) is completely
      // unaffected. Negative moves the text left, closer to the previous
      // column, purely visually.
      double leftShift = 0,
    }) {
      final align = center
          ? pw.TextAlign.center
          : (right ? pw.TextAlign.right : pw.TextAlign.left);
      return pw.Expanded(
        flex: (flex * 10).round(),
        child: pw.Padding(
          padding: pw.EdgeInsets.only(left: 1 + leftShift, right: 1),
          child: pw.Text(
            text,
            textAlign: align,
            style: pw.TextStyle(
              fontSize: fontSize,
              fontWeight: bold ? pw.FontWeight.bold : null,
            ),
          ),
        ),
      );
    }

    // One full row of the item table's top line (SN/ITEM/QTY/RATE) or
    // bottom line (blank/UNIT/VAT %/VALUE). Built as two independent
    // pw.Rows rather than stacking a top+bottom pw.Text inside each
    // column: when the ITEM name wraps onto a second line, a per-column
    // stack pushes that column's own "bottom" line down with it while its
    // siblings (UNIT/VAT %/VALUE) stay put, throwing the whole row out of
    // alignment. Two literal rows keep UNIT/VAT %/VALUE always on their
    // own shared single line, however tall the ITEM row above them grows.
    pw.Widget itemTableRow(
      String col1,
      String col2,
      String col3,
      String col4, {
      bool bold = false,
      bool col4Center = false,
      // col1Flex/col2Flex are overridable per call so data rows can start
      // ITEM closer to SN without touching the header - only their SUM
      // matters for QTY's position, so col1Flex + col2Flex must add up to
      // the same total (5.9) in every call. col3Flex (QTY) is shared
      // unchanged by both header and data calls on purpose: QTY's own
      // value must sit centered under its own "QTY" heading, which only
      // holds if QTY's column position AND width are identical between
      // the two rows. It was previously too narrow (0.8) for the bold
      // "QTY" heading itself to fit on one line - widened to 1.3, with
      // RATE/VALUE trimmed from 2.2 to 1.8 (numbers there are short) to
      // give that width back without shrinking ITEM.
      double col1Flex = 1,
      double col2Flex = 4.9,
      double col3Flex = 1.3,
      double fontSize = 9,
      // Fixed-pixel nudge for QTY's text only - lets data rows pull QTY's
      // rendered value visually closer to ITEM without changing col3Flex
      // (so QTY's column position/width, and its alignment with the
      // header's own QTY column, stay exactly where they are).
      double col3LeftShift = 0,
    }) {
      return pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          cell(col1, col1Flex, bold: bold, fontSize: fontSize),
          cell(col2, col2Flex, bold: bold, fontSize: fontSize),
          cell(
            col3,
            col3Flex,
            bold: bold,
            center: true,
            fontSize: fontSize,
            leftShift: col3LeftShift,
          ),
          col4Center
              ? cell(col4, 1.8, bold: bold, center: true, fontSize: fontSize)
              : cell(col4, 1.8, bold: bold, right: true, fontSize: fontSize),
        ],
      );
    }

    // The UNIT/VAT %/VALUE line specifically: UNIT and VAT % are laid out
    // as direct siblings in one merged region (ITEM+QTY's combined flex)
    // with only a small fixed gap between them, instead of each living in
    // its own wide flex column - that's what keeps VAT % sitting right
    // next to UNIT regardless of how wide the ITEM column is. VALUE stays
    // on the same flex/alignment as RATE above it so the two line up.
    pw.Widget unitVatValueRow(
      String unit,
      String vatPercent,
      String value, {
      bool bold = false,
      bool col4Center = false,
      double fontSize = 9,
    }) {
      final style = pw.TextStyle(
        fontSize: fontSize,
        fontWeight: bold ? pw.FontWeight.bold : null,
      );
      return pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          cell('', 1, bold: bold, fontSize: fontSize),
          pw.Expanded(
            flex: 62,
            child: pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 1),
              child: pw.Row(
                children: [
                  // Fixed width (not intrinsic sizing) - a plain pw.Text
                  // here made everything after it (the gap + VAT % box)
                  // start at whatever pixel width THIS specific unit
                  // string happened to render at, which drifts slightly
                  // between different unit strings even at equal
                  // character count (glyph widths vary per letter). VAT %
                  // must land at the exact same x every time regardless
                  // of what UNIT says.
                  pw.SizedBox(
                    width: 32,
                    child: pw.Text(unit, style: style),
                  ),
                  pw.SizedBox(width: 2),
                  // Fixed width shared between the "VAT %" heading and
                  // every item's actual percentage, so a short value like
                  // "5%" centers under the wider heading text instead of
                  // just starting flush at its left edge.
                  pw.SizedBox(
                    width: 30,
                    child: pw.Text(
                      vatPercent,
                      textAlign: pw.TextAlign.center,
                      style: style,
                    ),
                  ),
                ],
              ),
            ),
          ),
          col4Center
              ? cell(value, 1.8, bold: bold, center: true, fontSize: fontSize)
              : cell(value, 1.8, bold: bold, right: true, fontSize: fontSize),
        ],
      );
    }

    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        // Wider than the Delivery Note's 58mm: with 6 item-table columns
        // (SN/ITEM/QTY/UNIT/RATE/AMOUNT) 58mm was too cramped to stay
        // legible - 76mm matches the reference PDF's own export width.
        pageFormat: PdfPageFormat(
          76 * PdfPageFormat.mm,
          double.infinity,
          marginLeft: 10,
          marginRight: 10,
          marginTop: 50,
          marginBottom: 30,
        ),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              // Explicit width+height (matching the asset's ~1:1 aspect
              // ratio) and BoxFit.contain, instead of height-only: with
              // only height set, this pw.Column hands the Image the full
              // page content width as its constraint, and letting the fit
              // calculation infer the box from that (rather than a fixed
              // width) was cropping the top of the logo.
              pw.Image(
                uniGasLogo,
                width: 61,
                height: 60,
                fit: pw.BoxFit.contain,
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'UNITED GAS CO. LLC',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Divider(thickness: 1),
              leftText('A Partner You Can Trust'),
              leftText('Sharjah | Dubai | RAK | UAQ | Fujairah', size: 8),
              pw.SizedBox(height: 6),
              detailLine('Tel', '800 864427'),
              detailLine('Email', 'Info@unigastt.com'),
              detailLine('Web', 'www.unigastt.com'),
              detailLine('TRN', '100206964700003'),
              pw.SizedBox(height: 6),
              pw.Divider(thickness: 1),
              // "TAX INVOICE" + Arabic "فاتورة ضريبية" stay on one line,
              // matching the reference exactly (unlike the signature
              // box below, this heading fits fine at this width).
              pw.Container(
                width: double.infinity,
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'TAX INVOICE',
                      style: pw.TextStyle(
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      'فاتورة ضريبية',
                      textDirection: pw.TextDirection.rtl,
                      style: pw.TextStyle(fontSize: 10, font: arabicFont),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 4),
              leftText('Invoice No: ${_vchnoController.text}'),
              leftText('Date & Time: $dateTimeText'),
              pw.SizedBox(height: 10),
              leftText('CUSTOMER DETAILS', size: 9, weight: pw.FontWeight.bold),
              pw.SizedBox(height: 4),
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(6),
                decoration: pw.BoxDecoration(border: pw.Border.all(width: 1)),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    detailLine(
                      'Name',
                      cleanOrNotAvailable(_selectedpartyledger),
                      size: 9,
                      boldLabel: false,
                    ),
                    pw.SizedBox(height: 6),
                    detailLine('TRN', customerTrn),
                    pw.SizedBox(height: 6),
                    detailLine('Address', customerAddress),
                    pw.SizedBox(height: 6),
                    detailLine('Phone', customerMobile),
                    pw.SizedBox(height: 6),
                    detailLine('Email', customerEmail),
                  ],
                ),
              ),
              pw.SizedBox(height: 10),
              // One continuous box covering headings, item rows, taxable
              // value/VAT and the total - matching the reference exactly.
              // No per-cell grid lines (left/right/inside borders) -
              // columns are aligned with Expanded flex instead of a
              // pw.Table, matching the reference's plain-row look. Top
              // and bottom borders are bold to frame the whole block.
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 6,
                ),
                decoration: const pw.BoxDecoration(
                  border: pw.Border(
                    left: pw.BorderSide(width: 1),
                    right: pw.BorderSide(width: 1),
                    top: pw.BorderSide(width: 2),
                    bottom: pw.BorderSide(width: 2),
                  ),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    // Reference format packs each item into 2 stacked
                    // lines across 4 columns (SN | ITEM/UNIT | QTY/VAT% |
                    // RATE/VALUE) rather than one row of 8 flat columns.
                    // Top line (SN/ITEM/QTY/RATE) is normal weight, bottom
                    // line (UNIT/VAT %/VALUE) is bold - same for header and
                    // every item row. The dotted rule sits between the two
                    // header lines, not below both.
                    itemTableRow('SN', 'ITEM', 'QTY', 'RATE', fontSize: 8.5),
                    pw.Row(
                      children: [
                        // Empty placeholder matching the SN column's own
                        // flex share, so the dotted rule starts under ITEM
                        // instead of under SN.
                        pw.Expanded(flex: 10, child: pw.SizedBox()),
                        pw.Expanded(flex: 78, child: dots()),
                      ],
                    ),
                    unitVatValueRow(
                      'UNIT',
                      'VAT %',
                      // Forced onto 2 lines (heading only) to match the
                      // reference exactly, regardless of column width.
                      // Right-aligned (not centered) so it lines up with
                      // RATE above and the right-aligned numbers below.
                      'VALUE\n(AED)',
                      bold: true,
                      // Smaller than the top header line (fontSize 8.5),
                      // matching the same reduction applied to the value
                      // rows' second line.
                      fontSize: 7.5,
                    ),
                    pw.Divider(thickness: 0.75),
                    pw.SizedBox(height: 2),
                    for (var item in saleItems.asMap().entries) ...[
                      itemTableRow(
                        '${item.key + 1}',
                        item.value.itemName,
                        item.value.itemQuantity,
                        formatAmountInvoice(item.value.itemPrice.toString()),
                        // Item name starts closer to the SN value here
                        // (header keeps its own default spacing). QTY's
                        // own flex is left at the shared default so its
                        // value stays centered under the "QTY" heading.
                        col1Flex: 0.6,
                        col2Flex: 6.0,
                        // Matches the header's own top-line font size.
                        fontSize: 7.5,
                        // Pulls QTY's rendered value a few points closer to
                        // ITEM, purely visually - QTY's column itself is
                        // untouched, so it stays exactly where the header
                        // has it.
                        col3LeftShift: -6,
                      ),
                      pw.SizedBox(height: 2),
                      unitVatValueRow(
                        item.value.itemUnit,
                        _selectedvatledger != 'Not Applicable'
                            ? '${vatperc.toStringAsFixed(vatperc.truncateToDouble() == vatperc ? 0 : 2)}%'
                            : '0%',
                        formatAmountInvoice(item.value.itemAmount.toString()),
                        bold: true,
                        // Matches the header's own second-line font size.
                        fontSize: 7.5,
                      ),
                      pw.SizedBox(height: 6),
                    ],
                    // Small gap before the totals, matching the reference's
                    // handful of blank lines - not the large fixed filler
                    // used elsewhere for thermal-printer last-row padding.
                    pw.SizedBox(height: 24),
                    spaceBetweenLine(
                      'Taxable Value (AED)',
                      formatAmountInvoice(totalPriceOfItems.toString()),
                      bold: false,
                    ),
                    pw.SizedBox(height: 4),
                    spaceBetweenLine(
                      'VAT (${vatperc.toStringAsFixed(vatperc.truncateToDouble() == vatperc ? 0 : 2)}%)',
                      formatAmountInvoice(totalVatAmount.toString()),
                      bold: false,
                    ),
                    pw.SizedBox(height: 4),
                    pw.Divider(thickness: 1),
                    spaceBetweenLine(
                      'TOTAL Incl. VAT (AED)',
                      formatAmountInvoice(roundedtotalAmount.toString()),
                    ),
                    pw.SizedBox(height: 8),
                    pw.RichText(
                      text: pw.TextSpan(
                        children: [
                          pw.TextSpan(
                            text: 'Amount in Words: ',
                            style: pw.TextStyle(
                              fontSize: 9,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                          pw.TextSpan(
                            text: convertAmountToWords(roundedtotalAmount),
                            style: pw.TextStyle(fontSize: 9),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 10),
              spaceBetweenLine('Delivered by:', cleanOrNotAvailable(name)),
              pw.SizedBox(height: 2),
              spaceBetweenLine('Vehicle:', cleanOrNotAvailable(vehicleName)),
              pw.SizedBox(height: 10),
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(6),
                decoration: pw.BoxDecoration(border: pw.Border.all(width: 1)),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Text(
                          'CUSTOMER SIGNATURE',
                          style: pw.TextStyle(
                            fontSize: 8,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.Text(
                          'توقيع العميل',
                          textDirection: pw.TextDirection.rtl,
                          style: pw.TextStyle(fontSize: 8, font: arabicFont),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 6),
                    pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        // Shows the receiver's captured on-screen signature
                        // when available, otherwise a blank box for the
                        // customer's physical signature/stamp.
                        receiverSignatureBytes != null
                            ? pw.Container(
                                width: 60,
                                height: 60,
                                decoration: pw.BoxDecoration(
                                  border: pw.Border.all(width: 1),
                                ),
                                child: pw.Image(
                                  pw.MemoryImage(receiverSignatureBytes!),
                                  fit: pw.BoxFit.contain,
                                ),
                              )
                            : pw.Container(
                                width: 60,
                                height: 60,
                                decoration: pw.BoxDecoration(
                                  border: pw.Border.all(width: 1),
                                ),
                              ),
                        pw.SizedBox(width: 8),
                        pw.Expanded(
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(
                                'Name: ${receiverNameController.text.trim()}',
                                style: pw.TextStyle(
                                  fontSize: 8,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                              pw.SizedBox(height: 20),
                              pw.Text(
                                'Phone: ${receiverMobileController.text.trim()}',
                                style: pw.TextStyle(
                                  fontSize: 8,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 10),
              pw.Text(
                "This document doesn't serve as payment proof",
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(fontSize: 9),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'Please request and maintain separate receipt as a proof of payment',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(fontSize: 9),
              ),
              pw.SizedBox(height: 8),
              pw.Text(
                'Thank you for your business!',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          );
        },
      ),
    );

    final pdfData = await pdf.save();
    final formattedDate =
        "${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}";
    final dir = await getApplicationDocumentsDirectory();
    final filePath = '${dir.path}/SaleInvoice_$formattedDate.pdf';
    final file = File(filePath);
    await file.writeAsBytes(pdfData);

    // UniGas is direct-print only - no share sheet. Reset always runs,
    // even if the print flow itself throws (e.g. no printer available,
    // user cancels, raster/platform error) - otherwise a failed/aborted
    // print silently leaves the form filled with no way to know why.
    try {
      await printUniGasPdf(
        context,
        pdfData,
        documentName: 'SaleInvoice_$formattedDate',
      );
    } catch (e) {
      debugPrint('UNIGAS TAX INVOICE PRINT ERROR: $e');
    } finally {
      _resetSalesInvoiceFormAfterPrint();
    }
  }

  // Drops focus before a form reset that clears _partyLedgerController's
  // text. A single unfocus() isn't enough here: when this runs right after
  // Navigator.pop(context) closes the success dialog, Flutter's own route
  // focus-restoration (which reassigns focus back to whatever had it
  // before the dialog opened - often the Party Ledger field) runs on the
  // next frame, AFTER our synchronous unfocus() call, silently re-focusing
  // the field and reopening its suggestions overlay. Unfocusing again in a
  // post-frame callback wins that race.
  void _dropFocusBeforeReset() {
    FocusScope.of(context).requestFocus(FocusNode());
    // Whatever closes after this (a dialog's Navigator.pop, or the native
    // print sheet from printUniGasPdf) can hand focus back to the
    // previously-focused field on the NEXT frame, after this synchronous
    // call already ran - so it has to be unfocused again once that frame
    // lands to actually win the race.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        FocusScope.of(context).requestFocus(FocusNode());
      }
    });
  }

  // Mirrors showSalesInvoiceDialog's "No, Thanks" reset - used after the
  // UniGas direct-print flow, which skips that dialog entirely.
  void _resetSalesInvoiceFormAfterPrint() {
    _dropFocusBeforeReset();

    setState(() {
      controller_narration.clear();
      controller_refno.clear();
      _textFieldFocusNodeNarration.unfocus();

      saledate = DateTime.now();
      saledatestring = _dateFormat.format(saledate);
      saledatetxt = formatlastsaledate(saledatestring);
      _dateController.text = saledatetxt;

      // Reference Date resets to the voucher date itself, same as the
      // screen-open default.
      refdate = saledate;
      refdatestring = saledatestring;
      refdatetxt = saledatetxt;
      _refdateController.text = saledatetxt;

      fetchvchnos(_selectedvchtypename);

      _selectedpartyledger = null;
      _partyLedgerController.clear();

      receiverNameController.clear();
      receiverMobileController.clear();
      receiverSignatureBytes = null;

      _selectedledger = ledgerdata.isNotEmpty ? ledgerdata[0]['name'] : null;
      _selectedvatledger = _defaultVatLedger();

      _selecteditem = '${itemdata[0]['name']}';
      _itemController.text = _selecteditem;

      if (locationsdata.isNotEmpty) {
        selectedLocation = locationsdata[0];
        isVisibleLocation = true;
      } else {
        isVisibleLocation = false;
      }

      _updateUnitDropdown(_selecteditem);

      saleItems.clear();
      ledgerEntries.clear();

      totalPriceOfItems = 0.0;
      totalAmountOfLedgers = 0.0;
      totalVatAmount = 0.0;

      controller_vatamt.clear();
      controller_totalamt.clear();

      isVisibleItemHeading = false;
      isVisibleLedgerHeading = false;

      _isFocused_vchno = false;
      _isFocused_item = false;
      _isFocused_unit = false;
      _isFocused_ledger = false;
      _isFocused_narration = false;
      _isFocused_totalamt = false;
      _isFocused_vatamt = false;
    });
  }

  /*Future<void> generateInvoicePDF(String trn, String address, String emirate, String country) async {
    final font = pw.Font.ttf(await rootBundle.load("assets/fonts/NotoSans.ttf"));
    final pdf = pw.Document();

    int totalQuantity = 0;
    double totalitemAmount = 0;
    for (var item in saleItems) {
      int qty_int = int.tryParse(item.itemQuantity) ?? 0;
      totalQuantity += qty_int;
      totalitemAmount += item.itemAmount;
    }

    // 🧾 Build PDF
    pdf.addPage(
      pw.Page(
        build: (pw.Context context) {
          return pw.Stack(
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Header(
                    level: 0,
                    decoration: const pw.BoxDecoration(
                      border: pw.Border(bottom: pw.BorderSide.none),
                    ),
                    child: pw.Center(
                      child: pw.Text(
                        'Tax Invoice',
                        textAlign: pw.TextAlign.center,
                        style: pw.TextStyle(fontSize: 18),
                      ),
                    ),
                  ),
                  pw.SizedBox(height: 8),
                  pw.Text(
                    company ?? '',
                    style: pw.TextStyle(
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Text(
                    'Party: ${_selectedpartyledger ?? "N/A"}',
                    style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
                  ),
                  if (address.isNotEmpty && address != "null")
                    pw.Text('Address: $address', style: pw.TextStyle(fontSize: 11)),
                  if (emirate.isNotEmpty && emirate != "null")
                    pw.Text('Emirate: $emirate', style: pw.TextStyle(fontSize: 11)),
                  if (country.isNotEmpty && country != "null")
                    pw.Text('Country: $country', style: pw.TextStyle(fontSize: 11)),
                  if (trn.isNotEmpty && trn != "null")
                    pw.Text('TRN: $trn', style: pw.TextStyle(fontSize: 11)),
                  pw.SizedBox(height: 10),

                  pw.Table.fromTextArray(
                    border: pw.TableBorder.all(width: 1),
                    headerDecoration: pw.BoxDecoration(color: PdfColors.grey300),
                    headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: font),
                    cellStyle: pw.TextStyle(fontSize: 10, font: font), // ✅ Use your font here too
                    headers: ['Sr No', 'Item', 'Qty', 'Rate', 'Amount'],
                    data: [
                      for (int i = 0; i < saleItems.length; i++)
                        [
                          (i + 1).toString(),
                          saleItems[i].itemName,
                          saleItems[i].itemQuantity,
                          formatAmountInvoice(saleItems[i].itemPrice.toString()),
                          formatAmountInvoice(saleItems[i].itemAmount.toString()),
                        ],
                    ],
                  ),

                  pw.SizedBox(height: 10),

                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('Total Quantity: $totalQuantity',
                          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                      pw.Text(
                          'Total Amount: ${formatAmountInvoice(totalitemAmount.toString())}',
                          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                    ],
                  ),

                  pw.SizedBox(height: 20),
                  pw.Text(
                    'This is a system-generated document',
                    style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
                  ),
                ],
              ),
              pw.Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(5),
                  alignment: pw.Alignment.center,
                  child: pw.Text(
                    'Created by https://tallyuae.ae/',
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(
                      fontSize: 10,
                      color: PdfColor.fromInt(0xFFCCCCCC),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );

    // 🗂 Save to temp file
    final pdfData = await pdf.save();
    final tempDir = await getTemporaryDirectory();
    final tempFilePath =
        '${tempDir.path}/SaleInvoice_${_selectedpartyledger ?? "Unknown"}.pdf';
    final file = File(tempFilePath);
    await file.writeAsBytes(pdfData);

    // ✅ Share using ShareXFiles (modern API)
    final xfile = XFile(tempFilePath);
    await Share.shareXFiles(
      [xfile],
      text: 'Sharing Sale Invoice for $_selectedpartyledger',
    );

    // ♻️ Reset all UI fields after sharing
    setState(() {
      controller_narration.clear();
      controller_refno.clear();

      _textFieldFocusNodeNarration.unfocus();

      saledate = DateTime.now();
      saledatestring = _dateFormat.format(saledate);
      _dateController.text = formatlastsaledate(saledatestring);

      refdate = DateTime.now();
      refdatestring = _dateFormat.format(refdate);
      _refdateController.text = formatlastsaledate(refdatestring);

      _selectedvchtypename = vchtypenamedata[0];
      fetchvchnos(_selectedvchtypename);
      _selectedpartyledger = partyledgerdata[0];
      _partyLedgerController.text = _selectedpartyledger;
      _selectedsalesledger = salesledger_data[0];
      _selectedledger = ledgerdata.isNotEmpty ? ledgerdata[0]['name'] : null;
      _selectedvatledger = _defaultVatLedger();
      _selecteditem = '${itemdata[0]['name']}';

      if (locationsdata.isNotEmpty) {
        selectedLocation = locationsdata[0];
        isVisibleLocation = true;
      } else {
        isVisibleLocation = false;
      }
      _updateUnitDropdown(_selecteditem);

      saleItems.clear();
      ledgerEntries.clear();

      totalPriceOfItems = saleItems.fold(0.0, (sum, item) {
        return sum + (item.itemPrice * double.parse(item.itemQuantity));
      });

      totalAmountOfLedgers = ledgerEntries.fold(0.0, (sum, entry) {
        return sum + entry.ledgerAmount;
      });

      if (_selectedvatledger != 'Not Applicable') {
        double vatPerc = vatperc / 100;
        itemsVatAmount = totalPriceOfItems * vatPerc;
        totalVatAmount = itemsVatAmount + ledgerVatAmount;
        roundedtotalVatAmount = double.parse(totalVatAmount.toStringAsFixed(decimal!));
        NumberFormat formatter = NumberFormat('#,##0.${'0' * decimal!}', 'en_US');
        controller_vatamt.text = formatter.format(roundedtotalVatAmount);
      } else {
        totalVatAmount = 0;
        roundedtotalVatAmount = double.parse(totalVatAmount.toStringAsFixed(decimal!));
        NumberFormat formatter = NumberFormat('#,##0.${'0' * decimal!}', 'en_US');
        controller_vatamt.text = formatter.format(roundedtotalVatAmount);
      }

      isVisibleItemHeading = saleItems.isNotEmpty;
      totalAmountForVatAppEntries = ledgerEntries
          .where((entry) => entry.vatApp)
          .fold(0.0, (sum, entry) => sum + entry.ledgerAmount);

      if (_selectedvatledger != 'Not Applicable') {
        double vatPerc = vatperc / 100;
        ledgerVatAmount = totalAmountForVatAppEntries * vatPerc;
        totalVatAmount = itemsVatAmount + ledgerVatAmount;
        roundedtotalVatAmount = double.parse(totalVatAmount.toStringAsFixed(decimal!));
        NumberFormat formatter = NumberFormat('#,##0.${'0' * decimal!}', 'en_US');
        controller_vatamt.text = formatter.format(roundedtotalVatAmount);
      } else {
        totalVatAmount = 0;
        roundedtotalVatAmount = double.parse(totalVatAmount.toStringAsFixed(decimal!));
        NumberFormat formatter = NumberFormat('#,##0.${'0' * decimal!}', 'en_US');
        controller_vatamt.text = formatter.format(roundedtotalVatAmount);
      }

      isVisibleLedgerHeading = ledgerEntries.isNotEmpty;
      totalAmount = totalPriceOfItems + totalAmountOfLedgers + totalVatAmount;
      roundedtotalAmount = double.parse(totalAmount.toStringAsFixed(decimal!));
      NumberFormat formatter = NumberFormat('#,##0.${'0' * decimal!}', 'en_US');
      controller_totalamt.text = formatter.format(roundedtotalAmount);

      _isFocused_vchno = false;
      _isFocused_item = false;
      _isFocused_unit = false;
      _isFocused_ledger = false;
      _isFocused_narration = false;
      _isFocused_totalamt = false;
      _isFocused_vatamt = false;
    });
  }*/

  String getCurrencySymbol(String currencyCode) {
    NumberFormat format;
    // Number/currency formatting is intentionally locale-independent -
    // amounts must show Western digits and standard symbol placement
    // regardless of the app's display language (Arabic UI still shows
    // '1,234.50 AED', not Arabic-Indic digits), matching how real
    // finance apps in the region behave.
    Locale locale = const Locale('en');

    try {
      if (currencyCode == 'INR' ||
          currencyCode == 'EUR' ||
          currencyCode == 'PKR' ||
          currencyCode == 'USD') {
        format = new NumberFormat.simpleCurrency(
          locale: locale.toString(),
          name: currencyCode,
        );
      } else {
        format = new NumberFormat.currency(
          locale: locale.toString(),
          name: currencyCode,
        );
      }
      return format.currencySymbol;
    } catch (e) {
      return 'AED';
    }
  }

  // Currency-symbol-aware value display - renders the Dirham glyph for AED
  // instead of the literal "AED" text that getCurrencySymbol() falls back
  // to (there's no distinct AED symbol glyph in the standard locale data).
  Widget _currencyValueWidget(String numberText, TextStyle style) {
    return currencyAmountText(
      currencyCode: currencycode,
      symbol: getCurrencySymbol(currencycode),
      amountText: numberText,
      style: style,
      textAlign: TextAlign.right,
      maxLines: 2,
      overflow: TextOverflow.visible,
    );
  }

  Future<void> saveEntry() async {
    // ❌ Prevent save if Party Ledger not selected
    if (_selectedpartyledger == null ||
        _selectedpartyledger.toString().trim().isEmpty) {
      showAppMessage(context, "Please select Party Ledger");

      return;
    }

    // ❌ Prevent save if Reference Date is somehow empty (it always
    // defaults to the voucher date, but this guards against that state
    // ever slipping through).
    if (refdatestring.trim().isEmpty) {
      showAppMessage(context, "Please select Reference Date");

      return;
    }

    // UniGas only: Receiver Name is mandatory before saving.
    if (isUniGasSerial && receiverNameController.text.trim().isEmpty) {
      showAppMessage(context, "Please enter the Receiver's Name before saving");

      return;
    }

    if (saleItems.isEmpty) {
      showAppMessage(context, 'Atleast add 1 item');
    } else {
      setState(() {
        _isLoading = true;
      });
      String narrationValue = controller_narration.text.trim();
      String vchnoValue = _vchnoController.text;

      String refnoValue = controller_refno.text;
      roundedtotalAmount = double.parse(totalAmount.toStringAsFixed(decimal!));

      // UniGas posts BILLALLOCATIONS.LIST on the party ledger entry
      // (matching their reference JSON format); every other serial keeps
      // the existing format unchanged (no bill-wise tracking).
      final String currentSerialNo = serial_no?.trim() ?? '';
      final bool isUniGasSerial = vanSalesSerialNo.contains(currentSerialNo);

      double totalItemAmount = 0.0;

      for (SaleItem item in saleItems) {
        totalItemAmount += double.parse(
          item.itemAmount.toStringAsFixed(decimal!),
        ); // calculating item amounts total
      }

      for (var saleItem in saleItems) {
        // making sales ledger
        if (saleItem.accountingAllocationList.isEmpty) {
          saleItem.accountingAllocationList = {
            "LEDGERNAME": _selectedsalesledger,
            "AMOUNT": saleItem.itemAmount.toStringAsFixed(decimal!),
            "ISDEEMEDPOSITIVE": "No",
          };
        }
      }

      // ---- tally-api voucher-entries payload ------------------------
      //
      // Legacy posted a Tally-XML-shaped body (LEDGERENTRIES.LIST/
      // INVENTORYENTRIES.LIST/BILLALLOCATIONS.LIST/ACCOUNTINGALLOCATIONS.
      // LIST, ISDEEMEDPOSITIVE strings, compound "12.00/Nos" RATE strings)
      // to `POST /api/entry/create/:company/:serial`. tally-api's
      // voucher-entries endpoint (`voucherEntrySchema`, see
      // voucher_entry_repository.dart) is flatter and numeric-masterId-
      // keyed instead - every field below carries the same value legacy's
      // payload used; see the inline comments for anything with no direct
      // equivalent.
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
        setState(() {
          _isLoading = false;
        });
        showAppMessage(
          context,
          'Could not resolve voucher type/party ledger/sales ledger/currency - please reload and try again.',
        );
        return;
      }

      // Legacy encoded debit/credit via a signed AMOUNT plus a redundant
      // "ISDEEMEDPOSITIVE" string; the new schema separates that into a
      // plain positive `amount` and a single `isDebit` boolean.
      final List<Map<String, dynamic>> entryLedgers = [];

      final List<Map<String, dynamic>> partyBillAllocations = [];
      if (isUniGasSerial) {
        // Party's "credit_period" (e.g. "30 Days") -> due date = voucher
        // date + that many days. Falls back to just the voucher date
        // itself when the party has no credit period set.
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

        // Use the Reference No./Date as the bill name/date when the user
        // entered a reference (that's what the customer will quote back
        // when settling this invoice) - falls back to the voucher
        // number/date otherwise.
        final bool hasRefNo = refnoValue.trim().isNotEmpty;
        final String billName = hasRefNo ? refnoValue.trim() : vchnoValue;
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
        debugPrint('Sales New Ref bill allocation -> $partyBillAllocations');
      }

      entryLedgers.add({
        'ledgerMasterId': partyLedgerMasterId,
        'amount': roundedtotalAmount,
        'isDebit': true,
        'isPartyLedger': true,
        // UniGas's reference JSON expects a bill-wise allocation on the
        // party ledger entry - always "New Ref" (no "On Account"), using
        // the voucher number/reference itself as the bill reference name.
        if (partyBillAllocations.isNotEmpty)
          'billAllocations': partyBillAllocations,
      });

      // Aggregate sales-ledger credit entry. Legacy never posted this as
      // its own LEDGERENTRIES.LIST row - Tally's XML engine derives the
      // accounting posting from each item's own ACCOUNTINGALLOCATIONS.LIST
      // instead. The new schema has no equivalent nested per-item ledger-
      // allocation list (`inventoryEntries[].ledgerMasterId` is a single
      // ledger reference, not a list of allocations), so this one
      // aggregate row is added here to keep the entry double-entry-
      // complete under the new shape.
      entryLedgers.add({
        'ledgerMasterId': salesLedgerMasterId,
        'amount': totalItemAmount,
        'isDebit': false,
        'isPartyLedger': false,
      });

      // Manual "other" ledger entries (freight/discount/etc). Legacy also
      // sent "VATAPPLICABLE" on these - entryLedgerEntryRowSchema has no
      // such field (it was only ever an input to this screen's own VAT
      // total calculation, not something legacy's backend needed back), so
      // it's dropped here. Any entry whose ledger name doesn't resolve to
      // a masterId (shouldn't normally happen - names come from the same
      // loadData() lists) is skipped rather than sent broken.
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
          debugPrint(
            'Skipping inventory entry for "${item.itemName}" - could not '
            'resolve stockItemMasterId/unitMasterId',
          );
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
                // Tally's own default batch name for a godown-only
                // (non-lot-tracked) allocation - these items aren't real
                // Tally batches, but entryBatchAllocationRowSchema still
                // requires a non-empty batchName.
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
        'narration': narrationValue,
        if (refnoValue.trim().isNotEmpty) 'reference': refnoValue.trim(),
        'referenceDate': _isoDate(parseCompactDate(refdatestring)),
        if (vchnoValue.trim().isNotEmpty) 'voucherNumber': vchnoValue.trim(),
        'ledgerEntries': entryLedgers,
        'inventoryEntries': entryInventory,
      };

      // Plain print() doesn't chunk long strings - Android/iOS truncate
      // each log line at a fixed byte length, clipping this JSON mid-way
      // for any entry with more than a couple items. debugPrint's
      // wrapWidth splits it into multiple lines first, so the full
      // payload actually shows up in the console.
      debugPrint(jsonEncode(voucherEntryBody), wrapWidth: 1024);

      try {
        await VoucherEntryRepository.instance.create(voucherEntryBody);
        loadLedgerData();
      } on ApiException catch (e) {
        setState(() {
          _isLoading = false;
        });
        showAppMessage(context, e.message);
      } catch (e) {
        setState(() {
          _isLoading = false;
        });
        debugPrint('SalesRegistration saveEntry failed: $e');
        showAppMessage(context, 'Something went wrong!!!');
      }
    }
    setState(() {
      _isLoading = false;
    });
  }

  void showSalesInvoiceDialog(
    BuildContext context,
    String trn,
    String address,
    String emirate,
    String country,
  ) {
    // UniGas prints directly - no "created successfully / Share" dialog.
    if (isUniGasSerial) {
      generateInvoicePDF(trn, address, emirate, country);
      return;
    }

    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: "SalesInvoice",
      barrierColor: Colors.black.withValues(alpha: 0.35),
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: MediaQuery.of(context).size.width * 0.85,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(28), // 🔥 more rounded
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.green, width: 4.0),
                    ),
                    child: const Icon(
                      Icons.done,
                      size: 40,
                      color: Colors.green,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Do you want to share the sales invoice?',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(fontSize: 18.0),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Sales Invoice Created Successfully',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: 16.0,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 12,
                    runSpacing: 12,
                    children: <Widget>[
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _dropFocusBeforeReset();
                          setState(() {
                            controller_narration.clear();
                            controller_refno.clear();
                            _textFieldFocusNodeNarration.unfocus();

                            saledate = DateTime.now();
                            saledatestring = _dateFormat.format(saledate);
                            saledatetxt = formatlastsaledate(saledatestring);
                            _dateController.text = saledatetxt;

                            refdate = DateTime.now();
                            refdatestring = _dateFormat.format(refdate);
                            refdatetxt = formatlastsaledate(refdatestring);
                            _refdateController.text = refdatetxt;

                            fetchvchnos(_selectedvchtypename);

                            _selectedpartyledger = null;
                            _partyLedgerController.clear();

                            _selectedledger = ledgerdata.isNotEmpty
                                ? ledgerdata[0]['name']
                                : null;
                            _selectedvatledger = _defaultVatLedger();

                            _selecteditem = '${itemdata[0]['name']}';
                            _itemController.text = _selecteditem;

                            if (locationsdata.isNotEmpty) {
                              selectedLocation = locationsdata[0];
                              isVisibleLocation = true;
                            } else {
                              isVisibleLocation = false;
                            }

                            _updateUnitDropdown(_selecteditem);

                            saleItems.clear();
                            ledgerEntries.clear();

                            totalPriceOfItems = 0.0;
                            totalAmountOfLedgers = 0.0;
                            totalVatAmount = 0.0;

                            controller_vatamt.clear();
                            controller_totalamt.clear();

                            isVisibleItemHeading = false;
                            isVisibleLedgerHeading = false;

                            _isFocused_vchno = false;
                            _isFocused_item = false;
                            _isFocused_unit = false;
                            _isFocused_ledger = false;
                            _isFocused_narration = false;
                            _isFocused_totalamt = false;
                            _isFocused_vatamt = false;
                          });
                        },
                        icon: const Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: Colors.white,
                        ),
                        label: Text(
                          'No, Thanks',
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          elevation: 4,
                          shadowColor: Colors.redAccent.withOpacity(0.3),
                        ),
                      ),

                      ElevatedButton.icon(
                        onPressed: () async {
                          Navigator.pop(context);
                          await generateInvoicePDF(
                            trn,
                            address,
                            emirate,
                            country,
                          );
                        },
                        icon: const Icon(
                          Icons.share_rounded,
                          size: 18,
                          color: Colors.white,
                        ),
                        label: Text(
                          'Share',
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: app_color,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          elevation: 4,
                          shadowColor: app_color.withOpacity(0.3),
                        ),
                      ),
                    ],
                  ),

                  /*Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          setState(() {
                            controller_narration.clear();
                            controller_refno.clear();
                            _textFieldFocusNodeNarration.unfocus();

                            saledate = DateTime.now();
                            saledatestring = _dateFormat.format(saledate);
                            saledatetxt = formatlastsaledate(saledatestring);
                            _dateController.text = saledatetxt;

                            refdate = DateTime.now();
                            refdatestring = _dateFormat.format(refdate);
                            refdatetxt = formatlastsaledate(refdatestring);
                            _refdateController.text = refdatetxt;

                            //_selectedvchtypename = vchtypenamedata[0];
                            fetchvchnos(_selectedvchtypename);
                            _selectedpartyledger = null;
                            _partyLedgerController.clear();
                            // _selectedsalesledger = salesledger_data[0];
                            _selectedledger = ledgerdata.isNotEmpty ? ledgerdata[0]['name'] : null;
                            _selectedvatledger = _defaultVatLedger();
                            _selecteditem = '${itemdata[0]['name']}';
                            _itemController.text = _selecteditem;

                            if (locationsdata.isNotEmpty) {
                              selectedLocation = locationsdata[0];
                              isVisibleLocation = true;
                            } else {
                              isVisibleLocation = false;
                            }

                            _updateUnitDropdown(_selecteditem);

                            saleItems.clear();
                            ledgerEntries.clear();

                            totalPriceOfItems = 0.0;
                            totalAmountOfLedgers = 0.0;
                            totalVatAmount = 0.0;
                            controller_vatamt.clear();
                            controller_totalamt.clear();

                            isVisibleItemHeading = false;
                            isVisibleLedgerHeading = false;

                            _isFocused_vchno = false;
                            _isFocused_item = false;
                            _isFocused_unit = false;
                            _isFocused_ledger = false;
                            _isFocused_narration = false;
                            _isFocused_totalamt = false;
                            _isFocused_vatamt = false;
                          });
                        },
                        icon: const Icon(Icons.close_rounded, size: 20, color: Colors.white),
                        label: Text(
                          'No, Thanks',
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          elevation: 4,
                          shadowColor: Colors.redAccent.withOpacity(0.3),
                        ),
                      ),
                      const SizedBox(width: 20),
                      ElevatedButton.icon(
                        onPressed: () async {
                          Navigator.pop(context);
                          await generateInvoicePDF(trn, address, emirate, country);
                        },
                        icon: const Icon(Icons.share_rounded, size: 20, color: Colors.white),
                        label: Text(
                          'Share',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: app_color,
                          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          elevation: 4,
                          shadowColor: app_color.withOpacity(0.3),
                        ),
                      )
                    ],
                  ),*/
                ],
              ),
            ),
          ),
        );
      },

      // 🔥 POPUP ANIMATION
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return Transform.scale(
          scale: Curves.easeOutBack.transform(animation.value),
          child: Opacity(opacity: animation.value, child: child),
        );
      },
    );
  }

  /// Replaces legacy's single `POST /api/entry/getSalesData/:company/:serial`
  /// (which server-side pre-classified everything for `"type": "sales"` -
  /// vchTypes/partyLedgers/salesLedgers/vatLedgers/otherLedgers/items/
  /// locations in one response) with tally-api's own equivalent bundle
  /// endpoint - `VoucherEntryDropdownsRepository.salesData()`
  /// (`GET .../voucher-entry-dropdowns/sales-data`) - which does the exact
  /// same server-side classification (by `GroupReservedName`/
  /// `VoucherReservedName` instead of legacy's raw Tally name strings) in
  /// one call, already scoped to this company-user's master-restrictions
  /// (Van Allocation). This replaced an earlier client-side-classification
  /// version of this method that fetched every `/ledgers`/`/groups`/
  /// `/voucher-types`/`/godowns`/stock-item list separately and
  /// re-classified them here.
  ///  - vchTypes/partyLedgers/salesLedgers/vatLedgers/otherLedgers/godowns ->
  ///    used as-is (`{masterId, name}` rows, `otherLedgers` also carries
  ///    `vatApplicable`, not currently read here).
  ///  - items -> stock items, already shaped close to what this screen's
  ///    item-picker/unit-dropdown/bulk-add code reads; reshaped one more
  ///    step by `_shapeStockItemForLegacyItemdata` into the exact legacy key
  ///    names (`name`/`masterid`/`saleprice`/`standardprice`/`unit`/`part`)
  ///    so none of those call sites needed to change.
  ///
  /// `currencies` has no equivalent in this bundle (Sales/Receipt dropdown
  /// data is currency-agnostic) - fetched separately, same as before.
  ///
  /// `sales-data`'s `partyLedgers` rows now always include `priceLevel`/
  /// `creditPeriod` directly (added after this screen's initial migration -
  /// see tally-api's `voucher-entry-dropdowns.service.ts`), so both UniGas
  /// fields are read straight off each party ledger row below - no separate
  /// `LedgerRepository.listLedgers()` call needed any more (the earlier,
  /// UniGas-only extra fetch this doc comment used to describe is gone).
  /// This closes the price-level UX regression flagged when this screen was
  /// first migrated: `fetchPriceLevelDetailsForSelectedItem`/
  /// `_resolvePriceLevelRateForItem` now resolve a real per-party price
  /// level again instead of always falling through to the "no price level"
  /// branch.
  Future<void> loadData() async {
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

    setState(() {
      _isLoading = true;
    });

    // Van Allocation prefill/lock now comes from tally-api's
    // master-restrictions feature instead of the legacy 'spectra_allocations'
    // SharedPreferences blob: the /godowns and /voucher-types data fetched
    // below are already filtered server-side to this company-user's GODOWN /
    // VOUCHER_TYPE restriction - a single row back means this company-user
    // is locked to one vehicle/voucher type; unrestricted returns every row.
    try {
      final String currentSerialNo = serial_no?.trim() ?? '';
      final bool isUniGasSerial = vanSalesSerialNo.contains(currentSerialNo);

      debugPrint('sales loadData serial_no -> $currentSerialNo');
      debugPrint('sales loadData isUniGasSerial -> $isUniGasSerial');

      final results = await Future.wait([
        VoucherEntryDropdownsRepository.instance.salesData(),
        fetchAllPages(
          (page) => _tallyApiClient.getForCompany(
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

      /// Trims a raw `priceLevel`/`creditPeriod` string from `partyLedgers`,
      /// collapsing blank to `null` - matches the old
      /// `creditPeriodByLedgerName` trimming behavior this replaces.
      String? trimOrNull(String? raw) =>
          (raw?.trim().isEmpty ?? true) ? null : raw!.trim();

      String? voucherTypeToFetch;

      setState(() {
        vchtypenamedata = [for (final vt in voucherTypes) vt['name'] as String];
        _voucherTypeMasterIdByName
          ..clear()
          ..addAll({
            for (final vt in voucherTypes)
              vt['name'] as String: vt['masterId'] as int,
          });

        // Van Allocation: tally-api's master-restrictions feature already
        // filters this company-user's SALES voucher types server-side - a
        // single one back means this company-user is locked to one vehicle's
        // voucher type.
        isVoucherTypeLocked = vchtypenamedata.length == 1;
        _selectedvchtypename = vchtypenamedata.isNotEmpty
            ? vchtypenamedata[0]
            : null;

        voucherTypeToFetch = _selectedvchtypename;

        // The dropdown bundle above already scopes every list to the
        // dropdowns this screen actually offers - merge them all into one
        // name->masterId map for saveEntry()'s lookups (covers every ledger
        // reachable through any picker on this screen).
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

        if (isUniGasSerial) {
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

        // Sales ledger soft default (not master-restriction-gated): the one
        // ledger under a Group whose reservedName is SALES, company-wide.
        // Never locked - just a starting selection the user can still change.
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

        // "Other ledgers" (the manual Ledger Entry add list) - the bundle's
        // own `otherLedgers` classification (see the dropdowns service's
        // doc-comment: SALES/expense/income/asset/liability groups).
        ledgerdata = [
          for (final l in otherLedgersRaw) {'name': l['name']},
        ];

        _selectedledger = ledgerdata.isNotEmpty
            ? ledgerdata[0]['name']
            : null;

        _selectedvatledger = _defaultVatLedger();

        itemdata = [
          for (final item in stockItems) _shapeStockItemForLegacyItemdata(item),
        ];

        if (itemdata.isNotEmpty) {
          _selecteditem = '${itemdata[0]['name']}';
          _itemController.text = _selecteditem ?? '';
          _updateUnitDropdown(_selecteditem);
        }

        locationsdata = [for (final g in godowns) g['name'] as String];
        _godownMasterIdByName
          ..clear()
          ..addAll({
            for (final g in godowns) g['name'] as String: g['masterId'] as int,
          });

        if (locationsdata.isNotEmpty) {
          selectedLocation = locationsdata[0];
          isVisibleLocation = true;
        } else {
          isVisibleLocation = false;
        }

        // Exactly one server-side master-restriction-filtered godown means
        // this company-user is locked to one vehicle; otherwise
        // (unrestricted, or none synced yet) leave it a normal editable
        // picker with no default lock.
        isGodownLocked = locationsdata.length == 1;

        // Resolve the voucher-entry currency once here - matches the
        // company's configured `currencycode` (prefs), falling back to
        // whatever currency tally-api returns first (every Tally company
        // has at least a base currency).
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
        fetchvchnos(voucherTypeToFetch!);
      }
    } on ApiException catch (e) {
      showAppMessage(context, e.message);
    } catch (e) {
      debugPrint('SalesRegistration loadData failed: $e');
      showAppMessage(context, 'Something went wrong!!!');
    }

    setState(() {
      _isLoading = false;
    });
  }

  /// Reshapes one tally-api stock-items row into the legacy key names this
  /// screen's item picker/unit-dropdown/bulk-add code already reads
  /// (`name`/`masterid`/`saleprice`/`standardprice`/`unit`/`part`) - see
  /// loadData()'s doc comment.
  Map<String, dynamic> _shapeStockItemForLegacyItemdata(
    Map<String, dynamic> item,
  ) {
    final int? baseUnitMasterId = item['baseUnitMasterId'] as int?;
    final String? baseUnitSymbol = (item['baseUnitSymbol'] as String?)
        ?.trim();
    final int? additionalUnitMasterId = item['additionalUnitMasterId'] as int?;
    final String? additionalUnitSymbol =
        (item['additionalUnitSymbol'] as String?)?.trim();
    // "1 additionalUnit = denominator baseUnits" (see Items.dart's own
    // qty-conversion comment for this same field) - saleprice/standardprice
    // below are priced per base unit, so the additional unit's rate
    // multiplier is that same denominator.
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
      // Every real Tally stock item has at least a base unit - this only
      // guards `_updateUnitDropdown()`'s `unitdata[0]` access for the
      // unexpected case of a completely unresolved unit.
      units.add({'name': '', 'multiplier': '1', 'masterId': null});
    }

    return {
      'name': item['name'],
      'masterid': item['masterId'],
      'saleprice': item['lastSalePrice']?.toString() ?? 'null',
      // tally-api's own field name (misspelled server-side, see Items.dart).
      'standardprice': item['stardardPrice']?.toString() ?? 'null',
      'unit': units,
      'part': (item['partNo'] as List?)?.cast<String>().join(', ') ?? '',
    };
  }

  /*Future<void> loadData() async {
    vchtypenamedata.clear();
    itemdata.clear();
    salesledger_data.clear();
    partyledgerdata.clear();
    vatledgerdata.clear();

    ledgerdata.clear();
    locationsdata.clear();

    setState(() {
      _isLoading = true;
    });

    try {
      final url = Uri.parse(HttpURL_loadData!);

      Map<String, String> headers = {
        'Authorization': 'Bearer $token',
        "Content-Type": "application/json",
      };

      final String currentSerialNo = serial_no?.trim() ?? '';
      final bool isUniGasSerial = vanSalesSerialNo.contains(currentSerialNo);

      String godownName = '';
      String? allocationString = prefs.getString('spectra_allocations');

      if (isUniGasSerial &&
          allocationString != null &&
          allocationString.isNotEmpty) {
        try {
          List<dynamic> allocations = jsonDecode(allocationString);

          if (allocations.isNotEmpty) {
            godownName = allocations.first['godown']?.toString() ?? '';
          }
        } catch (e) {
          debugPrint('allocation decode error -> $e');
        }
      }

      var body = jsonEncode({
        "type": "sales",
        if (isUniGasSerial && godownName.isNotEmpty)
          "godownName": godownName,
      });

      debugPrint('sales loadData serial_no -> $currentSerialNo');
      debugPrint('sales loadData isUniGasSerial -> $isUniGasSerial');
      debugPrint('sales loadData godownName -> $godownName');
      debugPrint('sales loadData body -> $body');

      final response = await http.post(
        url,
        headers: headers,
        body: body,
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> jsonResponse = json.decode(utf8.decode(response.bodyBytes));

        debugPrint('sales loadData response -> $jsonResponse');

        setState(() {
          vchtypenamedata = List<String>.from(
            (jsonResponse["vchTypes"] ?? [])
                .where((e) => e != null)
                .map((e) => e.toString()),
          );

          _selectedvchtypename =
          vchtypenamedata.isNotEmpty ? vchtypenamedata[0] : null;

          fetchvchnos(_selectedvchtypename);



          if (vanSalesSerialNo.contains(currentSerialNo)) {
            partyledgerdata.clear();
            partyLedgerPriceLevelMap.clear();
            partyLedgerCreditPeriodMap.clear();

            for (var ledger in (jsonResponse["partyLedgers"] ?? [])) {
              if (ledger == null) continue;

              final String ledgerName =
                  ledger['name']?.toString().trim() ?? '';

              final dynamic rawPriceLevel = ledger['price_level'];

              final String? priceLevel = rawPriceLevel == null ||
                  rawPriceLevel.toString().trim().isEmpty ||
                  rawPriceLevel.toString().trim().toLowerCase() == 'null'
                  ? null
                  : rawPriceLevel.toString().trim();

              final dynamic rawCreditPeriod = ledger['credit_period'];
              final String? creditPeriod = rawCreditPeriod == null ||
                  rawCreditPeriod.toString().trim().isEmpty ||
                  rawCreditPeriod.toString().trim().toLowerCase() == 'null'
                  ? null
                  : rawCreditPeriod.toString().trim();

              if (ledgerName.isEmpty) continue;

              if (!partyledgerdata.contains(ledgerName)) {
                partyledgerdata.add(ledgerName);
              }

              partyLedgerPriceLevelMap[ledgerName] = priceLevel;
              partyLedgerCreditPeriodMap[ledgerName] = creditPeriod;
            }
          }
          else {
            partyledgerdata = List<String>.from(
              (jsonResponse["partyLedgers"] ?? [])
                  .where((e) => e != null)
                  .map((e) => e.toString()),
            );
          }
          partyledgerdata.sort(
            (a, b) => a.toLowerCase().compareTo(b.toLowerCase()),
          );

          // _selectedpartyledger = partyledgerdata.isNotEmpty ? partyledgerdata[0] : null;

          // _partyLedgerController.text = _selectedpartyledger ?? '';



          salesledger_data = List<String>.from(
            (jsonResponse["salesLedgers"] ?? [])
                .where((e) => e != null)
                .map((e) => e.toString()),
          );

          _selectedsalesledger =
          salesledger_data.isNotEmpty ? salesledger_data[0] : null;

          if (allocationString != null &&
              allocationString.isNotEmpty) {

            List<dynamic> allocations =
            jsonDecode(allocationString);

            if (allocations.isNotEmpty) {

              final allocation =
              allocations.first as Map<String, dynamic>;

              final savedSalesLedger =
              allocation['sales_ledger']?.toString();

              if (savedSalesLedger != null &&
                  savedSalesLedger.isNotEmpty &&
                  salesledger_data.contains(savedSalesLedger)) {

                _selectedsalesledger = savedSalesLedger;

                // LOCK DROPDOWN
                isSalesLedgerLocked = true;

              } else if (salesledger_data.isNotEmpty) {

                _selectedsalesledger = salesledger_data[0];

                isSalesLedgerLocked = false;
              }
            }
          }
          else if (salesledger_data.isNotEmpty) {

            _selectedsalesledger = salesledger_data[0];

            isSalesLedgerLocked = false;
          }

          ledgerdata = List<Map<String, dynamic>>.from(
            jsonResponse['otherLedgers'] ?? [],
          );

          _selectedledger =
          ledgerdata.isNotEmpty ? ledgerdata[0]['name'] : null;

          vatledgerdata.add('Not Applicable');
          vatledgerdata.addAll(
            List<String>.from(
              (jsonResponse["vatLedgers"] ?? [])
                  .where((e) => e != null)
                  .map((e) => e.toString()),
            ),
          );

          _selectedvatledger = _defaultVatLedger();

          itemdata = jsonResponse["items"] ?? [];

          if (itemdata.isNotEmpty) {
            _selecteditem = '${itemdata[0]['name']}';
            _itemController.text = _selecteditem;
            _updateUnitDropdown(_selecteditem);
          }

          locationsdata = List<String>.from(
            (jsonResponse['locations'] ?? [])
                .where((e) => e != null)
                .map((e) => e.toString()),
          );

          if (locationsdata.isNotEmpty) {
            selectedLocation = locationsdata[0];
            isVisibleLocation = true;
          } else {
            isVisibleLocation = false;
          }

          if (isUniGasSerial &&
              godownName.isNotEmpty &&
              locationsdata.contains(godownName)) {
            selectedLocation = godownName;
            isVisibleLocation = true;
          }

          if (allocationString != null) {
            List<dynamic> allocations = jsonDecode(allocationString);

            if (allocations.isNotEmpty) {
              final allocation = allocations.first;

              // GODOWN
              if (allocation['godown'] != null &&
                  locationsdata.contains(allocation['godown'])) {
                selectedLocation = allocation['godown'];

                isVisibleLocation = true;

              }

              // SALES LEDGER
              */ /*if (allocation['sales_ledger'] != null &&
            salesledger_data.contains(allocation['sales_ledger'])) {
          _selectedsalesledger = allocation['sales_ledger'];
        }*/ /*

              // VOUCHER TYPE
              final savedVoucherType =
              allocation['sales_voucher_type']?.toString();

              if (savedVoucherType != null &&
                  savedVoucherType.isNotEmpty &&
                  vchtypenamedata.contains(savedVoucherType)) {

                _selectedvchtypename = savedVoucherType;

                isVoucherTypeLocked = true;

                // optional if your app fetches voucher numbers on selection
                fetchvchnos(_selectedvchtypename);

              } else if (vchtypenamedata.isNotEmpty) {

                _selectedvchtypename = vchtypenamedata[0];

                isVoucherTypeLocked = false;

                fetchvchnos(_selectedvchtypename);
              }

              setState(() {});
            }
          }

        });
      } else {
        Map<String, dynamic> data = json.decode(utf8.decode(response.bodyBytes));
        String error = '';

        if (data.containsKey('error')) {
          error = data['error'];
        } else {
          error = 'Something went wrong!!!';
        }

        showAppMessage(context, error);
      }
    } catch (e) {
      print(e);
    }

    setState(() {
      _isLoading = false;
    });
  }*/

  /// Replaces legacy's `POST /api/ledger/getLedger/:company/:serial`
  /// (looked up the selected party ledger's TRN/address/state/country/
  /// mobile/email server-side). tally-api's ledger list already carries all
  /// of those fields, so this is now a local lookup against
  /// `_allLedgersCache` (populated by loadData()) instead of a network
  /// call.
  Future<void> loadLedgerData() async {
    setState(() {
      _isLoading = true;
    });

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

      setState(() {
        _selectedPartyMobile = ledger['mobileNumber']?.toString();
        _selectedPartyEmail = ledger['email']?.toString();
        showSalesInvoiceDialog(context, tinValue, address, emirate, country);
      });
    } catch (e) {
      debugPrint('SalesRegistration loadLedgerData failed: $e');
    }

    setState(() {
      _isLoading = false;
    });
  }

  /// Replaces legacy's `GET /api/entry/nos/:company/:serial` (server-side
  /// generated the next voucher number from Tally's own voucher sequence
  /// for this vchtype/date-range).
  ///
  /// Now backed by tally-api's `GET .../voucher-entries/voucher-numbers`
  /// (added after this screen's initial migration - see
  /// `VoucherEntryRepository.voucherNumbers`'s doc-comment), which unions
  /// this app's own draft `VoucherEntry` numbers with the real Tally-synced
  /// `Voucher.number`s for this vchtype/date-range - a strictly better
  /// source than the earlier client-side-only approach (fetching every
  /// `VoucherEntry` via `listAll()`), since a number already used in real
  /// Tally data is now correctly excluded from the suggestion too. The
  /// suggestion still lands in `_vchnoController` via the unchanged
  /// `generateNextVchNo`, and stays a plain editable text field the user
  /// can always override (`checkVchNoExistence` still flags a clash
  /// against this same [vchnos] list before submit).
  Future<void> fetchvchnos(String vchname) async {
    vchnos.clear();
    setState(() {
      _isLoading = true;
    });

    try {
      final int? voucherTypeMasterId = _voucherTypeMasterIdByName[vchname];

      if (voucherTypeMasterId != null) {
        final String fromParam = DateFormat('yyyy-MM-dd').format(
          parseCompactDate(startfrom),
        );
        final String toParam = DateFormat('yyyy-MM-dd').format(yearEndDate);

        vchnos = await VoucherEntryRepository.instance.voucherNumbers(
          voucherTypeMasterId: voucherTypeMasterId,
          from: fromParam,
          to: toParam,
        );
      }

      setState(() {
        // SORT first
        vchnos.sort((a, b) {
          RegExp regExp = RegExp(r'(\d+)(?!.*\d)');
          int numA = int.tryParse(regExp.firstMatch(a)?.group(0) ?? '0') ?? 0;
          int numB = int.tryParse(regExp.firstMatch(b)?.group(0) ?? '0') ?? 0;
          return numA.compareTo(numB);
        });

        debugPrint('vch nos from tally-api voucher-numbers -> $vchnos');

        // GENERATE NEXT
        String nextVch = generateNextVchNo(vchnos);

        _vchnoController.text = nextVch;
      });
    } on ApiException catch (e) {
      vchnos.clear();
      showAppMessage(context, e.message);
    } catch (e) {
      vchnos.clear();
      debugPrint('SalesRegistration fetchvchnos failed: $e');
    }

    setState(() {
      _isLoading = false;
    });
  }

  void _updateUnitDropdown(dynamic _selectedItem) {
    setState(() {
      selectedMultiplier = 0.0;
      isVisibleUnit = true;

      itemQuantityController.text = 1.toString();

      dynamic selectedItemInfo = itemdata.firstWhere(
        (item) => item["name"] == _selectedItem,
        orElse: () => null,
      );

      String salePrice = selectedItemInfo["saleprice"].toString();
      String standardPrice = selectedItemInfo["standardprice"].toString();

      /*print(selectedItemInfo);*/

      final List<dynamic> jsonList = selectedItemInfo["unit"];

      setState(() {
        unitdata = jsonList.map((jsonUnit) {
          return Unit.fromJson(jsonUnit);
        }).toList();
      });

      if (unitdata.isNotEmpty) {
        _selectedunit = unitdata[0].name;

        selectedMultiplier = unitdata[0].multiplier;
      }
      String qtyValue = itemQuantityController.text;

      /*print('unit: $_selectedunit, Multiplier: $selectedMultiplier');*/

      double rateValue = 0;

      if (standardPrice == 'null') {
        if (salePrice == 'null') {
          rateValue = 0;
          itemRateController.text = '';
        } else {
          rateValue = (double.parse(salePrice) * selectedMultiplier);
          double roundedrateValue = double.parse(
            rateValue.toStringAsFixed(decimal!),
          );

          itemRateController.text = roundedrateValue.toString();
        }
      } else {
        rateValue = (double.parse(standardPrice) * selectedMultiplier);
        double roundedrateValue = double.parse(
          rateValue.toStringAsFixed(decimal!),
        );

        itemRateController.text = roundedrateValue.toString();
      }
      double amountValue = (double.parse(qtyValue) * rateValue);
      double roundedAmountValue = double.parse(
        amountValue.toStringAsFixed(decimal!),
      );

      NumberFormat formatter = NumberFormat('#,##0.${'0' * decimal!}', 'en_US');
      String formattedAmount = formatter.format(roundedAmountValue);

      itemAmountController.text = formattedAmount.toString();
    });
  }

  void updateRateAndAmount() {
    String qtyValue = itemQuantityController.text;

    if (qtyValue.isEmpty) {
      qtyValue = '0';
    }

    String rateValue = itemRateController.text;
    if (rateValue.isEmpty) {
      rateValue = '0';
    }
    double amountValue = (double.parse(qtyValue) * double.parse(rateValue));

    double roundedAmountValue = double.parse(
      amountValue.toStringAsFixed(decimal!),
    );

    NumberFormat formatter = NumberFormat('#,##0.${'0' * decimal!}', 'en_US');
    String formattedAmount = formatter.format(roundedAmountValue);

    itemAmountController.text = formattedAmount.toString();
  }

  void updateAmount() {
    String qtyValue = itemQuantityController.text;

    if (qtyValue.isEmpty) {
      qtyValue = '0';
    }

    String rateValue = itemRateController.text;
    if (rateValue.isEmpty) {
      rateValue = '0';
    }
    double amountValue = (double.parse(qtyValue) * double.parse(rateValue));

    double roundedAmountValue = double.parse(
      amountValue.toStringAsFixed(decimal!),
    );

    NumberFormat formatter = NumberFormat('#,##0.${'0' * decimal!}', 'en_US');
    String formattedAmount = formatter.format(roundedAmountValue);

    itemAmountController.text = formattedAmount.toString();
  }

  Future<void> _selectsaleDate(BuildContext context) async {
    if (isUniGasSerial) {
      closeKeyboard(context);
      showAppMessage(context, "Voucher date cannot be changed");
      return;
    }
    setState(() {
      _isFocused_refno = false;
      _isFocused_narration = false;
    });
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: saledate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
      builder: (BuildContext context, Widget? child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(
              context,
            ).colorScheme.copyWith(primary: app_color),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != saledate)
      setState(() {
        saledate = picked;
        saledatestring = _dateFormat.format(saledate);
        saledatetxt = formatlastsaledate(saledatestring);
        _dateController.text = saledatetxt;
      });
  }

  Future<void> _selectrefDate(BuildContext context) async {
    setState(() {
      _isFocused_refno = false;
      _isFocused_narration = false;
    });
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: refdate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
      builder: (BuildContext context, Widget? child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(
              context,
            ).colorScheme.copyWith(primary: app_color),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && picked != refdate)
      setState(() {
        refdate = picked;
        refdatestring = _dateFormat.format(refdate);
        refdatetxt = formatlastsaledate(refdatestring);
        _refdateController.text = refdatetxt;
      });
  }

  /*Future<void> _showItemDetailsPopup(BuildContext context) async {
    showDialog(
        context: context,
        builder: (BuildContext context) {
          return StatefulBuilder(
            builder: (context, setStateDialog) {
              return AlertDialog(
                backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                title: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [Colors.teal, Colors.greenAccent],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: const Icon(Icons.add_shopping_cart, color: Colors.white, size: 28),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      "Add Item",
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
                content: SingleChildScrollView(
                  child: Form(
                    key: _itemFormkey,
                    child: Column(
                      children: [

                        // 🔍 Item Search
                        TypeAheadField<Map<String, dynamic>>(
                          // 🔹 Latest API requires this controller instead of inside TextFieldConfiguration
                          controller: _itemController,

                          // 🔹 Suggestion logic
                          suggestionsCallback: (pattern) async {
                            return itemdata
                                .where((item) {
                              final name = item['name']?.toString().toLowerCase() ?? '';
                              final part = item['part']?.toString().toLowerCase() ?? '';
                              return name.contains(pattern.toLowerCase()) ||
                                  part.contains(pattern.toLowerCase());
                            })
                                .cast<Map<String, dynamic>>() // 👈 important fix
                                .toList();
                          },

                          // 🔹 How each suggestion looks
                          itemBuilder: (context, suggestion) {
                            return ListTile(
                              title: Text(
                                suggestion['name'] ?? '',
                                style: GoogleFonts.poppins(fontSize: 14, color: Theme.of(context).colorScheme.onSurface),
                              ),
                              subtitle: Text(
                                suggestion['part'] ?? '',
                                style: GoogleFonts.poppins(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                              ),
                            );
                          },

                          // 🔹 Required in new API (replaces onSuggestionSelected)

                          onSelected: (suggestion) {
                            setStateDialog(() {
                              _selecteditem = suggestion['name'] ?? '';
                              _itemController.text = _selecteditem;

                              if (locationsdata.isNotEmpty) {
                                selectedLocation = locationsdata[0];
                                isVisibleLocation = true;
                              } else {
                                isVisibleLocation = false;
                              }

                              _updateUnitDropdown(_selecteditem);
                              isVisibleUnit = true;
                            });
                          },



                          // 🔹 Main TextField builder (replaces old textFieldConfiguration)
                          builder: (context, controller, focusNode) {
                            return TextField(
                              controller: controller,
                              focusNode: focusNode,
                              decoration: InputDecoration(
                                labelText: "Item",
                                hintText: "Search item",
                                prefixIcon: Container(
                                  margin: const EdgeInsets.all(8),
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [Colors.blue, Colors.lightBlueAccent],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius: BorderRadius.all(Radius.circular(8)),
                                  ),
                                  child: const Icon(Icons.inventory_outlined, color: Colors.white),
                                ),

                                // 👉 Close + Dropdown icons
                                suffixIcon: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (_itemController.text.isNotEmpty)
                                      IconButton(
                                        icon: Icon(Icons.close, color: Theme.of(context).colorScheme.onSurfaceVariant, size: 20),
                                        onPressed: () {
                                          _itemController.clear();
                                          setStateDialog(() {
                                            _selecteditem = "";
                                            isVisibleLocation = false;
                                            isVisibleUnit = false;
                                          });
                                        },
                                      ),
                                    Icon(Icons.arrow_drop_down, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                    const SizedBox(width: 6),
                                  ],
                                ),

                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: BorderSide(color: app_color, width: 1.5),
                                ),
                                contentPadding:
                                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                              ),
                            );
                          },

                          // 🔹 Optional — shows if no match found
                          emptyBuilder: (context) => const SizedBox.shrink(),
                        ),




                        const SizedBox(height: 14),

                        // 📍 Location
                        Visibility(
                          visible: isVisibleLocation,
                          child: DropdownButtonFormField<String>(
                            isExpanded: true,

                            value: selectedLocation,
                            items: locationsdata.map((value) {
                              return DropdownMenuItem(
                                value: value,
                                child: SizedBox(
                                  width: double.infinity,
                                  child: Text(
                                    value,
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                ),
                              );
                            }).toList(),
                            onChanged: isGodownLocked
                                ? null
                                : (val) => setStateDialog(() => selectedLocation = val!),
                            decoration: InputDecoration(
                              labelText: isGodownLocked
                                  ? "Location Locked"
                                  : "Location",
                              prefixIcon: Container(
                                margin: const EdgeInsets.all(8),
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [Colors.orange, Colors.redAccent],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.all(Radius.circular(8)),
                                ),
                                child: const Icon(Icons.location_on, color: Colors.white),
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide(color: app_color, width: 1.5),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 14),

                        // 📦 Unit
                        Visibility(
                          visible: isVisibleUnit,
                          child: DropdownButtonFormField<String>(
                            value: _selectedunit,
                            items: unitdata.map((u) {
                              return DropdownMenuItem(value: u.name, child: Text(u.name));
                            }).toList(),
                            onChanged: (val) {
                              setStateDialog(() {
                                _selectedunit = val!;
                                itemQuantityController.text = "1";
                                selectedMultiplier = unitdata.firstWhere((u) => u.name == _selectedunit).multiplier;
                                updateRateAndAmount();
                              });
                            },
                            decoration: InputDecoration(
                              labelText: "Unit",
                              prefixIcon: Container(
                                margin: const EdgeInsets.all(8),
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [Colors.purple, Colors.deepPurpleAccent],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.all(Radius.circular(8)),
                                ),
                                child: const Icon(Icons.straighten, color: Colors.white),
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide(color: app_color, width: 1.5),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 14),

                        // 📝 Basic User Description (UniGas only) - one or
                        // more separate single-line boxes, "+" adds another.
                        // Sent as Tally's BASICUSERDESCRIPTION.LIST on this
                        // item's inventory entry (one object per box).
                        if (isUniGasSerial && isVisibleUnit) ...[
                          Row(
                            children: [
                              Text(
                                "Description (optional)",
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const Spacer(),
                              InkWell(
                                borderRadius: BorderRadius.circular(20),
                                onTap: () {
                                  setStateDialog(() {
                                    itemDescriptionControllers.add(
                                      TextEditingController(),
                                    );
                                  });
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: app_color.withOpacity(0.12),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.add,
                                    size: 18,
                                    color: app_color,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          for (
                            int i = 0;
                            i < itemDescriptionControllers.length;
                            i++
                          ) ...[
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: itemDescriptionControllers[i],
                                    maxLines: 1,
                                    maxLength: 75,
                                    decoration: InputDecoration(
                                      hintText: "Enter description",
                                      isDense: true,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 12,
                                          ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(
                                          14,
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(
                                          14,
                                        ),
                                        borderSide: BorderSide(
                                          color: app_color,
                                          width: 1.5,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                if (itemDescriptionControllers.length > 1)
                                  IconButton(
                                    icon: const Icon(
                                      Icons.close,
                                      size: 18,
                                      color: Colors.redAccent,
                                    ),
                                    onPressed: () {
                                      setStateDialog(() {
                                        itemDescriptionControllers
                                            .removeAt(i)
                                            .dispose();
                                      });
                                    },
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                          ],
                          const SizedBox(height: 6),
                        ],

                        // 🔢 Quantity
                        TextFormField(
                          controller: itemQuantityController,
                          keyboardType: TextInputType.number,
                          onChanged: (_) => updateRateAndAmount(),
                          decoration: InputDecoration(
                            labelText: "Quantity",
                            prefixIcon: Container(
                              margin: const EdgeInsets.all(8),
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [Colors.green, Colors.lightGreen],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.all(Radius.circular(8)),
                              ),
                              child: const Icon(Icons.confirmation_num, color: Colors.white),
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(color: app_color, width: 1.5),
                            ),
                          ),
                        ),

                        const SizedBox(height: 14),

                        // 💲 Rate
                        TextFormField(
                          controller: itemRateController,
                          keyboardType: TextInputType.number,
                          onChanged: (_) => updateAmount(),
                          decoration: InputDecoration(
                            labelText: "Rate",
                            prefix: Container(
                              margin: const EdgeInsets.only(right: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [Colors.blue, Colors.blue], // ✅ distinct from Ledger
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.all(Radius.circular(8)),
                              ),
                              child: currencySymbolWidget(
                                currencycode,
                                getCurrencySymbol(currencycode),
                                GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(color: app_color, width: 1.5),
                            ),
                          ),
                        ),

                        const SizedBox(height: 14),

                        // 💰 Amount (Disabled with Gradient Currency Symbol)
                        TextFormField(
                          controller: itemAmountController,
                          enabled: false,
                          decoration: InputDecoration(
                            labelText: "Amount",
                            prefix: Container(
                              margin: const EdgeInsets.only(right: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [Colors.green, Colors.teal], // ✅ distinct from Ledger
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.all(Radius.circular(8)),
                              ),
                              child: currencySymbolWidget(
                                currencycode,
                                getCurrencySymbol(currencycode),
                                GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(color: app_color, width: 1.5),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text("Cancel", style: GoogleFonts.poppins(color: app_color)),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: app_color,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                    icon: const Icon(Icons.check, color: Colors.white),
                    label: Text("Add Item",
                        style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600)),
                    onPressed: () {
                      if (_itemFormkey.currentState!.validate()) {
                        addItem();
                      }
                    },
                  ),
                ],
              );

            },);}
    );
  }*/

  double? _resolveItemOwnRate(Map<String, dynamic> item, double multiplier) {
    final String standardPrice = item['standardprice']?.toString() ?? 'null';
    final String salePrice = item['saleprice']?.toString() ?? 'null';

    if (standardPrice != 'null') {
      final double? parsed = double.tryParse(standardPrice);
      if (parsed != null) return parsed * multiplier;
    }
    if (salePrice != 'null') {
      final double? parsed = double.tryParse(salePrice);
      if (parsed != null) return parsed * multiplier;
    }
    return null;
  }

  // Price-level rate for one item, reusing the same API the single-item
  // flow already uses. Returns null if the party has no price level, or
  // the API has no rate for this item under that price level.
  Future<double?> _resolvePriceLevelRateForItem(String itemMasterId) async {
    if (serial_no == null ||
        serial_no!.trim().isEmpty ||
        !vanSalesSerialNo.contains(serial_no!.trim())) {
      return null;
    }
    if (selectedPartyLedgerPriceLevel == null ||
        selectedPartyLedgerPriceLevel!.trim().isEmpty) {
      return null;
    }

    try {
      final DateTime selectedDate = saledatestring.isNotEmpty
          ? parseCompactDate(saledatestring)
          : DateTime.now();

      final int? parsedItemMasterId = int.tryParse(itemMasterId);
      if (parsedItemMasterId == null) return null;

      return await _priceLevelRate(
        stockItemMasterId: parsedItemMasterId,
        priceLevelName: selectedPartyLedgerPriceLevel!,
        asOf: selectedDate,
      );
    } catch (e) {
      debugPrint('Bulk add: price level lookup failed for $itemMasterId: $e');
    }
    return null;
  }

  // Mirrors the totals recalculation addItem() does, kept separate so
  // this experimental flow can't regress the existing single-item logic.
  void _recalcTotalsAfterBulkAdd() {
    setState(() {
      isVisibleItemHeading = saleItems.isNotEmpty;

      totalPriceOfItems = saleItems.fold(0.0, (
        double previousAmount,
        SaleItem item,
      ) {
        return previousAmount +
            (double.parse(item.itemPrice.toStringAsFixed(decimal!)) *
                double.parse(item.itemQuantity));
      });

      double vat_perc = vatperc / 100;
      if (_selectedvatledger != 'Not Applicable') {
        double totalAmountForVatAppEntries = ledgerEntries
            .where((entry) => entry.vatApp)
            .fold(0.0, (double previousAmount, LedgerEntry entry) {
              return previousAmount + entry.ledgerAmount;
            });
        double ledgerVatAmount = totalAmountForVatAppEntries * vat_perc;
        itemsVatAmount = double.parse(
          (totalPriceOfItems * vat_perc).toStringAsFixed(decimal!),
        );
        totalVatAmount = itemsVatAmount + ledgerVatAmount;
      } else {
        totalVatAmount = 0;
      }
      roundedtotalVatAmount = double.parse(
        totalVatAmount.toStringAsFixed(decimal!),
      );
      final vatFormatter = NumberFormat('#,##0.${'0' * decimal!}', 'en_US');
      controller_vatamt.text = vatFormatter.format(roundedtotalVatAmount);

      double totalAmountOfLedgers = ledgerEntries.fold(0.0, (
        double previousAmount,
        LedgerEntry entry,
      ) {
        return previousAmount + entry.ledgerAmount;
      });

      totalAmount = totalPriceOfItems + totalAmountOfLedgers + totalVatAmount;
      roundedtotalAmount = double.parse(totalAmount.toStringAsFixed(decimal!));
      final totalFormatter = NumberFormat('#,##0.${'0' * decimal!}', 'en_US');
      controller_totalamt.text = totalFormatter.format(roundedtotalAmount);
    });
  }

  // Small colored badge used to permanently show where a rate came from
  // (Price Level / Item Rate / Manual) — a normal user-facing indicator.
  Widget _rateSourceBadge(String source) {
    final Color color = source == 'Price Level'
        ? Colors.green
        : (source == 'Item Rate' ? Colors.blueAccent : Colors.orange);
    final String label = source == 'Empty' ? 'Manual' : source;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (source == 'Price Level')
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(Icons.lock_outline, size: 12, color: color),
            ),
          Text(
            label,
            style: GoogleFonts.poppins(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  // Compact rounded stepper used for quantity in the bulk-add sheet.
  Widget _bulkQtyStepper(
    TextEditingController controller,
    VoidCallback onDecrement,
    VoidCallback onIncrement, {
    ValueChanged<String>? onChanged,
    bool enabled = true,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? Theme.of(context).colorScheme.surfaceContainerHighest
            : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: enabled ? onDecrement : null,
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(14),
            ),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Icon(
                Icons.remove,
                size: 18,
                color: enabled ? Colors.redAccent : Colors.grey,
              ),
            ),
          ),
          // Users can manually type large quantities here too - caps the
          // BOX at a reasonable width and lets the number scroll
          // horizontally within it (rather than clipping), same fix as
          // Delivery Note's meter-reading-derived quantities.
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 40, maxWidth: 110),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: IntrinsicWidth(
                child: TextField(
                  controller: controller,
                  enabled: enabled,
                  textAlign: TextAlign.center,
                  textAlignVertical: TextAlignVertical.center,
                  keyboardType: TextInputType.number,
                  onChanged: onChanged,
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 4),
                    border: InputBorder.none,
                  ),
                ),
              ),
            ),
          ),
          InkWell(
            onTap: enabled ? onIncrement : null,
            borderRadius: const BorderRadius.horizontal(
              right: Radius.circular(14),
            ),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Icon(
                Icons.add,
                size: 18,
                color: enabled ? app_color : Colors.grey,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showMultiItemSelectPopup(BuildContext context) async {
    final Set<String> selectedItemNames = {};
    // Shows exactly where each item's rate came from — Price Level,
    // Item Rate, or Manual (empty, needs entry).
    final Map<String, _ResolvedRateInfo> rateInfoCache = {};
    // Editable rate per item — locked when the rate came from a Price
    // Level (matches the existing single-item behavior), editable when
    // it came from the item's own rate or was left empty.
    final Map<String, TextEditingController> rateEditControllers = {};
    // Editable quantity per item, defaults to "1".
    final Map<String, TextEditingController> qtyEditControllers = {};
    // Selected unit per item — matches the single-item flow's unit
    // dropdown. Switching units resets qty to "1" (same behavior; rate
    // is intentionally NOT recomputed on unit change, mirroring the
    // single-item flow exactly).
    final Map<String, String> selectedUnitPerItem = {};
    // Selected location per item - only surfaced (non-UniGas) when there's
    // more than one location to choose from; defaults to the first one.
    final Map<String, String> selectedLocationPerItem = {};
    // UniGas-only free-text "Basic User Description" boxes per item (see
    // SaleItem.basicUserDescriptions) - one controller per box, "+" adds
    // another for that item.
    final Map<String, List<TextEditingController>> descriptionControllers =
        {};
    final TextEditingController searchController = TextEditingController();
    String searchQuery = '';

    Future<void> resolveRateFor(
      String name,
      Map<String, dynamic> itemInfo,
      StateSetter setStateDialog,
    ) async {
      setStateDialog(() {
        rateInfoCache[name] = _ResolvedRateInfo(
          rate: null,
          source: 'Resolving…',
          loading: true,
        );
      });

      final List<dynamic> unitJson = itemInfo['unit'] ?? [];
      final List<Unit> units = unitJson.map((u) => Unit.fromJson(u)).toList();
      final double multiplier = units.isNotEmpty ? units.first.multiplier : 1.0;
      final String? masterId = itemInfo['masterid']?.toString();

      double? rate;
      String source;

      if (masterId != null && masterId.isNotEmpty) {
        rate = await _resolvePriceLevelRateForItem(masterId);
      }
      if (rate != null) {
        source = 'Price Level';
      } else {
        rate = _resolveItemOwnRate(itemInfo, multiplier);
        source = rate != null ? 'Item Rate' : 'Empty';
      }

      setStateDialog(() {
        rateInfoCache[name] = _ResolvedRateInfo(
          rate: rate,
          source: source,
          loading: false,
        );
        rateEditControllers[name] = TextEditingController(
          text: rate != null ? rate.toStringAsFixed(decimal ?? 2) : '',
        );
      });
    }

    void adjustQty(String name, int delta, StateSetter setStateDialog) {
      final controller = qtyEditControllers[name];
      if (controller == null) return;
      final int current = int.tryParse(controller.text.trim()) ?? 1;
      final int next = current + delta;
      setStateDialog(() {
        if (next < 1) {
          // Decrementing below 1 unselects the item instead of clamping
          // at 1 - reset its qty back to 1 so it starts fresh if picked
          // again later.
          selectedItemNames.remove(name);
          controller.text = '1';
        } else {
          controller.text = next.toString();
        }
      });
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            bool isAdding = false;
            final List<dynamic> searchedItems = searchQuery.isEmpty
                ? itemdata
                : itemdata
                      .where(
                        (i) => (i['name']?.toString() ?? '')
                            .toLowerCase()
                            .contains(searchQuery.toLowerCase()),
                      )
                      .toList();

            // Deliberately NOT reordering selected items to the top - that
            // used to re-sort the whole list on every checkbox toggle,
            // which made rows jump around under the user's finger while
            // they were still picking items. The list now stays in one
            // fixed, natural order; the pinned chip row above the list
            // (see selectedItemNames.isNotEmpty below) gives at-a-glance
            // confirmation of what's selected instead.
            final List<dynamic> filteredItems = searchedItems;

            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.9,
              minChildSize: 0.5,
              builder: (context, scrollController) {
                return Column(
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 10),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 12, 6),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Colors.indigo, Colors.blueAccent],
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.checklist,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              "Add Multiple Items",
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (selectedItemNames.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              margin: const EdgeInsets.only(right: 4),
                              decoration: BoxDecoration(
                                color: app_color.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                "${selectedItemNames.length} selected",
                                style: GoogleFonts.poppins(
                                  color: app_color,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          IconButton(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                      child: TextField(
                        controller: searchController,
                        style: GoogleFonts.poppins(fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Search items…',
                          hintStyle: GoogleFonts.poppins(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                          prefixIcon: Icon(
                            Icons.search,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                          suffixIcon: searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.close),
                                  onPressed: () {
                                    searchController.clear();
                                    setStateDialog(() => searchQuery = '');
                                  },
                                )
                              : null,
                          filled: true,
                          fillColor:
                              Theme.of(context).brightness == Brightness.dark
                              ? Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHighest
                              : Colors.grey.shade100,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 0,
                            horizontal: 16,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onChanged: (value) {
                          setStateDialog(() => searchQuery = value);
                        },
                      ),
                    ),
                    // Pinned summary of what's selected so far - stays put
                    // while the list below scrolls, instead of the old
                    // behavior of reordering the list itself to show
                    // selected items at the top.
                    if (selectedItemNames.isNotEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.only(bottom: 10),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              for (final selectedName in selectedItemNames)
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: Chip(
                                    label: Text(
                                      selectedName,
                                      style: GoogleFonts.poppins(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: app_color,
                                      ),
                                    ),
                                    backgroundColor: app_color.withValues(
                                      alpha: 0.12,
                                    ),
                                    deleteIcon: Icon(
                                      Icons.close,
                                      size: 16,
                                      color: app_color,
                                    ),
                                    onDeleted: () {
                                      setStateDialog(() {
                                        selectedItemNames.remove(
                                          selectedName,
                                        );
                                      });
                                    },
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    visualDensity: VisualDensity.compact,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(20),
                                      side: BorderSide.none,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    Expanded(
                      child: filteredItems.isEmpty
                          ? Center(
                              child: Text(
                                "No items found",
                                style: GoogleFonts.poppins(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            )
                          : ListView.builder(
                              controller: scrollController,
                              padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
                              itemCount: filteredItems.length,
                              itemBuilder: (context, index) {
                                final item = filteredItems[index];
                                final String name =
                                    item['name']?.toString() ?? '';
                                final bool checked = selectedItemNames.contains(
                                  name,
                                );
                                final _ResolvedRateInfo? info =
                                    rateInfoCache[name];
                                final bool isDark =
                                    Theme.of(context).brightness ==
                                    Brightness.dark;
                                final List<Unit> itemUnits =
                                    ((item['unit'] ?? []) as List<dynamic>)
                                        .map((u) => Unit.fromJson(u))
                                        .toList();

                                void toggle() {
                                  final bool next = !checked;
                                  setStateDialog(() {
                                    if (next) {
                                      selectedItemNames.add(name);
                                      qtyEditControllers.putIfAbsent(
                                        name,
                                        () => TextEditingController(text: '1'),
                                      );
                                      if (itemUnits.isNotEmpty) {
                                        selectedUnitPerItem.putIfAbsent(
                                          name,
                                          () => itemUnits.first.name,
                                        );
                                      }
                                      if (locationsdata.isNotEmpty) {
                                        selectedLocationPerItem.putIfAbsent(
                                          name,
                                          () => locationsdata.first,
                                        );
                                      }
                                      if (isUniGasSerial) {
                                        descriptionControllers.putIfAbsent(
                                          name,
                                          () => [TextEditingController()],
                                        );
                                      }
                                    } else {
                                      selectedItemNames.remove(name);
                                    }
                                  });
                                  if (next &&
                                      !rateInfoCache.containsKey(name)) {
                                    resolveRateFor(name, item, setStateDialog);
                                  }
                                }

                                return Container(
                                  key: ValueKey(name),
                                  margin: const EdgeInsets.symmetric(
                                    vertical: 6,
                                  ),
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).cardColor,
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(
                                      color: checked
                                          ? app_color.withValues(alpha: 0.55)
                                          : (isDark
                                                ? Colors.white.withValues(
                                                    alpha: 0.08,
                                                  )
                                                : Colors.grey.shade200),
                                      width: checked ? 1.6 : 1,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.04,
                                        ),
                                        blurRadius: 10,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      InkWell(
                                        borderRadius: BorderRadius.circular(12),
                                        onTap: toggle,
                                        child: Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(8),
                                              decoration: BoxDecoration(
                                                gradient: LinearGradient(
                                                  colors: checked
                                                      ? [
                                                          app_color,
                                                          app_color.withValues(
                                                            alpha: 0.7,
                                                          ),
                                                        ]
                                                      : [
                                                          Colors.grey.shade400,
                                                          Colors.grey.shade300,
                                                        ],
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                              child: const Icon(
                                                Icons.shopping_bag_outlined,
                                                color: Colors.white,
                                                size: 16,
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Text(
                                                name,
                                                style: GoogleFonts.poppins(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w600,
                                                  color: Theme.of(
                                                    context,
                                                  ).colorScheme.onSurface,
                                                ),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Icon(
                                              checked
                                                  ? Icons.check_circle
                                                  : Icons
                                                        .radio_button_unchecked,
                                              color: checked
                                                  ? app_color
                                                  : Colors.grey.shade400,
                                              size: 24,
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (checked && info != null)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 12,
                                          ),
                                          child: info.loading
                                              ? Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        left: 4,
                                                      ),
                                                  child: Row(
                                                    children: [
                                                      const SizedBox(
                                                        width: 14,
                                                        height: 14,
                                                        child:
                                                            CircularProgressIndicator(
                                                              strokeWidth: 2,
                                                            ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Text(
                                                        'Resolving rate…',
                                                        style:
                                                            GoogleFonts.poppins(
                                                              color:
                                                                  Colors.grey,
                                                              fontSize: 12,
                                                            ),
                                                      ),
                                                    ],
                                                  ),
                                                )
                                              : Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    if (itemUnits
                                                            .isNotEmpty &&
                                                        !isUniGasSerial) ...[
                                                      DropdownButtonFormField<
                                                        String
                                                      >(
                                                        value:
                                                            selectedUnitPerItem[name] ??
                                                            itemUnits
                                                                .first
                                                                .name,
                                                        isExpanded: true,
                                                        items: itemUnits.map((
                                                          u,
                                                        ) {
                                                          return DropdownMenuItem(
                                                            value: u.name,
                                                            child: Text(
                                                              u.name,
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                              style: GoogleFonts.poppins(
                                                                fontSize: 13,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w500,
                                                              ),
                                                            ),
                                                          );
                                                        }).toList(),
                                                        onChanged: (val) {
                                                          setStateDialog(() {
                                                            selectedUnitPerItem[name] =
                                                                val!;
                                                            // Matches the
                                                            // single-item
                                                            // flow: switching
                                                            // units resets
                                                            // qty to 1 and
                                                            // does NOT
                                                            // recompute rate.
                                                            qtyEditControllers[name]
                                                                    ?.text =
                                                                '1';
                                                          });
                                                        },
                                                        decoration: _inputDecoration(
                                                          label: "Unit",
                                                          icon:
                                                              Icons.straighten,
                                                          gradientColors: const [
                                                            Colors.purple,
                                                            Colors
                                                                .deepPurpleAccent,
                                                          ],
                                                        ),
                                                      ),
                                                      const SizedBox(
                                                        height: 10,
                                                      ),
                                                    ],
                                                    if (locationsdata
                                                            .isNotEmpty &&
                                                        !isUniGasSerial) ...[
                                                      DropdownButtonFormField<
                                                        String
                                                      >(
                                                        value:
                                                            selectedLocationPerItem[name] ??
                                                            locationsdata
                                                                .first,
                                                        isExpanded: true,
                                                        items: locationsdata.map((
                                                          loc,
                                                        ) {
                                                          return DropdownMenuItem(
                                                            value: loc,
                                                            child: Text(
                                                              loc,
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                              style: GoogleFonts.poppins(
                                                                fontSize: 13,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w500,
                                                              ),
                                                            ),
                                                          );
                                                        }).toList(),
                                                        onChanged: (val) {
                                                          setStateDialog(() {
                                                            selectedLocationPerItem[name] =
                                                                val!;
                                                          });
                                                        },
                                                        decoration: _inputDecoration(
                                                          label: "Location",
                                                          icon: Icons
                                                              .location_on_outlined,
                                                          gradientColors: const [
                                                            Colors.teal,
                                                            Colors
                                                                .tealAccent,
                                                          ],
                                                        ),
                                                      ),
                                                      const SizedBox(
                                                        height: 10,
                                                      ),
                                                    ],
                                                    if (isUniGasSerial) ...[
                                                      Row(
                                                        children: [
                                                          Text(
                                                            "Description (optional)",
                                                            style: GoogleFonts.poppins(
                                                              fontSize: 12,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w500,
                                                              color: Theme.of(
                                                                context,
                                                              ).colorScheme.onSurfaceVariant,
                                                            ),
                                                          ),
                                                          const Spacer(),
                                                          InkWell(
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  18,
                                                                ),
                                                            onTap: () {
                                                              setStateDialog(() {
                                                                descriptionControllers[name]!
                                                                    .add(
                                                                      TextEditingController(),
                                                                    );
                                                              });
                                                            },
                                                            child: Container(
                                                              padding:
                                                                  const EdgeInsets.all(
                                                                    3,
                                                                  ),
                                                              decoration: BoxDecoration(
                                                                color: app_color
                                                                    .withOpacity(
                                                                      0.12,
                                                                    ),
                                                                shape: BoxShape
                                                                    .circle,
                                                              ),
                                                              child: Icon(
                                                                Icons.add,
                                                                size: 16,
                                                                color:
                                                                    app_color,
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                      const SizedBox(
                                                        height: 6,
                                                      ),
                                                      for (
                                                        int di = 0;
                                                        di <
                                                            descriptionControllers[name]!
                                                                .length;
                                                        di++
                                                      ) ...[
                                                        Row(
                                                          children: [
                                                            Expanded(
                                                              child: TextField(
                                                                controller:
                                                                    descriptionControllers[name]![di],
                                                                maxLines: 1,
                                                                maxLength: 75,
                                                                style: GoogleFonts.poppins(
                                                                  fontSize: 13,
                                                                ),
                                                                decoration: InputDecoration(
                                                                  hintText:
                                                                      "Enter description",
                                                                  isDense: true,
                                                                  contentPadding:
                                                                      const EdgeInsets.symmetric(
                                                                        horizontal:
                                                                            12,
                                                                        vertical:
                                                                            10,
                                                                      ),
                                                                  border: OutlineInputBorder(
                                                                    borderRadius:
                                                                        BorderRadius.circular(
                                                                          12,
                                                                        ),
                                                                  ),
                                                                  focusedBorder: OutlineInputBorder(
                                                                    borderRadius:
                                                                        BorderRadius.circular(
                                                                          12,
                                                                        ),
                                                                    borderSide: BorderSide(
                                                                      color:
                                                                          app_color,
                                                                      width:
                                                                          1.5,
                                                                    ),
                                                                  ),
                                                                ),
                                                              ),
                                                            ),
                                                            if (descriptionControllers[name]!
                                                                    .length >
                                                                1)
                                                              IconButton(
                                                                icon: const Icon(
                                                                  Icons.close,
                                                                  size: 16,
                                                                  color: Colors
                                                                      .redAccent,
                                                                ),
                                                                onPressed: () {
                                                                  setStateDialog(() {
                                                                    descriptionControllers[name]!
                                                                        .removeAt(
                                                                          di,
                                                                        )
                                                                        .dispose();
                                                                  });
                                                                },
                                                              ),
                                                          ],
                                                        ),
                                                        const SizedBox(
                                                          height: 6,
                                                        ),
                                                      ],
                                                      const SizedBox(
                                                        height: 4,
                                                      ),
                                                    ],
                                                    Row(
                                                      children: [
                                                        _bulkQtyStepper(
                                                          qtyEditControllers[name]!,
                                                          () => adjustQty(
                                                            name,
                                                            -1,
                                                            setStateDialog,
                                                          ),
                                                          () => adjustQty(
                                                            name,
                                                            1,
                                                            setStateDialog,
                                                          ),
                                                          onChanged: (_) =>
                                                              setStateDialog(
                                                                () {},
                                                              ),
                                                        ),
                                                        const SizedBox(
                                                          width: 10,
                                                        ),
                                                        Expanded(
                                                          child: TextField(
                                                            controller:
                                                                rateEditControllers[name],
                                                            enabled:
                                                                info.source !=
                                                                'Price Level',
                                                            onChanged: (_) =>
                                                                setStateDialog(
                                                                  () {},
                                                                ),
                                                            textAlignVertical:
                                                                TextAlignVertical
                                                                    .center,
                                                            keyboardType:
                                                                const TextInputType.numberWithOptions(
                                                                  decimal: true,
                                                                ),
                                                            style:
                                                                GoogleFonts.poppins(
                                                                  fontSize: 14,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600,
                                                                ),
                                                            decoration: InputDecoration(
                                                              isDense: true,
                                                              hintText: 'Rate',
                                                              hintStyle: GoogleFonts.poppins(
                                                                fontSize: 13,
                                                                color: Theme.of(context)
                                                                    .colorScheme
                                                                    .onSurfaceVariant,
                                                              ),
                                                              prefix: Padding(
                                                                padding:
                                                                    const EdgeInsets.only(
                                                                      right: 4,
                                                                    ),
                                                                child: currencySymbolWidget(
                                                                  currencycode,
                                                                  getCurrencySymbol(
                                                                    currencycode,
                                                                  ),
                                                                  GoogleFonts.poppins(
                                                                    fontSize:
                                                                        14,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w600,
                                                                    color: Theme.of(
                                                                      context,
                                                                    ).colorScheme.onSurface,
                                                                  ),
                                                                ),
                                                              ),
                                                              filled: true,
                                                              fillColor: isDark
                                                                  ? Theme.of(
                                                                          context,
                                                                        )
                                                                        .colorScheme
                                                                        .surfaceContainerHighest
                                                                  : Colors
                                                                        .grey
                                                                        .shade100,
                                                              contentPadding:
                                                                  const EdgeInsets.symmetric(
                                                                    horizontal:
                                                                        12,
                                                                    vertical:
                                                                        10,
                                                                  ),
                                                              enabledBorder:
                                                                  OutlineInputBorder(
                                                                    borderRadius:
                                                                        BorderRadius.circular(
                                                                          14,
                                                                        ),
                                                                    borderSide:
                                                                        BorderSide
                                                                            .none,
                                                                  ),
                                                              focusedBorder: OutlineInputBorder(
                                                                borderRadius:
                                                                    BorderRadius.circular(
                                                                      14,
                                                                    ),
                                                                borderSide:
                                                                    BorderSide(
                                                                      color:
                                                                          app_color,
                                                                      width:
                                                                          1.5,
                                                                    ),
                                                              ),
                                                              border: OutlineInputBorder(
                                                                borderRadius:
                                                                    BorderRadius.circular(
                                                                      14,
                                                                    ),
                                                                borderSide:
                                                                    BorderSide
                                                                        .none,
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 12),
                                                    Row(
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .spaceBetween,
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .end,
                                                      children: [
                                                        if (isUniGasSerial)
                                                          _rateSourceBadge(
                                                            info.source,
                                                          )
                                                        else
                                                          const SizedBox.shrink(),
                                                        Builder(
                                                          builder: (context) {
                                                            final double qty =
                                                                double.tryParse(
                                                                  qtyEditControllers[name]
                                                                          ?.text
                                                                          .trim() ??
                                                                      '',
                                                                ) ??
                                                                0;
                                                            final double rate =
                                                                double.tryParse(
                                                                  rateEditControllers[name]
                                                                          ?.text
                                                                          .trim() ??
                                                                      '',
                                                                ) ??
                                                                0;
                                                            final double
                                                            amount = double.parse(
                                                              (qty * rate)
                                                                  .toStringAsFixed(
                                                                    decimal ??
                                                                        2,
                                                                  ),
                                                            );
                                                            final currencyFormatter =
                                                                NumberFormat(
                                                                  '#,##0.${'0' * (decimal ?? 2)}',
                                                                  'en_US',
                                                                );
                                                            return Flexible(
                                                              child: Container(
                                                                padding:
                                                                    const EdgeInsets.symmetric(
                                                                      horizontal:
                                                                          12,
                                                                      vertical:
                                                                          7,
                                                                    ),
                                                                decoration: BoxDecoration(
                                                                  color: app_color.withValues(
                                                                    alpha: 0.1,
                                                                  ),
                                                                  borderRadius:
                                                                      BorderRadius.circular(
                                                                        12,
                                                                      ),
                                                                ),
                                                                child: Column(
                                                                  crossAxisAlignment:
                                                                      CrossAxisAlignment
                                                                          .end,
                                                                  mainAxisSize:
                                                                      MainAxisSize
                                                                          .min,
                                                                  children: [
                                                                    Text(
                                                                      'Amount',
                                                                      style: GoogleFonts.poppins(
                                                                        fontSize:
                                                                            9,
                                                                        fontWeight:
                                                                            FontWeight.w600,
                                                                        color: app_color.withValues(
                                                                          alpha:
                                                                              0.8,
                                                                        ),
                                                                      ),
                                                                    ),
                                                                    _currencyValueWidget(
                                                                      currencyFormatter.format(
                                                                        amount,
                                                                      ),
                                                                      GoogleFonts.poppins(
                                                                        fontSize:
                                                                            15,
                                                                        fontWeight:
                                                                            FontWeight.w700,
                                                                        color:
                                                                            app_color,
                                                                      ),
                                                                    ),
                                                                  ],
                                                                ),
                                                              ),
                                                            );
                                                          },
                                                        ),
                                                      ],
                                                    ),
                                                  ],
                                                ),
                                        ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                    SafeArea(
                      top: false,
                      minimum: const EdgeInsets.only(bottom: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: app_color,
                            minimumSize: const Size(double.infinity, 52),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          icon: isAdding
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.check, color: Colors.white),
                          label: Text(
                            "Add Selected (${selectedItemNames.length})",
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          onPressed:
                              selectedItemNames.isEmpty || isAdding
                              ? null
                              : () async {
                                  // Same qty>0 check addItem() does, run for
                                  // every selected item before adding any of
                                  // them (all-or-nothing, like the single-item
                                  // flow returning early on failure).
                                  for (final name in selectedItemNames) {
                                    final double qty =
                                        double.tryParse(
                                          qtyEditControllers[name]?.text
                                                  .trim() ??
                                              '',
                                        ) ??
                                        0;
                                    if (qty <= 0) {
                                      showAppMessage(
                                        context,
                                        "Quantity must be greater than 0 for $name",
                                      );
                                      return;
                                    }

                                    // Same as addItem()'s itemPrice.isNotEmpty
                                    // requirement — a rate is required.
                                    final String rateText =
                                        rateEditControllers[name]?.text
                                            .trim() ??
                                        '';
                                    if (rateText.isEmpty) {
                                      showAppMessage(
                                        context,
                                        "Rate is required for $name",
                                      );
                                      return;
                                    }
                                  }

                                  setStateDialog(() => isAdding = true);
                                  await _addSelectedItemsInBulk(
                                    selectedItemNames,
                                    rateEditControllers,
                                    qtyEditControllers,
                                    selectedUnitPerItem,
                                    selectedLocationPerItem,
                                    descriptionControllers,
                                  );
                                  if (context.mounted) {
                                    Navigator.of(context).pop();
                                  }
                                },
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _addSelectedItemsInBulk(
    Set<String> selectedItemNames,
    Map<String, TextEditingController> rateEditControllers,
    Map<String, TextEditingController> qtyEditControllers,
    Map<String, String> selectedUnitPerItem,
    Map<String, String> selectedLocationPerItem,
    Map<String, List<TextEditingController>> descriptionControllers,
  ) async {
    for (final name in selectedItemNames) {
      final Map<String, dynamic>? itemInfo = itemdata.firstWhere(
        (i) => i['name'] == name,
        orElse: () => null,
      );
      if (itemInfo == null) continue;

      final List<dynamic> unitJson = itemInfo['unit'] ?? [];
      final List<Unit> units = unitJson.map((u) => Unit.fromJson(u)).toList();
      final String unitName =
          selectedUnitPerItem[name] ??
          (units.isNotEmpty ? units.first.name : '');
      final String itemLocationName =
          selectedLocationPerItem[name] ?? selectedLocation;
      final List<String> itemDescriptions =
          descriptionControllers[name]
              ?.map((c) => c.text.trim())
              .where((t) => t.isNotEmpty)
              .toList() ??
          const [];

      // Use whatever rate is currently in the editable field — lets the
      // user type a rate when it came back Empty, or override an Item
      // Rate value before adding. Price Level rates stay locked (field
      // disabled), so they always come through unchanged.
      final double resolvedRate =
          double.tryParse(rateEditControllers[name]?.text.trim() ?? '') ?? 0.0;
      final int parsedQty =
          int.tryParse(qtyEditControllers[name]?.text.trim() ?? '') ?? 1;
      final String qty = (parsedQty < 1 ? 1 : parsedQty).toString();
      // Matches updateRateAndAmount()/addItem(): amount is rounded to the
      // configured decimal places before being stored, not left raw.
      final double amount = double.parse(
        (resolvedRate * double.parse(qty)).toStringAsFixed(decimal!),
      );
      final int existingIndex = saleItems.indexWhere(
        (i) =>
            i.itemName == name &&
            double.parse(i.itemPrice.toStringAsFixed(decimal!)) ==
                double.parse(resolvedRate.toStringAsFixed(decimal!)) &&
            i.itemUnit == unitName,
      );

      if (existingIndex != -1) {
        final existing = saleItems[existingIndex];
        // BigInt, not int - a manually-typed quantity can run past int64
        // range and int.parse() throws FormatException on that instead of
        // silently erroring, crashing the add-item flow outright.
        final String newQty =
            (BigInt.parse(existing.itemQuantity) + BigInt.from(parsedQty))
                .toString();
        saleItems[existingIndex] = existing
            .updateQuantity(newQty)
            .updateItemAmount(resolvedRate * BigInt.parse(newQty).toDouble());
      } else {
        saleItems.add(
          SaleItem(
            itemName: name,
            itemQuantity: qty,
            itemPrice: resolvedRate,
            itemAmount: amount,
            itemLocation: itemLocationName,
            itemUnit: unitName,
            accountingAllocationList: {},
            batchAllocationList: {
              'GODOWNNAME': itemLocationName,
              'AMOUNT': amount,
              'ACTUALQTY': '$qty $unitName',
              'BILLEDQTY': '$qty $unitName',
            },
            basicUserDescriptions: itemDescriptions,
          ),
        );
      }
    }

    _recalcTotalsAfterBulkAdd();
  }

  Future<void> _showItemDetailsPopup(BuildContext context) async {
    _selecteditem = null;
    _itemController.clear();
    itemRateController.clear();
    itemAmountController.clear();

    final String currentSerialNo = serial_no?.trim() ?? '';

    showModalBottomSheet(
      useSafeArea: true,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      context: context,
      enableDrag: false,

      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            final mediaQuery = MediaQuery.of(context);
            final screenHeight = mediaQuery.size.height;
            final keyboardOpen = mediaQuery.viewInsets.bottom > 0;

            final bool hasItemDetails =
                isVisibleUnit ||
                showRateField ||
                itemAmountController.text.isNotEmpty;

            double sheetSize;

            if (keyboardOpen) {
              sheetSize = screenHeight < 700 ? 0.95 : 0.82;
            } else if (hasItemDetails) {
              if (screenHeight < 700) {
                sheetSize = 0.90;
              } else if (screenHeight < 850) {
                sheetSize = 0.78;
              } else {
                sheetSize = 0.68;
              }
            } else {
              if (screenHeight < 700) {
                sheetSize = 0.65;
              } else if (screenHeight < 850) {
                sheetSize = 0.55;
              } else {
                sheetSize = 0.45;
              }
            }

            return Padding(
              padding: EdgeInsets.only(bottom: mediaQuery.viewInsets.bottom),
              child: DraggableScrollableSheet(
                initialChildSize: sheetSize,
                minChildSize: sheetSize,
                maxChildSize: keyboardOpen ? 0.95 : 0.90,
                expand: false,
                builder: (context, scrollController) {
                  return Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(24),
                      ),
                      border: Border.all(
                        color: Theme.of(
                          context,
                        ).dividerColor.withValues(alpha: 0.45),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.18),
                          blurRadius: 24,
                          offset: const Offset(0, -8),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        const SizedBox(height: 10),

                        Container(
                          width: 45,
                          height: 5,
                          decoration: BoxDecoration(
                            color: Theme.of(context).dividerColor,
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),

                        const SizedBox(height: 14),

                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [Colors.teal, Colors.greenAccent],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: const Icon(
                            Icons.add_shopping_cart,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),

                        const SizedBox(height: 10),

                        Text(
                          "Add Item",
                          style: GoogleFonts.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),

                        const SizedBox(height: 12),

                        Expanded(
                          child: SingleChildScrollView(
                            controller: scrollController,
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.manual,
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                            child: Form(
                              key: _itemFormkey,
                              child: Column(
                                children: [
                                  TypeAheadField<Map<String, dynamic>>(
                                    controller: _itemController,
                                    decorationBuilder: (context, child) {
                                      return Material(
                                        elevation: 6,
                                        borderRadius: BorderRadius.circular(16),
                                        color: Theme.of(context).cardColor,
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          child: child,
                                        ),
                                      );
                                    },
                                    suggestionsCallback: (pattern) async {
                                      return itemdata
                                          .where((item) {
                                            final name =
                                                item['name']
                                                    ?.toString()
                                                    .toLowerCase() ??
                                                '';
                                            final part =
                                                item['part']
                                                    ?.toString()
                                                    .toLowerCase() ??
                                                '';

                                            return name.contains(
                                                  pattern.toLowerCase(),
                                                ) ||
                                                part.contains(
                                                  pattern.toLowerCase(),
                                                );
                                          })
                                          .cast<Map<String, dynamic>>()
                                          .toList();
                                    },
                                    itemBuilder: (context, suggestion) {
                                      return ListTile(
                                        title: Text(
                                          suggestion['name'] ?? '',
                                          style: GoogleFonts.poppins(
                                            fontSize: 14,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurface,
                                          ),
                                        ),
                                        subtitle: Text(
                                          suggestion['part'] ?? '',
                                          style: GoogleFonts.poppins(
                                            fontSize: 12,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      );
                                    },
                                    onSelected: (suggestion) async {
                                      FocusScope.of(context).unfocus();

                                      setStateDialog(() {
                                        _selecteditem =
                                            suggestion['name']?.toString() ??
                                            '';

                                        selectedItemMasterId =
                                            suggestion['masterid']
                                                ?.toString() ??
                                            suggestion['itemId']?.toString() ??
                                            suggestion['id']?.toString();

                                        _itemController.text = _selecteditem;

                                        if (locationsdata.isNotEmpty) {
                                          selectedLocation = locationsdata[0];
                                          isVisibleLocation = true;
                                        } else {
                                          isVisibleLocation = false;
                                        }

                                        _updateUnitDropdown(_selecteditem);
                                        isVisibleUnit = true;
                                      });

                                      await fetchPriceLevelDetailsForSelectedItem(
                                        setStateDialog,
                                      );
                                    },
                                    builder: (context, controller, focusNode) {
                                      return TextField(
                                        controller: controller,
                                        focusNode: focusNode,
                                        style: GoogleFonts.poppins(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurface,
                                        ),
                                        decoration: InputDecoration(
                                          labelText: "Item",
                                          hintText: "Search item",
                                          labelStyle: GoogleFonts.poppins(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                          ),
                                          hintStyle: GoogleFonts.poppins(
                                            fontSize: 13,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                          ),
                                          prefixIcon: Container(
                                            margin: const EdgeInsets.all(8),
                                            decoration: const BoxDecoration(
                                              gradient: LinearGradient(
                                                colors: [
                                                  Colors.blue,
                                                  Colors.lightBlueAccent,
                                                ],
                                              ),
                                              borderRadius: BorderRadius.all(
                                                Radius.circular(8),
                                              ),
                                            ),
                                            child: const Icon(
                                              Icons.inventory_outlined,
                                              color: Colors.white,
                                            ),
                                          ),
                                          suffixIcon: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              if (!isPriceLevelLoading &&
                                                  _itemController
                                                      .text
                                                      .isNotEmpty)
                                                IconButton(
                                                  icon: Icon(
                                                    Icons.close,
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .onSurfaceVariant,
                                                    size: 20,
                                                  ),
                                                  onPressed: () {
                                                    _itemController.clear();

                                                    setStateDialog(() {
                                                      _selecteditem = "";
                                                      selectedItemMasterId =
                                                          null;
                                                      itemRateController
                                                          .clear();
                                                      isVisibleLocation = false;
                                                      isVisibleUnit = false;
                                                    });
                                                  },
                                                ),
                                              if (!isPriceLevelLoading)
                                                Icon(
                                                  Icons.arrow_drop_down,
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                                ),
                                              const SizedBox(width: 6),
                                            ],
                                          ),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                          ),
                                          enabledBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                            borderSide: BorderSide(
                                              color: Theme.of(
                                                context,
                                              ).dividerColor,
                                            ),
                                          ),
                                          focusedBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                            borderSide: BorderSide(
                                              color: app_color,
                                              width: 1.5,
                                            ),
                                          ),
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                horizontal: 14,
                                                vertical: 14,
                                              ),
                                        ),
                                      );
                                    },
                                    emptyBuilder: (context) => Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Text(
                                        "No item found",
                                        style: GoogleFonts.poppins(
                                          fontSize: 13,
                                          color: Colors.redAccent,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ),

                                  if (isPriceLevelLoading)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 12),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          SizedBox(
                                            height: 22,
                                            width: 22,
                                            child:
                                                Theme.of(context).platform ==
                                                    TargetPlatform.iOS
                                                ? const CupertinoActivityIndicator(
                                                    radius: 11,
                                                  )
                                                : CircularProgressIndicator(
                                                    strokeWidth: 2.4,
                                                    valueColor:
                                                        AlwaysStoppedAnimation<
                                                          Color
                                                        >(app_color),
                                                  ),
                                          ),
                                          const SizedBox(width: 10),
                                          Text(
                                            "Loading item details...",
                                            style: GoogleFonts.poppins(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w500,
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                  if (!vanSalesSerialNo.contains(
                                    currentSerialNo,
                                  ))
                                    Visibility(
                                      visible: isVisibleLocation,
                                      child: Column(
                                        children: [
                                          const SizedBox(height: 14),

                                          DropdownButtonFormField<String>(
                                            isExpanded: true,

                                            value: selectedLocation,
                                            items: locationsdata.map((value) {
                                              return DropdownMenuItem(
                                                value: value,

                                                child: SizedBox(
                                                  width: double.infinity,
                                                  child: Text(
                                                    value,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    maxLines: 1,
                                                  ),
                                                ),
                                              );
                                            }).toList(),
                                            style: GoogleFonts.poppins(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w500,
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.onSurface,
                                            ),
                                            onChanged: isGodownLocked
                                                ? null
                                                : (val) => setStateDialog(
                                                    () => selectedLocation = val!,
                                                  ),
                                            decoration: InputDecoration(
                                              labelText: isGodownLocked
                                                  ? "Location Locked"
                                                  : "Location",
                                              labelStyle: GoogleFonts.poppins(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w500,
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.onSurfaceVariant,
                                              ),
                                              prefixIcon: Container(
                                                margin: const EdgeInsets.all(8),
                                                decoration: const BoxDecoration(
                                                  gradient: LinearGradient(
                                                    colors: [
                                                      Colors.orange,
                                                      Colors.redAccent,
                                                    ],
                                                    begin: Alignment.topLeft,
                                                    end: Alignment.bottomRight,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.all(
                                                        Radius.circular(8),
                                                      ),
                                                ),
                                                child: const Icon(
                                                  Icons.location_on,
                                                  color: Colors.white,
                                                ),
                                              ),
                                              border: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(16),
                                              ),
                                              focusedBorder: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(16),
                                                borderSide: BorderSide(
                                                  color: app_color,
                                                  width: 1.5,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                  if (!isPriceLevelLoading) ...[
                                    AnimatedSize(
                                      duration: const Duration(
                                        milliseconds: 250,
                                      ),
                                      child: Visibility(
                                        visible: isVisibleUnit,
                                        child: Column(
                                          children: [
                                            const SizedBox(height: 14),
                                            DropdownButtonFormField<String>(
                                              value: _selectedunit,
                                              isExpanded: true,
                                              items: unitdata.map((u) {
                                                return DropdownMenuItem(
                                                  value: u.name,
                                                  child: Text(
                                                    u.name,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: GoogleFonts.poppins(
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                      color: Theme.of(
                                                        context,
                                                      ).colorScheme.onSurface,
                                                    ),
                                                  ),
                                                );
                                              }).toList(),
                                              onChanged: (val) {
                                                setStateDialog(() {
                                                  _selectedunit = val!;
                                                  itemQuantityController.text =
                                                      "1";
                                                  selectedMultiplier = unitdata
                                                      .firstWhere(
                                                        (u) =>
                                                            u.name ==
                                                            _selectedunit,
                                                      )
                                                      .multiplier;
                                                  updateRateAndAmount();
                                                });
                                              },
                                              decoration: _inputDecoration(
                                                label: "Unit",
                                                icon: Icons.straighten,
                                                gradientColors: const [
                                                  Colors.purple,
                                                  Colors.deepPurpleAccent,
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),

                                    const SizedBox(height: 14),

                                    TextFormField(
                                      controller: itemQuantityController,
                                      keyboardType: TextInputType.number,
                                      onChanged: (_) => updateRateAndAmount(),
                                      style: GoogleFonts.poppins(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurface,
                                      ),
                                      decoration: _inputDecoration(
                                        label: "Quantity",
                                        icon: Icons.confirmation_num,
                                        gradientColors: const [
                                          Colors.green,
                                          Colors.lightGreen,
                                        ],
                                      ),
                                    ),

                                    AnimatedSize(
                                      duration: const Duration(
                                        milliseconds: 250,
                                      ),
                                      child: Visibility(
                                        visible: showRateField,
                                        child: Column(
                                          children: [
                                            const SizedBox(height: 14),
                                            TextFormField(
                                              enabled: isRateFieldEnabled,
                                              controller: itemRateController,
                                              keyboardType:
                                                  TextInputType.number,
                                              onChanged: isRateFieldEnabled
                                                  ? (_) => updateAmount()
                                                  : null,
                                              style: GoogleFonts.poppins(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w500,
                                                color: isRateFieldEnabled
                                                    ? Theme.of(
                                                        context,
                                                      ).colorScheme.onSurface
                                                    : Theme.of(context)
                                                          .colorScheme
                                                          .onSurfaceVariant,
                                              ),
                                              decoration: _currencyDecoration(
                                                label: "Rate",
                                                enabled: isRateFieldEnabled,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),

                                    const SizedBox(height: 14),

                                    TextFormField(
                                      controller: itemAmountController,
                                      enabled: false,
                                      style: GoogleFonts.poppins(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurface,
                                      ),
                                      decoration: _currencyDecoration(
                                        label: "Amount",
                                        enabled: false,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),

                        SafeArea(
                          top: false,
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                            decoration: BoxDecoration(
                              color: Theme.of(context).cardColor,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.08),
                                  blurRadius: 10,
                                  offset: const Offset(0, -2),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 14,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                    onPressed: () {
                                      /* setStateDialog(() {
                                        resetItemDialogFields();
                                      });*/

                                      _selectedledger = null;
                                      ledgerAmountController.clear();

                                      Navigator.of(context).pop();
                                    },
                                    child: Text(
                                      "Cancel",
                                      style: GoogleFonts.poppins(
                                        color: app_color,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: app_color,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 14,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                    icon: const Icon(
                                      Icons.check,
                                      color: Colors.white,
                                    ),
                                    label: Text(
                                      "Add Item",
                                      style: GoogleFonts.poppins(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    onPressed: () {
                                      if (_itemFormkey.currentState!
                                          .validate()) {
                                        addItem();
                                      }
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  /*void _showLedgerDetailsPopup(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setState) {
          return AlertDialog(
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),

            // 🔝 Title with gradient icon
            title: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [Colors.deepPurple, Colors.purpleAccent],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: const Icon(Icons.account_balance, color: Colors.white, size: 28),
                ),
                const SizedBox(height: 10),
                Text(
                  "Add Ledger",
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ],
            ),

            content: SingleChildScrollView(
              child: Form(
                key: _ledgerFormkey,
                child: Column(
                  children: [

                    // 🔻 Ledger Dropdown
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                      child: DropdownButtonFormField<String>(
                        isExpanded: true,
                        value: _selectedledger,
                        hint: const Text("Select Ledger"),
                        items: ledgerdata.map<DropdownMenuItem<String>>((ledger) {
                          return DropdownMenuItem<String>(
                            value: ledger['name'],
                            child: Text(
                              ledger['name'],
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            _selectedledger = value!;
                          });
                        },
                        decoration: InputDecoration(
                          labelText: "Ledger Name",
                          prefixIcon: Container(
                            margin: const EdgeInsets.all(8),
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Colors.blue, Colors.lightBlueAccent],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.all(Radius.circular(8)),
                            ),
                            child: const Icon(Icons.account_balance_wallet, color: Colors.white),
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: app_color, width: 1.5),
                          ),
                        ),
                      ),
                    ),

                    //const SizedBox(height: 6),

                    /// Ledger Amount
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                      child: TextFormField(
                        controller: ledgerAmountController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'^-?\d*\.?\d*')),
                        ],
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter amount';
                          } else if (double.tryParse(value) == 0.0) {
                            return 'Amount cannot be 0';
                          }
                          return null;
                        },
                        decoration: InputDecoration(
                          labelText: "Amount",
                          hintText: "Enter Amount",
                          prefix: Container(
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Colors.orange, Colors.redAccent], // ✅ distinct from Ledger
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.all(Radius.circular(8)),
                            ),
                            child: currencySymbolWidget(
                              currencycode,
                              getCurrencySymbol(currencycode),
                              GoogleFonts.poppins(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: app_color, width: 1.5),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Actions
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  _selectedledger = ledgerdata.isNotEmpty ? ledgerdata[0]['name'] : null;
                  ledgerAmountController.clear();
                },
                child: Text("Cancel", style: GoogleFonts.poppins(color: app_color)),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: app_color,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                icon: const Icon(Icons.check, color: Colors.white),
                label: Text("Add Ledger",
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    )),
                onPressed: () {
                  if (_ledgerFormkey.currentState!.validate()) {
                    _ledgerFormkey.currentState!.save();
                    addLedger();
                  }
                },
              ),
            ],
          );
        });
      },
    );
  }*/

  void _showLedgerDetailsPopup(BuildContext context) {
    final TextEditingController _ledgerController = TextEditingController();

    _ledgerController.clear();
    _selectedledger = null;

    showModalBottomSheet(
      useSafeArea: true,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      context: context,
      isScrollControlled: true,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            final mediaQuery = MediaQuery.of(context);
            final screenHeight = mediaQuery.size.height;
            final isKeyboardOpen = mediaQuery.viewInsets.bottom > 0;

            double sheetHeight;

            if (isKeyboardOpen) {
              if (screenHeight < 700) {
                sheetHeight = 0.95;
              } else if (screenHeight < 850) {
                sheetHeight = 0.88;
              } else {
                sheetHeight = 0.78;
              }
            } else {
              if (screenHeight < 700) {
                sheetHeight = 0.78;
              } else if (screenHeight < 850) {
                sheetHeight = 0.68;
              } else {
                sheetHeight = 0.58;
              }
            }

            return AnimatedPadding(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              padding: EdgeInsets.only(bottom: mediaQuery.viewInsets.bottom),
              child: FractionallySizedBox(
                heightFactor: sheetHeight,
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).dividerColor.withValues(alpha: 0.45),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 24,
                        offset: const Offset(0, -8),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      const SizedBox(height: 10),

                      Container(
                        width: 45,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Theme.of(context).dividerColor,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),

                      const SizedBox(height: 12),

                      if (!isKeyboardOpen) ...[
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [Colors.deepPurple, Colors.purpleAccent],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: const Icon(
                            Icons.account_balance,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],

                      Text(
                        "Add Ledger",
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),

                      const SizedBox(height: 10),

                      Expanded(
                        child: SingleChildScrollView(
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.manual,
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                          child: Form(
                            key: _ledgerFormkey,
                            child: Column(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 4,
                                    horizontal: 4,
                                  ),
                                  child: SizedBox(
                                    width: MediaQuery.of(context).size.width,
                                    child: TypeAheadField<String>(
                                      controller: _ledgerController,

                                      suggestionsCallback: (pattern) async {
                                        return ledgerdata
                                            .map<String>(
                                              (ledger) =>
                                                  ledger['name'].toString(),
                                            )
                                            .where(
                                              (item) =>
                                                  item.toLowerCase().contains(
                                                    pattern.toLowerCase(),
                                                  ),
                                            )
                                            .toList();
                                      },

                                      builder:
                                          (context, textController, focusNode) {
                                            return TextField(
                                              controller: textController,
                                              focusNode: focusNode,
                                              style: GoogleFonts.poppins(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w500,
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.onSurface,
                                              ),
                                              decoration: InputDecoration(
                                                hintText:
                                                    _selectedledger
                                                            ?.isNotEmpty ==
                                                        true
                                                    ? _selectedledger
                                                    : "Select Ledger",
                                                labelText: "Ledger Name",
                                                hintStyle: GoogleFonts.poppins(
                                                  fontSize: 13,
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                                ),
                                                labelStyle: GoogleFonts.poppins(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w500,
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                                ),
                                                prefixIcon: Container(
                                                  margin: const EdgeInsets.all(
                                                    8,
                                                  ),
                                                  decoration: const BoxDecoration(
                                                    gradient: LinearGradient(
                                                      colors: [
                                                        Colors.blue,
                                                        Colors.lightBlueAccent,
                                                      ],
                                                      begin: Alignment.topLeft,
                                                      end:
                                                          Alignment.bottomRight,
                                                    ),
                                                    borderRadius:
                                                        BorderRadius.all(
                                                          Radius.circular(12),
                                                        ),
                                                  ),
                                                  child: const Icon(
                                                    Icons
                                                        .account_balance_wallet,
                                                    color: Colors.white,
                                                    size: 20,
                                                  ),
                                                ),
                                                suffixIcon: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    if (_ledgerController
                                                        .text
                                                        .isNotEmpty)
                                                      IconButton(
                                                        icon: Icon(
                                                          Icons.close,
                                                          color: Theme.of(context)
                                                              .colorScheme
                                                              .onSurfaceVariant,
                                                          size: 20,
                                                        ),
                                                        onPressed: () {
                                                          setState(() {
                                                            _ledgerController
                                                                .clear();
                                                            _selectedledger =
                                                                "";
                                                          });
                                                        },
                                                      ),
                                                    Icon(
                                                      Icons.arrow_drop_down,
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .onSurfaceVariant,
                                                    ),
                                                    const SizedBox(width: 6),
                                                  ],
                                                ),
                                                border: OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(16),
                                                ),
                                                enabledBorder:
                                                    OutlineInputBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            16,
                                                          ),
                                                      borderSide: BorderSide(
                                                        color: Theme.of(
                                                          context,
                                                        ).dividerColor,
                                                        width: 1,
                                                      ),
                                                    ),
                                                focusedBorder:
                                                    OutlineInputBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            16,
                                                          ),
                                                      borderSide: BorderSide(
                                                        color: app_color,
                                                        width: 1.5,
                                                      ),
                                                    ),
                                              ),
                                            );
                                          },

                                      decorationBuilder: (context, child) {
                                        return Material(
                                          elevation: 6,
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          color: Theme.of(context).cardColor,
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                            child: child,
                                          ),
                                        );
                                      },

                                      itemBuilder:
                                          (context, String suggestion) {
                                            return ListTile(
                                              title: Text(
                                                suggestion,
                                                overflow: TextOverflow.ellipsis,
                                                style: GoogleFonts.poppins(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w500,
                                                  color: Theme.of(
                                                    context,
                                                  ).colorScheme.onSurface,
                                                ),
                                              ),
                                            );
                                          },

                                      onSelected: (String suggestion) {
                                        FocusScope.of(context).unfocus();

                                        setState(() {
                                          _selectedledger = suggestion;
                                          _ledgerController.text = suggestion;
                                        });
                                      },

                                      emptyBuilder: (context) => Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: Text(
                                          "No ledger found",
                                          style: GoogleFonts.poppins(
                                            fontSize: 13,
                                            color: Colors.redAccent,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 10),

                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 4,
                                    horizontal: 4,
                                  ),
                                  child: TextFormField(
                                    controller: ledgerAmountController,
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.allow(
                                        RegExp(r'^-?\d*\.?\d*'),
                                      ),
                                    ],
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return 'Please enter amount';
                                      } else if (double.tryParse(value) ==
                                          0.0) {
                                        return 'Amount cannot be 0';
                                      }
                                      return null;
                                    },
                                    decoration: InputDecoration(
                                      labelText: "Amount",
                                      hintText: "Enter Amount",
                                      prefix: Container(
                                        margin: const EdgeInsets.only(right: 8),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: const BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              Colors.orange,
                                              Colors.redAccent,
                                            ],
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                          ),
                                          borderRadius: BorderRadius.all(
                                            Radius.circular(8),
                                          ),
                                        ),
                                        child: currencySymbolWidget(
                                          currencycode,
                                          getCurrencySymbol(currencycode),
                                          GoogleFonts.poppins(
                                            color: Colors.white,
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(16),
                                        borderSide: BorderSide(
                                          color: Theme.of(context).dividerColor,
                                          width: 1,
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(16),
                                        borderSide: BorderSide(
                                          color: app_color,
                                          width: 1.5,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      SafeArea(
                        top: false,
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                          decoration: BoxDecoration(
                            color: Theme.of(context).cardColor,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.08),
                                blurRadius: 10,
                                offset: const Offset(0, -2),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  onPressed: () {
                                    Navigator.of(context).pop();

                                    _selectedledger = ledgerdata.isNotEmpty
                                        ? ledgerdata[0]['name']
                                        : null;

                                    ledgerAmountController.clear();
                                  },
                                  child: Text(
                                    "Cancel",
                                    style: GoogleFonts.poppins(
                                      color: app_color,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ),

                              const SizedBox(width: 12),

                              Expanded(
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: app_color,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  icon: const Icon(
                                    Icons.check,
                                    color: Colors.white,
                                  ),
                                  label: Text(
                                    "Add Ledger",
                                    style: GoogleFonts.poppins(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  onPressed: () {
                                    if (_ledgerFormkey.currentState!
                                        .validate()) {
                                      _ledgerFormkey.currentState!.save();
                                      addLedger();
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _recalculateTotals() {
    // Agar items empty hain to heading chhupao
    isVisibleItemHeading = saleItems.isNotEmpty;

    // Total items ka price
    totalPriceOfItems = saleItems.fold(0.0, (
      double previousAmount,
      SaleItem item,
    ) {
      return previousAmount +
          (double.parse(item.itemPrice.toStringAsFixed(decimal!)) *
              double.parse(item.itemQuantity));
    });

    // VAT calculation
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

      NumberFormat formatter = NumberFormat('#,##0.${'0' * decimal!}', 'en_US');
      controller_vatamt.text = formatter
          .format(roundedtotalVatAmount)
          .toString();
    } else {
      totalVatAmount = 0;
      roundedtotalVatAmount = double.parse(
        totalVatAmount.toStringAsFixed(decimal!),
      );
      NumberFormat formatter = NumberFormat('#,##0.${'0' * decimal!}', 'en_US');
      controller_vatamt.text = formatter.format(0).toString();
    }

    // Ledger totals
    totalAmountOfLedgers = ledgerEntries.fold(
      0.0,
      (double prev, entry) => prev + entry.ledgerAmount,
    );

    // Final total
    totalAmount = totalPriceOfItems + totalAmountOfLedgers + totalVatAmount;
    roundedtotalAmount = double.parse(totalAmount.toStringAsFixed(decimal!));

    NumberFormat formatter = NumberFormat('#,##0.${'0' * decimal!}', 'en_US');
    controller_totalamt.text = formatter.format(roundedtotalAmount).toString();
  }

  void addItem() {
    final itemName = _selecteditem;
    final itemQuantity = itemQuantityController.text;
    final itemPrice = itemRateController.text;
    final itemAmount = itemAmountController.text;
    final itemLocation = selectedLocation;
    final itemUnit = _selectedunit;

    final qty = double.tryParse(itemQuantity.replaceAll(',', '').trim()) ?? 0;

    if (itemQuantity.trim().isEmpty || qty <= 0) {
      showAppMessage(context, "Quantity must be greater than 0");
      return;
    }

    if (itemName.isNotEmpty && itemPrice.isNotEmpty) {
      Navigator.of(context).pop();

      double parsedAmount = double.parse(itemAmount.replaceAll(',', ''));
      double parsedPrice = double.parse(itemPrice.replaceAll(',', ''));
      String parsedQuantity = itemQuantity.replaceAll(',', '');

      final qty_unit = '$parsedQuantity $itemUnit';

      Map<String, dynamic> batchAllocation = {
        'GODOWNNAME': itemLocation,
        'AMOUNT': parsedAmount,
        'ACTUALQTY': qty_unit,
        'BILLEDQTY': qty_unit,
      };

      // Check if the item already exists in the list with the same name and price
      int existingIndex = saleItems.indexWhere(
        (item) =>
            item.itemName == itemName &&
            double.parse(item.itemPrice.toStringAsFixed(decimal!)) ==
                parsedPrice &&
            item.itemUnit == itemUnit,
      );
      if (existingIndex != -1) {
        // Item already exists with the same name, price, and unit, update its quantity and amount
        SaleItem existingItem = saleItems[existingIndex];
        // BigInt, not int - a manually-typed quantity can run past int64
        // range and int.parse() throws FormatException on that instead of
        // silently erroring, crashing the add-item flow outright.
        String newQuantity =
            (BigInt.parse(existingItem.itemQuantity) +
                    BigInt.parse(parsedQuantity))
                .toString();
        double newAmount = parsedPrice * BigInt.parse(newQuantity).toDouble();
        saleItems[existingIndex] = existingItem
            .updateQuantity(newQuantity)
            .updateItemAmount(newAmount);
      } else {
        // Item doesn't exist, create a new SaleItem object and add it to the list
        final newItem = SaleItem(
          itemName: itemName,
          itemQuantity: parsedQuantity,
          itemPrice: parsedPrice,
          itemAmount: parsedAmount,
          itemLocation: itemLocation,
          itemUnit: itemUnit,
          accountingAllocationList: {},
          batchAllocationList: batchAllocation,
          basicUserDescriptions: isUniGasSerial
              ? itemDescriptionControllers
                    .map((c) => c.text.trim())
                    .where((t) => t.isNotEmpty)
                    .toList()
              : const [],
        );

        setState(() {
          saleItems.add(newItem);
          // Rest of your code...
        });
      }
      for (final c in itemDescriptionControllers) {
        c.dispose();
      }
      itemDescriptionControllers = [TextEditingController()];

      setState(() {
        if (saleItems.isEmpty) {
          isVisibleItemHeading = false;
        } else {
          isVisibleItemHeading = true;
        }

        totalPriceOfItems = saleItems.fold(0.0, (
          double previousAmount,
          SaleItem item,
        ) {
          return previousAmount +
              (double.parse(item.itemPrice.toStringAsFixed(decimal!)) *
                  double.parse(item.itemQuantity));
        });

        if (_selectedvatledger != 'Not Applicable') {
          // Calculate the total price of items

          double vat_perc = vatperc / 100;

          totalAmountForVatAppEntries = ledgerEntries
              .where((entry) => entry.vatApp)
              .fold(0.0, (double previousAmount, LedgerEntry entry) {
                return previousAmount + entry.ledgerAmount;
              });

          ledgerVatAmount = totalAmountForVatAppEntries * vat_perc;

          itemsVatAmount = double.parse(
            (totalPriceOfItems * vat_perc).toStringAsFixed(decimal!),
          );
          totalVatAmount = itemsVatAmount + ledgerVatAmount;

          roundedtotalVatAmount = double.parse(
            totalVatAmount.toStringAsFixed(decimal!),
          );

          NumberFormat formatter = NumberFormat(
            '#,##0.${'0' * decimal!}',
            'en_US',
          );
          String formattedVat = formatter.format(roundedtotalVatAmount);
          controller_vatamt.text = formattedVat.toString();
        } else {
          totalVatAmount = 0;
          roundedtotalVatAmount = double.parse(
            totalVatAmount.toStringAsFixed(decimal!),
          );
          NumberFormat formatter = NumberFormat(
            '#,##0.${'0' * decimal!}',
            'en_US',
          );
          String formattedVat = formatter.format(0);
          controller_vatamt.text = formattedVat.toString();
        }

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
        NumberFormat formatter = NumberFormat(
          '#,##0.${'0' * decimal!}',
          'en_US',
        );
        String formattedtotal = formatter.format(roundedtotalAmount);
        controller_totalamt.text = formattedtotal.toString();

        _selecteditem = '${itemdata[0]['name']}';
        if (locationsdata.isNotEmpty) {
          selectedLocation = locationsdata[0];
          setState(() {
            isVisibleLocation = true;
          });
        } else {
          setState(() {
            isVisibleLocation = false;
          });
        }
        _updateUnitDropdown(_selecteditem);
        itemQuantityController.text = 1.toString();
        itemAmountController.clear();
        itemRateController.clear();
      });
    }
  }

  void addLedger() {
    Map<String, dynamic>? specificLedger = ledgerdata.firstWhere(
      (ledger) => ledger['name'] == _selectedledger,
    );

    final ledgerName = specificLedger['name'];
    final ledgerAmount = ledgerAmountController.text;

    int vatApplicable = specificLedger['vatapplicable'];
    final vatApp = vatApplicable == 1 ? true : false;

    if (ledgerName.isNotEmpty && ledgerAmount.isNotEmpty) {
      // Create a new SaleItem object and add it to the list
      Navigator.of(context).pop();
      int existingIndex = ledgerEntries.indexWhere(
        (entry) => entry.ledgerName == ledgerName,
      );
      double parsedAmount = double.parse(ledgerAmount.replaceAll(',', ''));

      if (existingIndex != -1) {
        // Ledger already exists, update its amount
        LedgerEntry existingLedger = ledgerEntries[existingIndex];
        double newAmount = existingLedger.ledgerAmount + parsedAmount;

        // Update vatApp if necessary
        bool newVatApp =
            existingLedger.vatApp; // Initialize with the existing value
        newVatApp = vatApp;

        ledgerEntries[existingIndex] = existingLedger.updateAmount(
          newAmount,
          newVatApp,
        );
      } else {
        // Ledger doesn't exist, create a new LedgerEntry object and add it to the list
        final newItem = LedgerEntry(
          ledgerName: ledgerName,
          ledgerAmount: parsedAmount,
          vatApp: vatApp,
        );
        setState(() {
          ledgerEntries.add(newItem);
        });
      }
      setState(() {
        if (ledgerEntries.isEmpty) {
          isVisibleLedgerHeading = false;
        } else {
          isVisibleLedgerHeading = true;
        }

        totalPriceOfItems = saleItems.fold(0.0, (
          double previousAmount,
          SaleItem item,
        ) {
          return previousAmount +
              (double.parse(item.itemPrice.toStringAsFixed(decimal!)) *
                  double.parse(item.itemQuantity));
        });

        if (_selectedvatledger != 'Not Applicable') {
          // Calculate the total ledger amount for entries with vatApp set to true
          totalAmountForVatAppEntries = ledgerEntries
              .where((entry) => entry.vatApp)
              .fold(0.0, (double previousAmount, LedgerEntry entry) {
                return previousAmount + entry.ledgerAmount;
              });

          double vat_perc = vatperc / 100;

          itemsVatAmount = double.parse(
            (totalPriceOfItems * vat_perc).toStringAsFixed(decimal!),
          );
          ledgerVatAmount = totalAmountForVatAppEntries * vat_perc;

          /*print('Total Ledger Amount for VAT-Applicable Entries: $totalAmountForVatAppEntries');
          print('5% VAT Amount: $ledgerVatAmount');*/

          totalVatAmount = itemsVatAmount + ledgerVatAmount;

          roundedtotalVatAmount = double.parse(
            totalVatAmount.toStringAsFixed(decimal!),
          );
          NumberFormat formatter = NumberFormat(
            '#,##0.${'0' * decimal!}',
            'en_US',
          );
          String formattedVat = formatter.format(roundedtotalVatAmount);
          controller_vatamt.text = formattedVat.toString();
        } else {
          totalVatAmount = 0;
          roundedtotalVatAmount = double.parse(
            totalVatAmount.toStringAsFixed(decimal!),
          );
          NumberFormat formatter = NumberFormat(
            '#,##0.${'0' * decimal!}',
            'en_US',
          );
          String formattedVat = formatter.format(0);
          controller_vatamt.text = formattedVat.toString();
        }
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
        NumberFormat formatter = NumberFormat(
          '#,##0.${'0' * decimal!}',
          'en_US',
        );
        String formattedtotal = formatter.format(roundedtotalAmount);
        controller_totalamt.text = formattedtotal.toString();
        _selectedledger = ledgerdata.isNotEmpty ? ledgerdata[0]['name'] : null;
        ledgerAmountController.clear();
      });
    }
  }

  late String company_trn, company_address, company_emirate, company_country;

  Future<void> _initSharedPreferences() async {
    prefs = await SharedPreferences.getInstance();

    setState(() {
      hostname = prefs.getString('hostname');
      company = prefs.getString('company_name');
      company_lowercase = company!.replaceAll(' ', '').toLowerCase();
      serial_no = prefs.getString('serial_no');
      username = prefs.getString('username');
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
      _dateController.text = saledatetxt;

      // Reference Date defaults to the voucher date itself (not a
      // separately-computed "now") - kept in sync so BILLDATE's
      // ref-no-empty fallback (saledatestring) and this default always
      // agree until the user actually picks a different reference date.
      refdate = saledate;
      refdatestring = saledatestring;
      refdatetxt = saledatetxt;
      _refdateController.text = saledatetxt;

      SecuritybtnAcessHolder = prefs.getString('secbtnaccess');

      String? email_nav = prefs.getString('email_nav');
      String? name_nav = prefs.getString('name_nav');

      itemQuantityController.text = 1.toString();
      controller_vatamt.text = 0.toString();

      controller_totalamt.text = 0.toString();

      if (email_nav != null && name_nav != null) {
        name = name_nav;
        email = email_nav;
      }
      if (SecuritybtnAcessHolder == "True") {
        isRolesVisible = true;
        isUserVisible = true;
      } else {
        isRolesVisible = false;
        isUserVisible = false;
      }
    });
    await loadData();
    if (mounted) {
      setState(() {
        _isInitialDataLoaded = true;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
    _animationController = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    )..repeat(reverse: true);

    _animation = Tween<double>(begin: 1.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _initSharedPreferences();
  }

  bool get isUniGasSerial {
    final currentSerial = serial_no?.trim() ?? '';

    // 👇 put only that one serial here

    return currentSerial == uniGasSerialNumber;
  }

  // vatledgerdata[0] is always the synthetic "Not Applicable" entry added
  // ahead of the API's real VAT ledgers. For UniGas, default to the first
  // real ledger (vatledgerdata[1]) instead of "Not Applicable" - UniGas
  // sales/deliveries are always VAT-applicable in practice. Every other
  // serial keeps the existing "Not Applicable" default.
  String? _defaultVatLedger() {
    if (vatledgerdata.isEmpty) return null;
    if (isUniGasSerial && vatledgerdata.length > 1) {
      return vatledgerdata[1];
    }
    return vatledgerdata[0];
  }

  @override
  void dispose() {
    _textFieldFocusNodeNarration
        .dispose(); // Dispose of the focus node when it's no longer needed.
    _animationController.dispose();
    for (final c in itemDescriptionControllers) {
      c.dispose();
    }
    super.dispose();
  }

  bool isValidEmail(String email) {
    // Simple email validation pattern
    final RegExp emailRegex = RegExp(
      r'^[\w-]+(\.[\w-]+)*@[a-zA-Z0-9-]+(\.[a-zA-Z0-9-]+)*(\.[a-zA-Z]{2,})$',
    );
    return emailRegex.hasMatch(email);
  }

  // Skeleton stand-in for the entry form while the initial dropdown/lookup
  // data (parties, ledgers, items, locations, etc.) is being fetched -
  // replaces the old full-page spinner so the loading state mirrors the
  // shape of the form (label + input pairs) instead of a blank centered spinner.
  Widget _buildSkeletonForm() {
    return ShimmerLoading(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int i = 0; i < 6; i++) ...[
              const ShimmerBox(height: 13, width: 110),
              const SizedBox(height: 8),
              const ShimmerBox(height: 46, borderRadius: 12),
              const SizedBox(height: 18),
            ],
            const ShimmerBox(height: 46, borderRadius: 12),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialDataLoaded) {
      return Scaffold(
        bottomNavigationBar: const AppBottomNav(
          activeTab: AppBottomNavTab.entries,
          activeEntryType: AppEntryType.sales,
        ),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        key: _scaffoldKey,
        appBar: entryAppBar(
          context: context,
          title: "New Sales Entry",
          onBack: () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => PendingSalesEntry()),
            );
          },
        ),
        body: _buildSkeletonForm(),
      );
    }

    final NumberFormat currencyFormat = NumberFormat("#,##0.${'0' * decimal!}");

    final bool canEditVoucherNo =
        SecuritybtnAcessHolder.toString().toLowerCase() == 'true';
    return Scaffold(
      bottomNavigationBar: const AppBottomNav(
        activeTab: AppBottomNavTab.entries,
        activeEntryType: AppEntryType.sales,
      ),
      key: _scaffoldKey,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: entryAppBar(
        context: context,
        title: "New Sales Entry",
        onBack: () {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => PendingSalesEntry()),
          );
        },
      ),
      body: WillPopScope(
        onWillPop: () async {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => PendingSalesEntry()),
          );
          return false;
        },
        child: Stack(
          children: [
            ListView(
              children: [
                Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      const SizedBox(height: 8),

                      // ── Entry Details Section ──
                      EntrySection(
                        icon: Icons.receipt_long_outlined,
                        title: "Entry Details",
                        iconGradient: [
                          app_color,
                          app_color.withValues(alpha: 0.7),
                        ],
                        children: [
                          // Date
                          EntryFormField(
                            label: "Date",
                            icon: Icons.calendar_today,
                            iconGradient: [
                              app_color,
                              app_color.withValues(alpha: 0.7),
                            ],
                            controller: _dateController,
                            readOnly: true,
                            enabled: !isUniGasSerial,
                            suffixIcon: isUniGasSerial
                                ? Icon(
                                    Icons.lock,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  )
                                : null,
                            onTap: isUniGasSerial
                                ? null
                                : () {
                                    _selectsaleDate(context);
                                  },
                          ),

                          // Voucher No
                          EntryFormField(
                            label: "Voucher No.",
                            icon: canEditVoucherNo
                                ? Icons.edit_note_rounded
                                : Icons.confirmation_num_outlined,
                            iconGradient: canEditVoucherNo
                                ? [Colors.teal, Colors.tealAccent]
                                : [
                                    Colors.deepOrangeAccent,
                                    Colors.orangeAccent,
                                  ],
                            controller: _vchnoController,
                            readOnly: !canEditVoucherNo,
                            enabled: canEditVoucherNo,
                            onChanged: canEditVoucherNo
                                ? (value) {
                                    checkVchNoExistence(value.trim());
                                  }
                                : null,
                            keyboardType: TextInputType.text,
                            errorText: errorMessageVchNo.isNotEmpty
                                ? errorMessageVchNo
                                : null,
                            suffixIcon: canEditVoucherNo
                                ? const Icon(
                                    Icons.edit,
                                    color: Colors.teal,
                                    size: 20,
                                  )
                                : Icon(
                                    Icons.lock_outline,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                    size: 20,
                                  ),
                          ),

                          // Info Banner
                          const EntryInfoBanner(
                            text:
                                'Duplicate voucher numbers in Tally will trigger automatic assignment of a new number.',
                          ),

                          // Voucher Type Dropdown
                          EntryDropdownField<String>(
                            label: "Voucher Type",
                            icon: Icons.discount_outlined,
                            iconGradient: [
                              Colors.purpleAccent,
                              Colors.deepPurple,
                            ],
                            value: _selectedvchtypename,
                            locked: isVoucherTypeLocked,
                            hintText: isVoucherTypeLocked
                                ? "Voucher Type Locked"
                                : "Voucher Type",
                            items: vchtypenamedata.map((item) {
                              return DropdownMenuItem<String>(
                                value: item,
                                child: Text(
                                  item,
                                  style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
                                  ),
                                ),
                              );
                            }).toList(),
                            onChanged: (value) async {
                              setState(() {
                                _selectedvchtypename = value!;
                                fetchvchnos(_selectedvchtypename);
                              });
                            },
                          ),

                          // Party Ledger TypeAheadField
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            child: SizedBox(
                              width: MediaQuery.of(context).size.width,
                              child: TypeAheadField<String>(
                                controller: _partyLedgerController,
                                suggestionsCallback: (pattern) async {
                                  return partyledgerdata
                                      .where(
                                        (item) => item.toLowerCase().contains(
                                          pattern.toLowerCase(),
                                        ),
                                      )
                                      .toList();
                                },
                                builder: (context, textController, focusNode) {
                                  return TextField(
                                    controller: textController,
                                    focusNode: focusNode,
                                    style: GoogleFonts.poppins(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface,
                                    ),
                                    decoration: InputDecoration(
                                      hintText:
                                          _selectedpartyledger?.isNotEmpty ==
                                              true
                                          ? _selectedpartyledger
                                          : "Select Party Ledger",
                                      hintStyle: GoogleFonts.poppins(
                                        fontSize: 13,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                      labelText: "Party Ledger",
                                      labelStyle: GoogleFonts.poppins(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                      filled: true,
                                      fillColor:
                                          Theme.of(
                                            context,
                                          ).inputDecorationTheme.fillColor ??
                                          Theme.of(
                                            context,
                                          ).cardColor.withValues(alpha: 0.95),
                                      prefixIcon: Container(
                                        margin: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          gradient: const LinearGradient(
                                            colors: [
                                              Colors.greenAccent,
                                              Colors.teal,
                                            ],
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.person_outline,
                                          color: Colors.white,
                                          size: 20,
                                        ),
                                      ),
                                      suffixIcon: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (_partyLedgerController
                                              .text
                                              .isNotEmpty)
                                            IconButton(
                                              icon: Icon(
                                                Icons.close,
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.onSurfaceVariant,
                                                size: 20,
                                              ),
                                              onPressed: () {
                                                setState(() {
                                                  _partyLedgerController
                                                      .clear();
                                                  _selectedpartyledger = "";
                                                  selectedPartyLedgerPriceLevel =
                                                      null;
                                                });
                                              },
                                            ),
                                          Icon(
                                            Icons.arrow_drop_down,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                          ),
                                          const SizedBox(width: 6),
                                        ],
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(14),
                                        borderSide: BorderSide(
                                          color: Theme.of(context).dividerColor,
                                          width: 1,
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(14),
                                        borderSide: BorderSide(
                                          color: app_color,
                                          width: 1.5,
                                        ),
                                      ),
                                      errorBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(14),
                                        borderSide: const BorderSide(
                                          color: Colors.redAccent,
                                          width: 1.5,
                                        ),
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 16,
                                          ),
                                    ),
                                  );
                                },
                                decorationBuilder: (context, child) {
                                  return Material(
                                    elevation: 6,
                                    borderRadius: BorderRadius.circular(16),
                                    color: Theme.of(context).cardColor,
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(16),
                                      child: child,
                                    ),
                                  );
                                },
                                itemBuilder: (context, String suggestion) {
                                  return ListTile(
                                    title: Text(
                                      suggestion,
                                      style: GoogleFonts.poppins(
                                        fontSize: 13,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurface,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  );
                                },
                                onSelected: (String suggestion) {
                                  setState(() {
                                    _selectedpartyledger = suggestion;
                                    _partyLedgerController.text = suggestion;
                                    selectedPartyLedgerPriceLevel =
                                        partyLedgerPriceLevelMap[suggestion];
                                    debugPrint(
                                      'selected party ledger -> $_selectedpartyledger',
                                    );
                                    debugPrint(
                                      'selected price level -> $selectedPartyLedgerPriceLevel',
                                    );
                                    FocusManager.instance.primaryFocus
                                        ?.unfocus();
                                  });
                                },
                                emptyBuilder: (context) => Padding(
                                  padding: const EdgeInsets.all(12.0),
                                  child: Text(
                                    "No ledger found",
                                    style: GoogleFonts.poppins(
                                      fontSize: 13,
                                      color: Colors.redAccent,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),

                          // Sales Ledger Dropdown
                          EntryDropdownField<String>(
                            label: "Sales Ledger",
                            icon: Icons.sell_outlined,
                            iconGradient: [Colors.blueAccent, Colors.indigo],
                            value: _selectedsalesledger,
                            locked: isSalesLedgerLocked,
                            hintText: isSalesLedgerLocked
                                ? "Sales Ledger Locked"
                                : "Sales Ledger",
                            items: salesledger_data.map((item) {
                              return DropdownMenuItem<String>(
                                value: item.toString(),
                                child: Text(
                                  item.toString(),
                                  style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
                                  ),
                                ),
                              );
                            }).toList(),
                            onChanged: (value) async {
                              setState(() {
                                _selectedsalesledger = value!;
                              });
                            },
                          ),
                        ],
                      ),

                      // ── Reference Section ──
                      EntrySection(
                        icon: Icons.link,
                        title: "Reference",
                        iconGradient: [
                          Colors.pinkAccent,
                          Colors.deepPurpleAccent,
                        ],
                        children: [
                          // Reference Date
                          EntryFormField(
                            label: "Reference Date",
                            icon: Icons.event,
                            iconGradient: [
                              Colors.pinkAccent,
                              Colors.deepPurpleAccent,
                            ],
                            controller: _refdateController,
                            readOnly: true,
                            enableInteractiveSelection: false,
                            onTap: () => _selectrefDate(context),
                          ),

                          // Reference No
                          EntryFormField(
                            label: "Reference No",
                            icon: Icons.link,
                            iconGradient: [Colors.redAccent, Colors.deepOrange],
                            controller: controller_refno,
                            validator: (value) => null,
                          ),
                        ],
                      ),

                      // ── Items Section ──
                      EntrySection(
                        icon: Icons.shopping_cart,
                        title: "Items",
                        iconGradient: [Colors.purple, Colors.blue],
                        trailing: GestureDetector(
                          onTap: () {
                            _showMultiItemSelectPopup(context);
                          },
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                colors: [Colors.indigo, Colors.blueAccent],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.teal.withValues(alpha: 0.3),
                                  blurRadius: 6,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.add,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                        children: [
                          ListView.builder(
                            physics: const NeverScrollableScrollPhysics(),
                            shrinkWrap: true,
                            itemCount: saleItems.length,
                            itemBuilder: (context, index) {
                              final item = saleItems[index];
                              final itemUnit = item.itemUnit;
                              return EntryItemCard(
                                itemName: item.itemName,
                                quantity: item.itemQuantity,
                                unit: itemUnit,
                                rate: '',
                                amount: '',
                                rateWidget: _currencyValueWidget(
                                  currencyFormat.format(
                                    double.parse(
                                      item.itemPrice.toStringAsFixed(
                                        decimal!,
                                      ),
                                    ),
                                  ),
                                  GoogleFonts.poppins(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                amountWidget: _currencyValueWidget(
                                  currencyFormat.format(
                                    double.parse(
                                          item.itemPrice.toStringAsFixed(
                                            decimal!,
                                          ),
                                        ) *
                                        double.parse(item.itemQuantity),
                                  ),
                                  GoogleFonts.poppins(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: app_color,
                                  ),
                                ),
                                onIncrement: () {
                                  int currentQty =
                                      int.tryParse(item.itemQuantity) ?? 0;
                                  setState(() {
                                    item.itemQuantity = (currentQty + 1)
                                        .toString();
                                    _recalculateTotals();
                                  });
                                },
                                onDecrement: () {
                                  int currentQty =
                                      int.tryParse(item.itemQuantity) ?? 0;
                                  if (currentQty > 1) {
                                    setState(() {
                                      item.itemQuantity = (currentQty - 1)
                                          .toString();
                                      _recalculateTotals();
                                    });
                                  } else {
                                    setState(() {
                                      saleItems.removeAt(index);
                                      _recalculateTotals();
                                    });
                                  }
                                },
                                onDelete: () {
                                  _deleteSaleItem(index);
                                },
                              );
                            },
                          ),
                        ],
                      ),

                      // ── Ledger Section ──
                      EntrySection(
                        icon: Icons.list,
                        title: "Ledger",
                        iconGradient: [Colors.red, Colors.redAccent],
                        trailing: GestureDetector(
                          onTap: () {
                            _showLedgerDetailsPopup(context);
                          },
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                colors: [Colors.orange, Colors.orange],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.teal.withValues(alpha: 0.3),
                                  blurRadius: 6,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.add,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                        children: [
                          ListView.builder(
                            physics: const NeverScrollableScrollPhysics(),
                            shrinkWrap: true,
                            itemCount: ledgerEntries.length,
                            itemBuilder: (context, index) {
                              final item = ledgerEntries[index];
                              return EntryLedgerCard(
                                ledgerName: item.ledgerName,
                                amount: '',
                                amountWidget: _currencyValueWidget(
                                  currencyFormat.format(item.ledgerAmount),
                                  GoogleFonts.poppins(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.indigo,
                                  ),
                                ),
                                onDelete: () {
                                  _deleteLedger(index);
                                },
                              );
                            },
                          ),
                        ],
                      ),

                      // ── Receiver Information Section (UniGas only) ──
                      if (isUniGasSerial)
                        EntrySection(
                          icon: Icons.assignment_ind_outlined,
                          title: "Receiver Information",
                          iconGradient: [Colors.teal, Colors.tealAccent],
                          children: [
                            EntryFormField(
                              label: "Receiver Name *",
                              icon: Icons.person_outline,
                              iconGradient: [Colors.teal, Colors.tealAccent],
                              controller: receiverNameController,
                            ),
                            EntryFormField(
                              label: "Receiver Mobile",
                              icon: Icons.phone_outlined,
                              iconGradient: [Colors.blue, Colors.blueAccent],
                              controller: receiverMobileController,
                              keyboardType: TextInputType.phone,
                              validator: (value) => null,
                            ),
                            ReceiverSignatureTile(
                              signatureBytes: receiverSignatureBytes,
                              onCaptured: (bytes) => setState(() {
                                receiverSignatureBytes = bytes;
                              }),
                            ),
                          ],
                        ),

                      // ── VAT Section ──
                      EntrySection(
                        icon: Icons.receipt_long_outlined,
                        title: "VAT",
                        iconGradient: [Colors.indigo, Colors.cyan],
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            child: Row(
                              children: [
                                // VAT Ledger Dropdown
                                Expanded(
                                  child: SearchableSelectorField<String>(
                                    label: "VAT Ledger",
                                    hintText: "Select VAT Ledger",
                                    icon: Icons.receipt_long_outlined,
                                    iconGradient: const [
                                      Colors.indigo,
                                      Colors.cyan,
                                    ],
                                    borderRadius: 14,
                                    fillColor:
                                        Theme.of(context).brightness ==
                                            Brightness.dark
                                        ? Theme.of(
                                            context,
                                          ).colorScheme.surfaceContainerHighest
                                        : Colors.grey.shade100,
                                    value: _selectedvatledger,
                                    items: vatledgerdata,
                                    itemLabel: (item) => item,
                                    onChanged: (value) {
                                      setState(() {
                                        _selectedvatledger = value!;

                                        totalPriceOfItems = saleItems.fold(
                                          0.0,
                                          (double prev, SaleItem item) =>
                                              prev +
                                              (double.parse(
                                                    item.itemPrice
                                                        .toStringAsFixed(
                                                          decimal!,
                                                        ),
                                                  ) *
                                                  double.parse(
                                                    item.itemQuantity,
                                                  )),
                                        );

                                        totalAmountOfLedgers = ledgerEntries
                                            .fold(
                                              0.0,
                                              (
                                                double prev,
                                                LedgerEntry entry,
                                              ) => prev + entry.ledgerAmount,
                                            );

                                        if (_selectedvatledger ==
                                            'Not Applicable') {
                                          totalVatAmount = 0;
                                          roundedtotalVatAmount = double.parse(
                                            totalVatAmount.toStringAsFixed(
                                              decimal!,
                                            ),
                                          );
                                          NumberFormat formatter = NumberFormat(
                                            '#,##0.${'0' * decimal!}',
                                            'en_US',
                                          );
                                          controller_vatamt.text = formatter
                                              .format(0);
                                        } else {
                                          double
                                          totalAmountForLedgerVatAppEntries =
                                              ledgerEntries
                                                  .where(
                                                    (entry) => entry.vatApp,
                                                  )
                                                  .fold(
                                                    0.0,
                                                    (
                                                      double prev,
                                                      LedgerEntry entry,
                                                    ) =>
                                                        prev +
                                                        entry.ledgerAmount,
                                                  );

                                          double vat_perc = vatperc / 100;
                                          itemsVatAmount = double.parse(
                                            (totalPriceOfItems * vat_perc)
                                                .toStringAsFixed(decimal!),
                                          );
                                          ledgerVatAmount =
                                              totalAmountForLedgerVatAppEntries *
                                              vat_perc;
                                          totalVatAmount =
                                              itemsVatAmount + ledgerVatAmount;

                                          roundedtotalVatAmount = double.parse(
                                            totalVatAmount.toStringAsFixed(
                                              decimal!,
                                            ),
                                          );
                                          NumberFormat formatter = NumberFormat(
                                            '#,##0.${'0' * decimal!}',
                                            'en_US',
                                          );
                                          controller_vatamt.text = formatter
                                              .format(roundedtotalVatAmount);
                                        }

                                        totalAmount =
                                            totalPriceOfItems +
                                            totalAmountOfLedgers +
                                            totalVatAmount;
                                        roundedtotalAmount = double.parse(
                                          totalAmount.toStringAsFixed(decimal!),
                                        );
                                        NumberFormat formatter = NumberFormat(
                                          '#,##0.${'0' * decimal!}',
                                          'en_US',
                                        );
                                        controller_totalamt.text = formatter
                                            .format(roundedtotalAmount);
                                      });
                                    },
                                  ),
                                ),

                                const SizedBox(width: 10),

                                // VAT Amount
                                Expanded(
                                  child: TextFormField(
                                    enabled: false,
                                    controller: controller_vatamt,
                                    style: GoogleFonts.poppins(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface,
                                    ),
                                    decoration: InputDecoration(
                                      labelText: "VAT Amount",
                                      labelStyle: GoogleFonts.poppins(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                        fontWeight: FontWeight.w500,
                                        fontSize: 13,
                                      ),
                                      prefix: Container(
                                        margin: const EdgeInsets.only(right: 8),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          gradient: const LinearGradient(
                                            colors: [Colors.green, Colors.teal],
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: currencySymbolWidget(
                                          currencycode,
                                          getCurrencySymbol(currencycode),
                                          GoogleFonts.poppins(
                                            color: Colors.white,
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      filled: true,
                                      fillColor:
                                          Theme.of(context).brightness ==
                                              Brightness.dark
                                          ? Theme.of(context)
                                                .colorScheme
                                                .surfaceContainerHighest
                                          : Colors.grey.shade100,
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(14),
                                        borderSide: BorderSide(
                                          color: Theme.of(context).dividerColor,
                                          width: 1,
                                        ),
                                      ),
                                      disabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(14),
                                        borderSide: BorderSide(
                                          color: Theme.of(context).dividerColor,
                                          width: 1,
                                        ),
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 14,
                                          ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      // ── Narration Section ──
                      EntrySection(
                        icon: Icons.notes_rounded,
                        title: "Narration",
                        iconGradient: [Colors.pinkAccent, Colors.deepOrange],
                        children: [
                          EntryFormField(
                            label: "Narration",
                            icon: Icons.notes_rounded,
                            iconGradient: [
                              Colors.pinkAccent,
                              Colors.deepOrange,
                            ],
                            controller: controller_narration,
                            validator: (value) => null,
                            maxLines: 3,
                          ),
                        ],
                      ),

                      // ── Total Amount ──
                      EntryTotalBar(
                        label: "Total Amount",
                        value: controller_totalamt.text.isNotEmpty
                            ? controller_totalamt.text
                            : "0.00",
                        currencySymbol: getCurrencySymbol(currencycode),
                        currencyCode: currencycode,
                      ),

                      // ── Save Button ──
                      EntrySaveButton(
                        label: "Save",
                        onPressed: errorMessageVchNo.isNotEmpty
                            ? null
                            : () {
                                if (_formKey.currentState != null &&
                                    _formKey.currentState!.validate()) {
                                  _formKey.currentState!.save();
                                  saveEntry();
                                }
                              },
                      ),

                      const SizedBox(height: 30),
                    ],
                  ),
                ),
              ],
            ),
            Visibility(
              visible: _isLoading,
              child: Center(child: AppLogoLoader()),
            ),
          ],
        ),
      ),
    );
  }
}
