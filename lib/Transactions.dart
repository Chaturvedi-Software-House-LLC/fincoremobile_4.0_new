import 'dart:convert';
import 'dart:ui';
import 'package:FincoreGo/Dashboard.dart';
import 'package:FincoreGo/utils/currency_helper.dart';
/*import 'package:FincoreGo/currencyFormat.dart';*/
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'SerialSelect.dart';
import 'package:http/http.dart' as http;
import 'TransactionClicked.dart';
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
import 'widgets/scroll_fab.dart';

class transactions {
  final String ledger;
  final String vchname;
  final String vchno;
  final double amount;
  final String vchdate;
  final String isoptional;
  final String ispostdated;
  final String refno;
  final String refdate;
  final String masterid;

  transactions({
    required this.ledger,
    required this.vchname,
    required this.vchno,
    required this.amount,
    required this.vchdate,
    required this.isoptional,
    required this.ispostdated,
    required this.refno,
    required this.refdate,
    required this.masterid,
  });

  factory transactions.fromJson(Map<String, dynamic> json) {
    return transactions(
      ledger: json['ledger'].toString(),
      vchname: json['vchname'].toString(),
      vchno: json['vchno'].toString(),
      amount: double.tryParse(json['amount'].toString()) ?? 0,
      vchdate: json['vchdate'].toString(),
      isoptional: json['isoptional'].toString(),
      refno: json['refno'].toString(),
      refdate: json['refdate'].toString(),
      masterid: json['masterid'].toString(),
      ispostdated: json['ispostdated'].toString(),
    );
  }
}

class Transactions extends StatefulWidget {
  @override
  _TransactionsPageState createState() => _TransactionsPageState();
}

