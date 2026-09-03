import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:FincoreGo/Items.dart';
import 'package:FincoreGo/PendingDeliveryNoteEntry.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'constants.dart';
import 'package:FincoreGo/widgets/app_bottom_nav.dart';
import 'widgets/entry_widgets.dart';
import 'widgets/signature_capture.dart';
import 'widgets/searchable_selector.dart';
import 'providers/delivery_note_registration_notifier.dart';
import 'api/price_level_repository.dart';
import 'api/monthly_bucket_helper.dart' show parseCompactDate;

class Deliverynoteregistration extends ConsumerStatefulWidget {
  const Deliverynoteregistration({Key? key}) : super(key: key);
  @override
  ConsumerState<Deliverynoteregistration> createState() =>
      _DeliverynoteregistrationPageState();
}

// Debug helper for the experimental bulk multi-item add: records which
// source (Price Level / Item Rate / Empty) an item's rate came from.
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
  final String meterFrom;
  final String meterTo;
  // UniGas-only, user-typed free-text description lines for this item
  // (Tally's "Basic User Description" on a stock item) - each entry here
  // becomes its own BASICUSERDESCRIPTION.LIST object, one item can have
  // several (matching the multiple separate single-line boxes in the UI).
  // Empty list when none entered - no BASICUSERDESCRIPTION.LIST is sent.
  final List<String> basicUserDescriptions;
  // tally-api migration: the stock item's tally-api `masterId`, needed to
  // build a `voucher-entries` inventoryEntries[].stockItemMasterId at
  // submit time (the legacy create endpoint only needed the item NAME).
  // Nullable only so older in-memory items constructed before this field
  // existed (there are none at runtime, but keeps the constructor
  // non-breaking) still compile; saveEntry() resolves a null masterId by
  // name against `_stockItemsRaw` as a fallback.
  final int? itemMasterId;

  SaleItem({
    required this.itemName,
    required this.itemQuantity,
    required this.itemPrice,
    required this.itemAmount,

    required this.itemLocation,
    required this.itemUnit,
    required this.accountingAllocationList,
    required this.batchAllocationList,
    required this.meterFrom,
    required this.meterTo,
    this.basicUserDescriptions = const [],
    this.itemMasterId,
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
      meterFrom: this.meterFrom,
      meterTo: this.meterTo,
      basicUserDescriptions: this.basicUserDescriptions,
      itemMasterId: this.itemMasterId,
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
      meterFrom: this.meterFrom,
      meterTo: this.meterTo,
      basicUserDescriptions: this.basicUserDescriptions,
      itemMasterId: this.itemMasterId,
    );
  }
}

class Unit {
  final String name;
  final double multiplier;

  Unit({required this.name, required this.multiplier});

