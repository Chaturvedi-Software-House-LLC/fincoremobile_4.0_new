import 'dart:convert';
import 'widgets/scroll_fab.dart';
import 'package:FincoreGo/currencyFormat.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

class Data {
  final String vchno;
  final String vchdate;
  final double amount;
  final String ispostdated;
  final String isoptional;

  Data({
    required this.vchno,
    required this.vchdate,
    required this.amount,
    required this.ispostdated,
    required this.isoptional,
  });

  factory Data.fromJson(Map<String, dynamic> json) {
    return Data(
      vchno: json['vchno'].toString(),
      vchdate: json['vchdate'].toString(),
      amount: double.tryParse(json['amount'].toString()) ?? 0,
      ispostdated: json['ispostdated'].toString(),
      isoptional: json['isoptional'].toString(),
    );
  }
}

class PartyTotalClickedRest extends StatefulWidget {
  final String startdate_string, enddate_string, type, ledger, total;

  const PartyTotalClickedRest({
    required this.startdate_string,
    required this.enddate_string,
    required this.type,
    required this.ledger,
    required this.total,
  });
  @override
  _PartyTotalClickedRestPageState createState() =>
      _PartyTotalClickedRestPageState(
        startDateString: startdate_string,
        endDateString: enddate_string,
        type: type,
        total: total,
        ledger: ledger,
      );
}

