import 'package:FincoreGo/currencyFormat.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'constants.dart';
import 'widgets/scroll_fab.dart';
import 'api/ledger_repository.dart';
import 'api/monthly_bucket_helper.dart' show parseMoneyField;

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

class PartyTotalClickedRecPayClicked extends StatefulWidget {
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
  _PartyTotalClickedRecPayClickedPageState createState() =>
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
    extends State<PartyTotalClickedRecPayClicked>
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

  int counter = 0;
  double total_double = 0;

  String total_main = "0";

  final List<String> itemList = [
    'Default',
    'Newest to Oldest',
    'Oldest to Newest',
    'A->Z',
    'Z->A',
    'Amount High to Low',
    'Amount Low to High',
  ];

  String selectedSortOption = '';

  bool isSortVisible = false;
  final ScrollController _scrollFabController = ScrollController();
  late String currencysymbol = '';
  String _currencyCode = 'AED';

  late NumberFormat currencyFormat;

  String overdue_value = "", creditlimit = "0", creditperiod = "0";

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

  String? SecuritybtnAcessHolder;
  bool isDashEnable = true,
      isRolesEnable = true,
      isUserEnable = true,
      isRolesVisible = true,
      isUserVisible = true,
      _isSearchViewVisible = false,
      _isListVisible = true,
      isVisibleDays = false;

  String email = "";
  String name = "";

  TextEditingController searchController = TextEditingController();

  bool isVisibleNoDataFound = false;

  late GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey;
  late SharedPreferences prefs;
  late String startdate_text = "", enddate_text = "";
  String? datetype;

  late String? startdate_pref, enddate_pref;

  String? company = "", username = "";
  List<dynamic> myData = [];
  bool _isLoading = false;

  List<Data> item_list = [];
  List<Data> filteredItems = []; // default initialization

  // Ageing bucket report - client-side bucketing of the same outstanding
  // bill list (no new API), so users can see/filter which bucket their
  // outstanding amount is concentrated in. Boundaries come from the same
  // AgeingConfig thresholds (SharedPreferences 'heading1'..'heading5')
  // used by PartyClicked's Receivable/Payable row1-row6 breakdown,
  // instead of being hardcoded here - so both screens always agree.
  List<int> _ageingThresholds = [30, 60, 90, 120, 180];
  String? _selectedAgeingBucket; // null = no bucket filter applied

  List<String> get _ageingBuckets {
    final t = _ageingThresholds;
    return [
      '0-${t[0]}',
      '${t[0]}-${t[1]}',
      '${t[1]}-${t[2]}',
      '${t[2]}-${t[3]}',
      '${t[3]}-${t[4]}',
      '${t[4]}+',
    ];
  }

  Future<void> _loadAgeingThresholds() async {
    final t = [
      int.tryParse(prefs.getString('heading1') ?? '') ?? 30,
      int.tryParse(prefs.getString('heading2') ?? '') ?? 60,
      int.tryParse(prefs.getString('heading3') ?? '') ?? 90,
      int.tryParse(prefs.getString('heading4') ?? '') ?? 120,
      int.tryParse(prefs.getString('heading5') ?? '') ?? 180,
    ];
    if (mounted) {
      setState(() => _ageingThresholds = t);
    } else {
      _ageingThresholds = t;
    }
  }

  String _bucketFor(String overdueRaw) {
    final days = int.tryParse(overdueRaw) ?? 0;
    final t = _ageingThresholds;
    final buckets = _ageingBuckets;
    if (days <= t[0]) return buckets[0];
    if (days <= t[1]) return buckets[1];
    if (days <= t[2]) return buckets[2];
    if (days <= t[3]) return buckets[3];
    if (days <= t[4]) return buckets[4];
    return buckets[5];
  }

  Map<String, List<Data>> get _itemsByBucket {
    final map = {for (final b in _ageingBuckets) b: <Data>[]};
    for (final item in item_list) {
      map[_bucketFor(item.overdue)]!.add(item);
    }
    return map;
  }

