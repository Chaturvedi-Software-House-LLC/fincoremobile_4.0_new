import 'dart:math' as math;
import 'dart:ui';
import 'package:fl_chart/fl_chart.dart';
import 'package:FincoreGo/Dashboard.dart';
import 'package:FincoreGo/utils/currency_helper.dart';
/*import 'package:FincoreGo/currencyFormat.dart';*/
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'CompanySelectTallyOauth.dart';
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
import 'providers/transactions_notifier.dart';

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

class Transactions extends ConsumerStatefulWidget {
  @override
  ConsumerState<Transactions> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends ConsumerState<Transactions>
    with TickerProviderStateMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  final List<String> itemList = [
    'Default',
    'Newest to Oldest',
    'Oldest to Newest',
    'A->Z',
    'Z->A',
    'Amount High to Low',
    'Amount Low to High',
  ];

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

  TextEditingController searchController = TextEditingController();

  late GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey;

  final ScrollController _scrollFabController = ScrollController();

  TransactionsNotifier get _notifier =>
      ref.read(transactionsNotifierProvider.notifier);
  TransactionsState get _s => ref.read(transactionsNotifierProvider);

  String _currentSearchQuery() => searchController.text;

  Widget _buildQuickFilterChips() {
    final vm = _s;
    final counts = {
      'All': vm.transactionsList.length,
      'Postdated':
          vm.transactionsList.where((t) => t.ispostdated == '1').length,
      'Optional':
          vm.transactionsList.where((t) => t.isoptional == '1').length,
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
    final isSelected = _s.quickFilter == label;
    return GestureDetector(
      onTap: () {
        searchController.clear();
        _notifier.setQuickFilter(label, _currentSearchQuery);
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
                        _notifier.applySortOption(itemList[index]);
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
                              fontWeight:
                                  itemList[index] == _s.selectedSortOption
                                  ? FontWeight.bold
                                  : FontWeight
                                        .normal, // Apply bold style to the text if the tile is selected
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          trailing: itemList[index] == _s.selectedSortOption
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


  String formatledger_report(String ledger) {
    if (ledger == 'null') {
      ledger = '-';
    }
    return ledger;
  }

  Future<void> generateAndSharePDF_Transactions(List<transactions> items) async {
    final vm = _s;
    final company = vm.company;
    final _selectedtransaction = vm.selectedTransaction;
    final startDateString = vm.startDateString;
    final endDateString = vm.endDateString;
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
    final pageCount = (items.length / itemsPerPage).ceil();

    for (int pageNumber = 0; pageNumber < pageCount; pageNumber++) {
      final startIndex = pageNumber * itemsPerPage;
      final endIndex = (pageNumber + 1) * itemsPerPage;
      final itemsSubset = items.sublist(
        startIndex,
        endIndex > items.length ? items.length : endIndex,
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

  Future<void> generateAndShareCSV_Transactions(List<transactions> items) async {
    final vm = _s;
    final company = vm.company;
    final _selectedtransaction = vm.selectedTransaction;
    final startDateString = vm.startDateString;
    final endDateString = vm.endDateString;
    final List<List<dynamic>> csvData = [];
    final headersRow = [
      'Vch No',
      'Vch Name',
      'Vch Date',
      'Party Name',
      'Amount',
    ];
    csvData.add(headersRow);

    for (final item in items) {
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
    if (!_s.isTextEnabled) return;
    final initialDateRange = DateTimeRange(
      start: _notifier.startDate,
      end: _notifier.endDate,
    );
    final prefs = await SharedPreferences.getInstance();
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
      _notifier.setCustomDateRange(
        selectedDateRange.start,
        selectedDateRange.end,
        _currentSearchQuery,
      );
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
    final isTrendTabSelected = _s.isTrendTabSelected;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: _buildTransTabButton(
              label: 'Overview',
              isSelected: isTrendTabSelected,
              onTap: () {
                _notifier.setTrendTabSelected(true);
                _notifier.ensureChartData();
              },
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _buildTransTabButton(
              label: 'Transactions',
              isSelected: !isTrendTabSelected,
              onTap: () => _notifier.setTrendTabSelected(false),
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

  void _onTransactionsScroll() {
    final vm = _s;
    if (vm.isTrendTabSelected) return;
    if (vm.isLoadingMoreTx) return;
    if (!_notifier.canLoadMore) return;
    if (!_scrollFabController.hasClients) return;
    final position = _scrollFabController.position;
    if (position.pixels >= position.maxScrollExtent - 400) {
      _notifier.loadNextTransactionsPage(_currentSearchQuery);
    }
  }

  @override
  void initState() {
    super.initState();
    _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
    _scrollFabController.addListener(_onTransactionsScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      checkCurrencyMismatch(context);
    });
  }

  @override
  void dispose() {
    _scrollFabController.removeListener(_onTransactionsScroll);
    _scrollFabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(transactionsNotifierProvider);
    final vm = _s;
    final selectedSortOption = vm.selectedSortOption;
    final startdate_text = vm.startDateText;
    final enddate_text = vm.endDateText;
    final startDateString = vm.startDateString;
    final endDateString = vm.endDateString;
    final _isTextEnabled = vm.isTextEnabled;
    final _selecteddate = vm.selectedDate;
    final filteredItems_transactions = vm.filteredItemsTransactions;
    final transactions_count = vm.transactionsCount;
    final _selectedtransaction = vm.selectedTransaction;
    final spinner_list = vm.spinnerList;
    final transactions_list = vm.transactionsList;
    final isVisibleNoDataFound = vm.isVisibleNoDataFound;
    final isSortVisible = vm.isSortVisible;
    final _isLoading = vm.isLoading;
    final _isLoadingMoreTx = vm.isLoadingMoreTx;
    final _isTrendTabSelected = vm.isTrendTabSelected;
    final currencysymbol = vm.currencySymbol;
    final _currencyCode = vm.currencyCode;
    final decimal = vm.decimal;
    final company = vm.company;
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
              onTap: () => navigateToCompanySwitch(context),
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
            // Sort now lives in the app bar (standard Material/iOS
            // placement) instead of a floating pill hovering over the
            // list - that pattern covered content, was easy to miss, and
            // isn't how sort controls are usually surfaced. Disabled
            // (greyed out) rather than hidden when there's nothing to sort
            // (or on the Overview chart tab, where sorting never applied),
            // so its position doesn't jump around as data/tabs change.
            IconButton(
              onPressed: isSortVisible && !_isTrendTabSelected
                  ? () => _showSelectionWindow(context)
                  : null,
              icon: Icon(
                Icons.sort_rounded,
                color: isSortVisible && !_isTrendTabSelected
                    ? Colors.white
                    : Colors.white38,
                size: 22,
              ),
            ),
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
                        onTap: () async {
                          Navigator.pop(context);
                          if (transactions_list.isEmpty) return;
                          final items = await _notifier.fullTransactionsForExport();
                          if (items.isEmpty) return;
                          generateAndSharePDF_Transactions(items);
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
                        onTap: () async {
                          Navigator.pop(context);

                          if (transactions_list.isEmpty) return;
                          final items = await _notifier.fullTransactionsForExport();
                          if (items.isEmpty) return;
                          generateAndShareCSV_Transactions(items);
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
                                  _notifier.handleDate(
                                    value,
                                    _currentSearchQuery,
                                  );
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
                                  _notifier.selectTransactionType(
                                    newValue!,
                                    _currentSearchQuery,
                                  );
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
                        totalsByTypeAndMonth: _notifier.buildVoucherStackedTotals(),
                        countByMonth: _notifier.buildVoucherMonthCounts(),
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
                                  onChanged: (value) => _notifier
                                      .applyTransactionFilters(
                                        _currentSearchQuery,
                                      ),
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
                                                    ledger: card.ledger,
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

                // Bottom-of-list spinner while the next backward page of
                // vouchers loads (tally-api path only - see this class's
                // paging-state doc comment).
                if (!_isTrendTabSelected && _isLoadingMoreTx)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Colors.teal,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
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
