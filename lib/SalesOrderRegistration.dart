import 'dart:io';
import 'package:FincoreGo/Items.dart';
import 'package:FincoreGo/PendingSalesEntry.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'constants.dart';
import 'PendingSalesOrderEntry.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:FincoreGo/widgets/app_bottom_nav.dart';
import 'widgets/entry_widgets.dart';
import 'widgets/searchable_selector.dart';
import 'api/api_exception.dart';
import 'api/ledger_repository.dart';
import 'api/monthly_bucket_helper.dart';
import 'api/pagination_helper.dart';
import 'api/stock_repository.dart';
import 'api/tally_api_client.dart';
import 'api/voucher_entry_repository.dart';

class SalesOrderRegistration extends StatefulWidget {
  const SalesOrderRegistration({Key? key}) : super(key: key);
  @override
  _SalesOrderRegistrationPageState createState() =>
      _SalesOrderRegistrationPageState();
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
  final String meterFrom;
  final String meterTo;

  SaleItem({
    required this.itemName,
    required this.itemQuantity,
    required this.itemPrice,
    required this.itemAmount,
    required this.itemLocation,
    required this.itemUnit,
    required this.accountingAllocationList,
    required this.batchAllocationList,
    this.meterFrom = '',
    this.meterTo = '',
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
    );
  }
}

class Unit {
  final String name;
  final double multiplier;

  Unit({required this.name, required this.multiplier});

