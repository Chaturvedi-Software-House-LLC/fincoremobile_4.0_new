import 'dart:ui';
import 'package:FincoreGo/Dashboard.dart';
import 'package:FincoreGo/constants.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'PartyClicked.dart';
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
import 'providers/party_notifier.dart';

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

class Party extends ConsumerStatefulWidget {
  @override
  ConsumerState<Party> createState() => _PartyPageState();
}

class _PartyPageState extends ConsumerState<Party>
    with TickerProviderStateMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ScrollController _scrollFabController = ScrollController();

  TextEditingController _inactivedayscontroller = TextEditingController();

  TextEditingController searchController = TextEditingController();

  late GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey;

  bool allparties_visibility = true;
  bool inactiveparties_visibility = true;

  PartyState get _s => ref.read(partyNotifierProvider);
  PartyNotifier get _notifier => ref.read(partyNotifierProvider.notifier);

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

    final companyName = _s.company;
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

    final companyName = _s.company;
    final reportname = 'Parties';
    final parentname = _s.selectedParty;
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
    ], text: 'Sharing Parties Report of ${_s.company}');
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

  void _onPartyScroll() {
    if (!_s.isClickedAllParties) return;
    if (!_scrollFabController.hasClients) return;
    final position = _scrollFabController.position;
    if (position.pixels >= position.maxScrollExtent - 400) {
      _notifier.loadNextPartyPage();
    }
  }

  Future<void> _loadInactiveDaysDefault() async {
    final prefs = await SharedPreferences.getInstance();
    final defaultDays = prefs.getInt('inactiveparties_days') ?? 30;
    _inactivedayscontroller.text = defaultDays.toString();
  }

  @override
  void initState() {
    super.initState();
    _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
    _scrollFabController.addListener(_onPartyScroll);
    _loadInactiveDaysDefault();
  }

  @override
  void dispose() {
    _scrollFabController.removeListener(_onPartyScroll);
    _scrollFabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(partyNotifierProvider);
    ref.listen<PartyState>(partyNotifierProvider, (previous, next) {
      if (next.errorMessage != null) {
        showAppMessage(context, next.errorMessage!);
        _notifier.clearError();
      }
    });

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
                      _s.company,

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
                          if (_s.partiesList.isEmpty) return;
                          final items = await _notifier
                              .fullPartiesForExport(searchController.text);
                          if (items.isEmpty) return;
                          if (_s.selectedParty == 'All Parties') {
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

                          if (_s.partiesList.isEmpty) return;
                          final items = await _notifier
                              .fullPartiesForExport(searchController.text);
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
                            value: _s.selectedParty,
                            items: _s.spinnerList,
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
                              if (newValue == null) return;
                              searchController.clear();
                              _notifier.selectPartyGroup(newValue);
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
                                  isActive: _s.isClickedAllParties,
                                  onTap: () {
                                    FocusScope.of(context).unfocus();
                                    searchController.clear();
                                    _notifier.showAllPartiesTab();
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
                                  isActive: _s.isClickedInactiveParties,
                                  onTap: () {
                                    FocusScope.of(context).unfocus();
                                    _notifier.prepareInactiveTab();
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
                              // See PartyNotifier.applyFilter's doc comment:
                              // on the "All Parties"/group tabs this only
                              // searches pages already loaded by infinite
                              // scroll (no server-side name-search param on
                              // tally-api's /ledgers), not the whole
                              // company's parties. Inactive Parties still
                              // searches its full (non-paged) result set.
                              _notifier.applyFilter(value);
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
                                      _s.partyCount,
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
                        visible: _s.isVisibleNoDataFound,
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
                if (_s.isAllList)
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final card = _s.filteredItemsParties[index];
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
                      }, childCount: _s.filteredItemsParties.length),
                    ),
                  ),

                // Bottom-of-list spinner while the next page of the "All
                // Parties" tab loads - never shown for Inactive Parties,
                // which always loads its full result set in one go.
                if (_s.isClickedAllParties && _s.isLoadingMoreParties)
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
            if (_s.isLoading)
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
                            _notifier.fetchInactivePartyData(
                              _s.selectedParty,
                              date,
                            );
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