  factory Unit.fromJson(Map<String, dynamic> json) {
    return Unit(
      name: json['name'] ?? '',
      multiplier: double.tryParse(json['multiplier']?.toString() ?? '0') ?? 0,
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

class _DeliverynoteregistrationPageState
    extends ConsumerState<Deliverynoteregistration>
    with TickerProviderStateMixin {
  DeliveryNoteRegistrationNotifier get _notifier =>
      ref.read(deliveryNoteRegistrationNotifierProvider.notifier);
  DeliveryNoteRegistrationState get _s =>
      ref.read(deliveryNoteRegistrationNotifierProvider);

  String? meterReadingError;

  TextEditingController _itemController = TextEditingController();
  TextEditingController _partyLedgerController = TextEditingController();
  String? selectedPartyLedgerPriceLevel;

  final TextEditingController voucherStartReadingController =
      TextEditingController();
  final TextEditingController voucherEndReadingController =
      TextEditingController();

  String? selectedItemMasterId;
  bool isPriceLevelLoading = false;

  // Customer mobile/email for the selected party ledger - fetched in
  // loadLedgerData() alongside TRN/address/emirate/country, used by the
  // UniGas POS delivery note PDF format.
  bool isRateFieldEnabled = true;

  bool showRateField = true;

  // UniGas bulk delivery only - Receiver Information shown on the printed
  // Bulk Gas Delivery Note. Name/Signature is mandatory before saving;
  // Mobile/EID# are optional. Left blank, the PDF just shows dotted
  // pen-fill lines instead (see _generateUniGasBulkDeliveryNotePDF).
  final TextEditingController bulkReceiverNameController =
      TextEditingController();
  final TextEditingController bulkReceiverMobileController =
      TextEditingController();
  final TextEditingController bulkReceiverEidController =
      TextEditingController();

  // UniGas bulk delivery only - the receiver's on-screen drawn signature,
  // captured via _showSignatureCapturePad(), embedded as an image in the
  // printed Bulk Gas Delivery Note. Null until captured.
  Uint8List? bulkReceiverSignatureBytes;

  final FocusNode _textFieldFocusNodeNarration = FocusNode();

  late AnimationController _animationController;
  late Animation<double> _animation;

  /// tally-api migration: replaces legacy's `GET
  /// /api/item/getPriceLevelDetails/:company/:serial` (a single-row,
  /// server-filtered-by-date/item/price-level-name lookup) with
  /// `PriceLevelRepository.ratesForItem`, which returns every price-level
  /// row tally-api has for that item; this filters to [priceLevelName] and
  /// picks the most recent row whose `date` is on/before [asOfYyyyMMdd]
  /// client-side (Tally price lists are "effective from" a date, so the
  /// latest one not in the future is the one that applies) - the closest
  /// equivalent to what the legacy endpoint's own `date` query param did
  /// server-side. Returns null on no match/any error, same as legacy's
  /// "no rate" empty-list branch did.
  Future<double?> _lookupPriceLevelRate({
    required int stockItemMasterId,
    required String priceLevelName,
    required String asOfYyyyMMdd,
  }) async {
    try {
      final DateTime asOf = parseCompactDate(asOfYyyyMMdd);
      final rows = await PriceLevelRepository.instance.ratesForItem(
        stockItemMasterId,
      );
      final matching = rows.where(
        (r) => r['priceLevelName']?.toString() == priceLevelName,
      );
      DateTime? bestDate;
      double? bestRate;
      for (final row in matching) {
        final rowDate = DateTime.tryParse(row['date']?.toString() ?? '');
        if (rowDate == null || rowDate.isAfter(asOf)) continue;
        if (bestDate == null || rowDate.isAfter(bestDate)) {
          final rate = _parseCompoundRate(row['rate']);
          if (rate != null) {
            bestDate = rowDate;
            bestRate = rate;
          }
        }
      }
      return bestRate;
    } catch (e) {
      debugPrint('Price level lookup failed: $e');
      return null;
    }
  }

  // Recomputed totals/formatted VAT+total text after any notifier mutation
  // that touches saleItems/ledgerEntries/VAT ledger - mirrors the inline
  // `controller_vatamt.text = ...`/`controller_totalamt.text = ...`
  // formatting duplicated across the pre-migration `setState` blocks this
  // replaces (those two controllers are widget-local `TextEditingController`s,
  // so they can't just read the notifier's state directly).
  void _syncTotalsControllers() {
    controller_vatamt.text = _s.formattedVatAmount;
    controller_totalamt.text = _s.formattedTotalAmount;
  }

  void _deleteLedger(int index) {
    _notifier.deleteLedger(index);
    _syncTotalsControllers();
  }

  void _deleteSaleItem(int index) {
    _notifier.deleteSaleItem(index);
    _syncTotalsControllers();
  }

  String formatitemKey(int key) {
    key++;
    String keyy = key.toString();
    return keyy;
  }

  String convertAmountToWords(num amount) {
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
    String decimalPartStr = formattedAmount.split('.')[1];
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

  // ---- read-only aliases onto notifier state (migrated fields) ----------
  // Same-named getters delegating to `_s`, rather than per-method local
  // aliases - this screen's fields are read from dozens of scattered
  // methods/dialogs (PDF generators, save validation, reset flows), so this
  // is the "many read sites" case the migration convention calls for (see
  // `receipt_registration_notifier.dart`'s widget for the same treatment).
  bool get isVisibleItemHeading => _s.isVisibleItemHeading;
  bool get isVisibleLedgerHeading => _s.isVisibleLedgerHeading;
  double get roundedtotalVatAmount => _s.roundedTotalVatAmount;
  double get roundedtotalAmount => _s.roundedTotalAmount;
  List<String> get salesledger_data => _s.salesLedgerData;
  int? get decimal => _s.decimal;
  List<String> get vchtypenamedata => _s.vchTypeNameData;
  List<String> get partyledgerdata => _s.partyLedgerData;
  List<String> get vatledgerdata => _s.vatLedgerData;
  List<dynamic> get itemdata => _s.itemData;
  double get vatperc => _s.vatperc;
  List<String> get locationsdata => _s.locationsData;
  List<Map<String, dynamic>> get ledgerdata => _s.ledgerData;
  String get token => _s.token;
  String get name => _s.name;
  String get saledatestring => _s.saledatestring;
  String get saledatetxt => _s.saledatetxt;
  String get refdatestring => _s.refdatestring;
  String get refdatetxt => _s.refdatetxt;
  Map<String, String?> get partyLedgerPriceLevelMap =>
      _s.partyLedgerPriceLevelMap;
  String? get company => _s.company;
  String? get serial_no => _s.serialNo;
  String? get SecuritybtnAcessHolder => _s.securitybtnAccessHolder;
  String get company_trn => _s.companyTrn;
  String get company_address => _s.companyAddress;
  String get company_emirate => _s.companyEmirate;
  String get company_country => _s.companyCountry;
  DateTime get saledate => _s.saledate;
  DateTime get refdate => _s.refdate;
  String get currencycode => _s.currencyCode;
  List<String> get vchnos => _s.vchNos;
  String get errorMessageVchNo => _s.errorMessageVchNo;
  List<SaleItem> get saleItems => _s.saleItems;
  List<LedgerEntry> get ledgerEntries => _s.ledgerEntries;
  double get ledgerVatAmount => _s.ledgerVatAmount;
  double get itemsVatAmount => _s.itemsVatAmount;
  double get totalVatAmount => _s.totalVatAmount;
  double get totalAmount => _s.totalAmount;
  double get totalPriceOfItems => _s.totalPriceOfItems;
  double get totalAmountForVatAppEntries => _s.totalAmountForVatAppEntries;
  double get totalAmountOfLedgers => _s.totalAmountOfLedgers;
  bool get isVoucherTypeLocked => _s.isVoucherTypeLocked;
  bool get isSalesLedgerLocked => _s.isSalesLedgerLocked;
  bool get isGodownLocked => _s.isGodownLocked;
  bool get _isLoading => _s.isLoading;
  bool get _isInitialDataLoaded => _s.isInitialDataLoaded;
  dynamic get _selectedvchtypename => _s.selectedVchTypeName;
  dynamic get _selectedpartyledger => _s.selectedPartyLedger;
  dynamic get _selectedsalesledger => _s.selectedSalesLedger;
  dynamic get _selectedvatledger => _s.selectedVatLedger;
  String? get _selectedPartyMobile => _s.selectedPartyMobile;
  String? get _selectedPartyEmail => _s.selectedPartyEmail;
  bool? get _isBulkDelivery => _s.isBulkDelivery;

  bool isVisibleUnit = true;

  final _formKey = GlobalKey<FormState>();

  bool isVisibleLocation = false;

  GlobalKey<FormState> _itemFormkey = GlobalKey<FormState>();

  GlobalKey<FormState> _ledgerFormkey = GlobalKey<FormState>();

  late String selectedLocation = ''; // Store the selected location here

  List<Unit> unitdata = [];

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  late GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey;
  late SharedPreferences prefs;

  /// tally-api's stock item `rate` fields (e.g. `stardardPrice`,
  /// `lastSalePrice`) and the price-levels `rate` field are all Tally's
  /// compound "value/unit" string (e.g. "100.00/Nos"), not a plain number -
  /// this strips the unit suffix.
  double? _parseCompoundRate(dynamic value) {
    if (value == null) return null;
    final String text = value.toString();
    if (text.isEmpty || text.toLowerCase() == 'null') return null;
    final String numericPart = text.split('/').first.trim();
    return double.tryParse(numericPart);
  }


  dynamic _selectedledger, _selecteditem, _selectedunit;

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

  double selectedMultiplier = 0.0;

  final DateFormat _dateFormat = DateFormat('yyyyMMdd');

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

  void checkVchNoExistence(String vchNo) {
    _notifier.checkVchNoExistence(vchNo);
  }

  String generateNextVchNo(List<String> vchnos) {
    return _notifier.generateNextVchNo(vchnos);
  }

  // Estimates how much extra bottom padding the LAST item row needs so the
  // item table's own borders/dividers stretch to roughly fill the remaining
  // page space, instead of leaving a blank gap before the signatory box.
  // This is an approximation (a real `pw.Table` can never be wrapped in
  // `pw.Expanded` to measure exact remaining space — the library throws
  // 'Cannot have a spanning widget flexible' for that combination), based on
  // typical section heights on an A4 page.
  double _estimateLastRowFillerPadding(int itemCount) {
    // Calibrated against actual rendered output on an A4 page: with the
    // default 5pt padding, a 1-item delivery note's content ends ~637pt
    // from the top (includes the 110pt-tall UniGas logo), and each extra
    // item adds ~29.7pt. The usable content area ends at ~785pt from the
    // top (page height minus top/bottom margins), so the gap left to fill
    // is the difference between the two.
    const double targetContentEnd = 745.0;
    const double baselineForOneItem = 637.4;
    const double perItemHeight = 29.7;

    final double baseline =
        baselineForOneItem + (itemCount - 1) * perItemHeight;
    final double remaining = targetContentEnd - baseline;
    return remaining.clamp(5.0, 260.0);
  }

  Future<void> generateDeliveryNotePDF(
    String trn,
    String address,
    String emirate,
    String country,
  ) async {
    // UniGas now uses a completely separate POS delivery note format (the old
    // A4-style layout with hidden rate/amount columns is retired for
    // this serial type) - see _generateUniGasDeliveryNotePDF. Bulk (tanker)
    // deliveries use a wholly different "Delivery Note - Bulk Gas" format -
    // see _generateUniGasBulkDeliveryNotePDF.
    if (isUniGasMeterReadingSerial) {
      if (_isBulkDelivery == true) {
        await _generateUniGasBulkDeliveryNotePDF(
          trn,
          address,
          emirate,
          country,
        );
      } else {
        await _generateUniGasDeliveryNotePDF(trn, address, emirate, country);
      }
      return;
    }

    final pdf = pw.Document();

    // BigInt, not int - a manually-typed quantity can run past int64 range
    // and int.parse() throws FormatException on that instead of silently
    // erroring, crashing PDF generation outright (see the meter-reading
    // BigInt fix above for the same overflow class of bug).
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

    final startReading = voucherStartReadingController.text.trim();
    final endReading = voucherEndReadingController.text.trim();

    final meterReadingText = startReading.isEmpty && endReading.isEmpty
        ? ''
        : '${startReading.isEmpty ? 'No Value' : startReading} - ${endReading.isEmpty ? 'No Value' : endReading}';

    List<String> placeParts = [];

    // Address
    if (address != null &&
        address != "null" &&
        address != "Not Available" &&
        address.trim().isNotEmpty) {
      placeParts.add(address.trim());
    }
    if (emirate != null &&
        emirate != "null" &&
        emirate != "Not Available" &&
        emirate.trim().isNotEmpty) {
      placeParts.add(emirate.trim());
    }

    // Country
    if (country != null &&
        country != "null" &&
        country != "Not Available" &&
        country.trim().isNotEmpty) {
      placeParts.add(country.trim());
    }

    String placeOfSupply = placeParts.join(", ");

    pw.MemoryImage? uniGasLogo;
    if (isUniGasMeterReadingSerial) {
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
            if (uniGasLogo != null)
              pw.Center(
                child: pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 8),
                  child: pw.Image(uniGasLogo, height: 110),
                ),
              ),
            // Tax Invoice Heading
            pw.Header(
              level: 0,
              decoration: pw.BoxDecoration(
                border: pw.Border(bottom: pw.BorderSide.none),
              ),

              child: pw.Center(
                child: pw.Text(
                  'Delivery Note',
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

                          if (company_address != "null" &&
                              company_address != "Not Available")
                            pw.Column(
                              children: [
                                pw.SizedBox(height: 2),

                                pw.Text(company_address),
                              ],
                            ),

                          if (company_emirate != "null" &&
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

                          if (company_country != "null" &&
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

                          if (company_trn != "null" &&
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

                          pw.SizedBox(height: 20),
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
                                        pw.Text('Delivery Note No:'),
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

                          if (placeOfSupply.isNotEmpty)
                            pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                pw.SizedBox(height: 2),

                                pw.Row(
                                  crossAxisAlignment:
                                      pw.CrossAxisAlignment.start,
                                  children: [
                                    pw.Text("Place of Supply :"),

                                    pw.SizedBox(width: 5),

                                    pw.Expanded(child: pw.Text(placeOfSupply)),
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

                          pw.SizedBox(height: 20),
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
                      if (!isUniGasMeterReadingSerial)
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
                      if (!isUniGasMeterReadingSerial)
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
                      if (!isUniGasMeterReadingSerial)
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
                              'Amount',
                              style: pw.TextStyle(fontSize: 10),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),

            // NOTE: these tables are intentionally NOT wrapped in a
            // Container/Column (unlike before) — pw.MultiPage can only
            // split a pw.Table row-by-row across pages when the Table
            // is a direct top-level widget. Wrapping it breaks that
            // splitting entirely (every row gets deferred to the next
            // page, leaving a blank gap). The left/right border lines
            // are added directly on each Table's own TableBorder
            // instead, so the vertical box lines still show.
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
                  top: pw.BorderSide.none,
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
                              item.key == saleItems.length - 1
                                  ? _estimateLastRowFillerPadding(
                                      saleItems.length,
                                    )
                                  : 5.0,
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
                            padding: pw.EdgeInsets.fromLTRB(
                              5,
                              5,
                              5,
                              item.key == saleItems.length - 1
                                  ? _estimateLastRowFillerPadding(
                                      saleItems.length,
                                    )
                                  : 5.0,
                            ),
                            alignment: pw.Alignment.topLeft,

                            child: pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                pw.Text(
                                  item.value.itemName,
                                  style: pw.TextStyle(fontSize: 10),
                                ),
                                if (isUniGasMeterReadingSerial &&
                                    item.value.meterFrom.isNotEmpty &&
                                    item.value.meterTo.isNotEmpty)
                                  pw.Text(
                                    'Meter Reading: ${item.value.meterFrom} - ${item.value.meterTo}',
                                    style: pw.TextStyle(
                                      fontSize: 7,
                                      fontStyle: pw.FontStyle.italic,
                                      color: PdfColors.grey500,
                                    ),
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
                              item.key == saleItems.length - 1
                                  ? _estimateLastRowFillerPadding(
                                      saleItems.length,
                                    )
                                  : 5.0,
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
                        if (!isUniGasMeterReadingSerial)
                          pw.Expanded(
                            flex: 1,
                            child: pw.Container(
                              padding: pw.EdgeInsets.fromLTRB(5, 5, 5, 5),
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
                              item.key == saleItems.length - 1
                                  ? _estimateLastRowFillerPadding(
                                      saleItems.length,
                                    )
                                  : 5.0,
                            ),
                            alignment: pw.Alignment.center,
                            child: pw.Text(
                              item.value.itemUnit,
                              textAlign: pw.TextAlign.center,
                              style: pw.TextStyle(fontSize: 10),
                            ),
                          ),
                        ),
                        if (!isUniGasMeterReadingSerial)
                          pw.Expanded(
                            flex: 1,
                            child: pw.Container(
                              padding: pw.EdgeInsets.fromLTRB(5, 5, 5, 5),
                              alignment: pw.Alignment.center,
                              child: pw.Text(
                                '',
                                style: pw.TextStyle(fontSize: 10),
                              ),
                            ),
                          ),

                        if (!isUniGasMeterReadingSerial)
                          pw.Expanded(
                            flex: 2,
                            child: pw.Container(
                              padding: pw.EdgeInsets.fromLTRB(5, 5, 5, 5),
                              alignment: pw.Alignment.centerRight,
                              child: pw.Text(
                                formatAmountInvoice(
                                  item.value.itemAmount.toStringAsFixed(
                                    decimal!,
                                  ),
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

              if (!isUniGasMeterReadingSerial)
                pw.Table(
                  border: pw.TableBorder(
                    left: pw.BorderSide(width: 1.0),
                    right: pw.BorderSide(width: 1.0),
                    horizontalInside: pw.BorderSide.none,
                    verticalInside: pw.BorderSide(
                      color: PdfColor.fromHex('#050400'),
                    ),
                    top: pw.BorderSide.none,
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
                            child: pw.Text(
                              '',
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
                              '',
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

              if (!isUniGasMeterReadingSerial && ledgerEntries.isNotEmpty)
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
                      top: pw.BorderSide.none,
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

              if (!isUniGasMeterReadingSerial &&
                  vatledgerdata.isNotEmpty &&
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
                    top: pw.BorderSide.none,
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
              if (!isUniGasMeterReadingSerial)
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
                              formatAmountInvoice(
                                roundedtotalAmount.toString(),
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

              if (!isUniGasMeterReadingSerial)
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
            ],

            // declaration table
            pw.Container(
              decoration: pw.BoxDecoration(
                border: pw.Border(
                  left: pw.BorderSide(width: 1.0),
                  right: pw.BorderSide(width: 1.0),
                  bottom: pw.BorderSide(width: 1.0),
                  top: pw.BorderSide(color: PdfColor.fromHex('#050400')),
                ),
              ),
              child: pw.Table(
                border: pw.TableBorder(
                  verticalInside: pw.BorderSide(
                    color: PdfColor.fromHex('#050400'),
                  ),
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
                            mainAxisSize: pw.MainAxisSize.min,
                            mainAxisAlignment: pw.MainAxisAlignment.start,
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.SizedBox(height: 10),

                              pw.Text(
                                'Recd. in Good Condition',
                                textAlign: pw.TextAlign.left,
                                style: pw.TextStyle(fontSize: 10),
                              ),

                              pw.SizedBox(height: 55),
                            ],
                          ),
                        ),
                      ),

                      pw.Expanded(
                        flex: 1,
                        child: pw.Container(
                          padding: pw.EdgeInsets.fromLTRB(5, 5, 5, 5),

                          // Left, Top, Right, Bottom
                          alignment: pw.Alignment.topCenter,

                          child: pw.Column(
                            mainAxisSize: pw.MainAxisSize.min,
                            mainAxisAlignment: pw.MainAxisAlignment.start,
                            crossAxisAlignment: pw.CrossAxisAlignment.center,
                            children: [
                              pw.SizedBox(height: 10),

                              pw.Text(
                                'for $company',
                                textAlign: pw.TextAlign.center,
                                style: pw.TextStyle(fontSize: 10),
                              ),

                              pw.SizedBox(height: 55),

                              pw.Text(
                                'Authorised Signatory',
                                textAlign: pw.TextAlign.left,
                                style: pw.TextStyle(fontSize: 10),
                              ),

                              pw.SizedBox(height: 5),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            pw.Container(
              padding: pw.EdgeInsets.fromLTRB(
                5,
                5,
                5,
                5,
              ), // Left, Top, Right, Bottom
              alignment: pw.Alignment.center,

              child: pw.Text(
                'This is a System Generated Document',
                textAlign: pw.TextAlign.left,
                style: pw.TextStyle(fontSize: 10),
              ),
            ),
          ];
        },
      ),
    );

    // 🗂 Save to temp file
    final pdfData = await pdf.save();
    final now = DateTime.now();
    final formattedDate =
        "${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}";

    final dir = await getApplicationDocumentsDirectory();
    final filePath = '${dir.path}/DeliveryNote_$formattedDate.pdf';
    debugPrint("PDF PATH: $filePath");
    final file = File(filePath);
    await file.writeAsBytes(pdfData);

    await Share.shareXFiles([
      XFile(filePath, mimeType: 'application/pdf'),
    ], text: 'Sharing Delivery Note for $_selectedpartyledger');

    _resetDeliveryNoteFormAfterShare();
  }

  // Shared by both the standard A4 PDF path and the UniGas POS delivery note path:
  // clears the form and recomputes totals after a delivery note is shared.
  void _resetDeliveryNoteFormAfterShare() {
    // Drop focus first - otherwise clearing a party/ledger TypeAheadField's
    // text below while it still has focus makes it re-run its
    // suggestionsCallback('') (which matches everything) and pop its
    // suggestions overlay back open right after reset. A bare unfocus()
    // leaves the scope's "last focused descendant" pointer intact, so a
    // dialog pop just before this can still silently hand focus straight
    // back to that field - requesting a disposable FocusNode instead fully
    // severs that link.
    FocusScope.of(context).requestFocus(FocusNode());

    // UniGas only: this reset runs right after printUniGasPdf's full-screen
    // printing animation dialog pops itself (Navigator.pop() inside a
    // delayed callback, not synchronously with this function). Navigator's
    // own focus-restoration-to-previous-route can land on the NEXT frame,
    // after the drop above already ran - reclaiming focus for the Party
    // field and popping its suggestions list back open. A second drop
    // scheduled for the next frame beats that race instead of just the
    // first one.
    if (isUniGasMeterReadingSerial) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) FocusScope.of(context).requestFocus(FocusNode());
      });
    }

    controller_narration.clear();
    controller_refno.clear();

    _textFieldFocusNodeNarration.unfocus(); // Unfocus the TextField

    // Migrated-state half (saledate/refdate/party ledger/sales+VAT ledger
    // defaults/saleItems+ledgerEntries clear+totals recompute/isBulkDelivery
    // reset) - see `resetAfterShare`'s doc-comment.
    _notifier.resetAfterShare();
    _syncTotalsControllers();

    _dateController.text = saledatetxt;
    _refdateController.text = refdatetxt;
    // Don't reassign _selectedvchtypename here - for UniGas it's locked
    // to the allocation-assigned voucher type, and shouldn't fall back
    // to the first option on reset like a manually-selected one would.
    fetchvchnos(_selectedvchtypename);
    _partyLedgerController.clear();
    voucherStartReadingController.clear();
    voucherEndReadingController.clear();
    bulkReceiverNameController.clear();
    bulkReceiverMobileController.clear();
    bulkReceiverEidController.clear();
    bulkReceiverSignatureBytes = null;

    setState(() {
      _selectedledger = ledgerdata.isNotEmpty ? ledgerdata[0]['name'] : null;

      _selecteditem = '${itemdata[0]['name']}';
      _itemController.text = _selecteditem;
      if (locationsdata.isNotEmpty) {
        selectedLocation = locationsdata[0];
        isVisibleLocation = true;
      } else {
        isVisibleLocation = false;
      }
      _updateUnitDropdown(_selecteditem);

      _isFocused_vchno = false;
      _isFocused_item = false;
      _isFocused_unit = false;
      _isFocused_ledger = false;
      _isFocused_narration = false;
      _isFocused_totalamt = false;
      _isFocused_vatamt = false;
    });

    // The print flow's full-screen animation dialog can restore focus to
    // whatever field was active before it was shown once its route pops -
    // that restoration lands a frame after the unfocus() above, so it can
    // win the race and pop the Party Ledger suggestions back open. Unfocus
    // again once that settles to make sure it sticks.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusManager.instance.primaryFocus?.unfocus();
    });
  }

  // Narrow POS delivery note format required by UniGas for their thermal
  // printer/POS device (~76mm / 216pt wide, single continuous page).
  // Company header details (name, tagline, branch locations, tel/email/
  // web/TRN) are hardcoded here because this format is only ever used
  // when the device's serial is a UniGas serial - i.e. the company is
  // always United Gas Co. LLC.
  //
  // Note: the reference format includes an Arabic "customer signature"
  // label. The bundled NotoSans.ttf has no Arabic glyphs, so it's
  // omitted here rather than rendering as blank boxes - add an
  // Arabic-capable font asset to restore it.
  Future<void> _generateUniGasDeliveryNotePDF(
    String trn,
    String address,
    String emirate,
    String country,
  ) async {
    // Resolve the van (vehicle) allocated to this device's serial number
    // from the locally-cached 'spectra_allocations' SharedPreferences
    // value (same cache PendingDeliveryNoteEntry.dart etc. read for
    // voucher_type) rather than making a fresh network call.
    String vehicleName = '';
    try {
      final String? spectraAllocationsString = prefs.getString(
        'spectra_allocations',
      );
      debugPrint(
        "UNIGAS DELIVERY NOTE VEHICLE LOOKUP (prefs): $spectraAllocationsString",
      );

      if (spectraAllocationsString != null &&
          spectraAllocationsString.isNotEmpty) {
        final List<dynamic> spectraAllocations = jsonDecode(
          spectraAllocationsString,
        );
        if (spectraAllocations.isNotEmpty) {
          final first = Map<String, dynamic>.from(spectraAllocations.first);
          // Cached shape is {"godown": "...", "company": "...", ...} -
          // no "godown_name"/"serial_no" keys like the live API response.
          vehicleName = first['godown']?.toString() ?? '';
        }
      }
    } catch (e) {
      debugPrint("UNIGAS DELIVERY NOTE VEHICLE LOOKUP ERROR: $e");
    }

    final logoBytes = await rootBundle.load("assets/uigas-logo.jpeg");
    final uniGasLogo = pw.MemoryImage(logoBytes.buffer.asUint8List());

    // Arabic-capable font for the "توقيع العميل" signature label -
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

    // Font sizes below are matched directly against the reference PDF
    // (extracted per-run via PyMuPDF), not eyeballed - keep in sync with
    // it if the format changes.
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
    // Wrapped so long values (long addresses/emails etc.) wrap onto a
    // second line instead of overflowing the narrow receipt width.
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
    // by/Vehicle, matching the reference layout. Both are bold-ish in
    // the reference (Roboto-Medium) - pw.FontWeight.bold is the closest
    // match available since only a Regular weight is bundled.
    pw.Widget spaceBetweenLine(String label, String value) {
      return pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(width: 6),
          pw.Flexible(
            child: pw.Text(
              value,
              textAlign: pw.TextAlign.right,
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
            ),
          ),
        ],
      );
    }

    // Item name plus, when this is a UniGas meter-reading item, a small
    // "X - Y" meter-reading values line underneath.
    pw.Widget itemCell(SaleItem item) {
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 3),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(item.itemName, style: pw.TextStyle(fontSize: 10)),
            if (item.meterFrom.isNotEmpty && item.meterTo.isNotEmpty)
              pw.Text(
                '${item.meterFrom} - ${item.meterTo}',
                style: pw.TextStyle(
                  fontSize: 7,
                  fontStyle: pw.FontStyle.italic,
                  color: PdfColors.grey500,
                ),
              ),
          ],
        ),
      );
    }

    pw.Widget cell(String text, {bool bold = false}) {
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 3),
        child: pw.Text(
          text,
          style: pw.TextStyle(
            fontSize: 10,
            fontWeight: bold ? pw.FontWeight.bold : null,
          ),
        ),
      );
    }

    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        // Shared/viewed only (not printed on the Sunmi's 58mm thermal
        // paper), so widened to 76mm to match the Tax Invoice format and
        // give the item table/signature box more breathing room.
        pageFormat: PdfPageFormat(
          76 * PdfPageFormat.mm,
          double.infinity,
          marginLeft: 10,
          marginRight: 10,
          marginTop: 8,
          marginBottom: 8,
        ),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Image(uniGasLogo, height: 60),
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
              leftText('DELIVERY NOTE', size: 10, weight: pw.FontWeight.bold),
              pw.SizedBox(height: 4),
              leftText('Document No: ${_vchnoController.text}'),
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
              pw.Table(
                border: pw.TableBorder(
                  left: const pw.BorderSide(width: 0.5),
                  right: const pw.BorderSide(width: 0.5),
                  top: const pw.BorderSide(width: 1.5),
                  bottom: const pw.BorderSide(width: 1.5),
                ),
                columnWidths: {
                  0: const pw.FixedColumnWidth(20),
                  1: const pw.FlexColumnWidth(1),
                  2: const pw.FixedColumnWidth(30),
                  3: const pw.FixedColumnWidth(32),
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(
                      border: pw.Border(bottom: pw.BorderSide(width: 0.75)),
                    ),
                    children: [
                      cell('SN', bold: true),
                      cell('ITEM', bold: true),
                      cell('UOM', bold: true),
                      cell('QTY', bold: true),
                    ],
                  ),
                  for (var item in saleItems.asMap().entries)
                    pw.TableRow(
                      children: [
                        cell('${item.key + 1}'),
                        itemCell(item.value),
                        cell(item.value.itemUnit),
                        cell(item.value.itemQuantity),
                      ],
                    ),
                ],
              ),
              pw.SizedBox(height: 10),
              spaceBetweenLine('Delivered by:', cleanOrNotAvailable(name)),
              pw.SizedBox(height: 2),
              spaceBetweenLine('Vehicle:', cleanOrNotAvailable(vehicleName)),
              pw.SizedBox(height: 10),
              pw.Text(
                'I confirm that quantity in this delivery is correct with good condition and quality',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(fontSize: 9),
              ),
              pw.SizedBox(height: 6),
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
                        bulkReceiverSignatureBytes != null
                            ? pw.Container(
                                width: 60,
                                height: 60,
                                decoration: pw.BoxDecoration(
                                  border: pw.Border.all(width: 1),
                                ),
                                child: pw.Image(
                                  pw.MemoryImage(bulkReceiverSignatureBytes!),
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
                                'Name: ${bulkReceiverNameController.text.trim().isEmpty ? '' : bulkReceiverNameController.text.trim()}',
                                style: pw.TextStyle(
                                  fontSize: 8,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                              pw.SizedBox(height: 20),
                              pw.Text(
                                'Phone: ${bulkReceiverMobileController.text.trim().isEmpty ? '' : bulkReceiverMobileController.text.trim()}',
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
    final filePath = '${dir.path}/DeliveryNote_$formattedDate.pdf';
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
        documentName: 'DeliveryNote_$formattedDate',
      );
    } catch (e) {
      debugPrint('UNIGAS DELIVERY NOTE PRINT ERROR: $e');
    } finally {
      _resetDeliveryNoteFormAfterShare();
    }
  }

  // UniGas bulk (tanker) gas delivery format - "DELIVERY NOTE - BULK GAS".
  // Wholly different layout from the cylinder format above: single metered
  // item (Product/Unit/Start-End Reading/Total Quantity) and vehicle
  // details from the app, plus a Receiver Signature/Mobile/EID#/Signature
  // block left entirely blank for the recipient to fill in by hand -
  // there's no in-app field for any of that, by design.
  Future<void> _generateUniGasBulkDeliveryNotePDF(
    String trn,
    String address,
    String emirate,
    String country,
  ) async {
    String vehicleName = '';
    try {
      final String? spectraAllocationsString = prefs.getString(
        'spectra_allocations',
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
      debugPrint("UNIGAS BULK DELIVERY NOTE VEHICLE LOOKUP ERROR: $e");
    }

    final logoBytes = await rootBundle.load("assets/uigas-logo.jpeg");
    final uniGasLogo = pw.MemoryImage(logoBytes.buffer.asUint8List());

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

    // Bulk deliveries are single-item only (enforced at selection time),
    // so the first sale item is the metered product.
    final SaleItem? bulkItem = saleItems.isNotEmpty ? saleItems.first : null;
    // BigInt, not double - readings can run to many digits and double
    // both loses precision past ~15-17 digits and clamps via .toInt() on
    // overflow (see _syncQtyWithMeterReading). NumberFormat can't take a
    // BigInt directly, so the comma-grouping is inserted manually.
    final BigInt meterFromBig = BigInt.tryParse(bulkItem?.meterFrom ?? '') ?? BigInt.zero;
    final BigInt meterToBig = BigInt.tryParse(bulkItem?.meterTo ?? '') ?? BigInt.zero;
    final BigInt totalQuantityBig = meterToBig - meterFromBig;
    String formatBigIntWithCommas(BigInt value) {
      final String digits = value.abs().toString();
      final StringBuffer buffer = StringBuffer();
      for (int i = 0; i < digits.length; i++) {
        if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
        buffer.write(digits[i]);
      }
      return (value.isNegative ? '-' : '') + buffer.toString();
    }

    final now = DateTime.now();
    final dateTimeText = DateFormat('dd-MMM-yyyy HH:mm:ss').format(now);

    pw.Widget leftText(String text, {double size = 9, pw.FontWeight? weight}) {
      return pw.Align(
        alignment: pw.Alignment.centerLeft,
        child: pw.Text(
          text,
          style: pw.TextStyle(fontSize: size, fontWeight: weight),
        ),
      );
    }

    pw.Widget detailLine(String label, String value, {double size = 8}) {
      return pw.Align(
        alignment: pw.Alignment.centerLeft,
        child: pw.RichText(
          text: pw.TextSpan(
            children: [
              pw.TextSpan(
                text: '$label: ',
                style: pw.TextStyle(
                  fontSize: size,
                  fontWeight: pw.FontWeight.bold,
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

    pw.Widget centeredDetailLine(String label, String value) {
      return pw.Align(
        alignment: pw.Alignment.center,
        child: pw.RichText(
          textAlign: pw.TextAlign.center,
          text: pw.TextSpan(
            children: [
              pw.TextSpan(
                text: '$label: ',
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.TextSpan(text: value, style: pw.TextStyle(fontSize: 9)),
            ],
          ),
        ),
      );
    }

    // A dotted line for pen-fill fields (Receiver Signature block, blank
    // Notes) - the pdf package has no built-in dashed-border widget, so
    // this is faked with a clipped run of periods.
    pw.Widget dots({int count = 80, pw.TextAlign align = pw.TextAlign.left}) {
      return pw.Text(
        '.' * count,
        maxLines: 1,
        overflow: pw.TextOverflow.clip,
        textAlign: align,
        style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
      );
    }

    // Label bold on the left, value (regular weight) on the right -
    // matches the reference's Start/End Reading, Vehicle No. etc. An
    // empty value renders a dotted line instead, for the Receiver
    // Signature block's pen-fill fields.
    pw.Widget kv(String label, String value) {
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 3),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          // Bottom-align label with the value/dotted line so blank rows'
          // extra handwriting space appears above both, not just above
          // the dots while the label stays pinned to the top.
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              label,
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(width: 6),
            value.isEmpty
                // Blank fields push the dotted line to the bottom of a
                // taller box, leaving natural handwriting space between
                // the label and the line instead of the line sitting
                // right on the label's baseline.
                ? pw.Expanded(
                    child: pw.SizedBox(
                      height: 22,
                      child: pw.Column(
                        mainAxisAlignment: pw.MainAxisAlignment.end,
                        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                        children: [dots(align: pw.TextAlign.right)],
                      ),
                    ),
                  )
                : pw.Flexible(
                    child: pw.Text(
                      value,
                      textAlign: pw.TextAlign.right,
                      style: pw.TextStyle(fontSize: 9),
                    ),
                  ),
          ],
        ),
      );
    }

    pw.Widget bulkBox(List<pw.Widget> children) {
      return pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(border: pw.Border.all(width: 1)),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: children,
        ),
      );
    }

    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(
          76 * PdfPageFormat.mm,
          double.infinity,
          marginLeft: 10,
          marginRight: 10,
          marginTop: 8,
          marginBottom: 8,
        ),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Image(uniGasLogo, height: 60),
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
              leftText('A Partner You Can Trust.'),
              leftText('Sharjah | Dubai | RAK | UAQ | Fujairah', size: 8),
              pw.SizedBox(height: 6),
              detailLine('Tel', '800 864427'),
              detailLine('Email', 'info@unigastt.com'),
              detailLine('Web', 'www.unigastt.com'),
              detailLine('TRN#', '100206964700003'),
              pw.SizedBox(height: 6),
              pw.Divider(thickness: 1),
              leftText(
                'DELIVERY NOTE - BULK GAS',
                size: 10,
                weight: pw.FontWeight.bold,
              ),
              pw.SizedBox(height: 4),
              kv('DO Number:', cleanOrNotAvailable(_vchnoController.text)),
              kv('Date & Time:', dateTimeText),
              pw.SizedBox(height: 10),
              bulkBox([
                centeredDetailLine(
                  'Customer',
                  cleanOrNotAvailable(_selectedpartyledger),
                ),
                pw.SizedBox(height: 6),
                centeredDetailLine('Address', customerAddress),
                pw.SizedBox(height: 6),
                centeredDetailLine('TRN#', customerTrn),
              ]),
              pw.SizedBox(height: 10),
              bulkBox([
                kv('Start Reading:', bulkItem?.meterFrom ?? 'Not Available'),
                kv('End Reading:', bulkItem?.meterTo ?? 'Not Available'),
                kv('Total Quantity:', formatBigIntWithCommas(totalQuantityBig)),
                kv('Unit:', cleanOrNotAvailable(bulkItem?.itemUnit)),
                kv('Product:', cleanOrNotAvailable(bulkItem?.itemName)),
              ]),
              pw.SizedBox(height: 10),
              bulkBox([
                kv('Vehicle No.:', cleanOrNotAvailable(vehicleName)),
                kv('Driver / Operator:', cleanOrNotAvailable(name)),
              ]),
              pw.SizedBox(height: 10),
              pw.Text(
                'I confirm that quantity in this delivery order is correct '
                'with good condition and quality.',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(fontSize: 9),
              ),
              pw.SizedBox(height: 10),
              bulkBox([
                pw.Text(
                  'Notes (if any):',
                  style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                if (controller_narration.text.trim().isNotEmpty) ...[
                  pw.SizedBox(height: 4),
                  pw.Text(
                    controller_narration.text.trim(),
                    style: pw.TextStyle(fontSize: 9),
                  ),
                ] else ...[
                  // Blank space to write in before the dotted line, same
                  // idea as kv()'s blank fields - room for a natural
                  // handwritten note, not just a line right under the label.
                  pw.SizedBox(height: 22),
                  pw.SizedBox(width: double.infinity, child: dots()),
                ],
              ]),
              pw.SizedBox(height: 10),
              // Receiver's own details - shows the typed value if the
              // Receiver Information section was filled in, otherwise a
              // blank dotted line for the recipient to fill in by pen.
              bulkBox([
                kv(
                  'Receiver Name:',
                  bulkReceiverNameController.text.trim(),
                ),
                kv('Mobile:', bulkReceiverMobileController.text.trim()),
                kv(
                  'EID#:',
                  // The "784" prefix is auto-filled as soon as bulk is
                  // chosen - if the user never typed anything past it,
                  // treat it the same as not having filled EID# in at all.
                  bulkReceiverEidController.text
                              .replaceAll(RegExp(r'[^0-9]'), '')
                              .length >
                          3
                      ? bulkReceiverEidController.text.trim()
                      : '',
                ),
                pw.SizedBox(height: 6),
                // Embeds the receiver's on-screen captured signature image
                // when available, otherwise falls back to the blank
                // dotted pen-fill line.
                if (bulkReceiverSignatureBytes != null)
                  pw.Row(
                    // Bottom-aligned so the label sits level with the
                    // bottom of the (much taller) signature image instead
                    // of floating in the vertical middle of it.
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        'Signature:',
                        style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(width: 8),
                      // Placed right next to the label (not centered across
                      // the remaining row width) and enlarged so the
                      // signature reads clearly on the printed page. Both
                      // dimensions are fixed so BoxFit.contain has a real
                      // box to scale into without overflowing.
                      pw.SizedBox(
                        width: 220,
                        height: 90,
                        child: pw.Image(
                          pw.MemoryImage(bulkReceiverSignatureBytes!),
                          fit: pw.BoxFit.contain,
                          alignment: pw.Alignment.centerLeft,
                        ),
                      ),
                    ],
                  )
                else
                  kv('Signature:', ''),
              ]),
              pw.SizedBox(height: 12),
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
    final filePath = '${dir.path}/BulkDeliveryNote_$formattedDate.pdf';
    final file = File(filePath);
    await file.writeAsBytes(pdfData);

    try {
      await printUniGasPdf(
        context,
        pdfData,
        documentName: 'BulkDeliveryNote_$formattedDate',
      );
    } catch (e) {
      debugPrint('UNIGAS BULK DELIVERY NOTE PRINT ERROR: $e');
    } finally {
      _resetDeliveryNoteFormAfterShare();
    }
  }

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
    );
  }

  Future<void> saveEntry() async {
    // ❌ Prevent save if Party Ledger not selected
    if (_selectedpartyledger == null ||
        _selectedpartyledger.toString().trim().isEmpty) {
      showAppMessage(context, "Please select Party Ledger");

      return;
    }

    // UniGas delivery (bulk or cylinder): Receiver Name is mandatory.
    if (isUniGasMeterReadingSerial &&
        bulkReceiverNameController.text.trim().isEmpty) {
      showAppMessage(
        context,
        "Please enter the Receiver's Name before saving",
      );
      return;
    }

    // UniGas bulk gas delivery: start/end meter reading is mandatory -
    // already enforced when adding the item in the picker, checked again
    // here in case it was somehow left blank.
    if (isUniGasMeterReadingSerial &&
        _isBulkDelivery == true &&
        saleItems.isNotEmpty &&
        (saleItems.first.meterFrom.trim().isEmpty ||
            saleItems.first.meterTo.trim().isEmpty)) {
      showAppMessage(
        context,
        "Please enter both the Start Reading and End Reading",
      );
      return;
    }

    // UniGas bulk gas delivery: Receiver EID# is optional, but if entered
    // must be a valid UAE Emirates ID - 15 digits starting with 784
    // (784-YYYY-NNNNNNN-C), dashes/spaces allowed and ignored. The "784"
    // prefix is auto-filled as soon as bulk is chosen, so only treat it
    // as "entered" once the user has typed something past that prefix.
    if (isUniGasMeterReadingSerial && _isBulkDelivery == true) {
      final String eidDigitsOnly = bulkReceiverEidController.text.replaceAll(
        RegExp(r'[\s-]'),
        '',
      );
      if (eidDigitsOnly.length > 3 &&
          !RegExp(r'^784\d{12}$').hasMatch(eidDigitsOnly)) {
        showAppMessage(
          context,
          "Please enter a valid Emirates ID - it should start with 784 "
          "and have 15 digits in total",
        );
        return;
      }
    }

    if (saleItems.isEmpty) {
      showAppMessage(context, 'Atleast add 1 item');
      return;
    }

    String narrationValue = controller_narration.text.trim();
    String vchnoValue = _vchnoController.text;
    String refnoValue = controller_refno.text;

    // Verbatim port of the original's reference-date fallback: prefer
    // `refdatestring` (migrated state); if that's blank but the widget-local
    // `_refdateController` has text, parse it back out of its display
    // format. Resolved here (not in the notifier) since it needs the
    // widget-local controller.
    String selectedReferenceDate = refdatestring;
    if (selectedReferenceDate.trim().isEmpty &&
        _refdateController.text.trim().isNotEmpty) {
      final parsedDate = DateFormat(
        'dd-MM-yyyy',
      ).parse(_refdateController.text.trim());
      selectedReferenceDate = _dateFormat.format(parsedDate);
    }

    final result = await _notifier.saveEntry(
      narration: narrationValue,
      vchno: vchnoValue,
      refno: refnoValue,
      referenceDate: selectedReferenceDate,
    );

    if (result.success) {
      loadLedgerData();
    } else if (result.errorMessage != null) {
      showAppMessage(context, result.errorMessage!);
    }
    // else: a generic (non-ApiException) failure - matches the original's
    // silent `catch (e) { ...; print(e); }` branch (no message, no ledger
    // reload).
  }

  void showDeliveryNoteDialog(
    BuildContext context,
    String trn,
    String address,
    String emirate,
    String country,
  ) {
    // UniGas prints directly - no "created successfully / Share" dialog.
    if (isUniGasMeterReadingSerial) {
      generateDeliveryNotePDF(trn, address, emirate, country);
      return;
    }

    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: "DeliveryNote",
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
                    'Do you want to share the delivery note?',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(fontSize: 18.0),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Delivery Note Created Successfully',
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
                          // Drop focus first - otherwise clearing
                          // _partyLedgerController's text below while the
                          // Party Ledger TypeAheadField still has focus
                          // makes it re-run its suggestionsCallback('')
                          // (which matches everything) and pop its
                          // suggestions overlay back open right after
                          // reset. A bare unfocus() leaves the scope's
                          // "last focused descendant" pointer intact, so
                          // popping this dialog can still silently hand
                          // focus straight back to that field - requesting
                          // a disposable FocusNode instead fully severs
                          // that link.
                          FocusScope.of(context).requestFocus(FocusNode());
                          Navigator.pop(context);

                          controller_narration.clear();
                          controller_refno.clear();
                          _textFieldFocusNodeNarration.unfocus();
                          voucherStartReadingController.clear();
                          voucherEndReadingController.clear();
                          bulkReceiverNameController.clear();
                          bulkReceiverMobileController.clear();
                          bulkReceiverEidController.clear();
                          bulkReceiverSignatureBytes = null;

                          // Migrated-state half - see `resetAfterShare`'s
                          // doc-comment.
                          _notifier.resetAfterShare();
                          _syncTotalsControllers();

                          _dateController.text = saledatetxt;
                          _refdateController.text = refdatetxt;

                          fetchvchnos(_selectedvchtypename);
                          _partyLedgerController.clear();

                          setState(() {
                            _selectedledger = ledgerdata.isNotEmpty
                                ? ledgerdata[0]['name']
                                : null;

                            _selecteditem = '${itemdata[0]['name']}';
                            _itemController.text = _selecteditem;

                            if (locationsdata.isNotEmpty) {
                              selectedLocation = locationsdata[0];
                              isVisibleLocation = true;
                            } else {
                              isVisibleLocation = false;
                            }

                            _updateUnitDropdown(_selecteditem);

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
                          await generateDeliveryNotePDF(
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

                  /* Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          setState(() {
                            controller_narration.clear();
                            controller_refno.clear();
                            _textFieldFocusNodeNarration.unfocus();
                            voucherStartReadingController.clear();
                            voucherEndReadingController.clear();
                            _isBulkDelivery = null;
                            bulkReceiverNameController.clear();
                            bulkReceiverMobileController.clear();
                            bulkReceiverEidController.clear();
                            bulkReceiverSignatureBytes = null;

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
                          await generateDeliveryNotePDF(trn, address, emirate, country);
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

  bool get isUniGasMeterReadingSerial {
    final currentSerial = serial_no?.trim() ?? '';

    // 👇 put only that one serial here

    return currentSerial == uniGasSerialNumber;
  }

  /// tally-api migration: replaces legacy's `GET
  /// /api/entry/getSalesData/:company/:serial` (a single server-shaped
  /// response with `vchTypes`/`partyLedgers`/`salesLedgers`/`otherLedgers`/
  /// `vatLedgers`/`items`/`locations` already grouped) with a combination of
  /// `StockRepository.listStockItems()`, `LedgerRepository.listLedgers()`
  /// (+ its `listPartyGroups()`) and direct `TallyApiClient` calls for the
  /// master types no repository wraps yet (`/groups`, `/units`, `/godowns`,
  /// `/voucher-types`, `/currencies` - see this method's final report note
  /// suggesting dedicated repositories be added). Ledger classification
  /// (party/sales/VAT/other) is resolved client-side from each ledger's
  /// `groupMasterId` joined against `/groups`' `reservedName`, the same
  /// Tally-reserved-name convention tally-api's own reports use (see
  /// tally-api's CLAUDE.md "Reports" section) - `'SALES'` for sales
  /// ledgers, `'DUTIES'` for VAT/tax ledgers, the two reserved party
  /// group names (also `LedgerRepository`'s own party-group heuristic) for
  /// party ledgers, everything else falls into "other ledgers". These are
  /// tally-api's `GroupReservedName` enum labels (screaming-snake-case, its
  /// 2026-08-21 schema-hardening migration), not Tally's own mixed-case
  /// reservedName strings - see `ledger_repository.dart`'s doc comment.
  ///
  /// Every downstream widget in this file still reads the same
  /// `vchtypenamedata`/`itemdata`/`partyledgerdata`/`salesledger_data`/
  /// `ledgerdata`/`vatledgerdata`/`locationsdata` shapes as before - this
  /// method's job is only to repopulate them from the new backend, not to
  /// change how they're consumed.
  Future<void> loadData() async {
    final error = await _notifier.loadData();
    if (error != null) {
      showAppMessage(context, error);
    }
    if (_selecteditem != null) {
      _updateUnitDropdown(_selecteditem);
    }
  }

  /// tally-api migration: legacy's `GET /api/ledger/getLedger/:company/:serial`
  /// (POSTed with `{"ledger": name}`) returned exactly the TRN/address/
  /// state/country/mobile/email fields tally-api's own `/ledgers` list row
  /// already carries. The notifier's `loadLedgerData` does the lookup and
  /// returns the result (or `null` for "ledger not found"); this wrapper
  /// makes the actual `showAppMessage`/`showDeliveryNoteDialog` calls, since
  /// those need `context`.
  Future<void> loadLedgerData() async {
    final result = await _notifier.loadLedgerData();
    if (result == null) {
      showAppMessage(context, 'Ledger not found');
      return;
    }
    showDeliveryNoteDialog(
      context,
      result.tin,
      result.address,
      result.emirate,
      result.country,
    );
  }

  /// Backed by tally-api's `GET .../voucher-entries/voucher-numbers` (see
  /// `VoucherEntryRepository.voucherNumbers`'s doc-comment) - the notifier
  /// does the fetch/sort/next-number-generation; this wrapper sets the
  /// widget-local `_vchnoController.text` from the result and surfaces any
  /// error via `showAppMessage`.
  Future<void> fetchvchnos(String vchname) async {
    final result = await _notifier.fetchVchNos(vchname);
    _vchnoController.text = result.nextVchNo;
    if (result.error != null) {
      showAppMessage(context, result.error!);
    }
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

  // When both start/end meter readings are entered and valid, quantity is
  // derived from them (end - start) and the field is locked to prevent it
  // drifting out of sync with the readings. If both readings are cleared,
  // quantity goes back to being user-editable and resets to '1'.
  bool _isQtyLockedByMeterReading(String startText, String endText) {
    final start = BigInt.tryParse(startText.trim());
    final end = BigInt.tryParse(endText.trim());
    return start != null && end != null && end > start;
  }

  void _syncQtyWithMeterReading({
    required TextEditingController startController,
    required TextEditingController endController,
    required TextEditingController qtyController,
  }) {
    final startText = startController.text.trim();
    final endText = endController.text.trim();

    // Meter readings are whole numbers that can run to many digits - a
    // real van meter has no fixed max length. BigInt parses/subtracts
    // them exactly; double loses precision past ~15-17 digits and its
    // .toInt() silently clamps to 9223372036854775807 (int64 max) when
    // the value is too large to represent, instead of erroring - which is
    // exactly what was showing up as a "stuck" quantity for long readings.
    final start = BigInt.tryParse(startText);
    final end = BigInt.tryParse(endText);

    if (start != null && end != null && end > start) {
      qtyController.text = (end - start).toString();
    } else if (startText.isEmpty && endText.isEmpty) {
      qtyController.text = '1';
    }
  }

  Future<void> _selectsaleDate(BuildContext context) async {
    if (isUniGasSerial(serial_no)) {
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
    if (picked != null && picked != saledate) {
      _notifier.setSaleDate(picked);
      _dateController.text = saledatetxt;
    }
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

    if (picked != null) {
      _notifier.setRefDate(picked);
      _refdateController.text = refdatetxt;

      debugPrint("Updated Reference Date Display: ${_refdateController.text}");
      debugPrint("Updated Reference Date Body: $refdatestring");
    }
  }


  // ─────────────────────────────────────────────────────────────────
  // EXPERIMENTAL: bulk multi-item add.
  // Fully separate from the existing single-item flow below
  // (_showItemDetailsPopup / addItem) — nothing here is called by the
  // main add-item button. Reachable only via the new checklist icon
  // next to "Items". Safe to test in isolation; the existing flow is
  // untouched.
  // ─────────────────────────────────────────────────────────────────

  // Item's own default rate: standardPrice, falling back to salePrice,
  // falling back to null (caller leaves rate empty for manual entry).
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

    final int? masterId = int.tryParse(itemMasterId);
    if (masterId == null) return null;

    final String selectedDate = saledatestring.isNotEmpty
        ? saledatestring
        : DateFormat('yyyyMMdd').format(DateTime.now());

    return _lookupPriceLevelRate(
      stockItemMasterId: masterId,
      priceLevelName: selectedPartyLedgerPriceLevel!,
      asOfYyyyMMdd: selectedDate,
    );
  }

  // Small colored badge used to permanently show where a rate came from
  // (Price Level / Item Rate / Manual) — a normal user-facing indicator.
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
          // Bulk (meter-reading) quantities come from a real van meter and
          // can run to a lot of digits - there's no safe upper bound to
          // cap them at. Rather than clip or force-shrink the text, this
          // caps the BOX at a reasonable width and lets the number scroll
          // horizontally within it, so every digit stays reachable no
          // matter how long the reading is.
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

  // Reads whether this device's vehicle allocation is tagged "is_bulk" -
  // set in Add/Modify Allocation on the backend and returned per-allocation
  // in the "spectra_allocations" login response (cached in prefs, same
  // record used for the vehicle/godown lookups elsewhere in this file).
  Future<bool> _resolveIsBulkFromSpectraAllocation() async {
    try {
      final String? spectraAllocationsString = prefs.getString(
        'spectra_allocations',
      );
      if (spectraAllocationsString != null &&
          spectraAllocationsString.isNotEmpty) {
        final List<dynamic> spectraAllocations = jsonDecode(
          spectraAllocationsString,
        );
        if (spectraAllocations.isNotEmpty) {
          final first = Map<String, dynamic>.from(spectraAllocations.first);
          return parseBoolFlag(first['is_bulk']);
        }
      }
    } catch (e) {
      debugPrint("UNIGAS IS_BULK ALLOCATION LOOKUP ERROR: $e");
    }
    return false;
  }

  // UniGas-only: resolves once per entry whether this is a bulk (tanker)
  // gas delivery from the allocation's "is_bulk" tag before opening the
  // item picker, then remembers the answer for the rest of the entry
  // (cleared on reset after share/print). No user confirmation popup.
  Future<void> _onAddItemTapped(BuildContext context) async {
    if (isUniGasMeterReadingSerial && _isBulkDelivery == null) {
      final bool isBulk = await _resolveIsBulkFromSpectraAllocation();
      _notifier.setBulkDelivery(isBulk);
      // Pre-fill the fixed UAE Emirates ID prefix so the user only ever
      // types the remaining digits.
      if (isBulk && bulkReceiverEidController.text.isEmpty) {
        setState(() {
          bulkReceiverEidController.text = '784-';
          bulkReceiverEidController.selection = TextSelection.collapsed(
            offset: bulkReceiverEidController.text.length,
          );
        });
      }
    }
    // Bulk deliveries allow exactly one item for the whole entry - once
    // it's added, block reopening the picker entirely rather than just
    // restricting selection inside it.
    if (isUniGasMeterReadingSerial &&
        _isBulkDelivery == true &&
        saleItems.isNotEmpty) {
      showAppMessage(
        context,
        "Only one item can be added for a Bulk delivery. Remove the "
        "current item first if you need a different one",
      );
      return;
    }
    _showMultiItemSelectPopup(context);
  }

  // Receiver EID# so it always reads as a UAE Emirates ID:
  // 784-YYYY-NNNNNNN-C (3-4-7-1 digit grouping, 15 digits total). The
  // "784" prefix is fixed - typing over/deleting it just puts it back.
  void _formatBulkReceiverEid(String raw) {
    String digits = raw.replaceAll(RegExp(r'[^0-9]'), '');

    if (!digits.startsWith('784')) {
      digits = digits.length >= 3 ? '784${digits.substring(3)}' : '784';
    }
    if (digits.length > 15) {
      digits = digits.substring(0, 15);
    }

    final StringBuffer formatted = StringBuffer(digits.substring(0, 3));
    if (digits.length > 3) {
      formatted.write('-${digits.substring(3, digits.length.clamp(3, 7))}');
    }
    if (digits.length > 7) {
      formatted.write('-${digits.substring(7, digits.length.clamp(7, 14))}');
    }
    if (digits.length > 14) {
      formatted.write('-${digits.substring(14, 15)}');
    }

    final String result = formatted.toString();
    if (result == bulkReceiverEidController.text) return;
    bulkReceiverEidController.value = TextEditingValue(
      text: result,
      selection: TextSelection.collapsed(offset: result.length),
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
    // Meter start/end reading per item — only used/shown for UniGas
    // serials, same fields and validation as the single-item flow.
    final Map<String, TextEditingController> startReadingControllers = {};
    final Map<String, TextEditingController> endReadingControllers = {};
    final Map<String, String?> meterReadingErrors = {};
    // Selected unit per item — matches the single-item flow's unit
    // dropdown. Switching units resets qty to "1" (same behavior; rate
    // is intentionally NOT recomputed on unit change, mirroring the
    // single-item flow exactly).
    final Map<String, String> selectedUnitPerItem = {};
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

    // Mirrors addItem()'s meter reading validation exactly: both fields
    // must be filled together, and end must be greater than start.
    void validateMeterReading(String name, StateSetter setStateDialog) {
      final String meterFrom = startReadingControllers[name]?.text.trim() ?? '';
      final String meterTo = endReadingControllers[name]?.text.trim() ?? '';

      String? error;
      if ((meterFrom.isNotEmpty && meterTo.isEmpty) ||
          (meterFrom.isEmpty && meterTo.isNotEmpty)) {
        error = "Please enter both start and end readings";
      } else if (meterFrom.isNotEmpty && meterTo.isNotEmpty) {
        // BigInt, not double - see _syncQtyWithMeterReading for why.
        final start = BigInt.tryParse(meterFrom);
        final end = BigInt.tryParse(meterTo);
        if (start == null || end == null || end <= start) {
          error = "End reading must be greater than start reading";
        }
      }

      setStateDialog(() {
        meterReadingErrors[name] = error;
        final qtyController = qtyEditControllers[name];
        if (qtyController != null) {
          _syncQtyWithMeterReading(
            startController: startReadingControllers[name]!,
            endController: endReadingControllers[name]!,
            qtyController: qtyController,
          );
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
                              (isUniGasMeterReadingSerial &&
                                      _isBulkDelivery == true)
                                  ? "Select Bulk Item"
                                  : "Add Multiple Items",
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
                                  final bool isBulk =
                                      isUniGasMeterReadingSerial &&
                                      _isBulkDelivery == true;
                                  setStateDialog(() {
                                    if (next) {
                                      // Bulk deliveries are single-item
                                      // only - selecting a new item
                                      // replaces whatever was picked
                                      // before instead of adding to it.
                                      if (isBulk) {
                                        selectedItemNames.clear();
                                      }
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
                                      if (isBulk) {
                                        startReadingControllers.putIfAbsent(
                                          name,
                                          () => TextEditingController(),
                                        );
                                        endReadingControllers.putIfAbsent(
                                          name,
                                          () => TextEditingController(),
                                        );
                                      }
                                      if (isUniGasSerial(serial_no)) {
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
                                                    if (itemUnits.length >
                                                        1) ...[
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
                                                    if (isUniGasSerial(
                                                      serial_no,
                                                    )) ...[
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
                                                          enabled:
                                                              !(isUniGasMeterReadingSerial &&
                                                                  _isQtyLockedByMeterReading(
                                                                    startReadingControllers[name]
                                                                            ?.text ??
                                                                        '',
                                                                    endReadingControllers[name]
                                                                            ?.text ??
                                                                        '',
                                                                  )),
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
                                                    if (isUniGasMeterReadingSerial &&
                                                        _isBulkDelivery ==
                                                            true) ...[
                                                      const SizedBox(
                                                        height: 10,
                                                      ),
                                                      Row(
                                                        children: [
                                                          Expanded(
                                                            child: TextField(
                                                              controller:
                                                                  startReadingControllers[name],
                                                              keyboardType:
                                                                  TextInputType
                                                                      .number,
                                                              // Digits only -
                                                              // no length cap,
                                                              // since real van
                                                              // meters can
                                                              // legitimately
                                                              // have long
                                                              // readings.
                                                              inputFormatters: [
                                                                FilteringTextInputFormatter
                                                                    .digitsOnly,
                                                              ],
                                                              style:
                                                                  GoogleFonts.poppins(
                                                                    fontSize:
                                                                        13,
                                                                  ),
                                                              onChanged: (_) =>
                                                                  validateMeterReading(
                                                                    name,
                                                                    setStateDialog,
                                                                  ),
                                                              decoration: _inputDecoration(
                                                                label:
                                                                    "Start Reading",
                                                                icon:
                                                                    Icons.speed,
                                                                gradientColors:
                                                                    const [
                                                                      Colors
                                                                          .orange,
                                                                      Colors
                                                                          .deepOrangeAccent,
                                                                    ],
                                                              ).copyWith(counterText: ''),
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                            width: 10,
                                                          ),
                                                          Expanded(
                                                            child: TextField(
                                                              controller:
                                                                  endReadingControllers[name],
                                                              keyboardType:
                                                                  TextInputType
                                                                      .number,
                                                              inputFormatters: [
                                                                FilteringTextInputFormatter
                                                                    .digitsOnly,
                                                              ],
                                                              style:
                                                                  GoogleFonts.poppins(
                                                                    fontSize:
                                                                        13,
                                                                  ),
                                                              onChanged: (_) =>
                                                                  validateMeterReading(
                                                                    name,
                                                                    setStateDialog,
                                                                  ),
                                                              decoration: _inputDecoration(
                                                                label:
                                                                    "End Reading",
                                                                icon: Icons
                                                                    .speed_outlined,
                                                                gradientColors:
                                                                    const [
                                                                      Colors
                                                                          .red,
                                                                      Colors
                                                                          .deepOrange,
                                                                    ],
                                                              ).copyWith(counterText: ''),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                      if (meterReadingErrors[name] !=
                                                          null)
                                                        Padding(
                                                          padding:
                                                              const EdgeInsets.only(
                                                                top: 6,
                                                                left: 4,
                                                              ),
                                                          child: Row(
                                                            children: [
                                                              const Icon(
                                                                Icons
                                                                    .error_outline,
                                                                size: 14,
                                                                color: Colors
                                                                    .redAccent,
                                                              ),
                                                              const SizedBox(
                                                                width: 4,
                                                              ),
                                                              Expanded(
                                                                child: Text(
                                                                  meterReadingErrors[name]!,
                                                                  style: GoogleFonts.poppins(
                                                                    color: Colors
                                                                        .redAccent,
                                                                    fontSize:
                                                                        11,
                                                                  ),
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                    ],
                                                    const SizedBox(height: 12),
                                                    Row(
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .spaceBetween,
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .end,
                                                      children: [
                                                        if (isUniGasMeterReadingSerial)
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
                                                            return Container(
                                                              padding:
                                                                  const EdgeInsets.symmetric(
                                                                    horizontal:
                                                                        12,
                                                                    vertical: 7,
                                                                  ),
                                                              decoration: BoxDecoration(
                                                                color: app_color
                                                                    .withValues(
                                                                      alpha:
                                                                          0.1,
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
                                                                          FontWeight
                                                                              .w600,
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
                                                                          FontWeight
                                                                              .w700,
                                                                      color:
                                                                          app_color,
                                                                    ),
                                                                  ),
                                                                ],
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
                              selectedItemNames.isEmpty ||
                                  isAdding ||
                                  meterReadingErrors.values.any(
                                    (e) => e != null,
                                  )
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
                                        "Please enter a Quantity greater "
                                        "than 0 for $name",
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
                                        "Please enter a Rate for $name",
                                      );
                                      return;
                                    }

                                    // Bulk gas delivery is metered - start
                                    // and end reading are mandatory, not
                                    // just format-validated when present.
                                    if (isUniGasMeterReadingSerial &&
                                        _isBulkDelivery == true) {
                                      final String meterFrom =
                                          startReadingControllers[name]?.text
                                              .trim() ??
                                          '';
                                      final String meterTo =
                                          endReadingControllers[name]?.text
                                              .trim() ??
                                          '';
                                      if (meterFrom.isEmpty ||
                                          meterTo.isEmpty) {
                                        showAppMessage(
                                          context,
                                          "Please enter both the Start "
                                          "Reading and End Reading for $name",
                                        );
                                        return;
                                      }
                                    }
                                  }

                                  setStateDialog(() => isAdding = true);
                                  await _addSelectedItemsInBulk(
                                    selectedItemNames,
                                    rateEditControllers,
                                    qtyEditControllers,
                                    startReadingControllers,
                                    endReadingControllers,
                                    selectedUnitPerItem,
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
    Map<String, TextEditingController> startReadingControllers,
    Map<String, TextEditingController> endReadingControllers,
    Map<String, String> selectedUnitPerItem,
    Map<String, List<TextEditingController>> descriptionControllers,
  ) async {
    final List<DnBulkEntry> entries = [];
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
      final bool isBulk = isUniGasMeterReadingSerial && _isBulkDelivery == true;
      final String meterFrom = isBulk
          ? (startReadingControllers[name]?.text.trim() ?? '')
          : '';
      final String meterTo = isBulk
          ? (endReadingControllers[name]?.text.trim() ?? '')
          : '';

      entries.add(
        DnBulkEntry(
          name: name,
          unitName: unitName,
          quantity: parsedQty,
          rate: resolvedRate,
          location: selectedLocation,
          meterFrom: meterFrom,
          meterTo: meterTo,
          descriptions: itemDescriptions,
          itemMasterId: int.tryParse(itemInfo['masterid']?.toString() ?? ''),
        ),
      );
    }

    _notifier.addBulkItems(entries);
    _syncTotalsControllers();
  }

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
                                                  _selectedledger?.isNotEmpty ==
                                                      true
                                                  ? _selectedledger
                                                  : "Select Ledger",
                                              labelText: "Ledger Name",
                                              hintStyle: GoogleFonts.poppins(
                                                fontSize: 13,
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.onSurfaceVariant,
                                              ),
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
                                                      Colors.blue,
                                                      Colors.lightBlueAccent,
                                                    ],
                                                    begin: Alignment.topLeft,
                                                    end: Alignment.bottomRight,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.all(
                                                        Radius.circular(12),
                                                      ),
                                                ),
                                                child: const Icon(
                                                  Icons.account_balance_wallet,
                                                  color: Colors.white,
                                                  size: 20,
                                                ),
                                              ),
                                              suffixIcon: Row(
                                                mainAxisSize: MainAxisSize.min,
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
                                                          _selectedledger = "";
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
                                              enabledBorder: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(16),
                                                borderSide: BorderSide(
                                                  color: Theme.of(
                                                    context,
                                                  ).dividerColor,
                                                  width: 1,
                                                ),
                                              ),
                                              focusedBorder: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(16),
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
                                    itemBuilder: (context, String suggestion) {
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

                                const SizedBox(height: 10),

                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 4,
                                    horizontal: 4,
                                  ),
                                  child: TextFormField(
                                    controller: ledgerAmountController,
                                    style: GoogleFonts.poppins(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface,
                                    ),
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
                                      errorStyle: GoogleFonts.poppins(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
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
                                      errorBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(16),
                                        borderSide: const BorderSide(
                                          color: Colors.redAccent,
                                          width: 1.5,
                                        ),
                                      ),
                                      focusedErrorBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(16),
                                        borderSide: const BorderSide(
                                          color: Colors.redAccent,
                                          width: 1.5,
                                        ),
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 14,
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

  /// Thin wrapper: the guard/`Navigator.pop`/dialog-local resets stay here
  /// (need `context`/`_selectedledger`/`ledgerAmountController`, all
  /// widget-local); the actual `ledgerEntries` mutation + totals recompute
  /// is `_notifier.addOrMergeLedger` - see that method's doc-comment for the
  /// pre-existing `vatapplicable` crash this preserves verbatim.
  void addLedger() {
    Map<String, dynamic>? specificLedger = ledgerdata.firstWhere(
      (ledger) => ledger['name'] == _selectedledger,
    );

    final ledgerName = specificLedger['name'];
    final ledgerAmount = ledgerAmountController.text;

    if (ledgerName.isNotEmpty && ledgerAmount.isNotEmpty) {
      Navigator.of(context).pop();
      double parsedAmount = double.parse(ledgerAmount.replaceAll(',', ''));
      _notifier.addOrMergeLedger(ledgerName, parsedAmount);
      _syncTotalsControllers();
      _selectedledger = ledgerdata.isNotEmpty ? ledgerdata[0]['name'] : null;
      ledgerAmountController.clear();
    }
  }

  Future<void> _initWidgetPrefs() async {
    prefs = await SharedPreferences.getInstance();
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
    _initWidgetPrefs();
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
    ref.watch(deliveryNoteRegistrationNotifierProvider);
    if (!_isInitialDataLoaded) {
      return Scaffold(
        bottomNavigationBar: const AppBottomNav(
          activeTab: AppBottomNavTab.entries,
          activeEntryType: AppEntryType.deliveryNote,
        ),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        key: _scaffoldKey,
        appBar: entryAppBar(
          context: context,
          title: "New Delivery Note",
          onBack: () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => PendingDeliveryNoteEntry(),
              ),
            );
          },
        ),
        body: _buildSkeletonForm(),
      );
    }

    final NumberFormat currencyFormat = NumberFormat(
      "#,##0.${'0' * decimal!}", // 👈 dynamically repeat '0' for decimal places
    );
    final bool canEditVoucherNo =
        SecuritybtnAcessHolder.toString().toLowerCase() == 'true';

    return Scaffold(
      bottomNavigationBar: const AppBottomNav(
        activeTab: AppBottomNavTab.entries,
        activeEntryType: AppEntryType.deliveryNote,
      ),
      key: _scaffoldKey,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: entryAppBar(
        context: context,
        title: "New Delivery Note",
        onBack: () {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => PendingDeliveryNoteEntry()),
          );
        },
      ),
      body: WillPopScope(
        onWillPop: () async {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => PendingDeliveryNoteEntry()),
          );
          return false;
        },

        child: Stack(
          children: [
            ListView(
              children: [
                /* GestureDetector(
                      onTap: () => _selectDateRangeVchNo(context),
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor.withOpacity(0.9),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 12,
                              offset: const Offset(0, 6),
                            ),
                          ],
                          border: Border.all(
                            color: app_color.withOpacity(0.3),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // calendar icon with gradient style
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [app_color, app_color.withOpacity(0.7)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.calendar_today, color: Colors.white, size: 20),
                            ),
                            const SizedBox(width: 14),

                            // text column
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "Voucher No. Range",
                                    style: GoogleFonts.poppins(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    "${DateFormat('dd-MMM-yyyy').format(yearStartDate)} → ${DateFormat('dd-MMM-yyyy').format(yearEndDate)}",
                                    style: GoogleFonts.poppins(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: app_color,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            Icon(Icons.keyboard_arrow_down, color: Theme.of(context).colorScheme.onSurfaceVariant),
                          ],
                        ),
                      ),
                    ),*/
                Container(
                  child: Column(
                    children: [
                      Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            const SizedBox(height: 8),

                            EntrySection(
                              icon: Icons.receipt_long_outlined,
                              title: "Entry Details",
                              iconGradient: [
                                app_color,
                                app_color.withValues(alpha: 0.7),
                              ],
                              children: [
                                EntryFormField(
                                  label: "Date",
                                  icon: Icons.calendar_today,
                                  iconGradient: [
                                    app_color,
                                    app_color.withValues(alpha: 0.7),
                                  ],
                                  controller: _dateController,
                                  readOnly: true,
                                  enabled: !isUniGasSerial(serial_no),
                                  suffixIcon: isUniGasSerial(serial_no)
                                      ? Icon(
                                          Icons.lock,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        )
                                      : null,
                                  onTap: isUniGasSerial(serial_no)
                                      ? null
                                      : () {
                                          _selectsaleDate(context);
                                        },
                                ),

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

                                const EntryInfoBanner(
                                  text:
                                      'Duplicate voucher numbers in Tally will trigger automatic assignment of a new number.',
                                ),

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
                                    _notifier.setSelectedVchType(value!);
                                    fetchvchnos(_selectedvchtypename);
                                  },
                                ),

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
                                              (item) =>
                                                  item.toLowerCase().contains(
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
                                                _selectedpartyledger
                                                        ?.isNotEmpty ==
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
                                                Theme.of(context)
                                                    .inputDecorationTheme
                                                    .fillColor ??
                                                Theme.of(context).cardColor
                                                    .withValues(alpha: 0.95),
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
                                                borderRadius:
                                                    BorderRadius.circular(10),
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
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .onSurfaceVariant,
                                                      size: 20,
                                                    ),
                                                    onPressed: () {
                                                      _partyLedgerController
                                                          .clear();
                                                      _notifier
                                                          .clearSelectedPartyLedger();
                                                      setState(() {
                                                        selectedPartyLedgerPriceLevel =
                                                            null;
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
                                            enabledBorder: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                              borderSide: BorderSide(
                                                color: Theme.of(
                                                  context,
                                                ).dividerColor,
                                                width: 1,
                                              ),
                                            ),
                                            focusedBorder: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                              borderSide: BorderSide(
                                                color: app_color,
                                                width: 1.5,
                                              ),
                                            ),
                                            errorBorder: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(14),
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
                                        _notifier.selectPartyLedger(suggestion);
                                        _partyLedgerController.text =
                                            suggestion;
                                        setState(() {
                                          selectedPartyLedgerPriceLevel =
                                              partyLedgerPriceLevelMap[suggestion];
                                        });
                                        debugPrint(
                                          'selected party ledger -> $_selectedpartyledger',
                                        );
                                        debugPrint(
                                          'selected price level -> $selectedPartyLedgerPriceLevel',
                                        );
                                        FocusManager.instance.primaryFocus
                                            ?.unfocus();
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

                                EntryDropdownField<String>(
                                  label: "Sales Ledger",
                                  icon: Icons.sell_outlined,
                                  iconGradient: [
                                    Colors.blueAccent,
                                    Colors.indigo,
                                  ],
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
                                    _notifier.setSelectedSalesLedger(value!);
                                  },
                                ),
                              ],
                            ),

                            EntrySection(
                              icon: Icons.link,
                              title: "Reference",
                              iconGradient: [
                                Colors.pinkAccent,
                                Colors.deepPurpleAccent,
                              ],
                              children: [
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

                                EntryFormField(
                                  label: "Reference No",
                                  icon: Icons.link,
                                  iconGradient: [
                                    Colors.redAccent,
                                    Colors.deepOrange,
                                  ],
                                  controller: controller_refno,
                                  validator: (value) => null,
                                ),
                              ],
                            ),

                            EntrySection(
                              icon: Icons.shopping_cart,
                              title: "Items",
                              iconGradient: [Colors.purple, Colors.blue],
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Bulk multi-item picker is now the sole
                                  // way to add items — it carries every
                                  // check/behavior the single-item flow
                                  // (_showItemDetailsPopup / addItem) had,
                                  // including per-item unit selection, so
                                  // the old single-add button is hidden
                                  // (not deleted — _showItemDetailsPopup
                                  // and addItem() are left intact below).
                                  GestureDetector(
                                    onTap: () {
                                      _onAddItemTapped(context);
                                    },
                                    child: Container(
                                      width: 34,
                                      height: 34,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        gradient: const LinearGradient(
                                          colors: [
                                            Colors.indigo,
                                            Colors.blueAccent,
                                          ],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.indigo.withValues(
                                              alpha: 0.3,
                                            ),
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
                                ],
                              ),
                              children: [
                                ListView.builder(
                                  physics: const NeverScrollableScrollPhysics(),
                                  shrinkWrap: true,
                                  itemCount: saleItems.length,
                                  itemBuilder: (context, index) {
                                    final item = saleItems[index];
                                    final itemUnit = [
                                      if (item.itemUnit.isNotEmpty)
                                        item.itemUnit,
                                      if (item.meterFrom.isNotEmpty ||
                                          item.meterTo.isNotEmpty)
                                        'Meter: ${item.meterFrom} - ${item.meterTo}',
                                    ].join(' | ');

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
                                      quantityLocked:
                                          _isQtyLockedByMeterReading(
                                            item.meterFrom,
                                            item.meterTo,
                                          ),
                                      onIncrement: () {
                                        _notifier.incrementItemQuantity(index);
                                        _syncTotalsControllers();
                                      },
                                      onDecrement: () {
                                        _notifier.decrementItemQuantity(index);
                                        _syncTotalsControllers();
                                      },
                                      onDelete: () {
                                        _deleteSaleItem(index);
                                      },
                                    );
                                  },
                                ),
                              ],
                            ),

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
                                      colors: [Colors.teal, Colors.green],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.teal.withValues(
                                          alpha: 0.3,
                                        ),
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
                                        currencyFormat.format(
                                          item.ledgerAmount,
                                        ),
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

                            if (isUniGasMeterReadingSerial)
                              EntrySection(
                                icon: Icons.assignment_ind_outlined,
                                title: "Receiver Information",
                                iconGradient: [Colors.teal, Colors.tealAccent],
                                children: [
                                  EntryFormField(
                                    label: "Receiver Name *",
                                    icon: Icons.person_outline,
                                    iconGradient: [
                                      Colors.teal,
                                      Colors.tealAccent,
                                    ],
                                    controller: bulkReceiverNameController,
                                  ),
                                  EntryFormField(
                                    label: "Receiver Mobile",
                                    icon: Icons.phone_outlined,
                                    iconGradient: [
                                      Colors.blue,
                                      Colors.blueAccent,
                                    ],
                                    controller: bulkReceiverMobileController,
                                    keyboardType: TextInputType.phone,
                                    validator: (value) => null,
                                  ),
                                  // EID# is bulk (tanker) delivery only -
                                  // cylinder deliveries, Sales, and Receipt
                                  // just take Name/Mobile/Signature.
                                  if (_isBulkDelivery == true) ...[
                                    EntryFormField(
                                      label: "Receiver EID#",
                                      icon: Icons.badge_outlined,
                                      iconGradient: [
                                        Colors.purple,
                                        Colors.deepPurpleAccent,
                                      ],
                                      controller: bulkReceiverEidController,
                                      keyboardType: TextInputType.number,
                                      onChanged: _formatBulkReceiverEid,
                                      validator: (value) => null,
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        left: 16,
                                        right: 16,
                                        top: 2,
                                        bottom: 6,
                                      ),
                                      child: Text(
                                        "Format: 784-****-*******-*",
                                        style: GoogleFonts.poppins(
                                          fontSize: 11,
                                          fontStyle: FontStyle.italic,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant
                                              .withValues(alpha: 0.7),
                                        ),
                                      ),
                                    ),
                                  ],
                                  ReceiverSignatureTile(
                                    signatureBytes: bulkReceiverSignatureBytes,
                                    onCaptured: (bytes) => setState(() {
                                      bulkReceiverSignatureBytes = bytes;
                                    }),
                                  ),
                                ],
                              ),

                            Row(
                              children: [
                                // 🌈 VAT Ledger Dropdown
                                Expanded(
                                  child: Padding(
                                    padding: EdgeInsets.only(
                                      top: 20,
                                      left: 10,
                                      right: isUniGasMeterReadingSerial
                                          ? 20
                                          : 10,
                                    ),
                                    child: SearchableSelectorField<String>(
                                      label: "VAT Ledger",
                                      hintText: "Select VAT Ledger",
                                      icon: Icons.receipt_long_outlined,
                                      iconGradient: const [
                                        Colors.indigo,
                                        Colors.cyan,
                                      ],
                                      filled: false,
                                      borderRadius: 16,
                                      contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 12,
                                      ),
                                      value: _selectedvatledger,
                                      items: vatledgerdata,
                                      itemLabel: (item) => item,
                                      onChanged: (value) {
                                        _notifier
                                            .setSelectedVatLedgerAndRecalculate(
                                              value!,
                                            );
                                        _syncTotalsControllers();
                                      },
                                    ),
                                  ),
                                ),

                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.only(
                                      top: 20,
                                      left: 0,
                                      right: 10,
                                    ),
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
                                          ).colorScheme.onSurface,
                                          fontWeight: FontWeight.w500,
                                        ),

                                        // 🌈 Gradient Currency Symbol (inline instead of icon)
                                        prefix: Container(
                                          margin: const EdgeInsets.only(
                                            right: 8,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: const BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: [
                                                Colors.green,
                                                Colors.teal,
                                              ], // ✅ distinct from Ledger
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
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          borderSide: BorderSide(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
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
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          borderSide: BorderSide(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 12,
                                            ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            EntrySection(
                              icon: Icons.notes_rounded,
                              title: "Narration",
                              iconGradient: [
                                Colors.pinkAccent,
                                Colors.deepOrange,
                              ],
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
                          ],
                        ),
                      ),

                      EntryTotalBar(
                        label: "Total Amount",
                        value: controller_totalamt.text.isNotEmpty
                            ? controller_totalamt.text
                            : "0.00",
                        currencySymbol: getCurrencySymbol(currencycode),
                        currencyCode: currencycode,
                      ),

                      EntrySaveButton(
                        label: "Save",
                        onPressed: errorMessageVchNo.isNotEmpty
                            ? null
                            : () {
                                if (_formKey.currentState != null &&
                                    _formKey.currentState!.validate()) {
                                  _formKey.currentState!.save();
                                  if (isUniGasMeterReadingSerial) {
                                    final startText =
                                        voucherStartReadingController.text
                                            .trim();
                                    final endText = voucherEndReadingController
                                        .text
                                        .trim();

                                    final isStartFilled = startText.isNotEmpty;
                                    final isEndFilled = endText.isNotEmpty;

                                    if ((isStartFilled && !isEndFilled) ||
                                        (!isStartFilled && isEndFilled)) {
                                      setState(() {
                                        meterReadingError =
                                            "Please enter both start and end reading";
                                      });

                                      showAppMessage(
                                        context,
                                        "Please enter both start and end reading",
                                      );

                                      return;
                                    }

                                    if (!isStartFilled && !isEndFilled) {
                                      setState(() {
                                        meterReadingError = null;
                                      });
                                    }

                                    if (isStartFilled && isEndFilled) {
                                      final start = double.tryParse(startText);
                                      final end = double.tryParse(endText);

                                      if (start == null || end == null) {
                                        setState(() {
                                          meterReadingError =
                                              "Please enter valid meter readings";
                                        });

                                        showAppMessage(
                                          context,
                                          "Please enter valid meter readings",
                                        );

                                        return;
                                      }

                                      if (end <= start) {
                                        setState(() {
                                          meterReadingError =
                                              "End reading must be greater than start reading";
                                        });

                                        showAppMessage(
                                          context,
                                          "End reading must be greater than start reading",
                                        );

                                        return;
                                      }

                                      setState(() {
                                        meterReadingError = null;
                                      });
                                    }
                                  }
                                  saveEntry();
                                }
                              },
                      ),
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