  // Re-applies both the active search text and the active ageing-bucket
  // filter together, so the two work in combination rather than one
  // silently overriding the other.
  void _applyItemFilters() {
    Iterable<Data> items = item_list;

    if (_selectedAgeingBucket != null) {
      items = items.where((i) => _bucketFor(i.overdue) == _selectedAgeingBucket);
    }

    final query = searchController.text.trim().toLowerCase();
    if (query.isNotEmpty) {
      items = items.where((i) => i.billno.toLowerCase().contains(query));
    }

    setState(() {
      filteredItems = items.toList();
    });
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
              if (_selectedAgeingBucket != null)
                GestureDetector(
                  onTap: () {
                    _selectedAgeingBucket = null;
                    _applyItemFilters();
                  },
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
                for (final entry in _ageingBuckets.asMap().entries)
                  Builder(
                    builder: (context) {
                      final bucket = entry.value;
                      final color = _ageingBucketColors[entry.key];
                      final items = byBucket[bucket] ?? const <Data>[];
                      final total = items.fold<double>(
                        0,
                        (sum, i) => sum + i.outstanding,
                      );
                      final isSelected = _selectedAgeingBucket == bucket;

                      return GestureDetector(
                        onTap: () {
                          _selectedAgeingBucket = isSelected ? null : bucket;
                          _applyItemFilters();
                        },
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
                                  currencyCode: _currencyCode,
                                  symbol: currencysymbol,
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
                        setState(() {
                          selectedSortOption =
                              itemList[index]; // Update the selected index
                        });
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
                          ), // Add the icon to each list tile
                          title: Text(
                            itemList[index],
                            style: GoogleFonts.poppins(
                              fontWeight: itemList[index] == selectedSortOption
                                  ? FontWeight.bold
                                  : FontWeight
                                        .normal, // Apply bold style to the text if the tile is selected
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
      if (filteredItems.isNotEmpty) {
        filteredItems = List.from(item_list);
        _scrollFabController.animateTo(
          0.0,
          duration: Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  void sortByAlphabetAtoZ() {
    setState(() {
      if (filteredItems.isNotEmpty) {
        filteredItems.sort((a, b) => a.billno.compareTo(b.billno));
        _scrollFabController.animateTo(
          0.0,
          duration: Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  void sortByAlphabetZtoA() {
    setState(() {
      if (filteredItems.isNotEmpty) {
        filteredItems.sort((a, b) => b.billno.compareTo(a.billno));
        _scrollFabController.animateTo(
          0.0,
          duration: Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  void sortByDateLowtoHigh() {
    setState(() {
      if (filteredItems.isNotEmpty) {
        filteredItems.sort((a, b) => a.billdate.compareTo(b.billdate));
        _scrollFabController.animateTo(
          0.0,
          duration: Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  void sortByDateHightoLow() {
    setState(() {
      if (filteredItems.isNotEmpty) {
        filteredItems.sort((a, b) => b.billdate.compareTo(a.billdate));
        _scrollFabController.animateTo(
          0.0,
          duration: Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  void sortByAmountLowtoHigh() {
    setState(() {
      if (filteredItems.isNotEmpty) {
        if (type == "Receivable") {
          filteredItems.sort((a, b) => b.outstanding.compareTo(a.outstanding));
          _scrollFabController.animateTo(
            0.0,
            duration: Duration(milliseconds: 500),
            curve: Curves.easeInOut,
          );
        } else {
          filteredItems.sort((a, b) => a.outstanding.compareTo(b.outstanding));
          _scrollFabController.animateTo(
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
      if (filteredItems.isNotEmpty) {
        if (type == "Receivable") {
          filteredItems.sort((a, b) => a.outstanding.compareTo(b.outstanding));
          _scrollFabController.animateTo(
            0.0,
            duration: Duration(milliseconds: 500),
            curve: Curves.easeInOut,
          );
        } else {
          filteredItems.sort((a, b) => b.outstanding.compareTo(a.outstanding));
          _scrollFabController.animateTo(
            0.0,
            duration: Duration(milliseconds: 500),
            curve: Curves.easeInOut,
          );
        }
      }
    });
  }

  Future<void> generateAndSharePDF_RecPay() async {
    final font = pw.Font.ttf(
      await rootBundle.load("assets/fonts/NotoSans.ttf"),
    );
    final pdf = pw.Document();

    final companyName = company!;
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
    final pageCount = (item_list.length / itemsPerPage).ceil();

    for (int pageNumber = 0; pageNumber < pageCount; pageNumber++) {
      final startIndex = pageNumber * itemsPerPage;
      final endIndex = (pageNumber + 1) * itemsPerPage;
      final itemsSubset = item_list.sublist(
        startIndex,
        endIndex > item_list.length ? item_list.length : endIndex,
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
    ], text: 'Sharing Receivable/Payable Report of $company');
  }

  Future<void> generateAndShareCSV_RecPay() async {
    final List<List<dynamic>> csvData = [];
    final headersRow = [
      'Bill Date',
      'Bill No',
      'Due Date',
      'Overdue(Days)',
      'Amount',
    ];
    csvData.add(headersRow);

    for (final item in item_list) {
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
    ], text: 'Sharing Receivable/Payable Report of $company');
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
      currencyCode: _currencyCode,
      symbol: currencysymbol,
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

  /// `creditLimit`/`creditPeriod` are already columns on the base
  /// `/ledgers` list row - no separate endpoint like legacy's `getLedger`
  /// is needed.
  Future<void> fetchCreditlimit() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final ledgers = await LedgerRepository.instance.listLedgers();
      final match = ledgers.firstWhere(
        (l) => l['masterId'] == ledgerMasterId,
        orElse: () => const {},
      );

      final creditLimitValue = parseMoneyField(match['creditLimit']);
      creditlimit = creditLimitValue.toString();

      final creditPeriodRaw = match['creditPeriod']?.toString();
      if (creditPeriodRaw == null || creditPeriodRaw.isEmpty) {
        creditperiod = '0';
      } else if (creditPeriodRaw.contains('Days')) {
        setState(() => isVisibleDays = false);
        creditperiod = creditPeriodRaw;
      } else {
        setState(() => isVisibleDays = true);
        creditperiod = creditPeriodRaw;
      }
    } catch (e) {
      print(e);
    }
  }

  /// `reports/ledgers/outstanding-bills` already returns every open bill
  /// for this ledger with a server-computed `overdueDays` - no separate
  /// "showAll"/ageing-bucket param needed, since the ageing bucket split
  /// happens entirely client-side in this screen already
  /// (`_ageingBuckets`/`_selectedAgeingBucket`). `isDebit == 'true'` (set by
  /// the caller for the Receivable tile) keeps only bills with a positive
  /// balance; the Payable tile (isDebit == '') keeps the rest - matching
  /// `DashboardClicked.dart`'s `_fetchReceivablePayableTallyApi` convention.
  Future<void> fetchData(final String isDebit) async {
    setState(() {
      _isLoading = true;
      _isListVisible = true;
      isSortVisible = false;
    });

    item_list.clear();
    filteredItems.clear();
    _selectedAgeingBucket = null;

    try {
      final bills = await LedgerRepository.instance.outstandingBills(
        ledgerMasterId: ledgerMasterId,
      );

      final rows = bills.where((bill) {
        final balance = parseMoneyField(bill['finalBalance']);
        return isDebit == 'true' ? balance > 0 : balance <= 0;
      }).map((bill) {
        return Data.fromJson({
          'billno': bill['name'] ?? '',
          'overdue': bill['overdueDays']?.toString() ?? '0',
          'outstanding': parseMoneyField(bill['finalBalance']).abs(),
          'billdate': bill['date'] ?? '',
          'duedate': bill['dueDate'] ?? 'null',
        });
      }).toList();

      isVisibleNoDataFound = false;
      item_list.addAll(rows);
      filteredItems = item_list;
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      print(e);
    }

    setState(() {
      if (item_list.isEmpty) {
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
    await _loadAgeingThresholds();

    setState(() {
      company = prefs.getString('company_name');
      username = prefs.getString('username');
    });

    String? currencyCode = '';

    currencyCode = prefs.getString('currencycode');

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

    try {
      selectedSortOption = prefs.getString('sort')!;
      if (selectedSortOption == null || selectedSortOption == 'null') {
        selectedSortOption = 'Default';
      }
    } catch (e) {
      selectedSortOption = 'Default';
    }

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

    startdate_text = convertDateFormat(startDateString);
    enddate_text = convertDateFormat(endDateString);

    overdue_value = variable + variabletype;

    fetchCreditlimit();

    String isDebit = "";
    if (type == "Payable") {
      isDebit = "";
    } else if (type == "Receivable") {
      isDebit = "true";
    }

    /* filteredItems = [
      Data(
        billno: 'INV-001245',
        overdue: '12',
        outstanding: 1540.75,
        billdate: '2025-09-01',
        duedate: '2025-09-15',
      ),
      Data(
        billno: 'INV-001246',
        overdue: '25',
        outstanding: 27890.20,
        billdate: '2025-08-25',
        duedate: '2025-09-05',
      ),
      Data(
        billno: 'INV-001247',
        overdue: '5',
        outstanding: 990.00,
        billdate: '2025-09-10',
        duedate: '2025-09-25',
      ),
      Data(
        billno: 'INV-001248',
        overdue: '60',
        outstanding: 74500.99,
        billdate: '2025-07-20',
        duedate: '2025-08-05',
      ),
      Data(
        billno: 'INV-001249',
        overdue: '0',
        outstanding: 459.45,
        billdate: '2025-09-18',
        duedate: '2025-10-02',
      ),
    ];*/
    fetchData(isDebit);
  }

  @override
  void dispose() {
    _scrollFabController.dispose();
    super.dispose();
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
              onPressed: () {
                counter++;

                if (counter % 2 == 0) {
                  setState(() {
                    _isSearchViewVisible = false;
                  });
                } else {
                  setState(() {
                    _isSearchViewVisible = true;
                  });
                }
              },
              icon: Icon(Icons.search, color: Colors.white, size: 22),
            ),
            // Sort in the app bar, matching standard Material/iOS
            // placement - see PartyDrillDown.dart's identical fix for why
            // the floating pill it replaces was a poor pattern.
            IconButton(
              onPressed: isSortVisible
                  ? () => _showSelectionWindow(context)
                  : null,
              icon: Icon(
                Icons.sort_rounded,
                color: isSortVisible ? Colors.white : Colors.white38,
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
                          if (item_list.isEmpty) return;
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
                          if (item_list.isEmpty) return;
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
                                    enddate_text,
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
                                    overdue_value,
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
                                    currencyCode: _currencyCode,
                                    symbol: currencysymbol,
                                    amountText: CurrencyFormatter.formatCurrencyParts(
                                      double.tryParse(
                                            creditlimit.replaceAll(',', ''),
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
                                    creditperiod,
                                    style: GoogleFonts.poppins(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12.5,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface,
                                    ),
                                  ),
                                  Visibility(
                                    visible: isVisibleDays,
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

              if (item_list.isNotEmpty)
                SliverToBoxAdapter(child: _buildAgeingBucketSummary(context)),

              // Only reserve space/paint this card when it actually has
              // something to show (search field or "no records" state) -
              // otherwise it rendered as an empty decorated box (visible
              // shadow/rounded corners with nothing inside).
              if (_isSearchViewVisible || isVisibleNoDataFound)
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
                      if (_isSearchViewVisible) ...[
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
                              onChanged: (value) => _applyItemFilters(),
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

                    ],
                  ),
                ),
              ),

              // 📋 Bills list - a real sliver (SliverList) so the
              // CustomScrollView only builds cards near the viewport; the
              // previous shrinkWrap ListView.builder forced eager layout of
              // every bill up front, which is what caused the same
              // scroll-hang bug already fixed on the Party list.
              if (_isListVisible)
                SliverPadding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                            final card = filteredItems[index];
                            final curr =
                                currencysymbol ??
                                ''; // ✅ currency symbol from prefs

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
                    }, childCount: filteredItems.length),
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
