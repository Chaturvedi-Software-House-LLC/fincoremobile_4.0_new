import 'package:FincoreGo/currencyFormat.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'constants.dart';
import 'widgets/scroll_fab.dart';
import 'providers/party_clicked_rec_pay_clicked_notifier.dart';

class Data {
  final String billno;
  final String overdue;
  final double outstanding;
  final String billdate;
  final String duedate;

  Data({
    required this.billno,
    required this.overdue,
    required this.outstanding,
    required this.billdate,
    required this.duedate,
  });

  factory Data.fromJson(Map<String, dynamic> json) {
    return Data(
      billno: json['billno'].toString(),
      overdue: json['overdue'].toString(),
      // Some bills come back with a comma-formatted "outstanding" string
      // (e.g. "1,234.56") - double.tryParse silently fails on the comma
      // and falls back to 0, which is what made several real bills show
      // as a 0.00 amount even though they clearly have an overdue balance.
      outstanding:
          double.tryParse(
            json['outstanding'].toString().replaceAll(',', ''),
          ) ??
          0,
      billdate: json['billdate'].toString(),
      duedate: json['duedate'].toString(),
    );
  }
}

class PartyTotalClickedRecPayClicked extends ConsumerStatefulWidget {
  final String startdate_string,
      enddate_string,
      type,
      ledger,
      total,
      variable,
      variabletype;
  final int? ledgerMasterId;

  const PartyTotalClickedRecPayClicked({
    required this.startdate_string,
    required this.enddate_string,
    required this.type,
    required this.ledger,
    required this.total,
    required this.variable,
    required this.variabletype,
    this.ledgerMasterId,
  });
  @override
  ConsumerState<PartyTotalClickedRecPayClicked> createState() =>
      _PartyTotalClickedRecPayClickedPageState(
        startDateString: startdate_string,
        endDateString: enddate_string,
        type: type,
        total: total,
        ledger: ledger,
        variable: variable,
        variabletype: variabletype,
        ledgerMasterId: ledgerMasterId,
      );
}

