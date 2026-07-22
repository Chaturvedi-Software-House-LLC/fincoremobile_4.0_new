import 'dart:convert';
import 'package:FincoreGo/Items.dart';
import 'package:FincoreGo/PendingSalesEntry.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'constants.dart';
import 'PendingSalesOrderEntry.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:progress_dialog_null_safe/progress_dialog_null_safe.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:FincoreGo/widgets/app_bottom_nav.dart';
import 'widgets/entry_widgets.dart';

class ModifySalesOrderEntry extends StatefulWidget {
  final int id, isSynced;
  final String type;
  final Map<String, dynamic> data;
  const ModifySalesOrderEntry({
    required this.id,
    required this.isSynced,
    required this.type,
    required this.data,
  });
  @override
  _ModifySalesOrderEntryPageState createState() =>
      _ModifySalesOrderEntryPageState(
        id: id,
        isSynced: isSynced,
        type: type,
        data: data,
      );
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
      name: json['name'],
      multiplier: double.parse(json['multiplier']),
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

class _ModifySalesOrderEntryPageState extends State<ModifySalesOrderEntry>
    with TickerProviderStateMixin {
  int id, isSynced;
  String type;
  Map<String, dynamic> data;
  _ModifySalesOrderEntryPageState({
    required this.id,
    required this.isSynced,
    required this.type,
    required this.data,
  });

  bool isDashEnable = true,
      isRolesVisible = true,
      isUserEnable = true,
      isUserVisible = true,
      isRolesEnable = true,
      _isLoading = true,
      isVisibleNoUserFound = false;

  bool _isInitialDataLoaded = false;

  TextEditingController _itemController = TextEditingController();
  TextEditingController _partyLedgerController = TextEditingController();

  final TextEditingController _dateController = TextEditingController();

  final TextEditingController _vchnoController = TextEditingController();

  String errorMessageVchNo = '';

  bool isVchEditable = false; // state variable

  late DateTime now = DateTime.now();

  // Current year start date
  late DateTime yearStartDate = DateTime(now.year, 1, 1);

  // Current year end date
  late DateTime yearEndDate = DateTime(now.year, 12, 31);

  List<String> vchnos = [];

  late AnimationController _animationController;
  late Animation<double> _animation;

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
                style: GoogleFonts.poppins(
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
                style: GoogleFonts.poppins(
                  color: app_color, // Change the text color here
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _deleteLedger(int index) {
    setState(() {
      ledgerEntries.removeAt(index);

      totalPriceOfItems = saleItems.fold(0.0, (
        double previousAmount,
        SaleItem item,
      ) {
        return previousAmount +
            (item.itemPrice * double.parse(item.itemQuantity));
      });

      totalAmountForVatAppEntries = ledgerEntries
          .where((entry) => entry.vatApp)
          .fold(0.0, (double previousAmount, LedgerEntry entry) {
            return previousAmount + entry.ledgerAmount;
          });

      totalAmountOfLedgers = ledgerEntries.fold(0.0, (
        double previousAmount,
        LedgerEntry entry,
      ) {
        return previousAmount + entry.ledgerAmount;
      });

      if (_selectedvatledger != 'Not Applicable') {
        double vat_perc = vatperc / 100;
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
        String formattedVat = formatter.format(roundedtotalVatAmount);
        controller_vatamt.text = formattedVat.toString();
      }

      totalAmount = totalPriceOfItems + totalAmountOfLedgers + totalVatAmount;
      roundedtotalAmount = double.parse(totalAmount.toStringAsFixed(decimal!));
      NumberFormat formatter = NumberFormat('#,##0.${'0' * decimal!}', 'en_US');
      String formattedtotal = formatter.format(roundedtotalAmount);
      controller_totalamt.text = formattedtotal.toString();
      if (ledgerEntries.isEmpty) {
        isVisibleLedgerHeading = false;
      } else {
        isVisibleLedgerHeading = true;
      }
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
                style: GoogleFonts.poppins(
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
                style: GoogleFonts.poppins(
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

      totalAmountForVatAppEntries = ledgerEntries
          .where((entry) => entry.vatApp)
          .fold(0.0, (double previousAmount, LedgerEntry entry) {
            return previousAmount + entry.ledgerAmount;
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

      totalAmountOfLedgers = ledgerEntries.fold(0.0, (
        double previousAmount,
        LedgerEntry entry,
      ) {
        return previousAmount + entry.ledgerAmount;
      });
      totalAmount = totalPriceOfItems + totalAmountOfLedgers + totalVatAmount;
      roundedtotalAmount = double.parse(totalAmount.toStringAsFixed(decimal!));
      NumberFormat formatter = NumberFormat('#,##0.${'0' * decimal!}', 'en_US');
      String formattedtotal = formatter.format(roundedtotalAmount);
      controller_totalamt.text = formattedtotal.toString();
      if (saleItems.isEmpty) {
        isVisibleItemHeading = false;
      } else {
        isVisibleItemHeading = true;
      }
    });
  }

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

  Future<void> fetchvchnos(String vchname) async {
    // Format the dates as yyyyMMdd
    String formattedStartDateVchNo = DateFormat(
      'yyyyMMdd',
    ).format(yearStartDate);
    String formattedEndDateVchNo = DateFormat('yyyyMMdd').format(yearEndDate);

    vchnos.clear();
    setState(() {
      _isLoading = true;
    });

    // vchnos fetching
    try {
      final url = Uri.parse(HttpURL_fetchvchnos!);
      Map<String, String> headers = {
        'Authorization': 'Bearer $token',
        "Content-Type": "application/json",
      };

      Map<String, dynamic> jsonDatabody = {
        "to": formattedEndDateVchNo,
        "from": formattedStartDateVchNo,
        "vchname": vchname,
      };

      String jsonDatabodyString = jsonEncode(jsonDatabody);

      var body = jsonDatabodyString;
      final response = await http.post(url, headers: headers, body: body);

      if (response.statusCode == 200) {
        /*print(response.body);*/
        setState(() {
          final Map<String, dynamic> jsonResponse = json.decode(response.body);

          final List<dynamic> vchnosJson = jsonResponse['vchnos'];
          vchnos = vchnosJson.cast<String>();
          int q = vchnos.length;
          print('vchno list containes $q nos whos values are $vchnos');

          if (isVchEditable) {
            checkVchNoExistence(_vchnoController.text);
          }
        });
      } else {
        vchnos.clear();
        Map<String, dynamic> data = json.decode(response.body);
        String error = '';
        if (data.containsKey('error')) {
          setState(() {
            error = data['error'];
          });
        } else {
          error = 'Something went wrong!!!';
        }
        showAppMessage(context, error);
      }
    } catch (e) {
      vchnos.clear();
      print(e);
    }

    setState(() {
      _isLoading = false;
    });
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

  double ledgerVatAmount = 0,
      itemsVatAmount = 0,
      totalVatAmount = 0,
      totalAmount = 0;

  late ProgressDialog progressDialog;

  double totalPriceOfItems = 0,
      totalAmountForVatAppEntries = 0,
      totalAmountOfLedgers = 0;

  final FocusNode _textFieldFocusNodeNarration = FocusNode();

  Map<String, dynamic> jsonEntryData = {
    "DATE": "",
    "VOUCHERTYPENAME": "",
    "PARTYLEDGERNAME": "",
    "NARRATION": "",
    "VOUCHERNUMBER": "",
    "REFERENCE": "",
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

  String token = '';

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

  late final TextEditingController controller_vchno = TextEditingController();

  late final TextEditingController controller_narration =
      TextEditingController();
  late final TextEditingController controller_vatamt = TextEditingController();
  late final TextEditingController controller_totalamt =
      TextEditingController();
  late final TextEditingController controller_orderno = TextEditingController();

  bool _isFocused_vchno = false,
      _isFocused_item = false,
      _isFocused_unit = false,
      _isFocused_ledger = false,
      _isFocused_narration = false,
      _isFocused_vatamt = false,
      _isFocused_totalno = false,
      _isFocused_totalamt = false,
      _isFocused_orderno = false;

  String? hostname = "",
      company = "",
      company_lowercase = "",
      serial_no = "",
      username = "",
      HttpURL = "",
      SecuritybtnAcessHolder = "";

  late DateTime saledate;
  String? HttpURL_loadData, HttpURL_modifysalesEntry, HttpURL_fetchvchnos;

  double selectedMultiplier = 0.0;

  final DateFormat _dateFormat = DateFormat('yyyyMMdd');

  List<SaleItem> saleItems = [];
  List<LedgerEntry> ledgerEntries = [];

  final TextEditingController itemQuantityController = TextEditingController();
  final TextEditingController itemRateController = TextEditingController();
  final TextEditingController itemAmountController = TextEditingController();
  final TextEditingController ledgerAmountController = TextEditingController();

  String currencycode = '';

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

  String formatAmountInvoice(String amount) {
    int? decimal = prefs?.getInt('decimalplace') ?? 2;

    String amount_string = "";
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
    if (isUniGasSerial(serial_no)) {
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
                                if (isUniGasSerial(serial_no) &&
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

    // This is a Modify screen, not a new-entry screen - after sharing the
    // updated order there's nothing left to edit here, so go to the view
    // screen (matching "No, Thanks") instead of resetting fields in place.
    // The in-place reset used to leave the Party Ledger TypeAheadField
    // focused while its controller was cleared/updated, which reopened its
    // suggestions dropdown right after save/share.
    if (context.mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => PendingSalesOrderEntry()),
      );
    }
  }

  String getCurrencySymbol(String currencyCode) {
    NumberFormat format;
    Locale locale = Localizations.localeOf(context);

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

  Future<void> updateEntry(int id) async {
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

      String narrationValue = controller_narration.text;
      String ordernoValue = controller_orderno.text;
      String vchnoValue = _vchnoController.text;

      jsonEntryData["DATE"] = saledatestring;
      jsonEntryData["VOUCHERTYPENAME"] = _selectedvchtypename;
      jsonEntryData["PARTYLEDGERNAME"] = _selectedpartyledger;
      jsonEntryData["totalAmount"] = roundedtotalAmount;
      jsonEntryData["NARRATION"] = narrationValue;
      jsonEntryData["VOUCHERNUMBER"] = vchnoValue;
      jsonEntryData["REFERENCE"] = ordernoValue;

      double totalItemAmount = 0.0;

      for (SaleItem item in saleItems) {
        totalItemAmount += item.itemAmount; // calculating item amounts total
      }

      for (var saleItem in saleItems) {
        // making sales ledger

        saleItem.accountingAllocationList = {
          "LEDGERNAME": _selectedsalesledger,
          "AMOUNT": saleItem.itemAmount.toStringAsFixed(decimal!),
          "ISDEEMEDPOSITIVE": "No",
        };
      }

      jsonEntryData["INVENTORYENTRIES.LIST"] = saleItems.map((item) {
        // making stockitem list
        return {
          "STOCKITEMNAME": item.itemName,
          "ISDEEMEDPOSITIVE": "No",
          "RATE": "${item.itemPrice}/${item.itemUnit}",
          "AMOUNT": item.itemAmount,
          "ACTUALQTY": "${item.itemQuantity} ${item.itemUnit}",
          "BILLEDQTY": "${item.itemQuantity} ${item.itemUnit}",
          "BATCHALLOCATIONS.LIST": item.batchAllocationList,
          "ACCOUNTINGALLOCATIONS.LIST": item.accountingAllocationList,
        };
      }).toList();

      double totalLedgerAmount = 0.0;

      for (LedgerEntry ledger in ledgerEntries) {
        // calculating total ledger amount
        totalLedgerAmount +=
            ledger.ledgerAmount; // calculating ledger amounts total
      }

      double partyLedgerAmount =
          totalVatAmount + totalItemAmount + totalLedgerAmount ??
          0.0; // adding vat total, items total, ledgers total

      partyLedgerAmount = partyLedgerAmount * -1;

      List<Map<String, Object>> ledgerList = [];

      Map<String, Object> partyLedgerData = {
        // making party ledger
        "LEDGERNAME": _selectedpartyledger,
        "AMOUNT": partyLedgerAmount.toStringAsFixed(decimal!),
        "ISPARTYLEDGER": "Yes",
        "ISDEEMEDPOSITIVE": "Yes",
        "ledgerType": "Party",
      };

      ledgerList.add(partyLedgerData);

      // Add ledger entries to the list
      ledgerList.addAll(
        ledgerEntries.map((item) {
          return {
            "LEDGERNAME": item.ledgerName,
            "VATAPPLICABLE": item.vatApp,
            "AMOUNT": item.ledgerAmount,
            "ISDEEMEDPOSITIVE": "No",
            "ledgerType": "ledgerList",
          };
        }),
      );

      // Add VAT ledger data if applicable
      if (_selectedvatledger != 'Not Applicable') {
        Map<String, Object> vatDataToAdd = {
          "LEDGERNAME": _selectedvatledger,
          "AMOUNT": roundedtotalVatAmount,
          "ISDEEMEDPOSITIVE": "No",
          "ledgerType": "VAT",
        };
        ledgerList.add(vatDataToAdd);
      }

      jsonEntryData["LEDGERENTRIES.LIST"] = ledgerList;

      Map<String, dynamic> jsonData = {
        'id': id,
        'vchno': _vchnoController.text,
        'data': jsonEntryData,
      };

      String jsonDataString = jsonEncode(jsonData);

      print(jsonDataString);

      try {
        final url_salesentry = Uri.parse(HttpURL_modifysalesEntry!);

        Map<String, String> headers_salesentry = {
          'Authorization': 'Bearer $token',
          "Content-Type": "application/json",
        };

        var body_salesentry = jsonDataString;

        final response_salesentry = await http.post(
          url_salesentry,
          body: body_salesentry,
          headers: headers_salesentry,
        );

        if (response_salesentry.statusCode == 200) {
          if (response_salesentry.body == 'Entry updated successfully') {
            setState(() {
              _isLoading = false;
            });
            showSalesOrderDialog(context);
          } else {
            setState(() {
              _isLoading = false;
            });

            showAppMessage(context, 'an error occoured');
          }
        } else {
          showAppMessage(context, response_salesentry.body);
        }
      } catch (e) {
        setState(() {
          _isLoading = false;
        });
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
                    'Sales Order Updated Successfully',
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
                          Navigator.pop(context);
                          // This is a Modify screen - go to the view screen
                          // instead of resetting fields in place.
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (context) => PendingSalesOrderEntry(),
                            ),
                          );
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
                        ),
                      ),

                      ElevatedButton.icon(
                        onPressed: () async {
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

                            _selectedvchtypename = vchtypenamedata[0];
                            fetchvchnos(_selectedvchtypename);
                            _selectedpartyledger = partyledgerdata[0];
                            _partyLedgerController.text = _selectedpartyledger;

                            _selectedsalesledger = salesledger_data[0];
                            _selectedledger = ledgerdata.isNotEmpty ? ledgerdata[0]['name'] : null;
                            _selectedvatledger = vatledgerdata[0];

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

                            totalPriceOfItems = saleItems.fold(
                              0.0,
                                  (double previousAmount, SaleItem item) {
                                return previousAmount +
                                    (item.itemPrice * double.parse(item.itemQuantity));
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

                            roundedtotalVatAmount =
                                double.parse(totalVatAmount.toStringAsFixed(decimal!));

                            NumberFormat formatter = NumberFormat(
                                '#,##0.${'0' * decimal!}', 'en_US');

                            controller_vatamt.text =
                                formatter.format(roundedtotalVatAmount);

                            isVisibleItemHeading = saleItems.isNotEmpty;

                            totalAmountForVatAppEntries =
                                ledgerEntries.where((entry) => entry.vatApp).fold(
                                  0.0,
                                      (double previousAmount, LedgerEntry entry) {
                                    return previousAmount + entry.ledgerAmount;
                                  },
                                );

                            if (_selectedvatledger != 'Not Applicable') {
                              double vat_perc = vatperc / 100;
                              ledgerVatAmount =
                                  totalAmountForVatAppEntries * vat_perc;
                              totalVatAmount = itemsVatAmount + ledgerVatAmount;
                            } else {
                              totalVatAmount = 0;
                            }

                            roundedtotalVatAmount =
                                double.parse(totalVatAmount.toStringAsFixed(decimal!));
                            controller_vatamt.text =
                                formatter.format(roundedtotalVatAmount);

                            isVisibleLedgerHeading = ledgerEntries.isNotEmpty;

                            totalAmount = totalPriceOfItems +
                                totalAmountOfLedgers +
                                totalVatAmount;

                            roundedtotalAmount =
                                double.parse(totalAmount.toStringAsFixed(decimal!));
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

  /*Future<void> saveEntry(int id) async {

    if (saleItems.isEmpty) {
      showAppMessage(context, 'Atleast add 1 item');
    }
    else
    {
      setState(() {
        _isLoading_saveData = true;
        showProgressDialog_SaveData(context, _isLoading_saveData);

        String narrationValue = controller_narration.text;

        jsonEntryData["date"] = saledatestring;
        jsonEntryData["vchname"] = _selectedvchtypename;
        jsonEntryData["partyledger"] = _selectedpartyledger;
        jsonEntryData["totalAmount"] = roundedtotalAmount;
        jsonEntryData["salesledger"] = _selectedsalesledger;
        jsonEntryData["narration"] = narrationValue;
        jsonEntryData["items"] = saleItems.map((item) {
          return {
            "name": item.itemName,
            "rate": "${item.itemPrice}/${item.itemUnit}",
            "qty": item.itemQuantity,
            "location": item.itemLocation,
            "amount": item.itemAmount,
          };
        }).toList();


        jsonEntryData["ledgers"] = ledgerEntries.map((
            item) { // setting ledger entries data in ledger list in json
          return {
            "name": item.ledgerName,
            "vatApplicable": item.vatApp,
            "amount": item.ledgerAmount,
            "isDeemedPositive": item.isDeemedPositive,
            "ledgerType": "ledgerList",

          };
        }).toList();

        if (_selectedvatledger != 'Not Applicable') {
          Map<String, Object> vatDataToAdd = {
            "name": _selectedvatledger,
            "amount": roundedtotalVatAmount,
            "isDeemedPositive": false,
            "ledgerType": "VAT",

          };
          jsonEntryData["ledgers"].add(
              vatDataToAdd); // setting vat ledger data in ledger list
        }

        double totalItemAmount = 0.0;
        double totalLedgerAmount = 0.0;

        for (SaleItem item in saleItems) {
          totalItemAmount += item.itemAmount; // calculating item amounts total
        }

        for (LedgerEntry ledger in ledgerEntries) {
          totalLedgerAmount +=
              ledger.ledgerAmount; // calculating ledger amounts total
        }

        Map<String, Object> salesLedgerData = {
          "name": _selectedsalesledger,
          "amount": totalItemAmount.toStringAsFixed(decimal!),
          // all items added total amount
          "isDeemedPositive": false,
          "ledgerType": "Sales",

        };

        double partyLedgerAmount = totalVatAmount + totalItemAmount +
            totalLedgerAmount ??
            0.0; // adding vat total, items total, ledgers total

        Map<String, Object> partyLedgerData = {
          "name": _selectedpartyledger,
          "amount": partyLedgerAmount.toStringAsFixed(decimal!),
          "isDeemedPositive": true,
          "ledgerType": "Party",
        };

        jsonEntryData["ledgers"].add(salesLedgerData);

        jsonEntryData["ledgers"].add(partyLedgerData);
      });
      */ /*print("entry data: ${jsonEntryData}");*/ /*

      Map<String, dynamic> jsonData = {
        'id' : id,
        'data' : jsonEntryData

      };

      String jsonDataString = jsonEncode(jsonData);

      try {
        final url_salesentry = Uri.parse(HttpURL_modifysalesEntry!);
        final response_salesentry = await http.post(
            url_salesentry,
            headers: {
              'Content-Type': 'application/json', // Set the Content-Type header to indicate JSON data
            },
            body: jsonDataString

        );

        if (response_salesentry.statusCode == 200) {

          */ /*print(response_salesentry.body);*/ /*
          if(response_salesentry.body == 'Entry updated successfully')
            {
              setState(() {
                _isLoading_saveData = false;
                showProgressDialog_SaveData(context, _isLoading_saveData);

              });
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => PendingSalesEntry()),
              );
            }

          else
          {
            setState(() {
              _isLoading_saveData = false;
              showProgressDialog_SaveData(context, _isLoading_saveData);

            });
            showAppMessage(context, 'an error occoured');
          }
        }
        else
        {
          showAppMessage(context, response_salesentry.body);

        }
      }
      catch (e) {
        setState(() {
          _isLoading_saveData = false;
          showProgressDialog_SaveData(context, _isLoading_saveData);

        });
        print(e);
      }
    }
  }*/

  String extractQuantity(String inputString) {
    RegExp quantityRegex = RegExp(r'(\d+)'); // Match one or more digits

    Match? match = quantityRegex.firstMatch(inputString);

    if (match != null) {
      String quantityString = match.group(0)!;
      return quantityString;
    } else {
      // Handle the case where no quantity is found in the string
      return '0'; // You can return any default value or handle it as needed
    }
  }

  Future<void> loadData() async {
    vchtypenamedata.clear();
    itemdata.clear();
    salesledger_data.clear();
    partyledgerdata.clear();
    vatledgerdata.clear();
    saleItems.clear();
    ledgerEntries.clear();

    ledgerdata.clear();
    locationsdata.clear();

    setState(() {
      _isLoading = true;
    });

    // vchtype fetching
    try {
      final url = Uri.parse(HttpURL_loadData!);

      Map<String, String> headers = {
        'Authorization': 'Bearer $token',
        "Content-Type": "application/json",
      };
      var body = jsonEncode({'type': "sales order"});
      final response = await http.post(url, body: body, headers: headers);

      if (response.statusCode == 200) {
        final Map<String, dynamic> jsonResponse = json.decode(response.body);

        /*print('existing data = $data');*/

        setState(() {
          // setting current sales entry data

          String oldvchname = data['VOUCHERTYPENAME'];
          String oldpartyledger = data['PARTYLEDGERNAME'];
          String oldvchno = data['VOUCHERNUMBER'];

          _vchnoController.text = oldvchno;

          /* String oldsalesledger = data['salesledger'];*/
          String oldnarration = data['NARRATION'];
          String oldrefno = data['REFERENCE'];

          saledate = DateTime.parse(data['DATE']);
          saledatestring = _dateFormat.format(saledate);
          saledatetxt = formatlastsaledate(saledatestring);
          _dateController.text = saledatetxt;

          controller_narration.text = oldnarration;
          controller_orderno.text = oldrefno;

          vchtypenamedata = jsonResponse["vchTypes"].cast<String>();
          _selectedvchtypename = oldvchname;
          fetchvchnos(_selectedvchtypename);
          partyledgerdata = jsonResponse["partyLedgers"].cast<String>();
          _selectedpartyledger = oldpartyledger;
          _partyLedgerController.text = _selectedpartyledger;
          salesledger_data = jsonResponse["salesLedgers"].cast<String>();

          /*_selectedsalesledger = oldsalesledger;*/ // setting sales ledgers later
          /* _selectedsalesledger = salesledger_data[0];*/

          if (data.containsKey("INVENTORYENTRIES.LIST") &&
              data["INVENTORYENTRIES.LIST"] is List) {
            // setting items list in SaleItem objects

            dynamic itemData = data['INVENTORYENTRIES.LIST'][0];
            if (itemData is Map<String, dynamic>) {
              Map<String, dynamic> accountingAllocationList =
                  itemData["ACCOUNTINGALLOCATIONS.LIST"];
              String saleLedgerName = accountingAllocationList['LEDGERNAME'];
              _selectedsalesledger =
                  saleLedgerName; // setting sales ledger from first item data
            }
          }

          ledgerdata = List<Map<String, dynamic>>.from(
            jsonResponse['otherLedgers'],
          );
          _selectedledger = ledgerdata.isNotEmpty
              ? ledgerdata[0]['name']
              : null;

          vatledgerdata.add('Not Applicable');
          vatledgerdata.addAll(jsonResponse["vatLedgers"].cast<String>());

          _selectedvatledger = vatledgerdata[0];

          try {
            // vat ledger name value setting
            String vatLedgerValue =
                data['LEDGERENTRIES.LIST']
                        .firstWhere(
                          (ledger) => ledger['ledgerType'] == 'VAT',
                          orElse: () => null,
                        )
                        ?.containsKey('LEDGERNAME') ==
                    true
                ? data['LEDGERENTRIES.LIST'].firstWhere(
                    (ledger) => ledger['ledgerType'] == 'VAT',
                    orElse: () => null,
                  )['LEDGERNAME']
                : null;

            if (vatLedgerValue != null &&
                vatledgerdata.contains(vatLedgerValue)) {
              // if vat ledger exists
              _selectedvatledger = vatLedgerValue;
              // Extract VAT ledger amount as a string

              double vatLedgerAmountString = 0.0;
              try {
                // setting vat ledger amount if it is in double
                vatLedgerAmountString =
                    data['LEDGERENTRIES.LIST']
                            .firstWhere(
                              (ledger) => ledger['ledgerType'] == 'VAT',
                              orElse: () => null,
                            )
                            ?.containsKey('AMOUNT') ==
                        true
                    ? data['LEDGERENTRIES.LIST'].firstWhere(
                        (ledger) => ledger['ledgerType'] == 'VAT',
                        orElse: () => null,
                      )['AMOUNT']
                    : null;
              } catch (e) {
                // setting vat ledger amount if it is in integer

                int vatLedgerAmountint =
                    data['LEDGERENTRIES.LIST']
                            .firstWhere(
                              (ledger) => ledger['ledgerType'] == 'VAT',
                              orElse: () => null,
                            )
                            ?.containsKey('AMOUNT') ==
                        true
                    ? data['LEDGERENTRIES.LIST'].firstWhere(
                        (ledger) => ledger['ledgerType'] == 'VAT',
                        orElse: () => null,
                      )['AMOUNT']
                    : null;
                NumberFormat formatter =
                    NumberFormat.decimalPattern(); // Create a formatter
                formatter.minimumFractionDigits =
                    decimal!; // Set the number of decimal places

                String formattedValue = formatter.format(
                  vatLedgerAmountint,
                ); // Format the integer
                formattedValue = formattedValue.replaceAll(
                  ',',
                  '',
                ); // Remove commas

                vatLedgerAmountString =
                    double.tryParse(formattedValue.replaceAll(',', '')) ?? 0.0;
              }

              // if vat ledger is other than not applicable
              if (_selectedvatledger != 'Not Applicable') {
                try {
                  // set total vat amount from vat ledger if it is in double
                  totalVatAmount = vatLedgerAmountString;
                } catch (e) {
                  // set total vat amount from vat ledger if it is in integer

                  print(e);
                  NumberFormat formatter =
                      NumberFormat.decimalPattern(); // Create a formatter
                  formatter.minimumFractionDigits =
                      decimal!; // Set the number of decimal places

                  String formattedValue = formatter.format(
                    vatLedgerAmountString,
                  ); // Format the integer
                  formattedValue = formattedValue.replaceAll(
                    ',',
                    '',
                  ); // Remove commas

                  totalVatAmount =
                      double.tryParse(formattedValue.replaceAll(',', '')) ??
                      0.0;
                  /*print(totalVatAmount);*/
                }

                roundedtotalVatAmount = double.parse(
                  totalVatAmount.toStringAsFixed(decimal!),
                );

                NumberFormat formatter = NumberFormat(
                  '#,##0.${'0' * decimal!}',
                  'en_US',
                );
                String formattedVat = formatter.format(roundedtotalVatAmount);
                controller_vatamt.text = formattedVat.toString();
              } else // if vat ledger is not applicable
              {
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
            }
          } catch (e) // if vat ledger has error
          {
            print(e);
            _selectedvatledger = vatledgerdata[0];

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
          try {
            totalAmount =
                double.tryParse(
                  data['totalAmount'].toString().replaceAll(',', ''),
                ) ??
                0.0;
          } catch (e) {
            NumberFormat formatter =
                NumberFormat.decimalPattern(); // Create a formatter
            formatter.minimumFractionDigits =
                decimal!; // Set the number of decimal places

            String formattedValue = formatter.format(
              data['totalAmount'],
            ); // Format the integer
            formattedValue = formattedValue.replaceAll(
              ',',
              '',
            ); // Remove commas

            totalAmount =
                double.tryParse(formattedValue.replaceAll(',', '')) ?? 0.0;
          }
          roundedtotalAmount = double.parse(
            totalAmount.toStringAsFixed(decimal!),
          );
          NumberFormat formatter = NumberFormat(
            '#,##0.${'0' * decimal!}',
            'en_US',
          );
          String formattedtotal = formatter.format(roundedtotalAmount);

          controller_totalamt.text = formattedtotal.toString();

          if (data.containsKey("INVENTORYENTRIES.LIST") &&
              data["INVENTORYENTRIES.LIST"] is List) {
            // setting items list in SaleItem objects

            data["INVENTORYENTRIES.LIST"].forEach((itemData) {
              if (itemData is Map<String, dynamic>) {
                String itemName = itemData["STOCKITEMNAME"] ?? "";

                String itemQuantity = itemData["ACTUALQTY"] ?? "";

                String quantity = extractQuantity(itemQuantity);

                String parsedQuantity = quantity.replaceAll(',', '');

                String rate = itemData["RATE"] ?? "";
                List<String> rateParts = rate.split('/');
                if (rateParts.length == 2) {
                  double itemPrice = 0.0;
                  if (rateParts[0].contains('.')) {
                    try {
                      itemPrice = double.tryParse(rateParts[0]) ?? 0.0;
                    } catch (e) {
                      itemPrice = int.parse(rateParts[0]).toDouble();
                      print("Error parsing itemPrice as double: $e");
                    }
                  } else {
                    try {
                      itemPrice = int.parse(rateParts[0]).toDouble();
                    } catch (e) {
                      print("Error parsing itemPrice as int: $e");
                    }
                  }

                  String itemUnit = rateParts[1];

                  // Try parsing itemAmount as a double, and if that fails, as an integer
                  double itemAmount;
                  try {
                    itemAmount = double.parse(itemData["AMOUNT"].toString());
                  } catch (e) {
                    try {
                      itemAmount = int.parse(
                        itemData["AMOUNT"].toString(),
                      ).toDouble();
                      print("Error parsing itemAmount as double: $e");
                    } catch (e) {
                      print("Error parsing itemAmount as int: $e");
                      itemAmount = 0.0; // Default to 0.0 if parsing fails
                    }
                  }
                  Map<String, dynamic> batchAllocationList =
                      itemData['BATCHALLOCATIONS.LIST'];

                  String itemLocation = batchAllocationList["GODOWNNAME"] ?? "";

                  Map<String, dynamic> accountingAllocationList =
                      itemData['ACCOUNTINGALLOCATIONS.LIST'];

                  SaleItem saleItem = SaleItem(
                    itemName: itemName,
                    itemQuantity: parsedQuantity,
                    itemPrice: itemPrice,
                    itemAmount: itemAmount,
                    itemLocation: itemLocation,
                    itemUnit: itemUnit,
                    accountingAllocationList: accountingAllocationList,
                    batchAllocationList: batchAllocationList,
                  );

                  saleItems.add(saleItem);
                }
              }
            });
          }

          if (saleItems.isEmpty) {
            isVisibleItemHeading = false;
          } else {
            isVisibleItemHeading = true;
          }

          // Extract and convert ledger entries from the JSON data
          if (data.containsKey("LEDGERENTRIES.LIST") &&
              data["LEDGERENTRIES.LIST"] is List) {
            data["LEDGERENTRIES.LIST"].forEach((ledgerData) {
              if (ledgerData is Map<String, dynamic> &&
                  ledgerData["ledgerType"] == "ledgerList") {
                String ledgerName = ledgerData["LEDGERNAME"] ?? "";

                // Try parsing ledgerAmount as a double, or default to 0.0
                double ledgerAmount =
                    double.tryParse(ledgerData["AMOUNT"].toString()) ?? 0.0;

                bool vatApp = ledgerData["VATAPPLICABLE"];

                LedgerEntry ledgerEntry = LedgerEntry(
                  ledgerName: ledgerName,
                  ledgerAmount: ledgerAmount,
                  vatApp: vatApp,
                );

                ledgerEntries.add(ledgerEntry);
              }
            });
          }
          if (ledgerEntries.isEmpty) {
            isVisibleLedgerHeading = false;
          } else {
            isVisibleLedgerHeading = true;
          }

          itemdata = jsonResponse["items"];

          _selecteditem = '${itemdata[0]['name']}';
          _itemController.text = _selecteditem;
          locationsdata = List<String>.from(jsonResponse['locations']);
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
        });
      }
    } catch (e) {
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
        _selectedunit = unitdata[0].name;

        selectedMultiplier = unitdata[0].multiplier ?? 0.0;
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
    final start = double.tryParse(startText.trim());
    final end = double.tryParse(endText.trim());
    return start != null && end != null && end > start;
  }

  void _syncQtyWithMeterReading({
    required TextEditingController startController,
    required TextEditingController endController,
    required TextEditingController qtyController,
  }) {
    final startText = startController.text.trim();
    final endText = endController.text.trim();
    final start = double.tryParse(startText);
    final end = double.tryParse(endText);

    if (start != null && end != null && end > start) {
      final qty = end - start;
      qtyController.text = qty == qty.roundToDouble()
          ? qty.toInt().toString()
          : qty.toString();
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
    if (isUniGasSerial(serial_no)) {
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
                    // ✅ The new API uses `builder` instead of `textFieldConfiguration`
                    builder: (context, controller, focusNode) {
                      return TextField(
                        controller: _itemController,
                        focusNode: focusNode,
                        decoration: InputDecoration(
                          labelText: "Item",
                          hintText: "Search item",
                          prefixIcon: Container(
                            margin: const EdgeInsets.all(8),
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Colors.blue, Colors.blue],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.all(Radius.circular(8)),
                            ),
                            child: const Icon(Icons.inventory_outlined, color: Colors.white),
                          ),
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
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
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                        ),
                      );
                    },

                    // ✅ `suggestionsCallback` must return Future<List<T>> or List<T>
                    suggestionsCallback: (pattern) async {
                      return itemdata
                          .where((item) {
                        final name = (item['name'] ?? '').toString().toLowerCase();
                        final part = (item['part'] ?? '').toString().toLowerCase();
                        return name.contains(pattern.toLowerCase()) ||
                            part.contains(pattern.toLowerCase());
                      })
                          .cast<Map<String, dynamic>>()
                          .toList();
                    },

                    // ✅ Suggestion item widget
                    itemBuilder: (context, Map<String, dynamic> suggestion) {
                      return ListTile(
                        title: Text(suggestion['name'] ?? ''),
                        subtitle: suggestion['part'] != null && suggestion['part'].toString().isNotEmpty
                            ? Text(suggestion['part'].toString())
                            : null,
                      );
                    },

                    // ✅ Required parameter
                    onSelected: (Map<String, dynamic> suggestion) {
                      setState(() {
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

                    // ✅ Empty state
                    emptyBuilder: (context) => Padding(
                      padding: EdgeInsets.all(8),
                      child: Text("No items found", style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    ),
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
                        child: Text(
                          getCurrencySymbol(currencycode),
                          style: GoogleFonts.poppins(
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
                        child: Text(
                          getCurrencySymbol(currencycode),
                          style: GoogleFonts.poppins(
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
      },
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
                                      child: Text(
                                        getCurrencySymbol(currencycode),
                                        style: GoogleFonts.poppins(
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
                                      child: Text(
                                        getCurrencySymbol(currencycode),
                                        style: GoogleFonts.poppins(
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
                            child: Text(
                              getCurrencySymbol(currencycode),
                              style: GoogleFonts.poppins(
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
                                        child: Text(
                                          getCurrencySymbol(currencycode),
                                          style: GoogleFonts.poppins(
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
      final int next = (current + delta) < 1 ? 1 : current + delta;
      setStateDialog(() {
        controller.text = next.toString();
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
            final List<dynamic> filteredItems = searchQuery.isEmpty
                ? itemdata
                : itemdata
                      .where(
                        (i) => (i['name']?.toString() ?? '')
                            .toLowerCase()
                            .contains(searchQuery.toLowerCase()),
                      )
                      .toList();

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
                                      if (isUniGasSerial(serial_no)) {
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
                                                              !(isUniGasSerial(
                                                                    serial_no,
                                                                  ) &&
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
                                                              prefixText:
                                                                  '${getCurrencySymbol(currencycode)} ',
                                                              prefixStyle: GoogleFonts.poppins(
                                                                fontSize: 14,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                                color: Theme.of(
                                                                  context,
                                                                ).colorScheme.onSurface,
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
                                                    if (isUniGasSerial(
                                                      serial_no,
                                                    )) ...[
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
                                                        if (isUniGasSerial(
                                                          serial_no,
                                                        ))
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
                                                                  Text(
                                                                    '${getCurrencySymbol(currencycode)} ${currencyFormatter.format(amount)}',
                                                                    style: GoogleFonts.poppins(
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
      final String meterFrom = isUniGasSerial(serial_no)
          ? (startReadingControllers[name]?.text.trim() ?? '')
          : '';
      final String meterTo = isUniGasSerial(serial_no)
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
        final String newQty = (int.parse(existing.itemQuantity) + parsedQty)
            .toString();
        saleItems[existingIndex] = existing
            .updateQuantity(newQty)
            .updateItemAmount(resolvedRate * int.parse(newQty));
      } else {
        saleItems.add(
          SaleItem(
            itemName: name,
            itemQuantity: qty,
            itemPrice: resolvedRate,
            itemAmount: amount,
            itemLocation: selectedLocation,
            itemUnit: unitName,
            accountingAllocationList: {},
            batchAllocationList: {
              'GODOWNNAME': selectedLocation,
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
        String newQuantity =
            (int.parse(existingItem.itemQuantity) + int.parse(parsedQuantity))
                .toString();
        double newAmount = parsedPrice * int.parse(newQuantity);
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
          double vat_perc = vatperc / 100;
          itemsVatAmount = double.parse(
            (totalPriceOfItems * vat_perc).toStringAsFixed(decimal!),
          );
          totalAmountForVatAppEntries = ledgerEntries
              .where((entry) => entry.vatApp)
              .fold(0.0, (double previousAmount, LedgerEntry entry) {
                return previousAmount + entry.ledgerAmount;
              });

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
      token = prefs.getString('token')!;
      currencycode = prefs.getString('currencycode') ?? 'AED';

      vatperc = prefs.getDouble('vatperc') ?? 5.0;

      decimal = prefs?.getInt('decimalplace') ?? 2;

      saledate = DateTime.parse(data['DATE']);
      saledatestring = _dateFormat.format(saledate);
      saledatetxt = formatlastsaledate(saledatestring);
      _dateController.text = saledatetxt;

      SecuritybtnAcessHolder = prefs.getString('secbtnaccess');

      String? email_nav = prefs.getString('email_nav');
      String? name_nav = prefs.getString('name_nav');

      HttpURL_loadData =
          '$hostname/api/entry/getSalesData/$company_lowercase/$serial_no';
      /*HttpURL_loadData = 'http://192.168.2.110:4999/api/entry/getSalesData/$company_lowercase/$serial_no';*/

      HttpURL_fetchvchnos =
          '$hostname/api/entry/nos/$company_lowercase/$serial_no';
      /*HttpURL_fetchvchnos = 'http://192.168.2.110:4999/api/entry/nos/$company_lowercase/$serial_no';*/

      HttpURL_modifysalesEntry =
          '$hostname/api/entry/updateEntry/$company_lowercase/$serial_no';
      /*HttpURL_salesEntry = 'http://192.168.2.110:4999/api/entry/create/demonewformobilepp/767060064';*/

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
          title: "Modify Sales Order Entry",
          onBack: () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => PendingSalesOrderEntry()),
            );
          },
        ),
        body: Center(child: AppLogoLoader()),
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
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      key: _scaffoldKey,
      appBar: entryAppBar(
        context: context,
        title: "Modify Sales Order Entry",
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
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 12,
                              ),
                              child: TextFormField(
                                controller: _dateController,
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface,
                                ),
                                decoration: InputDecoration(
                                  labelText: "Date",
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
                                    onTap: isUniGasSerial(serial_no)
                                        ? null
                                        : () => _selectsaleDate(context),
                                    child: Container(
                                      margin: const EdgeInsets.all(8),
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
                                        Icons.calendar_today,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                  suffixIcon: isUniGasSerial(serial_no)
                                      ? Icon(
                                          Icons.lock,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        )
                                      : null,
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
                                readOnly: true,
                                enableInteractiveSelection: false,
                                onTap: isUniGasSerial(serial_no)
                                    ? null
                                    : () {
                                        _selectsaleDate(context);
                                      },
                              ),
                            ),

                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
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
                                    margin: const EdgeInsets.all(8),
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
                                      Icons.lock_outline,
                                      color: app_color,
                                    ),
                                    onPressed: () {},
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
                                left: 20,
                                right: 20,
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
                                left: 20,
                                right: 20,
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
                                left: 20,
                                right: 20,
                                bottom: 0,
                              ),
                              child: Container(
                                width: MediaQuery.of(context).size.width,
                                child: TypeAheadField<String>(
                                  // ✅ New builder syntax replaces textFieldConfiguration
                                  builder: (context, controller, focusNode) {
                                    return TextField(
                                      controller: _partyLedgerController,
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
                                          margin: const EdgeInsets.all(8),
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

                                        // ✖️ Clear + ⬇️ Dropdown
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
                                                  setState(() {
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

                                        // Borders
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

                                  // ✅ Suggestions must return FutureOr<List<T>>
                                  suggestionsCallback: (pattern) async {
                                    return partyledgerdata
                                        .where(
                                          (item) => item.toLowerCase().contains(
                                            pattern.toLowerCase(),
                                          ),
                                        )
                                        .toList();
                                  },

                                  // ✅ Suggestion tile
                                  itemBuilder: (context, String suggestion) {
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

                                  // ✅ Required parameter in new API
                                  onSelected: (String suggestion) {
                                    setState(() {
                                      _selectedpartyledger = suggestion;
                                      _partyLedgerController.text =
                                          _selectedpartyledger;
                                    });
                                  },

                                  // ✅ Empty state
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

                            Padding(
                              padding: const EdgeInsets.only(
                                top: 12,
                                left: 20,
                                right: 20,
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
                                  labelText: "Sales Ledger",
                                  labelStyle: GoogleFonts.poppins(
                                    fontSize: 13,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                  // Prefix icon with gradient (blue)
                                  prefixIcon: Container(
                                    margin: const EdgeInsets.all(8),
                                    decoration: const BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          Colors.blueAccent,
                                          Colors.indigo,
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      borderRadius: BorderRadius.all(
                                        Radius.circular(12),
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.sell_outlined,
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
                                  "Sales Ledger",
                                  style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                value: _selectedsalesledger,
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
                                onTap: () {
                                  setState(() {
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
                                      rate:
                                          "${getCurrencySymbol(currencycode)} ${currencyFormat.format(double.parse(item.itemPrice.toStringAsFixed(decimal!)))}",
                                      amount:
                                          "${getCurrencySymbol(currencycode)} ${currencyFormat.format(double.parse(item.itemPrice.toStringAsFixed(decimal!)) * double.parse(item.itemQuantity))}",
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
                                      amount:
                                          "${getCurrencySymbol(currencycode)} ${currencyFormat.format(item.ledgerAmount)}",
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
                                      left: 20,
                                      right: 5,
                                    ),
                                    child: DropdownButtonFormField<String>(
                                      isExpanded: true,
                                      decoration: InputDecoration(
                                        labelText: "VAT Ledger",
                                        labelStyle: GoogleFonts.poppins(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurface,
                                          fontWeight: FontWeight.w500,
                                        ),
                                        // 🌈 Gradient Icon Container
                                        prefixIcon: Container(
                                          margin: const EdgeInsets.all(8),
                                          decoration: const BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: [
                                                Colors.indigo,
                                                Colors.cyan,
                                              ],
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                            ),
                                            borderRadius: BorderRadius.all(
                                              Radius.circular(12),
                                            ),
                                          ),
                                          child: const Icon(
                                            Icons.receipt_long_outlined,
                                            size: 20,
                                            color: Colors.white,
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
                                              vertical: 14,
                                            ),
                                      ),
                                      value: _selectedvatledger,
                                      hint: const Text("Select VAT Ledger"),
                                      items: vatledgerdata.map((item) {
                                        return DropdownMenuItem<String>(
                                          value: item,
                                          child: Text(
                                            item,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        );
                                      }).toList(),
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
                                      right: 20,
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
                                          child: Text(
                                            getCurrencySymbol(currencycode),
                                            style: GoogleFonts.poppins(
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
                      ),

                      EntrySaveButton(
                        label: "Update",
                        icon: Icons.save_as_rounded,
                        onPressed: errorMessageVchNo.isNotEmpty
                            ? null
                            : () {
                                if (_formKey.currentState != null &&
                                    _formKey.currentState!.validate()) {
                                  _formKey.currentState!.save();
                                  updateEntry(id);
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
