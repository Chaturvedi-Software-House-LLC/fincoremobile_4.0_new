import 'dart:ui';
import 'package:FincoreGo/Dashboard.dart';
import 'package:FincoreGo/constants.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'PartyClicked.dart';
import 'SerialSelect.dart';
import 'CompanySelectTallyOauth.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'widgets/searchable_selector.dart';
import 'package:share_plus/share_plus.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:FincoreGo/widgets/app_bottom_nav.dart';
import 'package:FincoreGo/widgets/app_navigation.dart';
import 'widgets/scroll_fab.dart';
import 'widgets/entry_widgets.dart';
import 'api/api_exception.dart';
import 'api/ledger_repository.dart';

class party {
  final int masterId;
  final String partyname;
  final String alias;
  final String mobile;
  final String email;
  final String maxdate;

  party({
    required this.masterId,
    required this.partyname,
    required this.alias,
    required this.mobile,
    required this.email,
    required this.maxdate,
  });

  /// Maps a tally-api ledger row (base `/ledgers` list, or one merged with
  /// `lastVoucherDate` by `LedgerRepository.listInactiveLedgers`) - no
  /// legacy `getLedger`/`getInactiveLedger` shape survives here.
  ///
  /// The base ledger list has no per-ledger "last activity" date (that
  /// only exists on the inactive-ledgers report), so `maxdate` is only
  /// ever populated for rows coming from the Inactive Parties list - the
  /// main "All Parties" list shows '-' where it used to show a date. No
  /// tally-api field fills that gap for an active ledger.
  factory party.fromJson(Map<String, dynamic> json) {
    final alias = (json['alias'] as List?)?.cast<String>() ?? const [];
    return party(
      masterId: json['masterId'] as int,
      partyname: (json['name'] ?? '').toString(),
      alias: alias.isEmpty ? 'null' : alias.join(', '),
      mobile: (json['mobileNumber'] ?? json['phoneNumber'] ?? 'null').toString(),
      email: (json['email'] ?? 'null').toString(),
      maxdate: (json['lastVoucherDate'] ?? '').toString(),
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

  String party_count = "0";

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

  dynamic _selectedparty = "All Parties";
  List<String> spinner_list = ["All Parties"];
  final Map<String, int> _groupMasterIdByName = {};

  List<party> parties_list = [];

  // --- Incremental (infinite-scroll) paging state for the "All Parties"
  // tab. tally-api's `/ledgers` list has no "in a set of group ids" filter
  // (only a single `groupMasterId` equality filter), so "All Parties"
  // (every party-like group at once) pages through each relevant group's
  // ids in turn - fully exhausting one group's pages before starting the
  // next - rather than requesting every group in one call. A single
  // selected group in the dropdown is just a one-element queue.
  static const int _partyPageLimit = 30;
  List<int> _pagingGroupIds = [];
  int _pagingGroupIndex = 0;
  int _pagingPage = 1;
  bool _pagingHasMore = false;
  bool _isLoadingMoreParties = false;

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

  Future<void> generateAndSharePDF_Party(List<party> items) async {
    final font = pw.Font.ttf(
      await rootBundle.load("assets/fonts/NotoSans.ttf"),
    );
    final pdf = pw.Document();

    final companyName = company!;
    final reportname = 'Parties';
    final headersRow3 = ['Party Name', 'Alias', 'Email Address', 'Contact No'];

    final itemsPerPage = 10;
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

  Future<void> generateAndSharePDF_PartyCustom(List<party> items) async {
    final font = pw.Font.ttf(
      await rootBundle.load("assets/fonts/NotoSans.ttf"),
    );
    final pdf = pw.Document();

    final companyName = company!;
    final reportname = 'Parties';
    final parentname = _selectedparty;
    final headersRow3 = ['Party Name', 'Alias', 'Email Address', 'Contact No'];

    final itemsPerPage = 10;
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

  Future<void> generateAndShareCSV_Party(List<party> items) async {
    final List<List<dynamic>> csvData = [];
    final headersRow = ['Party Name', 'Alias', 'Email Address', 'Contact No'];
    csvData.add(headersRow);

    for (final item in items) {
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

  /// Populates the "parent" dropdown from tally-api's party-like groups
  /// (see LedgerRepository's doc comment on the group-name/reservedName
  /// match it uses in place of the legacy `ledGroups` server-side filter).
  Future<void> fetchParentData(final String ledGroups) async {
    setState(() {
      _isLoading = true;
    });

    try {
      final groups = await LedgerRepository.instance.listPartyGroups();
      _groupMasterIdByName.clear();
      for (final group in groups) {
        final name = group['name'] as String;
        _groupMasterIdByName[name] = group['masterId'] as int;
        spinner_list.add(name);
      }
      setState(() {
        _selectedparty = spinner_list[0];
        isClicked_allparties = true;
        isClicked_inactiveparties = false;
      });
      fetchPartyData(_selectedparty);
    } on ApiException catch (e) {
      showAppMessage(context, e.message);
      setState(() => _isLoading = false);
    } catch (e) {
      showAppMessage(context, 'Could not reach the server. Please try again.');
      setState(() => _isLoading = false);
    }
  }

  void fetchPartyData(String party) {
    final groupIds = party == "All Parties"
        ? _groupMasterIdByName.values.toList()
        : (_groupMasterIdByName[party] == null
              ? <int>[]
              : [_groupMasterIdByName[party]!]);
    _startPartyPaging(groupIds);
  }

  void fetchInactivePartyData(String party, String date) {
    fetchInactiveParties(
      party == "All Parties" ? null : _groupMasterIdByName[party],
      date,
    );
  }

  /// Re-applies the search box's filter over whatever has been loaded so
  /// far. **Narrower than the old full-list search**: tally-api's `/ledgers`
  /// list has no server-side name-search query param, so this only
  /// searches the pages already fetched by infinite scroll, not the whole
  /// company's parties - matching more of them as the user scrolls further
  /// (or searches after scrolling down) rather than all at once.
  void _applyPartySearchFilter() {
    final value = searchController.text.toLowerCase();
    filteredItems_parties = value.isEmpty
        ? parties_list
        : parties_list
              .where((item) => item.partyname.toLowerCase().contains(value))
              .toList();
    party_count = filteredItems_parties.length.toString();
    party_text = filteredItems_parties.length == 1 ? "Party" : "Parties";
  }

  /// Resets and starts (or restarts) the "All Parties" tab's incremental
  /// paging queue over [groupIds], then loads the first page.
  Future<void> _startPartyPaging(List<int> groupIds) async {
    setState(() {
      party_count = "0";
      party_text = "Party";
      _isLoading = true;
      _isAllList = false;
      isClicked_parties = true;
      isVisibleNoDataFound = false;
      searchController.clear();
    });

    parties_list.clear();
    filteredItems_parties = parties_list;
    _pagingGroupIds = groupIds;
    _pagingGroupIndex = 0;
    _pagingPage = 1;
    _pagingHasMore = groupIds.isNotEmpty;

    await _loadNextPartyPage();
  }

  /// Loads one more page of parties (30 rows) into [parties_list], moving
  /// on to the next group in [_pagingGroupIds] once the current one is
  /// exhausted. Called for the first page by [_startPartyPaging] and for
  /// every subsequent page by the scroll-near-bottom listener.
  ///
  /// Auto-chains through any number of consecutive EMPTY groups (bounded by
  /// [_pagingGroupIds]'s length) rather than stopping after the first one -
  /// real party ledgers are often nested under a sub-group ("Local
  /// Customers" under "Sundry Debtors") rather than sitting directly in the
  /// top-level reserved group, so the very first group in the queue coming
  /// back empty is a normal, expected case, not "no data" - without this,
  /// the screen would show "No matching parties" and never get a chance to
  /// try the next group, since there'd be no scrollable content left to
  /// trigger the next page load.
  Future<void> _loadNextPartyPage() async {
    if (_isLoadingMoreParties || !_pagingHasMore) return;
    if (_pagingGroupIndex >= _pagingGroupIds.length) {
      setState(() => _pagingHasMore = false);
      return;
    }

    setState(() => _isLoadingMoreParties = true);

    try {
      while (_pagingGroupIndex < _pagingGroupIds.length) {
        final groupId = _pagingGroupIds[_pagingGroupIndex];
        final result = await LedgerRepository.instance.listLedgersPage(
          page: _pagingPage,
          limit: _partyPageLimit,
          groupMasterId: groupId,
        );
        parties_list.addAll(result.items.map(party.fromJson));

        if (result.hasMore) {
          _pagingPage++;
          break;
        } else {
          _pagingGroupIndex++;
          _pagingPage = 1;
          if (result.items.isNotEmpty) break;
          // Empty page from this group - keep walking the queue instead of
          // stopping here, so a party-less top-level group doesn't hide
          // every other group's parties.
        }
      }
      _pagingHasMore = _pagingGroupIndex < _pagingGroupIds.length;

      _applyPartySearchFilter();
      setState(() {
        _isAllList = true;
        _isLoading = false;
        _isLoadingMoreParties = false;
        isVisibleNoDataFound = parties_list.isEmpty;
      });
    } on ApiException catch (e) {
      showAppMessage(context, e.message);
      setState(() {
        _isAllList = parties_list.isNotEmpty;
        _isLoading = false;
        _isLoadingMoreParties = false;
      });
    } catch (e) {
      showAppMessage(context, 'Could not reach the server. Please try again.');
      setState(() {
        _isAllList = parties_list.isNotEmpty;
        _isLoading = false;
        _isLoadingMoreParties = false;
      });
    }
  }

  void _onPartyScroll() {
    if (!isClicked_allparties) return;
    if (!_scrollFabController.hasClients) return;
    final position = _scrollFabController.position;
    if (position.pixels >= position.maxScrollExtent - 400) {
      _loadNextPartyPage();
    }
  }

  /// Fetches the full, unpaginated party list on demand for PDF/CSV export
  /// - export is an occasional explicit action (not the initial screen
  /// render infinite-scroll is optimizing), so it's fine for it to fetch
  /// everything rather than being limited to whatever's been scrolled into
  /// view so far.
  Future<List<party>> _fullPartiesForExport() async {
    if (isClicked_inactiveparties) {
      // Inactive Parties never uses incremental paging (see
      // fetchInactiveParties) - filteredItems_parties already holds its
      // full, sorted result set.
      return filteredItems_parties;
    }
    final groupMasterId = _selectedparty == "All Parties"
        ? null
        : _groupMasterIdByName[_selectedparty];
    final rows = await LedgerRepository.instance.listLedgers(
      groupMasterId: groupMasterId,
    );
    final all = rows.map(party.fromJson).toList();
    final value = searchController.text.toLowerCase();
    return value.isEmpty
        ? all
        : all.where((item) => item.partyname.toLowerCase().contains(value)).toList();
  }

  Future<void> fetchInactiveParties(int? groupMasterId, String date) async {
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
      final rows = await LedgerRepository.instance.listInactiveLedgers(
        asOf: DateTime.parse(date),
        groupMasterId: groupMasterId,
      );
      parties_list.addAll(rows.map(party.fromJson));

      // A ledger with no voucher activity ever has a null lastVoucherDate
      // (party.fromJson maps that to '') - sorts last rather than
      // throwing, unlike a bare DateTime.parse would on an empty string.
      parties_list.sort((a, b) {
        final dateA = DateTime.tryParse(a.maxdate);
        final dateB = DateTime.tryParse(b.maxdate);
        if (dateA == null && dateB == null) return 0;
        if (dateA == null) return 1;
        if (dateB == null) return -1;
        return dateB.compareTo(dateA);
      });

      filteredItems_parties = parties_list;
      setState(() {
        party_count = filteredItems_parties.length.toString();
        party_text = filteredItems_parties.length == 1 ? "Party" : "Parties";
        _isAllList = true;
        _isLoading = false;
      });
    } on ApiException catch (e) {
      showAppMessage(context, e.message);
      setState(() {
        _isAllList = false;
        _isLoading = false;
      });
    } catch (e) {
      showAppMessage(context, 'Could not reach the server. Please try again.');
      setState(() {
        _isAllList = false;
        _isLoading = false;
      });
    }

    setState(() {
      if (parties_list.isEmpty) {
        party_count = "0";
        party_text = "Party";
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
      int defaultDays =
          prefs.getInt('inactiveparties_days') ??
          30; // Default to 30 if not found
      _inactivedayscontroller.text = defaultDays.toString();
    });

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
    _scrollFabController.addListener(_onPartyScroll);
    _initSharedPreferences();
  }

  @override
  void dispose() {
    _scrollFabController.removeListener(_onPartyScroll);
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
        preferredSize: Size.fromHeight(44),
        child: AppBar(
          backgroundColor: app_color,
          elevation: 2,
          automaticallyImplyLeading: false,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
          ),
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: Colors.white, size: 20),
            onPressed: () {
              AppNavigation.backOrDashboard(context);
            },
          ),
          title: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth:
                  MediaQuery.of(context).size.width - (kToolbarHeight * 1.6),
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
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  SizedBox(width: 2),
                  Icon(Icons.arrow_drop_down, color: Colors.white, size: 20),
                ],
              ),
            ),
          ),
          centerTitle: false,
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
                  if((int.tryParse(party_count) ?? 0)<2)
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
                        onTap: () async {
                          Navigator.pop(context);
                          if (parties_list.isEmpty) return;
                          final items = await _fullPartiesForExport();
                          if (items.isEmpty) return;
                          if (_selectedparty == 'All Parties') {
                            generateAndSharePDF_Party(items);
                          } else {
                            generateAndSharePDF_PartyCustom(items);
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
                        onTap: () async {
                          Navigator.pop(context);

                          if (parties_list.isEmpty) return;
                          final items = await _fullPartiesForExport();
                          if (items.isEmpty) return;
                          generateAndShareCSV_Party(items);
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
                    margin: const EdgeInsets.only(left: 12, right: 12, top: 10),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black12.withOpacity(0.08),
                          blurRadius: 8,
                          offset: Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Dropdown
                        Container(
                          height: 38,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(context).brightness == Brightness.dark
                                ? Colors.white.withOpacity(0.06)
                                : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: SearchableSelectorField<String>(
                            value: _selectedparty,
                            items: spinner_list,
                            itemLabel: (v) => v,
                            hintText: "Select Party",
                            decorated: false,
                            trailingIcon: Icons.keyboard_arrow_down_rounded,
                            textStyle: GoogleFonts.poppins(
                              fontSize: 15,
                              color: Theme.of(context).colorScheme.onSurface,
                              fontWeight: FontWeight.w500,
                            ),
                            hintStyle: GoogleFonts.poppins(
                              fontSize: 14,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
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

                        const SizedBox(height: 8),

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
                              const SizedBox(width: 8),

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
                                      party_text = (int.tryParse(party_count) ?? 0) < 2
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
                          left: 12,
                          right: 12,
                          top: 8,
                          bottom: 4,
                        ),
                        child: SizedBox(
                          height: 46,
                          child: TextField(
                            controller: searchController,
                            style: GoogleFonts.poppins(fontSize: 13.5),
                            onChanged: (value) {
                              // See _applyPartySearchFilter's doc comment:
                              // on the "All Parties"/group tabs this only
                              // searches pages already loaded by infinite
                              // scroll (no server-side name-search param on
                              // tally-api's /ledgers), not the whole
                              // company's parties. Inactive Parties still
                              // searches its full (non-paged) result set.
                              setState(() => _applyPartySearchFilter());
                            },
                            decoration: InputDecoration(
                              isDense: true,
                              hintText: "Search Parties...",
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
                              suffixIcon: Padding(
                                padding: const EdgeInsets.only(right: 12),
                                child: Center(
                                  widthFactor: 1,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: app_color.withOpacity(0.10),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      party_count,
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
                    ],
                  ),
                ),

                // 📋 Party List - a real sliver (SliverList) so the
                // CustomScrollView only builds cards near the viewport;
                // the previous shrinkWrap ListView.builder forced eager
                // layout of every party up front, which is what made
                // scrolling hang on large party lists.
                if (_isAllList)
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final card = filteredItems_parties[index];
                        return GestureDetector(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => PartyClicked(
                                      partyname: card.partyname,
                                      ledgerMasterId: card.masterId,
                                    ),
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
                      }, childCount: filteredItems_parties.length),
                    ),
                  ),

                // Bottom-of-list spinner while the next page of the "All
                // Parties" tab loads - never shown for Inactive Parties,
                // which always loads its full result set in one go.
                if (isClicked_allparties && _isLoadingMoreParties)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: app_color,
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
                  child: _buildSkeletonPartyList(),
                ),
              ),
            ScrollFab(controller: _scrollFabController),
          ],
        ),
      ),
    );
  }

  // Skeleton stand-in for the header (dropdown + toggle buttons) and party
  // list while the initial fetch is in flight - replaces the old dimmed
  // spinner overlay so the loading state reads as "content incoming"
  // instead of a blank page. Generic (icon badge + name line + alias line +
  // pill line) rather than mirroring every party card variant, since the
  // shape is close enough for the transition to feel seamless.
  Widget _buildSkeletonPartyList() {
    return ShimmerLoading(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 90),
        children: [
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
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
              children: [
                const ShimmerBox(height: 38, borderRadius: 12),
                const SizedBox(height: 8),
                Row(
                  children: const [
                    Expanded(child: ShimmerBox(height: 34, borderRadius: 12)),
                    SizedBox(width: 8),
                    Expanded(child: ShimmerBox(height: 34, borderRadius: 12)),
                  ],
                ),
              ],
            ),
          ),
          for (int i = 0; i < 7; i++)
            Container(
              margin: const EdgeInsets.only(top: 5, bottom: 5),
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 16,
              ),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor.withOpacity(0.9),
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
                border: Border.all(
                  color: Theme.of(context).dividerColor.withOpacity(0.55),
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      ShimmerBox(width: 36, height: 36, borderRadius: 18),
                      SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ShimmerBox(height: 15, width: 140),
                            SizedBox(height: 6),
                            ShimmerBox(height: 11, width: 90),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const ShimmerBox(height: 24, width: 160, borderRadius: 30),
                ],
              ),
            ),
        ],
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
        duration: const Duration(milliseconds: 200),
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: isActive
              ? activeColor.withOpacity(0.10)
              : (Theme.of(context).brightness == Brightness.dark
                    ? Colors.white.withOpacity(0.06)
                    : Colors.grey.shade100),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isActive
                  ? activeColor
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),

            const SizedBox(width: 6),

            Flexible(
              child: Text(
                label,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,

                style: GoogleFonts.poppins(
                  fontSize: 13,
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
                          showAppMessage(
                            context,
                            'Please enter no. of days',
                            isError: false,
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
                            showAppMessage(
                              context,
                              'Please enter a valid number',
                              isError: false,
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
