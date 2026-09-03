import 'package:FincoreGo/Items.dart';
import 'package:FincoreGo/constants.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:open_file/open_file.dart';
import 'package:share_plus/share_plus.dart';
import 'Dashboard.dart';
import 'PendingReceiptEntry.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:FincoreGo/widgets/app_bottom_nav.dart';
import 'widgets/entry_widgets.dart';
import 'providers/modify_receipt_entry_notifier.dart';

// Migration note (legacy Node backend -> tally-api): this screen used to
// receive `id`/`isSynced`/`type` alongside the raw Tally-XML-shaped `data`
// blob (PARTYLEDGERNAME/ALLLEDGERENTRIES.LIST/etc, straight from the local
// pending-entries queue PendingReceiptEntry.dart kept). tally-api's
// VoucherEntry family has no local "unsynced" queue - every row returned by
// VoucherEntryRepository.listAll()/getById() already lives on the server,
// so `isSynced`/`type` have no equivalent here and were dropped. The caller
// (PendingReceiptEntry.dart, migrated separately) must now pass:
//   - `voucherEntryId`: the server's voucher-entry `id` (String/UUID) -
//     used for the PATCH .../voucher-entries/:id call on Update.
//   - `data`: the full server-shaped row exactly as returned by
//     VoucherEntryRepository.instance.listAll()/getById() (camelCase
//     fields, nested `ledgerEntries[].billAllocations`/`bankAllocations`
//     with resolved `ledgerName`s) - see voucher-entry.schema.ts.
class ModifyReceiptEntry extends ConsumerStatefulWidget {
  final String voucherEntryId;
  final Map<String, dynamic> data;
  const ModifyReceiptEntry({
    required this.voucherEntryId,
    required this.data,
  });
  @override
  ConsumerState<ModifyReceiptEntry> createState() =>
      _ModifyReceiptEntryPageState();
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

class _ModifyReceiptEntryPageState extends ConsumerState<ModifyReceiptEntry> {
  late final _args = ModifyReceiptEntryArgs(
    id: widget.voucherEntryId,
    data: widget.data,
  );

  ModifyReceiptEntryNotifier get _notifier =>
      ref.read(modifyReceiptEntryNotifierProvider(_args).notifier);
  ModifyReceiptEntryState get _s =>
      ref.read(modifyReceiptEntryNotifierProvider(_args));

  TextEditingController _partyController = TextEditingController();

  TextEditingController _bankcashnameController = TextEditingController();

  TextEditingController billNoController = TextEditingController();

  TextEditingController _banknameController = TextEditingController();

  late final TextEditingController controller_narration =
      TextEditingController();

  final TextEditingController _vchnoController = TextEditingController();

  /// `isVchEditable` is always false in the pre-migration source (the "edit
  /// voucher number" button's `onPressed` is a no-op) - kept exactly as-is,
  /// not fixed (see `modify_receipt_entry_notifier.dart`'s doc-comment).
  bool isVchEditable = false;

  Future<void> _selectDateRangeVchNo(BuildContext context) async {
    final vm = _s;
    final initialDateRange = DateTimeRange(
      start: vm.yearStartDate,
      end: vm.yearEndDate,
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
      _notifier.setVchNoDateRange(
        selectedDateRange.start,
        selectedDateRange.end,
      );
      fetchvchnos(_s.selectedVchTypeName);
    }
  }

  void checkVchNoExistence(String vchNo) {
    _notifier.checkVchNoExistence(vchNo);
  }

  /// Thin wrapper around [ModifyReceiptEntryNotifier.fetchVchNos] - the
  /// original also conditionally called [checkVchNoExistence] afterward
  /// when `isVchEditable` (always false), kept here unchanged.
  Future<void> fetchvchnos(String vchname) async {
    final error = await _notifier.fetchVchNos(vchname);
    if (error != null && mounted) {
      showAppMessage(context, error);
    }
    if (isVchEditable) {
      checkVchNoExistence(_vchnoController.text);
    }
  }