  factory Unit.fromJson(Map<String, dynamic> json) {
    return Unit(
      name: (json['name'] ?? '').toString(),
      multiplier: double.tryParse('${json['multiplier']}') ?? 1.0,
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

class _SalesOrderRegistrationPageState extends State<SalesOrderRegistration>
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

  bool get isUniGasSerial {
    final currentSerial = serial_no?.trim() ?? '';

    // 👇 put only that one serial here

    return currentSerial == uniGasSerialNumber;
  }

  void _confirmLedgerDeletion(
    BuildContext context,
    int index,
    String ledgername,
  ) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Confirm Deletion'),
          content: Text('Do you really want to delete $ledgername ledger?'),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Dismiss the dialog
              },
              child: Text(
                'No',
                style: TextStyle(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurfaceVariant, // Change the text color here
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Dismiss the dialog
                _deleteLedger(index);
              },
              child: Text(
                'Yes',
                style: TextStyle(
                  color: app_color, // Change the text color here
                ),
              ),
            ),
          ],
        );
      },
    );
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

  void _confirmItemDeletion(BuildContext context, int index, String itemname) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Confirm Deletion'),
          content: Text('Do you really want to delete $itemname?'),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Dismiss the dialog
              },
              child: Text(
                'No',
                style: TextStyle(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurfaceVariant, // Change the text color here
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Dismiss the dialog
                _deleteSaleItem(index);
              },
              child: Text(
                'Yes',
                style: TextStyle(
                  color: app_color, // Change the text color here
                ),
              ),
            ),
          ],
        );
      },
    );
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
            (item.itemPrice * double.parse(item.itemQuantity));
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

  String name = "", email = "", saledatestring = '', saledatetxt = '';

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
      _isFocused_orderno = false;

  String? hostname = "",
      company = "",
      company_lowercase = "",
      serial_no = "",
      username = "",
      HttpURL = "",
      SecuritybtnAcessHolder = "";

  late DateTime saledate, refdate;
  List<String> vchnos = [];

  // --- tally-api migration: masterId lookups -------------------------------
  // The legacy `getSalesData`/`entry/create` endpoints spoke Tally's own
  // XML-tag names (LEDGERNAME/STOCKITEMNAME/GODOWNNAME/...) end-to-end, so
  // the UI never needed a numeric id for anything - it just round-tripped
  // display names. tally-api's `voucher-entries` write endpoint needs
  // `ledgerMasterId`/`stockItemMasterId`/`unitMasterId`/`godownMasterId`/
  // `voucherTypeMasterId`/`currencyMasterId` instead, so these maps (built
  // once in loadData(), from the same master lists already fetched for the
  // dropdowns) resolve a selected display name back to its masterId at
  // submit time, without changing any of the existing name-based dropdown/
  // validation logic above.
  final TallyApiClient _tallyApiClient = TallyApiClient();
  final Map<String, int> _ledgerMasterIdByName = {};
  final Map<String, int> _godownMasterIdByName = {};
  final Map<String, int> _voucherTypeMasterIdByName = {};
  int? _currencyMasterId;

  double selectedMultiplier = 0.0;

  final DateFormat _dateFormat = DateFormat('yyyyMMdd');

  List<SaleItem> saleItems = [];
  List<LedgerEntry> ledgerEntries = [];
  String currencycode = '';

  final TextEditingController itemQuantityController = TextEditingController();
  final TextEditingController itemRateController = TextEditingController();
  final TextEditingController itemAmountController = TextEditingController();
  final TextEditingController ledgerAmountController = TextEditingController();
  final TextEditingController _dateController = TextEditingController();
  final TextEditingController controller_orderno = TextEditingController();

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

  Future<void> generateSalesOrderPDF() async {
    final pdf = pw.Document();

    int totalQuantity = 0;
    double totalitemAmount = 0;
    for (var item in saleItems) {
      String qty = item.itemQuantity;
      int qty_int = int.parse(qty);
      totalQuantity += qty_int;

      totalitemAmount += item.itemAmount;
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
            // Logo pinned top-left, "Sales Order" heading centered
            // independently - matches the Sales Invoice PDF layout.
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
                          'Sales Order',
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
                    'Sales Order',
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
                        children: [pw.Text(company!)],
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
                                        pw.Text('Voucher No:'),
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
                                        pw.Text('Order No:'),
                                        pw.SizedBox(height: 2),
                                        pw.Text(controller_orderno.text),
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
                          pw.Text(_selectedpartyledger!),
                          pw.SizedBox(height: 20),
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
              child: pw.Expanded(
                child: pw.Column(
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
            ),

            // NOTE: these tables are direct top-level widgets (not
            // wrapped in a Container/Column) — pw.MultiPage can only
            // split a pw.Table row-by-row across pages when the
            // Table is top-level; wrapping it defers every row to
            // the next page instead. Left/right border lines are
            // added on each Table's own TableBorder so the box
            // still looks unified.
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

                            child: pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                pw.Text(
                                  item.value.itemName,
                                  style: pw.TextStyle(fontSize: 10),
                                ),
                                if (isUniGasSerial &&
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
                                pw.SizedBox(width: 2),
                                pw.Text(
                                  item.value.itemUnit,
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
                                item.value.itemAmount.toString(),
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
                            formatAmountInvoice(totalitemAmount.toString()),
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

              // declaration table
              pw.Table(
                border: pw.TableBorder(
                  left: pw.BorderSide(width: 1.0),
                  right: pw.BorderSide(width: 1.0),
                  horizontalInside: pw.BorderSide.none,
                  verticalInside: pw.BorderSide.none,
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
                              /* pw.SizedBox(height:10),

                                                  pw.Text(
                                                    'Declaration',
                                                    textAlign: pw.TextAlign.left,
                                                    style: pw.TextStyle(
                                                      fontSize: 10,
                                                    ),
                                                  ),

                                                  pw.Text(
                                                    'We declare that this invoice shows the actual price of the goods described and that all particulars are true and correct',
                                                    textAlign: pw.TextAlign.left,
                                                    style: pw.TextStyle(
                                                      fontSize: 10,
                                                    ),
                                                  ),
                                                  pw.SizedBox(height: 10)*/
                            ],
                          ),
                        ),
                      ),

                      pw.Expanded(
                        flex: 1,
                        child: pw.Container(
                          margin: pw.EdgeInsets.only(top: 30),
                          padding: pw.EdgeInsets.fromLTRB(5, 5, 5, 5),
                          decoration: pw.BoxDecoration(
                            border: pw.Border(
                              top: pw.BorderSide(width: 1.0),
                              left: pw.BorderSide(width: 1.0),
                            ),
                          ),
                          // Left, Top, Right, Bottom
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
                              pw.SizedBox(height: 5),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],

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
          ];
        },
      ),
    );

    final pdfData = await pdf.save();

    final dir = await getApplicationDocumentsDirectory();

    final filePath = '${dir.path}/${_selectedpartyledger ?? "SalesOrder"}.pdf';

    final file = File(filePath);
    await file.writeAsBytes(pdfData);

    await Share.shareXFiles([
      XFile(filePath, mimeType: 'application/pdf'),
    ], text: 'Sharing Sales Order for $_selectedpartyledger');

    // Drop focus first - otherwise updating _partyLedgerController's text
    // below while the Party Ledger TypeAheadField still has focus makes it
    // re-run its suggestionsCallback (which matches everything) and pop
    // its suggestions overlay back open right after reset.
    FocusManager.instance.primaryFocus?.unfocus();

    setState(() {
      controller_narration.clear();
      controller_orderno.clear();

      _textFieldFocusNodeNarration.unfocus(); // Unfocus the TextField

      saledate = DateTime.now();
      saledatestring = _dateFormat.format(saledate);
      saledatetxt = formatlastsaledate(saledatestring);
      _dateController.text = saledatetxt;

      _selectedvchtypename = (vchtypenamedata.isNotEmpty ? vchtypenamedata[0] : null);
      fetchvchnos(_selectedvchtypename);
      _selectedpartyledger = (partyledgerdata.isNotEmpty ? partyledgerdata[0] : null);

      _selectedsalesledger = (salesledger_data.isNotEmpty ? salesledger_data[0] : null);

      _selectedledger = ledgerdata.isNotEmpty ? ledgerdata[0]['name'] : null;

      _selectedvatledger = (vatledgerdata.isNotEmpty ? vatledgerdata[0] : null);

      _selecteditem = '${(itemdata.isNotEmpty ? itemdata[0]['name'] : '')}';
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
            (item.itemPrice * double.parse(item.itemQuantity));
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
      _isFocused_orderno = false;
    });
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

    if (saleItems.isEmpty) {
      showAppMessage(context, 'Atleast add 1 item');
    } else {
      setState(() {
        _isLoading = true;
      });
      String narrationValue = controller_narration.text.trim();
      String vchnoValue = _vchnoController.text.trim();
      String refnoValue = controller_orderno.text.trim();

      // --- tally-api migration: resolve every display name this screen
      // works with back to the masterId `voucher-entries` needs (see the
      // lookup maps built by loadData()).
      final int? voucherTypeMasterId =
          _voucherTypeMasterIdByName[_selectedvchtypename];
      final int? partyLedgerMasterId =
          _ledgerMasterIdByName[_selectedpartyledger];
      final int? salesLedgerMasterId =
          _ledgerMasterIdByName[_selectedsalesledger];
      final int? currencyMasterId = _currencyMasterId;

      if (voucherTypeMasterId == null) {
        showAppMessage(context, 'Please select a Voucher Type');
        setState(() => _isLoading = false);
        return;
      }
      if (partyLedgerMasterId == null) {
        showAppMessage(context, 'Unknown Party Ledger - please reselect it');
        setState(() => _isLoading = false);
        return;
      }
      if (salesLedgerMasterId == null) {
        showAppMessage(context, 'Please select a Sales Ledger');
        setState(() => _isLoading = false);
        return;
      }
      if (currencyMasterId == null) {
        showAppMessage(context, 'Could not resolve the company currency');
        setState(() => _isLoading = false);
        return;
      }

      double totalItemAmount = 0.0;
      for (SaleItem item in saleItems) {
        totalItemAmount += item.itemAmount; // calculating item amounts total
      }

      // Builds each inventory entry - resolves stockItemMasterId/
      // unitMasterId from the same itemdata list the item/unit dropdowns
      // use. godownMasterId comes from the item's chosen location; when the
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
            ((itemInfo['unit'] as List?) ?? const [])
                .cast<Map<String, dynamic>>();
        final Map<String, dynamic> unitInfo = units.firstWhere(
          (u) => u['name'] == item.itemUnit,
          orElse: () => {},
        );
        final int? unitMasterId = unitInfo['masterId'] as int?;

        if (stockItemMasterId == null || unitMasterId == null) {
          showAppMessage(
            context,
            'Could not resolve item/unit for "${item.itemName}" - please re-add it',
          );
          setState(() => _isLoading = false);
          return;
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
                // non-batch-tracked stock items - is used here, matching
                // what a real Tally sync would show for the same item.
                'batchName': 'Primary',
                'quantity': quantity,
              },
            ],
        });
      }

      double totalLedgerAmount = 0.0;
      for (LedgerEntry ledger in ledgerEntries) {
        // calculating total ledger amount
        totalLedgerAmount +=
            ledger.ledgerAmount; // calculating ledger amounts total
      }

      // Double-entry ledgerEntries: the Party ledger is debited for the
      // full invoice value; the Sales ledger, any additional ledgers, and
      // VAT (when applicable) are credited for their respective shares -
      // the same net effect as legacy's signed-AMOUNT/ISDEEMEDPOSITIVE
      // convention, just expressed as tally-api's own isDebit-flag +
      // unsigned-amount pairs (see vouchers-sync, which stores `amount` as
      // an unsigned magnitude the same way).
      final double partyLedgerAmount =
          totalVatAmount +
          totalItemAmount +
          totalLedgerAmount; // adding vat total, items total, ledgers total

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

      bool missingLedger = false;
      for (final entry in ledgerEntries) {
        final int? ledgerMasterId = _ledgerMasterIdByName[entry.ledgerName];
        if (ledgerMasterId == null) {
          missingLedger = true;
          break;
        }
        ledgerEntriesPayload.add({
          'ledgerMasterId': ledgerMasterId,
          'amount': entry.ledgerAmount,
          'isDebit': false,
          'isPartyLedger': false,
        });
      }
      if (missingLedger) {
        showAppMessage(context, 'Could not resolve one of the added ledgers');
        setState(() => _isLoading = false);
        return;
      }

      // Add VAT ledger data if applicable
      if (_selectedvatledger != 'Not Applicable') {
        final int? vatLedgerMasterId = _ledgerMasterIdByName[_selectedvatledger];
        if (vatLedgerMasterId == null) {
          showAppMessage(context, 'Could not resolve the VAT ledger');
          setState(() => _isLoading = false);
          return;
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
        'narration': narrationValue,
        'reference': refnoValue,
        if (vchnoValue.isNotEmpty) 'voucherNumber': vchnoValue,
        'ledgerEntries': ledgerEntriesPayload,
        'inventoryEntries': inventoryEntries,
      };

      try {
        await VoucherEntryRepository.instance.create(body);
        showSalesOrderDialog(context);
      } on ApiException catch (e) {
        showAppMessage(context, e.message);
      } catch (e) {
        showAppMessage(context, 'Could not reach the server. Please try again.');
        print(e);
      }
    }
    setState(() {
      _isLoading = false;
    });
  }

  void showSalesOrderDialog(BuildContext context) {
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: "SalesOrder",
      barrierColor: Colors.black.withValues(alpha: 0.35),
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: MediaQuery.of(context).size.width * 0.85,
              padding: const EdgeInsets.all(20.0),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(28),
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
                  const Text(
                    'Do you want to share the sales order?',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18.0),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Sales Order Created Successfully',
                    textAlign: TextAlign.center,
                    style: TextStyle(
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
                          // Drop focus first - otherwise updating
                          // _partyLedgerController's text below while the
                          // Party Ledger TypeAheadField still has focus
                          // makes it re-run its suggestionsCallback (which
                          // matches everything) and pop its suggestions
                          // overlay back open right after reset. A bare
                          // unfocus() leaves the scope's "last focused
                          // descendant" pointer intact, so popping this
                          // dialog can still silently hand focus straight
                          // back to that field - requesting a disposable
                          // FocusNode instead fully severs that link.
                          FocusScope.of(context).requestFocus(FocusNode());
                          Navigator.pop(context);
                          setState(() {
                            controller_narration.clear();
                            controller_orderno.clear();

                            _textFieldFocusNodeNarration
                                .unfocus(); // Unfocus the TextField

                            saledate = DateTime.now();
                            saledatestring = _dateFormat.format(saledate);
                            saledatetxt = formatlastsaledate(saledatestring);
                            _dateController.text = saledatetxt;

                            _selectedvchtypename = (vchtypenamedata.isNotEmpty ? vchtypenamedata[0] : null);
                            fetchvchnos(_selectedvchtypename);
                            _selectedpartyledger = (partyledgerdata.isNotEmpty ? partyledgerdata[0] : null);

                            _selectedsalesledger = (salesledger_data.isNotEmpty ? salesledger_data[0] : null);

                            _selectedledger = ledgerdata.isNotEmpty
                                ? ledgerdata[0]['name']
                                : null;

                            _selectedvatledger = (vatledgerdata.isNotEmpty ? vatledgerdata[0] : null);

                            _selecteditem = '${(itemdata.isNotEmpty ? itemdata[0]['name'] : '')}';
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

                            totalPriceOfItems = saleItems.fold(0.0, (
                              double previousAmount,
                              SaleItem item,
                            ) {
                              return previousAmount +
                                  (item.itemPrice *
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
                                (totalPriceOfItems * vat_perc)
                                    .toStringAsFixed(decimal!),
                              );

                              totalVatAmount =
                                  itemsVatAmount + ledgerVatAmount;

                              roundedtotalVatAmount = double.parse(
                                totalVatAmount.toStringAsFixed(decimal!),
                              );
                              NumberFormat formatter = NumberFormat(
                                '#,##0.${'0' * decimal!}',
                                'en_US',
                              );
                              String formattedVat = formatter.format(
                                roundedtotalVatAmount,
                              );
                              controller_vatamt.text = formattedVat
                                  .toString();
                            } else {
                              totalVatAmount = 0;

                              roundedtotalVatAmount = double.parse(
                                totalVatAmount.toStringAsFixed(decimal!),
                              );
                              NumberFormat formatter = NumberFormat(
                                '#,##0.${'0' * decimal!}',
                                'en_US',
                              );
                              String formattedVat = formatter.format(
                                roundedtotalVatAmount,
                              );
                              controller_vatamt.text = formattedVat
                                  .toString();
                            }
                            if (saleItems.isEmpty) {
                              isVisibleItemHeading = false;
                            } else {
                              isVisibleItemHeading = true;
                            }
                            totalAmountForVatAppEntries = ledgerEntries
                                .where((entry) => entry.vatApp)
                                .fold(0.0, (
                                  double previousAmount,
                                  LedgerEntry entry,
                                ) {
                                  return previousAmount + entry.ledgerAmount;
                                });

                            if (_selectedvatledger != 'Not Applicable') {
                              double vat_perc = vatperc / 100;
                              ledgerVatAmount =
                                  totalAmountForVatAppEntries * vat_perc;
                              totalVatAmount =
                                  itemsVatAmount + ledgerVatAmount;
                              roundedtotalVatAmount = double.parse(
                                totalVatAmount.toStringAsFixed(decimal!),
                              );
                              NumberFormat formatter = NumberFormat(
                                '#,##0.${'0' * decimal!}',
                                'en_US',
                              );
                              String formattedVat = formatter.format(
                                roundedtotalVatAmount,
                              );
                              controller_vatamt.text = formattedVat
                                  .toString();
                            } else {
                              totalVatAmount = 0;
                              roundedtotalVatAmount = double.parse(
                                totalVatAmount.toStringAsFixed(decimal!),
                              );
                              NumberFormat formatter = NumberFormat(
                                '#,##0.${'0' * decimal!}',
                                'en_US',
                              );
                              String formattedVat = formatter.format(
                                roundedtotalVatAmount,
                              );
                              controller_vatamt.text = formattedVat
                                  .toString();
                            }
                            if (ledgerEntries.isEmpty) {
                              isVisibleLedgerHeading = false;
                            } else {
                              isVisibleLedgerHeading = true;
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
                            String formattedtotal = formatter.format(
                              roundedtotalAmount,
                            );
                            controller_totalamt.text = formattedtotal
                                .toString();
                            _isFocused_vchno = false;
                            _isFocused_item = false;
                            _isFocused_unit = false;
                            _isFocused_ledger = false;
                            _isFocused_narration = false;
                            _isFocused_totalamt = false;
                            _isFocused_vatamt = false;
                            _isFocused_orderno = false;
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
                          // Same reasoning as "No, Thanks" - this path also
                          // stays on this screen (no navigation away), so
                          // sever focus from the Party Ledger field before
                          // the dialog closes.
                          FocusScope.of(context).requestFocus(FocusNode());
                          Navigator.pop(context);
                          await generateSalesOrderPDF();
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
                            controller_orderno.clear();
                            _textFieldFocusNodeNarration.unfocus();

                            saledate = DateTime.now();
                            saledatestring = _dateFormat.format(saledate);
                            saledatetxt = formatlastsaledate(saledatestring);
                            _dateController.text = saledatetxt;

                            _selectedvchtypename = (vchtypenamedata.isNotEmpty ? vchtypenamedata[0] : null);
                            fetchvchnos(_selectedvchtypename);
                            _selectedpartyledger = (partyledgerdata.isNotEmpty ? partyledgerdata[0] : null);
                            _partyLedgerController.text = _selectedpartyledger;
                            _selectedsalesledger = (salesledger_data.isNotEmpty ? salesledger_data[0] : null);
                            _selectedledger = ledgerdata.isNotEmpty ? ledgerdata[0]['name'] : null;
                            _selectedvatledger = (vatledgerdata.isNotEmpty ? vatledgerdata[0] : null);

                            _selecteditem = '${(itemdata.isNotEmpty ? itemdata[0]['name'] : '')}';
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

                            totalPriceOfItems = saleItems.fold(
                              0.0,
                                  (double previousAmount, SaleItem item) {
                                return previousAmount +
                                    (item.itemPrice *
                                        double.parse(item.itemQuantity));
                              },
                            );

                            totalAmountOfLedgers = ledgerEntries.fold(
                              0.0,
                                  (double previousAmount, LedgerEntry entry) {
                                return previousAmount + entry.ledgerAmount;
                              },
                            );

                            if (_selectedvatledger != 'Not Applicable') {
                              double vat_perc = vatperc / 100;
                              itemsVatAmount = double.parse(
                                  (totalPriceOfItems * vat_perc).toStringAsFixed(decimal!));
                              totalVatAmount = itemsVatAmount + ledgerVatAmount;
                            } else {
                              totalVatAmount = 0;
                            }

                            roundedtotalVatAmount = double.parse(
                                totalVatAmount.toStringAsFixed(decimal!));
                            NumberFormat formatter = NumberFormat(
                                '#,##0.${'0' * decimal!}', 'en_US');
                            controller_vatamt.text =
                                formatter.format(roundedtotalVatAmount);

                            isVisibleItemHeading = saleItems.isNotEmpty;

                            totalAmountForVatAppEntries = ledgerEntries
                                .where((entry) => entry.vatApp)
                                .fold(
                              0.0,
                                  (double previousAmount, LedgerEntry entry) {
                                return previousAmount + entry.ledgerAmount;
                              },
                            );

                            if (_selectedvatledger != 'Not Applicable') {
                              double vat_perc = vatperc / 100;
                              ledgerVatAmount =
                                  totalAmountForVatAppEntries * vat_perc;
                              totalVatAmount =
                                  itemsVatAmount + ledgerVatAmount;
                            } else {
                              totalVatAmount = 0;
                            }

                            roundedtotalVatAmount = double.parse(
                                totalVatAmount.toStringAsFixed(decimal!));
                            controller_vatamt.text =
                                formatter.format(roundedtotalVatAmount);

                            isVisibleLedgerHeading = ledgerEntries.isNotEmpty;

                            totalAmount = totalPriceOfItems +
                                totalAmountOfLedgers +
                                totalVatAmount;

                            roundedtotalAmount = double.parse(
                                totalAmount.toStringAsFixed(decimal!));
                            controller_totalamt.text =
                                formatter.format(roundedtotalAmount);

                            _isFocused_vchno = false;
                            _isFocused_item = false;
                            _isFocused_unit = false;
                            _isFocused_ledger = false;
                            _isFocused_narration = false;
                            _isFocused_totalamt = false;
                            _isFocused_vatamt = false;
                            _isFocused_orderno = false;
                          });
                        },
                        icon: const Icon(Icons.close_rounded,
                            size: 20, color: Colors.white),
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
                          padding: const EdgeInsets.symmetric(
                              horizontal: 22, vertical: 14),
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
                          await generateSalesOrderPDF();
                        },
                        icon: const Icon(Icons.share_rounded,
                            size: 20, color: Colors.white),
                        label: Text(
                          'Share',
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: app_color,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 22, vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          elevation: 4,
                          shadowColor: app_color.withOpacity(0.3),
                        ),
                      ),
                    ],
                  ),*/
                ],
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return Transform.scale(
          scale: Curves.easeOutBack.transform(animation.value),
          child: Opacity(opacity: animation.value, child: child),
        );
      },
    );
  }

  // --- tally-api migration: master-list fetch helpers ----------------------
  // No single tally-api endpoint returns this screen's whole "sales order
  // entry form" bundle the way legacy's `getSalesData` did, so loadData()
  // below assembles the same bundle from several tally-api list endpoints.
  // These four don't have a dedicated `lib/api/` repository yet (unlike
  // ledgers/stock-items) - see the migration report for the suggested
  // additions (GodownRepository/VoucherTypeRepository/CurrencyRepository/
  // an "all ledgers, unfiltered" method on LedgerRepository). Implemented
  // inline here for now, using the same `TallyApiClient`/`fetchAllPages`
  // plumbing those repositories use internally.
  Future<List<Map<String, dynamic>>> _fetchAllLedgersUnfiltered() =>
      fetchAllPages(
        (page) => _tallyApiClient.getForCompany('/ledgers?page=$page&limit=100'),
      );

  /// masterIds of every group with tally-api's `'SALES'` GroupReservedName
  /// enum label (screaming-snake-case, its 2026-08-21 schema-hardening
  /// migration - not Tally's own mixed-case `'Sales Accounts'` string) -
  /// used to classify "sales ledgers" the same way tally-api's own reports
  /// classify sales activity (see CLAUDE.md's reports section).
  Future<Set<int>> _fetchSalesAccountGroupIds() async {
    final groups = await fetchAllPages(
      (page) => _tallyApiClient.getForCompany('/groups?page=$page&limit=100'),
    );
    return groups
        .where((g) => g['reservedName'] == 'SALES')
        .map((g) => g['masterId'] as int)
        .toSet();
  }

  Future<List<Map<String, dynamic>>> _fetchGodowns() => fetchAllPages(
        (page) => _tallyApiClient.getForCompany('/godowns?page=$page&limit=100'),
      );

  Future<List<Map<String, dynamic>>> _fetchVoucherTypes() => fetchAllPages(
        (page) =>
            _tallyApiClient.getForCompany('/voucher-types?page=$page&limit=100'),
      );

  /// Resolves the company's own currency masterId to match [isoCode]
  /// (`currencycode`, e.g. `'AED'`) against tally-api's `isoCurrencyCode`
  /// field; falls back to the first currency the company has synced if
  /// nothing matches (a company should always have at least its home
  /// currency), and to `null` only when the company has none at all.
  Future<int?> _fetchCurrencyMasterId(String isoCode) async {
    final currencies = await fetchAllPages(
      (page) =>
          _tallyApiClient.getForCompany('/currencies?page=$page&limit=100'),
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

  Future<void> loadData() async {
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

    setState(() {
      _isLoading = true;
    });

    try {
      final results = await Future.wait([
        StockRepository.instance.listStockItems(),
        _fetchAllLedgersUnfiltered(),
        LedgerRepository.instance.listLedgers(),
        _fetchSalesAccountGroupIds(),
        _fetchGodowns(),
        _fetchVoucherTypes(),
        _fetchCurrencyMasterId(currencycode),
      ]);

      final stockItems = results[0] as List<Map<String, dynamic>>;
      final allLedgers = results[1] as List<Map<String, dynamic>>;
      final partyLedgers = results[2] as List<Map<String, dynamic>>;
      final salesAccountGroupIds = results[3] as Set<int>;
      final godowns = results[4] as List<Map<String, dynamic>>;
      final voucherTypes = results[5] as List<Map<String, dynamic>>;
      _currencyMasterId = results[6] as int?;

      for (final l in allLedgers) {
        _ledgerMasterIdByName[l['name'] as String] = l['masterId'] as int;
      }
      for (final g in godowns) {
        _godownMasterIdByName[g['name'] as String] = g['masterId'] as int;
      }
      // Only "Sales Order" (Tally's own reservedName, stable regardless of
      // any custom voucher-type naming) - matches legacy's
      // `{'type': 'sales order'}` request filter.
      final salesOrderTypes = voucherTypes
          .where((v) => v['reservedName'] == 'SALES_ORDER')
          .toList();
      for (final v in salesOrderTypes) {
        _voucherTypeMasterIdByName[v['name'] as String] = v['masterId'] as int;
      }

      setState(() {
        vchtypenamedata = salesOrderTypes
            .map((v) => v['name'] as String)
            .toList();
        _selectedvchtypename = (vchtypenamedata.isNotEmpty ? vchtypenamedata[0] : null);
        fetchvchnos(_selectedvchtypename);

        partyledgerdata = partyLedgers.map((l) => l['name'] as String).toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
        _selectedpartyledger = (partyledgerdata.isNotEmpty ? partyledgerdata[0] : null);
        _partyLedgerController.text = _selectedpartyledger;

        // "Sales ledgers" - every ledger under a 'Sales Accounts' group.
        salesledger_data = allLedgers
            .where((l) => salesAccountGroupIds.contains(l['groupMasterId']))
            .map((l) => l['name'] as String)
            .toList();
        _selectedsalesledger = (salesledger_data.isNotEmpty ? salesledger_data[0] : null);

        // "Other ledgers" (the free-pick "Add Ledger" dropdown, e.g.
        // freight/discount allocations) - best-effort equivalent of
        // legacy's `otherLedgers`: every ledger not already offered via the
        // Party or Sales Ledger dropdowns above.
        final partyNames = partyledgerdata.toSet();
        final salesNames = salesledger_data.toSet();
        ledgerdata = allLedgers
            .where(
              (l) =>
                  !partyNames.contains(l['name']) &&
                  !salesNames.contains(l['name']),
            )
            .toList();
        _selectedledger = ledgerdata.isNotEmpty
            ? ledgerdata[0]['name']
            : null;

        // VAT ledgers - tally-api exposes a direct `vatApplicable` flag per
        // ledger (more accurate than legacy's name/group-based guess).
        vatledgerdata.add('Not Applicable');
        vatledgerdata.addAll(
          allLedgers
              .where((l) => l['vatApplicable'] == true)
              .map((l) => l['name'] as String),
        );
        _selectedvatledger = (vatledgerdata.isNotEmpty ? vatledgerdata[0] : null);

        // Reshapes tally-api's stock-item row into the `name`/`saleprice`/
        // `standardprice`/`unit` shape `_updateUnitDropdown`/`addItem`/
        // `_addSelectedItemsInBulk` already expect (unchanged below) - see
        // those methods' own comments for the "saleprice"/"standardprice"/
        // unit-multiplier meaning. tally-api tracks at most a base + one
        // additional unit per item (no arbitrary compound-unit list like
        // legacy's `unit` array could carry) - `multiplier` for the
        // additional unit is `denominator` ("1 additional unit = denominator
        // base units", same relationship Items.dart's display already
        // relies on for this pair of fields).
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

        _selecteditem = '${(itemdata.isNotEmpty ? itemdata[0]['name'] : '')}';
        _itemController.text = _selecteditem;
        locationsdata = godowns.map((g) => g['name'] as String).toList();
        if (locationsdata.isNotEmpty) {
          selectedLocation = locationsdata[0];
          isVisibleLocation = true;
        } else {
          isVisibleLocation = false;
        }
        _updateUnitDropdown(_selecteditem);
      });
    } on ApiException catch (e) {
      showAppMessage(context, e.message);
    } catch (e) {
      showAppMessage(context, 'Could not reach the server. Please try again.');
      print(e);
    }

    setState(() {
      _isLoading = false;
    });
  }

  Future<void> fetchvchnos(String vchname) async {
    vchnos.clear();
    setState(() {
      _isLoading = true;
    });

    // tally-api's VoucherEntry has no server-side auto-numbering (see
    // VoucherEntryRepository's doc-comment on the "known gap") - this
    // fetches every existing voucher-entry, narrows it to this voucher type
    // and this year's date window (matching legacy's own from/to range),
    // and reuses generateNextVchNo() to suggest the next number exactly as
    // before. The field stays user-editable via the existing lock/edit
    // toggle (isVchEditable) since there's no server sequence to defer to.
    try {
      final entries = await VoucherEntryRepository.instance.listAll();
      final matching = entries.where((e) {
        if (e['voucherTypeName'] != vchname) return false;
        final date = DateTime.tryParse(e['date']?.toString() ?? '');
        if (date == null) return false;
        return !date.isBefore(yearStartDate) &&
            !date.isAfter(
              DateTime(
                yearEndDate.year,
                yearEndDate.month,
                yearEndDate.day,
                23,
                59,
                59,
              ),
            );
      });

      setState(() {
        vchnos = matching
            .map((e) => (e['voucherNumber'] as String?) ?? '')
            .where((v) => v.isNotEmpty)
            .toList();

        // SORT first
        vchnos.sort((a, b) {
          RegExp regExp = RegExp(r'(\d+)(?!.*\d)');
          int numA = int.tryParse(regExp.firstMatch(a)?.group(0) ?? '0') ?? 0;
          int numB = int.tryParse(regExp.firstMatch(b)?.group(0) ?? '0') ?? 0;
          return numA.compareTo(numB);
        });

        // GENERATE NEXT
        String nextVch = generateNextVchNo(vchnos);

        _vchnoController.text = nextVch;
      });
    } on ApiException catch (e) {
      vchnos.clear();
      showAppMessage(context, e.message);
    } catch (e) {
      vchnos.clear();
      showAppMessage(context, 'Could not reach the server. Please try again.');
      print(e);
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
        _selectedunit = (unitdata.isNotEmpty ? unitdata[0].name : '');

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
    // real van meter has no fixed max length. BigInt parses/subtracts them
    // exactly; double loses precision past ~15-17 digits and its .toInt()
    // silently clamps to 9223372036854775807 (int64 max) when the value is
    // too large to represent, instead of erroring.
    final start = BigInt.tryParse(startText);
    final end = BigInt.tryParse(endText);

    if (start != null && end != null && end > start) {
      qtyController.text = (end - start).toString();
    } else if (startText.isEmpty && endText.isEmpty) {
      qtyController.text = '1';
    }
  }

  double _estimateInvoiceLastRowFillerPadding(int itemCount) {
    // Calibrated against actual rendered output on an A4 page (same
    // technique as the Sales Invoice PDF). A single item's content ends
    // ~557pt from the top with no filler, so there's real room to stretch
    // the last row down to fill the page.
    const double targetContentEnd = 700.0;
    const double baselineForOneItem = 557.4;
    const double perItemHeight = 33.0;

    final double baseline =
        baselineForOneItem + (itemCount - 1) * perItemHeight;
    final double remaining = targetContentEnd - baseline;
    return remaining.clamp(5.0, 260.0);
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

  Future<void> _selectsaleDate(BuildContext context) async {
    if (isUniGasSerial) {
      closeKeyboard(context);
      showAppMessage(context, "Voucher date cannot be changed");
      return;
    }
    setState(() {
      _isFocused_orderno = false;
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

  /*
  Future<void> _showItemDetailsPopup(BuildContext context) async {
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
                                    setState(() {
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
                      onChanged: (val) => setState(() => selectedLocation = val!),
                      decoration: InputDecoration(
                        labelText: "Location",
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
                        setState(() {
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
  }
*/

  Future<void> _showItemDetailsPopup(BuildContext context) async {
    FocusManager.instance.primaryFocus?.unfocus();
    showModalBottomSheet(
      useSafeArea: true,
      requestFocus: false,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      context: context,
      isScrollControlled: true,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            final mediaQuery = MediaQuery.of(context);
            final screenHeight = mediaQuery.size.height;
            final isKeyboardOpen = mediaQuery.viewInsets.bottom > 0;

            final bool hasExtraFields = isVisibleLocation || isVisibleUnit;

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
              if (hasExtraFields) {
                if (screenHeight < 700) {
                  sheetHeight = 0.92;
                } else if (screenHeight < 850) {
                  sheetHeight = 0.78;
                } else {
                  sheetHeight = 0.68;
                }
              } else {
                if (screenHeight < 700) {
                  sheetHeight = 0.72;
                } else if (screenHeight < 850) {
                  sheetHeight = 0.60;
                } else {
                  sheetHeight = 0.50;
                }
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
                      ],

                      Text(
                        "Add Item",
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
                            key: _itemFormkey,
                            child: Column(
                              children: [
                                TypeAheadField<Map<String, dynamic>>(
                                  controller: _itemController,

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

                                  onSelected: (suggestion) {
                                    FocusScope.of(context).unfocus();

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
                                              colors: [
                                                Colors.blue,
                                                Colors.lightBlueAccent,
                                              ],
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
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
                                            if (_itemController.text.isNotEmpty)
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
                                                    isVisibleLocation = false;
                                                    isVisibleUnit = false;
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
                                            width: 1,
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

                                  emptyBuilder: (context) =>
                                      const SizedBox.shrink(),
                                ),

                                const SizedBox(height: 14),

                                AnimatedSize(
                                  duration: const Duration(milliseconds: 250),
                                  child: Visibility(
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
                                      onChanged: (val) => setStateDialog(
                                        () => selectedLocation = val!,
                                      ),
                                      decoration: InputDecoration(
                                        labelText: "Location",
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
                                            borderRadius: BorderRadius.all(
                                              Radius.circular(8),
                                            ),
                                          ),
                                          child: const Icon(
                                            Icons.location_on,
                                            color: Colors.white,
                                          ),
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
                                            width: 1,
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
                                      ),
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 14),

                                AnimatedSize(
                                  duration: const Duration(milliseconds: 250),
                                  child: Visibility(
                                    visible: isVisibleUnit,
                                    child: DropdownButtonFormField<String>(
                                      value: _selectedunit,
                                      isExpanded: true,
                                      items: unitdata.map((u) {
                                        return DropdownMenuItem(
                                          value: u.name,
                                          child: Text(
                                            u.name,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        );
                                      }).toList(),
                                      onChanged: (val) {
                                        setStateDialog(() {
                                          _selectedunit = val!;
                                          itemQuantityController.text = "1";
                                          selectedMultiplier = unitdata
                                              .firstWhere(
                                                (u) => u.name == _selectedunit,
                                              )
                                              .multiplier;
                                          updateRateAndAmount();
                                        });
                                      },
                                      decoration: InputDecoration(
                                        labelText: "Unit",
                                        prefixIcon: Container(
                                          margin: const EdgeInsets.all(8),
                                          decoration: const BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: [
                                                Colors.purple,
                                                Colors.deepPurpleAccent,
                                              ],
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                            ),
                                            borderRadius: BorderRadius.all(
                                              Radius.circular(8),
                                            ),
                                          ),
                                          child: const Icon(
                                            Icons.straighten,
                                            color: Colors.white,
                                          ),
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
                                            width: 1,
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
                                      ),
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 14),

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
                                          colors: [
                                            Colors.green,
                                            Colors.lightGreen,
                                          ],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ),
                                        borderRadius: BorderRadius.all(
                                          Radius.circular(8),
                                        ),
                                      ),
                                      child: const Icon(
                                        Icons.confirmation_num,
                                        color: Colors.white,
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

                                const SizedBox(height: 14),

                                TextFormField(
                                  controller: itemRateController,
                                  keyboardType: TextInputType.number,
                                  onChanged: (_) => updateAmount(),
                                  decoration: InputDecoration(
                                    labelText: "Rate",
                                    prefix: Container(
                                      margin: const EdgeInsets.only(right: 8),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: const BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [Colors.blue, Colors.blue],
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

                                const SizedBox(height: 14),

                                TextFormField(
                                  controller: itemAmountController,
                                  enabled: false,
                                  decoration: InputDecoration(
                                    labelText: "Amount",
                                    filled: true,
                                    fillColor:
                                        Theme.of(context).brightness ==
                                            Brightness.dark
                                        ? Theme.of(
                                            context,
                                          ).colorScheme.surfaceContainerHighest
                                        : (Theme.of(context).brightness ==
                                                  Brightness.dark
                                              ? Theme.of(context)
                                                    .colorScheme
                                                    .surfaceContainerHighest
                                              : Colors.grey.shade100),
                                    prefix: Container(
                                      margin: const EdgeInsets.only(right: 8),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: const BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [Colors.green, Colors.teal],
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
                                    disabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      borderSide: BorderSide(
                                        color: Theme.of(context).dividerColor,
                                        width: 1,
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
                                  onPressed: () => Navigator.of(context).pop(),
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
                                    if (_itemFormkey.currentState!.validate()) {
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
                ),
              ),
            );
          },
        );
      },
    );
  }

  /*
  void _showLedgerDetailsPopup(BuildContext context) {
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
                      child: SearchableSelectorField<String>(
                        value: _selectedledger as String?,
                        hintText: "Select Ledger",
                        label: "Ledger Name",
                        icon: Icons.account_balance_wallet,
                        iconGradient: const [Colors.blue, Colors.lightBlueAccent],
                        items: ledgerdata
                            .map<String>((ledger) => ledger['name'] as String)
                            .toList(),
                        itemLabel: (v) => v,
                        onChanged: (value) {
                          setState(() {
                            _selectedledger = value!;
                          });
                        },
                      ),
                    ),

                    //const SizedBox(height: 6),

                    // 💰 Ledger Amount
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
  }
*/

  void _showLedgerDetailsPopup(BuildContext context) {
    FocusManager.instance.primaryFocus?.unfocus();
    final TextEditingController _ledgerController = TextEditingController();

    _ledgerController.clear();
    _selectedledger = null;

    showModalBottomSheet(
      useSafeArea: true,
      requestFocus: false,
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
          SizedBox(
            width: 40,
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
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
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
    // Selected location per item - only surfaced (non-UniGas) when there's
    // more than one location to choose from; defaults to the first one.
    final Map<String, String> selectedLocationPerItem = {};
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
      final double? rate = _resolveItemOwnRate(itemInfo, multiplier);
      final String source = rate != null ? 'Item Rate' : 'Empty';

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
        final start = double.tryParse(meterFrom);
        final end = double.tryParse(meterTo);
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

            // Selected items bubble to the top (in their original relative
            // order among themselves); unselected items stay below (also
            // in original order). Since this recomputes on every toggle,
            // checking an item moves it up immediately, and unchecking it
            // drops it right back into its natural position among the
            // other unselected items - not to some arbitrary spot.
            final List<dynamic> filteredItems = [
              ...searchedItems.where(
                (i) => selectedItemNames.contains(i['name']?.toString() ?? ''),
              ),
              ...searchedItems.where(
                (i) =>
                    !selectedItemNames.contains(i['name']?.toString() ?? ''),
              ),
            ];

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
                                        startReadingControllers.putIfAbsent(
                                          name,
                                          () => TextEditingController(),
                                        );
                                        endReadingControllers.putIfAbsent(
                                          name,
                                          () => TextEditingController(),
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
                                                              !(isUniGasSerial &&
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
                                                    if (isUniGasSerial) ...[
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
                                                              ),
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
                                                              ),
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
                                    startReadingControllers,
                                    endReadingControllers,
                                    selectedUnitPerItem,
                                    selectedLocationPerItem,
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
    Map<String, String> selectedLocationPerItem,
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
      final String meterFrom = isUniGasSerial
          ? (startReadingControllers[name]?.text.trim() ?? '')
          : '';
      final String meterTo = isUniGasSerial
          ? (endReadingControllers[name]?.text.trim() ?? '')
          : '';

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
            meterFrom: meterFrom,
            meterTo: meterTo,
          ),
        );
      }
    }

    _recalcTotalsAfterBulkAdd();
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
            item.itemPrice == parsedPrice &&
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
        );

        setState(() {
          saleItems.add(newItem);
          // Rest of your code...
        });
      }

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
              (item.itemPrice * double.parse(item.itemQuantity));
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

        _selecteditem = '${(itemdata.isNotEmpty ? itemdata[0]['name'] : '')}';
        _itemController.text = _selecteditem;
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

    // tally-api's ledger row carries `vatApplicable` as a real bool
    // (legacy's own shape used a 0/1 int under a lowercase key).
    final vatApp = specificLedger['vatApplicable'] == true;

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
              (item.itemPrice * double.parse(item.itemQuantity));
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

      vatperc = prefs.getDouble('vatperc') ?? 5.0;

      decimal = prefs.getInt('decimalplace') ?? 2;

      saledate = DateTime.now();
      saledatestring = _dateFormat.format(saledate);
      saledatetxt = formatlastsaledate(saledatestring);
      _dateController.text = saledatetxt;

      SecuritybtnAcessHolder = prefs.getString('secbtnaccess');

      String? email_nav = prefs.getString('email_nav');
      String? name_nav = prefs.getString('name_nav');

      // tally-api migration: the legacy getSalesData/nos/create URLs this
      // screen used to build here are gone - loadData()/fetchvchnos()/
      // saveEntry() now talk to tally-api via StockRepository/
      // LedgerRepository/VoucherEntryRepository (+ the local TallyApiClient
      // helpers above) instead, which resolve the active company/session
      // from TokenStore rather than these SharedPreferences fields.

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

  @override
  void dispose() {
    _textFieldFocusNodeNarration
        .dispose(); // Dispose of the focus node when it's no longer needed.
    _animationController.dispose();
    super.dispose();
  }

  bool isValidEmail(String email) {
    // Simple email validation pattern
    final RegExp emailRegex = RegExp(
      r'^[\w-]+(\.[\w-]+)*@[a-zA-Z0-9-]+(\.[a-zA-Z0-9-]+)*(\.[a-zA-Z]{2,})$',
    );
    return emailRegex.hasMatch(email);
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
          (item.itemPrice * double.parse(item.itemQuantity));
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
          activeEntryType: AppEntryType.salesOrder,
        ),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        key: _scaffoldKey,
        appBar: entryAppBar(
          context: context,
          title: "New Sales Order Entry",
          onBack: () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => PendingSalesOrderEntry()),
            );
          },
        ),
        body: _buildSkeletonForm(),
      );
    }

    final NumberFormat currencyFormat = NumberFormat(
      "#,##0.${'0' * decimal!}", // 👈 dynamically repeat '0' for decimal places
    );
    return Scaffold(
      bottomNavigationBar: const AppBottomNav(
        activeTab: AppBottomNavTab.entries,
        activeEntryType: AppEntryType.salesOrder,
      ),
      key: _scaffoldKey,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: entryAppBar(
        context: context,
        title: "New Sales Order Entry",
        onBack: () {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => PendingSalesOrderEntry()),
          );
        },
      ),

      body: WillPopScope(
        onWillPop: () async {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => PendingSalesOrderEntry()),
          );
          return false;
        },
        child: Stack(
          children: [
            ListView(
              children: [
                GestureDetector(
                  onTap: () => _selectDateRangeVchNo(context),
                  child: Container(
                    margin: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 12,
                    ),
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
                          child: const Icon(
                            Icons.calendar_today,
                            color: Colors.white,
                            size: 20,
                          ),
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
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
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

                        Icon(
                          Icons.keyboard_arrow_down,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),

                Container(
                  child: Column(
                    children: [
                      Form(
                        key: _formKey,
                        child: Column(
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

                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              child: TextFormField(
                                controller: _vchnoController,

                                readOnly: !isVchEditable, // 👈 MAIN CHANGE
                                enableInteractiveSelection:
                                    isVchEditable, // 👈 ADD THIS
                                onChanged: (value) {
                                  if (isVchEditable) {
                                    checkVchNoExistence(value);
                                  }
                                },

                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: isVchEditable
                                      ? Theme.of(context).colorScheme.onSurface
                                      : Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant, // 👈 visual hint
                                ),

                                decoration: InputDecoration(
                                  labelText: "Voucher No.",
                                  labelStyle: GoogleFonts.poppins(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),

                                  errorText: errorMessageVchNo.isNotEmpty
                                      ? errorMessageVchNo
                                      : null,

                                  filled: true,
                                  fillColor:
                                      Theme.of(
                                        context,
                                      ).inputDecorationTheme.fillColor ??
                                      (Theme.of(
                                            context,
                                          ).inputDecorationTheme.fillColor ??
                                          Theme.of(
                                            context,
                                          ).cardColor.withOpacity(0.95)),

                                  prefixIcon: Container(
                                    margin: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [
                                          Colors.deepOrangeAccent,
                                          Colors.orangeAccent,
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      borderRadius: BorderRadius.all(
                                        Radius.circular(12),
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.confirmation_num_outlined,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ),

                                  // 👇 EDIT BUTTON
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      isVchEditable
                                          ? Icons.lock_open
                                          : Icons.edit,
                                      color: app_color,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        isVchEditable = !isVchEditable;
                                      });
                                    },
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

                                  contentPadding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                    horizontal: 14,
                                  ),
                                ),
                              ),
                            ),

                            Padding(
                              padding: EdgeInsets.only(
                                top: 0,
                                left: 10,
                                right: 10,
                                bottom: 0,
                              ),
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  color: Colors.grey.withOpacity(0.2),
                                ),
                                padding: EdgeInsets.all(10),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.info_outline_rounded,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                                    SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        'Duplicate voucher numbers in Tally will trigger automatic assignment of a new number.',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            Padding(
                              padding: const EdgeInsets.only(
                                top: 12,
                                left: 10,
                                right: 10,
                                bottom: 0,
                              ),
                              child: DropdownButtonFormField<String>(
                                isExpanded: true,
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor:
                                      Theme.of(
                                        context,
                                      ).inputDecorationTheme.fillColor ??
                                      (Theme.of(
                                            context,
                                          ).inputDecorationTheme.fillColor ??
                                          Theme.of(
                                            context,
                                          ).cardColor.withOpacity(0.95)),
                                  labelText: "Voucher Type",
                                  labelStyle: GoogleFonts.poppins(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),

                                  // Prefix icon with gradient bg (different color)
                                  prefixIcon: Container(
                                    margin: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [
                                          Colors.purpleAccent,
                                          Colors.deepPurple,
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      borderRadius: BorderRadius.all(
                                        Radius.circular(12),
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.discount_outlined,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ),

                                  // Borders
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
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 14,
                                  ),
                                ),
                                hint: Text(
                                  "Voucher Type Name",
                                  style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                value: _selectedvchtypename,
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
                                onTap: () {
                                  setState(() {
                                    _isFocused_vchno = false;
                                    _isFocused_narration = false;
                                    _isFocused_totalamt = false;
                                  });
                                },
                              ),
                            ),

                            Padding(
                              padding: const EdgeInsets.only(
                                top: 12,
                                left: 10,
                                right: 10,
                                bottom: 0,
                              ),
                              child: Container(
                                width: MediaQuery.of(context).size.width,
                                child: TypeAheadField<String>(
                                  suggestionsCallback: (pattern) async {
                                    // Filter matching ledgers (case-insensitive)
                                    return partyledgerdata
                                        .where(
                                          (item) => item.toLowerCase().contains(
                                            pattern.toLowerCase(),
                                          ),
                                        )
                                        .toList();
                                  },
                                  builder: (context, controller, focusNode) {
                                    _partyLedgerController =
                                        controller; // ensures correct reference

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
                                        hintText: "Search Party Ledger",
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
                                            (Theme.of(context)
                                                    .inputDecorationTheme
                                                    .fillColor ??
                                                Theme.of(
                                                  context,
                                                ).cardColor.withOpacity(0.95)),

                                        // 🌈 Gradient prefix icon
                                        prefixIcon: Container(
                                          margin: const EdgeInsets.all(6),
                                          decoration: const BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: [
                                                Colors.greenAccent,
                                                Colors.teal,
                                              ],
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                            ),
                                            borderRadius: BorderRadius.all(
                                              Radius.circular(12),
                                            ),
                                          ),
                                          child: const Icon(
                                            Icons.person_outline,
                                            color: Colors.white,
                                            size: 20,
                                          ),
                                        ),

                                        // ❌ Clear + ⬇ Dropdown icons
                                        suffixIcon: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (controller.text.isNotEmpty)
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
                                                    controller.clear();
                                                    _selectedpartyledger = "";
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

                                        // ✨ Borders
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          borderSide: BorderSide(
                                            color: Theme.of(
                                              context,
                                            ).dividerColor,
                                            width: 1,
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
                                        errorBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
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
                                    );
                                  },
                                  itemBuilder: (context, suggestion) {
                                    return ListTile(
                                      title: Text(
                                        suggestion,
                                        style: GoogleFonts.poppins(
                                          fontSize: 13,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurface,
                                        ),
                                      ),
                                    );
                                  },
                                  onSelected: (suggestion) {
                                    setState(() {
                                      _selectedpartyledger = suggestion;
                                      _partyLedgerController.text = suggestion;
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

                            Container(
                              padding: EdgeInsets.only(
                                top: 15,
                                left: 10,
                                right: 10,
                                bottom: 0,
                              ),
                              child: TextFormField(
                                enabled: true,
                                controller: controller_orderno,
                                validator: (value) {
                                  if (value!.isEmpty || value == null) {
                                    return 'Order No value cannot be empty';
                                  }
                                  return null;
                                },
                                decoration: InputDecoration(
                                  labelText: 'Order No',
                                  hintText: 'Enter order no',
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
                                      (Theme.of(
                                            context,
                                          ).inputDecorationTheme.fillColor ??
                                          Theme.of(
                                            context,
                                          ).cardColor.withOpacity(0.95)),
                                  prefixIcon: GestureDetector(
                                    child: Container(
                                      margin: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            app_color,
                                            app_color.withOpacity(0.7),
                                          ],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Icon(
                                        Icons.note_outlined,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                    ),
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
                                  contentPadding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                    horizontal: 14,
                                  ),
                                ),

                                onChanged: (value) {
                                  setState(() {
                                    _isFocused_narration = false;
                                    _isFocused_totalamt = false;
                                    _isFocused_orderno = true;
                                    _isFocused_vatamt = false;
                                    _isFocused_vchno = false;
                                  });
                                },
                                onFieldSubmitted: (value) {
                                  setState(() {
                                    _isFocused_narration = false;
                                    _isFocused_totalamt = false;
                                    _isFocused_orderno = false;
                                    _isFocused_vatamt = false;
                                    _isFocused_vchno = false;
                                  });
                                },
                                onTap: () {
                                  setState(() {
                                    _isFocused_narration = false;
                                    _isFocused_totalamt = false;
                                    _isFocused_orderno = true;
                                    _isFocused_vatamt = false;
                                    _isFocused_vchno = false;
                                  });
                                },
                                onEditingComplete: () {
                                  setState(() {
                                    _isFocused_narration = false;
                                    _isFocused_totalamt = false;
                                    _isFocused_orderno = false;
                                    _isFocused_vatamt = false;
                                    _isFocused_vchno = false;
                                  });
                                },
                              ),
                            ),

                            Padding(
                              padding: const EdgeInsets.only(
                                top: 12,
                                left: 10,
                                right: 10,
                                bottom: 0,
                              ),
                              child: SearchableSelectorField<String>(
                                label: "Sales Ledger",
                                hintText: "Sales Ledger",
                                icon: Icons.sell_outlined,
                                iconGradient: const [
                                  Colors.blueAccent,
                                  Colors.indigo,
                                ],
                                value: _selectedsalesledger,
                                items: salesledger_data,
                                itemLabel: (item) => item.toString(),
                                onChanged: (value) {
                                  setState(() {
                                    _selectedsalesledger = value!;
                                    _isFocused_vchno = false;
                                    _isFocused_narration = false;
                                    _isFocused_totalamt = false;
                                  });
                                },
                              ),
                            ),

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
                                      colors: [
                                        Colors.indigo,
                                        Colors.blueAccent,
                                      ],
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
                                      onIncrement: () {
                                        int currentQty =
                                            int.tryParse(item.itemQuantity) ??
                                            0;
                                        setState(() {
                                          item.itemQuantity = (currentQty + 1)
                                              .toString();
                                          _recalculateTotals();
                                        });
                                      },
                                      onDecrement: () {
                                        int currentQty =
                                            int.tryParse(item.itemQuantity) ??
                                            0;
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

                            Row(
                              children: [
                                // 🌈 VAT Ledger Dropdown
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.only(
                                      top: 20,
                                      left: 10,
                                      right: 5,
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
                                        setState(() {
                                          _selectedvatledger = value!;

                                          // 👇 VAT calculation logic intact
                                          totalPriceOfItems = saleItems.fold(
                                            0.0,
                                            (double prev, SaleItem item) =>
                                                prev +
                                                (item.itemPrice *
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
                                            roundedtotalVatAmount =
                                                double.parse(
                                                  totalVatAmount
                                                      .toStringAsFixed(
                                                        decimal!,
                                                      ),
                                                );
                                            NumberFormat formatter =
                                                NumberFormat(
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
                                                itemsVatAmount +
                                                ledgerVatAmount;

                                            roundedtotalVatAmount =
                                                double.parse(
                                                  totalVatAmount
                                                      .toStringAsFixed(
                                                        decimal!,
                                                      ),
                                                );
                                            NumberFormat formatter =
                                                NumberFormat(
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
                                            totalAmount.toStringAsFixed(
                                              decimal!,
                                            ),
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
                                ),

                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.only(
                                      top: 20,
                                      left: 5,
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