class _PartyTotalClickedRecPayClickedPageState
    extends ConsumerState<PartyTotalClickedRecPayClicked>
    with TickerProviderStateMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  String startDateString = "",
      endDateString = "",
      type = "",
      ledger = "",
      total = "",
      variable = "",
      variabletype = "";
  final int? ledgerMasterId;

  final List<String> itemList = [
    'Default',
    'Newest to Oldest',
    'Oldest to Newest',
    'A->Z',
    'Z->A',
    'Amount High to Low',
    'Amount Low to High',
  ];

  final ScrollController _scrollFabController = ScrollController();

  _PartyTotalClickedRecPayClickedPageState({
    required this.startDateString,
    required this.endDateString,
    required this.type,
    required this.ledger,
    required this.total,
    required this.variable,
    required this.variabletype,
    this.ledgerMasterId,
  });

  TextEditingController searchController = TextEditingController();

  late final _args = PartyClickedRecPayClickedArgs(
    startDateString: startDateString,
    endDateString: endDateString,
    type: type,
    variable: variable,
    variabletype: variabletype,
    ledgerMasterId: ledgerMasterId,
  );

  PartyClickedRecPayClickedNotifier get _notifier =>
      ref.read(partyClickedRecPayClickedNotifierProvider(_args).notifier);
  PartyClickedRecPayClickedState get _s =>
      ref.read(partyClickedRecPayClickedNotifierProvider(_args));

  Map<String, List<Data>> get _itemsByBucket => _notifier.itemsByBucket();

  void _scrollToTop() {
    _scrollFabController.animateTo(
      0.0,
      duration: Duration(milliseconds: 500),
      curve: Curves.easeInOut,
    );
  }

  void _selectSort(String option) {
    if (_notifier.selectSortOption(option)) {
      _scrollToTop();
    }
  }

  // Indexed by bucket position (0 = freshest .. 5 = most overdue) since
  // the bucket labels themselves are now dynamic (driven by AgeingConfig).
  static const List<Color> _ageingBucketColors = [
    Color(0xFF2ECC71),
    Color(0xFFA9D82E),
    Color(0xFFF1C40F),
    Color(0xFFE67E22),
    Color(0xFFE85D3D),
    Color(0xFFE74C3C),
  ];

  Widget _buildAgeingBucketSummary(BuildContext context) {
    final vm = _s;
    final byBucket = _itemsByBucket;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Theme.of(context).brightness == Brightness.dark
            ? Border.all(color: Colors.white.withOpacity(0.10), width: 1)
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black12.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Ageing Breakdown',
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              if (vm.selectedAgeingBucket != null)
                GestureDetector(
                  onTap: () => _notifier.selectAgeingBucket(null),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.close_rounded,
                        size: 14,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        'Clear filter',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          // 6 buckets (matching AgeingConfig's 5 thresholds) no longer fit
          // in one un-scrolled row on a phone width, so this scrolls
          // horizontally like the "As of" pill above it already does.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final entry in vm.ageingBuckets.asMap().entries)
                  Builder(
                    builder: (context) {
                      final bucket = entry.value;
                      final color = _ageingBucketColors[entry.key];
                      final items = byBucket[bucket] ?? const <Data>[];
                      final total = items.fold<double>(
                        0,
                        (sum, i) => sum + i.outstanding,
                      );
                      final isSelected = vm.selectedAgeingBucket == bucket;

                      return GestureDetector(
                        onTap: () => _notifier.selectAgeingBucket(bucket),
                        child: Container(
                          width: 96,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          padding: const EdgeInsets.symmetric(
                            vertical: 10,
                            horizontal: 4,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? color.withOpacity(0.18)
                                : color.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected
                                  ? color
                                  : color.withOpacity(0.3),
                              width: isSelected ? 1.5 : 1,
                            ),
                          ),
                          child: Column(
                            children: [
                              Text(
                                '$bucket d',
                                style: GoogleFonts.poppins(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: color,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${items.length} bill${items.length == 1 ? '' : 's'}',
                                style: GoogleFonts.poppins(
                                  fontSize: 10,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 4),
                              FittedBox(
                                child: currencyAmountText(
                                  currencyCode: vm.currencyCode,
                                  symbol: vm.currencySymbol,
                                  amountText:
                                      '${CurrencyFormatter.formatCurrencyParts(total.abs()).number} ${total >= 0 ? 'CR' : 'DR'}',
                                  style: GoogleFonts.poppins(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
                                  ),
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
          ),
        ],
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
                        _selectSort(itemList[index]);
                        Navigator.pop(
                          context,
                        ); // Close the selection window after a tile is selected
                      },
                      child: Container(
                        child: ListTile(
                          leading: Icon(
                            icons[index],
                          ), // Add the icon to each list tile
                          title: Text(
                            itemList[index],
                            style: GoogleFonts.poppins(
                              fontWeight:
                                  itemList[index] == _s.selectedSortOption
                                      ? FontWeight.bold
                                      : FontWeight
                                            .normal, // Apply bold style to the text if the tile is selected
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

  Future<void> generateAndSharePDF_RecPay() async {
    final vm = _s;
    final font = pw.Font.ttf(
      await rootBundle.load("assets/fonts/NotoSans.ttf"),
    );
    final pdf = pw.Document();

    final companyName = vm.company;
    final reportname = 'Receivable/Payable Summary';
    final partyname = ledger;
    final overlimit = variabletype;

    final headersRow3 = [
      'Bill Date',
      'Bill No',
      'Due Date',
      'Overdue(Days)',
      'Amount',
    ];

    final itemsPerPage = 10;
    final orders = vm.itemList;
    final pageCount = (orders.length / itemsPerPage).ceil();

    for (int pageNumber = 0; pageNumber < pageCount; pageNumber++) {
      final startIndex = pageNumber * itemsPerPage;
      final endIndex = (pageNumber + 1) * itemsPerPage;
      final itemsSubset = orders.sublist(
        startIndex,
        endIndex > orders.length ? orders.length : endIndex,
      );

      final tableSubsetRows = itemsSubset.map((item) {
        return [
          convertDateFormat(item.billdate),
          handleBillNo(item.billno),
          convertDueDateFormat(item.duedate, item.billdate),
          item.overdue,
          formatAmount(item.outstanding.toString()),
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
          4: pw.FractionColumnWidth(0.4),
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
                      'Ledger:',
                      style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(width: 5),
                    pw.Text(partyname, style: pw.TextStyle(fontSize: 16)),
                  ],
                ),
                pw.SizedBox(height: 10),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  children: [
                    pw.Text(
                      'Overdue Limit:',
                      style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(width: 5),
                    pw.Text(
                      '$overlimit Days',
                      style: pw.TextStyle(fontSize: 16),
                    ),
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
    final tempFilePath = '${tempDir.path}/Receivable_Payable.pdf';
    final file = File(tempFilePath);
    await file.writeAsBytes(pdfData);

    // ✅ Updated share method
    await Share.shareXFiles([
      XFile(tempFilePath),
    ], text: 'Sharing Receivable/Payable Report of ${vm.company}');
  }

  Future<void> generateAndShareCSV_RecPay() async {
    final vm = _s;
    final List<List<dynamic>> csvData = [];
    final headersRow = [
      'Bill Date',
      'Bill No',
      'Due Date',
      'Overdue(Days)',
      'Amount',
    ];
    csvData.add(headersRow);

    for (final item in vm.itemList) {
      final rowData = [
        convertDateFormat(item.billdate),
        handleBillNo(item.billno),
        convertDueDateFormat(item.duedate, item.billdate),
        item.overdue,
        formatAmount(item.outstanding.toString()),
      ];
      csvData.add(rowData);
    }

    final csvString = const ListToCsvConverter().convert(csvData);
    final tempDir = await Directory.systemTemp.createTemp();
    final tempFilePath = '${tempDir.path}/Receivable_Payable.csv';
    final file = File(tempFilePath);
    await file.writeAsString(csvString);

    // ✅ Updated share method
    await Share.shareXFiles([
      XFile(tempFilePath),
    ], text: 'Sharing Receivable/Payable Report of ${vm.company}');
  }

  String formatCostCenter(String costcenter) {
    String costcenter_string = "";
    if (costcenter == 'null') {
      costcenter_string = '*Not Applicable';
    } else {
      costcenter_string = costcenter;
    }
    // Apply any transformations or formatting to the 'amount' variable here
    return costcenter_string;
  }

  String formatOpening(String opening) {
    String opening_string = "";

    if (opening.contains("-")) {
      opening = opening.replaceAll("-", "");
      double opening_double = double.parse(opening);
      int opening_int = opening_double.round();
      opening_string = CurrencyFormatter.formatCurrency_int(opening_int);
      opening_string = opening_string + " DR";
    } else {
      double opening_double = double.parse(opening);
      int opening_int = opening_double.round();
      opening_string = CurrencyFormatter.formatCurrency_int(opening_int);
      opening_string = opening_string + " CR";
    }
    return opening_string;
  }

  // The header "total" arrives in one of two shapes depending on which tap
  // brought the user here: a plain signed number (from the card's own
  // Total tap) or "<number> DR"/"<number> CR" (from a bucket row tap,
  // already suffix-formatted upstream). Handle both so the symbol/glyph
  // renders correctly either way instead of showing plain unstyled text.
  Widget _totalAmountWidget(String value, TextStyle style) {
    final vm = _s;
    String cleaned = value.trim();
    String suffix;
    final upper = cleaned.toUpperCase();
    if (upper.endsWith(' DR') || upper.endsWith(' CR')) {
      suffix = upper.substring(upper.length - 2);
      cleaned = cleaned.substring(0, cleaned.length - 3).trim();
    } else if (cleaned.contains('-')) {
      cleaned = cleaned.replaceAll('-', '');
      suffix = 'DR';
    } else {
      suffix = 'CR';
    }
    final parsed = double.tryParse(cleaned.replaceAll(',', '')) ?? 0.0;
    final parts = CurrencyFormatter.formatCurrencyParts(parsed);
    return currencyAmountText(
      currencyCode: vm.currencyCode,
      symbol: vm.currencySymbol,
      amountText: '${parts.number} $suffix',
      style: style,
    );
  }

  String convertDateFormat(String dateStr) {
    String formattedDate = "";

    DateTime date = DateTime.parse(dateStr);

    // Format the date to the desired output format
    formattedDate = DateFormat("dd-MMM-yyyy").format(date);

    // Parse the input date string

    return formattedDate;
  }

  String handleBillNo(String billno) {
    debugPrint('bill no -> $billno');

    if (billno == 'null') {
      billno = "N/A";
    }
    return billno;
  }

  String convertDueDateFormat(String duedate, String billdate) {
    String formattedDate = "";

    if (duedate == 'null') {
      DateTime date = DateTime.parse(billdate);

      formattedDate = DateFormat("dd-MMM-yyyy").format(date);
    } else {
      formattedDate = duedate;
    }
    // Parse the input date string

    return formattedDate;
  }

  @override
  void dispose() {
    _scrollFabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(partyClickedRecPayClickedNotifierProvider(_args));
    final vm = _s;
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(52),
        child: AppBar(
          backgroundColor: app_color,
          elevation: 2,

          automaticallyImplyLeading: false,

          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
            onPressed: () {
              Navigator.pop(context);
            },
          ),
          centerTitle: false,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                ledger,
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                type,
                style: GoogleFonts.poppins(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          actions: [
            IconButton(
              onPressed: _notifier.toggleSearchView,
              icon: Icon(Icons.search, color: Colors.white, size: 22),
            ),
            // Sort in the app bar, matching standard Material/iOS
            // placement - see PartyDrillDown.dart's identical fix for why
            // the floating pill it replaces was a poor pattern.
            IconButton(
              onPressed: vm.isSortVisible
                  ? () => _showSelectionWindow(context)
                  : null,
              icon: Icon(
                Icons.sort_rounded,
                color: vm.isSortVisible ? Colors.white : Colors.white38,
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
                        onTap: () async {
                          Navigator.pop(context);
                          if (vm.itemList.isEmpty) return;
                          try {
                            await generateAndSharePDF_RecPay();
                          } catch (e) {
                            debugPrint('Share as PDF failed: $e');
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Could not generate PDF: $e'),
                                ),
                              );
                            }
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
                        onTap: () async {
                          Navigator.pop(context);
                          if (vm.itemList.isEmpty) return;
                          try {
                            await generateAndShareCSV_RecPay();
                          } catch (e) {
                            debugPrint('Share as CSV failed: $e');
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Could not generate CSV: $e'),
                                ),
                              );
                            }
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

      body: Stack(
        children: [
          CustomScrollView(
            controller: _scrollFabController,
            slivers: [
              SliverToBoxAdapter(
                child: Container(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
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
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Total Value
                      Center(
                        child: _totalAmountWidget(
                          total,
                          GoogleFonts.poppins(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Theme.of(context).colorScheme.onSurface,
                            letterSpacing: 0,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),

                      // As of + Overdue + Credit Limit row (pill style)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context).brightness ==
                                  Brightness.dark
                              ? Colors.white.withOpacity(0.06)
                              : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Left part: As of + Overdue
                              Row(
                                children: [
                                  Text(
                                    'As of ',
                                    style: GoogleFonts.poppins(
                                      fontWeight: FontWeight.w500,
                                      fontSize: 12.5,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface,
                                    ),
                                  ),
                                  Text(
                                    vm.endDateText,
                                    style: GoogleFonts.poppins(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12.5,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface,
                                    ),
                                  ),
                                  Text(
                                    ' | ',
                                    style: GoogleFonts.poppins(
                                      fontWeight: FontWeight.w500,
                                      fontSize: 12.5,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  Text(
                                    vm.overdueValue,
                                    style: GoogleFonts.poppins(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12.5,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface,
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(width: 16),

                              // Right part: Credit Limit + Period
                              Row(
                                children: [
                                  Text(
                                    'Credit Limit: ',
                                    style: GoogleFonts.poppins(
                                      fontWeight: FontWeight.w500,
                                      fontSize: 12.5,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface,
                                    ),
                                  ),
                                  currencyAmountText(
                                    currencyCode: vm.currencyCode,
                                    symbol: vm.currencySymbol,
                                    amountText: CurrencyFormatter.formatCurrencyParts(
                                      double.tryParse(
                                            vm.creditLimit.replaceAll(',', ''),
                                          ) ??
                                          0.0,
                                    ).number,
                                    style: GoogleFonts.poppins(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12.5,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface,
                                    ),
                                  ),
                                  Text(
                                    ' / ',
                                    style: GoogleFonts.poppins(
                                      fontWeight: FontWeight.w500,
                                      fontSize: 12.5,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  Text(
                                    vm.creditPeriod,
                                    style: GoogleFonts.poppins(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12.5,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface,
                                    ),
                                  ),
                                  Visibility(
                                    visible: vm.isVisibleDays,
                                    child: Text(
                                      ' Days',
                                      style: GoogleFonts.poppins(
                                        fontWeight: FontWeight.w500,
                                        fontSize: 12.5,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurface,
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
                ),
              ),

              if (vm.itemList.isNotEmpty)
                SliverToBoxAdapter(child: _buildAgeingBucketSummary(context)),

              // Only reserve space/paint this card when it actually has
              // something to show (search field or "no records" state) -
              // otherwise it rendered as an empty decorated box (visible
              // shadow/rounded corners with nothing inside).
              if (vm.isSearchViewVisible || vm.isVisibleNoDataFound)
                SliverToBoxAdapter(
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(
                    left: 16,
                    right: 16,
                    bottom: 16,
                  ),
                  padding: const EdgeInsets.only(
                    left: 0,
                    right: 0,
                    top: 4,
                    bottom: 4,
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
                  child: Column(
                    children: [
                      if (vm.isSearchViewVisible) ...[
                        Padding(
                          padding: const EdgeInsets.only(
                            left: 12,
                            right: 12,
                            top: 10,
                          ),
                          child: SizedBox(
                            height: 46,
                            child: TextField(
                              controller: searchController,
                              onChanged: _notifier.filter,
                              style: GoogleFonts.poppins(
                                fontSize: 13.5,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                              decoration: InputDecoration(
                                isDense: true,
                                hintText: 'Search...',
                                hintStyle: GoogleFonts.poppins(fontSize: 13),
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
                      ],

                      if (vm.isVisibleNoDataFound)
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

                    ],
                  ),
                ),
              ),

              // 📋 Bills list - a real sliver (SliverList) so the
              // CustomScrollView only builds cards near the viewport; the
              // previous shrinkWrap ListView.builder forced eager layout of
              // every bill up front, which is what caused the same
              // scroll-hang bug already fixed on the Party list.
              if (vm.isListVisible)
                SliverPadding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                            final card = vm.filteredItems[index];
                            final curr = vm.currencySymbol; // ✅ currency symbol from prefs

                            return Container(
                              margin: const EdgeInsets.only(bottom: 14),
                              decoration: BoxDecoration(
                                color: Theme.of(context).cardColor,
                                borderRadius: BorderRadius.circular(18),
                                border:
                                    Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? Border.all(
                                        color: Colors.white.withOpacity(0.10),
                                        width: 1,
                                      )
                                    : null,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.05),
                                    blurRadius: 10,
                                    spreadRadius: 1,
                                    offset: const Offset(0, 5),
                                  ),
                                ],
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 16,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // 🔹 Bill Number Header
                                    Row(
                                      children: [
                                        Container(
                                          width: 34,
                                          height: 34,
                                          decoration: const BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: [
                                                Color(0xFF00C9FF),
                                                Color(0xFF92FE9D),
                                              ], // cyan-green
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                            ),
                                            borderRadius: BorderRadius.all(
                                              Radius.circular(10),
                                            ),
                                          ),
                                          child: const Icon(
                                            Icons.receipt_long,
                                            size: 18,
                                            color: Colors.white,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            handleBillNo(card.billno) ?? 'N/A',
                                            softWrap: true,
                                            style: GoogleFonts.poppins(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w700,
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.onSurface,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),

                                    const SizedBox(height: 12),

                                    // 🔹 Info Chips
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        // Bill Date Chip
                                        _buildGradientChip(
                                          context: context,
                                          icon: Icons.calendar_today_rounded,
                                          label: 'Bill Date',
                                          value: convertDateFormat(
                                            card.billdate,
                                          ),
                                          colors: const [
                                            Color(0xFF56CCF2),
                                            Color(0xFF2F80ED),
                                          ],
                                        ),
                                        // Overdue Chip
                                        _buildGradientChip(
                                          context: context,
                                          icon: Icons.timelapse_rounded,
                                          label: 'Overdue',
                                          value: '${card.overdue} Days',
                                          colors: const [
                                            Color(0xFFFF9966),
                                            Color(0xFFFF5E62),
                                          ],
                                        ),

                                        // Due Date Chip
                                        _buildGradientChip(
                                          context: context,
                                          icon: Icons.event_rounded,
                                          label: 'Due',
                                          value: convertDueDateFormat(
                                            card.duedate,
                                            card.billdate,
                                          ),
                                          colors: const [
                                            Color(0xFF11998E),
                                            Color(0xFF38EF7D),
                                          ],
                                        ),
                                      ],
                                    ),

                                    const SizedBox(height: 16),

                                    // 🔹 Amount Section (Bottom Right)
                                    Align(
                                      alignment: Alignment.bottomRight,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 8,
                                        ),
                                        decoration: BoxDecoration(
                                          gradient: const LinearGradient(
                                            colors: [
                                              Color(0xFF43CEA2),
                                              Color(0xFF185A9D),
                                            ],
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black12.withOpacity(
                                                0.15,
                                              ),
                                              blurRadius: 6,
                                              offset: const Offset(0, 3),
                                            ),
                                          ],
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.center,
                                          children: [
                                            Flexible(
                                              child: formatAmountRich(
                                                card.outstanding.toString(),
                                                softWrap: true,
                                                overflow: TextOverflow.visible,
                                                style: GoogleFonts.poppins(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w600,
                                                  color: Colors.white,
                                                  height: 1.4,
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
                            );
                    }, childCount: vm.filteredItems.length),
                  ),
                ),
            ],
          ),

          if (vm.isLoading)
            Positioned.fill(
              child: Container(
                color: Theme.of(context).scaffoldBackgroundColor,
                child: _buildSkeletonList(),
              ),
            ),

          ScrollFab(controller: _scrollFabController),
        ],
      ),
    );
  }

  // Skeleton stand-in for the header + list while the initial fetch is in
  // flight - replaces the old dimmed spinner-over-stale-content overlay so
  // the loading state reads as "content incoming" instead of a blank page.
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
              ],
            ),
          ),
          for (int i = 0; i < 6; i++)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
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
                border: Border.all(
                  color: Theme.of(context).dividerColor.withOpacity(0.55),
                ),
              ),
              child: Row(
                children: [
                  const ShimmerBox(width: 38, height: 38, borderRadius: 12),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const ShimmerBox(height: 13, width: 140),
                        const SizedBox(height: 6),
                        const ShimmerBox(height: 11, width: 90),
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

  Widget _buildMetaChipWithIcon(
    IconData icon,
    String label,
    Color bgColor,
    Color textColor,
  ) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: textColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.poppins(
              color: textColor,
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

Widget _buildGradientChip({
  required BuildContext context,
  required IconData icon,
  required String label,
  required String value,
  required List<Color> colors,
}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: Theme.of(context).brightness == Brightness.dark
          ? Theme.of(context).colorScheme.surfaceContainerHighest
          : const Color(0xFFF7F8FA), // 👈 soft light grey background
      borderRadius: BorderRadius.circular(18),
      border: Theme.of(context).brightness == Brightness.dark
          ? Border.all(color: Colors.white.withOpacity(0.10), width: 1)
          : null,
      boxShadow: [
        BoxShadow(
          color: Colors.black12.withOpacity(0.05),
          blurRadius: 4,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,

      children: [
        // 🔹 Left side: gradient icon + label
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: colors,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 14, color: Colors.white),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ),

        // 🔹 Right side: value text
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            softWrap: true,
            overflow: TextOverflow.visible,
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
              height: 1.4,
            ),
          ),
        ),
      ],
    ),
  );
}
