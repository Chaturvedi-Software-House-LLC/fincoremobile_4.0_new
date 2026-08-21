import 'dart:convert';
import 'widgets/scroll_fab.dart';
import 'package:FincoreGo/PartyClickedSalePurcOrderClicked.dart';
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
import 'package:FincoreGo/widgets/app_bottom_nav.dart';
import 'package:FincoreGo/widgets/app_navigation.dart';

class Data {
  final String item;
  final String totalQty;
  final double totalAmount;

  Data({required this.item, required this.totalQty, required this.totalAmount});

  factory Data.fromJson(Map<String, dynamic> json) {
    return Data(
      item: json['item'].toString(),
      totalQty: json['totalQty'].toString(),
      totalAmount: double.tryParse(json['totalAmount'].toString()) ?? 0,
    );
  }
}

class Data_Top {
  final String Partyledger;

  Data_Top({required this.Partyledger});

  factory Data_Top.fromJson(Map<String, dynamic> json) {
    return Data_Top(Partyledger: json['Partyledger'].toString());
  }
}

class PartyClickedSalePurcOrder extends StatefulWidget {
  final String startdate_string, enddate_string, type, ledger, vchtype;

  const PartyClickedSalePurcOrder({
    required this.startdate_string,
    required this.enddate_string,
    required this.type,
    required this.ledger,
    required this.vchtype,
  });
  @override
  _PartyClickedSalePurcOrderPageState createState() =>
      _PartyClickedSalePurcOrderPageState(
        startDateString: startdate_string,
        endDateString: enddate_string,
        type: type,
        ledger: ledger,
        vchtype: vchtype,
      );
}

