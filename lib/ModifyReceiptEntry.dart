import 'dart:convert';
import 'package:FincoreGo/Items.dart';
import 'package:FincoreGo/constants.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:open_file/open_file.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'Dashboard.dart';
import 'PendingReceiptEntry.dart';
import 'SerialSelect.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:FincoreGo/widgets/app_bottom_nav.dart';
import 'widgets/entry_widgets.dart';

class ModifyReceiptEntry extends StatefulWidget {
  final int id, isSynced;
  final String type;
  final Map<String, dynamic> data;
  const ModifyReceiptEntry({
    required this.id,
    required this.isSynced,
    required this.type,
    required this.data,
  });
  @override
  _ModifyReceiptEntryPageState createState() => _ModifyReceiptEntryPageState(
    id: id,
    isSynced: isSynced,
    type: type,
    data: data,
  );
}

class Bills {
  final String billName;
  final double billAmount;
  final String? billNo;
  final String? billDueDate;

  Bills({
    required this.billName,
    required this.billAmount,
    required this.billNo,
    required this.billDueDate,
  });
}

class Cheque {
  final String date;
  final String instno;
  final String? instdate;
  final String? bankname;
  final double chequeAmount;
  final String paymentMode;
  final String paymentFavouring;
  final String bankPartyName;
  Cheque({
    required this.instno,
    required this.instdate,
    required this.bankname,
    required this.chequeAmount,
    required this.paymentMode,
    required this.paymentFavouring,
    required this.bankPartyName,
    required this.date,
  });
}