class _PartyTotalClickedRestPageState extends State<PartyTotalClickedRest>
    with TickerProviderStateMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ScrollController _scrollFabController = ScrollController();
  String startDateString = "",
      endDateString = "",
      type = "",
      ledger = "",
      total = "",
      token = '';

  int counter = 0;

  double total_double = 0;

  String total_main = "0";

  List<Data> filteredItems =
      []; // Initialize an empty list to hold the filtered items

  _PartyTotalClickedRestPageState({
    required this.startDateString,
    required this.endDateString,
    required this.type,
    required this.ledger,
    required this.total,
  });

  String? SecuritybtnAcessHolder;
  bool isDashEnable = true,
      isRolesEnable = true,
      isUserEnable = true,
      isRolesVisible = true,
      isUserVisible = true,
      _isSearchViewVisible = false,
      _isListVisible = false,
      isVisiblePostDated = true,
      isVisibleOptional = true;

  String email = "";
  String name = "";

  TextEditingController searchController = TextEditingController();

  bool isVisibleNoDataFound = false;

  String selectedSortOption = '';

  late GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey;
  late SharedPreferences prefs;
  late String startdate_text = "", enddate_text = "";
  String? datetype;

  String HttpURL = "";

  String? hostname = "",
      company = "",
      serial_no = "",
      company_lowercase = "",
      username = "";
  List<dynamic> myData = [];
  bool _isLoading = false;

  bool isSortVisible = false;

  final List<String> itemList = [
    'Default',
    'Newest to Oldest',
    'Oldest to Newest',
    'A->Z',
    'Z->A',
    'Amount High to Low',
    'Amount Low to High',
  ];

  ScrollController _scrollController = ScrollController();

  List<Data> item_list = [];

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
        _scrollController.animateTo(
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
        filteredItems.sort((a, b) => a.vchno.compareTo(b.vchno));
        _scrollController.animateTo(
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
        filteredItems.sort((a, b) => b.vchno.compareTo(a.vchno));
        _scrollController.animateTo(
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
        filteredItems.sort((a, b) => a.vchdate.compareTo(b.vchdate));
        _scrollController.animateTo(
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
        filteredItems.sort((a, b) => b.vchdate.compareTo(a.vchdate));
        _scrollController.animateTo(
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
        filteredItems.sort((a, b) => a.amount.compareTo(b.amount));
        _scrollController.animateTo(
          0.0,
          duration: Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  void sortByAmountHightoLow() {
    setState(() {
      if (filteredItems.isNotEmpty) {
        filteredItems.sort((a, b) => b.amount.compareTo(a.amount));
        _scrollController.animateTo(
          0.0,
          duration: Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
      }
    });
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

  Future<void> generateAndSharePDF_Rest() async {
    final font = pw.Font.ttf(
      await rootBundle.load("assets/fonts/NotoSans.ttf"),
    );

    final pdf = pw.Document();

    final companyName = company!;
    final reportname = '$type Summary';
    final partyname = ledger;

    final headersRow3 = [
      'Vch No',
      'Vch Date',
      'Post Dated',
      'Optional',
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
          item.vchno,
          convertDateFormat(item.vchdate),
          item.ispostdated,
          item.isoptional,
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
        cellPadding: pw.EdgeInsets.all(5),
        columnWidths: {
          0: pw.FractionColumnWidth(0.25),
          1: pw.FractionColumnWidth(0.25),
          2: pw.FractionColumnWidth(0.25),
          3: pw.FractionColumnWidth(0.25),
          4: pw.FractionColumnWidth(0.25),
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
    final tempFilePath = '${tempDir.path}/$type.pdf';
    final file = File(tempFilePath);
    await file.writeAsBytes(pdfData);

    await Share.shareXFiles([
      XFile(tempFilePath),
    ], text: 'Sharing $type Report of $company');
  }

  Future<void> generateAndShareCSV_Rest() async {
    final List<List<dynamic>> csvData = [];
    final headersRow = [
      'Vch No',
      'Vch Date',
      'Post Dated',
      'Optional',
      'Amount',
    ];
    csvData.add(headersRow);

    for (final item in item_list) {
      final rowData = [
        item.vchno,
        convertDateFormat(item.vchdate),
        item.ispostdated,
        item.isoptional,
        formatAmount(item.amount.toString()),
      ];
      csvData.add(rowData);
    }

    final csvString = const ListToCsvConverter().convert(csvData);

    final tempDir = await Directory.systemTemp.createTemp();
    final tempFilePath = '${tempDir.path}/$type.csv';
    final file = File(tempFilePath);
    await file.writeAsString(csvString);

    await Share.shareXFiles([
      XFile(tempFilePath),
    ], text: 'Sharing $type Report of $company');
  }

  String formatVchNo(String vchno) {
    if (vchno == "null") {
      vchno = "No Voucher No.";
    }

    return vchno;
  }

  String convertDateFormat(String dateStr) {
    // Parse the input date string
    DateTime date = DateTime.parse(dateStr);

    // Format the date to the desired output format
    String formattedDate = DateFormat("dd-MMM-yyyy").format(date);

    return formattedDate;
  }

  Future<void> fetchData(
    final String ledger,
    final String startdate,
    final String enddate,
    final String vchtype,
  ) async {
    setState(() {
      _isLoading = true;
      _isListVisible = true;
      isSortVisible = false;
    });

    item_list.clear();
    filteredItems.clear();

    try {
      final url = Uri.parse(HttpURL!);

      Map<String, String> headers = {
        'Authorization': 'Bearer $token',
        "Content-Type": "application/json",
      };

      var body = jsonEncode({
        'startdate': startdate,
        'enddate': enddate,
        'ledger': ledger,
        'vchtypes': vchtype,
      });

      final response = await http.post(url, body: body, headers: headers);

      if (response.statusCode == 200) {
        print(response.body);
        final List<dynamic> values_list = jsonDecode(response.body);
        if (values_list != null) {
          isVisibleNoDataFound = false;

          item_list.addAll(
            values_list.map((json) => Data.fromJson(json)).toList(),
          );
          filteredItems = item_list;
        } else {
          throw Exception('Failed to fetch data');
        }
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

    setState(() {
      hostname = prefs.getString('hostname');
      company = prefs.getString('company_name');
      company_lowercase = company!.replaceAll(' ', '').toLowerCase();
      serial_no = prefs.getString('serial_no');
      username = prefs.getString('username');
      token = prefs.getString('token')!;
    });

    try {
      selectedSortOption = prefs.getString('sort')!;
      if (selectedSortOption == null || selectedSortOption == 'null') {
        selectedSortOption = 'Default';
      }
      if (!itemList.contains(selectedSortOption)) {
        selectedSortOption = 'Default';
      }
    } catch (e) {
      selectedSortOption = 'Default';
    }

    HttpURL = '$hostname/api/ledger/getTotal/$company_lowercase/$serial_no';

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

    fetchData(ledger, startDateString, endDateString, type);
  }

  @override
  void initState() {
    super.initState();
    _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
    _initSharedPreferences();
  }

  @override
  void dispose() {
    _scrollFabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: const AppBottomNav(activeTab: AppBottomNavTab.party),
      key: _scaffoldKey,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,

      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: AppBar(
          backgroundColor: app_color,
          elevation: 6,
          automaticallyImplyLeading: false,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () {
              AppNavigation.backOrDashboard(context);
            },
          ),
          centerTitle: true,
          title: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth:
                  MediaQuery.of(context).size.width - (kToolbarHeight * 5.2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ledger,
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  type,
                  style: GoogleFonts.poppins(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.normal,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
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
              icon: Icon(Icons.search, color: Colors.white, size: 30),
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
                        onTap: () {
                          Navigator.pop(context);
                          if (!item_list.isEmpty) {
                            generateAndSharePDF_Rest();
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

                          if (!item_list.isEmpty) {
                            generateAndShareCSV_Rest();
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
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 20,
                        spreadRadius: 2,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Total Value
                      Center(
                        child: Text(
                          total,
                          style: GoogleFonts.poppins(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: Theme.of(context).colorScheme.onSurface,
                            letterSpacing: 0,
                          ),
                        ),
                      ),

                      const SizedBox(height: 8),

                      // Date Range pill
                      Center(
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

              // Content Section
              SliverToBoxAdapter(
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
                      // Search bar
                      if (_isSearchViewVisible) ...[
                        Padding(
                          padding: const EdgeInsets.only(
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
                                if (value.isEmpty) {
                                  setState(() {
                                    filteredItems = item_list;
                                  });
                                } else {
                                  setState(() {
                                    filteredItems = item_list.where((item) {
                                      final query = value.toLowerCase();
                                      return item.vchno.toLowerCase().contains(
                                        query,
                                      );
                                    }).toList();
                                  });
                                }
                              },
                              style: GoogleFonts.poppins(
                                fontSize: 15,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                              decoration: InputDecoration(
                                hintText: 'Search by Voucher No...',
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
                                contentPadding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                  horizontal: 16,
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(18),
                                  borderSide: BorderSide(
                                    color: Theme.of(context).dividerColor,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(18),
                                  borderSide: const BorderSide(
                                    color: app_color,
                                    width: 1.5,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],

                      // No data found
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

                      // List
                      Visibility(
                        visible: _isListVisible,
                        child: ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          itemCount: filteredItems.length,
                          itemBuilder: (context, index) {
                            final card = filteredItems[index];

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
                                    offset: const Offset(0, 5),
                                  ),
                                ],
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 16,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // 🔹 Header Row (Voucher No + Date Chip)
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          width: 36,
                                          height: 36,
                                          decoration: const BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: [
                                                Color(0xFF7F7FD5),
                                                Color(0xFF86A8E7),
                                              ],
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

                                        // Voucher Number
                                        Expanded(
                                          child: Text(
                                            formatVchNo(card.vchno),
                                            style: GoogleFonts.poppins(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w700,
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.onSurface,
                                            ),
                                          ),
                                        ),

                                        // 📅 Date Chip (colored background)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: [
                                                Colors.orange.withOpacity(0.03),
                                                Colors.orange.withOpacity(0.1),
                                              ],
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.orange
                                                    .withOpacity(0.08),
                                                blurRadius: 6,
                                                offset: const Offset(0, 3),
                                              ),
                                            ],
                                          ),
                                          child: Row(
                                            children: [
                                              const Icon(
                                                Icons.calendar_today_outlined,
                                                size: 13,
                                                color: Colors.orange,
                                              ),
                                              const SizedBox(width: 5),
                                              Text(
                                                convertDateFormat(card.vchdate),
                                                style: GoogleFonts.poppins(
                                                  fontSize: 12.5,
                                                  fontWeight: FontWeight.w500,
                                                  color: Colors.orange,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),

                                    const SizedBox(height: 14),

                                    // 💰 Amount Chip (white background, colored border + text)
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 8,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Theme.of(context).cardColor,
                                          border: Border.all(
                                            color: Colors.deepOrangeAccent
                                                .withOpacity(0.8),
                                            width: 1.4,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.deepOrange
                                                  .withOpacity(0.08),
                                              blurRadius: 4,
                                              offset: const Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize
                                              .min, // ✅ only as wide as text
                                          children: [
                                            Flexible(
                                              child: Text(
                                                '${formatAmount(card.amount.toString())}',
                                                softWrap:
                                                    true, // ✅ allows text to wrap to next line
                                                overflow: TextOverflow
                                                    .visible, // ✅ ensures nothing gets cut off
                                                textAlign: TextAlign
                                                    .end, // or TextAlign.center if needed
                                                style: GoogleFonts.poppins(
                                                  fontSize: 13.5,
                                                  fontWeight: FontWeight.w600,
                                                  color:
                                                      Colors.deepOrangeAccent,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),

                                    const SizedBox(height: 12),

                                    // 🔹 Status Chips (Optional / Post Dated)
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 6,
                                      children: [
                                        if (card.ispostdated == "1" &&
                                            isVisiblePostDated)
                                          _buildStatusChip(
                                            context: context,
                                            label: 'Post Dated',
                                            colors: const [
                                              Color(0xFF3A7BD5),
                                              Color(0xFF00D2FF),
                                            ],
                                          ),
                                        if (card.isoptional == "1" &&
                                            isVisibleOptional)
                                          _buildStatusChip(
                                            context: context,
                                            label: 'Optional',
                                            colors: const [
                                              Color(0xFFFFB347),
                                              Color(0xFFFFCC33),
                                            ],
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // Sort Button
          if (isSortVisible)
            Positioned(
              bottom: 28,
              left: 0,
              right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: () {
                    _showSelectionWindow(context);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 15,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [app_color, app_color],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(50),
                      boxShadow: [
                        BoxShadow(
                          color: app_color.withOpacity(0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.tune_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Sort',
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 15.5,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // Loading Indicator
          Visibility(
            visible: _isLoading,
            child: Center(child: AppLogoLoader()),
          ),
          ScrollFab(controller: _scrollFabController),
        ],
      ),
    );
  }
}

Widget _buildStatusChip({
  required BuildContext context,
  required String label,
  required List<Color> colors,
}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: Theme.of(context).brightness == Brightness.dark
          ? Theme.of(context).colorScheme.surfaceContainerHighest
          : const Color(0xFFF7F8FA),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: colors.last.withOpacity(0.3)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: colors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Icon(
            Icons.check_circle_outline,
            size: 12,
            color: Colors.white,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ],
    ),
  );
}