  final _formKey = GlobalKey<FormState>();

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

  String selectedbankname = '';

  // ---- read-only aliases/getters delegating to the notifier's state -----
  List<String> get vchtypenamedata => _s.vchTypeNameData;
  List<String> get partydata => _s.partyData;
  List<Map<String, String>> get bankcashname_data => _s.bankCashNameData;
  List<String> get paymentmode_data => _s.paymentModeData;
  List<String> get bankname_data => _s.bankNameData;

  List<Bills> get bills => _s.bills;
  List<Cheque> get cheque => _s.cheque;

  double get totalBillAmount => _s.totalBillAmount;
  double get roundedtotalBillAmount => _s.roundedTotalBillAmount;
  double get totalChequeAmount => _s.totalChequeAmount;
  double get roundedtotalChequeAmount => _s.roundedTotalChequeAmount;

  bool get isVisibleBillHeading => _s.isVisibleBillHeading;
  bool get isVisibleChequeHeading => _s.isVisibleChequeHeading;
  bool get isChequeVisible => _s.isChequeVisible;
  bool get isPaymentModeVisible => _s.isPaymentModeVisible;

  bool get _isLoading => _s.isLoading;
  bool get _isInitialDataLoaded => _s.isInitialDataLoaded;

  String? get company => _s.company;
  String? get serial_no => _s.serialNo;
  String get currencycode => _s.currencyCode;
  int get decimal => _s.decimal;

  DateTime get receiptdate => _s.receiptDate;
  String get receiptdatestring => _s.receiptDateString;
  String get receiptdatetxt => _s.receiptDateText;

  DateTime get yearStartDate => _s.yearStartDate;
  DateTime get yearEndDate => _s.yearEndDate;

  String get _selectedvchtypename => _s.selectedVchTypeName;
  dynamic get _selectedparty => _s.selectedParty;
  Map<String, String>? get _selectedbankcashname => _s.selectedBankCashName;
  dynamic get _selectedpaymentmode => _s.selectedPaymentMode;

  String get errorMessageVchNo => _s.errorMessageVchNo;
  List<String> get vchnos => _s.vchNos;

  bool get isSelectedBankCashInHand => _notifier.isSelectedBankCashInHand;

  List<String> billsdata = ['On Account', 'New Ref', 'Agst Ref'];

  bool isVisibleDueDate = false, isVisibleBillNo = false;

  String instdatestring = '', instdatetxt = '';

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  dynamic _selectedbill;

  late final TextEditingController controller_totalamt =
      TextEditingController();

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

  late DateTime instdate = DateTime.now();

  final DateFormat _dateFormat = DateFormat('yyyyMMdd');

  final TextEditingController billAmountController = TextEditingController();
  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _billduedateController = TextEditingController();
  final TextEditingController instDateController = TextEditingController();
  final TextEditingController instNoController = TextEditingController();
  final TextEditingController chequeAmountController = TextEditingController();

