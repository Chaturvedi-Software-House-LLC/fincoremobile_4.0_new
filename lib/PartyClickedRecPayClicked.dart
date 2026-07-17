import 'dart:convert';
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
import 'widgets/scroll_fab.dart';

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
      outstanding: double.tryParse(json['outstanding'].toString()) ?? 0,
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

  const PartyTotalClickedRecPayClicked({
    required this.startdate_string,
    required this.enddate_string,
    required this.type,
    required this.ledger,
    required this.total,
    required this.variable,
    required this.variabletype,
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

  String selectedSortOption = '', token = '';

  bool isSortVisible = false;
  ScrollController _scrollController = ScrollController();
  final ScrollController _scrollFabController = ScrollController();
  late String currencysymbol = '';

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

  String HttpURL_CreditLimit = "", HttpURL = "";

  String? hostname = "",
      company = "",
      serial_no = "",
      company_lowercase = "",
      username = "";
  List<dynamic> myData = [];
  bool _isLoading = false;

  List<Data> item_list = [];
  List<Data> filteredItems = []; // default initialization

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
        filteredItems.sort((a, b) => a.billno.compareTo(b.billno));
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
        filteredItems.sort((a, b) => b.billno.compareTo(a.billno));
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
        filteredItems.sort((a, b) => a.billdate.compareTo(b.billdate));
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
        filteredItems.sort((a, b) => b.billdate.compareTo(a.billdate));
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
        if (type == "Receivable") {
          filteredItems.sort((a, b) => b.outstanding.compareTo(a.outstanding));
          _scrollController.animateTo(
            0.0,
            duration: Duration(milliseconds: 500),
            curve: Curves.easeInOut,
          );
        } else {
          filteredItems.sort((a, b) => a.outstanding.compareTo(b.outstanding));
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
        if (type == "Receivable") {
          filteredItems.sort((a, b) => a.outstanding.compareTo(b.outstanding));
          _scrollController.animateTo(
            0.0,
            duration: Duration(milliseconds: 500),
            curve: Curves.easeInOut,
          );
        } else {
          filteredItems.sort((a, b) => b.outstanding.compareTo(a.outstanding));
          _scrollController.animateTo(
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

  Future<void> fetchCreditlimit(final String ledger) async {
    setState(() {
      _isLoading = true;
    });

    try {
      final url = Uri.parse(HttpURL_CreditLimit);
      Map<String, String> headers = {
        'Authorization': 'Bearer $token',
        "Content-Type": "application/json",
      };

      var body = jsonEncode({'ledger': ledger});

      final response = await http.post(url, body: body, headers: headers);

      if (response.statusCode == 200) {
        final List<dynamic> values_list = jsonDecode(response.body);
        if (values_list != null) {
          for (var item in values_list) {
            String creditlimitt = item['creditlimit'].toString();
            String creditperiodd = item['creditPeriod'].toString();

            if (creditlimitt == 'null') {
              creditlimitt = "0";
            }
            if (creditperiodd == "null") {
              creditperiod = "0";
              creditlimit = creditlimitt;
            } else {
              if (creditperiodd.contains("Days")) {
                setState(() {
                  isVisibleDays = false;
                });
              } else {
                setState(() {
                  isVisibleDays = true;
                });
              }
              creditlimit = creditlimitt;

              creditperiod = creditperiodd;
            }
          }
        } else {
          throw Exception('Failed to fetch data');
        }
      }
    } catch (e) {
      print(e);
    }
  }

  Future<void> fetchData(
    final String orderby,
    final String ledger,
    final String groupby,
    final String enddate,
    final String variabletype,
    final String isDebit,
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
        'billdate': enddate,
        'ledger': ledger,
        'isDebit': isDebit,
        'orderby': orderby,
        'groupby': groupby,
        'overdue': variabletype,
      });

      final response = await http.post(url, body: body, headers: headers);

      if (response.statusCode == 200) {
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

    try {
      selectedSortOption = prefs.getString('sort')!;
      if (selectedSortOption == null || selectedSortOption == 'null') {
        selectedSortOption = 'Default';
      }
    } catch (e) {
      selectedSortOption = 'Default';
    }

    HttpURL_CreditLimit =
        '$hostname/api/ledger/getLedger/$company_lowercase/$serial_no';

    HttpURL =
        '$hostname/api/ledger/getOutstandingList/$company_lowercase/$serial_no';

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

    fetchCreditlimit(ledger);

    String variable_type_2 = variabletype;
    if (variable_type_2 == "All") {
      variable_type_2 = "";
    } else {
      variable_type_2 = variabletype;
    }
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
    fetchData(
      "billno",
      ledger,
      "billno",
      endDateString,
      variable_type_2,
      isDebit,
    );
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
                            generateAndSharePDF_RecPay();
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
                            generateAndShareCSV_RecPay();
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
                    vertical: 12,
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
                    crossAxisAlignment: CrossAxisAlignment.center,
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
                      const SizedBox(height: 12),

                      // As of + Overdue + Credit Limit row (pill style)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest.withOpacity(
                                Theme.of(context).brightness == Brightness.dark
                                    ? 0.85
                                    : 0.35,
                              ),
                              Theme.of(context).cardColor.withOpacity(
                                Theme.of(context).brightness == Brightness.dark
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
                                      fontSize: 14,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface,
                                    ),
                                  ),
                                  Text(
                                    enddate_text,
                                    style: GoogleFonts.poppins(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface,
                                    ),
                                  ),
                                  Text(
                                    ' | ',
                                    style: GoogleFonts.poppins(
                                      fontWeight: FontWeight.w500,
                                      fontSize: 14,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  Text(
                                    overdue_value,
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

                              const SizedBox(width: 16),

                              // Right part: Credit Limit + Period
                              Row(
                                children: [
                                  Text(
                                    'Credit Limit: ',
                                    style: GoogleFonts.poppins(
                                      fontWeight: FontWeight.w500,
                                      fontSize: 14,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface,
                                    ),
                                  ),
                                  Text(
                                    creditlimit,
                                    style: GoogleFonts.poppins(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface,
                                    ),
                                  ),
                                  Text(
                                    ' / ',
                                    style: GoogleFonts.poppins(
                                      fontWeight: FontWeight.w500,
                                      fontSize: 14,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  Text(
                                    creditperiod,
                                    style: GoogleFonts.poppins(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
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
                                        fontSize: 14,
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
                                      // Filter items based on the search query and the ledgerName property
                                      final query = value.toLowerCase();
                                      return item.billno.toLowerCase().contains(
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
                                hintText: 'Search...',
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
                                              child: Text(
                                                '${formatAmount(card.outstanding.toString())}',
                                                softWrap: true,
                                                maxLines: null,
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
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

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

          Visibility(
            visible: _isLoading,
            child: Center(child: AppLogoLoader()),
          ),

          ScrollFab(controller: _scrollFabController),
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