class _ModifyReceiptEntryPageState extends State<ModifyReceiptEntry>
    with TickerProviderStateMixin {
  bool isDashEnable = true,
      isRolesVisible = true,
      isUserEnable = true,
      isUserVisible = true,
      isRolesEnable = true,
      _isLoading = true,
      isVisibleNoUserFound = false;

  bool _isInitialDataLoaded = false;

  int id, isSynced;
  String type;
  Map<String, dynamic> data;
  _ModifyReceiptEntryPageState({
    required this.id,
    required this.isSynced,
    required this.type,
    required this.data,
  });

  TextEditingController _partyController = TextEditingController();

  TextEditingController _bankcashnameController = TextEditingController();

  TextEditingController billNoController = TextEditingController();

  TextEditingController _banknameController = TextEditingController();

  late final TextEditingController controller_narration =
      TextEditingController();

  final FocusNode _textFieldFocusNodeNarration = FocusNode();

  final TextEditingController _vchnoController = TextEditingController();

  double totalBillAmount = 0;

  double totalChequeAmount = 0;

  String errorMessageVchNo = '';

  List<String> vchnos = [];

  bool isVchEditable = false; // state variable

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
          final Map<String, dynamic> jsonResponse = json.decode(utf8.decode(response.bodyBytes));

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
        Map<String, dynamic> data = json.decode(utf8.decode(response.bodyBytes));
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

  String formatChequeAmount(double amount) {
    String amountstring = '0';

    amount = -amount;

    amountstring = amount.toString();

    return amountstring;
  }

  double _entryAmount(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString().replaceAll(',', '')) ?? 0;
  }

  List<dynamic> _entryList(dynamic value) {
    if (value is List) return value;
    return const [];
  }

  Map<String, dynamic>? _findBillLedgerEntry(List<dynamic> ledgerEntries) {
    for (final entry in ledgerEntries) {
      if (entry is Map<String, dynamic> &&
          _entryList(entry['BILLALLOCATIONS.LIST']).isNotEmpty) {
        return entry;
      }
    }
    return null;
  }

  Map<String, dynamic>? _findBankLedgerEntry(List<dynamic> ledgerEntries) {
    for (final ledger in bankcashname_data) {
      final ledgerName = ledger['name'];
      if (ledgerName == null || ledgerName.trim().isEmpty) continue;

      for (final entry in ledgerEntries) {
        if (entry is Map<String, dynamic> &&
            entry['LEDGERNAME'] == ledgerName) {
          return entry;
        }
      }
    }

    for (final entry in ledgerEntries) {
      if (entry is Map<String, dynamic> &&
          _entryList(entry['BANKALLOCATIONS.LIST']).isNotEmpty) {
        return entry;
      }
    }

    for (final entry in ledgerEntries) {
      if (entry is Map<String, dynamic> &&
          entry['ISPARTYLEDGER'] != 'Yes' &&
          !_entryList(entry['BILLALLOCATIONS.LIST']).isNotEmpty) {
        return entry;
      }
    }

    return null;
  }

  late List<String> vchtypenamedata = [];

  Map<String, dynamic> jsonEntryData = {
    "DATE": "",
    "VOUCHERTYPENAME": "",
    "PARTYLEDGERNAME": "",
    "VOUCHERNUMBER": "",
    "ENTEREDBY": "",
    "NARRATION": "",
    "ALLLEDGERENTRIES.LIST": [],
  };

  bool isVisibleBillHeading = false,
      isVisibleChequeHeading = false,
      isChequeVisible = false;

  final _formKey = GlobalKey<FormState>();

  late String _selectedvchtypename = '';

  String selectedbankname = '';

  bool isInstNoRepeated(String instNo, List<Cheque> cheques) {
    if (instNo.isNotEmpty) {
      for (var cheque in cheques) {
        if (cheque.instno == instNo) {
          return true; // Found a match, instno is repeated
        }
      }
    }
    return false; // No match found
  }

  GlobalKey<FormState> _billsFormkey = GlobalKey<FormState>();

  GlobalKey<FormState> _chequedetailsFormkey = GlobalKey<FormState>();

  double roundedtotalVatAmount = 0.0;

  double roundedtotalBillAmount = 0.0;

  double roundedtotalChequeAmount = 0.0;

  List<Map<String, String>> bankcashname_data = [];

  List<String> paymentmode_data = [];

  bool isPaymentModeVisible = false;

  int decimal = 2;

  late List<String> partydata = [];

  List<String> bankname_data = [
    'Not Applicable',
    "RAK Bank (UAE)",
    "Mashreq Bank (UAE)",
    "National Bank of Abu Dhabi (UAE)",
    "ADCB (UAE)",
    "Arab Bank (UAE)",
    "Commercial Bank of Dubai (UAE)",
    "Emirates NBD (UAE)",
    "Habib Bank AG Zurich (UAE)",
    "National Bank of Fujairah (UAE)",
    "Standard Chartered Bank (UAE)",
    "Bank of Baroda (UAE)",
    "HSBC Bank (UAE)",
    "Union National Bank (UAE)",
    "United Arab Bank (UAE)",
    "Al Ahli Bank of Kuwait (UAE)",
    "Noor Islamic Bank (UAE)",
    "Emirates Bank (UAE)",
    "Emirates Islamic Bank (UAE)",
    "United Bank Ltd. (UAE)",
    "Dubai Islamic Bank (UAE)",
    "ADIB (UAE)",
    "Bank of Sharjah (UAE)",
    "Blom Bank France (UAE)",
    "First Gulf Bank (UAE)",
    "Invest Bank (UAE)",
    "Habib Bank Limited (UAE)",
    "Oman Arab Bank (UAE)",
    "NBAD(UAE)",
    "NCB Bank(UAE)",
    "NBQ Bank (UAE)",
    "HBL Bank (UAE)",
    "Al Hilal Bank(UAE)",
    "FGB (UAE)",
    "Sharjah Islamic Bank(UAE)",
    "Noor Bank(UAE)",
    "CBI - Commercial Bank International (UAE)",
    "Janata Bank Ltd (UAE)",
    "Ajman Bank (UAE)",
    "Bank Melli Iran (UAE)",
    "FAB - First Abu Dhabi Bank (UAE)",
    "Citi Bank (UAE)",
    "The Saudi British Bank (UAE)",
    "BNP Paribas (UAE)",
    "Arab African International Bank (UAE)",
    "AL Masraf (UAE)",
    "Banque Misr (UAE)",
    "Samba Financial Group (UAE)",
  ];

  List<String> billsdata = ['On Account', 'New Ref', 'Agst Ref'];

  String user_email_fetched = "", token = '';

  bool isVisibleDueDate = false, isVisibleBillNo = false;

  String name = "",
      email = "",
      receiptdatestring = '',
      receiptdatetxt = '',
      instdatestring = '',
      instdatetxt = '',
      currencycode = '',
      billduedatestring = '',
      billduedatetxt = '';

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  late SharedPreferences prefs;

  dynamic _selectedbill, _selectedparty;

  Map<String, String>? _selectedbankcashname;

  // The 'type' value comes straight from the synced Tally ledger's
  // ledgroup column (backend entry.js), so its exact casing/spacing can
  // vary per company (e.g. "Cash-in-hand" vs "Cash-in-Hand") even though
  // MySQL's case-insensitive collation lets it through the same
  // "ledgroup in (...)" filter - normalize before comparing instead of
  // an exact string match.
  bool get isSelectedBankCashInHand {
    final type = _selectedbankcashname?['type']
        ?.toString()
        .trim()
        .toLowerCase()
        .replaceAll('-', ' ');

    return type == 'cash in hand';
  }

  late dynamic _selectedpaymentmode = '';

  late final TextEditingController controller_totalamt =
      TextEditingController();

  void updateChequeAmount() {
    totalChequeAmount = cheque.fold(0.0, (
      double previousAmount,
      Cheque cheque,
    ) {
      return previousAmount + cheque.chequeAmount;
    });
    // Update formatted total amount
    roundedtotalChequeAmount = double.parse(
      totalChequeAmount.toStringAsFixed(decimal),
    );
    print('cheque amount $roundedtotalChequeAmount');
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
        format = NumberFormat.simpleCurrency(
          locale: locale.toString(),
          name: currencyCode,
        );
      } else {
        format = NumberFormat.currency(
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

  bool isNumeric(String s) {
    if (s == null) {
      return false;
    }
    return double.tryParse(s) != null;
  }

  String? hostname = "",
      company = "",
      company_lowercase = "",
      serial_no = "",
      username = "",
      HttpURL = "",
      SecuritybtnAcessHolder = "";

  late DateTime receiptdate;
  late DateTime billduedate;
  late DateTime instdate;

  String? HttpURL_loadData, HttpURL_receiptEntry, HttpURL_fetchvchnos;

  final DateFormat _dateFormat = DateFormat('yyyyMMdd');

  List<Bills> bills = [];

  List<Cheque> cheque = [];

  final TextEditingController billAmountController = TextEditingController();
  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _billduedateController = TextEditingController();
  final TextEditingController instDateController = TextEditingController();
  final TextEditingController instNoController = TextEditingController();
  final TextEditingController chequeAmountController = TextEditingController();

  void _confirmBillDeletion(
    BuildContext context,
    int index,
    String billname,
    String billamount,
  ) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Confirm Deletion'),
          content: Text('Do you really want to delete $billname bill?'),
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
                _deleteBill(index);
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

  void _deleteBill(int index) {
    setState(() {
      bills.removeAt(index);
      // Calculate the total price of items
      totalBillAmount = bills.fold(0.0, (double previousAmount, Bills bill) {
        return previousAmount + bill.billAmount;
      });

      roundedtotalBillAmount = double.parse(
        totalBillAmount.toStringAsFixed(decimal),
      );
      NumberFormat formatter = NumberFormat('#,##0.${'0' * decimal}', 'en_US');
      String formattedtotal = formatter.format(roundedtotalBillAmount);
      controller_totalamt.text = formattedtotal.toString();

      if (bills.isEmpty) {
        isVisibleBillHeading = false;
        isChequeVisible = false;
        _selectedpaymentmode = paymentmode_data.isNotEmpty ? paymentmode_data.first : '';
        cheque.clear();
        updateChequeAmount();
        isPaymentModeVisible = false;
        instNoController.clear();
        selectedbankname = bankname_data.first;
        _banknameController.text = selectedbankname;
        chequeAmountController.clear();
        instdate = DateTime.now();
        instdatestring = _dateFormat.format(instdate);
        instdatetxt = formatlastsaledate(instdatestring);
        instDateController.text = instdatetxt;
        isVisibleChequeHeading = false;
      } else {
        isVisibleBillHeading = true;
        if (_selectedbankcashname != null && isSelectedBankCashInHand) {
          isPaymentModeVisible = false;
          _selectedpaymentmode = paymentmode_data.isNotEmpty ? paymentmode_data.first : '';
          cheque.clear();
          updateChequeAmount();

          isVisibleChequeHeading = false;
          isChequeVisible = false;
        } else {
          if (bills.isNotEmpty) {
            if (cheque.isNotEmpty) {
              isPaymentModeVisible = true;
              isChequeVisible = true;
              isVisibleChequeHeading = true;
            } else {
              isPaymentModeVisible = true;
              _selectedpaymentmode = paymentmode_data.isNotEmpty ? paymentmode_data.first : '';
              cheque.clear();
              updateChequeAmount();

              isVisibleChequeHeading = false;
              isChequeVisible = true;
            }
          } else {
            isPaymentModeVisible = true;
            _selectedpaymentmode = paymentmode_data.isNotEmpty ? paymentmode_data.first : '';
            cheque.clear();
            updateChequeAmount();

            isVisibleChequeHeading = false;
            isChequeVisible = false;
          }
        }
      }
      if (roundedtotalBillAmount < roundedtotalChequeAmount) {
        cheque.clear();
        updateChequeAmount();

        isVisibleChequeHeading = false;
      }
    });
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

  String formatAmountVoucher(String amount) {
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

  void showReceiptVoucherUpdatedDialog(BuildContext context) {
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: "ReceiptVoucherUpdated",
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
                  Text(
                    'Do you want to share the receipt voucher?',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(fontSize: 18.0),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Receipt Voucher Updated Successfully',
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
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (context) => PendingReceiptEntry(),
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
                          elevation: 4,
                          shadowColor: Colors.redAccent.withOpacity(0.3),
                        ),
                      ),

                      ElevatedButton.icon(
                        onPressed: () async {
                          Navigator.pop(context);
                          await generateVoucherPDF();
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
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(builder: (context) => PendingReceiptEntry()),
                          );
                        },
                        icon: const Icon(
                          Icons.close_rounded,
                          size: 20,
                          color: Colors.white,
                        ),
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
                          await generateVoucherPDF();
                        },
                        icon: const Icon(
                          Icons.share_rounded,
                          size: 20,
                          color: Colors.white,
                        ),
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
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return Transform.scale(
          scale: Curves.easeOutBack.transform(animation.value),
          child: Opacity(opacity: animation.value, child: child),
        );
      },
    );
  }

  Future<void> generateVoucherPDF() async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        build: (pw.Context context) {
          return pw.Stack(
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  // Tax Invoice Heading
                  pw.Header(
                    level: 0,
                    decoration: pw.BoxDecoration(
                      border: pw.Border(bottom: pw.BorderSide.none),
                    ),

                    child: pw.Center(
                      child: pw.Column(
                        children: [
                          pw.Text(
                            company!,
                            textAlign: pw.TextAlign.center,
                            style: pw.TextStyle(fontSize: 18),
                          ),
                          pw.SizedBox(height: 20),
                          pw.Text(
                            'Receipt Voucher',
                            textAlign: pw.TextAlign.center,
                            style: pw.TextStyle(fontSize: 18),
                          ),
                        ],
                      ),
                    ),
                  ),

                  pw.SizedBox(height: 10),

                  pw.Table(
                    border: pw.TableBorder(
                      horizontalInside: pw.BorderSide.none,
                      verticalInside: pw.BorderSide.none,
                      bottom: pw.BorderSide.none,
                    ),
                    children: [
                      pw.TableRow(
                        children: [
                          pw.Expanded(
                            flex: 5,
                            child: pw.Container(
                              padding: pw.EdgeInsets.fromLTRB(5, 5, 5, 5),
                              alignment: pw.Alignment.centerLeft,

                              child: pw.Row(
                                children: [
                                  pw.Text(
                                    'No. : ',
                                    style: pw.TextStyle(fontSize: 12),
                                  ),

                                  pw.Text(
                                    _vchnoController.text,
                                    style: pw.TextStyle(fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          pw.Expanded(
                            flex: 5,
                            child: pw.Container(
                              padding: pw.EdgeInsets.fromLTRB(5, 5, 5, 5),
                              alignment: pw.Alignment.centerRight,

                              child: pw.Row(
                                mainAxisAlignment: pw.MainAxisAlignment.end,
                                crossAxisAlignment: pw.CrossAxisAlignment.end,
                                children: [
                                  pw.Text(
                                    'Dated : ',
                                    style: pw.TextStyle(fontSize: 12),
                                  ),

                                  pw.Text(
                                    formatlastsaledate(receiptdatestring),
                                    style: pw.TextStyle(fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  pw.SizedBox(height: 5),

                  pw.Table(
                    border: pw.TableBorder(
                      horizontalInside: pw.BorderSide.none,
                      verticalInside: pw.BorderSide.none,
                      bottom: pw.BorderSide.none,
                    ),
                    children: [
                      pw.TableRow(
                        children: [
                          pw.Expanded(
                            flex: 5,
                            child: pw.Container(
                              padding: pw.EdgeInsets.fromLTRB(5, 5, 5, 15),
                              alignment: pw.Alignment.centerLeft,

                              child: pw.Row(
                                children: [
                                  pw.Text(
                                    'Remarks : ',
                                    style: pw.TextStyle(fontSize: 12),
                                  ),

                                  pw.Text(
                                    controller_narration.text,
                                    style: pw.TextStyle(fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  pw.SizedBox(height: 20),

                  pw.Table(
                    border: pw.TableBorder(
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
                            flex: 7,
                            child: pw.Container(
                              padding: pw.EdgeInsets.fromLTRB(10, 2, 5, 2),
                              alignment: pw.Alignment.centerLeft,

                              child: pw.Text(
                                'Particulars',
                                style: pw.TextStyle(fontSize: 11),
                              ),
                            ),
                          ),

                          pw.Expanded(
                            flex: 3,
                            child: pw.Container(
                              padding: pw.EdgeInsets.fromLTRB(5, 2, 10, 2),
                              alignment: pw.Alignment.centerRight,

                              child: pw.Text(
                                'Amount',
                                style: pw.TextStyle(fontSize: 11),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  pw.Table(
                    border: pw.TableBorder(
                      horizontalInside: pw.BorderSide.none,
                      verticalInside: pw.BorderSide(
                        color: PdfColor.fromHex('#050400'),
                      ),
                      bottom: pw.BorderSide.none,
                      top: pw.BorderSide.none,
                    ),
                    children: [
                      pw.TableRow(
                        children: [
                          pw.Expanded(
                            flex: 7,
                            child: pw.Container(
                              padding: pw.EdgeInsets.fromLTRB(5, 3, 5, 2),
                              alignment: pw.Alignment.centerLeft,

                              child: pw.Text(
                                'Account :',
                                style: pw.TextStyle(fontSize: 11),
                              ),
                            ),
                          ),

                          pw.Expanded(
                            flex: 3,
                            child: pw.Container(
                              padding: pw.EdgeInsets.fromLTRB(5, 2, 10, 2),
                              alignment: pw.Alignment.centerRight,

                              child: pw.Text(
                                '',
                                style: pw.TextStyle(fontSize: 11),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  pw.Table(
                    border: pw.TableBorder(
                      horizontalInside: pw.BorderSide.none,
                      verticalInside: pw.BorderSide(
                        color: PdfColor.fromHex('#050400'),
                      ),
                      bottom: pw.BorderSide.none,
                      top: pw.BorderSide.none,
                    ),
                    children: [
                      pw.TableRow(
                        children: [
                          pw.Expanded(
                            flex: 7,
                            child: pw.Container(
                              padding: pw.EdgeInsets.fromLTRB(15, 3, 5, 2),
                              alignment: pw.Alignment.centerLeft,

                              child: pw.Text(
                                _selectedparty,
                                style: pw.TextStyle(fontSize: 11),
                              ),
                            ),
                          ),

                          pw.Expanded(
                            flex: 3,
                            child: pw.Container(
                              padding: pw.EdgeInsets.fromLTRB(5, 2, 5, 2),
                              alignment: pw.Alignment.centerRight,

                              child: pw.Text(
                                formatAmountVoucher(
                                  roundedtotalBillAmount.toString(),
                                ),
                                style: pw.TextStyle(fontSize: 11),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  pw.Table(
                    border: pw.TableBorder(
                      horizontalInside: pw.BorderSide.none,
                      verticalInside: pw.BorderSide(
                        color: PdfColor.fromHex('#050400'),
                      ),
                      bottom: pw.BorderSide.none,
                      top: pw.BorderSide.none,
                    ),
                    children: [
                      for (var bill in bills.asMap().entries)
                        pw.TableRow(
                          children: [
                            pw.Expanded(
                              flex: 7,
                              child: pw.Container(
                                padding: pw.EdgeInsets.fromLTRB(20, 2, 10, 2),
                                alignment: pw.Alignment.centerLeft,

                                child: pw.Row(
                                  children: [
                                    pw.Text(
                                      bill.value.billName,
                                      style: pw.TextStyle(
                                        fontSize: 11,
                                        fontWeight: pw.FontWeight.bold,
                                      ),
                                    ),
                                    pw.SizedBox(width: 2),
                                    pw.Text(
                                      formatAmountVoucher(
                                        bill.value.billAmount.toString(),
                                      ),
                                      style: pw.TextStyle(
                                        fontSize: 11,
                                        fontWeight: pw.FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            pw.Expanded(
                              flex: 3,
                              child: pw.Container(
                                padding: pw.EdgeInsets.fromLTRB(5, 2, 10, 2),
                                alignment: pw.Alignment.centerRight,

                                child: pw.Text(
                                  '',
                                  style: pw.TextStyle(fontSize: 11),
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),

                  pw.Table(
                    border: pw.TableBorder(
                      horizontalInside: pw.BorderSide.none,
                      verticalInside: pw.BorderSide(
                        color: PdfColor.fromHex('#050400'),
                      ),
                      bottom: pw.BorderSide.none,
                      top: pw.BorderSide.none,
                    ),
                    children: [
                      pw.TableRow(
                        children: [
                          pw.Expanded(
                            flex: 7,
                            child: pw.Container(
                              padding: pw.EdgeInsets.fromLTRB(20, 2, 5, 2),
                              alignment: pw.Alignment.centerLeft,

                              child: pw.SizedBox(height: 25),
                            ),
                          ),

                          pw.Expanded(
                            flex: 3,
                            child: pw.Container(
                              padding: pw.EdgeInsets.fromLTRB(5, 2, 10, 2),
                              alignment: pw.Alignment.centerRight,

                              child: pw.SizedBox(height: 25),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  pw.Table(
                    border: pw.TableBorder(
                      horizontalInside: pw.BorderSide.none,
                      verticalInside: pw.BorderSide(
                        color: PdfColor.fromHex('#050400'),
                      ),
                      bottom: pw.BorderSide.none,
                      top: pw.BorderSide.none,
                    ),
                    children: [
                      pw.TableRow(
                        children: [
                          pw.Expanded(
                            flex: 7,
                            child: pw.Container(
                              padding: pw.EdgeInsets.fromLTRB(5, 2, 5, 2),
                              alignment: pw.Alignment.centerLeft,

                              child: pw.Text(
                                'Through : ',
                                style: pw.TextStyle(
                                  fontSize: 11,
                                  fontWeight: pw.FontWeight.normal,
                                ),
                              ),
                            ),
                          ),

                          pw.Expanded(
                            flex: 3,
                            child: pw.Container(
                              padding: pw.EdgeInsets.fromLTRB(5, 2, 10, 2),
                              alignment: pw.Alignment.centerRight,

                              child: pw.Text(
                                '',
                                style: pw.TextStyle(
                                  fontSize: 11,
                                  fontWeight: pw.FontWeight.normal,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  pw.Table(
                    border: pw.TableBorder(
                      horizontalInside: pw.BorderSide.none,
                      verticalInside: pw.BorderSide(
                        color: PdfColor.fromHex('#050400'),
                      ),
                      bottom: pw.BorderSide.none,
                      top: pw.BorderSide.none,
                    ),
                    children: [
                      pw.TableRow(
                        children: [
                          pw.Expanded(
                            flex: 7,
                            child: pw.Container(
                              padding: pw.EdgeInsets.fromLTRB(5, 2, 5, 2),
                              alignment: pw.Alignment.centerLeft,

                              child: pw.Text(
                                _selectedbankcashname!['name']!,
                                style: pw.TextStyle(
                                  fontSize: 11,
                                  fontWeight: pw.FontWeight.normal,
                                ),
                              ),
                            ),
                          ),

                          pw.Expanded(
                            flex: 3,
                            child: pw.Container(
                              padding: pw.EdgeInsets.fromLTRB(5, 2, 10, 2),
                              alignment: pw.Alignment.centerRight,

                              child: pw.Text(
                                '',
                                style: pw.TextStyle(
                                  fontSize: 11,
                                  fontWeight: pw.FontWeight.normal,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  if (cheque.isNotEmpty)
                    pw.Column(
                      children: [
                        pw.Table(
                          border: pw.TableBorder(
                            horizontalInside: pw.BorderSide.none,
                            verticalInside: pw.BorderSide(
                              color: PdfColor.fromHex('#050400'),
                            ),
                            bottom: pw.BorderSide.none,
                            top: pw.BorderSide.none,
                          ),
                          children: [
                            pw.TableRow(
                              children: [
                                pw.Expanded(
                                  flex: 7,
                                  child: pw.Container(
                                    padding: pw.EdgeInsets.fromLTRB(5, 2, 5, 2),
                                    alignment: pw.Alignment.centerLeft,

                                    child: pw.Text(
                                      'Bank Transaction Details:',
                                      style: pw.TextStyle(
                                        fontSize: 11,
                                        fontWeight: pw.FontWeight.normal,
                                      ),
                                    ),
                                  ),
                                ),

                                pw.Expanded(
                                  flex: 3,
                                  child: pw.Container(
                                    padding: pw.EdgeInsets.fromLTRB(
                                      5,
                                      2,
                                      10,
                                      2,
                                    ),
                                    alignment: pw.Alignment.centerRight,

                                    child: pw.Text(
                                      '',
                                      style: pw.TextStyle(
                                        fontSize: 11,
                                        fontWeight: pw.FontWeight.normal,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),

                        for (var cheque in cheque.asMap().entries)
                          pw.Table(
                            border: pw.TableBorder(
                              horizontalInside: pw.BorderSide.none,
                              verticalInside: pw.BorderSide(
                                color: PdfColor.fromHex('#050400'),
                              ),
                              bottom: pw.BorderSide.none,
                              top: pw.BorderSide.none,
                            ),
                            children: [
                              pw.TableRow(
                                children: [
                                  pw.Expanded(
                                    flex: 7,
                                    child: pw.Container(
                                      padding: pw.EdgeInsets.fromLTRB(
                                        5,
                                        2,
                                        5,
                                        2,
                                      ),
                                      alignment: pw.Alignment.centerLeft,

                                      child: pw.Row(
                                        children: [
                                          pw.Text(
                                            cheque.value.paymentMode,
                                            style: pw.TextStyle(
                                              fontSize: 11,
                                              fontWeight: pw.FontWeight.normal,
                                            ),
                                          ),

                                          pw.SizedBox(width: 10),

                                          pw.Text(
                                            formatlastsaledate(
                                              cheque.value.instdate.toString(),
                                            ),
                                            style: pw.TextStyle(
                                              fontSize: 11,
                                              fontWeight: pw.FontWeight.normal,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),

                                  pw.Expanded(
                                    flex: 3,
                                    child: pw.Container(
                                      padding: pw.EdgeInsets.fromLTRB(
                                        5,
                                        2,
                                        10,
                                        2,
                                      ),
                                      alignment: pw.Alignment.centerRight,

                                      child: pw.Text(
                                        '',
                                        style: pw.TextStyle(
                                          fontSize: 11,
                                          fontWeight: pw.FontWeight.normal,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                      ],
                    ),
                  pw.Column(
                    children: [
                      pw.Table(
                        border: pw.TableBorder(
                          horizontalInside: pw.BorderSide.none,
                          verticalInside: pw.BorderSide(
                            color: PdfColor.fromHex('#050400'),
                          ),
                          bottom: pw.BorderSide.none,
                          top: pw.BorderSide.none,
                        ),
                        children: [
                          pw.TableRow(
                            children: [
                              pw.Expanded(
                                flex: 7,
                                child: pw.Container(
                                  padding: pw.EdgeInsets.fromLTRB(5, 30, 5, 2),
                                  alignment: pw.Alignment.centerLeft,

                                  child: pw.Text(
                                    'Amount (in words) :',
                                    style: pw.TextStyle(
                                      fontSize: 11,
                                      fontWeight: pw.FontWeight.normal,
                                    ),
                                  ),
                                ),
                              ),

                              pw.Expanded(
                                flex: 3,
                                child: pw.Container(
                                  padding: pw.EdgeInsets.fromLTRB(5, 30, 10, 2),
                                  alignment: pw.Alignment.centerRight,

                                  child: pw.Text(
                                    '',
                                    style: pw.TextStyle(
                                      fontSize: 11,
                                      fontWeight: pw.FontWeight.normal,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),

                      pw.Table(
                        border: pw.TableBorder(
                          horizontalInside: pw.BorderSide.none,
                          verticalInside: pw.BorderSide(
                            color: PdfColor.fromHex('#050400'),
                          ),
                          bottom: pw.BorderSide.none,
                          top: pw.BorderSide.none,
                        ),
                        children: [
                          pw.TableRow(
                            children: [
                              pw.Expanded(
                                flex: 7,
                                child: pw.Container(
                                  padding: pw.EdgeInsets.fromLTRB(5, 2, 5, 2),
                                  alignment: pw.Alignment.centerLeft,

                                  child: pw.Text(
                                    convertAmountToWords(totalBillAmount),
                                    style: pw.TextStyle(
                                      fontSize: 11,
                                      fontWeight: pw.FontWeight.normal,
                                    ),
                                  ),
                                ),
                              ),

                              pw.Expanded(
                                flex: 3,
                                child: pw.Container(
                                  padding: pw.EdgeInsets.fromLTRB(5, 2, 10, 2),
                                  alignment: pw.Alignment.centerRight,

                                  child: pw.Text(
                                    '',
                                    style: pw.TextStyle(
                                      fontSize: 11,
                                      fontWeight: pw.FontWeight.normal,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),

                      pw.Table(
                        border: pw.TableBorder(
                          horizontalInside: pw.BorderSide.none,
                          verticalInside: pw.BorderSide(
                            color: PdfColor.fromHex('#050400'),
                          ),
                          bottom: pw.BorderSide.none,
                          top: pw.BorderSide.none,
                          right: pw.BorderSide.none,
                        ),
                        children: [
                          pw.TableRow(
                            children: [
                              pw.Expanded(
                                flex: 7,
                                child: pw.Container(
                                  padding: pw.EdgeInsets.fromLTRB(5, 5, 5, 0),
                                  alignment: pw.Alignment.centerLeft,

                                  child: pw.Text(
                                    '',
                                    style: pw.TextStyle(
                                      fontSize: 11,
                                      fontWeight: pw.FontWeight.normal,
                                    ),
                                  ),
                                ),
                              ),

                              pw.Expanded(
                                flex: 3,
                                child: pw.Container(
                                  padding: pw.EdgeInsets.fromLTRB(0, 5, 0, 0),
                                  alignment: pw.Alignment.centerRight,

                                  child: pw.Table(
                                    border: pw.TableBorder(
                                      horizontalInside: pw.BorderSide.none,
                                      verticalInside: pw.BorderSide.none,
                                      bottom: pw.BorderSide(
                                        color: PdfColor.fromHex('#050400'),
                                      ),
                                      top: pw.BorderSide(
                                        color: PdfColor.fromHex('#050400'),
                                      ),
                                      right: pw.BorderSide.none,
                                    ),
                                    children: [
                                      pw.TableRow(
                                        children: [
                                          pw.Expanded(
                                            flex: 3,
                                            child: pw.Container(
                                              padding: pw.EdgeInsets.fromLTRB(
                                                0,
                                                5,
                                                10,
                                                5,
                                              ),
                                              alignment:
                                                  pw.Alignment.centerRight,

                                              child: pw.Text(
                                                formatAmountVoucher(
                                                  totalBillAmount.toString(),
                                                ),
                                                style: pw.TextStyle(
                                                  fontSize: 11,
                                                  fontWeight:
                                                      pw.FontWeight.normal,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),

                      pw.Table(
                        border: pw.TableBorder(
                          horizontalInside: pw.BorderSide.none,
                          verticalInside: pw.BorderSide.none,
                          bottom: pw.BorderSide.none,
                          top: pw.BorderSide.none,
                          right: pw.BorderSide.none,
                        ),
                        children: [
                          pw.TableRow(
                            children: [
                              pw.Expanded(
                                flex: 7,
                                child: pw.Container(
                                  padding: pw.EdgeInsets.fromLTRB(5, 50, 5, 0),
                                  alignment: pw.Alignment.centerLeft,

                                  child: pw.Text(
                                    '',
                                    style: pw.TextStyle(
                                      fontSize: 11,
                                      fontWeight: pw.FontWeight.normal,
                                    ),
                                  ),
                                ),
                              ),

                              pw.Expanded(
                                flex: 3,
                                child: pw.Container(
                                  padding: pw.EdgeInsets.fromLTRB(0, 50, 5, 0),
                                  alignment: pw.Alignment.centerLeft,

                                  child: pw.Text(
                                    'Authorised Signatory',
                                    style: pw.TextStyle(
                                      fontSize: 11,
                                      fontWeight: pw.FontWeight.normal,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
              pw.Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: pw.Container(
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
                ),
              ),
            ],
          );
        },
      ),
    );
    final pdfData = await pdf.save();

    final dir = await getApplicationDocumentsDirectory();
    final filePath = '${dir.path}/$_selectedparty.pdf';

    final file = File(filePath);
    await file.writeAsBytes(pdfData);

    await Share.shareXFiles([
      XFile(filePath, mimeType: 'application/pdf'),
    ], text: 'Sharing Receipt Voucher for $_selectedparty');

    // This is a Modify screen, not a new-entry screen - after sharing the
    // updated voucher there's nothing left to edit here, so go to the view
    // screen (matching the dialog's "No, Thanks") instead of resetting
    // fields in place. The in-place reset used to leave the Party
    // TypeAheadField focused while its controller was cleared/updated,
    // which reopened its suggestions dropdown right after save/share.
    if (context.mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => PendingReceiptEntry()),
      );
    }
  }

  Future<void> updateEntry(int id) async {
    // ❌ Prevent save if party not selected
    if (_selectedparty == null || _selectedparty.toString().trim().isEmpty) {
      showAppMessage(context, "Please select Party");
      return;
    }

    // ❌ Prevent save if bank/cash not selected
    if (_selectedbankcashname == null ||
        _selectedbankcashname!['name'] == null ||
        _selectedbankcashname!['name']!.trim().isEmpty) {
      showAppMessage(context, "Please select Bank / Cash Ledger");
      return;
    }

    if (bills.isEmpty) {
      showAppMessage(context, 'Atleast add 1 bill');
    } else {
      setState(() {
        _isLoading = true;
      });
      jsonEntryData.clear();
      String narrationValue = controller_narration.text.trim();
      String vchnoValue = _vchnoController.text;

      jsonEntryData["DATE"] = receiptdatestring;
      jsonEntryData["VOUCHERTYPENAME"] = _selectedvchtypename;
      jsonEntryData["PARTYLEDGERNAME"] = _selectedparty;
      jsonEntryData["VOUCHERNUMBER"] = vchnoValue;
      jsonEntryData["ENTEREDBY"] = name;
      jsonEntryData["NARRATION"] = narrationValue;

      final List<Map<String, dynamic>> allLedgerEntriesList = [];

      // Get the list of non-"On Account" bills
      final List<Map<String, dynamic>> nonOnAccountBills = bills
          .where((bill) => bill.billName != "On Account")
          .map((bill) {
            final Map<String, dynamic> billData = {
              "BILLTYPE": bill.billName,
              "AMOUNT": bill.billAmount.toStringAsFixed(decimal),
            };

            // Conditionally add BILLNO and BILL CREDIT PERIOD if BILLTYPE is not "On Account"
            if (bill.billName != "On Account") {
              billData["NAME"] = bill.billNo;
              billData["BILLCREDITPERIOD"] =
                  bill.billDueDate ??
                  ""; // Assuming billDueDate is part of the bill object
            }

            return billData;
          })
          .toList();

      // Get the list of "On Account" bills
      final List<Map<String, dynamic>> onAccountBills = bills
          .where((bill) => bill.billName == "On Account")
          .map((bill) {
            final Map<String, dynamic> billData = {
              "BILLTYPE": bill.billName,
              "AMOUNT": bill.billAmount,
            };
            return billData;
          })
          .toList();

      // Combine the lists, placing "On Account" bills at the end
      final List<Map<String, dynamic>> allBillAllocations = [
        ...nonOnAccountBills,
        ...onAccountBills,
      ];

      final Map<String, dynamic> allLedgerEntry = {
        "LEDGERNAME": _selectedparty,
        "AMOUNT": totalBillAmount,
        "ISPARTYLEDGER": "Yes",
        "ISDEEMEDPOSITIVE": "No",
        "BILLALLOCATIONS.LIST": allBillAllocations,
      };
      allLedgerEntriesList.add(allLedgerEntry);

      // Add bank allocation details
      final Map<String, dynamic> bankAllocation = {
        "LEDGERNAME":
            _selectedbankcashname!['name'], // Assuming you're getting bank name dynamically
        "AMOUNT":
            -totalBillAmount, // Assuming you have totalBankAmount calculated
        "ISPARTYLEDGER": "No",
        "ISDEEMEDPOSITIVE": "Yes",
        "BANKALLOCATIONS.LIST":
            [], // Conditionally empty list based on the type of selected bank/cash
      };
      allLedgerEntriesList.add(bankAllocation);

      // If the selected bank/cash type is not 'Cash-in-Hand', add cheque details to bank allocation list
      if (!isSelectedBankCashInHand) {
        bankAllocation["BANKALLOCATIONS.LIST"] = cheque.map((cheque) {
          return {
            "DATE": cheque.date,
            "INSTRUMENTDATE": cheque.instdate ?? receiptdatestring,
            "TRANSACTIONTYPE": cheque.paymentMode,
            "BANKNAME": (cheque.bankname != "Not Applicable")
                ? cheque.bankname
                : "",
            "PAYMENTFAVOURING": cheque.paymentFavouring,
            "INSTRUMENTNUMBER": cheque.instno,
            "BANKPARTYNAME": cheque.bankPartyName,
            "AMOUNT": -cheque.chequeAmount,
          };
        }).toList();
      }

      jsonEntryData['ALLLEDGERENTRIES.LIST'] = allLedgerEntriesList;

      try {
        final url_receiptentry = Uri.parse(HttpURL_receiptEntry!);
        Map<String, String> headers_receiptentry = {
          'Authorization': 'Bearer $token',
          "Content-Type": "application/json",
        };
        Map<String, dynamic> jsonData = {'id': id, 'data': jsonEntryData};
        String jsonDataString = jsonEncode(jsonData);
        print(jsonDataString);

        var body_receiptentry = jsonDataString;

        final response_receiptentry = await http.post(
          url_receiptentry,
          body: body_receiptentry,
          headers: headers_receiptentry,
        );

        if (response_receiptentry.statusCode == 200) {
          if (response_receiptentry.body == 'Entry updated successfully') {
            data = Map<String, dynamic>.from(jsonEntryData);
            showReceiptVoucherUpdatedDialog(context);
          } else {
            showAppMessage(context, 'an error occoured');
          }
        } else {
          Map<String, dynamic> data = json.decode(response_receiptentry.body);
          String error = '';

          if (data.containsKey('error')) {
            setState(() {
              error = data['error'];
            });
          } else {
            error = "Error in data fetching!!!";
          }
          showAppMessage(context, error);
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

  Future<void> loadData() async {
    vchtypenamedata.clear();
    partydata.clear();
    bankcashname_data.clear();
    bills.clear();
    totalBillAmount = bills.fold(0.0, (double previousAmount, Bills bill) {
      return previousAmount + bill.billAmount;
    });
    // Update formatted total amount
    roundedtotalBillAmount = double.parse(
      totalBillAmount.toStringAsFixed(decimal),
    );
    NumberFormat formatter = NumberFormat('#,##0.${'0' * decimal}', 'en_US');
    String formattedtotal = formatter.format(roundedtotalBillAmount);
    controller_totalamt.text = formattedtotal.toString();
    cheque.clear();
    updateChequeAmount();

    billAmountController.clear();
    chequeAmountController.clear();
    instNoController.clear();
    selectedbankname = bankname_data.first;
    _banknameController.text = selectedbankname;
    controller_totalamt.text = '0';

    setState(() {
      _isLoading = true;
    });

    // data fetching
    try {
      final url = Uri.parse(HttpURL_loadData!);
      Map<String, String> headers = {
        'Authorization': 'Bearer $token',
        "Content-Type": "application/json",
      };
      final response = await http.post(url, headers: headers);

      if (response.statusCode == 200) {
        final Map<String, dynamic> jsonResponse = json.decode(utf8.decode(response.bodyBytes));

        String oldvchname = data['VOUCHERTYPENAME']?.toString() ?? '';
        String oldpartyledger = data['PARTYLEDGERNAME']?.toString() ?? '';
        String oldvchno = data['VOUCHERNUMBER']?.toString() ?? '';
        /* String oldsalesledger = data['salesledger'];*/
        String oldnarration = data['NARRATION']?.toString() ?? '';
        /*print(response.body);*/
        setState(() {
          vchtypenamedata = List<String>.from(
            (jsonResponse['vchTypes'] ?? const [])
                .where((item) => item != null)
                .map((item) => item.toString()),
          );
          _selectedvchtypename =
              oldvchname.isNotEmpty && vchtypenamedata.contains(oldvchname)
              ? oldvchname
              : (vchtypenamedata.isNotEmpty ? vchtypenamedata.first : '');
          if (_selectedvchtypename.isNotEmpty) {
            fetchvchnos(_selectedvchtypename);
          }
          partydata = List<String>.from(
            (jsonResponse['partyLedgers'] ?? const [])
                .where((item) => item != null)
                .map((item) => item.toString()),
          );
          partydata.sort();
          _selectedparty = oldpartyledger;
          _partyController.text = _selectedparty;

          controller_narration.text = oldnarration;

          _vchnoController.text = oldvchno;

          bankcashname_data = List<Map<String, String>>.from(
            jsonResponse['cashLedgers']?.map(
                  (cashLedger) => Map<String, String>.from(cashLedger),
                ) ??
                [],
          );

          List<dynamic> ledgerEntries = _entryList(
            data['ALLLEDGERENTRIES.LIST'],
          );

          final bankLedgerEntry = _findBankLedgerEntry(ledgerEntries);
          final ledgerNameToMatch = bankLedgerEntry?['LEDGERNAME']?.toString();

          Map<String, String>? selectedLedger;
          if (ledgerNameToMatch != null && ledgerNameToMatch.isNotEmpty) {
            try {
              selectedLedger = bankcashname_data.firstWhere(
                (item) => item['name'] == ledgerNameToMatch,
              );
            } catch (_) {
              selectedLedger = null;
            }
          }

          if (selectedLedger != null) {
            _selectedbankcashname = selectedLedger;
            _bankcashnameController.text = _selectedbankcashname!['name'] ?? "";
          }

          // Print the data from ledgerEntries
          for (var entry in ledgerEntries) {
            print(entry);
          }

          try {
            final billLedgerEntry = _findBillLedgerEntry(ledgerEntries);
            final billAllocations = _entryList(
              billLedgerEntry?['BILLALLOCATIONS.LIST'],
            );

            for (final allocation in billAllocations) {
              if (allocation is! Map<String, dynamic>) continue;

              final billType = allocation['BILLTYPE']?.toString() ?? 'Unknown';
              final billAmount = _entryAmount(allocation['AMOUNT']).abs();

              String? billNo;
              String? billDueDate;

              if (billType != 'On Account') {
                billNo = allocation['NAME']?.toString();
                billDueDate = allocation['BILLCREDITPERIOD']?.toString();
              }

              bills.add(
                Bills(
                  billName: billType,
                  billAmount: billAmount,
                  billNo: billNo,
                  billDueDate: billDueDate,
                ),
              );
            }
          } catch (e) {
            print(e);
          }

          try {
            final bankAllocations = _entryList(
              bankLedgerEntry?['BANKALLOCATIONS.LIST'],
            );
            print('bank length ${bankAllocations.length}');

            for (final allocation in bankAllocations) {
              if (allocation is! Map<String, dynamic>) continue;

              final instno = allocation['INSTRUMENTNUMBER']?.toString() ?? '';
              final instdate = allocation['INSTRUMENTDATE']?.toString();
              final bankname = allocation['BANKNAME']?.toString();
              final chequeAmount = _entryAmount(allocation['AMOUNT']).abs();
              final paymentMode =
                  allocation['TRANSACTIONTYPE']?.toString() ?? '';
              final date = allocation['DATE']?.toString() ?? '';
              final paymentfavouring =
                  allocation['PAYMENTFAVOURING']?.toString() ?? '';
              final bankpartyname =
                  allocation['BANKPARTYNAME']?.toString() ?? '';

              cheque.add(
                Cheque(
                  date: date,
                  paymentFavouring: paymentfavouring,
                  bankPartyName: bankpartyname,
                  instno: instno,
                  instdate: instdate,
                  bankname: bankname,
                  chequeAmount: chequeAmount,
                  paymentMode: paymentMode,
                ),
              );
            }
          } catch (e) {
            print(e);
          }
          int l = cheque.length;

          print('cheque length $l');

          if (cheque.isNotEmpty) {
            _selectedpaymentmode = cheque.last.paymentMode;
          } else {
            _selectedpaymentmode = paymentmode_data.isNotEmpty ? paymentmode_data.first : '';
            isPaymentModeVisible = false;
          }

          if (bills.isEmpty) {
            isVisibleBillHeading = false;
            isPaymentModeVisible = false;
          } else {
            isVisibleBillHeading = true;
          }

          if (_selectedbankcashname != null && isSelectedBankCashInHand) {
            isPaymentModeVisible = false;
            _selectedpaymentmode = paymentmode_data.isNotEmpty ? paymentmode_data.first : '';
            cheque.clear();
            updateChequeAmount();
            isVisibleChequeHeading = false;
            isChequeVisible = false;
          } else {
            if (bills.isNotEmpty) {
              if (cheque.isNotEmpty) {
                isPaymentModeVisible = true;
                isChequeVisible = true;
                isVisibleChequeHeading = true;
              } else {
                isPaymentModeVisible = true;
                _selectedpaymentmode = paymentmode_data.isNotEmpty ? paymentmode_data.first : '';
                cheque.clear();
                updateChequeAmount();

                isVisibleChequeHeading = false;
                isChequeVisible = true;
              }
            } else {
              isPaymentModeVisible = true;
              _selectedpaymentmode = paymentmode_data.isNotEmpty ? paymentmode_data.first : '';
              cheque.clear();
              updateChequeAmount();

              isVisibleChequeHeading = false;
              isChequeVisible = true;
            }
          }

          totalBillAmount = bills.fold(0.0, (
            double previousAmount,
            Bills bill,
          ) {
            return previousAmount + bill.billAmount;
          });
          roundedtotalBillAmount = double.parse(
            totalBillAmount.toStringAsFixed(decimal),
          );
          NumberFormat formatter = NumberFormat(
            '#,##0.${'0' * decimal}',
            'en_US',
          );
          String formattedtotal = formatter.format(roundedtotalBillAmount);
          controller_totalamt.text = formattedtotal.toString();

          updateChequeAmount();
        });
      } else {
        Map<String, dynamic> data = json.decode(utf8.decode(response.bodyBytes));
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
      /*print(e);*/
    }

    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _selectreceiptDate(BuildContext context) async {
    if (isUniGasSerial(serial_no)) {
      closeKeyboard(context);
      showAppMessage(context, "Voucher date cannot be changed");
      return;
    }
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: receiptdate,
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
    if (picked != null && picked != receiptdate) {
      setState(() {
        receiptdate = picked;
        receiptdatestring = _dateFormat.format(receiptdate);
        receiptdatetxt = formatlastsaledate(receiptdatestring);
        _dateController.text = receiptdatetxt;

        if (_selectedbankcashname != null && isSelectedBankCashInHand) {
          isPaymentModeVisible = false;
          _selectedpaymentmode = paymentmode_data.isNotEmpty ? paymentmode_data.first : '';
          cheque.clear();
          updateChequeAmount();
          isVisibleChequeHeading = false;
          isChequeVisible = false;
        } else {
          if (bills.isNotEmpty) {
            if (cheque.isNotEmpty) {
              isPaymentModeVisible = true;
              _selectedpaymentmode = paymentmode_data.isNotEmpty ? paymentmode_data.first : '';
              cheque.clear();
              updateChequeAmount();

              isVisibleChequeHeading = false;
              isChequeVisible = true;
            } else {
              isPaymentModeVisible = true;
              _selectedpaymentmode = paymentmode_data.isNotEmpty ? paymentmode_data.first : '';
              cheque.clear();
              updateChequeAmount();

              isVisibleChequeHeading = false;
              isChequeVisible = true;
            }
          } else {
            isPaymentModeVisible = true;
            _selectedpaymentmode = paymentmode_data.isNotEmpty ? paymentmode_data.first : '';
            cheque.clear();
            updateChequeAmount();

            isVisibleChequeHeading = false;
            isChequeVisible = false;
          }
        }
      });
    }
  } // main receipt date

  Future<void> _selectinstDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: instdate,
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
    if (picked != null && picked != instdate) {
      setState(() {
        instdate = picked;
        instdatestring = _dateFormat.format(instdate);
        instdatetxt = formatlastsaledate(instdatestring);
        instDateController.text = instdatetxt;
      });
    }
  }

  /*Future<void> _selectbilldueDate(BuildContext context) async {

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: billduedate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
      builder: (BuildContext context, Widget? child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme:  Theme.of(context).colorScheme.copyWith(
              primary:  app_color,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != receiptdate)
    {
      setState(() {
        billduedate = picked;
        billduedatestring = _dateFormat.format(billduedate);
        billduedatetxt = formatlastsaledate(billduedatestring);
        _billduedateController.text = billduedatetxt;
      });
    }

  }*/ // bill due date selection

  /*Future<void> _showBillsDetailsPopup(BuildContext context) async {
    setState(() {
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            titlePadding: EdgeInsets.zero,
            title:
            Column(
              children: [
                Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: app_color,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [Colors.white, Colors.white],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: const Icon(Icons.receipt_long, color: app_color, size: 26),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Add Bill",
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),


            content: SingleChildScrollView(
              child: Form(
                key: _billsFormkey,
                child: Column(
                  children: <Widget>[
                    // 🔹 Bill Type Dropdown
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: "Bill Type",
                        hintText: "Select Bill Type",
                        labelStyle: GoogleFonts.poppins(
                          fontSize: 12.5,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        hintStyle: GoogleFonts.poppins(
                          fontSize: 12.5,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        prefixIcon: Container(
                          margin: const EdgeInsets.all(8), // 👈 smaller margin
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Colors.indigo, Colors.cyan],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.book, color: Colors.white, size: 16), // 👈 smaller icon
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14), // 👈 slightly tighter radius
                          borderSide: BorderSide(color: Theme.of(context).dividerColor),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: app_color, width: 1.3),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10, // 👈 tighter padding
                        ),
                      ),
                      value: _selectedbill,
                      items: billsdata.map((String value) {
                        return DropdownMenuItem(
                          value: value,
                          child: Text(value, style: GoogleFonts.poppins(fontSize: 13)),
                        );
                      }).toList(),
                      onChanged: (newValue) {
                        setState(() {
                          _selectedbill = newValue!;
                          if (_selectedbill == 'New Ref' || _selectedbill == 'Agst Ref') {
                            isVisibleDueDate = true;
                            isVisibleBillNo = true;
                          } else {
                            isVisibleDueDate = false;
                            isVisibleBillNo = false;
                            billNoController.clear();
                            _billduedateController.clear();
                          }
                          Navigator.of(context).pop();
                          _billsFormkey = GlobalKey<FormState>();
                          _showBillsDetailsPopup(context);
                        });
                      },
                    ),


                    // 🔹 Bill No
                    Visibility(
                      visible: isVisibleBillNo,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: TextFormField(
                          controller: billNoController,
                          validator: (value) => value!.isEmpty ? 'Please enter bill no' : null,
                          decoration: InputDecoration(
                            labelText: "Bill No",
                            hintText: "Enter Bill No",
                            labelStyle: GoogleFonts.poppins(
                              fontSize: 12.5,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                            hintStyle: GoogleFonts.poppins(
                              fontSize: 12.5,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                            prefixIcon: Container(
                              margin: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Colors.orange, Colors.deepOrangeAccent],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.confirmation_num_outlined, color: Colors.white, size: 20),
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(color: app_color, width: 1.5),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),

                          ),
                        ),
                      ),
                    ),

                    // 🔹 Due Date
                    Visibility(
                      visible: isVisibleDueDate,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: TextFormField(
                          controller: _billduedateController,
                          validator: (value) {
                            if (value!.isNotEmpty) {
                              if (double.tryParse(value) == null) {
                                return 'Invalid input, please enter a number';
                              } else if (double.parse(value) < 0) {
                                return 'Due date days cannot be negative';
                              }
                            }
                            return null;
                          },
                          decoration: InputDecoration(
                            labelText: "Due Date (days)",
                            hintText: "Enter due date",
                            labelStyle: GoogleFonts.poppins(
                              fontSize: 13,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                            hintStyle: GoogleFonts.poppins(
                              fontSize: 13,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                            prefixIcon: Container(
                              margin: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Colors.pinkAccent, Colors.redAccent],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.calendar_today, color: Colors.white, size: 20),
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(color: app_color, width: 1.5),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),

                          ),
                        ),
                      ),
                    ),

                    // 🔹 Amount
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: TextFormField(
                        controller: billAmountController,
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          if (value!.isEmpty) return 'Please enter amount';
                          if (!isNumeric(value)) return 'Enter valid amount';
                          if (double.parse(value) == 0) return 'Amount should not be 0';
                          return null;
                        },
                        decoration: InputDecoration(
                          labelText: "Amount",
                          hintText: "0",
                          labelStyle: GoogleFonts.poppins(
                            fontSize: 13,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          hintStyle: GoogleFonts.poppins(
                            fontSize: 13,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
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
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),

                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  _selectedbill = billsdata.first;
                  isVisibleDueDate = _selectedbill == 'New Ref' || _selectedbill == 'Agst Ref';
                  isVisibleBillNo = isVisibleDueDate;
                  _billduedateController.clear();
                  billAmountController.clear();
                },
                child: Text('Cancel',
                  style: GoogleFonts.poppins(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),

              // ✅ Premium Add Bill button
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: app_color,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                onPressed: () {
                  if (_billsFormkey.currentState!.validate()) {
                    _billsFormkey.currentState!.save();
                    addBill();
                  }
                },
                child: Text("Add Bill",
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          );
        },
      );
    });
  }*/

  Future<void> _showBillsDetailsPopup(BuildContext context) async {
    setState(() {
      showModalBottomSheet(
        useSafeArea: true,
        barrierColor: Colors.black.withValues(alpha: 0.45),
        context: context,
        isScrollControlled: true,
        enableDrag: false,
        backgroundColor: Colors.transparent,
        builder: (BuildContext context) {
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
                if (isVisibleBillNo || isVisibleDueDate) {
                  if (screenHeight < 700) {
                    sheetHeight = 0.86;
                  } else if (screenHeight < 850) {
                    sheetHeight = 0.70;
                  } else {
                    sheetHeight = 0.60;
                  }
                } else {
                  if (screenHeight < 700) {
                    sheetHeight = 0.62;
                  } else if (screenHeight < 850) {
                    sheetHeight = 0.50;
                  } else {
                    sheetHeight = 0.42;
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
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: app_color,
                            ),
                            child: const Icon(
                              Icons.receipt_long,
                              color: Colors.white,
                              size: 26,
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],

                        Text(
                          "Add Bill",
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
                              key: _billsFormkey,
                              child: Column(
                                children: <Widget>[
                                  DropdownButtonFormField<String>(
                                    isExpanded: true,
                                    decoration: InputDecoration(
                                      labelText: "Bill Type",
                                      hintText: "Select Bill Type",
                                      labelStyle: GoogleFonts.poppins(
                                        fontSize: 12.5,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                      hintStyle: GoogleFonts.poppins(
                                        fontSize: 12.5,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                      prefixIcon: Container(
                                        margin: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          gradient: const LinearGradient(
                                            colors: [
                                              Colors.indigo,
                                              Colors.cyan,
                                            ],
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.book,
                                          color: Colors.white,
                                          size: 16,
                                        ),
                                      ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(14),
                                        borderSide: BorderSide(
                                          color: Theme.of(context).dividerColor,
                                        ),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(14),
                                        borderSide: BorderSide(
                                          color: Theme.of(context).dividerColor,
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(14),
                                        borderSide: BorderSide(
                                          color: app_color,
                                          width: 1.3,
                                        ),
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 10,
                                          ),
                                    ),
                                    value: _selectedbill,
                                    items: billsdata.map((String value) {
                                      return DropdownMenuItem(
                                        value: value,
                                        child: Text(
                                          value,
                                          style: GoogleFonts.poppins(
                                            fontSize: 13,
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                    onChanged: (newValue) {
                                      setState(() {
                                        _selectedbill = newValue!;

                                        if (_selectedbill == 'New Ref' ||
                                            _selectedbill == 'Agst Ref') {
                                          isVisibleDueDate = true;
                                          isVisibleBillNo = true;
                                        } else {
                                          isVisibleDueDate = false;
                                          isVisibleBillNo = false;
                                          billNoController.clear();
                                          _billduedateController.clear();
                                        }

                                        _billsFormkey = GlobalKey<FormState>();
                                      });
                                    },
                                  ),

                                  Visibility(
                                    visible: isVisibleBillNo,
                                    child: Padding(
                                      padding: const EdgeInsets.only(top: 12),
                                      child: TextFormField(
                                        controller: billNoController,
                                        validator: (value) => value!.isEmpty
                                            ? 'Please enter bill no'
                                            : null,
                                        decoration: InputDecoration(
                                          labelText: "Bill No",
                                          hintText: "Enter Bill No",
                                          labelStyle: GoogleFonts.poppins(
                                            fontSize: 12.5,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                          ),
                                          hintStyle: GoogleFonts.poppins(
                                            fontSize: 12.5,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                          ),
                                          prefixIcon: Container(
                                            margin: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              gradient: const LinearGradient(
                                                colors: [
                                                  Colors.orange,
                                                  Colors.deepOrangeAccent,
                                                ],
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: const Icon(
                                              Icons.confirmation_num_outlined,
                                              color: Colors.white,
                                              size: 20,
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
                                                horizontal: 12,
                                                vertical: 10,
                                              ),
                                        ),
                                      ),
                                    ),
                                  ),

                                  Visibility(
                                    visible: isVisibleDueDate,
                                    child: Padding(
                                      padding: const EdgeInsets.only(top: 12),
                                      child: TextFormField(
                                        controller: _billduedateController,
                                        validator: (value) {
                                          if (value!.isNotEmpty) {
                                            if (double.tryParse(value) ==
                                                null) {
                                              return 'Invalid input, please enter a number';
                                            } else if (double.parse(value) <
                                                0) {
                                              return 'Due date days cannot be negative';
                                            }
                                          }
                                          return null;
                                        },
                                        decoration: InputDecoration(
                                          labelText: "Due Date (days)",
                                          hintText: "Enter due date",
                                          labelStyle: GoogleFonts.poppins(
                                            fontSize: 13,
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
                                            decoration: BoxDecoration(
                                              gradient: const LinearGradient(
                                                colors: [
                                                  Colors.pinkAccent,
                                                  Colors.redAccent,
                                                ],
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: const Icon(
                                              Icons.calendar_today,
                                              color: Colors.white,
                                              size: 20,
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
                                                horizontal: 12,
                                                vertical: 10,
                                              ),
                                        ),
                                      ),
                                    ),
                                  ),

                                  Padding(
                                    padding: const EdgeInsets.only(top: 12),
                                    child: TextFormField(
                                      controller: billAmountController,
                                      keyboardType: TextInputType.number,
                                      validator: (value) {
                                        if (value!.isEmpty) {
                                          return 'Please enter amount';
                                        }
                                        if (!isNumeric(value)) {
                                          return 'Enter valid amount';
                                        }
                                        if (double.parse(value) == 0) {
                                          return 'Amount should not be 0';
                                        }
                                        return null;
                                      },
                                      decoration: InputDecoration(
                                        labelText: "Amount",
                                        hintText: "0",
                                        labelStyle: GoogleFonts.poppins(
                                          fontSize: 13,
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
                                              horizontal: 12,
                                              vertical: 10,
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
                                      _selectedbill = billsdata.first;
                                      isVisibleDueDate =
                                          _selectedbill == 'New Ref' ||
                                          _selectedbill == 'Agst Ref';
                                      isVisibleBillNo = isVisibleDueDate;
                                      _billduedateController.clear();
                                      billAmountController.clear();
                                    },
                                    child: Text(
                                      'Cancel',
                                      style: GoogleFonts.poppins(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ),

                                const SizedBox(width: 12),

                                Expanded(
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: app_color,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 14,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                    onPressed: () {
                                      if (_billsFormkey.currentState!
                                          .validate()) {
                                        _billsFormkey.currentState!.save();
                                        addBill();
                                      }
                                    },
                                    child: Text(
                                      "Add Bill",
                                      style: GoogleFonts.poppins(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 15,
                                      ),
                                    ),
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
    });
  }

  /* Future<void> _showChequeDetailsPopup(BuildContext context) async {
    setState(() {
      showDialog(
        context: context,
          builder: (BuildContext context) {
            return StatefulBuilder(
              builder: (context, setStateDialog) {
                return AlertDialog(
            titlePadding: EdgeInsets.zero,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),

            title:

            Column(
              children: [
                Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: app_color,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [Colors.white, Colors.white],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: const Icon(Icons.payment, color: app_color, size: 26),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "$_selectedpaymentmode Details",
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),



            content: SingleChildScrollView(
              child: Form(
                key: _chequedetailsFormkey,
                child: Column(
                  children: <Widget>[

                    // 🔹 Inst No
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: TextFormField(
                        controller: instNoController,
                        decoration: InputDecoration(
                          labelText: 'Inst No',
                          hintText: 'Enter Inst No',
                          labelStyle: GoogleFonts.poppins(
                            fontSize: 13,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10, // 👈 tighter padding
                          ),
                          filled: true,
                          fillColor: Theme.of(context).inputDecorationTheme.fillColor ?? Theme.of(context).cardColor.withOpacity(0.95),
                          prefixIcon: Container(
                            margin: const EdgeInsets.all(8),
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Colors.orange, Colors.deepOrangeAccent],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.all(Radius.circular(12)),
                            ),
                            child: const Icon(Icons.confirmation_number_outlined, color: Colors.white, size: 20),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: Theme.of(context).dividerColor, width: 1),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: app_color, width: 1.5),
                          ),
                        ),
                      ),
                    ),

                    // 🔹 Inst Date
                    Padding(
                      padding:  EdgeInsets.symmetric(vertical: 4),
                      child: TextFormField(
                        controller: instDateController,
                        readOnly: true,
                        enableInteractiveSelection: false,
                        onTap: () => _selectinstDate(context),
                        decoration: InputDecoration(
                          labelText: 'Inst Date',
                          hintText: 'Select Date',
                          labelStyle: GoogleFonts.poppins(
                            fontSize: 13,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10, // 👈 tighter padding
                          ),
                          filled: true,
                          fillColor: Theme.of(context).inputDecorationTheme.fillColor ?? Theme.of(context).cardColor.withOpacity(0.95),
                          prefixIcon: Container(
                            margin: const EdgeInsets.all(8),
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Colors.teal, Colors.cyan],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.all(Radius.circular(12)),
                            ),
                            child: const Icon(Icons.calendar_today, color: Colors.white, size: 20),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: Theme.of(context).dividerColor, width: 1),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: app_color, width: 1.5),
                          ),
                        ),
                      ),
                    ),

                    // 🔹 Bank Name
                    Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: TypeAheadField<String>(
                          suggestionsCallback: (pattern) {
                            return bankname_data.where((item) {
                              final name = item.toString().toLowerCase();
                              return name.contains(pattern.toLowerCase());
                            }).toList();
                          },

                          builder: (context, controller, focusNode) {
                            controller.text = _banknameController.text;

                            return TextField(
                              controller: controller,
                              focusNode: focusNode,
                              decoration: InputDecoration(
                                labelText: "Bank",
                                hintText: 'Search Bank',
                                labelStyle: GoogleFonts.poppins(
                                  fontSize: 13,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                                contentPadding:
                                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                filled: true,
                                fillColor: Theme.of(context).inputDecorationTheme.fillColor ?? Theme.of(context).cardColor.withOpacity(0.95),
                                prefixIcon: Container(
                                  margin: const EdgeInsets.all(8),
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [Colors.purple, Colors.deepPurpleAccent],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius: BorderRadius.all(Radius.circular(12)),
                                  ),
                                  child: const Icon(Icons.account_balance_outlined,
                                      color: Colors.white, size: 20),
                                ),
                                suffixIcon: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (controller.text.isNotEmpty)
                                      GestureDetector(
                                        onTap: () {
                                          setState(() {
                                            controller.clear();
                                            selectedbankname = "";
                                          });
                                        },
                                        child:
                                        Icon(Icons.close, color: Theme.of(context).colorScheme.onSurfaceVariant, size: 20),
                                      ),
                                    const SizedBox(width: 4),
                                    Icon(Icons.arrow_drop_down, color: Theme.of(context).colorScheme.onSurface),
                                    const SizedBox(width: 8),
                                  ],
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide:
                                  BorderSide(color: Theme.of(context).dividerColor, width: 1),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide:
                                  BorderSide(color: app_color, width: 1.5),
                                ),
                              ),
                            );
                          },

                          itemBuilder: (context, String suggestion) {
                            return ListTile(
                              title: Text(
                                suggestion,
                                style: GoogleFonts.poppins(fontSize: 13),
                              ),
                            );
                          },

                          onSelected: (String suggestion) {
                            setStateDialog(() {
                              selectedbankname = suggestion;
                              _banknameController.text = suggestion;
                            });
                          },




                          // ✅ New API uses EmptyBuilder instead of noItemsFoundBuilder
                          emptyBuilder: (context) => Padding(
                            padding: EdgeInsets.all(8.0),
                            child: Text(
                              'No matching bank found',
                              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                            ),
                          ),
                        )



                    ),

                    // 🔹 Amount
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: TextFormField(
                        controller: chequeAmountController,
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          if (value!.isEmpty) return 'Please enter amount';
                          if (double.parse(value) == 0) return 'Amount should not be 0';
                          return null;
                        },
                        decoration: InputDecoration(
                          labelText: 'Amount',
                          hintText: '0',
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10, // 👈 tighter padding
                          ),
                          labelStyle: GoogleFonts.poppins(
                            fontSize: 13,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          filled: true,
                          fillColor: Theme.of(context).inputDecorationTheme.fillColor ?? Theme.of(context).cardColor.withOpacity(0.95),
                          prefixIcon: Container(
                            margin:  EdgeInsets.all(8),
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              gradient:  LinearGradient(
                                colors: [Colors.grey, Colors.brown],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            alignment: Alignment.center,
                            child: currencySymbolWidget(
                              currencycode,
                              getCurrencySymbol(currencycode),
                              GoogleFonts.poppins(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),


                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: Theme.of(context).dividerColor, width: 1),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: app_color, width: 1.5),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 🔹 Actions
            actions: <Widget>[
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  setState(() {
                    selectedbankname = bankname_data.first;
                    _banknameController.text = selectedbankname;
                    instNoController.clear();
                    instdate = DateTime.now();
                    instdatestring = _dateFormat.format(instdate);
                    instdatetxt = formatlastsaledate(instdatestring);
                    instDateController.text = instdatetxt;
                    chequeAmountController.clear();
                  });
                },
                child: Text('Cancel', style: GoogleFonts.poppins(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: app_color,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                ),
                onPressed: () {
                  if (_chequedetailsFormkey.currentState != null &&
                      _chequedetailsFormkey.currentState!.validate()) {
                    _chequedetailsFormkey.currentState!.save();
                    addCheque();
                  }
                },
                child: Text(
                  'Add $_selectedpaymentmode',
                  style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          );
        },);}
      );
    });
  }*/

  Future<void> _showChequeDetailsPopup(BuildContext context) async {
    setState(() {
      showModalBottomSheet(
        useSafeArea: true,
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
                  sheetHeight = 0.90;
                } else if (screenHeight < 850) {
                  sheetHeight = 0.74;
                } else {
                  sheetHeight = 0.64;
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
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: app_color,
                            ),
                            child: const Icon(
                              Icons.payment,
                              color: Colors.white,
                              size: 26,
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],

                        Text(
                          "$_selectedpaymentmode Details",
                          style: GoogleFonts.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                          textAlign: TextAlign.center,
                        ),

                        const SizedBox(height: 10),

                        Expanded(
                          child: SingleChildScrollView(
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.manual,
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                            child: Form(
                              key: _chequedetailsFormkey,
                              child: Column(
                                children: <Widget>[
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                    child: TextFormField(
                                      controller: instNoController,
                                      decoration: InputDecoration(
                                        labelText: 'Inst No',
                                        hintText: 'Enter Inst No',
                                        labelStyle: GoogleFonts.poppins(
                                          fontSize: 13,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 10,
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
                                        prefixIcon: Container(
                                          margin: const EdgeInsets.all(8),
                                          decoration: const BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: [
                                                Colors.orange,
                                                Colors.deepOrangeAccent,
                                              ],
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                            ),
                                            borderRadius: BorderRadius.all(
                                              Radius.circular(12),
                                            ),
                                          ),
                                          child: const Icon(
                                            Icons.confirmation_number_outlined,
                                            color: Colors.white,
                                            size: 20,
                                          ),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            14,
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

                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 4,
                                    ),
                                    child: TextFormField(
                                      controller: instDateController,
                                      readOnly: true,
                                      enableInteractiveSelection: false,
                                      onTap: () => _selectinstDate(context),
                                      decoration: InputDecoration(
                                        labelText: 'Inst Date',
                                        hintText: 'Select Date',
                                        labelStyle: GoogleFonts.poppins(
                                          fontSize: 13,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 10,
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
                                        prefixIcon: Container(
                                          margin: const EdgeInsets.all(8),
                                          decoration: const BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: [
                                                Colors.teal,
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
                                            Icons.calendar_today,
                                            color: Colors.white,
                                            size: 20,
                                          ),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            14,
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

                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 4,
                                    ),
                                    child: TypeAheadField<String>(
                                      suggestionsCallback: (pattern) {
                                        return bankname_data.where((item) {
                                          final name = item
                                              .toString()
                                              .toLowerCase();
                                          return name.contains(
                                            pattern.toLowerCase(),
                                          );
                                        }).toList();
                                      },
                                      builder: (context, controller, focusNode) {
                                        controller.text =
                                            _banknameController.text;

                                        return TextField(
                                          controller: controller,
                                          focusNode: focusNode,
                                          decoration: InputDecoration(
                                            labelText: "Bank",
                                            hintText: 'Search Bank',
                                            labelStyle: GoogleFonts.poppins(
                                              fontSize: 13,
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.onSurfaceVariant,
                                            ),
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                  horizontal: 12,
                                                  vertical: 10,
                                                ),
                                            filled: true,
                                            fillColor:
                                                Theme.of(context)
                                                    .inputDecorationTheme
                                                    .fillColor ??
                                                (Theme.of(context)
                                                        .inputDecorationTheme
                                                        .fillColor ??
                                                    Colors.white.withOpacity(
                                                      0.95,
                                                    )),
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
                                                  Radius.circular(12),
                                                ),
                                              ),
                                              child: const Icon(
                                                Icons.account_balance_outlined,
                                                color: Colors.white,
                                                size: 20,
                                              ),
                                            ),
                                            suffixIcon: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                if (controller.text.isNotEmpty)
                                                  GestureDetector(
                                                    onTap: () {
                                                      setState(() {
                                                        controller.clear();
                                                        selectedbankname = "";
                                                      });
                                                    },
                                                    child: Icon(
                                                      Icons.close,
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .onSurfaceVariant,
                                                      size: 20,
                                                    ),
                                                  ),
                                                const SizedBox(width: 4),
                                                Icon(
                                                  Icons.arrow_drop_down,
                                                  color: Theme.of(
                                                    context,
                                                  ).colorScheme.onSurface,
                                                ),
                                                const SizedBox(width: 8),
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
                                                ),
                                              ),
                                            );
                                          },
                                      onSelected: (String suggestion) {
                                        FocusScope.of(context).unfocus();

                                        setStateDialog(() {
                                          selectedbankname = suggestion;
                                          _banknameController.text = suggestion;
                                        });
                                      },
                                      emptyBuilder: (context) => Padding(
                                        padding: EdgeInsets.all(8.0),
                                        child: Text(
                                          'No matching bank found',
                                          style: TextStyle(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),

                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 4,
                                    ),
                                    child: TextFormField(
                                      controller: chequeAmountController,
                                      keyboardType: TextInputType.number,
                                      validator: (value) {
                                        if (value!.isEmpty) {
                                          return 'Please enter amount';
                                        }
                                        if (double.parse(value) == 0) {
                                          return 'Amount should not be 0';
                                        }
                                        return null;
                                      },
                                      decoration: InputDecoration(
                                        labelText: 'Amount',
                                        hintText: '0',
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 10,
                                            ),
                                        labelStyle: GoogleFonts.poppins(
                                          fontSize: 13,
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
                                        prefixIcon: Container(
                                          margin: const EdgeInsets.all(8),
                                          width: 32,
                                          height: 32,
                                          decoration: BoxDecoration(
                                            gradient: const LinearGradient(
                                              colors: [
                                                Colors.grey,
                                                Colors.brown,
                                              ],
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          alignment: Alignment.center,
                                          child: currencySymbolWidget(
                                            currencycode,
                                            getCurrencySymbol(currencycode),
                                            GoogleFonts.poppins(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            14,
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

                                      setState(() {
                                        selectedbankname = bankname_data.first;
                                        _banknameController.text =
                                            selectedbankname;
                                        instNoController.clear();
                                        instdate = DateTime.now();
                                        instdatestring = _dateFormat.format(
                                          instdate,
                                        );
                                        instdatetxt = formatlastsaledate(
                                          instdatestring,
                                        );
                                        instDateController.text = instdatetxt;
                                        chequeAmountController.clear();
                                      });
                                    },
                                    child: Text(
                                      'Cancel',
                                      style: GoogleFonts.poppins(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ),

                                const SizedBox(width: 12),

                                Expanded(
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: app_color,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 14,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                    onPressed: () {
                                      if (_chequedetailsFormkey.currentState !=
                                              null &&
                                          _chequedetailsFormkey.currentState!
                                              .validate()) {
                                        _chequedetailsFormkey.currentState!
                                            .save();
                                        addCheque();
                                      }
                                    },
                                    child: Text(
                                      'Add $_selectedpaymentmode',
                                      style: GoogleFonts.poppins(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
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
    });
  }

  void addBill() {
    final billAmount = billAmountController.text;
    final billName = _selectedbill;
    final billNo = billNoController.text;

    String dueDateString = '';
    if (billName == "New Ref" || billName == "Agst Ref") {
      String billDueDateinDaysString = _billduedateController.text;
      int billDueDateinDaysint = int.parse(billDueDateinDaysString);

      DateTime currentDate = DateTime.now();
      DateTime finalDate = currentDate.add(
        Duration(days: billDueDateinDaysint),
      );
      dueDateString = DateFormat('yyyyMMdd').format(finalDate);
    }

    if (billAmount.isNotEmpty) {
      // Check if a bill with name "On Account" already exists
      if (billName == "On Account" &&
          bills.any((bill) => bill.billName == "On Account")) {
        // Show message that the bill already exists
        showDialog(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: Text("Duplicate Bill"),
              content: Text(
                "A bill with the name 'On Account' already exists.",
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: Text("OK"),
                ),
              ],
            );
          },
        );
        return; // Exit the function without adding the bill
      }

      // Create a new bill
      Navigator.of(context).pop();
      double parsedAmount = double.parse(billAmount.replaceAll(',', ''));
      final newBill = Bills(
        billName: billName,
        billAmount: parsedAmount,
        billNo: (billName == "New Ref" || billName == "Agst Ref")
            ? billNo
            : null,
        billDueDate: (billName == "New Ref" || billName == "Agst Ref")
            ? dueDateString
            : null,
      );

      // Add the new bill to the list and update the total bill amount
      setState(() {
        bills.add(newBill);
        // Update visibility of bill heading
        isVisibleBillHeading = bills.isNotEmpty;
        totalBillAmount = bills.fold(0.0, (double previousAmount, Bills bill) {
          return previousAmount + bill.billAmount;
        });
        // Update formatted total amount
        roundedtotalBillAmount = double.parse(
          totalBillAmount.toStringAsFixed(decimal),
        );
        NumberFormat formatter = NumberFormat(
          '#,##0.${'0' * decimal}',
          'en_US',
        );
        String formattedtotal = formatter.format(roundedtotalBillAmount);
        controller_totalamt.text = formattedtotal.toString();
      });

      // Reset selected bill and visibility of due date and bill number
      setState(() {
        _selectedbill = billsdata.first;
        isVisibleDueDate =
            (_selectedbill == 'New Ref' || _selectedbill == "Agst Ref");
        isVisibleBillNo =
            (_selectedbill == "Agst Ref" || _selectedbill == 'New Ref');
        if (_selectedbankcashname != null && isSelectedBankCashInHand) {
          isPaymentModeVisible = false;
          _selectedpaymentmode = paymentmode_data.isNotEmpty ? paymentmode_data.first : '';
          cheque.clear();
          updateChequeAmount();
          isVisibleChequeHeading = false;
          isChequeVisible = false;
        } else {
          if (bills.isNotEmpty) {
            if (cheque.isNotEmpty) {
              isPaymentModeVisible = true;
              isChequeVisible = true;
              isVisibleChequeHeading = true;
            } else {
              isPaymentModeVisible = true;
              _selectedpaymentmode = paymentmode_data.isNotEmpty ? paymentmode_data.first : '';
              cheque.clear();
              updateChequeAmount();
              isVisibleChequeHeading = false;
              isChequeVisible = true;
            }
          } else {
            isPaymentModeVisible = true;
            _selectedpaymentmode = paymentmode_data.isNotEmpty ? paymentmode_data.first : '';
            cheque.clear();
            updateChequeAmount();
            isVisibleChequeHeading = false;
            isChequeVisible = false;
          }
        }
      });

      // Clear input fields
      billAmountController.clear();
      _billduedateController.clear();

      /*if(_selectedpaymentmode == 'Cheque/DD')
        {
          setState(() {
            isChequeVisible = true;
          });
        }
      else
        {
          setState(() {
            isChequeVisible = false;
          });
        }*/
    }
  } // add bill function

  void addCheque() {
    final instNo = instNoController.text;
    final instDate = instdate;
    final bankName = selectedbankname;
    final chequeAmount = chequeAmountController.text;
    final paymentMode = _selectedpaymentmode;

    double parsedAmount = double.parse(chequeAmount.replaceAll(',', ''));

    String formattedAmount = parsedAmount.toStringAsFixed(decimal);

    double formattedAmountDouble = double.parse(formattedAmount);

    String instDateString = DateFormat('yyyyMMdd').format(instDate);

    bool hasRepeatedInstNo = isInstNoRepeated(instNo, cheque);

    double remainingchequeamount =
        roundedtotalBillAmount - roundedtotalChequeAmount;

    print(
      'before processing cheque amount $chequeAmount and roundedbillamount $roundedtotalBillAmount and roundedchequeAmount $roundedtotalChequeAmount and entered cheque amount $formattedAmountDouble and remaining cheque amount $remainingchequeamount',
    );

    if (chequeAmount.isNotEmpty &&
        roundedtotalChequeAmount <= roundedtotalBillAmount &&
        roundedtotalChequeAmount != roundedtotalBillAmount &&
        !hasRepeatedInstNo &&
        formattedAmountDouble <= roundedtotalBillAmount &&
        formattedAmountDouble <= remainingchequeamount) {
      Navigator.of(context).pop();

      final newCheque = Cheque(
        date: receiptdatestring,
        paymentFavouring: _selectedparty,
        bankPartyName: _selectedparty,

        instno: instNo,
        instdate: instDateString,
        bankname: bankName,
        chequeAmount: formattedAmountDouble,
        paymentMode: paymentMode,
      );

      // Add the new bill to the list and update the total bill amount
      setState(() {
        cheque.add(newCheque);
        // Update visibility of bill heading
        isVisibleChequeHeading = cheque.isNotEmpty;
        updateChequeAmount();
      });
      print(
        'after processing cheque amount $chequeAmount and roundedbillamount $roundedtotalBillAmount and roundedchequeAmount $roundedtotalChequeAmount and entered cheque amount $formattedAmountDouble and remaining cheque amount $remainingchequeamount',
      );

      // Reset selected bill and visibility of due date and bill number
      setState(() {
        instNoController.clear();
        instdate = DateTime.now();
        instdatestring = _dateFormat.format(instdate);
        instdatetxt = formatlastsaledate(instdatestring);
        instDateController.text = instdatetxt;
        selectedbankname = bankname_data.first;
        _banknameController.text = selectedbankname;
        chequeAmountController.clear();
      });
    } else if (formattedAmountDouble > remainingchequeamount) {
      showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text("Alert"),
            content: Text(
              "Entered $_selectedpaymentmode amount exceeds remaining total amount",
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: Text("OK", style: GoogleFonts.poppins(color: app_color)),
              ),
            ],
          );
        },
      );
      return;
    } else if (hasRepeatedInstNo) {
      showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text("Alert"),
            content: Text(
              "A cheque with the inst no '$instNo' already exists.",
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: Text("OK", style: GoogleFonts.poppins(color: app_color)),
              ),
            ],
          );
        },
      );
      return;
    } else if (roundedtotalBillAmount < 0 || roundedtotalBillAmount == 0) {
      showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text("Alert"),
            content: Text("First add bills then proceed for payment details"),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: Text("OK", style: GoogleFonts.poppins(color: app_color)),
              ),
            ],
          );
        },
      );
      return;
    } else if (roundedtotalChequeAmount == roundedtotalBillAmount) {
      showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text("Alert"),
            content: Text("Cheques for the total amount already added"),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: Text("OK", style: GoogleFonts.poppins(color: app_color)),
              ),
            ],
          );
        },
      );
      return; // Exit the function without adding the bill
    } else if (formattedAmountDouble > roundedtotalBillAmount) {
      showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text("Alert"),
            content: Text(
              "Entered $_selectedpaymentmode amount should not be greater than total amount",
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: Text("OK", style: GoogleFonts.poppins(color: app_color)),
              ),
            ],
          );
        },
      );
      return;
    }
  } // add cheque function

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
      bankname_data.sort((a, b) {
        if (a == 'Not Applicable') {
          return -1; // 'Not Applicable' comes before everything else
        } else if (b == 'Not Applicable') {
          return 1; // 'Not Applicable' comes before everything else
        } else {
          return a.compareTo(b); // Compare other elements alphabetically
        }
      });

      decimal = prefs.getInt('decimalplace') ?? 2;

      paymentmode_data.add("ATM");
      paymentmode_data.add("Card");
      paymentmode_data.add('Cheque/DD');
      _selectedpaymentmode = paymentmode_data.isNotEmpty ? paymentmode_data.first : '';

      billAmountController.clear();

      receiptdate = DateTime.parse(data['DATE']);
      receiptdatestring = _dateFormat.format(receiptdate);
      receiptdatetxt = formatlastsaledate(receiptdatestring);
      _dateController.text = receiptdatetxt;

      instdate = DateTime.now();
      instdatestring = _dateFormat.format(instdate);
      instdatetxt = formatlastsaledate(instdatestring);
      instDateController.text = instdatetxt;

      _billduedateController.clear();

      SecuritybtnAcessHolder = prefs.getString('secbtnaccess');

      String? email_nav = prefs.getString('email_nav');
      String? name_nav = prefs.getString('name_nav');

      /*print('hostname: $hostname');*/

      HttpURL_loadData =
          '$hostname/api/entry/getReceiptData/$company_lowercase/$serial_no';
      /*HttpURL_loadData = 'http://192.168.2.110:4999/api/entry/getReceiptData/$company_lowercase/$serial_no';*/

      HttpURL_receiptEntry =
          '$hostname/api/entry/updateEntry/$company_lowercase/$serial_no';
      /*HttpURL_receiptEntry = 'http://192.168.2.110:4999/api/entry/create/demonewformobilepp/767060064';*/

      HttpURL_fetchvchnos =
          '$hostname/api/entry/nos/$company_lowercase/$serial_no';
      /*HttpURL_fetchvchnos = 'http://192.168.2.110:4999/api/entry/nos/$company_lowercase/$serial_no';*/

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
    _initSharedPreferences();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialDataLoaded) {
      return Scaffold(
        bottomNavigationBar: const AppBottomNav(
          activeTab: AppBottomNavTab.entries,
          activeEntryType: AppEntryType.receipt,
        ),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        key: _scaffoldKey,
        appBar: entryAppBar(
          context: context,
          title: "Modify Receipt Entry",
          onBack: () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => PendingReceiptEntry()),
            );
          },
        ),
        body: _buildSkeletonForm(),
      );
    }

    final NumberFormat currencyFormat = NumberFormat(
      "#,##0.${'0' * decimal}", // 👈 dynamically repeat '0' for decimal places
    );

    return Scaffold(
      bottomNavigationBar: const AppBottomNav(
        activeTab: AppBottomNavTab.entries,
        activeEntryType: AppEntryType.receipt,
      ),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      key: _scaffoldKey,
      appBar: entryAppBar(
        context: context,
        title: "Modify Receipt Entry",
        onBack: () {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => PendingReceiptEntry()),
          );
        },
      ),
      body: WillPopScope(
        onWillPop: () async {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => PendingReceiptEntry()),
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
                    margin: const EdgeInsets.only(
                      top: 8,
                      bottom: 4,
                      left: 12,
                      right: 12,
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

                Form(
                  key: _formKey,
                  child: Column(
                    children: [
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
                                    _selectreceiptDate(context);
                                  },
                          ),

                          EntryFormField(
                            label: "Voucher No.",
                            icon: isVchEditable
                                ? Icons.edit_note_rounded
                                : Icons.confirmation_num_outlined,
                            iconGradient: isVchEditable
                                ? [Colors.teal, Colors.tealAccent]
                                : [
                                    Colors.deepOrangeAccent,
                                    Colors.orangeAccent,
                                  ],
                            controller: _vchnoController,
                            readOnly: !isVchEditable,
                            enabled: isVchEditable,
                            onChanged: isVchEditable
                                ? (value) => checkVchNoExistence(value.trim())
                                : null,
                            errorText: errorMessageVchNo.isNotEmpty
                                ? errorMessageVchNo
                                : null,
                            suffixIcon: Icon(
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
                            label: "Voucher Type Name",
                            icon: Icons.receipt_long_outlined,
                            iconGradient: [
                              Colors.purpleAccent,
                              Colors.deepPurple,
                            ],
                            value:
                                _selectedvchtypename.isNotEmpty &&
                                    vchtypenamedata.contains(
                                      _selectedvchtypename,
                                    )
                                ? _selectedvchtypename
                                : null,
                            hintText: "Voucher Type Name",
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
                            onChanged: (value) {
                              if (value == null) return;
                              setState(() {
                                _selectedvchtypename = value;
                              });
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
                                suggestionsCallback: (pattern) {
                                  return partydata.where((item) {
                                    final name = item.toString().toLowerCase();
                                    return name.contains(pattern.toLowerCase());
                                  }).toList();
                                },
                                builder: (context, controller, focusNode) {
                                  if (controller.text.isEmpty &&
                                      _selectedparty.toString().isNotEmpty) {
                                    controller.text = _selectedparty;
                                  }
                                  _partyController = controller;
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
                                      labelText: "Party",
                                      hintText: 'Search',
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
                                        decoration: const BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              Colors.purple,
                                              Colors.deepOrange,
                                            ],
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                          ),
                                          borderRadius: BorderRadius.all(
                                            Radius.circular(10),
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
                                          if (controller.text.isNotEmpty)
                                            GestureDetector(
                                              onTap: () {
                                                setState(() {
                                                  controller.clear();
                                                  _selectedparty = "";
                                                });
                                              },
                                              child: Icon(
                                                Icons.close,
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.onSurfaceVariant,
                                                size: 20,
                                              ),
                                            ),
                                          const SizedBox(width: 4),
                                          Icon(
                                            Icons.arrow_drop_down,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurface,
                                          ),
                                          const SizedBox(width: 8),
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
                                        fontSize: 14,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurface,
                                      ),
                                    ),
                                  );
                                },
                                onSelected: (String suggestion) {
                                  setState(() {
                                    _selectedparty = suggestion;
                                    _partyController.text = _selectedparty;
                                  });
                                },
                                emptyBuilder: (context) => Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: Text(
                                    'No matching party found',
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),

                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            child: SizedBox(
                              width: MediaQuery.of(context).size.width,
                              child: TypeAheadField<String>(
                                suggestionsCallback: (pattern) {
                                  return bankcashname_data
                                      .where((ledger) {
                                        final name = ledger['name']!
                                            .toLowerCase();
                                        return name.contains(
                                          pattern.toLowerCase(),
                                        );
                                      })
                                      .map(
                                        (ledger) =>
                                            '${ledger['name']} (${ledger['type']})',
                                      )
                                      .toList();
                                },
                                builder: (context, controller, focusNode) {
                                  if (controller.text.isEmpty &&
                                      _selectedbankcashname != null) {
                                    controller.text =
                                        _selectedbankcashname!['name'] ?? '';
                                  }
                                  _bankcashnameController = controller;
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
                                      labelText: 'Bank / Cash Ledger',
                                      hintText: _selectedbankcashname != null
                                          ? _selectedbankcashname!['name'] ?? ''
                                          : 'Search',
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
                                        decoration: const BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              Colors.teal,
                                              Colors.blueAccent,
                                            ],
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                          ),
                                          borderRadius: BorderRadius.all(
                                            Radius.circular(10),
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
                                          if (controller.text.isNotEmpty)
                                            GestureDetector(
                                              onTap: () {
                                                setState(() {
                                                  controller.clear();
                                                  _selectedbankcashname = null;
                                                  isPaymentModeVisible = false;
                                                  isChequeVisible = false;
                                                  cheque.clear();
                                                  updateChequeAmount();
                                                });
                                              },
                                              child: Icon(
                                                Icons.close,
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.onSurfaceVariant,
                                                size: 20,
                                              ),
                                            ),
                                          const SizedBox(width: 4),
                                          Icon(
                                            Icons.arrow_drop_down,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurface,
                                          ),
                                          const SizedBox(width: 8),
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
                                        fontSize: 14,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurface,
                                      ),
                                    ),
                                  );
                                },
                                onSelected: (String suggestion) {
                                  setState(() {
                                    _selectedbankcashname = bankcashname_data
                                        .firstWhere(
                                          (ledger) =>
                                              '${ledger['name']} (${ledger['type']})' ==
                                              suggestion,
                                        );
                                    _bankcashnameController.text =
                                        _selectedbankcashname!['name'] ?? '';

                                    if (_selectedbankcashname != null &&
                                        isSelectedBankCashInHand) {
                                      isPaymentModeVisible = false;
                                      _selectedpaymentmode = paymentmode_data.isNotEmpty
                                          ? paymentmode_data.first
                                          : '';
                                      cheque.clear();
                                      updateChequeAmount();
                                      isVisibleChequeHeading = false;
                                      isChequeVisible = false;
                                    } else if (bills.isNotEmpty) {
                                      isPaymentModeVisible = true;
                                      isChequeVisible = true;
                                      isVisibleChequeHeading =
                                          cheque.isNotEmpty;
                                    } else {
                                      isPaymentModeVisible = true;
                                      _selectedpaymentmode = paymentmode_data.isNotEmpty
                                          ? paymentmode_data.first
                                          : '';
                                      cheque.clear();
                                      updateChequeAmount();
                                      isVisibleChequeHeading = false;
                                      isChequeVisible = false;
                                    }
                                  });
                                },
                                emptyBuilder: (context) => Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: Text(
                                    'No matching Bank/Cash name found',
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),

                      EntrySection(
                        icon: Icons.receipt_long,
                        title: "Bills",
                        iconGradient: [Colors.blueGrey, Colors.grey],
                        trailing: GestureDetector(
                          onTap: () {
                            _selectedbill = billsdata.first;
                            if (_selectedbill == 'New Ref' ||
                                _selectedbill == 'Agst Ref') {
                              setState(() {
                                isVisibleDueDate = true;
                                isVisibleBillNo = true;
                              });
                            } else {
                              setState(() {
                                isVisibleDueDate = false;
                                isVisibleBillNo = false;
                              });
                            }
                            billAmountController.clear();
                            billNoController.clear();
                            _billduedateController.clear();
                            _showBillsDetailsPopup(context);
                          },
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                colors: [Colors.orange, Colors.deepOrange],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.orange.withValues(alpha: 0.3),
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
                            itemCount: bills.length,
                            itemBuilder: (context, index) {
                              final bill = bills[index];
                              final bool showBillNo =
                                  (bill.billName == "Agst Ref" ||
                                      bill.billName == "New Ref") &&
                                  bill.billNo != 'null' &&
                                  bill.billNo != '';
                              return Dismissible(
                                key: UniqueKey(),
                                direction: DismissDirection.endToStart,
                                background: Container(
                                  alignment: Alignment.centerRight,
                                  padding: const EdgeInsets.only(right: 24),
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [
                                        Color(0xFFFF6B6B),
                                        Color(0xFFEE5A24),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: const Icon(
                                    Icons.delete_outline,
                                    color: Colors.white,
                                    size: 26,
                                  ),
                                ),
                                onDismissed: (direction) => _deleteBill(index),
                                child: Container(
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 4,
                                  ),
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).cardColor,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: Theme.of(context).dividerColor,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.03,
                                        ),
                                        blurRadius: 6,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            flex: 5,
                                            child: Text(
                                              bill.billName,
                                              style: GoogleFonts.poppins(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.onSurface,
                                              ),
                                            ),
                                          ),
                                          Expanded(
                                            flex: 5,
                                            child: Text(
                                              "Bill No: ${showBillNo ? bill.billNo ?? "N/A" : "N/A"}",
                                              textAlign: TextAlign.end,
                                              style: GoogleFonts.poppins(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w500,
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.onSurfaceVariant,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      Row(
                                        children: [
                                          Container(
                                            width: 26,
                                            height: 26,
                                            decoration: const BoxDecoration(
                                              shape: BoxShape.circle,
                                              gradient: LinearGradient(
                                                colors: [
                                                  Colors.teal,
                                                  Colors.cyan,
                                                ],
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                              ),
                                            ),
                                            alignment: Alignment.center,
                                            child: currencySymbolWidget(
                                              currencycode,
                                              getCurrencySymbol(currencycode),
                                              GoogleFonts.poppins(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            currencyFormat.format(
                                              bill.billAmount,
                                            ),
                                            style: GoogleFonts.poppins(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w600,
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.onSurface,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),

                      Visibility(
                        visible:
                            isPaymentModeVisible && !isSelectedBankCashInHand,
                        child: EntrySection(
                          icon: Icons.payment_outlined,
                          title: "Payment Mode",
                          iconGradient: [Colors.teal, Colors.indigo],
                          children: [
                            EntryDropdownField<String>(
                              label: "Payment Mode",
                              icon: Icons.payment_outlined,
                              iconGradient: [Colors.teal, Colors.indigo],
                              value:
                                  paymentmode_data.contains(
                                    _selectedpaymentmode,
                                  )
                                  ? _selectedpaymentmode
                                  : null,
                              hintText: 'Select Payment Mode',
                              items: paymentmode_data.map((item) {
                                return DropdownMenuItem<String>(
                                  value: item.toString(),
                                  child: Text(
                                    item.toString(),
                                    style: GoogleFonts.poppins(
                                      fontSize: 14,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface,
                                    ),
                                  ),
                                );
                              }).toList(),
                              onChanged: (value) async {
                                setState(() {
                                  _selectedpaymentmode = value!;
                                });
                                if (bills.isEmpty) {
                                  showAppMessage(
                                    context,
                                    'At least add 1 bill',
                                  );
                                  isChequeVisible = false;
                                  selectedbankname = bankname_data.first;
                                  _banknameController.text = selectedbankname;
                                  instNoController.clear();
                                  instdate = DateTime.now();
                                  instdatestring = _dateFormat.format(instdate);
                                  instdatetxt = formatlastsaledate(
                                    instdatestring,
                                  );
                                  instDateController.text = instdatetxt;
                                  chequeAmountController.clear();
                                  cheque.clear();
                                  updateChequeAmount();
                                } else {
                                  setState(() {
                                    isChequeVisible = true;
                                  });
                                }
                              },
                            ),
                          ],
                        ),
                      ),

                      Visibility(
                        visible: isChequeVisible,
                        child: EntrySection(
                          icon: Icons.payment,
                          title: _selectedpaymentmode,
                          iconGradient: [
                            Colors.purpleAccent,
                            Colors.deepPurple,
                          ],
                          trailing: GestureDetector(
                            onTap: () => _showChequeDetailsPopup(context),
                            child: Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: const LinearGradient(
                                  colors: [
                                    Colors.orange,
                                    Colors.deepOrangeAccent,
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.orange.withValues(alpha: 0.3),
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
                              itemCount: cheque.length,
                              itemBuilder: (context, index) {
                                final cheques = cheque[index];
                                final bool showInstNo =
                                    !(cheques.instno == "null" ||
                                        cheques.instno.isEmpty ||
                                        cheques.instno == "");
                                return Dismissible(
                                  key: UniqueKey(),
                                  direction: DismissDirection.endToStart,
                                  background: Container(
                                    alignment: Alignment.centerRight,
                                    padding: const EdgeInsets.only(right: 24),
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [
                                          Color(0xFFFF6B6B),
                                          Color(0xFFEE5A24),
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: const Icon(
                                      Icons.delete_outline,
                                      color: Colors.white,
                                      size: 26,
                                    ),
                                  ),
                                  onDismissed: (direction) {
                                    setState(() {
                                      cheque.removeAt(index);
                                      updateChequeAmount();
                                      isVisibleChequeHeading =
                                          cheque.isNotEmpty;
                                    });
                                  },
                                  child: Container(
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 4,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 12,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).cardColor,
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color:
                                            Theme.of(context).brightness ==
                                                Brightness.dark
                                            ? Colors.white.withValues(
                                                alpha: 0.08,
                                              )
                                            : Colors.grey.shade200,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(
                                            alpha: 0.03,
                                          ),
                                          blurRadius: 6,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Flexible(
                                              child: Row(
                                                children: [
                                                  const Icon(
                                                    Icons
                                                        .confirmation_num_outlined,
                                                    color: Colors.deepPurple,
                                                    size: 18,
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Flexible(
                                                    child: Text(
                                                      "Inst No: ${showInstNo ? cheques.instno : "N/A"}",
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style:
                                                          GoogleFonts.poppins(
                                                            fontSize: 13,
                                                            fontWeight:
                                                                FontWeight.w500,
                                                            color:
                                                                Theme.of(
                                                                      context,
                                                                    )
                                                                    .colorScheme
                                                                    .onSurface,
                                                          ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Flexible(
                                              child: Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.end,
                                                children: [
                                                  const Icon(
                                                    Icons.date_range,
                                                    color: Colors.teal,
                                                    size: 18,
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Flexible(
                                                    child: Text(
                                                      formatdate(
                                                        cheques.instdate ?? '',
                                                      ),
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style:
                                                          GoogleFonts.poppins(
                                                            fontSize: 13,
                                                            fontWeight:
                                                                FontWeight.w500,
                                                            color:
                                                                Theme.of(
                                                                      context,
                                                                    )
                                                                    .colorScheme
                                                                    .onSurface,
                                                          ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            Container(
                                              width: 26,
                                              height: 26,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                gradient: LinearGradient(
                                                  colors: [
                                                    Colors.deepPurple.shade400,
                                                    Colors.blue.shade600,
                                                  ],
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                ),
                                              ),
                                              child: Center(
                                                child: currencySymbolWidget(
                                                  currencycode,
                                                  getCurrencySymbol(
                                                    currencycode,
                                                  ),
                                                  GoogleFonts.poppins(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 11,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              currencyFormat.format(
                                                cheques.chequeAmount,
                                              ),
                                              style: GoogleFonts.poppins(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.onSurface,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),

                      EntrySection(
                        icon: Icons.notes_rounded,
                        title: "Narration",
                        iconGradient: [Colors.deepPurple, Colors.indigo],
                        children: [
                          EntryFormField(
                            label: "Narration",
                            icon: Icons.notes_rounded,
                            iconGradient: [Colors.deepPurple, Colors.indigo],
                            controller: controller_narration,
                            validator: (value) => null,
                            maxLines: 3,
                          ),
                        ],
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

            if (_isLoading)
              Positioned.fill(
                child: Container(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  child: _buildSkeletonForm(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Skeleton stand-in for the modify-entry form while the existing voucher's
  // data (and dependent dropdown data) is being fetched - replaces the old
  // dimmed spinner-over-stale-content overlay. Mirrors the generic
  // label + input-box shape of the form fields rather than a list-card shape.
  Widget _buildSkeletonForm() {
    return ShimmerLoading(
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          for (int i = 0; i < 6; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const ShimmerBox(height: 12, width: 100),
                  const SizedBox(height: 8),
                  const ShimmerBox(height: 44, borderRadius: 10),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
