import 'dart:convert';
import 'package:FincoreGo/Items.dart';
import 'package:FincoreGo/currencyFormat.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'PartyClickedRecPayClicked.dart';
import 'PartyClickedSalePurcOrder.dart';
import 'PartyClickedSoldPurchaseClicked.dart';
import 'PartyDrillDown.dart';
import 'PartyTotalClickedRest.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'constants.dart';
import 'theme_controller.dart';
import 'package:FincoreGo/widgets/app_bottom_nav.dart';
import 'package:FincoreGo/widgets/app_navigation.dart';

class Summary {
  final String vchtype, totalInvoice, averageAmount, lastdate, totalAmount;

  Summary({
    required this.vchtype,
    required this.totalInvoice,
    required this.averageAmount,
    required this.lastdate,
    required this.totalAmount,
  });

  factory Summary.fromJson(Map<String, dynamic> json) {
    return Summary(
      vchtype: json['vchtype'].toString(),
      totalInvoice: json['totalInvoice'].toString(),
      averageAmount: json['averageAmount'].toString(),
      lastdate: json['lastdate'].toString(),
      totalAmount: json['totalAmount'].toString(),
    );
  }
}

class Sold_Purchased {
  final String item, qty, unit, lastdate, rate;

  Sold_Purchased({
    required this.item,
    required this.qty,
    required this.unit,
    required this.lastdate,
    required this.rate,
  });

  factory Sold_Purchased.fromJson(Map<String, dynamic> json) {
    return Sold_Purchased(
      item: json['item'].toString(),
      qty: json['qty'].toString(),
      unit: json['unit'].toString(),
      lastdate: json['lastdate'].toString(),
      rate: json['rate'].toString(),
    );
  }
}

class months {
  final String mname, total;

  months({required this.mname, required this.total});

  factory months.fromJson(Map<String, dynamic> json) {
    return months(
      mname: json['mname'].toString(),
      total: json['total'].toString(),
    );
  }
}

class Rec_Pay {
  final String mname, total;

  Rec_Pay({required this.mname, required this.total});

  factory Rec_Pay.fromJson(Map<String, dynamic> json) {
    return Rec_Pay(
      mname: json['mname'].toString(),
      total: json['total'].toString(),
    );
  }
}

class PartyClicked extends StatefulWidget {
  final String partyname;
  const PartyClicked({required this.partyname});
  @override
  _PartyClickedPageState createState() =>
      _PartyClickedPageState(partyname: partyname);
}