  /// Verbatim port of `_deleteBill`'s confirmation-free delete (the
  /// `_confirmBillDeletion` dialog wrapper that used to exist around this
  /// had zero call sites and was dropped - see this screen's notifier
  /// doc-comment). The data mutation (including the cascading
  /// cheque/payment-mode reset) now lives in
  /// [ModifyReceiptEntryNotifier.deleteBill]; this wrapper only resets the
  /// widget-local "Add Cheque" dialog controllers when bills end up empty,
  /// exactly like the original's `setState` did.
  void _deleteBill(int index) {
    _notifier.deleteBill(index);
    controller_totalamt.text = _s.formattedTotalBillAmount;

    if (bills.isEmpty) {
      instNoController.clear();
      selectedbankname = bankname_data.first;
      _banknameController.text = selectedbankname;
      chequeAmountController.clear();
      instdate = DateTime.now();
      instdatestring = _dateFormat.format(instdate);
      instdatetxt = formatlastsaledate(instdatestring);
      instDateController.text = instdatetxt;
    }
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
                          // This path stays on the same Modify screen (no
                          // navigation away like "No, Thanks" does), so
                          // popping the dialog without dropping focus first
                          // hands focus straight back to whichever
                          // party/ledger TypeAheadField had it before save,
                          // reopening its suggestions overlay.
                          FocusScope.of(context).requestFocus(FocusNode());
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

  /// Thin wrapper around [ModifyReceiptEntryNotifier.updateEntry] - the
  /// pre-save validation (party/bank-cash/empty-bills checks, which read
  /// `context` via `showAppMessage`) and the trailing
  /// `showReceiptVoucherUpdatedDialog` call on success stay here (pure UI),
  /// exactly matching the original's structure.
  Future<void> updateEntry(String voucherEntryId) async {
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
      return;
    }

    final error = await _notifier.updateEntry(
      voucherEntryId,
      narration: controller_narration.text,
      vchno: _vchnoController.text,
    );

    if (!mounted) return;

    if (error != null) {
      showAppMessage(context, error);
      return;
    }

    showReceiptVoucherUpdatedDialog(context);
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
      _notifier.setReceiptDate(picked);
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

  /// Thin wrapper around [ModifyReceiptEntryNotifier.addBill] - resolves
  /// the dialog's `_billduedateController` (a days-from-now offset) into a
  /// `yyyyMMdd` due-date string exactly as the original did, then shows the
  /// matching dialog/pops the sheet/resets the widget-local dialog fields
  /// based on the outcome.
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

    final outcome = _notifier.addBill(
      billAmountText: billAmount,
      billName: billName,
      billNo: billNo,
      dueDateString: dueDateString,
    );

    switch (outcome) {
      case AddBillOutcome.duplicateOnAccount:
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
        return;
      case AddBillOutcome.notAdded:
        return;
      case AddBillOutcome.added:
        Navigator.of(context).pop();
        controller_totalamt.text = _s.formattedTotalBillAmount;
        setState(() {
          _selectedbill = billsdata.first;
          isVisibleDueDate =
              (_selectedbill == 'New Ref' || _selectedbill == "Agst Ref");
          isVisibleBillNo =
              (_selectedbill == "Agst Ref" || _selectedbill == 'New Ref');
        });
        billAmountController.clear();
        _billduedateController.clear();
    }
  } // add bill function

  /// Thin wrapper around [ModifyReceiptEntryNotifier.addCheque] - the
  /// notifier owns the validation/append/total-recompute; the widget keeps
  /// the alert dialogs, the sheet pop, and resetting the Add-Cheque sheet's
  /// own controllers back to their defaults on success.
  void addCheque() {
    final instNo = instNoController.text;
    final instDate = instdate;
    final bankName = selectedbankname;
    final chequeAmount = chequeAmountController.text;
    final paymentMode = _selectedpaymentmode;

    void showChequeAlert(String message) {
      showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text("Alert"),
            content: Text(message),
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
    }

    final AddChequeOutcome outcome = _notifier.addCheque(
      instNo: instNo,
      instDate: instDate,
      bankName: bankName,
      chequeAmountText: chequeAmount,
      paymentMode: paymentMode,
    );

    switch (outcome) {
      case AddChequeOutcome.added:
        Navigator.of(context).pop();

        // Reset the Add-Cheque sheet's own fields back to their defaults
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
      case AddChequeOutcome.exceedsRemaining:
        showChequeAlert(
          "Entered $_selectedpaymentmode amount exceeds remaining total amount",
        );
      case AddChequeOutcome.duplicateInstNo:
        showChequeAlert("A cheque with the inst no '$instNo' already exists.");
      case AddChequeOutcome.noBillsYet:
        showChequeAlert("First add bills then proceed for payment details");
      case AddChequeOutcome.chequeAlreadyFullyAllocated:
        showChequeAlert("Cheques for the total amount already added");
      case AddChequeOutcome.exceedsTotal:
        showChequeAlert(
          "Entered $_selectedpaymentmode amount should not be greater than total amount",
        );
    }
  } // add cheque function