class _PartyClickedSalePurcOrderPageState
    extends State<PartyClickedSalePurcOrder>
    with TickerProviderStateMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ScrollController _scrollFabController = ScrollController();
  String startDateString = "",
      endDateString = "",
      type = "",
      ledger = "",
      total = "",
      vchtype = "";

  int counter = 0;
  bool isSortVisible = false;
  double total_double = 0;

  String selectedSortOption = '', token = '';

  String total_main = "0";

  List<Data_Top> dropdownItems = [];

  final List<String> itemList = [
    'Default',
    'A->Z',
    'Z->A',
    'Amount High to Low',
    'Amount Low to High',
  ];

  List<Data> filteredItems =
      []; // Initialize an empty list to hold the filtered items

  _PartyClickedSalePurcOrderPageState({
    required this.startDateString,
    required this.endDateString,
    required this.type,
    required this.ledger,
    required this.vchtype,
  });

  String? SecuritybtnAcessHolder;
  bool isDashEnable = true,
      isRolesEnable = true,
      isUserEnable = true,
      isRolesVisible = true,
      isUserVisible = true,
      _isSearchViewVisible = false,
      _isListVisible = false;

  String email = "";
  String name = "";

  Data_Top? selectedTopValue;

  ScrollController _scrollController = ScrollController();

  TextEditingController searchController = TextEditingController();

  bool isVisibleNoDataFound = false;

  late GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey;
  late SharedPreferences prefs;
  String? datetype;

  late String? startdate_pref, enddate_pref;

  String HttpURL = "", HttpURL_Top = "";

  String? hostname = "",
      company = "",
      serial_no = "",
      company_lowercase = "",
      username = "";
  List<dynamic> myData = [];
  bool _isLoading = false;

  List<Data> item_list = [];

  void _showSelectionWindow(BuildContext context) {
    final List<IconData> icons = [
      Icons.sort_rounded,
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
                              ? Icon(Icons.check, color: app_color)
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
        filteredItems.sort((a, b) => a.item.compareTo(b.item));
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
        filteredItems.sort((a, b) => b.item.compareTo(a.item));
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
        if (vchtype == 'sales') {
          filteredItems.sort((a, b) => a.totalAmount.compareTo(b.totalAmount));
          _scrollController.animateTo(
            0.0,
            duration: Duration(milliseconds: 500),
            curve: Curves.easeInOut,
          );
        } else if (vchtype == 'purchase') {
          filteredItems.sort((a, b) => b.totalAmount.compareTo(a.totalAmount));
          _scrollController.animateTo(
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
        if (vchtype == 'sales') {
          filteredItems.sort((a, b) => b.totalAmount.compareTo(a.totalAmount));
          _scrollController.animateTo(
            0.0,
            duration: Duration(milliseconds: 500),
            curve: Curves.easeInOut,
          );
        } else if (vchtype == 'purchase') {
          filteredItems.sort((a, b) => a.totalAmount.compareTo(b.totalAmount));
          _scrollController.animateTo(
            0.0,
            duration: Duration(milliseconds: 500),
            curve: Curves.easeInOut,
          );
        }
      }
    });
  }

  Future<void> generateAndSharePDF_SalePurc() async {
    final font = pw.Font.ttf(
      await rootBundle.load("assets/fonts/NotoSans.ttf"),
    );
    final pdf = pw.Document();

    String typee = '';
    if (type == 'salesorder') {
      typee = 'Pending Sales Order';
    } else if (type == 'purcorder') {
      typee = 'Pending Purchase Order';
    }

    final companyName = company!;
    final reportname = '$typee Summary';
    final partyname = selectedTopValue!.Partyledger;

    final headersRow3 = ['Item', 'Pending Qty', 'Amount'];

    final itemsPerPage = 10;
    final pageCount = (item_list.length / itemsPerPage).ceil();

    for (int pageNumber = 0; pageNumber < pageCount; pageNumber++) {
      final startIndex = pageNumber * itemsPerPage;
      final endIndex = (pageNumber + 1) * itemsPerPage > item_list.length
          ? item_list.length
          : (pageNumber + 1) * itemsPerPage;

      final itemsSubset = item_list.sublist(startIndex, endIndex);

      final tableSubsetRows = itemsSubset.map((item) {
        return [
          item.item,
          item.totalQty,
          formatAmount(item.totalAmount.toString()),
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
                      'As on:',
                      style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.normal,
                      ),
                    ),
                    pw.SizedBox(width: 5),
                    pw.Text(
                      convertDateFormat(endDateString),
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
                      'Party:',
                      style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(width: 5),
                    pw.Text(
                      partyname,
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
            );
          },
        ),
      );
    }

    final pdfData = await pdf.save();
    final tempDir = await getTemporaryDirectory();
    final tempFilePath = '${tempDir.path}/PendingSales_PurchaseOrder.pdf';
    final file = File(tempFilePath);
    await file.writeAsBytes(pdfData);

    // ✅ Updated share method
    await Share.shareXFiles([
      XFile(tempFilePath),
    ], text: 'Sharing $typee Report of $company');
  }

  Future<void> generateAndShareCSV_SalePurc() async {
    String typee = '';
    if (type == 'salesorder') {
      typee = 'Pending Sales Order';
    } else if (type == 'purcorder') {
      typee = 'Pending Purchase Order';
    }

    final List<List<dynamic>> csvData = [];
    final headersRow = ['Item', 'Pending Qty', 'Amount'];
    csvData.add(headersRow);

    for (final item in item_list) {
      final rowData = [
        item.item,
        item.totalQty,
        formatAmount(item.totalAmount.toString()),
      ];
      csvData.add(rowData);
    }

    final csvString = const ListToCsvConverter().convert(csvData);

    final tempDir = await Directory.systemTemp.createTemp();
    final tempFilePath = '${tempDir.path}/PendingSales_PurchaseOrder.csv';
    final file = File(tempFilePath);
    await file.writeAsString(csvString);

    // ✅ Updated share method
    await Share.shareXFiles([
      XFile(tempFilePath),
    ], text: 'Sharing $typee Report of $company');
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

  Future<void> fetchData_Top(
    final String ordervchs,
    final String typee,
    final String groupby,
    final String orderby,
  ) async {
    setState(() {
      _isLoading = true;
    });

    /*print (ordervchs + typee);*/

    try {
      final url = Uri.parse(HttpURL_Top!);

      Map<String, String> headers = {
        'Authorization': 'Bearer $token',
        "Content-Type": "application/json",
      };

      var body = jsonEncode({
        'ordervchs': ordervchs,
        'vchtypes': typee,
        'groupby': groupby,
        'orderby': orderby,
      });

      final response = await http.post(url, body: body, headers: headers);

      if (response.statusCode == 200) {
        print('response -> ${response.body}');

        final parsed = jsonDecode(utf8.decode(response.bodyBytes)).cast<Map<String, dynamic>>();

        final List<Data_Top> values_list = parsed
            .map<Data_Top>((json) => Data_Top.fromJson(json))
            .toList();
        if (values_list != null) {
          String desiredValue = ledger; // Replace with your desired value
          Data_Top? selectedValue;
          try {
            selectedValue = values_list.firstWhere(
              (item) => item.Partyledger == desiredValue,
            );
          } catch (e) {
            selectedValue = null;
          }
          // dropdownItems and selectedTopValue must update together in the
          // same setState - assigning selectedTopValue outside setState (as
          // this used to) doesn't trigger a rebuild, so the AppBar's
          // DropdownButton kept rendering its stale (often null) value
          // until some unrelated rebuild happened to occur later. Release
          // builds batch/skip more of those incidental rebuilds than debug
          // does, which is why this only showed as a blank dropdown title
          // in release.
          setState(() {
            dropdownItems = values_list;
            selectedTopValue = selectedValue;
          });
          fetchData(
            vchtype,
            selectedTopValue?.Partyledger ?? '',
            type,
            endDateString,
            "item",
            "true",
          );
        } else {
          throw Exception('Failed to fetch data');
        }
      }
    } catch (e) {
      print(e);
    }
  }

  Future<void> fetchData(
    final String vchtype,
    final String partyname,
    final String type,
    final String enddate,
    final String groupby,
    final String select,
  ) async {
    setState(() {
      _isLoading = true;
      _isListVisible = true;
      isSortVisible = false;
      isVisibleNoDataFound = false;
    });

    item_list.clear();
    filteredItems.clear();

    try {
      final url = Uri.parse(HttpURL_Top!);

      Map<String, String> headers = {
        'Authorization': 'Bearer $token',
        "Content-Type": "application/json",
      };

      var body = jsonEncode({
        'vchtypes': vchtype,
        'ledger': partyname,
        'ordervchs': type,
        'enddate': enddate,
        'groupby': groupby,
        'select': select,
        'orderby': 'item',
      });

      final response = await http.post(url, body: body, headers: headers);

      if (response.statusCode == 200) {
        final List<dynamic> values_list = jsonDecode(utf8.decode(response.bodyBytes));
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
        isVisibleNoDataFound = false;

        switch (selectedSortOption) {
          case 'Default':
            sortByDefault(); // Call the sorting function
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
      token = prefs.getString('token') ?? '';  // absent for tally-oauth-only sessions (Phase 6) - was a crashing force-unwrap
      /*selectedTopValue = dropdownItems.first;
      filteredItems= item_list;
      isVisibleNoDataFound =false;
      _isListVisible = true;*/
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
    HttpURL_Top =
        '$hostname/api/ledger/getOrderSummary/$company_lowercase/$serial_no';

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

    fetchData_Top(type, vchtype, "Partyledger", "Partyledger");

    /*fetchData(ledger,startDateString, endDateString, type);*/
  }

  String formatTypeTitle(String type) {
    final Map<String, String> typeMappings = {
      'salesorder': 'Pending Sales Order',
      'purcorder': 'Pending Purchase Order',
      // add other known cases here
    };

    return typeMappings[type.toLowerCase()] ?? type;
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
        preferredSize: const Size.fromHeight(56),
        child: AppBar(
          backgroundColor: app_color,
          elevation: 2,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
          ),
          automaticallyImplyLeading: false,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: Colors.white, size: 20),
            onPressed: () {
              AppNavigation.backOrDashboard(context);
            },
          ),
          centerTitle: false,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min, // prevent forcing full height
            children: [
                  SizedBox(
                    height: 26,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DropdownButton<Data_Top>(
                        value: selectedTopValue,
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 15,
                        ),
                        dropdownColor: Colors.grey[800],
                        icon: Icon(Icons.arrow_drop_down, color: Colors.white, size: 20),
                        underline: SizedBox(),
                        onChanged: (newValue) {
                          setState(() {
                            selectedTopValue = newValue!;
                            fetchData(
                              vchtype,
                              newValue?.Partyledger ?? '',
                              type,
                              endDateString,
                              "item",
                              "true",
                            );
                          });
                        },
                        items: dropdownItems.map((Data_Top value) {
                          return DropdownMenuItem<Data_Top>(
                            value: value,
                            child: Text(
                              value.Partyledger,
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),

                  Text(
                    formatTypeTitle(type),
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
                            generateAndSharePDF_SalePurc();
                          }
                        },
                        child: Row(
                          children: [
                            Icon(
                              Icons.picture_as_pdf,
                              size: 16,
                              color: app_color,
                            ),
                            SizedBox(width: 5),

                            Text(
                              'Share as PDF',
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.normal,
                                color: app_color,
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
                            generateAndShareCSV_SalePurc();
                          }
                        },
                        child: Row(
                          children: [
                            Icon(
                              Icons.add_chart_outlined,
                              size: 16,
                              color: app_color,
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
                  width: double.infinity,
                  color: Theme.of(context).scaffoldBackgroundColor,
                  child: Column(
                    children: [
                      Container(
                        color: Theme.of(context).scaffoldBackgroundColor,
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
                                      onChanged: (value) {
                                        if (value.isEmpty) {
                                          setState(() {
                                            filteredItems = item_list;
                                          });
                                        } else {
                                          setState(() {
                                            filteredItems = item_list.where((
                                              item,
                                            ) {
                                              // Filter items based on the search query and the ledgerName property
                                              final query = value.toLowerCase();
                                              return item.item
                                                  .toLowerCase()
                                                  .contains(query);
                                            }).toList();
                                          });
                                        }
                                      },
                                      style: GoogleFonts.poppins(
                                        fontSize: 13.5,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurface,
                                      ),
                                      decoration: InputDecoration(
                                        isDense: true,
                                        hintText: 'Search...',
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
                                                ? Colors.white.withOpacity(
                                                    0.06,
                                                  )
                                                : Colors.grey.shade100,
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              vertical: 8,
                                              horizontal: 12,
                                            ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            24,
                                          ),
                                          borderSide: BorderSide.none,
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            24,
                                          ),
                                          borderSide: BorderSide(
                                            color: app_color.withOpacity(0.6),
                                            width: 1.4,
                                          ),
                                        ),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            24,
                                          ),
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
                      ],
                    ),
                  ),
                ),

              // 📋 Order list - a real sliver (SliverList) so the
              // CustomScrollView only builds cards near the viewport; the
              // previous shrinkWrap ListView.builder forced eager layout of
              // every order up front, which is what caused the same
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

                                      return GestureDetector(
                                        onTap: () {
                                          if (selectedTopValue == null) return;
                                          String item = card.item;
                                          String party =
                                              selectedTopValue!.Partyledger;

                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) =>
                                                  PartyClickedSalePurcOrderClicked(
                                                    ledger: party,
                                                    startdate_string:
                                                        startDateString,
                                                    enddate_string:
                                                        endDateString,
                                                    type: type,
                                                    vchtype: vchtype,
                                                    item: item,
                                                    dropdownItems: item_list,
                                                  ),
                                            ),
                                          );
                                        },
                                        child: Container(
                                          margin: const EdgeInsets.only(
                                            bottom: 7,
                                          ),
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                            color: Theme.of(
                                              context,
                                            ).cardColor.withOpacity(0.95),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withOpacity(
                                                  0.04,
                                                ),
                                                blurRadius: 10,
                                                spreadRadius: 1,
                                                offset: const Offset(0, 4),
                                              ),
                                            ],
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 16,
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              // Item Name
                                              Row(
                                                children: [
                                                  Icon(
                                                    Icons.widgets_outlined,
                                                    size: 18,
                                                    color: Colors.teal,
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: Text(
                                                      card.item,
                                                      style:
                                                          GoogleFonts.poppins(
                                                            fontSize: 15,
                                                            fontWeight:
                                                                FontWeight.w600,
                                                            color:
                                                                Theme.of(
                                                                      context,
                                                                    )
                                                                    .colorScheme
                                                                    .onSurface,
                                                            letterSpacing: 0,
                                                          ),
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ],
                                              ),

                                              const SizedBox(height: 12),

                                              // Subtle Divider
                                              Container(
                                                height: 1,
                                                color: Colors.grey.withOpacity(
                                                  0.12,
                                                ),
                                              ),

                                              const SizedBox(height: 12),

                                              // Pending Qty & Pending Amount - Modern pills
                                              // Pending Qty & Pending Amount - responsive wrap pills
                                              Wrap(
                                                spacing:
                                                    12, // space between pills horizontally
                                                runSpacing:
                                                    10, // space between rows if it wraps
                                                children: [
                                                  // Qty Pill
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 12,
                                                          vertical: 10,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: Colors.orange
                                                          .withOpacity(
                                                            Theme.of(
                                                                      context,
                                                                    ).brightness ==
                                                                    Brightness
                                                                        .dark
                                                                ? 0.22
                                                                : 0.1,
                                                          ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            24,
                                                          ),
                                                      border: Border.all(
                                                        color: Colors
                                                            .orange
                                                            .shade50,
                                                      ),
                                                    ),
                                                    child: Row(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        Icon(
                                                          Icons
                                                              .inventory_2_rounded,
                                                          size: 16,
                                                          color: Colors.orange,
                                                        ),
                                                        const SizedBox(
                                                          width: 6,
                                                        ),
                                                        Text(
                                                          'Qty: ${card.totalQty}',
                                                          style:
                                                              GoogleFonts.poppins(
                                                                fontSize: 13,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w500,
                                                                color: Colors
                                                                    .orange
                                                                    .shade800,
                                                              ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),

                                                  // Amount Pill — no icon, as per your last request
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 12,
                                                          vertical: 10,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: Colors.green
                                                          .withOpacity(
                                                            Theme.of(
                                                                      context,
                                                                    ).brightness ==
                                                                    Brightness
                                                                        .dark
                                                                ? 0.22
                                                                : 0.1,
                                                          ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            24,
                                                          ),
                                                      border: Border.all(
                                                        color: Colors
                                                            .green
                                                            .shade50,
                                                      ),
                                                    ),
                                                    child: formatAmountRich(
                                                      card.totalAmount
                                                          .toString(),
                                                      style:
                                                          GoogleFonts.poppins(
                                                            fontSize: 13,
                                                            fontWeight:
                                                                FontWeight.w500,
                                                            color: Colors
                                                                .green
                                                                .shade800,
                                                          ),
                                                    ),
                                                  ),
                                                ],
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