class _TransactionsPageState extends State<Transactions>
    with TickerProviderStateMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  bool isVisiblePostdatedTransaction =
      false; // to adjust post dated transactions visibility

  bool isClicked_transaction = true;

  late String startdate_text = "", enddate_text = "";

  String selectedSortOption = '', token = '';

  int counter = 0;

  bool isVisibleAlias = true;

  DateTime _startDate = DateTime.now();

  DateTime _endDate = DateTime.now().add(Duration(days: 7));

  List<transactions> filteredItems_transactions =
      []; // Initialize an empty list to hold the filtered items

  String transactions_count = "0";

  final List<String> itemList = [
    'Default',
    'Newest to Oldest',
    'Oldest to Newest',
    'A->Z',
    'Z->A',
    'Amount High to Low',
    'Amount Low to High',
  ];

  String startDateString = "", endDateString = "";

  bool _isTextEnabled = true;

  bool _isDashVisible = true,
      _isEnddateVisible = true,
      _IsSizeboxVisible = true;

  String? SecuritybtnAcessHolder;
  bool isDashEnable = true,
      isRolesEnable = true,
      isUserEnable = true,
      isRolesVisible = true,
      isUserVisible = true,
      _isSearchViewVisible = false,
      _isAllList = false;

  String email = "";
  String name = "";

  String? datetype;

  late int? decimal;

  TextEditingController searchController = TextEditingController();

  bool isVisibleNoDataFound = false, isSortVisible = false;

  String ledgroups =
      "Sundry Debtors, Sundry Creditors, Customers, Suppliers, Creditors, Debtors";

  late GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey;

  late SharedPreferences prefs;

  ScrollController _scrollController_transactions = ScrollController();
  final ScrollController _scrollFabController = ScrollController();

  void filterPostDatedTransactions() {
    setState(() {
      /*if (isVisiblePostdatedTransaction) {
        transactions_list = transactions_list
            .where((transaction) => transaction.ispostdated == '1' || transaction.ispostdated == '0')
            .toList();
      } */

      if (!isVisiblePostdatedTransaction) {
        transactions_list = transactions_list
            .where((transaction) => transaction.ispostdated == '0')
            .toList();
      }
    });
  }

  dynamic _selecteddate;
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

  late NumberFormat currencyFormat;

  late String currencysymbol = '';

  String? hostname = "",
      company = "",
      serial_no = "",
      company_lowercase = "",
      username = "";

  bool _isLoading = false;

  String? HttpURL_Parent, HttpURL_transaction;

  dynamic _selectedtransaction = "All Transactions";

  List<String> spinner_list = ["All Transactions"];

  List<transactions> transactions_list = [];

  void _showSelectionWindow(BuildContext context) {
    final List<IconData> icons = [
      Icons.sort_rounded,
      Icons.date_range_sharp,
      Icons.date_range_sharp,
      Icons.sort_by_alpha_rounded,
      Icons.sort_by_alpha_rounded,
      Icons.attach_money_outlined,
      Icons.attach_money_outlined,
    ];

    // Replace this list with your actual list data

    double totalHeight =
        itemList.length * 50.0 +
        30.0 +
        50.0; // Assuming each item has a height of 50 and adding padding height

    showModalBottomSheet<void>(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      context: context,
      builder: (BuildContext context) {
        return Container(
          constraints: BoxConstraints(
            maxHeight:
                totalHeight, // Set the maximum height of the selection window with additional padding
          ),
          color: Theme.of(context).colorScheme.surface,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  'Sort', // Replace with your desired heading text
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
              Expanded(
                // Wrap the ListView.builder with Expanded
                child: ListView.builder(
                  itemCount: itemList.length,
                  itemExtent: 50, // Set the height of each item in the list
                  itemBuilder: (BuildContext context, int index) {
                    // Replace this with your custom tile widget
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          selectedSortOption =
                              itemList[index]; // Update the selected value
                        });
                        // Now, you can use a switch or if-else statement to check the selected value
                        switch (selectedSortOption) {
                          case 'Default':
                            sortByDefault(); // Call the sorting function
                            break;
                          case 'Newest to Oldest':
                            sortByDateHightoLow(); // Call the sorting function
                            break;
                          case 'Oldest to Newest':
                            sortByDateLowtoHigh(); // Call the sorting function
                            break;
                          case 'A->Z':
                            sortByAlphabetAtoZ(); // Call the sorting function
                            break;
                          case 'Z->A':
                            sortByAlphabetZtoA(); // Call the sorting function
                            break;
                          case 'Amount High to Low':
                            sortByAmountHightoLow(); // Call the sorting function
                            break;
                          case 'Amount Low to High':
                            sortByAmountLowtoHigh(); // Call the sorting function
                            break;
                        }
                        print('Tile $index selected');
                        Navigator.pop(
                          context,
                        ); // Close the selection window after a tile is selected
                      },
                      child: Container(
                        child: ListTile(
                          leading: Icon(
                            icons[index],
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ), // Add the icon to each list tile
                          title: Text(
                            itemList[index],
                            style: GoogleFonts.poppins(
                              fontWeight: itemList[index] == selectedSortOption
                                  ? FontWeight.bold
                                  : FontWeight
                                        .normal, // Apply bold style to the text if the tile is selected
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          trailing: itemList[index] == selectedSortOption
                              ? Icon(Icons.check, color: Color(0xFF30D5C8))
                              : null, // Show arrow icon if the tile is selected
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void sortByDefault() {
    setState(() {
      if (filteredItems_transactions.isNotEmpty) {
        filteredItems_transactions = List.from(transactions_list);
        transactions_count = filteredItems_transactions.length.toString();

        if (_scrollController_transactions.hasClients) {
          _scrollController_transactions.animateTo(
            0.0,
            duration: Duration(milliseconds: 500),
            curve: Curves.easeInOut,
          );
        }
      }
    });
  }

  void sortByAlphabetAtoZ() {
    setState(() {
      if (filteredItems_transactions.isNotEmpty) {
        filteredItems_transactions.sort(
          (a, b) => a.vchname.compareTo(b.vchname),
        );
        transactions_count = filteredItems_transactions.length.toString();

        _scrollController_transactions.animateTo(
          0.0,
          duration: Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  void sortByAlphabetZtoA() {
    setState(() {
      if (filteredItems_transactions.isNotEmpty) {
        filteredItems_transactions.sort(
          (a, b) => b.vchname.compareTo(a.vchname),
        );
        transactions_count = filteredItems_transactions.length.toString();

        _scrollController_transactions.animateTo(
          0.0,
          duration: Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  void sortByDateLowtoHigh() {
    setState(() {
      if (filteredItems_transactions.isNotEmpty) {
        filteredItems_transactions.sort(
          (a, b) => a.vchdate.compareTo(b.vchdate),
        );
        transactions_count = filteredItems_transactions.length.toString();

        _scrollController_transactions.animateTo(
          0.0,
          duration: Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  void sortByDateHightoLow() {
    setState(() {
      if (filteredItems_transactions.isNotEmpty) {
        filteredItems_transactions.sort(
          (a, b) => b.vchdate.compareTo(a.vchdate),
        );
        transactions_count = filteredItems_transactions.length.toString();

        _scrollController_transactions.animateTo(
          0.0,
          duration: Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  void sortByAmountLowtoHigh() {
    setState(() {
      if (filteredItems_transactions.isNotEmpty) {
        filteredItems_transactions.sort((a, b) => a.amount.compareTo(b.amount));
        transactions_count = filteredItems_transactions.length.toString();

        if (_scrollController_transactions.hasClients) {
          _scrollController_transactions.animateTo(
            0.0,
            duration: Duration(milliseconds: 500),
            curve: Curves.easeInOut,
          );
        }
      }
    });
  }

  void sortByAmountHightoLow() {
    setState(() {
      if (filteredItems_transactions.isNotEmpty) {
        filteredItems_transactions.sort((a, b) => b.amount.compareTo(a.amount));
        transactions_count = filteredItems_transactions.length.toString();

        _scrollController_transactions.animateTo(
          0.0,
          duration: Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  String formatledger_report(String ledger) {
    if (ledger == 'null') {
      ledger = '-';
    }
    return ledger;
  }

  Future<void> generateAndSharePDF_Transactions() async {
    final font = pw.Font.ttf(
      await rootBundle.load("assets/fonts/NotoSans.ttf"),
    );
    final pdf = pw.Document();

    final companyName = company ?? '';
    final reportname = 'Transactions Summary';
    final parentname = _selectedtransaction ?? '';

    String startdate = formatdate(startDateString);
    String enddate = formatdate(endDateString);

    final headersRow3 = [
      'Vch No',
      'Vch Name',
      'Vch Date',
      'Party Name',
      'Amount',
    ];

    final itemsPerPage = 8; // Adjust this value as needed
    final pageCount = (transactions_list.length / itemsPerPage).ceil();

    for (int pageNumber = 0; pageNumber < pageCount; pageNumber++) {
      final startIndex = pageNumber * itemsPerPage;
      final endIndex = (pageNumber + 1) * itemsPerPage;
      final itemsSubset = transactions_list.sublist(
        startIndex,
        endIndex > transactions_list.length
            ? transactions_list.length
            : endIndex,
      );

      final tableSubsetRows = itemsSubset.map((item) {
        return [
          item.vchno,
          item.vchname,
          convertDateFormat(item.vchdate),
          formatledger_report(item.ledger),
          formatAmount(item.amount.toString()),
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
        cellPadding: const pw.EdgeInsets.all(5),
        columnWidths: {
          0: const pw.FractionColumnWidth(0.4),
          1: const pw.FractionColumnWidth(0.4),
          2: const pw.FractionColumnWidth(0.4),
          3: const pw.FractionColumnWidth(0.4),
          4: const pw.FractionColumnWidth(0.4),
        },
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: font),
        cellStyle: pw.TextStyle(fontSize: 12, font: font),
        rowDecoration: pw.BoxDecoration(
          border: pw.Border(
            top: pw.BorderSide(width: 1),
            bottom: pw.BorderSide(width: 1),
          ),
        ),
        headers: headersRow3,
        data: tableSubsetRows,
      );

      pdf.addPage(
        pw.Page(
          build: (pw.Context context) {
            return pw.Container(
              child: pw.Column(
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
                        'Vch Type:',
                        style: pw.TextStyle(
                          fontSize: 16,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(width: 5),
                      pw.Text(
                        parentname,
                        style: pw.TextStyle(
                          fontSize: 16,
                          fontWeight: pw.FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 10),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.center,
                    children: [
                      pw.Text(
                        'Date Range:',
                        style: pw.TextStyle(
                          fontSize: 16,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(width: 5),
                      pw.Text(
                        startdate,
                        style: pw.TextStyle(
                          fontSize: 16,
                          fontWeight: pw.FontWeight.normal,
                        ),
                      ),
                      pw.Text(
                        " - ",
                        style: pw.TextStyle(
                          fontSize: 16,
                          fontWeight: pw.FontWeight.normal,
                        ),
                      ),
                      pw.Text(
                        enddate,
                        style: pw.TextStyle(
                          fontSize: 16,
                          fontWeight: pw.FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 20),
                  pw.Expanded(child: tableSubset),
                ],
              ),
            );
          },
        ),
      );
    }

    final pdfData = await pdf.save();
    final tempDir = await getTemporaryDirectory();
    final tempFilePath = '${tempDir.path}/Transactions.pdf';
    final file = File(tempFilePath);
    await file.writeAsBytes(pdfData);

    // ✅ Share via XFile
    await Share.shareXFiles([
      XFile(tempFilePath),
    ], text: 'Sharing Transactions Report of $companyName');
  }

  Future<void> generateAndShareCSV_Transactions() async {
    final List<List<dynamic>> csvData = [];
    final headersRow = [
      'Vch No',
      'Vch Name',
      'Vch Date',
      'Party Name',
      'Amount',
    ];
    csvData.add(headersRow);

    for (final item in transactions_list) {
      final rowData = [
        item.vchno,
        item.vchname,
        convertDateFormat(item.vchdate),
        formatledger_report(item.ledger),
        formatAmount(item.amount.toString()),
      ];
      csvData.add(rowData);
    }

    final csvString = const ListToCsvConverter().convert(csvData);

    final tempDir = await Directory.systemTemp.createTemp();
    final tempFilePath = '${tempDir.path}/Transactions.csv';
    final file = File(tempFilePath);
    await file.writeAsString(csvString);

    // ✅ Share via XFile
    await Share.shareXFiles([
      XFile(tempFilePath),
    ], text: 'Sharing Transactions Report of $company');
  }

  String formatAlias(String alias) {
    String formated_alias = "";

    if (alias == 'null' || alias == '' || alias == null) {
      formated_alias = '';
    } else {
      formated_alias = alias;
    }

    return formated_alias;
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

          fetchMainData();
        });
      }
    }
  }

  String convertDateFormat(String dateStr) {
    // Parse the input date string
    DateTime date = DateTime.parse(dateStr);

    // Format the date to the desired output format
    String formattedDate = DateFormat("dd-MMM-yyyy").format(date);

    return formattedDate;
  }

  Future<void> fetchParentData(final String ledGroups) async {
    setState(() {
      _isLoading = true;
    });

    try {
      final url = Uri.parse(HttpURL_Parent!);

      Map<String, String> headers = {
        'Authorization': 'Bearer $token',
        "Content-Type": "application/json",
      };

      final response = await http.post(url, headers: headers);

      if (response.statusCode == 200) {
        List<dynamic> data = jsonDecode(response.body);
        for (var item in data) {
          String vchname = item['vchname'];
          spinner_list.add(vchname);
        }
        setState(() {
          _selectedtransaction = spinner_list[0];
        });
        fetchtransactionsData();
      } else {
        Map<String, dynamic> data = json.decode(response.body);
        String error = '';

        if (data.containsKey('error')) {
          setState(() {
            error = data['error'];
          });
        } else {
          error = 'Something went wrong!!!';
        }

        Fluttertoast.showToast(msg: error);
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      print(e);
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

      startdate_text = startDay + "-" + startMonth + "-" + startYear.toString();
      enddate_text = endDay + "-" + endMonth + "-" + endYear.toString();

      fetchMainData();

      setState(() {
        _isTextEnabled = false;
        _isDashVisible = false;
        _isEnddateVisible = false;
        _IsSizeboxVisible = false;
      });
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

      fetchMainData();

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

      startdate_text = startDay + "-" + startMonth + "-" + startYear.toString();
      enddate_text = endDay + "-" + endMonth + "-" + endYear.toString();

      fetchMainData();

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

      fetchMainData();

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

      print(startDateString);
      print(endDateString);

      fetchMainData();

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

      fetchMainData();

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

      fetchMainData();

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

        print(startDateString);
        print(endDateString);

        fetchMainData();
      });
    }
  }

  late String PostDatedTransactionsHolder;

  void fetchMainData() {
    if (_selectedtransaction == "All Transactions") {
      String parent = "";
      fetchall_transactions(startDateString, endDateString, parent, 'amount');
    } else {
      String parent = _selectedtransaction;
      fetchall_transactions(startDateString, endDateString, parent, 'amount');
    }
  }

  void fetchtransactionsData() {
    _handleDate(_selecteddate);
  }

  Future<void> fetchall_transactions(
    final String startdate,
    final String enddate,
    final String vchname,
    final String orderby,
  ) async {
    setState(() {
      transactions_count = "0";
      _isLoading = true;
      _isAllList = false;
      isClicked_transaction = true;
      isVisibleNoDataFound = false;
      isSortVisible = false;
    });

    filteredItems_transactions.clear();

    transactions_list.clear();

    try {
      final url = Uri.parse(HttpURL_transaction!);

      Map<String, String> headers = {
        'Authorization': 'Bearer $token',
        "Content-Type": "application/json",
      };

      var body = jsonEncode({
        'startdate': startdate,
        'enddate': enddate,
        'vchname': vchname,
        'orderby': orderby,
      });

      final response = await http.post(url, body: body, headers: headers);

      if (response.statusCode == 200) {
        final List<dynamic> values_list = jsonDecode(response.body);

        if (values_list != null) {
          isVisibleNoDataFound = false;

          transactions_list.addAll(
            values_list.map((json) => transactions.fromJson(json)).toList(),
          );

          filterPostDatedTransactions();

          filteredItems_transactions = transactions_list;

          setState(() {
            transactions_count = filteredItems_transactions.length.toString();
            _isAllList = true;
            _isLoading = false;
          });
        } else {
          throw Exception('Failed to fetch data');
        }
      } else {
        Map<String, dynamic> data = json.decode(response.body);
        String error = '';

        if (data.containsKey('error')) {
          setState(() {
            error = data['error'];
          });
        } else {
          error = 'Something went wrong!!!';
        }

        Fluttertoast.showToast(msg: error);

        setState(() {
          transactions_count = filteredItems_transactions.length.toString();
          _isAllList = false;
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _isAllList = false;
        _isLoading = false;
      });
      print(e);
    }

    setState(() {
      if (transactions_list.isEmpty) {
        transactions_count = "0";
        _isAllList = false;
        isVisibleNoDataFound = true;
        isSortVisible = false;
      } else {
        isSortVisible = true;
        switch (selectedSortOption) {
          case 'Default':
            sortByDefault(); // Call the sorting function
            break;
          case 'Newest to Oldest':
            sortByDateHightoLow(); // Call the sorting function
            break;
          case 'Oldest to Newest':
            sortByDateLowtoHigh(); // Call the sorting function
            break;
          case 'A->Z':
            sortByAlphabetAtoZ(); // Call the sorting function
            break;
          case 'Z->A':
            sortByAlphabetZtoA(); // Call the sorting function
            break;
          case 'Amount High to Low':
            sortByAmountHightoLow(); // Call the sorting function
            break;
          case 'Amount Low to High':
            sortByAmountLowtoHigh(); // Call the sorting function
            break;
        }
      }
      _isLoading = false;
    });
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
      datetype = prefs.getString('datetype') ?? date_range.first;
      decimal = prefs?.getInt('decimalplace') ?? 2;

      String? currencyCode = '';

      try {
        currencyCode = prefs.getString('currencycode');
        if (currencyCode == null) {
          currencyCode = 'AED';
        }
      } catch (e) {
        if (currencyCode == null) {
          currencyCode = 'AED';
        }
      }
      currencyFormat = new NumberFormat();

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

      PostDatedTransactionsHolder =
          prefs.getString("postdatedtransactions") ?? "True";

      if (PostDatedTransactionsHolder == "True") {
        setState(() {
          isVisiblePostdatedTransaction = true;
        });
      } else {
        setState(() {
          isVisiblePostdatedTransaction = false;
        });
      }

      _selecteddate = datetype;

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
    try {
      selectedSortOption = prefs.getString('sort')!;
      if (selectedSortOption == null || selectedSortOption == 'null') {
        selectedSortOption = 'Default';
      }
    } catch (e) {
      selectedSortOption = 'Default';
    }

    HttpURL_Parent =
        '$hostname/api/voucher/getvoucherNames/$company_lowercase/$serial_no';
    HttpURL_transaction =
        '$hostname/api/voucher/getvouchers/$company_lowercase/$serial_no';

    SecuritybtnAcessHolder = prefs.getString('secbtnaccess');

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
    fetchParentData(ledgroups);
  }

  @override
  void initState() {
    super.initState();
    _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
    _initSharedPreferences();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      checkCurrencyMismatch(context);
    });
  }

  @override
  void dispose() {
    _scrollFabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: const AppBottomNav(
        activeTab: AppBottomNavTab.transactions,
      ),
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
                  MediaQuery.of(context).size.width - (kToolbarHeight * 2.4),
            ),
            child: GestureDetector(
              onTap: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => SerialSelect()),
                );
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      company ?? '',

                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  SizedBox(width: 4),
                  Icon(Icons.arrow_drop_down, color: Colors.white),
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
            /*IconButton(
              onPressed: () {
                counter++;

                _isSearchViewVisible =! _isSearchViewVisible;

                setState(() {
                  searchController.clear();
                  filteredItems_transactions = transactions_list;
                  transactions_count = filteredItems_transactions.length.toString();

                });
              },
              icon: Icon(
                Icons.search,
                color: Colors.white,
                size: 30,
              ),
            ),*/
            IconButton(
              onPressed: () {
                final RenderBox button =
                    context.findRenderObject() as RenderBox;
                final RenderBox overlay =
                    Overlay.of(context).context.findRenderObject() as RenderBox;
                final Offset buttonPosition = button.localToGlobal(
                  Offset.zero,
                  ancestor: overlay,
                );

                showMenu(
                  context: context,
                  position: RelativeRect.fromLTRB(
                    overlay.size.width - buttonPosition.dx,
                    buttonPosition.dy - button.size.height,
                    overlay.size.width - buttonPosition.dx,
                    buttonPosition.dy,
                  ),
                  color: Theme.of(context).colorScheme.surface,
                  items: <PopupMenuEntry<String>>[
                    PopupMenuItem<String>(
                      child: GestureDetector(
                        onTap: () {
                          Navigator.pop(context);
                          if (!transactions_list.isEmpty) {
                            generateAndSharePDF_Transactions();
                          }
                        },
                        child: Row(
                          children: [
                            Icon(
                              Icons.picture_as_pdf,
                              size: 16,
                              color: Color(0xFF26ADA3),
                            ),
                            SizedBox(width: 5),
                            Text(
                              'Share as PDF',
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.normal,
                                color: Color(0xFF26ADA3),
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

                          if (!transactions_list.isEmpty) {
                            generateAndShareCSV_Transactions();
                          }
                        },
                        child: Row(
                          children: [
                            Icon(
                              Icons.add_chart_outlined,
                              size: 16,
                              color: Color(0xFF26ADA3),
                            ),
                            SizedBox(width: 5),

                            Text(
                              'Share as CSV',
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.normal,
                                color: Color(0xFF26ADA3),
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

      body: WillPopScope(
        onWillPop: () async {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => Dashboard()),
          );
          return true;
        },
        child: Stack(
          children: [
            CustomScrollView(
              controller: _scrollFabController,
              slivers: [
                //top header layout
                SliverToBoxAdapter(
                  child: Container(
                    margin: EdgeInsets.only(
                      left: 12,
                      right: 12,
                      top: 8,
                      bottom: 0,
                    ),
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
                    child: IntrinsicHeight(
                      child: Align(
                        alignment: Alignment.center,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 16, bottom: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // Date Range Dropdown
                              Container(
                                margin: const EdgeInsets.only(
                                  left: 16,
                                  right: 16,
                                  top: 4,
                                  bottom: 8,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).cardColor,
                                  borderRadius: BorderRadius.circular(18),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black12,
                                      blurRadius: 6,
                                      offset: Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<dynamic>(
                                    value: _selecteddate,
                                    isExpanded: true,
                                    style: GoogleFonts.poppins(
                                      fontSize: 16,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface,
                                    ),
                                    dropdownColor: Theme.of(
                                      context,
                                    ).colorScheme.surface,
                                    icon: const Icon(
                                      Icons.arrow_drop_down,
                                      color: Colors.teal,
                                    ),
                                    items: date_range.map((item) {
                                      return DropdownMenuItem<dynamic>(
                                        value: item,
                                        child: Text(item),
                                      );
                                    }).toList(),
                                    onChanged: (value) {
                                      setState(() {
                                        _handleDate(value);
                                      });
                                    },
                                  ),
                                ),
                              ),

                              // Transaction Dropdown
                              Container(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),

                                decoration: BoxDecoration(
                                  color: Theme.of(context).cardColor,
                                  borderRadius: BorderRadius.circular(18),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black12,
                                      blurRadius: 6,
                                      offset: Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: _selectedtransaction,
                                    isExpanded: true,
                                    style: GoogleFonts.poppins(
                                      fontSize: 16,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface,
                                    ),
                                    dropdownColor: Theme.of(
                                      context,
                                    ).colorScheme.surface,
                                    icon: const Icon(
                                      Icons.arrow_drop_down,
                                      color: Colors.teal,
                                    ),
                                    items: spinner_list.map((String value) {
                                      return DropdownMenuItem<String>(
                                        value: value,
                                        child: Text(
                                          value,

                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      );
                                    }).toList(),
                                    onChanged: (String? newValue) {
                                      setState(() {
                                        _selectedtransaction = newValue;
                                      });
                                      fetchtransactionsData();
                                    },
                                  ),
                                ),
                              ),

                              const SizedBox(height: 18),

                              /// 📆 Modern Date Range Selector
                              InkWell(
                                onTap: () => _selectDateRange(context),
                                borderRadius: BorderRadius.circular(50),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
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
                                                  ? 0.72
                                                  : 0.55,
                                            ),
                                        Theme.of(
                                          context,
                                        ).colorScheme.surface.withOpacity(
                                          Theme.of(context).brightness ==
                                                  Brightness.dark
                                              ? 0.92
                                              : 0.86,
                                        ),
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    border: Border.all(
                                      color: app_color,
                                      width: 1,
                                    ),
                                    borderRadius: BorderRadius.circular(50),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.calendar_month_rounded,
                                        size: 18,
                                        color: Colors.teal,
                                      ),
                                      const SizedBox(width: 10),
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
                    ),
                  ),
                ),

                SliverToBoxAdapter(
                  child: Column(
                    children: [
                      Container(
                        color: Colors.transparent,
                        child: Column(
                          children: [
                            Padding(
                              padding: EdgeInsets.only(
                                left: 12,
                                right: 12,
                                top: 5,
                              ),
                              child: Material(
                                elevation: 2,
                                borderRadius: BorderRadius.circular(20),
                                shadowColor: Colors.black12,

                                child: TextField(
                                  controller: searchController,
                                  onChanged: (value) {
                                    value = value.toLowerCase();

                                    if (value.isEmpty || value == '') {
                                      setState(() {
                                        filteredItems_transactions =
                                            transactions_list;
                                        transactions_count =
                                            filteredItems_transactions.length
                                                .toString();
                                      });
                                    } else {
                                      setState(() {
                                        filteredItems_transactions =
                                            transactions_list.where((item) {
                                              // Filter items based on the search query and the ledgerName property
                                              final query = value
                                                  .toLowerCase();
                                              return item.vchno
                                                  .toLowerCase()
                                                  .contains(query);
                                            }).toList();
                                        transactions_count =
                                            filteredItems_transactions.length
                                                .toString();
                                      });
                                    }
                                  },
                                  style: GoogleFonts.poppins(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
                                    fontSize: 13,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: "Search by voucher no...",
                                    hintStyle: GoogleFonts.poppins(
                                      fontSize: 13,
                                    ),
                                    prefixIcon: Icon(
                                      Icons.search,
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
                                        ).colorScheme.surfaceContainerHighest,
                                    contentPadding:
                                    const EdgeInsets.symmetric(
                                      vertical: 14,
                                      horizontal: 16,
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(20),
                                      borderSide: BorderSide(
                                        color: Theme.of(context).dividerColor,
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(20),
                                      borderSide: const BorderSide(
                                        color: app_color,
                                        width: 1.5,
                                      ),
                                    ),
                                    border: InputBorder.none,
                                  ),
                                ),
                              ),
                            ),

                            if (transactions_count != "0")
                              Padding(
                                padding: const EdgeInsets.only(
                                  left: 16,
                                  right: 16,
                                  top: 10,
                                  bottom: 10,
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(20),
                                  child: BackdropFilter(
                                    filter: ImageFilter.blur(
                                      sigmaX: 6,
                                      sigmaY: 6,
                                    ),
                                    child: Container(
                                      width: double.infinity,
                                      decoration: BoxDecoration(
                                        color: Theme.of(
                                          context,
                                        ).cardColor.withOpacity(0.65),
                                        borderRadius: BorderRadius.circular(
                                          30,
                                        ),
                                        border: Border.all(
                                          color: app_color,
                                          width: 1.4,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(
                                              0.04,
                                            ),
                                            blurRadius: 10,
                                            offset: Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      padding: EdgeInsets.only(
                                        left: 10,
                                        right: 10,
                                        top: 5,
                                        bottom: 5,
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                        MainAxisAlignment.center,
                                        children: [
                                          // 🔵 Icon
                                          Container(
                                            padding: const EdgeInsets.all(6),
                                            decoration: BoxDecoration(
                                              color: app_color.withOpacity(
                                                0.1,
                                              ),
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(
                                              Icons.receipt_long,
                                              size: 16,
                                              color: app_color,
                                            ),
                                          ),
                                          const SizedBox(width: 12),

                                          // 🔢 Count Text
                                          RichText(
                                            text: TextSpan(
                                              children: [
                                                TextSpan(
                                                  text:
                                                  "${transactions_count} ", // <-- Replace dynamically with $party_count
                                                  style: GoogleFonts.poppins(
                                                    fontSize: 14,
                                                    fontWeight:
                                                    FontWeight.bold,
                                                    color: app_color,
                                                  ),
                                                ),
                                                TextSpan(
                                                  text: "Transactions",
                                                  style: GoogleFonts.poppins(
                                                    fontSize: 15,
                                                    fontWeight:
                                                    FontWeight.w500,
                                                    color: app_color,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),

                            /*Visibility(
                                  visible: isVisibleNoDataFound,
                                  child: Padding(
                                    padding: const EdgeInsets.only(top: 60),
                                    child: Column(
                                      children: [
                                        Icon(Icons.search_off_rounded, color: Theme.of(context).colorScheme.onSurfaceVariant, size: 40),
                                        const SizedBox(height: 8),
                                        Text(
                                          'No Records Found',
                                          style: GoogleFonts.poppins(
                                            fontSize: 16,
                                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),*/
                            isVisibleNoDataFound
                                ? _buildEmptyState(context)
                                : ListView.builder(
                              shrinkWrap: true,
                              physics: NeverScrollableScrollPhysics(),
                              controller:
                              _scrollController_transactions,
                              itemCount:
                              filteredItems_transactions.length,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              itemBuilder: (context, index) {
                                final card =
                                filteredItems_transactions[index];
                                final double amt =
                                    double.tryParse(
                                      card.amount.toString(),
                                    ) ??
                                        0.0;
                                final bool isDebit = amt < 0;

                                // 🔹 Currency + Decimal + CR/DR
                                final formattedAmount =
                                    '$currencysymbol ${NumberFormat("#,##0.${"0" * decimal!}").format(amt.abs())} ${isDebit ? "DR" : "CR"}';
                                return GestureDetector(
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            TransactionsClicked(
                                              vchtype: card.vchname,
                                              startdate:
                                              startDateString,
                                              enddate: endDateString,
                                              vchno: card.vchno,
                                              vchdate: card.vchdate,
                                              ispostdated:
                                              card.ispostdated,
                                              isoptional:
                                              card.isoptional,
                                              refno: card.refno,
                                              refdate: card.refdate,
                                              masterid: card.masterid,
                                            ),
                                      ),
                                    );
                                  },
                                  child: Container(
                                    margin: const EdgeInsets.symmetric(
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      borderRadius:
                                      BorderRadius.circular(20),
                                      gradient: LinearGradient(
                                        colors: [
                                          Theme.of(context)
                                              .colorScheme
                                              .surface
                                              .withOpacity(
                                            Theme.of(
                                              context,
                                            ).brightness ==
                                                Brightness.dark
                                                ? 0.96
                                                : 1,
                                          ),
                                          Theme.of(context)
                                              .colorScheme
                                              .surfaceContainerHighest
                                              .withOpacity(
                                            Theme.of(
                                              context,
                                            ).brightness ==
                                                Brightness.dark
                                                ? 0.72
                                                : 0.38,
                                          ),
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black12
                                              .withOpacity(0.08),
                                          blurRadius: 12,
                                          offset: const Offset(0, 6),
                                        ),
                                      ],
                                      border: Border.all(
                                        color: Theme.of(context)
                                            .dividerColor
                                            .withOpacity(
                                          Theme.of(
                                            context,
                                          ).brightness ==
                                              Brightness.dark
                                              ? 0.7
                                              : 0.55,
                                        ),
                                        width: 1,
                                      ),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                        crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                        children: [
                                          /// 🔹 Header (Ledger + Chevron)
                                          Row(
                                            children: [
                                              Container(
                                                width: 36,
                                                height: 36,
                                                decoration: BoxDecoration(
                                                  gradient: LinearGradient(
                                                    colors: [
                                                      app_color
                                                          .withOpacity(
                                                        0.6,
                                                      ),
                                                      app_color
                                                          .withOpacity(
                                                        0.9,
                                                      ),
                                                    ],
                                                  ),
                                                  borderRadius:
                                                  BorderRadius.circular(
                                                    12,
                                                  ),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color:
                                                      (isDebit
                                                          ? Colors.red
                                                          : Colors.green)
                                                          .withOpacity(
                                                        0.25,
                                                      ),
                                                      blurRadius: 6,
                                                      offset:
                                                      const Offset(
                                                        0,
                                                        3,
                                                      ),
                                                    ),
                                                  ],
                                                ),

                                                child: const Icon(
                                                  Icons
                                                      .account_balance_wallet_rounded,
                                                  color: Colors.white,
                                                  size: 20,
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Text(
                                                  card.vchname != "null"
                                                      ? card.vchname
                                                      : "Unknown Ledger",
                                                  style: GoogleFonts.poppins(
                                                    fontSize: 16,
                                                    fontWeight:
                                                    FontWeight.w600,
                                                    color:
                                                    Theme.of(
                                                      context,
                                                    )
                                                        .colorScheme
                                                        .onSurface,
                                                  ),
                                                  overflow: TextOverflow
                                                      .visible,
                                                ),
                                              ),

                                              Container(
                                                padding:
                                                const EdgeInsets.all(
                                                  6,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .surfaceContainerHighest,
                                                  shape:
                                                  BoxShape.circle,
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: Colors
                                                          .black12,
                                                      blurRadius: 4,
                                                      offset:
                                                      const Offset(
                                                        0,
                                                        2,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                child: Icon(
                                                  Icons
                                                      .chevron_right_rounded,
                                                  size: 20,
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                                ),
                                              ),
                                            ],
                                          ),

                                          const SizedBox(height: 14),
                                          Divider(
                                            height: 1,
                                            color: Theme.of(
                                              context,
                                            ).dividerColor,
                                          ),
                                          const SizedBox(height: 14),

                                          _modernDetailRow(
                                            context,
                                            "Voucher No",
                                            card.vchno,
                                            Icons.receipt_long_rounded,
                                          ),

                                          _modernDetailRow(
                                            context,
                                            "Date",
                                            convertDateFormat(
                                              card.vchdate,
                                            ),
                                            Icons
                                                .calendar_today_outlined,
                                          ),

                                          _modernDetailRow(
                                            context,
                                            "Amount",
                                            formattedAmount,
                                            Icons.payments_outlined,
                                            isDebit: isDebit,
                                            isAmountRow: true,
                                          ),

                                          /// 🔹 Tags
                                          if (card.ispostdated == "1" ||
                                              card.isoptional ==
                                                  "1") ...[
                                            const SizedBox(height: 12),
                                            Wrap(
                                              spacing: 8,
                                              runSpacing: 6,
                                              children: [
                                                if (card.ispostdated ==
                                                    "1")
                                                  _buildTagChip(
                                                    label: "Post Dated",
                                                    icon:
                                                    Icons.schedule,
                                                    bgColor: app_color.withOpacity(
                                                      Theme.of(
                                                        context,
                                                      ).brightness ==
                                                          Brightness
                                                              .dark
                                                          ? 0.18
                                                          : 0.10,
                                                    ),
                                                    borderColor: app_color.withOpacity(
                                                      Theme.of(
                                                        context,
                                                      ).brightness ==
                                                          Brightness
                                                              .dark
                                                          ? 0.42
                                                          : 0.30,
                                                    ),
                                                    textColor:
                                                    Theme.of(
                                                      context,
                                                    ).brightness ==
                                                        Brightness
                                                            .dark
                                                        ? Colors
                                                        .tealAccent
                                                        .shade100
                                                        : Colors
                                                        .teal
                                                        .shade700,
                                                  ),
                                                if (card.isoptional ==
                                                    "1")
                                                  _buildTagChip(
                                                    label: "Optional",
                                                    icon: Icons
                                                        .info_outline,
                                                    bgColor: Colors.orange.withOpacity(
                                                      Theme.of(
                                                        context,
                                                      ).brightness ==
                                                          Brightness
                                                              .dark
                                                          ? 0.18
                                                          : 0.10,
                                                    ),
                                                    borderColor: Colors
                                                        .orange
                                                        .withOpacity(
                                                      Theme.of(
                                                        context,
                                                      ).brightness ==
                                                          Brightness
                                                              .dark
                                                          ? 0.42
                                                          : 0.30,
                                                    ),
                                                    textColor:
                                                    Theme.of(
                                                      context,
                                                    ).brightness ==
                                                        Brightness
                                                            .dark
                                                        ? Colors
                                                        .orange
                                                        .shade200
                                                        : Colors
                                                        .orange
                                                        .shade700,
                                                  ),
                                              ],
                                            ),
                                          ],
                                        ],
                                      ),
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
                ),
              ],
            ),

            Visibility(
              visible: isSortVisible,

              child: Padding(
                padding: const EdgeInsets.only(bottom: 50),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: GestureDetector(
                    onTap: () => _showSelectionWindow(context),
                    child: Container(
                      width: 100,
                      height: 40,
                      decoration: BoxDecoration(
                        color: app_color, // soft teal background
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.teal.withOpacity(0.3),
                            blurRadius: 10,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.sort, size: 18, color: Colors.white),
                          const SizedBox(width: 6),
                          Text(
                            'Sort',
                            style: GoogleFonts.poppins(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Visibility(
              visible: _isLoading,
              child: Center(child: AppLogoLoader()),
            ),
            ScrollFab(controller: _scrollFabController),
          ],
        ),
      ),
    );
  }
}

Widget _buildEmptyState(BuildContext context) {
  return SizedBox(
    height: MediaQuery.of(context).size.height * 0.5,
    child: Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.search_off_rounded,
          size: 80,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        SizedBox(height: 12),
        Text(
          "No Transactions found",
          style: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  ),
  );
}

Widget _buildTagChip({
  required String label,
  required IconData icon,
  required Color bgColor,
  required Color borderColor,
  required Color textColor,
}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: bgColor,
      border: Border.all(color: borderColor),
      borderRadius: BorderRadius.circular(30),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: textColor),
        const SizedBox(width: 6),
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
            color: textColor,
          ),
        ),
      ],
    ),
  );
}

/// 🔹 Reusable Detail Row with contextual gradients
Widget _modernDetailRow(
  BuildContext context,
  String title,
  String value,
  IconData icon, {
  bool? isDebit,
  bool? isAmountRow = false,
}) {
  LinearGradient _getGradient() {
    if (title.contains("Voucher")) {
      return LinearGradient(
        colors: [Colors.indigo.shade400, Colors.indigo.shade700],
      );
    } else if (title.contains("Date")) {
      return LinearGradient(
        colors: [Colors.blueGrey.shade400, Colors.blueGrey.shade700],
      );
    } else if (isAmountRow == true) {
      if (isDebit == true) {
        return LinearGradient(
          colors: [Colors.red.shade400, Colors.red.shade700],
        );
      } else {
        return LinearGradient(
          colors: [Colors.green.shade400, Colors.green.shade700],
        );
      }
    }
    return LinearGradient(colors: [Colors.grey.shade400, Colors.grey.shade600]);
  }

  return Container(
    margin: const EdgeInsets.symmetric(vertical: 2),
    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(
        Theme.of(context).brightness == Brightness.dark ? 0.34 : 0.42,
      ),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            gradient: _getGradient(),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: Colors.white, size: 18),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: Text(
              value,
              textAlign: TextAlign.right, // ✅ text inside also right aligned

              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              overflow: TextOverflow.visible,
              softWrap: true,
            ),
          ),
        ),
      ],
    ),
  );
}
