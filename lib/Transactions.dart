import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';
import 'package:fl_chart/fl_chart.dart';
import 'package:FincoreGo/Dashboard.dart';
import 'package:FincoreGo/utils/currency_helper.dart';
/*import 'package:FincoreGo/currencyFormat.dart';*/
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'currencyFormat.dart';
import 'package:FincoreGo/widgets/app_bottom_nav.dart';
import 'package:FincoreGo/widgets/app_navigation.dart';
import 'widgets/scroll_fab.dart';
import 'widgets/entry_widgets.dart';

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
  String _currencyCode = 'AED';

  String? hostname = "",
      company = "",
      serial_no = "",
      company_lowercase = "",
      username = "";

  bool _isLoading = false;

  // Toggles between the transaction list and the voucher-type trend
  // chart - having both stacked on screen at once was too cluttered, so
  // only one shows at a time now, tab-style.
  bool _isTrendTabSelected = false;

  // Quick filter chips - postdated/optional vouchers are exactly the
  // transactions users specifically need to track/follow up on, so a
  // one-tap filter is more useful day-to-day than another chart.
  String _quickFilter = 'All';

  void _applyTransactionFilters() {
    Iterable<transactions> items = transactions_list;

    if (_quickFilter == 'Postdated') {
      items = items.where((t) => t.ispostdated == '1');
    } else if (_quickFilter == 'Optional') {
      items = items.where((t) => t.isoptional == '1');
    }

    final query = searchController.text.trim().toLowerCase();
    if (query.isNotEmpty) {
      items = items.where((t) => t.vchno.toLowerCase().contains(query));
    }

    setState(() {
      filteredItems_transactions = items.toList();
      transactions_count = filteredItems_transactions.length.toString();
    });
  }

  Widget _buildQuickFilterChips() {
    final counts = {
      'All': transactions_list.length,
      'Postdated': transactions_list.where((t) => t.ispostdated == '1').length,
      'Optional': transactions_list.where((t) => t.isoptional == '1').length,
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final label in ['All', 'Postdated', 'Optional'])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _buildQuickFilterChip(label, counts[label] ?? 0),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickFilterChip(String label, int count) {
    final isSelected = _quickFilter == label;
    return GestureDetector(
      onTap: () {
        _quickFilter = label;
        searchController.clear();
        _applyTransactionFilters();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          gradient: isSelected
              ? LinearGradient(
                  colors: [Colors.teal.shade400, Colors.teal.shade600],
                )
              : null,
          color: isSelected
              ? null
              : (Theme.of(context).brightness == Brightness.dark
                    ? Colors.white.withOpacity(0.06)
                    : Colors.grey.shade100),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          '$label ($count)',
          style: GoogleFonts.poppins(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: isSelected
                ? Colors.white
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

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
      DateTime earliestDate =
          DateTime.tryParse(startfrom ?? '') ?? DateTime(2000);

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

  // Stacked bar - one bar per month, segments colored by voucher type.
  // Aggregates the already-fetched transactions_list (no new API call).
  // A multi-line chart with 8 crossing lines was too cluttered to read;
  // stacking shows both the total monthly volume AND the type breakdown
  // within it, in one view, with no overlapping lines.
  static const List<Color> _voucherTrendPalette = [
    Color(0xFF00BFA5),
    Color(0xFFFF6D00),
    Color(0xFF2979FF),
    Color(0xFF8E24AA),
    Color(0xFFFFC107),
    Color(0xFF43A047),
    Color(0xFFE53935),
    Color(0xFF3949AB),
  ];

  Map<String, Map<String, double>> _buildVoucherStackedTotals() {
    final totalsByTypeAndMonth = <String, Map<String, double>>{};

    for (final t in transactions_list) {
      final date = DateTime.tryParse(t.vchdate);
      if (date == null) continue;
      final monthLabel = DateFormat('MMMM yyyy').format(date);
      final byMonth = totalsByTypeAndMonth.putIfAbsent(t.vchname, () => {});
      byMonth[monthLabel] = (byMonth[monthLabel] ?? 0) + t.amount.abs();
    }

    return totalsByTypeAndMonth;
  }

  // Transaction COUNT per month (not amount) - summing mixed voucher-type
  // amounts together (Sales + Purchase + Receipt + Payment + Journal...)
  // doesn't produce a meaningful number since they're different kinds of
  // economic events. Count is meaningful regardless of the type mix.
  Map<String, int> _buildVoucherMonthCounts() {
    final countByMonth = <String, int>{};
    for (final t in transactions_list) {
      final date = DateTime.tryParse(t.vchdate);
      if (date == null) continue;
      final monthLabel = DateFormat('MMMM yyyy').format(date);
      countByMonth[monthLabel] = (countByMonth[monthLabel] ?? 0) + 1;
    }
    return countByMonth;
  }

  // Compact dropdown for the header - a small icon-labelled pill instead
  // of a full-width bordered box, so the two dropdowns can sit side by
  // side in one row instead of stacking full-width one under the other.
  Widget _buildCompactDropdown<T>({
    required T? value,
    required IconData icon,
    required List<T> items,
    required String Function(T) itemLabel,
    required void Function(T?) onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? Colors.white.withOpacity(0.06)
            : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, size: 15, color: Colors.teal),
          const SizedBox(width: 6),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<T>(
                value: value,
                isExpanded: true,
                isDense: true,
                style: GoogleFonts.poppins(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                dropdownColor: Theme.of(context).colorScheme.surface,
                icon: const Icon(
                  Icons.arrow_drop_down,
                  color: Colors.teal,
                  size: 20,
                ),
                items: items
                    .map(
                      (item) => DropdownMenuItem<T>(
                        value: item,
                        child: Text(
                          itemLabel(item),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionsTabRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: _buildTransTabButton(
              label: 'Overview',
              isSelected: _isTrendTabSelected,
              onTap: () => setState(() => _isTrendTabSelected = true),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _buildTransTabButton(
              label: 'Transactions',
              isSelected: !_isTrendTabSelected,
              onTap: () => setState(() => _isTrendTabSelected = false),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransTabButton({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          gradient: isSelected
              ? LinearGradient(
                  colors: [Colors.teal.shade400, Colors.teal.shade600],
                )
              : LinearGradient(
                  colors: Theme.of(context).brightness == Brightness.dark
                      ? [
                          Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest.withOpacity(0.7),
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
                offset: const Offset(0, 4),
              ),
          ],
        ),
        child: Center(
          child: Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: isSelected
                  ? Colors.white
                  : Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
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

        showAppMessage(context, error);
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
      // _startDate/_endDate are already loaded from the same 'startdate'/
      // 'enddate' prefs Dashboard saved (see _initSharedPreferences) - use
      // that range directly instead of forcing the native date-range
      // picker open every time this runs. The picker should only appear
      // when the user explicitly taps the date-range pill (_selectDateRange),
      // not automatically on load - that was popping up unprompted and,
      // if dismissed without picking, crashed on a force-unwrapped null.
      setState(() {
        _isTextEnabled = true;
        _isDashVisible = true;
        _isEnddateVisible = true;
        _IsSizeboxVisible = true;

        DateTime start = _startDate;
        DateTime end = _endDate;

        String startMonth = DateFormat('MMM').format(start);
        String sdf = DateFormat('MM').format(start);
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
      });

      fetchMainData();
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
    _quickFilter = 'All';

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

        showAppMessage(context, error);

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
      company = prefs.getString('company_name') ?? '';
      company_lowercase = company!.replaceAll(' ', '').toLowerCase();
      serial_no = prefs.getString('serial_no');
      username = prefs.getString('username');
      token = prefs.getString('token') ?? '';
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
      _currencyCode = currencyCode ?? 'AED';

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
        // Dashboard can leave 'datetype'='Custom Date' saved without a
        // matching startdate/enddate (e.g. the range picker was
        // cancelled) - DateTime.parse(...)! on a null/empty string threw
        // here, uncaught, aborting the rest of this setState (and every
        // fetch that follows it), which is why the whole screen loaded
        // nothing. Fall back to a sensible default range instead.
        _startDate =
            DateTime.tryParse(prefs.getString('startdate') ?? '') ??
            DateTime.now().subtract(const Duration(days: 30));
        _endDate =
            DateTime.tryParse(prefs.getString('enddate') ?? '') ??
            DateTime.now();

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
                //top header layout - compact: both dropdowns share one row
                //instead of stacking, and the date-range pill sits directly
                //below with tight spacing, cutting overall header height
                //roughly in half versus the previous 3-stacked-rows layout.
                SliverToBoxAdapter(
                  child: Container(
                    margin: const EdgeInsets.only(
                      left: 12,
                      right: 12,
                      top: 8,
                      bottom: 0,
                    ),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black12.withOpacity(0.08),
                          blurRadius: 10,
                          spreadRadius: 2,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _buildCompactDropdown<dynamic>(
                                value: _selecteddate,
                                icon: Icons.event_repeat_rounded,
                                items: date_range,
                                itemLabel: (item) => item.toString(),
                                onChanged: (value) {
                                  setState(() {
                                    _handleDate(value);
                                  });
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildCompactDropdown<String>(
                                value: _selectedtransaction,
                                icon: Icons.receipt_long_rounded,
                                items: spinner_list,
                                itemLabel: (item) => item,
                                onChanged: (newValue) {
                                  setState(() {
                                    _selectedtransaction = newValue;
                                  });
                                  fetchtransactionsData();
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        /// 📆 Compact date range selector
                        InkWell(
                          onTap: () => _selectDateRange(context),
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? Colors.white.withOpacity(0.06)
                                  : Colors.teal.withOpacity(0.06),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: app_color.withOpacity(0.4),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.calendar_month_rounded,
                                  size: 15,
                                  color: Colors.teal,
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    "$startdate_text → $enddate_text",
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.poppins(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12.5,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface,
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

                if (transactions_list.isNotEmpty)
                  SliverToBoxAdapter(child: _buildTransactionsTabRow()),

                if (_isTrendTabSelected && transactions_list.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: VoucherOverviewChart(
                        totalsByTypeAndMonth: _buildVoucherStackedTotals(),
                        countByMonth: _buildVoucherMonthCounts(),
                        palette: _voucherTrendPalette,
                        currencysymbol: currencysymbol,
                        currencyCode: _currencyCode,
                      ),
                    ),
                  ),

                if (!_isTrendTabSelected && transactions_list.isNotEmpty)
                  SliverToBoxAdapter(child: const SizedBox(height: 8)),

                if (!_isTrendTabSelected && transactions_list.isNotEmpty)
                  SliverToBoxAdapter(child: _buildQuickFilterChips()),

                if (!_isTrendTabSelected)
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
                              child: SizedBox(
                                height: 46,
                                child: TextField(
                                  controller: searchController,
                                  onChanged: (value) =>
                                      _applyTransactionFilters(),
                                  style: GoogleFonts.poppins(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
                                    fontSize: 13.5,
                                  ),
                                  decoration: InputDecoration(
                                    isDense: true,
                                    hintText: "Search by voucher no...",
                                    hintStyle: GoogleFonts.poppins(
                                      fontSize: 13,
                                    ),
                                    prefixIcon: Icon(
                                      Icons.search,
                                      size: 18,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                                    filled: true,
                                    fillColor:
                                        Theme.of(context).brightness ==
                                                Brightness.dark
                                            ? Colors.white.withOpacity(0.06)
                                            : Colors.grey.shade100,
                                    contentPadding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                      horizontal: 12,
                                    ),
                                    suffixIcon: transactions_count == "0"
                                        ? null
                                        : Padding(
                                            padding: const EdgeInsets.only(
                                              right: 12,
                                            ),
                                            child: Center(
                                              widthFactor: 1,
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                      vertical: 4,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: app_color.withOpacity(
                                                    0.10,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(20),
                                                ),
                                                child: Text(
                                                  transactions_count,
                                                  style: GoogleFonts.poppins(
                                                    fontSize: 12.5,
                                                    fontWeight: FontWeight.w700,
                                                    color: app_color,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(24),
                                      borderSide: BorderSide.none,
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(24),
                                      borderSide: BorderSide(
                                        color: app_color.withOpacity(0.6),
                                        width: 1.4,
                                      ),
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(24),
                                      borderSide: BorderSide.none,
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
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // 📋 Transaction list - a real sliver (SliverList) so the
                // CustomScrollView only builds cards near the viewport; the
                // previous shrinkWrap ListView.builder forced eager layout
                // of every transaction up front, which is what caused the
                // same scroll-hang bug already fixed on the Party list.
                if (!_isTrendTabSelected && isVisibleNoDataFound)
                  SliverToBoxAdapter(child: _buildEmptyState(context))
                else if (!_isTrendTabSelected)
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
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
                                          '${NumberFormat("#,##0.${"0" * decimal!}").format(amt.abs())} ${isDebit ? "DR" : "CR"}';
                                      return GestureDetector(
                                        onTap: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) =>
                                                  TransactionsClicked(
                                                    vchtype: card.vchname,
                                                    startdate: startDateString,
                                                    enddate: endDateString,
                                                    vchno: card.vchno,
                                                    vchdate: card.vchdate,
                                                    ispostdated:
                                                        card.ispostdated,
                                                    isoptional: card.isoptional,
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
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
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
                                                        color: app_color
                                                            .withOpacity(0.12),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              12,
                                                            ),
                                                      ),
                                                      child: Icon(
                                                        Icons
                                                            .account_balance_wallet_rounded,
                                                        color: app_color,
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
                                                              Theme.of(context)
                                                                  .colorScheme
                                                                  .onSurface,
                                                        ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 6),
                                                    Icon(
                                                      Icons
                                                          .chevron_right_rounded,
                                                      size: 22,
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .onSurfaceVariant
                                                          .withOpacity(0.6),
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
                                                  Icons.calendar_today_outlined,
                                                ),

                                                _modernDetailRow(
                                                  context,
                                                  "Amount",
                                                  '',
                                                  Icons.payments_outlined,
                                                  isDebit: isDebit,
                                                  isAmountRow: true,
                                                  valueWidget: currencyAmountText(
                                                    currencyCode:
                                                        _currencyCode,
                                                    symbol: currencysymbol,
                                                    amountText:
                                                        formattedAmount,
                                                    textAlign:
                                                        TextAlign.right,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: GoogleFonts.poppins(
                                                      fontSize: 14,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .onSurface,
                                                    ),
                                                  ),
                                                ),

                                                /// 🔹 Tags
                                                if (card.ispostdated == "1" ||
                                                    card.isoptional == "1") ...[
                                                  const SizedBox(height: 12),
                                                  Wrap(
                                                    spacing: 8,
                                                    runSpacing: 6,
                                                    children: [
                                                      if (card.ispostdated ==
                                                          "1")
                                                        _buildTagChip(
                                                          label: "Post Dated",
                                                          icon: Icons.schedule,
                                                          bgColor: app_color.withOpacity(
                                                            Theme.of(
                                                                      context,
                                                                    ).brightness ==
                                                                    Brightness
                                                                        .dark
                                                                ? 0.18
                                                                : 0.10,
                                                          ),
                                                          borderColor: app_color
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
                                                          bgColor: Colors.orange
                                                              .withOpacity(
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
                      }, childCount: filteredItems_transactions.length),
                    ),
                  ),
              ],
            ),

            Visibility(
              // Sorting only applies to the transaction list, not the
              // Overview chart tab - it was floating over the chart there
              // before, which didn't make sense.
              visible: isSortVisible && !_isTrendTabSelected,

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
            if (_isLoading)
              Positioned.fill(
                child: Container(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  child: _buildSkeletonList(),
                ),
              ),
            ScrollFab(controller: _scrollFabController),
          ],
        ),
      ),
    );
  }

  // Skeleton stand-in for the header/filter card + transaction list while
  // the initial fetch is in flight - replaces the old dimmed
  // spinner-over-stale-content overlay so the loading state reads as
  // "content incoming" instead of a blank page. Generic (icon + 2 text
  // lines + amount) rather than mirroring the exact vchtype-specific card,
  // and used for both the Overview and Transactions tabs for simplicity.
  Widget _buildSkeletonList() {
    return ShimmerLoading(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
        children: [
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black12.withOpacity(0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const ShimmerBox(height: 38, borderRadius: 12),
                const SizedBox(height: 8),
                const ShimmerBox(height: 38, borderRadius: 12),
                const SizedBox(height: 8),
                const ShimmerBox(height: 38, borderRadius: 12),
              ],
            ),
          ),
          for (int i = 0; i < 8; i++)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12.withOpacity(0.08),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
                border: Border.all(
                  color: Theme.of(context).dividerColor.withOpacity(0.55),
                ),
              ),
              child: Row(
                children: [
                  const ShimmerBox(width: 36, height: 36, borderRadius: 12),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const ShimmerBox(height: 14, width: 150),
                        const SizedBox(height: 6),
                        const ShimmerBox(height: 11, width: 100),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const ShimmerBox(height: 15, width: 70),
                ],
              ),
            ),
        ],
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
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: app_color.withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.receipt_long_rounded,
              size: 40,
              color: app_color.withOpacity(0.6),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            "No transactions found",
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "Try a different date range, voucher type, or filter",
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 13,
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
  Widget? valueWidget,
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
        Text(
          title,
          style: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child:
                valueWidget ??
                Text(
                  value,
                  textAlign:
                      TextAlign.right, // ✅ text inside also right aligned
                  maxLines: 1,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                  softWrap: true,
                ),
          ),
        ),
      ],
    ),
  );
}

// Donut (proportion by voucher type, toggle % / amount) + transaction
// COUNT per month (not amount - summing mixed voucher types like
// Sales + Purchase + Receipt + Payment + Journal together doesn't
// produce a meaningful number since they're different kinds of economic
// events; count stays meaningful regardless of the type mix).
class VoucherOverviewChart extends StatefulWidget {
  final Map<String, Map<String, double>> totalsByTypeAndMonth;
  final Map<String, int> countByMonth;
  final List<Color> palette;
  final String currencysymbol;
  final String currencyCode;

  const VoucherOverviewChart({
    super.key,
    required this.totalsByTypeAndMonth,
    required this.countByMonth,
    required this.palette,
    required this.currencysymbol,
    required this.currencyCode,
  });

  @override
  State<VoucherOverviewChart> createState() => _VoucherOverviewChartState();
}

class _VoucherOverviewChartState extends State<VoucherOverviewChart> {
  bool _showAmount = false;

  double _niceMax(double rawMax) {
    if (rawMax <= 0 || !rawMax.isFinite) return 1;
    final padded = rawMax * 1.1;
    final exponent = (math.log(padded) / math.ln10).floor();
    final magnitude = math.pow(10, exponent).toDouble();
    final normalized = padded / magnitude;
    const steps = [1, 1.5, 2, 2.5, 3, 4, 5, 6, 8, 10];
    final nice = steps.firstWhere(
      (step) => normalized <= step,
      orElse: () => 10,
    );
    return nice * magnitude;
  }

  String _formatCompact(double value) {
    if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}K';
    return value.toStringAsFixed(0);
  }

  Widget _legendValue(String type, double totalByType, double grandTotal) {
    if (!_showAmount) {
      final pct = grandTotal > 0 ? (totalByType / grandTotal * 100) : 0;
      // A genuinely non-zero amount can still round to "0%" once its
      // share is under 0.5% - showing "0%" then reads as if there's
      // nothing there at all, so show "<1%" instead in that case.
      final pctLabel = (pct.round() == 0 && totalByType > 0)
          ? '<1%'
          : '${pct.toStringAsFixed(0)}%';
      return Text(
        pctLabel,
        style: GoogleFonts.poppins(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      );
    }
    return currencyAmountText(
      currencyCode: widget.currencyCode,
      symbol: widget.currencysymbol,
      amountText: CurrencyFormatter.formatCurrencyParts(totalByType).number,
      style: GoogleFonts.poppins(
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        color: Theme.of(context).colorScheme.onSurface,
      ),
    );
  }

  Widget _toggleTab(String label, bool isSelected, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? Colors.teal.shade500 : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Center(
            child: Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isSelected
                    ? Colors.white
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final types = widget.totalsByTypeAndMonth.keys.toList();
    if (types.isEmpty) return const SizedBox.shrink();

    // Totals by type, for the donut - sorted biggest first so the
    // legend/slice order reads as a ranking.
    final totalByType = <String, double>{
      for (final type in types)
        type: widget.totalsByTypeAndMonth[type]!.values.fold<double>(
          0,
          (a, b) => a + b,
        ),
    };
    final sortedTypes = types.toList()
      ..sort((a, b) => totalByType[b]!.compareTo(totalByType[a]!));
    final grandTotal = totalByType.values.fold<double>(0, (a, b) => a + b);

    // Months present, for the count bar.
    final monthKeys = <String>{
      ...widget.countByMonth.keys,
      for (final byMonth in widget.totalsByTypeAndMonth.values) ...byMonth.keys,
    };
    final formatter = DateFormat('MMMM yyyy');
    final months = monthKeys.toList()
      ..sort((a, b) {
        try {
          return formatter.parse(a).compareTo(formatter.parse(b));
        } catch (_) {
          return a.compareTo(b);
        }
      });

    final years = months
        .map((m) {
          try {
            return formatter.parse(m).year;
          } catch (_) {
            return null;
          }
        })
        .whereType<int>()
        .toSet();
    final spansMultipleYears = years.length > 1;

    final shortLabels = months.map((m) {
      try {
        final parsed = formatter.parse(m);
        return spansMultipleYears
            ? DateFormat("MMM ''yy").format(parsed)
            : DateFormat('MMM').format(parsed);
      } catch (_) {
        return m;
      }
    }).toList();

    final monthCounts = [
      for (final m in months) (widget.countByMonth[m] ?? 0).toDouble(),
    ];
    final maxY = _niceMax(
      monthCounts.isEmpty ? 0 : monthCounts.reduce(math.max),
    );
    final interval = math.max(1.0, (maxY / 4).roundToDouble());

    const maxVisibleLabels = 7;
    final labelStep = months.isEmpty
        ? 1
        : (months.length / maxVisibleLabels).ceil().clamp(1, months.length);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Theme.of(context).brightness == Brightness.dark
            ? Border.all(color: Colors.white.withOpacity(0.10), width: 1)
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black12.withOpacity(0.05),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Share by Voucher Type',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 120,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white10
                      : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    _toggleTab(
                      '%',
                      !_showAmount,
                      () => setState(() => _showAmount = false),
                    ),
                    _toggleTab(
                      'Amt',
                      _showAmount,
                      () => setState(() => _showAmount = true),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 120,
                height: 120,
                child: PieChart(
                  PieChartData(
                    sectionsSpace: 2,
                    centerSpaceRadius: 32,
                    sections: [
                      for (var i = 0; i < sortedTypes.length; i++)
                        PieChartSectionData(
                          value: totalByType[sortedTypes[i]],
                          color:
                              widget.palette[types.indexOf(sortedTypes[i]) %
                                  widget.palette.length],
                          radius: 26,
                          showTitle: false,
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final type in sortedTypes)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            Container(
                              width: 9,
                              height: 9,
                              decoration: BoxDecoration(
                                color: widget.palette[types.indexOf(type) %
                                    widget.palette.length],
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                type,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.poppins(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            _legendValue(
                              type,
                              totalByType[type]!,
                              grandTotal,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            'Transactions per Month',
            style: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 200,
            child: months.isEmpty
                ? const SizedBox.shrink()
                : BarChart(
                    BarChartData(
                      minY: 0,
                      maxY: maxY,
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: interval,
                        getDrawingHorizontalLine: (value) => FlLine(
                          color: Theme.of(context).dividerColor,
                          strokeWidth: 1,
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      titlesData: FlTitlesData(
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 36,
                            interval: interval,
                            getTitlesWidget: (value, meta) => Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Text(
                                value.toStringAsFixed(0),
                                style: GoogleFonts.poppins(
                                  fontSize: 10,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 28,
                            getTitlesWidget: (value, meta) {
                              final index = value.round();
                              if ((value - index).abs() > 0.01) {
                                return const SizedBox.shrink();
                              }
                              if (index < 0 ||
                                  index >= shortLabels.length ||
                                  index % labelStep != 0) {
                                return const SizedBox.shrink();
                              }
                              return Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  shortLabels[index],
                                  style: GoogleFonts.poppins(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                      ),
                      barTouchData: BarTouchData(
                        enabled: true,
                        touchTooltipData: BarTouchTooltipData(
                          getTooltipItem: (group, groupIndex, rod, rodIndex) {
                            return BarTooltipItem(
                              rod.toY.toStringAsFixed(0),
                              GoogleFonts.poppins(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            );
                          },
                        ),
                      ),
                      barGroups: [
                        for (var i = 0; i < months.length; i++)
                          BarChartGroupData(
                            x: i,
                            barRods: [
                              BarChartRodData(
                                toY: monthCounts[i],
                                width: months.length > 12 ? 10 : 18,
                                borderRadius: BorderRadius.circular(3),
                                color: const Color(0xFF00BFA5),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