  /// One-time seeding of the widget-local controllers the moment the
  /// notifier's initial load resolves (mirrors
  /// `modify_sales_entry_notifier.dart`'s widget-side `_onStateChange`,
  /// registered the same way via `ref.listenManual` in `initState`).
  /// `_dateController` is re-synced on every state change (cheap, always
  /// correct) since [ModifyReceiptEntryNotifier.setReceiptDate] can change
  /// `receiptDateText` after the initial load too; `_vchnoController`/
  /// `controller_narration`/`controller_totalamt` are seeded exactly once,
  /// guarded on the `isInitialDataLoaded` false->true edge, so a later
  /// unrelated state change never clobbers in-progress edits to those
  /// fields.
  void _onStateChange(
    ModifyReceiptEntryState? previous,
    ModifyReceiptEntryState next,
  ) {
    _dateController.text = next.receiptDateText;

    final bool justFinishedLoading =
        (previous?.isInitialDataLoaded ?? false) == false &&
        next.isInitialDataLoaded;
    if (!justFinishedLoading) return;

    final error = _notifier.consumeInitError();
    if (error != null && mounted) {
      showAppMessage(context, error);
    }

    _vchnoController.text = next.initialVoucherNumber;
    controller_narration.text = next.initialNarration;
    controller_totalamt.text = next.formattedTotalBillAmount;

    billAmountController.clear();
    _billduedateController.clear();

    instdate = DateTime.now();
    instdatestring = _dateFormat.format(instdate);
    instdatetxt = formatlastsaledate(instdatestring);
    instDateController.text = instdatetxt;

    selectedbankname = next.bankNameData.isNotEmpty
        ? next.bankNameData.first
        : '';
    _banknameController.text = selectedbankname;

    if (next.selectedBankCashName != null) {
      _bankcashnameController.text = next.selectedBankCashName!['name'] ?? '';
    }
    if (next.selectedParty != null) {
      _partyController.text = next.selectedParty.toString();
    }
  }

  @override
  void initState() {
    super.initState();
    // Trigger provider creation (and its _init()) eagerly, matching the
    // original's initState-time kickoff rather than waiting for build().
    _notifier;
    ref.listenManual<ModifyReceiptEntryState>(
      modifyReceiptEntryNotifierProvider(_args),
      _onStateChange,
      fireImmediately: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(modifyReceiptEntryNotifierProvider(_args));
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
                              _notifier.setSelectedVchType(value);
                              fetchvchnos(value);
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
                                                controller.clear();
                                                _notifier.clearSelectedParty();
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
                                  _notifier.selectParty(suggestion);
                                  _partyController.text = suggestion;
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
                                                controller.clear();
                                                _notifier
                                                    .clearSelectedBankCashName();
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
                                  final selected = bankcashname_data
                                      .firstWhere(
                                        (ledger) =>
                                            '${ledger['name']} (${ledger['type']})' ==
                                            suggestion,
                                      );
                                  _notifier.selectBankCashName(selected);
                                  _bankcashnameController.text =
                                      selected['name'] ?? '';
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
                                // The notifier applies the selection plus
                                // (for the empty-bills case) the
                                // cheque-list/visibility reset, and tells
                                // us which branch ran; the widget keeps
                                // the message and its own dialog-field
                                // resets.
                                final bool billsEmpty = _notifier
                                    .setSelectedPaymentMode(value!);
                                if (billsEmpty) {
                                  showAppMessage(
                                    context,
                                    'At least add 1 bill',
                                  );
                                  setState(() {
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
                                  onDismissed: (direction) =>
                                      _notifier.deleteCheque(index),
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
                                  updateEntry(widget.voucherEntryId);
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