class _PartyClickedPageState extends State<PartyClicked>
    with TickerProviderStateMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  String partyname = "";

  String startDateString = "", endDateString = "";
  String totalsales = "";
  String vchtypes = "purchase" + "," + "sales", token = '';
  String HttpURL_SummaryContent = "",
      HttpURL_months = "",
      HttpURL_receivablepayable_total = "",
      HttpURL_receivablepayable = "",
      HttpURL_salespurchaseorder = "";

  bool isExpanded_Sales = false;
  String lastsaledate = "",
      noofsalesinvoice = "0",
      avgsalesinvoiceamt = "0",
      totalsaleamt = "0";
  String lastpurchasedate = "",
      noofpurchaseinvoice = "0",
      avgpurchaseinvoiceamt = "0",
      totalpurchaseamt = "0";
  String lastreceiptdate = "",
      noofreceiptinvoice = "0",
      avgreceiptinvoiceamt = "0",
      totalreceiptamt = "0";
  String lastpaymentdate = "",
      noofpaymentinvoice = "0",
      avgpaymentinvoiceamt = "0",
      totalpaymentamt = "0";
  String lastcreditnotedate = "",
      noofcreditnoteinvoice = "0",
      avgcreditnoteinvoiceamt = "0",
      totalcreditnoteamt = "0";
  String lastdebitnotedate = "",
      noofdebitnoteinvoice = "0",
      avgdebitnoteinvoiceamt = "0",
      totaldebitnoteamt = "0";
  String lastjournaldate = "",
      noofjournalinvoice = "0",
      avgjournalinvoiceamt = "0",
      totaljournalamt = "0";

  String receivabletotal = "0",
      onAccountReceivable = "0",
      row1_receivable = "0",
      row2_receivable = "0",
      row3_receivable = "0",
      row4_receivable = "0",
      row5_receivable = "0",
      row6_receivable = "0",
      row1_receivable_heading = "180",
      row2_receivable_heading = "120",
      row3_receivable_heading = "90",
      row4_receivable_heading = "60",
      row5_receivable_heading = "30",
      row6_receivable_heading = "0",
      row1_receivable_heading_value = "180",
      row2_receivable_heading_value = "120",
      row3_receivable_heading_value = "90",
      row4_receivable_heading_value = "60",
      row5_receivable_heading_value = "30",
      row6_receivable_heading_value = "0";

  String payabletotal = "0",
      onAccountPayable = "0",
      row1_payable = "0",
      row2_payable = "0",
      row3_payable = "0",
      row4_payable = "0",
      row5_payable = "0",
      row6_payable = "0",
      row1_payable_heading = "180",
      row2_payable_heading = "120",
      row3_payable_heading = "90",
      row4_payable_heading = "60",
      row5_payable_heading = "30",
      row6_payable_heading = "0",
      row1_payable_heading_value = "180",
      row2_payable_heading_value = "120",
      row3_payable_heading_value = "90",
      row4_payable_heading_value = "60",
      row5_payable_heading_value = "30",
      row6_payable_heading_value = "0";

  int counter = 0;

  late int? decimal;
  late NumberFormat currencyFormat;
  late String currencysymbol = '';

  bool isVisibleSoldBtn = false, isVisiblePurchaseBtn = false;

  bool isNoAccessVisible = false;

  bool isClicked_Summary = true,
      isClicked_Sold = false,
      isClicked_Purchase = false,
      isVisibleSoldList = false,
      isVisiblePurchaseList = false;

  bool SalesVisibility = false,
      PurchaseVisibility = false,
      ReceiptVisibility = false,
      PaymentVisibility = false,
      CreditnoteVisibility = false,
      DebitnoteVisibility = false,
      JournalVisibility = false,
      ReceivableVisibility = false,
      PayableVisibility = false,
      SalesOrderVisibility = false,
      PurchaseOrderVisibility = false;

  String pendingsalesorder = "0", pendingpurchaseorder = "0";

  dynamic _selecteddate;

  List<Sold_Purchased> filteredItems_sold = [];
  List<Sold_Purchased> sold_list = [];

  List<Sold_Purchased> filteredItems_purchase = [];
  List<Sold_Purchased> purchase_list = [];

  String item_count = "0";

  bool _isSearchViewVisible = false, isSearchLayoutVisible = false;
  List<String> date_range = [
    'Today',
    'Yesterday',
    'This Month',
    'Last Month',
    'This Year',
    'Last Year',
    'Year To Date',
    'Custom Date',
  ];

  List<months> months_list_sales =
      []; // Initialize an empty list to hold the filtered items
  List<months> months_list_purchase =
      []; // Initialize an empty list to hold the filtered items
  List<months> months_list_receipt =
      []; // Initialize an empty list to hold the filtered items
  List<months> months_list_payment =
      []; // Initialize an empty list to hold the filtered items
  List<months> months_list_creditnote =
      []; // Initialize an empty list to hold the filtered items
  List<months> months_list_debitnote =
      []; // Initialize an empty list to hold the filtered items
  List<months> months_list_journal =
      []; // Initialize an empty list to hold the filtered items

  _PartyClickedPageState({required this.partyname});

  String? SecuritybtnAcessHolder;
  bool isDashEnable = true,
      isRolesEnable = true,
      isUserEnable = true,
      isRolesVisible = true,
      isUserVisible = true;

  String email = "";
  String name = "";

  String? opening_value = "0", openingheading = "";

  TextEditingController searchController = TextEditingController();

  bool isVisibleNoDataFound = false;

  bool isVisibleSummaryBtn = false;

  late GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey;
  late SharedPreferences prefs;
  late String startdate_text = "", enddate_text = "";
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now().add(Duration(days: 7));
  String? datetype;

  late String? startdate_pref;

  String HttpURL_sold = "";

  String? hostname = "",
      company = "",
      serial_no = "",
      company_lowercase = "",
      username = "";
  List<dynamic> myData = [];
  bool _isLoading = false;

  List<String> spinner_list = [];

  String heading1 = '',
      heading2 = '',
      heading3 = '',
      heading4 = '',
      heading5 = '';

  bool _isTextEnabled = true;

  bool _isDashVisible = true,
      _isEnddateVisible = true,
      _IsSizeboxVisible = true;

  String salesparty = '';
  String purchaseparty = '';
  String creditnoteparty = '';
  String journalparty = '';
  String payableparty = '';
  String pendingpurchaseorderparty = '';
  String receiptparty = '';
  String paymentparty = '';
  String debitnoteparty = '';
  String receivableparty = '';
  String pendingsalesorderparty = '';
  String party_suppliers = '';
  String party_customers = '';

  // ------------------------ SOLD PDF ------------------------
  Future<void> generateAndSharePDF_Sold() async {
    final font = pw.Font.ttf(
      await rootBundle.load("assets/fonts/NotoSans.ttf"),
    );
    final pdf = pw.Document();

    final companyName = company!;
    final reportname = 'Party Wise Sales Summary';
    final party_name = partyname;

    final headersRow3 = ['Item', 'Qty', 'Last Sold', 'Rate'];

    final itemsPerPage = 10;
    final pageCount = (sold_list.length / itemsPerPage).ceil();

    for (int pageNumber = 0; pageNumber < pageCount; pageNumber++) {
      final startIndex = pageNumber * itemsPerPage;
      final endIndex = (pageNumber + 1) * itemsPerPage;
      final itemsSubset = sold_list.sublist(
        startIndex,
        endIndex > sold_list.length ? sold_list.length : endIndex,
      );

      final tableSubsetRows = itemsSubset.map((item) {
        return [
          item.item,
          item.qty,
          convertDateFormat(item.lastdate),
          item.rate,
        ];
      }).toList();

      final tableSubset = pw.Table.fromTextArray(
        border: pw.TableBorder.all(width: 1),
        headerDecoration: pw.BoxDecoration(
          borderRadius: pw.BorderRadius.circular(2),
          color: PdfColors.grey300,
        ),
        headerHeight: 30,
        cellAlignment: pw.Alignment.center,
        cellPadding: pw.EdgeInsets.all(5),
        columnWidths: {
          0: pw.FractionColumnWidth(0.4),
          1: pw.FractionColumnWidth(0.4),
          2: pw.FractionColumnWidth(0.4),
          3: pw.FractionColumnWidth(0.4),
        },
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: font),
        cellStyle: pw.TextStyle(fontSize: 12, font: font),
        headers: headersRow3,
        data: tableSubsetRows,
      );

      pdf.addPage(
        pw.Page(
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Text(
                  companyName,
                  style: pw.TextStyle(
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 10),
                pw.Text(
                  reportname,
                  style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 10),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  children: [
                    pw.Text(
                      convertDateFormat(startDateString),
                      style: pw.TextStyle(fontSize: 16),
                    ),
                    pw.SizedBox(width: 5),
                    pw.Text('to', style: pw.TextStyle(fontSize: 16)),
                    pw.SizedBox(width: 5),
                    pw.Text(
                      convertDateFormat(endDateString),
                      style: pw.TextStyle(fontSize: 16),
                    ),
                  ],
                ),
                pw.SizedBox(height: 10),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  children: [
                    pw.Text(
                      'Ledger:',
                      style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(width: 5),
                    pw.Text(party_name, style: pw.TextStyle(fontSize: 16)),
                  ],
                ),
                pw.SizedBox(height: 20),
                pw.Expanded(child: tableSubset),
              ],
            );
          },
        ),
      );
    }

    final pdfData = await pdf.save();
    final tempDir = await getTemporaryDirectory();
    final tempFilePath = '${tempDir.path}/SoldReport.pdf';
    final file = File(tempFilePath);
    await file.writeAsBytes(pdfData);

    // ✅ Updated share method
    await Share.shareXFiles([
      XFile(tempFilePath),
    ], text: 'Sharing $reportname Report of $company');
  }

  // ------------------------ PURCHASE PDF ------------------------
  Future<void> generateAndSharePDF_Purchase() async {
    final font = pw.Font.ttf(
      await rootBundle.load("assets/fonts/NotoSans.ttf"),
    );
    final pdf = pw.Document();

    final companyName = company!;
    final reportname = 'Party Wise Purchase Summary';
    final party_name = partyname;
    final headersRow3 = ['Item', 'Qty', 'Last Purchased', 'Rate'];

    final itemsPerPage = 10;
    final pageCount = (purchase_list.length / itemsPerPage).ceil();

    for (int pageNumber = 0; pageNumber < pageCount; pageNumber++) {
      final startIndex = pageNumber * itemsPerPage;
      final endIndex = (pageNumber + 1) * itemsPerPage;
      final itemsSubset = purchase_list.sublist(
        startIndex,
        endIndex > purchase_list.length ? purchase_list.length : endIndex,
      );

      final tableSubsetRows = itemsSubset.map((item) {
        return [
          item.item,
          item.qty,
          convertDateFormat(item.lastdate),
          item.rate,
        ];
      }).toList();

      final tableSubset = pw.Table.fromTextArray(
        border: pw.TableBorder.all(width: 1),
        headerDecoration: pw.BoxDecoration(
          borderRadius: pw.BorderRadius.circular(2),
          color: PdfColors.grey300,
        ),
        headerHeight: 30,
        cellAlignment: pw.Alignment.center,
        cellPadding: pw.EdgeInsets.all(5),
        columnWidths: {
          0: pw.FractionColumnWidth(0.4),
          1: pw.FractionColumnWidth(0.4),
          2: pw.FractionColumnWidth(0.4),
          3: pw.FractionColumnWidth(0.4),
        },
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: font),
        cellStyle: pw.TextStyle(fontSize: 12, font: font),
        headers: headersRow3,
        data: tableSubsetRows,
      );

      pdf.addPage(
        pw.Page(
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Text(
                  companyName,
                  style: pw.TextStyle(
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 10),
                pw.Text(
                  reportname,
                  style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 10),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  children: [
                    pw.Text(
                      convertDateFormat(startDateString),
                      style: pw.TextStyle(fontSize: 16),
                    ),
                    pw.SizedBox(width: 5),
                    pw.Text('to', style: pw.TextStyle(fontSize: 16)),
                    pw.SizedBox(width: 5),
                    pw.Text(
                      convertDateFormat(endDateString),
                      style: pw.TextStyle(fontSize: 16),
                    ),
                  ],
                ),
                pw.SizedBox(height: 10),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  children: [
                    pw.Text(
                      'Ledger:',
                      style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(width: 5),
                    pw.Text(party_name, style: pw.TextStyle(fontSize: 16)),
                  ],
                ),
                pw.SizedBox(height: 20),
                pw.Expanded(child: tableSubset),
              ],
            );
          },
        ),
      );
    }

    final pdfData = await pdf.save();
    final tempDir = await getTemporaryDirectory();
    final tempFilePath = '${tempDir.path}/PurchaseReport.pdf';
    final file = File(tempFilePath);
    await file.writeAsBytes(pdfData);

    // ✅ Updated share method
    await Share.shareXFiles([
      XFile(tempFilePath),
    ], text: 'Sharing $reportname Report of $company');
  }

  // ------------------------ SOLD CSV ------------------------
  Future<void> generateAndShareCSV_Sold() async {
    final List<List<dynamic>> csvData = [];
    final reportname = 'Party Wise Sales Summary';

    final headersRow = ['Item', 'Qty', 'Last Sold', 'Rate'];
    csvData.add(headersRow);

    for (final item in sold_list) {
      final rowData = [
        item.item,
        item.qty,
        convertDateFormat(item.lastdate),
        item.rate,
      ];
      csvData.add(rowData);
    }

    final csvString = const ListToCsvConverter().convert(csvData);
    final tempDir = await Directory.systemTemp.createTemp();
    final tempFilePath = '${tempDir.path}/SoldReport.csv';
    final file = File(tempFilePath);
    await file.writeAsString(csvString);

    // ✅ Updated share method
    await Share.shareXFiles([
      XFile(tempFilePath),
    ], text: 'Sharing $reportname Report of $company');
  }

  // ------------------------ PURCHASE CSV ------------------------
  Future<void> generateAndShareCSV_Purchase() async {
    final List<List<dynamic>> csvData = [];
    final reportname = 'Party Wise Purchase Summary';

    final headersRow = ['Item', 'Qty', 'Last Purchased', 'Rate'];
    csvData.add(headersRow);

    for (final item in purchase_list) {
      final rowData = [
        item.item,
        item.qty,
        convertDateFormat(item.lastdate),
        item.rate,
      ];
      csvData.add(rowData);
    }

    final csvString = const ListToCsvConverter().convert(csvData);
    final tempDir = await Directory.systemTemp.createTemp();
    final tempFilePath = '${tempDir.path}/PurchaseReport.csv';
    final file = File(tempFilePath);
    await file.writeAsString(csvString);

    // ✅ Updated share method
    await Share.shareXFiles([
      XFile(tempFilePath),
    ], text: 'Sharing $reportname Report of $company');
  }

  Future<void> fetchsold(
    final String vchtype,
    final String ledger,
    final String startdate,
    final String enddate,
  ) async {
    setState(() {
      item_count = "0";
      _isLoading = true;
      isVisibleSoldList = false;
      isVisibleNoDataFound = false;
      _isSearchViewVisible = false;
      searchController.clear();
    });

    filteredItems_sold.clear();
    sold_list.clear();

    try {
      final url = Uri.parse(HttpURL_sold);

      Map<String, String> headers = {
        'Authorization': 'Bearer $token',
        "Content-Type": "application/json",
      };

      var body = jsonEncode({
        'vchtype': vchtype,
        'ledger': ledger,
        'startdate': startdate,
        'enddate': enddate,
      });

      final response = await http.post(url, body: body, headers: headers);

      if (response.statusCode == 200) {
        debugPrint('fetch sold response -> ${response.body}');

        final List<dynamic> values_list = jsonDecode(response.body);

        if (values_list != null) {
          sold_list.addAll(
            values_list.map((json) => Sold_Purchased.fromJson(json)).toList(),
          );
          filteredItems_sold = sold_list;

          setState(() {
            item_count = filteredItems_sold.length.toString();
            isVisibleSoldList = true;
            _isLoading = false;
          });
        } else {
          throw Exception('Failed to fetch data');
        }
      }
    } catch (e) {
      setState(() {
        isVisibleSoldList = false;
        _isLoading = false;
      });
      print(e);
    }

    setState(() {
      isVisibleNoDataFound = false;
      if (sold_list.isEmpty) {
        item_count = "0";
        isVisibleSoldList = false;

        isVisibleNoDataFound = true;
      }
      _isLoading = false;
    });
  }

  Future<void> fetchpurchase(
    final String vchtype,
    final String ledger,
    final String startdate,
    final String enddate,
  ) async {
    setState(() {
      item_count = "0";
      _isLoading = true;
      isVisiblePurchaseList = false;
      isVisibleNoDataFound = false;
      _isSearchViewVisible = false;
      searchController.clear();
    });

    filteredItems_purchase.clear();
    purchase_list.clear();

    try {
      final url = Uri.parse(HttpURL_sold!);

      Map<String, String> headers = {
        'Authorization': 'Bearer $token',
        "Content-Type": "application/json",
      };

      var body = jsonEncode({
        'vchtype': vchtype,
        'ledger': ledger,
        'startdate': startdate,
        'enddate': enddate,
      });

      final response = await http.post(url, body: body, headers: headers);
      if (response.statusCode == 200) {
        final List<dynamic> values_list = jsonDecode(response.body);

        if (values_list != null) {
          isVisibleNoDataFound = false;

          purchase_list.addAll(
            values_list.map((json) => Sold_Purchased.fromJson(json)).toList(),
          );
          filteredItems_purchase = purchase_list;

          setState(() {
            item_count = filteredItems_purchase.length.toString();
            isVisiblePurchaseList = true;
            _isLoading = false;
          });
        } else {
          throw Exception('Failed to fetch data');
        }
      }
    } catch (e) {
      setState(() {
        isVisiblePurchaseList = false;
        _isLoading = false;
      });
      print(e);
    }

    setState(() {
      if (purchase_list.isEmpty) {
        item_count = "0";
        isVisiblePurchaseList = false;
        isVisibleNoDataFound = true;
      }
      _isLoading = false;
    });
  }

  void formatRecPayTotal(String outstanding) {
    final double value = double.tryParse(outstanding) ?? 0.0;

    if (value == 0) {
      setState(() {
        ReceivableVisibility = false;
        PayableVisibility = false;
        receivabletotal = "0";
        payabletotal = "0";
      });
      return;
    }

    if (value > 0) {
      if (receivableparty == 'True') {
        setState(() {
          ReceivableVisibility = true;
          PayableVisibility = false;
          receivabletotal = outstanding;
          payabletotal = "0";
        });
      }
    } else {
      if (payableparty == 'True') {
        setState(() {
          PayableVisibility = true;
          ReceivableVisibility = false;
          payabletotal = outstanding;
          receivabletotal = "0";
        });
      }
    }
  }

  void formatOnAccount(String outstanding) {
    final double value = double.tryParse(outstanding) ?? 0.0;

    if (value == 0) return;

    if (value < 0) {
      if (receivableparty == 'True') {
        setState(() {
          onAccountReceivable = outstanding; // raw: -57561
          ReceivableVisibility = true;
        });
      }
    } else {
      if (payableparty == 'True') {
        setState(() {
          onAccountPayable = outstanding; // raw: 57561
          PayableVisibility = true;
        });
      }
    }
  }

  String formatRemainingOverdue(String outstanding) {
    double outstanding_double = double.parse(outstanding);
    outstanding = CurrencyFormatter.formatCurrency_double(outstanding_double);

    return outstanding;
  }

  void formatOnAccountWithBillNo(int overdue_int, String total) {
    double sum_total_180_receivable = 0.00;
    double total_180_receivable = 0.00;

    double sum_total_120_receivable = 0.00;
    double total_120_receivable = 0.00;

    double sum_total_90_receivable = 0.00;
    double total_90_receivable = 0.00;

    double sum_total_60_receivable = 0.00;
    double total_60_receivable = 0.00;

    double sum_total_30_receivable = 0.00;
    double total_30_receivable = 0.00;

    double sum_total_0_receivable = 0.00;
    double total_0_receivable = 0.00;

    double sum_total_180_payable = 0.00;
    double total_180_payable = 0.00;

    double sum_total_120_payable = 0.00;
    double total_120_payable = 0.00;

    double sum_total_90_payable = 0.00;
    double total_90_payable = 0.00;

    double sum_total_60_payable = 0.00;
    double total_60_payable = 0.00;

    double sum_total_30_payable = 0.00;
    double total_30_payable = 0.00;

    double sum_total_0_payable = 0.00;
    double total_0_payable = 0.00;

    if (total.contains("-")) {
      if (receivableparty == 'True') {
        setState(() {
          ReceivableVisibility = true;
        });
        if (overdue_int > 0 && overdue_int <= int.parse(heading1)) {
          String total_string = total.replaceAll("-", "");
          total_0_receivable = double.parse(total_string);
          sum_total_0_receivable = sum_total_0_receivable + total_0_receivable;
          total_string = CurrencyFormatter.formatCurrency_double(
            sum_total_0_receivable,
          );
          total_string = total_string + " DR";

          row6_receivable = total_string.toString();
        }

        if (overdue_int > int.parse(heading1) &&
            overdue_int <= int.parse(heading2)) {
          String total_string = total.replaceAll("-", "");

          total_30_receivable = double.parse(total_string);
          sum_total_30_receivable =
              sum_total_30_receivable + total_30_receivable;
          total_string = CurrencyFormatter.formatCurrency_double(
            sum_total_30_receivable,
          );
          total_string = total_string + " DR";

          row5_receivable = total_string.toString();
        }

        if (overdue_int > int.parse(heading2) &&
            overdue_int <= int.parse(heading3)) {
          String total_string = total.replaceAll("-", "");

          total_60_receivable = double.parse(total_string);
          sum_total_60_receivable =
              sum_total_60_receivable + total_60_receivable;
          total_string = CurrencyFormatter.formatCurrency_double(
            sum_total_60_receivable,
          );
          total_string = total_string + " DR";
          row4_receivable = total_string.toString();
        }

        if (overdue_int > int.parse(heading3) &&
            overdue_int <= int.parse(heading4)) {
          String total_string = total.replaceAll("-", "");

          total_90_receivable = double.parse(total_string);
          sum_total_90_receivable =
              sum_total_90_receivable + total_90_receivable;
          total_string = CurrencyFormatter.formatCurrency_double(
            sum_total_90_receivable,
          );
          total_string = total_string + " DR";
          row3_receivable = total_string.toString();
        }

        if (overdue_int > int.parse(heading4) &&
            overdue_int <= int.parse(heading5)) {
          String total_string = total.replaceAll("-", "");

          total_120_receivable = double.parse(total_string);
          sum_total_120_receivable =
              sum_total_120_receivable + total_120_receivable;
          total_string = CurrencyFormatter.formatCurrency_double(
            sum_total_120_receivable,
          );
          total_string = total_string + " DR";
          row2_receivable = total_string.toString();
        }

        if (overdue_int > int.parse(heading5)) {
          String total_string = total.replaceAll("-", "");

          total_180_receivable = double.parse(total_string);
          sum_total_180_receivable =
              sum_total_180_receivable + total_180_receivable;
          total_string = CurrencyFormatter.formatCurrency_double(
            sum_total_180_receivable,
          );
          total_string = total_string + " DR";
          row1_receivable = total_string.toString();
        }
      }
    } else {
      if (payableparty == 'True') {
        setState(() {
          PayableVisibility = true;
        });
        if (overdue_int > 0 && overdue_int <= int.parse(heading1)) {
          String total_string = total;
          total_0_payable = double.parse(total_string);
          sum_total_0_payable = sum_total_0_payable + total_0_payable;
          total_string = CurrencyFormatter.formatCurrency_double(
            sum_total_0_payable,
          );
          total_string = total_string + " CR";

          row6_payable = total_string.toString();
        }

        if (overdue_int > int.parse(heading1) &&
            overdue_int <= int.parse(heading2)) {
          String total_string = total;

          total_30_payable = double.parse(total_string);
          sum_total_30_payable = sum_total_30_payable + total_30_payable;
          total_string = CurrencyFormatter.formatCurrency_double(
            sum_total_30_payable,
          );
          total_string = total_string + " CR";

          row5_payable = total_string.toString();
        }

        if (overdue_int > int.parse(heading2) &&
            overdue_int <= int.parse(heading3)) {
          String total_string = total;

          total_60_payable = double.parse(total_string);
          sum_total_60_payable = sum_total_60_payable + total_60_payable;
          total_string = CurrencyFormatter.formatCurrency_double(
            sum_total_60_payable,
          );
          total_string = total_string + " CR";
          row4_payable = total_string.toString();
        }

        if (overdue_int > int.parse(heading3) &&
            overdue_int <= int.parse(heading4)) {
          String total_string = total;

          total_90_payable = double.parse(total_string);
          sum_total_90_payable = sum_total_90_payable + total_90_payable;
          total_string = CurrencyFormatter.formatCurrency_double(
            sum_total_90_payable,
          );
          total_string = total_string + " CR";
          row3_payable = total_string.toString();
        }

        if (overdue_int > int.parse(heading4) &&
            overdue_int <= int.parse(heading5)) {
          String total_string = total;

          total_120_payable = double.parse(total_string);
          sum_total_120_payable = sum_total_120_payable + total_120_payable;
          total_string = CurrencyFormatter.formatCurrency_double(
            sum_total_120_payable,
          );
          total_string = total_string + " CR";
          row2_payable = total_string.toString();
        }

        if (overdue_int > int.parse(heading5)) {
          String total_string = total;

          total_180_payable = double.parse(total_string);
          sum_total_180_payable = sum_total_180_payable + total_180_payable;
          total_string = CurrencyFormatter.formatCurrency_double(
            sum_total_180_payable,
          );
          total_string = total_string + " CR";
          row1_payable = total_string.toString();
        }
      }
    }
  }

  String formatRate(String rate) {
    String rate_string = "";

    rate_string = CurrencyFormatter.formatCurrency_normal(rate);

    // Apply any transformations or formatting to the 'amount' variable here
    return rate_string;
  }

  String convertDateFormat(String dateStr) {
    String formattedDate = "";

    if (dateStr == '' || dateStr == 'null') {
    } else {
      DateTime date = DateTime.parse(dateStr);

      // Format the date to the desired output format
      formattedDate = DateFormat("dd-MMM-yy").format(date);
    }
    // Parse the input date string

    return formattedDate;
  }

  void formatSalePurc(String total, String vchtype) {
    double i = 0;
    String total_string = "";

    if (total != 'null') {
      i = double.parse(total);
    }
    if (total != 'null') {
      if (total.contains("-")) {
        total_string = i.toString();
        total_string = total_string.replaceAll("-", "");
        double total_double = double.parse(total_string);
        total_string = CurrencyFormatter.formatCurrency_double(total_double);
        total_string = total_string + " DR";
      } else {
        total_string = i.toString();
        double total_double = double.parse(total_string);
        total_string = CurrencyFormatter.formatCurrency_double(total_double);
        total_string = total_string + " CR";
      }
    }
    if (vchtype == 'SalesOrder') {
      if (pendingsalesorderparty == 'True') {
        if (total == 'null') {
          setState(() {
            SalesOrderVisibility = false;
          });
          pendingsalesorder = "0";
        } else {
          setState(() {
            SalesOrderVisibility = true;
          });
          pendingsalesorder = total;
        }
      }
    }
    if (vchtype == 'PurcOrder') {
      if (pendingpurchaseorderparty == 'True') {
        if (total == 'null') {
          setState(() {
            PurchaseOrderVisibility = false;
          });
          pendingpurchaseorder = "0";
        } else {
          setState(() {
            PurchaseOrderVisibility = true;
          });
          pendingpurchaseorder = total_string;
        }
      }
    }
  }

  Future<void> fetchSummaryData(
    String ledger,
    String startdate_string,
    String enddate_string,
    String groupby,
  ) async {
    months_list_sales.clear();
    months_list_purchase.clear();
    months_list_receipt.clear();
    months_list_payment.clear();
    months_list_creditnote.clear();
    months_list_debitnote.clear();
    months_list_journal.clear();

    row1_receivable = formatRemainingOverdue("0");
    row2_receivable = formatRemainingOverdue("0");
    row3_receivable = formatRemainingOverdue("0");
    row4_receivable = formatRemainingOverdue("0");
    row5_receivable = formatRemainingOverdue("0");
    row6_receivable = formatRemainingOverdue("0");

    row1_payable = formatRemainingOverdue("0");
    row2_payable = formatRemainingOverdue("0");
    row3_payable = formatRemainingOverdue("0");
    row4_payable = formatRemainingOverdue("0");
    row5_payable = formatRemainingOverdue("0");
    row6_payable = formatRemainingOverdue("0");

    setState(() {
      _isLoading = true;
      isClicked_Summary = true;
      isClicked_Sold = false;
      isClicked_Purchase = false;
      isSearchLayoutVisible = false;
      searchController.clear();
      isVisibleNoDataFound = false;

      SalesVisibility = false;
      PurchaseVisibility = false;
      ReceiptVisibility = false;
      PaymentVisibility = false;
      CreditnoteVisibility = false;
      DebitnoteVisibility = false;
      JournalVisibility = false;
      ReceivableVisibility = false;
      PayableVisibility = false;
      PurchaseOrderVisibility = false;
      SalesOrderVisibility = false;
    });

    try {
      final url = Uri.parse(HttpURL_SummaryContent!);

      Map<String, String> headers = {
        'Authorization': 'Bearer $token',
        "Content-Type": "application/json",
      };

      var body = jsonEncode({
        'ledger': ledger,
        'startdate': startdate_string,
        'enddate': enddate_string,
        'groupby': groupby,
      });

      final response = await http.post(url, body: body, headers: headers);

      if (response.statusCode == 200) {
        String responsee = response.body;

        print('response ->> ${response.body}');
        if (responsee == '[]') {
          setState(() {
            SalesVisibility = false;
            PurchaseVisibility = false;
            ReceiptVisibility = false;
            PaymentVisibility = false;
            CreditnoteVisibility = false;
            DebitnoteVisibility = false;
            JournalVisibility = false;
            isVisibleNoDataFound = true;
          });
        } else if (responsee == 'Connection Failed') {
          setState(() {
            SalesVisibility = false;
            PurchaseVisibility = false;
            ReceiptVisibility = false;
            PaymentVisibility = false;
            CreditnoteVisibility = false;
            DebitnoteVisibility = false;
            JournalVisibility = false;
            isVisibleNoDataFound = true;
          });
        } else {
          final List<dynamic> data_list = jsonDecode(responsee);
          // print(data_list);

          if (data_list != null) {
            for (var entry in data_list.asMap().entries) {
              dynamic item = entry.value;

              String vchtype = item['vchtype'].toString();

              if (vchtype == 'Sales') {
                if (salesparty == 'True') {
                  setState(() {
                    SalesVisibility = true;
                  });

                  totalsaleamt = item['totalAmount'].toString();
                  avgsalesinvoiceamt = item['averageAmount'].toString();
                  noofsalesinvoice = item['totalInvoice'].toString();
                  lastsaledate = item['lastdate'].toString();

                  final url_sales = Uri.parse(HttpURL_months!);

                  Map<String, String> headers_sales = {
                    'Authorization': 'Bearer $token',
                    "Content-Type": "application/json",
                  };

                  var body_sales = jsonEncode({
                    'ledger': ledger,
                    'startdate': startdate_string,
                    'enddate': enddate_string,
                    'groupby': 'mname',
                    'vchtype': vchtype,
                    'orderby': 'vchtype,vchdate',
                  });

                  final response_sales = await http.post(
                    url_sales,
                    body: body_sales,
                    headers: headers_sales,
                  );

                  if (response_sales.statusCode == 200) {
                    final List<dynamic> month_list = jsonDecode(
                      response_sales.body,
                    );

                    if (month_list != null) {
                      for (var entry in month_list.asMap().entries) {
                        int index = entry.key;
                        dynamic item = entry.value;
                        months_list_sales.add(
                          months.fromJson(month_list[index]),
                        );
                      }
                    }
                  }
                }
              } else if (vchtype == 'Purchase') {
                if (purchaseparty == 'True') {
                  setState(() {
                    PurchaseVisibility = true;
                  });

                  totalpurchaseamt = item['totalAmount'].toString();
                  avgpurchaseinvoiceamt = item['averageAmount'].toString();
                  noofpurchaseinvoice = item['totalInvoice'].toString();
                  lastpurchasedate = item['lastdate'].toString();

                  final url_purchase = Uri.parse(HttpURL_months!);

                  Map<String, String> headers_purchase = {
                    'Authorization': 'Bearer $token',
                    "Content-Type": "application/json",
                  };

                  var body_purchase = jsonEncode({
                    'ledger': ledger,
                    'startdate': startdate_string,
                    'enddate': enddate_string,
                    'groupby': 'mname',
                    'vchtype': vchtype,
                    'orderby': 'vchtype,vchdate',
                  });

                  final response_purchase = await http.post(
                    url_purchase,
                    body: body_purchase,
                    headers: headers_purchase,
                  );

                  if (response_purchase.statusCode == 200) {
                    final List<dynamic> month_list = jsonDecode(
                      response_purchase.body,
                    );

                    if (month_list != null) {
                      for (var entry in month_list.asMap().entries) {
                        int index = entry.key;
                        dynamic item = entry.value;
                        months_list_purchase.add(
                          months.fromJson(month_list[index]),
                        );
                      }
                    }
                  }
                }
              } else if (vchtype == 'Receipt') {
                if (receiptparty == 'True') {
                  setState(() {
                    ReceiptVisibility = true;
                  });

                  totalreceiptamt = item['totalAmount'].toString();
                  avgreceiptinvoiceamt = item['averageAmount'].toString();
                  noofreceiptinvoice = item['totalInvoice'].toString();
                  lastreceiptdate = item['lastdate'].toString();

                  final urll = Uri.parse(HttpURL_months!);

                  Map<String, String> headerss = {
                    'Authorization': 'Bearer $token',
                    "Content-Type": "application/json",
                  };

                  var bodyy = jsonEncode({
                    'ledger': ledger,
                    'startdate': startdate_string,
                    'enddate': enddate_string,
                    'groupby': 'mname',
                    'vchtype': vchtype,
                    'orderby': 'vchtype,vchdate',
                  });

                  final responseee = await http.post(
                    urll,
                    body: bodyy,
                    headers: headerss,
                  );

                  if (responseee.statusCode == 200) {
                    final List<dynamic> month_list = jsonDecode(
                      responseee.body,
                    );

                    if (month_list != null) {
                      for (var entry in month_list.asMap().entries) {
                        int index = entry.key;
                        dynamic item = entry.value;
                        months_list_receipt.add(
                          months.fromJson(month_list[index]),
                        );
                      }
                    }
                  }
                }
              } else if (vchtype == 'Payment') {
                if (paymentparty == 'True') {
                  setState(() {
                    PaymentVisibility = true;
                  });

                  totalpaymentamt = item['totalAmount'].toString();
                  avgpaymentinvoiceamt = item['averageAmount'].toString();
                  noofpaymentinvoice = item['totalInvoice'].toString();
                  lastpaymentdate = item['lastdate'].toString();

                  final urll = Uri.parse(HttpURL_months!);

                  Map<String, String> headerss = {
                    'Authorization': 'Bearer $token',
                    "Content-Type": "application/json",
                  };

                  var bodyy = jsonEncode({
                    'ledger': ledger,
                    'startdate': startdate_string,
                    'enddate': enddate_string,
                    'groupby': 'mname',
                    'vchtype': vchtype,
                    'orderby': 'vchtype,vchdate',
                  });

                  final responseee = await http.post(
                    urll,
                    body: bodyy,
                    headers: headerss,
                  );

                  if (responseee.statusCode == 200) {
                    final List<dynamic> month_list = jsonDecode(
                      responseee.body,
                    );

                    if (month_list != null) {
                      for (var entry in month_list.asMap().entries) {
                        int index = entry.key;
                        dynamic item = entry.value;
                        months_list_payment.add(
                          months.fromJson(month_list[index]),
                        );
                      }
                    }
                  }
                }
              } else if (vchtype == 'CreditNote') {
                if (creditnoteparty == 'True') {
                  setState(() {
                    CreditnoteVisibility = true;
                  });

                  totalcreditnoteamt = item['totalAmount'].toString();
                  avgcreditnoteinvoiceamt = item['averageAmount'].toString();
                  noofcreditnoteinvoice = item['totalInvoice'].toString();
                  lastcreditnotedate = item['lastdate'].toString();

                  final urll = Uri.parse(HttpURL_months!);

                  Map<String, String> headerss = {
                    'Authorization': 'Bearer $token',
                    "Content-Type": "application/json",
                  };

                  var bodyy = jsonEncode({
                    'ledger': ledger,
                    'startdate': startdate_string,
                    'enddate': enddate_string,
                    'groupby': 'mname',
                    'vchtype': vchtype,
                    'orderby': 'vchtype,vchdate',
                  });

                  final responseee = await http.post(
                    urll,
                    body: bodyy,
                    headers: headerss,
                  );

                  if (responseee.statusCode == 200) {
                    final List<dynamic> month_list = jsonDecode(
                      responseee.body,
                    );

                    if (month_list != null) {
                      for (var entry in month_list.asMap().entries) {
                        int index = entry.key;
                        dynamic item = entry.value;
                        months_list_creditnote.add(
                          months.fromJson(month_list[index]),
                        );
                      }
                    }
                  }
                }
              } else if (vchtype == 'DebitNote') {
                if (debitnoteparty == 'True') {
                  setState(() {
                    DebitnoteVisibility = true;
                  });

                  totaldebitnoteamt = item['totalAmount'].toString();
                  avgdebitnoteinvoiceamt = item['averageAmount'].toString();
                  noofdebitnoteinvoice = item['totalInvoice'].toString();
                  lastdebitnotedate = item['lastdate'].toString();

                  final urll = Uri.parse(HttpURL_months!);

                  Map<String, String> headerss = {
                    'Authorization': 'Bearer $token',
                    "Content-Type": "application/json",
                  };

                  var bodyy = jsonEncode({
                    'ledger': ledger,
                    'startdate': startdate_string,
                    'enddate': enddate_string,
                    'groupby': 'mname',
                    'vchtype': vchtype,
                    'orderby': 'vchtype,vchdate',
                  });

                  final responseee = await http.post(
                    urll,
                    body: bodyy,
                    headers: headerss,
                  );

                  if (responseee.statusCode == 200) {
                    final List<dynamic> month_list = jsonDecode(
                      responseee.body,
                    );

                    if (month_list != null) {
                      for (var entry in month_list.asMap().entries) {
                        int index = entry.key;
                        dynamic item = entry.value;
                        months_list_debitnote.add(
                          months.fromJson(month_list[index]),
                        );
                      }
                    }
                  }
                }
              } else if (vchtype == 'Journal') {
                if (journalparty == 'True') {
                  setState(() {
                    JournalVisibility = true;
                  });

                  totaljournalamt = item['totalAmount'].toString();
                  avgjournalinvoiceamt = item['averageAmount'].toString();
                  noofjournalinvoice = item['totalInvoice'].toString();
                  lastjournaldate = item['lastdate'].toString();

                  final urll = Uri.parse(HttpURL_months!);

                  Map<String, String> headerss = {
                    'Authorization': 'Bearer $token',
                    "Content-Type": "application/json",
                  };

                  var bodyy = jsonEncode({
                    'ledger': ledger,
                    'startdate': startdate_string,
                    'enddate': enddate_string,
                    'groupby': 'mname',
                    'vchtype': vchtype,
                    'orderby': 'vchtype,vchdate',
                  });

                  final responseee = await http.post(
                    urll,
                    body: bodyy,
                    headers: headerss,
                  );

                  if (responseee.statusCode == 200) {
                    final List<dynamic> month_list = jsonDecode(
                      responseee.body,
                    );

                    if (month_list != null) {
                      for (var entry in month_list.asMap().entries) {
                        int index = entry.key;
                        dynamic item = entry.value;
                        months_list_journal.add(
                          months.fromJson(month_list[index]),
                        );
                      }
                    }
                  }
                }
              } else if (vchtype == 'DelNote') {
                // Intentionally ignored. Delivery Note is not shown in this summary UI.
                continue;
              } else if (vchtype == 'SalesOrder') {
                // Intentionally ignored. Delivery Note is not shown in this summary UI.
                continue;
              }
            }
          }
        }

        if (receivableparty == 'True' || payableparty == 'True') {
          // receivable payable total calculation
          final url_recpaytotal = Uri.parse(HttpURL_receivablepayable_total!);

          Map<String, String> headers_recpaytotal = {
            'Authorization': 'Bearer $token',
            "Content-Type": "application/json",
          };

          var body_recpaytotal = jsonEncode({
            'ledger': ledger,
            'billdate': enddate_string,
            "opening": 'true',
          });

          final response_recpaytotal = await http.post(
            url_recpaytotal,
            body: body_recpaytotal,
            headers: headers_recpaytotal,
          );

          debugPrint(
            'response receivable/payable total-> ${response_recpaytotal.body}',
          );

          if (response_recpaytotal.statusCode == 200) {
            final dynamic decoded = jsonDecode(response_recpaytotal.body);

            void handleItem(Map<String, dynamic> item) {
              final String outstanding = (item['outstanding'] ?? '0')
                  .toString();
              formatRecPayTotal(outstanding);
            }

            if (decoded is List) {
              for (final item in decoded) {
                if (item is Map<String, dynamic>) {
                  handleItem(item);
                }
              }
            } else if (decoded is Map<String, dynamic>) {
              handleItem(decoded);
            }
          }

          // receivale payable values

          final url_recpay = Uri.parse(HttpURL_receivablepayable!);
          Map<String, String> headers_recpay = {
            'Authorization': 'Bearer $token',
            "Content-Type": "application/json",
          };

          var body_recpay = jsonEncode({
            'ledger': ledger,
            'billdate': enddate_string,
            'showAll': 'true',
            'orderby': 'billno',
          });

          final response_recpay = await http.post(
            url_recpay,
            body: body_recpay,
            headers: headers_recpay,
          );

          debugPrint('response receivable/payable-> ${response_recpay.body}');

          if (response_recpay.statusCode == 200) {
            final List<dynamic> recpay_list = jsonDecode(response_recpay.body);
            // print(response_recpay.body);

            if (recpay_list != null) {
              for (var entry in recpay_list.asMap().entries) {
                // int index = entry.key;
                dynamic item = entry.value;

                String outstanding = item['outstanding'].toString();
                String billno = item['billno'].toString();
                String overdue = item['overdue'].toString();
                int overdue_int = 0;

                if (overdue == 'null') {
                } else {
                  overdue_int = int.parse(overdue);
                }

                if (billno == 'null') {
                  formatOnAccount(outstanding);
                  if (overdue_int > 0) {
                    formatOnAccountWithBillNo(overdue_int, outstanding);
                  }
                } else {
                  formatOnAccountWithBillNo(overdue_int, outstanding);
                }
              }
            }
          }
        }

        if (pendingpurchaseorderparty == 'True' ||
            pendingsalesorderparty == 'True') {
          // pending sales/purchase order

          final url_salepurc = Uri.parse(HttpURL_salespurchaseorder!);

          Map<String, String> headers_salepurc = {
            'Authorization': 'Bearer $token',
            "Content-Type": "application/json",
          };

          var body_salepurc = jsonEncode({
            'ledger': ledger,
            'enddate': enddate_string,
            'vchtypes': 'sales,purchase',
            'ordervchs': 'salesorder,purcorder',
            'select': 'true',
            'groupby': 'vchtype',
          });

          final response_salepurc = await http.post(
            url_salepurc,
            body: body_salepurc,
            headers: headers_salepurc,
          );

          debugPrint(
            'response sales/purchase order -> ${response_salepurc.body}',
          );

          if (response_salepurc.statusCode == 200) {
            if (response_salepurc.body == '[]') {
            } else if (response_salepurc.body.contains('Connection')) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text("Error in Fetching Sale/Purchase Order"),
                ),
              );
            } else {
              final List<dynamic> salepurc_list = jsonDecode(
                response_salepurc.body,
              );

              if (salepurc_list != null) {
                for (var entry in salepurc_list.asMap().entries) {
                  int index = entry.key;
                  dynamic item = entry.value;

                  String vchtype = item['vchtype'].toString();
                  String totalAmount = item['totalAmount'].toString();

                  formatSalePurc(totalAmount, vchtype);
                }
              }
            }
          }
        }
      }
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      print(e);
    }
  }

  void fetchSummary() {
    if (salesparty == 'False' &&
        purchaseparty == 'False' &&
        receiptparty == 'False' &&
        paymentparty == 'False' &&
        creditnoteparty == 'False' &&
        debitnoteparty == 'False' &&
        journalparty == 'False' &&
        receivableparty == 'False' &&
        payableparty == 'False' &&
        pendingsalesorderparty == 'False' &&
        pendingpurchaseorderparty == 'False') {
      isVisibleSummaryBtn = false;
      isClicked_Summary = false;
      if (party_suppliers == 'True') {
        isClicked_Purchase = true;
        isClicked_Sold = false;
        isClicked_Summary = false;
        isSearchLayoutVisible = true;

        fetchpurchase("Purchase", partyname, startDateString, endDateString);
      } else if (party_customers == 'True') {
        isClicked_Summary = false;
        isClicked_Sold = true;
        isClicked_Purchase = false;
        isSearchLayoutVisible = true;

        fetchsold("Sales", partyname, startDateString, endDateString);
      }
    } else {
      setState(() {
        isVisibleSummaryBtn = true;
        isClicked_Summary = true;
      });
      fetchSummaryData(partyname, startDateString, endDateString, "vchtype");
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
      _selecteddate = prefs.getString('datetype') ?? date_range.first;

      decimal = prefs.getInt('decimalplace') ?? 2;

      currencyFormat = new NumberFormat();

      String? currencyCode = '';

      currencyCode = prefs.getString('currencycode') ?? "AED";

      try {
        if (currencyCode == 'INR' ||
            currencyCode == 'EUR' ||
            currencyCode == 'USD' ||
            currencyCode == 'PKR') {
          currencyFormat = NumberFormat('#,##0');
          NumberFormat format = NumberFormat.simpleCurrency(
            locale: 'en',
            name: currencyCode,
          );
          currencysymbol = format.currencySymbol;
        } else {
          NumberFormat format = NumberFormat.currency(
            locale: 'en',
            name: currencyCode,
          );
          currencysymbol = format.currencySymbol;
          currencyFormat = NumberFormat('#,##0');
        }
      } catch (e) {
        NumberFormat format = NumberFormat.currency(
          locale: 'en',
          name: currencyCode,
        );
        currencysymbol = format.currencySymbol;
        currencyFormat = NumberFormat('#,##0');
      }

      if (_selecteddate == 'Custom Date') {
        _startDate = DateTime.parse(prefs.getString('startdate')!);
        _endDate = DateTime.parse(prefs.getString('enddate')!);

        DateTime start = _startDate;
        DateTime end = _endDate;

        String startMonth = DateFormat('MMM').format(start);
        String sdf = DateFormat(
          'MM',
        ).format(start); // converting month into string
        String startDay = DateFormat('dd').format(start);
        int startYear = start.year;

        String endMonth = DateFormat('MMM').format(end);
        String sdfEnd = DateFormat('MM').format(end);
        String endDay = DateFormat('dd').format(end);
        int endYear = end.year;

        startDateString = '$startYear$sdf$startDay';
        endDateString = '$endYear$sdfEnd$endDay';

        startdate_text =
            startDay + "-" + startMonth + "-" + startYear.toString();
        enddate_text = endDay + "-" + endMonth + "-" + endYear.toString();
      }
    });

    salesparty = prefs.getString("salesparty") ?? 'False';
    purchaseparty = prefs.getString("purchaseparty") ?? 'False';
    creditnoteparty = prefs.getString("creditnoteparty") ?? 'False';
    journalparty = prefs.getString("journalparty") ?? 'False';
    payableparty = prefs.getString("payableparty") ?? 'False';
    pendingpurchaseorderparty =
        prefs.getString("pendingpurchaseorderparty") ?? 'False';
    receiptparty = prefs.getString("receiptparty") ?? 'False';
    paymentparty = prefs.getString("paymentparty") ?? 'False';
    debitnoteparty = prefs.getString("debitnoteparty") ?? 'False';
    receivableparty = prefs.getString("receivableparty") ?? 'False';
    pendingsalesorderparty =
        prefs.getString("pendingsalesorderparty") ?? 'False';
    party_suppliers = prefs.getString("purchaseparty") ?? 'False';
    party_customers = prefs.getString("salesparty") ?? 'False';

    if (party_suppliers == 'True') {
      isVisiblePurchaseBtn = true;
    } else {
      isVisiblePurchaseBtn = false;
    }

    if (party_customers == 'True') {
      isVisibleSoldBtn = true;
    } else {
      isVisibleSoldBtn = false;
    }
    SecuritybtnAcessHolder = prefs.getString('secbtnaccess');

    HttpURL_SummaryContent =
        '$hostname/api/ledger/getSummary/$company_lowercase/$serial_no';
    HttpURL_months =
        '$hostname/api/ledger/getMonthSummary/$company_lowercase/$serial_no';
    HttpURL_receivablepayable_total =
        '$hostname/api/ledger/getOutstandings/$company_lowercase/$serial_no';
    HttpURL_receivablepayable =
        '$hostname/api/ledger/getOutstandingList/$company_lowercase/$serial_no';
    HttpURL_salespurchaseorder =
        '$hostname/api/ledger/getOrderSummary/$company_lowercase/$serial_no';
    HttpURL_sold =
        '$hostname/api/ledger/getItemSummary/$company_lowercase/$serial_no';

    String? email_nav = prefs.getString('email_nav');
    String? name_nav = prefs.getString('name_nav');

    if (email_nav != null && name_nav != null) {
      name = name_nav;
      email = email_nav;
    } else {
      String val = "";
      if (SecuritybtnAcessHolder == "True") {
        val = SecuritybtnAcessHolder!;
      } else if (SecuritybtnAcessHolder == "False") {
        val = "";
      }
    }
    if (SecuritybtnAcessHolder == "True") {
      isRolesVisible = true;
      isUserVisible = true;
    } else {
      isRolesVisible = false;
      isUserVisible = false;
    }

    _handleDate(_selecteddate);

    if (prefs.getString('heading1') == null) {
      heading1 = '30';
      heading2 = '60';
      heading3 = '90';
      heading4 = '120';
      heading5 = '180';

      row1_receivable_heading_value = heading5;
      row2_receivable_heading_value = heading4;
      row3_receivable_heading_value = heading3;
      row4_receivable_heading_value = heading2;
      row5_receivable_heading_value = heading1;
      row6_receivable_heading_value = '0';

      row1_payable_heading_value = heading5;
      row2_payable_heading_value = heading4;
      row3_payable_heading_value = heading3;
      row4_payable_heading_value = heading2;
      row5_payable_heading_value = heading1;
      row6_payable_heading_value = '0';
    } else {
      heading1 = prefs.getString('heading1')!;
      heading2 = prefs.getString('heading2')!;
      heading3 = prefs.getString('heading3')!;
      heading4 = prefs.getString('heading4')!;
      heading5 = prefs.getString('heading5')!;

      row1_receivable_heading_value = heading5;
      row2_receivable_heading_value = heading4;
      row3_receivable_heading_value = heading3;
      row4_receivable_heading_value = heading2;
      row5_receivable_heading_value = heading1;
      row6_receivable_heading_value = '0';

      row1_payable_heading_value = heading5;
      row2_payable_heading_value = heading4;
      row3_payable_heading_value = heading3;
      row4_payable_heading_value = heading2;
      row5_payable_heading_value = heading1;
      row6_payable_heading_value = '0';
    }

    row1_receivable_heading = ">" + row1_receivable_heading_value;
    row2_receivable_heading = ">" + row2_receivable_heading_value;
    row3_receivable_heading = ">" + row3_receivable_heading_value;
    row4_receivable_heading = ">" + row4_receivable_heading_value;
    row5_receivable_heading = ">" + row5_receivable_heading_value;
    row6_receivable_heading = ">" + row6_receivable_heading_value;

    row1_payable_heading = ">" + row1_payable_heading_value;
    row2_payable_heading = ">" + row2_payable_heading_value;
    row3_payable_heading = ">" + row3_payable_heading_value;
    row4_payable_heading = ">" + row4_payable_heading_value;
    row5_payable_heading = ">" + row5_payable_heading_value;
    row6_payable_heading = ">" + row6_payable_heading_value;

    /*row1_receivable = formatRemainingOverdue(row1_receivable);
    row2_receivable = formatRemainingOverdue(row2_receivable);
    row3_receivable = formatRemainingOverdue(row3_receivable);
    row4_receivable = formatRemainingOverdue(row4_receivable);
    row5_receivable = formatRemainingOverdue(row5_receivable);
    row6_receivable = formatRemainingOverdue(row6_receivable);

    row1_payable = formatRemainingOverdue(row1_payable);
    row2_payable = formatRemainingOverdue(row2_payable);
    row3_payable = formatRemainingOverdue(row3_payable);
    row4_payable = formatRemainingOverdue(row4_payable);
    row5_payable = formatRemainingOverdue(row5_payable);
    row6_payable = formatRemainingOverdue(row6_payable);*/
  }

  Future<void> _selectDateRange(BuildContext context) async {
    if (_isTextEnabled) {
      final initialDateRange = DateTimeRange(start: _startDate, end: _endDate);
      String? startfrom = prefs.getString('startfrom');
      DateTime earliestDate = DateTime.parse(startfrom!);

      DateTimeRange? selectedDateRange = await showDateRangePicker(
        context: context,
        initialDateRange: initialDateRange,
        firstDate: earliestDate,
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

      if (selectedDateRange != null) {
        setState(() {
          _startDate = selectedDateRange.start;
          _endDate = selectedDateRange.end;

          DateTime start = _startDate;
          DateTime end = _endDate;

          String startMonth = DateFormat('MMM').format(start);
          String sdf = DateFormat(
            'MM',
          ).format(start); // converting month into string
          String startDay = DateFormat('dd').format(start);
          int startYear = start.year;

          String endMonth = DateFormat('MMM').format(end);
          String sdfEnd = DateFormat('MM').format(end);
          String endDay = DateFormat('dd').format(end);
          int endYear = end.year;

          startDateString = '$startYear$sdf$startDay';
          endDateString = '$endYear$sdfEnd$endDay';

          startdate_text =
              startDay + "-" + startMonth + "-" + startYear.toString();
          enddate_text = endDay + "-" + endMonth + "-" + endYear.toString();

          print(startDateString);
          print(endDateString);

          fetchSummary();
        });
      }
    }
  }

  Future<void> _selectDateRange_auto(BuildContext context) async {
    if (_isTextEnabled) {
      final initialDateRange = DateTimeRange(start: _startDate, end: _endDate);
      String? startfrom = prefs.getString('startfrom');
      DateTime earliestDate = DateTime.parse(startfrom!);

      DateTimeRange? selectedDateRange = await showDateRangePicker(
        context: context,
        initialDateRange: initialDateRange,
        firstDate: earliestDate,
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

      setState(() {
        _startDate = selectedDateRange!.start;
        _endDate = selectedDateRange!.end;

        DateTime start = _startDate;
        DateTime end = _endDate;

        String startMonth = DateFormat('MMM').format(start);
        String sdf = DateFormat(
          'MM',
        ).format(start); // converting month into string
        String startDay = DateFormat('dd').format(start);
        int startYear = start.year;

        String endMonth = DateFormat('MMM').format(end);
        String sdfEnd = DateFormat('MM').format(end);
        String endDay = DateFormat('dd').format(end);
        int endYear = end.year;

        startDateString = '$startYear$sdf$startDay';
        endDateString = '$endYear$sdfEnd$endDay';

        startdate_text =
            startDay + "-" + startMonth + "-" + startYear.toString();
        enddate_text = endDay + "-" + endMonth + "-" + endYear.toString();

        fetchSummary();

        print(startDateString);
        print(endDateString);
      });
    }
  }

  void _handleDate(String value) {
    setState(() {
      _selecteddate = value;
    });

    if (_selecteddate == "Today") {
      DateTime currentDate = DateTime.now();
      String startMonth = DateFormat('MMM').format(currentDate);
      String sdf = DateFormat(
        'MM',
      ).format(currentDate); // converting month into string

      String startDay = DateFormat('dd').format(currentDate);
      int startYear = currentDate.year;

      String endMonth = DateFormat('MMM').format(currentDate);
      String sdfEnd = DateFormat('MM').format(currentDate);

      String endDay = DateFormat('dd').format(currentDate);
      int endYear = currentDate.year;

      startDateString = "$startYear$sdf$startDay";
      endDateString = "$endYear$sdfEnd$endDay";
      print(startDateString);
      print(endDateString);
      fetchSummary();

      setState(() {
        _isTextEnabled = false;
        _isDashVisible = false;
        _isEnddateVisible = false;
        _IsSizeboxVisible = false;
      });

      startdate_text = startDay + "-" + startMonth + "-" + startYear.toString();
      enddate_text = endDay + "-" + endMonth + "-" + endYear.toString();
    } else if (_selecteddate == "Year To Date") {
      DateTime now = DateTime.now();
      DateTime startDate = DateTime(
        now.year,
        1,
        1,
      ); // Start of the current year
      DateTime endDate = DateTime(now.year, now.month, now.day); // Today's date

      DateFormat dateFormat = DateFormat("dd-MMM-yyyy");

      String startMonth = dateFormat.format(startDate).substring(3, 6);
      String sdf = DateFormat('MM').format(startDate);

      String startDay = dateFormat.format(startDate).substring(0, 2);
      int startYear = startDate.year;

      String endMonth = dateFormat.format(endDate).substring(3, 6);
      String sdfEnd = DateFormat('MM').format(endDate);

      String endDay = dateFormat.format(endDate).substring(0, 2);
      int endYear = endDate.year;

      startDateString = "$startYear$sdf$startDay";
      endDateString = "$endYear$sdfEnd$endDay";
      print(startDateString);
      print(endDateString);

      startdate_text = startDay + "-" + startMonth + "-" + startYear.toString();
      enddate_text = endDay + "-" + endMonth + "-" + endYear.toString();

      fetchSummary();

      setState(() {
        _isTextEnabled = false;
        _isDashVisible = true;
        _isEnddateVisible = true;
        _IsSizeboxVisible = true;
      });
    } else if (_selecteddate == "Yesterday") {
      DateTime yesterday = DateTime.now().subtract(Duration(days: 1));
      DateFormat dateFormat = DateFormat("dd-MMM-yyyy");

      String startMonth = dateFormat.format(yesterday).substring(3, 6);
      String sdf = DateFormat(
        'MM',
      ).format(yesterday); // converting month into string

      String startDay = dateFormat.format(yesterday).substring(0, 2);
      int startYear = yesterday.year;

      String endMonth = dateFormat.format(yesterday).substring(3, 6);
      String sdfEnd = DateFormat('MM').format(yesterday);

      String endDay = dateFormat.format(yesterday).substring(0, 2);
      int endYear = yesterday.year;

      startDateString = "$startYear$sdf$startDay";
      endDateString = "$endYear$sdfEnd$endDay";
      print(startDateString);
      print(endDateString);
      fetchSummary();

      startdate_text = startDay + "-" + startMonth + "-" + startYear.toString();
      enddate_text = endDay + "-" + endMonth + "-" + endYear.toString();

      setState(() {
        _isTextEnabled = false;
        _isDashVisible = false;
        _isEnddateVisible = false;
        _IsSizeboxVisible = false;
      });
    } else if (_selecteddate == "This Month") {
      DateTime now = DateTime.now();
      DateTime startOfMonth = DateTime(now.year, now.month, 1);
      DateTime endOfMonth = DateTime(now.year, now.month + 1, 0);

      String startMonth = DateFormat('MMM').format(startOfMonth);
      String sdf = DateFormat(
        'MM',
      ).format(startOfMonth); // converting month into string
      String startDay = DateFormat('dd').format(startOfMonth);
      int startYear = startOfMonth.year;

      String endMonth = DateFormat('MMM').format(endOfMonth);
      String sdfEnd = DateFormat('MM').format(endOfMonth);
      String endDay = DateFormat('dd').format(endOfMonth);
      int endYear = endOfMonth.year;

      startDateString = '$startYear$sdf$startDay';
      endDateString = '$endYear$sdfEnd$endDay';

      startdate_text = startDay + "-" + startMonth + "-" + startYear.toString();
      enddate_text = endDay + "-" + endMonth + "-" + endYear.toString();

      print(startDateString);
      print(endDateString);
      fetchSummary();

      setState(() {
        _isTextEnabled = false;

        _isDashVisible = true;
        _isEnddateVisible = true;
        _IsSizeboxVisible = true;
      });
    } else if (_selecteddate == "Last Month") {
      var calendarLastMonthStart = DateTime.now();
      var calendarLastMonthEnd = DateTime.now();

      calendarLastMonthStart = DateTime(
        calendarLastMonthStart.year,
        calendarLastMonthStart.month - 1,
        1,
      );

      calendarLastMonthStart = DateTime(
        calendarLastMonthStart.year,
        calendarLastMonthStart.month,
        1,
      );
      calendarLastMonthEnd = DateTime(
        calendarLastMonthStart.year,
        calendarLastMonthStart.month + 1,
        0,
      );

      var startMonth = DateFormat('MMM').format(calendarLastMonthStart);
      var sdf = DateFormat('MM').format(calendarLastMonthStart);
      var startDay = DateFormat('dd').format(calendarLastMonthStart);
      var startYear = calendarLastMonthStart.year;

      var endMonth = DateFormat('MMM').format(calendarLastMonthEnd);
      var sdfEnd = DateFormat('MM').format(calendarLastMonthEnd);
      var endDay = DateFormat('dd').format(calendarLastMonthEnd);
      var endYear = calendarLastMonthEnd.year;

      startDateString = '$startYear$sdf$startDay';
      endDateString = '$endYear$sdfEnd$endDay';

      startdate_text = startDay + "-" + startMonth + "-" + startYear.toString();
      enddate_text = endDay + "-" + endMonth + "-" + endYear.toString();

      fetchSummary();

      print(startDateString);
      print(endDateString);

      setState(() {
        _isTextEnabled = false;

        _isDashVisible = true;
        _isEnddateVisible = true;
        _IsSizeboxVisible = true;
      });
    } else if (_selecteddate == "This Year") {
      DateTime today = DateTime.now();
      DateTime yearStart = DateTime(today.year, 1, 1);
      DateTime yearEnd = DateTime(today.year, 12, 31);

      String startMonth = DateFormat('MMM').format(yearStart);
      String sdf = DateFormat(
        'MM',
      ).format(yearStart); // converting month into string
      String startDay = DateFormat('dd').format(yearStart);
      String startYear = DateFormat('yyyy').format(yearStart);

      String endMonth = DateFormat('MMM').format(yearEnd);
      String sdfEnd = DateFormat('MM').format(yearEnd);
      String endDay = DateFormat('dd').format(yearEnd);
      String endYear = DateFormat('yyyy').format(yearEnd);

      startDateString = '$startYear$sdf$startDay';
      endDateString = '$endYear$sdfEnd$endDay';

      startdate_text = startDay + "-" + startMonth + "-" + startYear.toString();
      enddate_text = endDay + "-" + endMonth + "-" + endYear.toString();

      print(startDateString);
      print(endDateString);

      fetchSummary();

      setState(() {
        _isTextEnabled = false;

        _isDashVisible = true;
        _isEnddateVisible = true;
        _IsSizeboxVisible = true;
      });
    } else if (_selecteddate == "Last Year") {
      DateTime today = DateTime.now();
      DateTime yearStart = DateTime(today.year - 1, 1, 1);
      DateTime yearEnd = DateTime(today.year - 1, 12, 31);

      String startMonth = DateFormat('MMM').format(yearStart);
      String sdf = DateFormat(
        'MM',
      ).format(yearStart); // converting month into string
      String startDay = DateFormat('dd').format(yearStart);
      String startYear = DateFormat('yyyy').format(yearStart);

      String endMonth = DateFormat('MMM').format(yearEnd);
      String sdfEnd = DateFormat('MM').format(yearEnd);
      String endDay = DateFormat('dd').format(yearEnd);
      String endYear = DateFormat('yyyy').format(yearEnd);

      startdate_text = startDay + "-" + startMonth + "-" + startYear.toString();
      enddate_text = endDay + "-" + endMonth + "-" + endYear.toString();

      startDateString = '$startYear$sdf$startDay';
      endDateString = '$endYear$sdfEnd$endDay';

      print(startDateString);
      print(endDateString);

      fetchSummary();

      setState(() {
        _isTextEnabled = false;

        _isDashVisible = true;
        _isEnddateVisible = true;
        _IsSizeboxVisible = true;
      });
    } else if (_selecteddate == "Custom Date") {
      setState(() {
        _isTextEnabled = true;

        _isDashVisible = true;
        _isEnddateVisible = true;
        _IsSizeboxVisible = true;
      });

      _selectDateRange_auto(context);
    }
  }

  @override
  void initState() {
    super.initState();
    _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
    _initSharedPreferences();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: const AppBottomNav(activeTab: AppBottomNavTab.party),
      key: _scaffoldKey,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(50),
        child: AppBar(
          backgroundColor: app_color,
          elevation: 6,
          automaticallyImplyLeading: false,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
          ),
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () {
              AppNavigation.backOrDashboard(context);
            },
          ),
          title: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth:
                  MediaQuery.of(context).size.width - (kToolbarHeight * 5.2),
            ),
            child: GestureDetector(
              onTap: () {},
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      partyname,
                      style: GoogleFonts.poppins(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
          centerTitle: true,
          actions: [
            IconButton(
              tooltip: 'Toggle theme',
              icon: Icon(
                Theme.of(context).brightness == Brightness.dark
                    ? Icons.light_mode
                    : Icons.dark_mode,
                color: Colors.white,
              ),
              onPressed: () {
                themeController.setThemeMode(
                  Theme.of(context).brightness == Brightness.dark
                      ? ThemeMode.light
                      : ThemeMode.dark,
                );
              },
            ),
            Visibility(
              visible: isSearchLayoutVisible,
              child: Align(
                alignment: Alignment.centerRight,
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () {
                        counter++;
                        setState(() {
                          _isSearchViewVisible = !_isSearchViewVisible;

                          if (!_isSearchViewVisible) {
                            setState(() {
                              searchController.clear();
                              if (isClicked_Sold) {
                                filteredItems_sold = sold_list;
                              } else if (isClicked_Purchase) {
                                filteredItems_purchase = purchase_list;
                              }
                            });
                          }
                        });

                        /*if (counter % 2 == 0) {
            setState(() {
              _isSearchViewVisible = false;
            });                      }
          else
          {
            setState(() {
              _isSearchViewVisible = true;
            });
          }*/
                      },
                      icon: Icon(Icons.search, color: Colors.white, size: 30),
                    ),
                    IconButton(
                      onPressed: () {
                        final RenderBox button =
                            context.findRenderObject() as RenderBox;
                        final RenderBox overlay =
                            Overlay.of(context).context.findRenderObject()
                                as RenderBox;
                        final Offset buttonPosition = button.localToGlobal(
                          Offset.zero,
                          ancestor: overlay,
                        );

                        showMenu(
                          color: Theme.of(context).colorScheme.surface,
                          context: context,
                          position: RelativeRect.fromLTRB(
                            overlay.size.width - buttonPosition.dx,
                            buttonPosition.dy - button.size.height,
                            overlay.size.width - buttonPosition.dx,
                            buttonPosition.dy,
                          ),
                          items: <PopupMenuEntry<String>>[
                            PopupMenuItem<String>(
                              child: GestureDetector(
                                onTap: () {
                                  Navigator.pop(context);
                                  if (isClicked_Sold) {
                                    if (!sold_list.isEmpty) {
                                      generateAndSharePDF_Sold();
                                    }
                                  } else if (isClicked_Purchase) {
                                    if (!purchase_list.isEmpty) {
                                      generateAndSharePDF_Purchase();
                                    }
                                  }
                                },
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.picture_as_pdf,
                                      size: 16,
                                      color: Colors.teal,
                                    ),
                                    SizedBox(width: 5),

                                    Text(
                                      'Share as PDF',
                                      style: GoogleFonts.poppins(
                                        fontWeight: FontWeight.normal,
                                        color: Colors.teal,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            PopupMenuItem<String>(
                              child: GestureDetector(
                                onTap: () {
                                  Navigator.pop(context);

                                  if (isClicked_Sold) {
                                    if (!sold_list.isEmpty) {
                                      generateAndShareCSV_Sold();
                                    }
                                  } else if (isClicked_Purchase) {
                                    if (!purchase_list.isEmpty) {
                                      generateAndShareCSV_Purchase();
                                    }
                                  }
                                },
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.add_chart_outlined,
                                      size: 16,
                                      color: Colors.teal,
                                    ),
                                    SizedBox(width: 5),
                                    Text(
                                      'Share as CSV',
                                      style: GoogleFonts.poppins(
                                        fontWeight: FontWeight.normal,
                                        color: Colors.teal,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                      icon: Icon(Icons.share, color: Colors.white, size: 30),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),

      body: Stack(
        children: [
          SizedBox.expand(
            child: Column(
              children: [
                Container(
                  margin: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black12.withOpacity(0.08),
                        blurRadius: 10,
                        spreadRadius: 2,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        /// 🔽 Dropdown
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: app_color, width: 1.2),
                          ),
                          padding: EdgeInsets.symmetric(horizontal: 12),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<dynamic>(
                              value: _selecteddate,
                              isExpanded: true,
                              icon: Icon(
                                Icons.expand_more,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                              style: GoogleFonts.poppins(
                                color: Theme.of(context).colorScheme.onSurface,
                                fontSize: 15,
                              ),
                              dropdownColor: Theme.of(
                                context,
                              ).colorScheme.surface,
                              onChanged: (value) {
                                if (value != null) _handleDate(value);
                              },

                              items: date_range.map((item) {
                                return DropdownMenuItem<dynamic>(
                                  value: item,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 10,
                                    ),
                                    child: Text(item),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ),

                        SizedBox(height: 18),

                        /// 📆 Date Range (Single Widget)
                        InkWell(
                          onTap: () => _selectDateRange(context),
                          borderRadius: BorderRadius.circular(50),
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest
                                      .withOpacity(
                                        Theme.of(context).brightness ==
                                                Brightness.dark
                                            ? 0.85
                                            : 0.35,
                                      ),
                                  Theme.of(context).cardColor.withOpacity(
                                    Theme.of(context).brightness ==
                                            Brightness.dark
                                        ? 0.95
                                        : 0.9,
                                  ),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              border: Border.all(color: app_color, width: 1),
                              borderRadius: BorderRadius.circular(50),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.calendar_month_rounded,
                                  size: 18,
                                  color: app_color,
                                ),
                                SizedBox(width: 10),
                                Text(
                                  "$startdate_text → $enddate_text",
                                  style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
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

                Expanded(
                  child: Container(
                    margin: const EdgeInsets.only(
                      left: 16,
                      right: 16,
                      bottom: 16,
                    ),
                    padding: const EdgeInsets.only(
                      left: 0,
                      right: 0,
                      top: 4,
                      bottom: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          LayoutBuilder(
                            builder: (context, constraints) {
                              int countPerRow = constraints.maxWidth > 600
                                  ? 3
                                  : 2;
                              double buttonWidth =
                                  (constraints.maxWidth -
                                      (countPerRow - 1) * 12) /
                                  countPerRow;

                              return Wrap(
                                spacing: 12,
                                runSpacing: 12,
                                alignment: WrapAlignment.center,
                                children: [
                                  if (isVisibleSummaryBtn)
                                    SizedBox(
                                      width: buttonWidth,
                                      child: _buildModernTabButton(
                                        label: 'SUMMARY',
                                        isSelected: isClicked_Summary,
                                        onTap: fetchSummary,
                                      ),
                                    ),
                                  if (isVisibleSoldBtn)
                                    SizedBox(
                                      width: buttonWidth,
                                      child: _buildModernTabButton(
                                        label: 'SOLD',
                                        isSelected: isClicked_Sold,
                                        onTap: () {
                                          setState(() {
                                            isClicked_Summary = false;
                                            isClicked_Sold = true;
                                            isClicked_Purchase = false;
                                            isSearchLayoutVisible = true;
                                            fetchsold(
                                              "Sales",
                                              partyname,
                                              startDateString,
                                              endDateString,
                                            );
                                          });
                                        },
                                      ),
                                    ),
                                  if (isVisiblePurchaseBtn)
                                    SizedBox(
                                      width: buttonWidth,
                                      child: _buildModernTabButton(
                                        label: 'PURCHASED',
                                        isSelected: isClicked_Purchase,
                                        onTap: () {
                                          setState(() {
                                            isClicked_Purchase = true;
                                            isClicked_Sold = false;
                                            isClicked_Summary = false;
                                            isSearchLayoutVisible = true;
                                            fetchpurchase(
                                              "Purchase",
                                              partyname,
                                              startDateString,
                                              endDateString,
                                            );
                                          });
                                        },
                                      ),
                                    ),
                                ],
                              );
                            },
                          ),

                          /* Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 25),
                            child: Divider(
                              thickness: 1,
                              color: Theme.of(context).dividerColor,
                            ),
                          ),*/
                          if (isClicked_Summary)
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (isVisibleNoDataFound &&
                                    !ReceivableVisibility &&
                                    !PayableVisibility &&
                                    !SalesOrderVisibility &&
                                    !PurchaseOrderVisibility)
                                  SizedBox(
                                    height: MediaQuery.of(context).size.height * 0.5,
                                    child: Center(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.search_off_rounded,
                                            size: 48,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                          ),
                                          SizedBox(height: 12),
                                          Text(
                                            'No Records Found',
                                            style: GoogleFonts.poppins(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                if (SalesVisibility)
                                  SummaryExpansionCard(
                                    title: 'Sales',
                                    totalAmount: totalsaleamt,
                                    lastDate: lastsaledate,
                                    count: noofsalesinvoice,
                                    type: "Sales",
                                    partyname: partyname,

                                    averageAmount: avgsalesinvoiceamt,
                                    months: months_list_sales,
                                    onTapTotal: () =>
                                        navigateToDetail('Sales', totalsaleamt),
                                    currencysymbol: currencysymbol,
                                    decimal: decimal,
                                  ),

                                if (PurchaseVisibility)
                                  SummaryExpansionCard(
                                    title: 'Purchase',
                                    totalAmount: totalpurchaseamt,
                                    lastDate: lastpurchasedate,
                                    count: noofpurchaseinvoice,
                                    averageAmount: avgpurchaseinvoiceamt,
                                    months: months_list_purchase,
                                    type: "Purchase",
                                    partyname: partyname,
                                    currencysymbol: currencysymbol,
                                    decimal: decimal,
                                    onTapTotal: () => navigateToDetail(
                                      'Purchase',
                                      totalpurchaseamt,
                                    ),
                                  ),

                                if (ReceiptVisibility)
                                  SummaryExpansionCard(
                                    title: 'Receipt',
                                    totalAmount: totalreceiptamt,
                                    lastDate: lastreceiptdate,
                                    count: noofreceiptinvoice,
                                    averageAmount: avgreceiptinvoiceamt,
                                    months: months_list_receipt,
                                    type: "Receipt",
                                    partyname: partyname,
                                    currencysymbol: currencysymbol,
                                    decimal: decimal,
                                    onTapTotal: () {
                                      String amount = formatAmount(
                                        totalreceiptamt,
                                      );

                                      print('amount -> $amount');
                                      String vchtype = 'Receipt';
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              PartyTotalClickedRest(
                                                startdate_string:
                                                    startDateString,
                                                enddate_string: endDateString,
                                                type: vchtype,
                                                total: amount,
                                                ledger: partyname,
                                              ),
                                        ),
                                      );
                                    },
                                  ),

                                if (PaymentVisibility)
                                  SummaryExpansionCard(
                                    title: 'Payment',
                                    totalAmount: totalpaymentamt,
                                    lastDate: lastpaymentdate,
                                    count: noofpaymentinvoice,
                                    averageAmount: avgpaymentinvoiceamt,
                                    months: months_list_payment,
                                    type: "Payment",
                                    partyname: partyname,
                                    currencysymbol: currencysymbol,
                                    decimal: decimal,
                                    onTapTotal: () {
                                      String amount = formatAmount(
                                        totalpaymentamt,
                                      );
                                      print('amount -> $amount');

                                      String vchtype = 'Payment';
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              PartyTotalClickedRest(
                                                startdate_string:
                                                    startDateString,
                                                enddate_string: endDateString,
                                                type: vchtype,
                                                total: amount,
                                                ledger: partyname,
                                              ),
                                        ),
                                      );
                                    },
                                  ),

                                if (CreditnoteVisibility)
                                  SummaryExpansionCard(
                                    title: 'Credit Note',
                                    totalAmount: totalcreditnoteamt,
                                    lastDate: lastcreditnotedate,
                                    count: noofcreditnoteinvoice,
                                    averageAmount: avgcreditnoteinvoiceamt,
                                    months: months_list_creditnote,
                                    type: "Credit Note",
                                    partyname: partyname,
                                    currencysymbol: currencysymbol,
                                    decimal: decimal,
                                    onTapTotal: () => navigateToDetail(
                                      'Credit Note',
                                      totalcreditnoteamt,
                                    ),
                                  ),
                                if (DebitnoteVisibility)
                                  SummaryExpansionCard(
                                    title: 'Debit Note',
                                    totalAmount: totaldebitnoteamt,
                                    lastDate: lastdebitnotedate,
                                    count: noofdebitnoteinvoice,
                                    averageAmount: avgdebitnoteinvoiceamt,
                                    months: months_list_debitnote,
                                    type: "Debit Note",
                                    partyname: partyname,
                                    currencysymbol: currencysymbol,
                                    decimal: decimal,
                                    onTapTotal: () => navigateToDetail(
                                      'Debit Note',
                                      totaldebitnoteamt,
                                    ),
                                  ),
                                if (JournalVisibility)
                                  SummaryExpansionCard(
                                    title: 'Journal',
                                    totalAmount: totaljournalamt,
                                    lastDate: lastjournaldate,
                                    count: noofjournalinvoice,
                                    averageAmount: avgjournalinvoiceamt,
                                    months: months_list_journal,
                                    type: "Journal",
                                    partyname: partyname,
                                    currencysymbol: currencysymbol,
                                    decimal: decimal,
                                    onTapTotal: () {
                                      String amount = formatAmount(
                                        totaljournalamt,
                                      );
                                      print('amount -> $amount');
                                      String vchtype = 'Journal';
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              PartyTotalClickedRest(
                                                startdate_string:
                                                    startDateString,
                                                enddate_string: endDateString,
                                                type: vchtype,
                                                total: amount,
                                                ledger: partyname,
                                              ),
                                        ),
                                      );
                                    },
                                  ),

                                if (ReceivableVisibility)
                                  ReceivableBreakdownCard(
                                    total: receivabletotal,
                                    onAccount: onAccountReceivable,
                                    onTotalTap: () {
                                      navigateToReceivable(
                                        'Receivable',
                                        receivabletotal,
                                        '',
                                        'All',
                                      );
                                    },

                                    rows: [
                                      {
                                        'label': row1_receivable_heading,
                                        'value': row1_receivable,
                                        'onTap': () {
                                          navigateToReceivable(
                                            'Receivable',
                                            row1_receivable,
                                            ">",
                                            row1_receivable_heading_value,
                                          );
                                        },
                                      },
                                      {
                                        'label': row2_receivable_heading,
                                        'value': row2_receivable,
                                        'onTap': () {
                                          navigateToReceivable(
                                            'Receivable',
                                            row2_receivable,
                                            ">",
                                            row2_receivable_heading_value,
                                          );
                                        },
                                      },
                                      {
                                        'label': row3_receivable_heading,
                                        'value': row3_receivable,
                                        'onTap': () {
                                          navigateToReceivable(
                                            'Receivable',
                                            row3_receivable,
                                            ">",
                                            row3_receivable_heading_value,
                                          );
                                        },
                                      },
                                      {
                                        'label': row4_receivable_heading,
                                        'value': row4_receivable,
                                        'onTap': () {
                                          navigateToReceivable(
                                            'Receivable',
                                            row4_receivable,
                                            ">",
                                            row4_receivable_heading_value,
                                          );
                                        },
                                      },
                                      {
                                        'label': row5_receivable_heading,
                                        'value': row5_receivable,
                                        'onTap': () {
                                          navigateToReceivable(
                                            'Receivable',
                                            row5_receivable,
                                            ">",
                                            row5_receivable_heading_value,
                                          );
                                        },
                                      },
                                      {
                                        'label': row6_receivable_heading,
                                        'value': row6_receivable,
                                        'onTap': () {
                                          navigateToReceivable(
                                            'Receivable',
                                            row6_receivable,
                                            ">",
                                            row6_receivable_heading_value,
                                          );
                                        },
                                      },
                                    ],
                                  ),

                                if (PayableVisibility)
                                  PayableBreakdownCard(
                                    total: payabletotal,
                                    onAccount: onAccountPayable,
                                    onTotalTap: () {
                                      navigateToPayable(
                                        'Payable',
                                        formatAmount(payabletotal.toString()),
                                        '',
                                        'All',
                                      );
                                    },
                                    rows: [
                                      {
                                        'label': row1_payable_heading,
                                        'value': row1_payable,
                                        'onTap': () {
                                          navigateToPayable(
                                            'Payable',
                                            row1_payable,
                                            ">",
                                            row1_payable_heading_value,
                                          );
                                        },
                                      },
                                      {
                                        'label': row2_payable_heading,
                                        'value': row2_payable,
                                        'onTap': () {
                                          navigateToPayable(
                                            'Payable',
                                            row2_payable,
                                            ">",
                                            row2_payable_heading_value,
                                          );
                                        },
                                      },
                                      {
                                        'label': row3_payable_heading,
                                        'value': row3_payable,
                                        'onTap': () {
                                          navigateToPayable(
                                            'Payable',
                                            row3_payable,
                                            ">",
                                            row3_payable_heading_value,
                                          );
                                        },
                                      },
                                      {
                                        'label': row4_payable_heading,
                                        'value': row4_payable,
                                        'onTap': () {
                                          navigateToPayable(
                                            'Payable',
                                            row4_payable,
                                            ">",
                                            row4_payable_heading_value,
                                          );
                                        },
                                      },
                                      {
                                        'label': row5_payable_heading,
                                        'value': row5_payable,
                                        'onTap': () {
                                          navigateToPayable(
                                            'Payable',
                                            row5_payable,
                                            ">",
                                            row5_payable_heading_value,
                                          );
                                        },
                                      },
                                      {
                                        'label': row6_payable_heading,
                                        'value': row6_payable,
                                        'onTap': () {
                                          navigateToPayable(
                                            'Payable',
                                            row6_payable,
                                            ">",
                                            row6_payable_heading_value,
                                          );
                                        },
                                      },
                                    ],
                                  ),

                                if (SalesOrderVisibility)
                                  PendingOrderTile(
                                    label: 'Pending Sales Order',
                                    amount: pendingsalesorder,
                                    currencysymbol: currencysymbol,
                                    decimal: decimal!,
                                    onTap: () => navigateToOrder('salesorder'),
                                  ),

                                if (PurchaseOrderVisibility)
                                  PendingOrderTile(
                                    label: 'Pending Purchase Order',
                                    amount: pendingpurchaseorder,
                                    currencysymbol: currencysymbol,
                                    decimal: decimal,
                                    onTap: () => navigateToOrder('purcorder'),
                                  ),
                              ],
                            ),

                          Visibility(
                            visible: isClicked_Sold,
                            child: Column(
                              children: [
                                // Header Count
                                Container(
                                  width: double.infinity,
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 10,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).cardColor,
                                    borderRadius: BorderRadius.circular(30),
                                    border: Border.all(
                                      color: Colors.teal,
                                      width: 1.2,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black12.withOpacity(0.05),
                                        blurRadius: 6,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(
                                        Icons.inventory_2_rounded,
                                        color: Colors.teal,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        '$item_count Items',
                                        style: GoogleFonts.poppins(
                                          fontSize: 14.5,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.teal,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                // Search Bar
                                if (_isSearchViewVisible)
                                  Padding(
                                    padding: EdgeInsets.only(
                                      left: 12,
                                      right: 12,
                                      top: 12,
                                    ),
                                    child: Material(
                                      elevation: 2,
                                      borderRadius: BorderRadius.circular(18),
                                      shadowColor: Colors.black12,

                                      child: TextField(
                                        controller: searchController,
                                        onChanged: (value) {
                                          final query = value.toLowerCase();
                                          setState(() {
                                            filteredItems_sold = query.isEmpty
                                                ? sold_list
                                                : sold_list
                                                      .where(
                                                        (item) => item.item
                                                            .toLowerCase()
                                                            .contains(query),
                                                      )
                                                      .toList();
                                          });
                                        },
                                        style: GoogleFonts.poppins(
                                          fontSize: 15,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurface,
                                        ),
                                        decoration: InputDecoration(
                                          hintText: 'Search...',
                                          prefixIcon: Icon(
                                            Icons.search,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                          ),
                                          filled: true,
                                          fillColor:
                                              Theme.of(context)
                                                  .inputDecorationTheme
                                                  .fillColor ??
                                              Theme.of(context)
                                                  .colorScheme
                                                  .surfaceContainerHighest,
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                vertical: 14,
                                                horizontal: 16,
                                              ),
                                          enabledBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                            borderSide: BorderSide(
                                              color: Theme.of(
                                                context,
                                              ).dividerColor,
                                            ),
                                          ),
                                          focusedBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                            borderSide: const BorderSide(
                                              color: app_color,
                                              width: 1.5,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),

                                // No Data Message
                                if (isVisibleNoDataFound)
                                  SizedBox(
                                    height: MediaQuery.of(context).size.height * 0.5,
                                    child: Center(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.search_off_rounded,
                                            size: 48,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                          ),
                                          SizedBox(height: 12),
                                          Text(
                                            'No Records Found',
                                            style: GoogleFonts.poppins(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),

                                // Sold List
                                if (isVisibleSoldList)
                                  ListView.builder(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    shrinkWrap: true,
                                    physics:
                                        const NeverScrollableScrollPhysics(),
                                    itemCount: filteredItems_sold.length,
                                    itemBuilder: (context, index) {
                                      final card = filteredItems_sold[index];
                                      return _buildSoldPurchaseCard(
                                        context: context,
                                        item: card.item,
                                        qty: card.qty,
                                        lastDate: card.lastdate,
                                        rate: card.rate,
                                        isSale: true,
                                        onTap: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  PartyClickedSoldPurchaseClicked(
                                                    startdate_string:
                                                        startDateString,
                                                    enddate_string:
                                                        endDateString,
                                                    type: 'Sales',
                                                    item: card.item,
                                                    unit: card.unit,
                                                    ledger: partyname,
                                                  ),
                                            ),
                                          );
                                        },
                                      );
                                    },
                                  ),
                              ],
                            ),
                          ),

                          Visibility(
                            visible: isClicked_Purchase,
                            child: Container(
                              width: double.infinity,
                              color: Theme.of(context).scaffoldBackgroundColor,
                              child: Column(
                                children: [
                                  /// 🔢 Item Count
                                  Container(
                                    width: double.infinity,
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 10,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).cardColor,
                                      borderRadius: BorderRadius.circular(30),
                                      border: Border.all(
                                        color: Colors.teal,
                                        width: 1.2,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black12.withOpacity(
                                            0.05,
                                          ),
                                          blurRadius: 6,
                                          offset: const Offset(0, 3),
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        const Icon(
                                          Icons.inventory_2_rounded,
                                          color: Colors.teal,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          '$item_count Items',
                                          style: GoogleFonts.poppins(
                                            fontSize: 14.5,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.teal,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  /// 🔍 Search Box
                                  if (_isSearchViewVisible)
                                    Padding(
                                      padding: EdgeInsets.only(
                                        left: 12,
                                        right: 12,
                                        top: 12,
                                      ),
                                      child: Material(
                                        elevation: 2,
                                        borderRadius: BorderRadius.circular(18),
                                        shadowColor: Colors.black12,

                                        child: TextField(
                                          controller: searchController,
                                          onChanged: (value) {
                                            final query = value.toLowerCase();
                                            setState(() {
                                              filteredItems_purchase =
                                                  query.isEmpty
                                                  ? purchase_list
                                                  : purchase_list
                                                        .where(
                                                          (item) => item.item
                                                              .toLowerCase()
                                                              .contains(query),
                                                        )
                                                        .toList();
                                            });
                                          },
                                          style: GoogleFonts.poppins(
                                            fontSize: 15,
                                          ),
                                          decoration: InputDecoration(
                                            hintText: 'Search...',
                                            prefixIcon: Icon(
                                              Icons.search,
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.onSurfaceVariant,
                                            ),
                                            filled: true,
                                            fillColor:
                                                Theme.of(context)
                                                    .inputDecorationTheme
                                                    .fillColor ??
                                                Theme.of(context)
                                                    .colorScheme
                                                    .surfaceContainerHighest,
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                  vertical: 14,
                                                  horizontal: 16,
                                                ),
                                            enabledBorder: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(18),
                                              borderSide: BorderSide(
                                                color: Theme.of(
                                                  context,
                                                ).dividerColor,
                                              ),
                                            ),
                                            focusedBorder: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(18),
                                              borderSide: const BorderSide(
                                                color: app_color,
                                                width: 1.5,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),

                                  const SizedBox(height: 10),

                                  /// ❌ No Data
                                  if (isVisibleNoDataFound)
                                    SizedBox(
                                      height: MediaQuery.of(context).size.height * 0.5,
                                      child: Center(
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.search_off_rounded,
                                              size: 48,
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.onSurfaceVariant,
                                            ),
                                            SizedBox(height: 12),
                                            Text(
                                              'No Records Found',
                                              style: GoogleFonts.poppins(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600,
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.onSurfaceVariant,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),

                                  /// 📦 Purchase List
                                  if (isVisiblePurchaseList)
                                    ListView.builder(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 8,
                                      ),
                                      shrinkWrap: true,
                                      physics:
                                          const NeverScrollableScrollPhysics(),
                                      itemCount: filteredItems_purchase.length,
                                      itemBuilder: (context, index) {
                                        final card =
                                            filteredItems_purchase[index];
                                        return _buildSoldPurchaseCard(
                                          context: context,
                                          item: card.item,
                                          qty: card.qty,
                                          lastDate: card.lastdate,
                                          rate: card.rate,
                                          isSale: false,
                                          onTap: () {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (context) =>
                                                    PartyClickedSoldPurchaseClicked(
                                                      startdate_string:
                                                          startDateString,
                                                      enddate_string:
                                                          endDateString,
                                                      type: "Purchase",
                                                      item: card.item,
                                                      unit: card.unit,
                                                      ledger: partyname,
                                                    ),
                                              ),
                                            );
                                          },
                                        );
                                      },
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          Visibility(
            visible: _isLoading,
            child: Center(child: AppLogoLoader()),
          ),
        ],
      ),
    );
  }

  Widget _buildModernTabButton({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            gradient: isSelected
                ? LinearGradient(
                    colors: [Colors.teal.shade400, Colors.teal.shade600],
                  )
                : LinearGradient(
                    colors: Theme.of(context).brightness == Brightness.dark
                        ? [
                            Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest
                                .withOpacity(0.7),
                            Theme.of(context).cardColor.withOpacity(0.95),
                          ]
                        : [Colors.grey.shade200, Colors.grey.shade100],
                  ),
            borderRadius: BorderRadius.circular(50),
            boxShadow: [
              if (isSelected)
                BoxShadow(
                  color: Colors.teal.withOpacity(0.2),
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              if (!isSelected &&
                  Theme.of(context).brightness == Brightness.light)
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.circle,
                size: 8,
                color: isSelected
                    ? Colors.white
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: isSelected
                      ? Colors.white
                      : Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void navigateToDetail(String vchtype, String amount) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PartyDrillDown(
          startdate_string: startDateString,
          enddate_string: endDateString,
          type: vchtype,
          total: formatAmount(amount),
          ledger: partyname,
        ),
      ),
    );
  }

  void navigateToReceivable(
    String type,
    String total,
    String variable,
    String variableType,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PartyTotalClickedRecPayClicked(
          startdate_string: startDateString,
          enddate_string: endDateString,
          type: type,
          total: total,
          ledger: partyname,
          variable: variable,
          variabletype: variableType,
        ),
      ),
    );
  }

  void navigateToPayable(
    String type,
    String total,
    String variable,
    String variableType,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PartyTotalClickedRecPayClicked(
          startdate_string: startDateString,
          enddate_string: endDateString,
          type: type,
          total: total,
          ledger: partyname,
          variable: variable,
          variabletype: variableType,
        ),
      ),
    );
  }

  void navigateToOrder(String type) {
    String vchtype = type == 'salesorder' ? 'sales' : 'purchase';

    print('vchtype -> $vchtype and type->$type');
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PartyClickedSalePurcOrder(
          startdate_string: startDateString,
          enddate_string: endDateString,
          type: type,
          ledger: partyname,
          vchtype: vchtype,
        ),
      ),
    );
  }
}

class SummaryExpansionCard extends StatelessWidget {
  final String title;
  final String totalAmount;
  final String lastDate;
  final String count;
  final String averageAmount;
  final List<dynamic> months;
  final VoidCallback onTapTotal;
  final String type;
  final String partyname;
  final int? decimal;
  final String? currencysymbol;

  const SummaryExpansionCard({
    super.key,
    required this.title,
    required this.totalAmount,
    required this.lastDate,
    required this.count,
    required this.averageAmount,
    required this.months,
    required this.onTapTotal,
    required this.type,
    required this.partyname,
    this.decimal,
    this.currencysymbol,
  });

  String formatAmountWithCrDr(String amount) {
    double value = double.tryParse(amount.replaceAll(',', '')) ?? 0.0;

    // ✅ Use provided decimal or fallback to 2
    final decimals = decimal ?? 2;
    final pattern = "#,##0.${'0' * decimals}";
    final formatted = NumberFormat(pattern).format(value.abs());

    // ✅ Add symbol only if provided
    final symbol = (currencysymbol != null && currencysymbol!.isNotEmpty)
        ? "${currencysymbol!} "
        : "";

    return value >= 0 ? "$symbol$formatted CR" : "$symbol$formatted DR";
  }

  IconData _getIconForTitle(String title) {
    switch (title.toLowerCase()) {
      case 'sales':
        return Icons.trending_up;
      case 'purchase':
        return Icons.shopping_cart_outlined;
      case 'receipt':
        return Icons.receipt_long;
      case 'payment':
        return Icons.payment;
      case 'credit note':
        return Icons.note_add_outlined;
      case 'debit note':
        return Icons.note_outlined;
      case 'journal':
        return Icons.book_online_outlined;
      default:
        return Icons.insert_chart_outlined_rounded;
    }
  }

  LinearGradient _getGradientForTitle(String title) {
    switch (title.toLowerCase()) {
      case 'sales':
        return LinearGradient(
          colors: [Colors.teal.shade400, Colors.teal.shade700],
        );
      case 'purchase':
        return LinearGradient(
          colors: [Colors.indigo.shade400, Colors.indigo.shade700],
        );
      case 'receipt':
        return LinearGradient(
          colors: [Colors.green.shade400, Colors.green.shade700],
        );
      case 'payment':
        return LinearGradient(
          colors: [Colors.redAccent.shade200, Colors.redAccent.shade400],
        );
      case 'credit note':
        return LinearGradient(
          colors: [Colors.orange.shade400, Colors.deepOrange.shade600],
        );
      case 'debit note':
        return LinearGradient(
          colors: [Colors.purple.shade400, Colors.purple.shade700],
        );
      case 'journal':
        return LinearGradient(
          colors: [Colors.brown.shade400, Colors.brown.shade700],
        );
      default:
        return LinearGradient(
          colors: [Colors.grey.shade400, Colors.grey.shade600],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final formattedTotal = formatAmountWithCrDr(totalAmount);

    return Container(
      margin: const EdgeInsets.only(left: 12, right: 12, top: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Theme.of(context).cardColor,
            Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(
              Theme.of(context).brightness == Brightness.dark ? 0.55 : 0.28,
            ),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black12.withOpacity(0.12),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ExpansionTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        tilePadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        childrenPadding: EdgeInsets.zero,
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                // 🔹 Gradient Icon Badge
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    gradient: _getGradientForTitle(title),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black12.withOpacity(0.2),
                        blurRadius: 8,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(
                    _getIconForTitle(title),
                    color: Colors.white,
                    size: 18,
                  ),
                ),

                const SizedBox(width: 12),

                // 🔹 Title Text
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ],
            ),

            SizedBox(width: 12),

            // 🔹 Total value (right aligned, wraps to next line if long)
            Flexible(
              child: Text(
                formattedTotal,
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.tealAccent.shade100
                      : Colors.teal.shade700,
                ),
                textAlign: TextAlign.right, // ✅ right align
                softWrap: true, // ✅ allow multi-line
                overflow: TextOverflow.visible, // ✅ prevent clipping
              ),
            ),
          ],
        ),

        children: [
          Divider(thickness: 1, color: Theme.of(context).dividerColor),

          // 🔹 Detail Rows
          DetailRowTile(label: 'Last $title Date', value: formatdate(lastDate)),
          DetailRowTile(label: 'No. of Invoices', value: count),
          DetailRowTile(
            label: 'Avg Invoice Amount',
            value: '${formatAmountWithCrDr(averageAmount)}',
          ),

          const SizedBox(height: 6),
          Divider(thickness: 1, color: Theme.of(context).dividerColor),

          // 🔹 Monthly Breakdown Expansion
          Theme(
            data: Theme.of(context).copyWith(
              dividerColor: Colors.transparent,
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
            ),
            child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 18),
              title: Row(
                children: [
                  // 🔹 Left side (icon + "Monthly Breakdown")
                  Expanded(
                    child: Row(
                      children: [
                        Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.blueGrey.shade400,
                                Colors.blueGrey.shade700,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.timeline_rounded,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Monthly Breakdown',
                            style: GoogleFonts.poppins(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                            overflow: TextOverflow.visible, // ✅ safe truncate
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 8),

                  // 🔹 Right side (formatted total)
                  Flexible(
                    child: Text(
                      formattedTotal,
                      style: GoogleFonts.poppins(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      overflow: TextOverflow.visible,
                      textAlign: TextAlign.right, // ✅ align safely
                    ),
                  ),
                ],
              ),

              children: [
                // 🔹 Total Row
                GestureDetector(
                  onTap: onTapTotal,
                  child: Container(
                    margin: const EdgeInsets.only(
                      left: 16,
                      right: 16,
                      bottom: 12,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black12.withOpacity(0.05),
                          blurRadius: 6,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.teal.shade400,
                                    Colors.teal.shade700,
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.link,
                                size: 16,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Total',
                              style: GoogleFonts.poppins(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w500,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            Text(
                              formattedTotal,
                              style: GoogleFonts.poppins(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                color:
                                    Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? Colors.white10
                                    : Colors.grey.shade200,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.chevron_right_rounded,
                                size: 16,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // 🔹 Monthly Rows
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: months.length,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  itemBuilder: (context, index) {
                    final card = months[index];
                    final month = card.mname;
                    final rawAmount = card.total.toString();
                    final formattedAmount = formatAmountWithCrDr(rawAmount);

                    return GestureDetector(
                      onTap: () {
                        final dateTimeFormatter = DateFormat('MMMM yyyy');
                        final date = dateTimeFormatter.parse(month);
                        final startStr = DateFormat(
                          'yyyyMMdd',
                        ).format(DateTime(date.year, date.month, 1));
                        final endStr = DateFormat(
                          'yyyyMMdd',
                        ).format(DateTime(date.year, date.month + 1, 0));

                        if (type == "Receipt" ||
                            type == "Payment" ||
                            type == "Journal") {
                          String amount = formatAmount(rawAmount);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => PartyTotalClickedRest(
                                startdate_string: startStr,
                                enddate_string: endStr,
                                type: type,
                                total: amount,
                                ledger: partyname,
                              ),
                            ),
                          );
                        } else {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => PartyDrillDown(
                                startdate_string: startStr,
                                enddate_string: endStr,
                                type: type,
                                total: formatAmount(rawAmount),
                                ledger: partyname,
                              ),
                            ),
                          );
                        }
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          borderRadius: BorderRadius.circular(18),
                          border:
                              Theme.of(context).brightness == Brightness.dark
                              ? Border.all(
                                  color: Colors.white.withOpacity(0.10),
                                  width: 1,
                                )
                              : null,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black12.withOpacity(0.05),
                              blurRadius: 6,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // 🔹 Left side (icon + month text)
                            Expanded(
                              child: Row(
                                children: [
                                  Container(
                                    width: 30,
                                    height: 30,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          Colors.indigo.shade400,
                                          Colors.indigo.shade700,
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(
                                      Icons.calendar_month_rounded,
                                      size: 16,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    // ✅ Prevents overflow
                                    child: Text(
                                      month,
                                      style: GoogleFonts.poppins(
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.w500,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurface,
                                      ),
                                      overflow: TextOverflow
                                          .visible, // ✅ truncate safely
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(width: 6),

                            // 🔹 Right side (amount + arrow)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  formattedAmount,
                                  style: GoogleFonts.poppins(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w600,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
                                  ),
                                  overflow: TextOverflow.visible,
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.all(3),
                                  decoration: BoxDecoration(
                                    color:
                                        Theme.of(context).brightness ==
                                            Brightness.dark
                                        ? Colors.white10
                                        : Colors.grey.shade200,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.chevron_right_rounded,
                                    size: 16,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
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
        ],
      ),
    );
  }
}

class DetailRowTile extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onTap;

  const DetailRowTile({
    required this.label,
    required this.value,
    this.onTap,
    super.key,
  });

  // Gradient chooser
  LinearGradient _getGradient(String label) {
    final lower = label.toLowerCase();
    if (lower.contains('last') && lower.contains('date')) {
      return LinearGradient(
        colors: [Colors.indigo.shade400, Colors.indigo.shade700],
      );
    } else if (lower.contains('no. of invoices')) {
      return LinearGradient(
        colors: [Colors.orange.shade400, Colors.deepOrange.shade600],
      );
    } else if (lower.contains('avg invoice amount')) {
      return LinearGradient(
        colors: [Colors.green.shade400, Colors.green.shade700],
      );
    }
    return LinearGradient(colors: [Colors.grey.shade400, Colors.grey.shade600]);
  }

  // Icon chooser
  IconData _getIcon(String label) {
    final lower = label.toLowerCase();
    if (lower.contains('last') && lower.contains('date')) {
      return Icons.calendar_today_rounded;
    } else if (lower.contains('no. of invoices')) {
      return Icons.receipt_long_rounded;
    } else if (lower.contains('avg invoice amount')) {
      return Icons.bar_chart_rounded;
    }
    return Icons.info_outline;
  }

  @override
  Widget build(BuildContext context) {
    final gradient = _getGradient(label);
    final icon = _getIcon(label);

    final row = Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? Colors.transparent
            : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          // 🔹 Gradient Icon
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              gradient: gradient,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: gradient.colors.last.withOpacity(0.25),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Icon(icon, size: 16, color: Colors.white),
          ),
          const SizedBox(width: 12),

          // 🔹 Label
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 13.5,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),

          // 🔹 Value
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );

    return onTap != null ? GestureDetector(onTap: onTap, child: row) : row;
  }
}

class PendingOrderTile extends StatelessWidget {
  final String label;
  final String amount;
  final VoidCallback onTap;
  final int? decimal;
  final String? currencysymbol;

  const PendingOrderTile({
    super.key,
    required this.label,
    required this.amount,
    required this.onTap,
    this.decimal,
    this.currencysymbol,
  });

  LinearGradient _getGradient(String label) {
    if (label.toLowerCase().contains('sales')) {
      return LinearGradient(
        colors: [Colors.teal.shade400, Colors.teal.shade700],
      );
    } else if (label.toLowerCase().contains('purchase')) {
      return LinearGradient(
        colors: [Colors.deepOrange.shade400, Colors.deepOrange.shade700],
      );
    }
    return LinearGradient(colors: [Colors.grey.shade400, Colors.grey.shade600]);
  }

  IconData _getIcon(String label) {
    if (label.toLowerCase().contains('sales')) {
      return Icons.shopping_cart_outlined;
    } else if (label.toLowerCase().contains('purchase')) {
      return Icons.local_shipping_outlined;
    }
    return Icons.receipt_long_outlined;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black12.withOpacity(0.12),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 🔹 Left (Icon + Label) → 50%
            Expanded(
              flex: 1,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      gradient: _getGradient(label),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(_getIcon(label), color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      style: GoogleFonts.poppins(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      softWrap: true,
                    ),
                  ),
                ],
              ),
            ),

            SizedBox(width: 5),
            // 🔹 Right (Amount + Arrow) → 50%
            Expanded(
              flex: 1,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Flexible(
                    child: Text(
                      formatCurrency(
                        amount,
                        decimals: decimal ?? 2,
                        currencySymbol: currencysymbol ?? '',
                        showCrDr: true,
                      ),
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      softWrap: true,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white10
                          : Colors.grey.shade200,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ReceivableBreakdownCard extends StatelessWidget {
  final String total;
  final String onAccount;
  final List<Map<String, dynamic>> rows;
  final VoidCallback onTotalTap;
  final VoidCallback? onAccountTap;

  final int? decimal;
  final String? currencysymbol;

  const ReceivableBreakdownCard({
    super.key,
    required this.total,
    required this.onAccount,
    required this.rows,
    required this.onTotalTap,
    this.onAccountTap,

    this.decimal,
    this.currencysymbol,
  });

  @override
  Widget build(BuildContext context) {
    return _BreakdownCardBase(
      title: 'Receivable',
      icon: Icons.call_received,
      gradient: LinearGradient(
        colors: [Colors.green.shade400, Colors.green.shade700],
      ),
      total: total,
      onAccount: onAccount,
      rows: rows,
      onTotalTap: onTotalTap,
      decimal: decimal,
      currencysymbol: currencysymbol,
    );
  }
}

class PayableBreakdownCard extends StatelessWidget {
  final String total;
  final String onAccount;
  final List<Map<String, dynamic>> rows;
  final VoidCallback onTotalTap;
  final int? decimal;
  final String? currencysymbol;

  const PayableBreakdownCard({
    super.key,
    required this.total,
    required this.onAccount,
    required this.rows,
    required this.onTotalTap,
    this.decimal,
    this.currencysymbol,
  });

  @override
  Widget build(BuildContext context) {
    return _BreakdownCardBase(
      title: 'Payable',
      icon: Icons.call_made,
      gradient: LinearGradient(
        colors: [Colors.red.shade400, Colors.red.shade700],
      ),
      total: total,
      onAccount: onAccount,
      rows: rows,
      onTotalTap: onTotalTap,
      decimal: decimal,
      currencysymbol: currencysymbol,
    );
  }
}

class _BreakdownCardBase extends StatelessWidget {
  final String title;
  final IconData icon;
  final LinearGradient gradient;
  final String total;
  final String onAccount;
  final List<Map<String, dynamic>> rows;
  final VoidCallback onTotalTap;
  final int? decimal;
  final String? currencysymbol;

  const _BreakdownCardBase({
    required this.title,
    required this.icon,
    required this.gradient,
    required this.total,
    required this.onAccount,
    required this.rows,
    required this.onTotalTap,
    this.decimal,
    this.currencysymbol,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 12, right: 12, top: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Theme.of(context).cardColor,
            Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(
              Theme.of(context).brightness == Brightness.dark ? 0.55 : 0.28,
            ),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black12.withOpacity(0.12),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ExpansionTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        tilePadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        childrenPadding: EdgeInsets.zero,
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                // 🔹 Gradient Icon Badge (same as SummaryExpansionCard)
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    gradient: gradient,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black12.withOpacity(0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(icon, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            Text(
              formatAmount(total),
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.tealAccent.shade100
                    : Colors.teal.shade700,
              ),
            ),
          ],
        ),
        children: [
          Divider(thickness: 1, color: Theme.of(context).dividerColor),

          // Different icon + color per row
          _DetailRowTile(
            label: 'Total',
            value: formatAmount(total),
            icon: Icons.summarize,
            iconColor: Colors.teal,
            onTap: onTotalTap,
          ),
          _DetailRowTile(
            label: 'On Account',
            value: formatAmount(onAccount),
            icon: Icons.account_balance_wallet,
            iconColor: Colors.indigo,
            // onTap: onTotalTap,
          ),

          Divider(thickness: 1, color: Theme.of(context).dividerColor),

          for (final row in rows)
            _DetailRowTile(
              label: row['label'] ?? '',
              value: row['value'] ?? '',
              icon: Icons.circle, // 👈 you can map this dynamically
              iconColor: Colors.orange, // 👈 different color per row
              onTap: row['onTap'],
            ),
        ],
      ),
    );
  }
}

class _DetailRowTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color iconColor;
  final VoidCallback? onTap;

  const _DetailRowTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.iconColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 14, color: iconColor),
              ),
              const SizedBox(width: 10),
              Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
          Row(
            children: [
              Text(
                value,
                style: GoogleFonts.poppins(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              if (onTap != null)
                Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: Icon(
                    Icons.chevron_right,
                    size: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ],
      ),
    );

    return onTap != null ? GestureDetector(onTap: onTap, child: row) : row;
  }
}

Widget _buildSoldPurchaseCard({
  required BuildContext context,
  required String item,
  required String qty,
  required String lastDate,
  required String rate,
  required bool isSale,
  required VoidCallback onTap,
}) {
  return GestureDetector(
    onTap: onTap,
    child: Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Theme.of(context).brightness == Brightness.dark
            ? Border.all(color: Colors.white.withOpacity(0.10), width: 1)
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black12.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 🔹 Item + Qty badge
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 📦 Icon + Item Name
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isSale
                              ? [Colors.teal.shade400, Colors.teal.shade700]
                              : [
                                  Colors.deepOrange.shade400,
                                  Colors.deepOrange.shade700,
                                ],
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.inventory_2_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 10),
                    // 👇 Flexible text prevents overflow
                    Expanded(
                      child: Text(
                        item,
                        softWrap: true,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 🧮 Qty badge (fixed size, aligned right)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: (isSale ? Colors.teal : Colors.deepOrange).withOpacity(
                    0.1,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  "Qty: $qty",
                  style: GoogleFonts.poppins(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: isSale
                        ? Colors.teal.shade700
                        : Colors.deepOrange.shade700,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // 🔹 Last Date + Rate row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 📅 Date
              Flexible(
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.blueGrey.shade400,
                            Colors.blueGrey.shade700,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.calendar_today,
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        formatdate(lastDate),
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          fontSize: 13.2,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 💰 Rate (icon left + text top-aligned, wraps neatly)
              Flexible(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment
                      .center, // 👈 aligns icon with top of text
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.orange.shade300,
                            Colors.deepOrange.shade400,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.price_change_rounded,
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // 👇 this makes sure long text wraps and stays aligned to the right
                    Flexible(
                      child: Text(
                        CurrencyFormatter.formatCurrency_normal(rate),
                        textAlign: TextAlign.right,
                        softWrap: true,
                        overflow: TextOverflow.visible,
                        style: GoogleFonts.poppins(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
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
  );
}

String formatCurrency(
  String amount, {
  int decimals = 2,
  String currencySymbol = '',
  bool showCrDr = false,
}) {
  double value =
      double.tryParse(
        amount.replaceAll(',', '').replaceAll(RegExp(r'[^0-9.-]'), ''),
      ) ??
      0.0;
  final formatter = NumberFormat.currency(
    locale: 'en_US',
    symbol: currencySymbol.isNotEmpty ? '$currencySymbol ' : '',
    decimalDigits: decimals,
  );

  String formatted = formatter.format(value.abs());

  if (showCrDr) {
    return value >= 0 ? "$formatted CR" : "$formatted DR";
  }
  return formatted;
}
