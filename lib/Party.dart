import 'dart:convert';
import 'dart:ui';
import 'package:FincoreGo/Dashboard.dart';
import 'package:FincoreGo/constants.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'PartyClicked.dart';
import 'SerialSelect.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:FincoreGo/widgets/app_bottom_nav.dart';
import 'package:FincoreGo/widgets/app_navigation.dart';
import 'widgets/scroll_fab.dart';

class party {
  final String partyname;
  final String alias;
  final String mobile;
  final String email;
  final String maxdate;

  party({
    required this.partyname,
    required this.alias,
    required this.mobile,
    required this.email,
    required this.maxdate,
  });

  factory party.fromJson(Map<String, dynamic> json) {
    return party(
      partyname: json['name'].toString(),
      alias: json['alias'].toString(),
      mobile: json['mobile'].toString(),
      email: json['email'].toString(),
      maxdate: json['maxdate'].toString() ?? "",
    );
  }
}

class Party extends StatefulWidget {
  @override
  _PartyPageState createState() => _PartyPageState();
}

class _PartyPageState extends State<Party> with TickerProviderStateMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ScrollController _scrollFabController = ScrollController();

  bool isClicked_parties = true;

  TextEditingController _inactivedayscontroller = TextEditingController();

  int counter = 0;

  String party_text = "Party";

  List<party> filteredItems_parties =
      []; // Initialize an empty list to hold the filtered items

  String party_count = "0", token = '';

  String? SecuritybtnAcessHolder;

  bool allparties_visibility = true,
      inactiveparties_visibility = true,
      isClicked_allparties = false,
      isClicked_inactiveparties = false;
  bool isDashEnable = true,
      isRolesEnable = true,
      isUserEnable = true,
      isRolesVisible = true,
      isUserVisible = true,
      _isSearchViewVisible = false,
      _isAllList = false;

  String email = "";
  String name = "";

  TextEditingController searchController = TextEditingController();

  bool isVisibleNoDataFound = false;

  String ledgroups =
      "Sundry Debtors, Sundry Creditors, Customers, Suppliers, Creditors, Debtors";

  late GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey;
  late SharedPreferences prefs;

  String? hostname = "",
      company = "",
      serial_no = "",
      company_lowercase = "",
      username = "";
  bool _isLoading = false;

  String? HttpURL_Parent, HttpURL_parties, HttpURL_inactiveparties;

  dynamic _selectedparty = "All Parties";
  List<String> spinner_list = ["All Parties"];

  List<party> parties_list = [];

  String formatEmail(String email) {
    if (email == 'null') {
      email = '-';
    }
    return email;
  }

  String formatcontact(String contact) {
    if (contact == 'null') {
      contact = '-';
    }
    return contact;
  }

  Future<void> generateAndSharePDF_Party() async {
    final font = pw.Font.ttf(
      await rootBundle.load("assets/fonts/NotoSans.ttf"),
    );
    final pdf = pw.Document();

    final companyName = company!;
    final reportname = 'Parties';
    final headersRow3 = ['Party Name', 'Alias', 'Email Address', 'Contact No'];

    final itemsPerPage = 10;
    final pageCount = (filteredItems_parties.length / itemsPerPage).ceil();

    for (int pageNumber = 0; pageNumber < pageCount; pageNumber++) {
      final startIndex = pageNumber * itemsPerPage;
      final endIndex = (pageNumber + 1) * itemsPerPage;
      final itemsSubset = filteredItems_parties.sublist(
        startIndex,
        endIndex > filteredItems_parties.length
            ? filteredItems_parties.length
            : endIndex,
      );

      final tableSubsetRows = itemsSubset.map((item) {
        return [
          item.partyname,
          formatAlias_Report(item.alias),
          formatEmail(item.email),
          formatcontact(item.mobile),
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
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: font),
        cellStyle: pw.TextStyle(fontSize: 12, font: font),
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
    final tempFilePath = '${tempDir.path}/Parties.pdf';
    await File(tempFilePath).writeAsBytes(pdfData);

    await Share.shareXFiles([
      XFile(tempFilePath),
    ], text: 'Sharing Parties Report of $companyName');
  }

  Future<void> generateAndSharePDF_PartyCustom() async {
    final font = pw.Font.ttf(
      await rootBundle.load("assets/fonts/NotoSans.ttf"),
    );
    final pdf = pw.Document();

    final companyName = company!;
    final reportname = 'Parties';
    final parentname = _selectedparty;
    final headersRow3 = ['Party Name', 'Alias', 'Email Address', 'Contact No'];

    final itemsPerPage = 10;
    final pageCount = (filteredItems_parties.length / itemsPerPage).ceil();

    for (int pageNumber = 0; pageNumber < pageCount; pageNumber++) {
      final startIndex = pageNumber * itemsPerPage;
      final endIndex = (pageNumber + 1) * itemsPerPage;
      final itemsSubset = filteredItems_parties.sublist(
        startIndex,
        endIndex > filteredItems_parties.length
            ? filteredItems_parties.length
            : endIndex,
      );

      final tableSubsetRows = itemsSubset.map((item) {
        return [
          item.partyname,
          formatAlias_Report(item.alias),
          formatEmail(item.email),
          formatcontact(item.mobile),
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
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: font),
        cellStyle: pw.TextStyle(fontSize: 12, font: font),
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
                        'Group:',
                        style: pw.TextStyle(
                          fontSize: 16,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(width: 5),
                      pw.Text(parentname, style: pw.TextStyle(fontSize: 16)),
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
    final tempFilePath = '${tempDir.path}/Parties_Custom.pdf';
    await File(tempFilePath).writeAsBytes(pdfData);

    await Share.shareXFiles([
      XFile(tempFilePath),
    ], text: 'Sharing Parties Report of $companyName');
  }

  Future<void> generateAndShareCSV_Party() async {
    final List<List<dynamic>> csvData = [];
    final headersRow = ['Party Name', 'Alias', 'Email Address', 'Contact No'];
    csvData.add(headersRow);

    for (final item in filteredItems_parties) {
      final rowData = [
        item.partyname,
        formatAlias_Report(item.alias),
        formatEmail(item.email),
        formatcontact(item.mobile),
      ];
      csvData.add(rowData);
    }

    final csvString = const ListToCsvConverter().convert(csvData);

    // Save the CSV to a temporary file
    final tempDir = await Directory.systemTemp.createTemp();
    final tempFilePath = '${tempDir.path}/Parties.csv';
    final file = File(tempFilePath);
    await file.writeAsString(csvString);

    // ✅ Share using the latest SharePlus API
    await Share.shareXFiles([
      XFile(tempFilePath),
    ], text: 'Sharing Parties Report of $company');
  }

  String formatAlias_Report(String alias) {
    if (alias == 'null') {
      alias = '-';
    }
    return alias;
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

      var body = jsonEncode({'ledGroups': ledGroups});

      final response = await http.post(url, body: body, headers: headers);

      if (response.statusCode == 200) {
        List<dynamic> data = jsonDecode(response.body);
        for (var item in data) {
          String partyname = item['parent'];
          spinner_list.add(partyname);
        }
        setState(() {
          _selectedparty = spinner_list[0];
        });
        setState(() {
          isClicked_allparties = true;
          isClicked_inactiveparties = false;
        });
        fetchPartyData(_selectedparty);
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      print(e);
    }
  }

  void fetchPartyData(String party) {
    if (party == "All Parties") {
      party = "";
      fetchall_parties(party, ledgroups);
    } else {
      fetchcustom_parties(party, ledgroups);
    }
  }

  void fetchInactivePartyData(String party, String date) {
    if (party == "All Parties") {
      party = "";

      fetchinactiveall_parties(party, date);
    } else {
      fetchinactivecustom_parties(party, date);
    }
  }

  Future<void> fetchall_parties(
    final String parent,
    final String ledGroups,
  ) async {
    setState(() {
      party_count = "0";
      if (int.parse(party_count) < 2) {
        party_text = "Party";
      } else {
        party_text = "Parties";
      }
      _isLoading = true;
      _isAllList = false;
      isClicked_parties = true;
      isVisibleNoDataFound = false;
    });

    filteredItems_parties.clear();
    parties_list.clear();

    try {
      final url = Uri.parse(HttpURL_parties!);
      Map<String, String> headers = {
        'Authorization': 'Bearer $token',
        "Content-Type": "application/json",
      };

      var body = jsonEncode({'parent': parent, 'ledGroups': ledGroups});

      final response = await http.post(url, body: body, headers: headers);

      if (response.statusCode == 200) {
        final List<dynamic> values_list = jsonDecode(response.body);

        if (values_list != null) {
          isVisibleNoDataFound = false;
          parties_list.addAll(
            values_list.map((json) => party.fromJson(json)).toList(),
          );
          filteredItems_parties = parties_list;
          setState(() {
            party_count = filteredItems_parties.length.toString();
            if (int.parse(party_count) < 2) {
              party_text = "Party";
            } else {
              party_text = "Parties";
            }
            _isAllList = true;
            _isLoading = false;
          });
        } else {
          throw Exception('Failed to fetch data');
        }
      }
    } catch (e) {
      setState(() {
        _isAllList = false;
        _isLoading = false;
      });
      print(e);
    }

    setState(() {
      if (parties_list.isEmpty) {
        party_count = "0";
        if (int.parse(party_count) < 2) {
          party_text = "Party";
        } else {
          party_text = "Parties";
        }
        _isAllList = false;
        isVisibleNoDataFound = true;
      }
      _isLoading = false;
    });
  }

  Future<void> fetchcustom_parties(
    final String parent,
    final String ledGroups,
  ) async {
    setState(() {
      party_count = "0";
      if (int.parse(party_count) < 2) {
        party_text = "Party";
      } else {
        party_text = "Parties";
      }
      _isLoading = true;
      _isAllList = false;
      isVisibleNoDataFound = false;
    });

    filteredItems_parties.clear();
    parties_list.clear();

    try {
      final url = Uri.parse(HttpURL_parties!);
      Map<String, String> headers = {
        'Authorization': 'Bearer $token',
        "Content-Type": "application/json",
      };

      var body = jsonEncode({'parent': parent, 'ledGroups': ledGroups});

      final response = await http.post(url, body: body, headers: headers);

      if (response.statusCode == 200) {
        final List<dynamic> values_list = jsonDecode(response.body);

        if (values_list != null) {
          isVisibleNoDataFound = false;

          parties_list.addAll(
            values_list.map((json) => party.fromJson(json)).toList(),
          );
          filteredItems_parties = parties_list;

          setState(() {
            party_count = filteredItems_parties.length.toString();
            if (int.parse(party_count) < 2) {
              party_text = "Party";
            } else {
              party_text = "Parties";
            }
            _isAllList = true;
            _isLoading = false;
          });
        } else {
          throw Exception('Failed to fetch data');
        }
      }
    } catch (e) {
      setState(() {
        _isAllList = false;
        _isLoading = false;
      });
      print(e);
    }

    setState(() {
      if (parties_list.isEmpty) {
        party_count = "0";
        if (int.parse(party_count) < 2) {
          party_text = "Party";
        } else {
          party_text = "Parties";
        }
        _isAllList = false;
        isVisibleNoDataFound = true;
      }
      _isLoading = false;
    });
  }

  Future<void> fetchinactiveall_parties(
    final String parent,
    final String date,
  ) async {
    setState(() {
      party_count = "0";
      _isLoading = true;
      _isAllList = false;
      isClicked_parties = true;
      isVisibleNoDataFound = false;

      filteredItems_parties.clear();
      parties_list.clear();
    });

    try {
      final url = Uri.parse(HttpURL_inactiveparties!);
      Map<String, String> headers = {
        'Authorization': 'Bearer $token',
        "Content-Type": "application/json",
      };

      var body = jsonEncode({
        'parent': parent,
        'date': date,
        'ledGroups': ledgroups,
      });

      final response = await http.post(url, body: body, headers: headers);

      if (response.statusCode == 200) {
        final List<dynamic> values_list = jsonDecode(response.body);

        if (values_list != null) {
          isVisibleNoDataFound = false;
          parties_list.addAll(
            values_list.map((json) => party.fromJson(json)).toList(),
          );

          parties_list.sort((a, b) {
            DateTime dateA = DateTime.parse(a.maxdate);
            DateTime dateB = DateTime.parse(b.maxdate);
            return dateB.compareTo(dateA);
          });

          filteredItems_parties = parties_list;
          setState(() {
            party_count = filteredItems_parties.length.toString();
            if (int.parse(party_count) < 2) {
              party_text = "Party";
            } else {
              party_text = "Parties";
            }
            _isAllList = true;
            _isLoading = false;
          });
        } else {
          throw Exception('Failed to fetch data');
        }
      }
    } catch (e) {
      setState(() {
        _isAllList = false;
        _isLoading = false;
      });

      print(e);
    }
    setState(() {
      if (parties_list.isEmpty) {
        party_count = "0";
        if (int.parse(party_count) < 2) {
          party_text = "Party";
        } else {
          party_text = "Parties";
        }
        _isAllList = false;
        isVisibleNoDataFound = true;
      }
      _isLoading = false;
    });
  }

  Future<void> fetchinactivecustom_parties(
    final String parent,
    final String date,
  ) async {
    setState(() {
      party_count = "0";
      if (int.parse(party_count) < 2) {
        party_text = "Party";
      } else {
        party_text = "Parties";
      }
      _isLoading = true;
      _isAllList = false;
      isVisibleNoDataFound = false;
    });

    filteredItems_parties.clear();
    parties_list.clear();

    try {
      final url = Uri.parse(HttpURL_inactiveparties!);
      Map<String, String> headers = {
        'Authorization': 'Bearer $token',
        "Content-Type": "application/json",
      };

      var body = jsonEncode({
        'parent': parent,
        'date': date,
        'ledGroups': ledgroups,
      });

      final response = await http.post(url, body: body, headers: headers);

      if (response.statusCode == 200) {
        final List<dynamic> values_list = jsonDecode(response.body);

        if (values_list != null) {
          isVisibleNoDataFound = false;

          parties_list.addAll(
            values_list.map((json) => party.fromJson(json)).toList(),
          );

          parties_list.sort((a, b) {
            DateTime dateA = DateTime.parse(a.maxdate);
            DateTime dateB = DateTime.parse(b.maxdate);
            return dateB.compareTo(dateA);
          });

          filteredItems_parties = parties_list;

          setState(() {
            party_count = filteredItems_parties.length.toString();
            if (int.parse(party_count) < 2) {
              party_text = "Party";
            } else {
              party_text = "Parties";
            }
            _isAllList = true;
            _isLoading = false;
          });
        } else {
          throw Exception('Failed to fetch data');
        }
      }
    } catch (e) {
      setState(() {
        _isAllList = false;
        _isLoading = false;
      });
      print(e);
    }

    setState(() {
      if (parties_list.isEmpty) {
        party_count = "0";
        if (int.parse(party_count) < 2) {
          party_text = "Party";
        } else {
          party_text = "Parties";
        }
        _isAllList = false;
        isVisibleNoDataFound = true;
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
      int defaultDays =
          prefs.getInt('inactiveparties_days') ??
          30; // Default to 30 if not found
      _inactivedayscontroller.text = defaultDays.toString();
    });

    HttpURL_Parent =
        '$hostname/api/ledger/getParent/$company_lowercase/$serial_no';
    HttpURL_parties =
        '$hostname/api/ledger/getLedger/$company_lowercase/$serial_no';

    HttpURL_inactiveparties =
        '$hostname/api/ledger/getInactiveLedger/$company_lowercase/$serial_no';

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

                setState(() {
                  counter++;


                  _isSearchViewVisible =!_isSearchViewVisible;

                  if(!_isSearchViewVisible)
                  {
                    searchController.clear();
                    filteredItems_parties = parties_list;
                  }
                  party_count = filteredItems_parties.length.toString();
                  if(int.parse(party_count)<2)
                  {
                    party_text = "Party";
                  }
                  else
                  {
                    party_text="Parties";
                  }
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
                          if (!parties_list.isEmpty) {
                            if (_selectedparty == 'All Parties') {
                              generateAndSharePDF_Party();
                            } else {
                              generateAndSharePDF_PartyCustom();
                            }
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
                              style: TextStyle(
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

                          if (!parties_list.isEmpty) {
                            generateAndShareCSV_Party();
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
                              style: TextStyle(
                                fontWeight: FontWeight.normal,
                                color: app_color,
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
                SliverToBoxAdapter(
                  child: Container(
                    width: MediaQuery.of(context).size.width,
                    margin: const EdgeInsets.only(left: 12, right: 12, top: 12),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 10,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Dropdown
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(context).cardColor,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: Theme.of(context).dividerColor,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black12,
                                blurRadius: 6,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _selectedparty,
                              isExpanded: true,
                              icon: Icon(
                                Icons.keyboard_arrow_down_rounded,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                              dropdownColor: Theme.of(
                                context,
                              ).colorScheme.surface,

                              hint: Text(
                                "Select Party",
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),

                              style: GoogleFonts.poppins(
                                fontSize: 15,
                                color: Theme.of(context).colorScheme.onSurface,
                                fontWeight: FontWeight.w500,
                              ),

                              items: spinner_list.map((String value) {
                                return DropdownMenuItem<String>(
                                  value: value,
                                  child: Container(
                                    width:
                                        double.infinity, // 🔥 prevents overflow
                                    child: Text(
                                      value,
                                      softWrap: true,
                                      maxLines: 2, // 👈 allow wrapping
                                      overflow: TextOverflow.visible,
                                      style: GoogleFonts.poppins(
                                        fontSize: 14,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurface,
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),

                              // 🔥 Clean selected view (collapsed)
                              selectedItemBuilder: (context) {
                                return spinner_list.map((value) {
                                  return Container(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      value,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.poppins(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  );
                                }).toList();
                              },

                              onChanged: (String? newValue) {
                                setState(() {
                                  _selectedparty = newValue;
                                  isClicked_allparties = true;
                                  isClicked_inactiveparties = false;
                                });
                                fetchPartyData(_selectedparty);
                              },
                            ),
                          ),
                        ),

                        const SizedBox(height: 12),

                        // Toggle Buttons
                        Row(
                          children: [
                            if (allparties_visibility)
                              Expanded(
                                child: _buildModernToggle(
                                  icon: Icons.group_sharp,
                                  label: "All Parties",
                                  isActive: isClicked_allparties,
                                  onTap: () {
                                    FocusScope.of(context).unfocus();
                                    setState(() {
                                      isClicked_allparties = true;
                                      isClicked_inactiveparties = false;
                                    });
                                    fetchPartyData(_selectedparty);
                                  },
                                ),
                              ),

                            if (allparties_visibility &&
                                inactiveparties_visibility)
                              const SizedBox(width: 10),

                            if (inactiveparties_visibility)
                              Expanded(
                                child: _buildModernToggle(
                                  icon: Icons.group_off_sharp,
                                  label: "Inactive Parties",
                                  isActive: isClicked_inactiveparties,
                                  onTap: () {
                                    setState(() {
                                      FocusScope.of(context).unfocus();

                                      isClicked_allparties = false;
                                      isClicked_inactiveparties = true;
                                      filteredItems_parties.clear();
                                      parties_list.clear();
                                      party_count = "0";
                                      party_text = int.parse(party_count) < 2
                                          ? "Party"
                                          : "Parties";
                                    });
                                    _showInactiveDialog();
                                  },
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                SliverToBoxAdapter(
                  child: Column(
                    children: [
                      // 🔍 Modern Search Bar
                      Padding(
                        padding: EdgeInsets.only(
                          left: 18,
                          right: 18,
                          top: 10,
                          bottom: 5,
                        ),
                        child: Material(
                          elevation: 2,
                          borderRadius: BorderRadius.circular(20),
                          shadowColor: Colors.black12,

                          child: TextField(
                            controller: searchController,
                            onChanged: (value) {
                              value = value.toLowerCase();
                              setState(() {
                                filteredItems_parties = value.isEmpty
                                    ? parties_list
                                    : parties_list.where((item) {
                                        return item.partyname
                                            .toLowerCase()
                                            .contains(value);
                                      }).toList();

                                party_count = filteredItems_parties.length
                                    .toString();
                                if (int.parse(party_count) < 2) {
                                  party_text = "Party";
                                } else {
                                  party_text = "Parties";
                                }
                              });
                            },
                            decoration: InputDecoration(
                              hintText: "Search Parties...",
                              hintStyle: GoogleFonts.poppins(fontSize: 13),
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
                      // 📊 Party Count
                      Padding(
                        padding: const EdgeInsets.only(
                          left: 16,
                          right: 16,
                          top: 5,
                          bottom: 0,
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                            child: Container(
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).cardColor.withOpacity(0.65),
                                borderRadius: BorderRadius.circular(30),
                                border: Border.all(
                                  color: app_color,
                                  width: 1.4,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.04),
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
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  // 🔵 Icon
                                  Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: app_color.withOpacity(0.1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.people_alt_rounded,
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
                                              "${party_count} ", // <-- Replace dynamically with $party_count
                                          style: GoogleFonts.poppins(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: app_color,
                                          ),
                                        ),
                                        TextSpan(
                                          text: party_text,
                                          style: GoogleFonts.poppins(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w500,
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

                      // ⚠️ No Data Found
                      Visibility(
                        visible: isVisibleNoDataFound,
                        child: SizedBox(
                          height: MediaQuery.of(context).size.height * 0.5,
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.search_off_rounded,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                  size: 40,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'No matching parties',
                                  style: GoogleFonts.poppins(
                                    fontSize: 16,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      // 📋 Party List
                      Visibility(
                        visible: _isAllList,
                        child: ListView.builder(
                          shrinkWrap: true,
                          physics: NeverScrollableScrollPhysics(),
                          itemCount: filteredItems_parties.length,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          itemBuilder: (context, index) {
                            final card = filteredItems_parties[index];
                            return GestureDetector(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        PartyClicked(partyname: card.partyname),
                                  ),
                                );
                              },
                              child: Container(
                                margin: EdgeInsets.only(top: 5, bottom: 0),
                                decoration: BoxDecoration(
                                  color: Theme.of(
                                    context,
                                  ).cardColor.withOpacity(0.9),
                                  borderRadius: BorderRadius.circular(22),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.04),
                                      blurRadius: 16,
                                      offset: Offset(0, 6),
                                    ),
                                  ],
                                  border: Border.all(
                                    color: Theme.of(
                                      context,
                                    ).dividerColor.withOpacity(0.55),
                                    width: 1,
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.only(
                                    left: 10,
                                    right: 10,
                                    top: 16,
                                    bottom: 16,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      // 🧾 Party Name Row with Icon + Prompt Arrow
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color: app_color.withOpacity(0.1),
                                              shape: BoxShape.circle,
                                            ),
                                            child: Icon(
                                              Icons.business_rounded,
                                              color: app_color,
                                              size: 20,
                                            ),
                                          ),
                                          const SizedBox(width: 16),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  card.partyname,
                                                  style: GoogleFonts.poppins(
                                                    fontSize: 17,
                                                    fontWeight: FontWeight.w700,
                                                    color: Theme.of(
                                                      context,
                                                    ).colorScheme.onSurface,
                                                  ),
                                                ),
                                                if (card.alias != 'null' &&
                                                    card.alias != '' &&
                                                    card.alias != null)
                                                  Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                          top: 4,
                                                        ),
                                                    child: Text(
                                                      card.alias,
                                                      style:
                                                          GoogleFonts.poppins(
                                                            fontSize: 14,
                                                            color: Colors
                                                                .grey[600],
                                                          ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),

                                          // 👇 Prompting Arrow Icon
                                          Icon(
                                            Icons.arrow_forward_ios_rounded,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                            size: 18,
                                          ),
                                        ],
                                      ),

                                      // 🕒 Last Invoice Pill
                                      if (card.maxdate != 'null' &&
                                          card.maxdate != '')
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 16,
                                          ),
                                          child: Row(
                                            children: [
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 5,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: app_color.withOpacity(
                                                    0.1,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(30),
                                                ),
                                                child: Row(
                                                  children: [
                                                    Icon(
                                                      Icons
                                                          .calendar_today_rounded,
                                                      size: 16,
                                                      color: app_color,
                                                    ),
                                                    const SizedBox(width: 6),
                                                    Text(
                                                      'Last Invoice:',
                                                      style:
                                                          GoogleFonts.poppins(
                                                            fontWeight:
                                                                FontWeight.w500,
                                                            fontSize: 13,
                                                            color: app_color,
                                                          ),
                                                    ),
                                                    const SizedBox(width: 6),
                                                    Text(
                                                      formatdate(card.maxdate),
                                                      style:
                                                          GoogleFonts.poppins(
                                                            fontSize: 13.5,
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
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
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

  Widget _buildModernToggle({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    final Color activeColor = app_color;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: isActive
              ? activeColor.withOpacity(0.08)
              : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isActive ? activeColor : Theme.of(context).dividerColor,
            width: 1.4,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center, // ✅ CENTER EVERYTHING
          mainAxisSize: MainAxisSize.min, // ✅ avoid stretching content
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isActive
                    ? activeColor
                    : (Theme.of(context).brightness == Brightness.dark
                          ? Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest
                          : Colors.grey.shade100),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 18,
                color: isActive
                    ? Colors.white
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),

            const SizedBox(width: 8),

            Flexible(
              // ✅ prevent overflow but keep centered
              child: Text(
                label,
                textAlign: TextAlign.center, // ✅ center text inside
                overflow: TextOverflow.ellipsis,

                style: GoogleFonts.poppins(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: isActive
                      ? activeColor
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showInactiveDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 🔹 Top Icon
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: app_color.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.timer_off_rounded,
                    size: 40,
                    color: app_color,
                  ),
                ),
                const SizedBox(height: 16),

                // 🔹 Title
                Text(
                  "Inactive Parties",
                  style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),

                // 🔹 Subtitle
                Text(
                  "Enter number of days to check parties with no activity",
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),

                // 🔹 Input Field
                TextField(
                  controller: _inactivedayscontroller,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    hintText: "Enter no. of days",
                    prefixIcon: const Icon(
                      Icons.calendar_today,
                      color: app_color,
                    ),
                    filled: true,
                    fillColor: Theme.of(context).brightness == Brightness.dark
                        ? Theme.of(context).colorScheme.surfaceContainerHighest
                        : (Theme.of(context).brightness == Brightness.dark
                              ? Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHighest
                              : Colors.grey.shade100),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none,
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
                const SizedBox(height: 20),

                // 🔹 Buttons Row
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(
                        "Cancel",
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: () {
                        String inputText = _inactivedayscontroller.text;
                        if (inputText.isEmpty) {
                          Fluttertoast.showToast(
                            msg: 'Please enter no. of days',
                            toastLength: Toast.LENGTH_SHORT,
                            gravity: ToastGravity.BOTTOM,
                            backgroundColor: app_color,
                            textColor: Colors.white,
                          );
                        } else {
                          int? days = int.tryParse(inputText);
                          if (days != null) {
                            DateTime currentDate = DateTime.now();
                            DateTime previousDate = currentDate.subtract(
                              Duration(days: days - 1),
                            );
                            String date = DateFormat(
                              'yyyyMMdd',
                            ).format(previousDate);
                            fetchInactivePartyData(_selectedparty!, date);
                            Navigator.of(context).pop();
                          } else {
                            Fluttertoast.showToast(
                              msg: 'Please enter a valid number',
                              toastLength: Toast.LENGTH_SHORT,
                              gravity: ToastGravity.BOTTOM,
                              backgroundColor: app_color,
                              textColor: Colors.white,
                            );
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: app_color,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                      ),
                      icon: const Icon(
                        Icons.check_circle_outline,
                        color: Colors.white,
                        size: 18,
                      ),
                      label: Text(
                        "Submit",
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
