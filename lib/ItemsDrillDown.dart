import 'dart:convert';
import 'dart:io';
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
import 'constants.dart';
import 'theme_controller.dart';
import 'package:FincoreGo/widgets/app_bottom_nav.dart';
import 'package:FincoreGo/widgets/app_navigation.dart';
import 'widgets/scroll_fab.dart';

class _Crumb {
  final IconData icon;
  final String type;
  final String label;
  const _Crumb(this.icon, this.type, this.label);
}

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

class _DrillLedger {
  final String Partyledger, qty;
  final double amount;
  _DrillLedger({
    required this.Partyledger,
    required this.qty,
    required this.amount,
  });
  factory _DrillLedger.fromJson(Map<String, dynamic> j) => _DrillLedger(
    Partyledger: j['Partyledger'].toString(),
    qty: j['qty'].toString(),
    amount: double.tryParse(j['amount'].toString()) ?? 0,
  );
}

class _DrillBill {
  final String vchno, Partyledger, vchdate;
  final double amount;
  _DrillBill({
    required this.vchno,
    required this.Partyledger,
    required this.vchdate,
    required this.amount,
  });
  factory _DrillBill.fromJson(Map<String, dynamic> j) => _DrillBill(
    vchno: j['vchno'].toString(),
    Partyledger: j['Partyledger'].toString(),
    vchdate: j['vchdate'].toString(),
    amount: double.tryParse(j['amount'].toString()) ?? 0,
  );
}

class _DrillVchType {
  final String vchname, qty;
  final double amount;
  _DrillVchType({
    required this.vchname,
    required this.qty,
    required this.amount,
  });
  factory _DrillVchType.fromJson(Map<String, dynamic> j) => _DrillVchType(
    vchname: j['vchname'].toString(),
    qty: j['qty'].toString(),
    amount: double.tryParse(j['amount'].toString()) ?? 0,
  );
}

class _DrillCostCenter {
  final String costcentre, qty;
  final double amount;
  _DrillCostCenter({
    required this.costcentre,
    required this.qty,
    required this.amount,
  });
  factory _DrillCostCenter.fromJson(Map<String, dynamic> j) => _DrillCostCenter(
    costcentre: j['costcentre'].toString(),
    qty: j['qty'].toString(),
    amount: double.tryParse(j['amount'].toString()) ?? 0,
  );
}

// ---------------------------------------------------------------------------
// Widget
// ---------------------------------------------------------------------------

/// Unified drill-down screen for the Items module.
/// Replaces all 16 ItemsTotalClicked*.dart files.
///
/// Pass the optional lock params to indicate which dimensions are already
/// fixed from a parent drill-down:
///   [lockedLedger]     – party/ledger filter already applied
///   [lockedCostcenter] – cost-centre filter already applied
///   [lockedVchname]    – voucher-type filter already applied
class ItemsDrillDown extends StatefulWidget {
  final String startdate_string, enddate_string, type, item_name, total;
  final String? lockedLedger;
  final String? lockedCostcenter;
  final String? lockedVchname;

  /// Ordered navigation history: each entry has 'type' and 'label' keys.
  final List<Map<String, String>> trail;

  const ItemsDrillDown({
    required this.startdate_string,
    required this.enddate_string,
    required this.type,
    required this.item_name,
    required this.total,
    this.lockedLedger,
    this.lockedCostcenter,
    this.lockedVchname,
    this.trail = const [],
  });

  @override
  _ItemsDrillDownState createState() => _ItemsDrillDownState();
}

class _ItemsDrillDownState extends State<ItemsDrillDown>
    with TickerProviderStateMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ScrollController _scrollFabController = ScrollController();
  late GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey;
  late SharedPreferences prefs;

  // Prefs / auth
  String? hostname, company, serial_no, company_lowercase, username;
  String HttpURL = '', token = '';
  String email = '', name = '';
  String? SecuritybtnAcessHolder;
  bool isDashEnable = true,
      isRolesEnable = true,
      isUserEnable = true,
      isRolesVisible = true,
      isUserVisible = true;

  // UI state
  late String _selectedgroup;
  bool _isLoading = false,
      _isSearchViewVisible = false,
      isSortVisible = false,
      showDateSort = false,
      isVisibleNoDataFound = false;
  String selectedSortOption = 'Default';
  String startdate_text = '', enddate_text = '';
  int counter = 0;

  // Data lists (full + filtered)
  List<_DrillLedger> ledger_list = [], filteredLedger = [];
  List<_DrillBill> bills_list = [], filteredBills = [];
  List<_DrillVchType> vchtype_list = [], filteredVchtype = [];
  List<_DrillCostCenter> costcenter_list = [], filteredCostcenter = [];

  final TextEditingController searchController = TextEditingController();
  final ScrollController _scLedger = ScrollController(),
      _scBills = ScrollController(),
      _scVchtype = ScrollController(),
      _scCostcenter = ScrollController();

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Dimensions that are NOT yet locked – shown in the group-by spinner.
  List<String> get _availableGroups {
    final all = <String>['Ledger', 'Bills', 'Voucher Type', 'Cost Center'];
    if (widget.lockedLedger != null) all.remove('Ledger');
    if (widget.lockedVchname != null) all.remove('Voucher Type');
    if (widget.lockedCostcenter != null) all.remove('Cost Center');
    return all;
  }

  /// Builds the POST body, injecting locked-dimension filters.
  Map<String, dynamic> _buildBody(String groupby, String orderby) {
    final body = <String, dynamic>{
      'startdate': widget.startdate_string,
      'enddate': widget.enddate_string,
      'item': widget.item_name,
      'vchtype': widget.type,
      'groupby': groupby,
      'orderby': orderby,
    };
    if (widget.lockedLedger != null) body['party'] = widget.lockedLedger;
    if (widget.lockedCostcenter != null)
      body['costcentre'] = widget.lockedCostcenter;
    if (widget.lockedVchname != null) body['vchname'] = widget.lockedVchname;
    return body;
  }

  String _formatCostCenter(String v) => v == 'null' ? '*Not Applicable' : v;

  String _convertDate(String dateStr) =>
      DateFormat('dd-MMM-yyyy').format(DateTime.parse(dateStr));

  String _formatAmount(double v) => formatAmount(v.toString());

  // ---------------------------------------------------------------------------
  // Fetch
  // ---------------------------------------------------------------------------

  void _clearLists() {
    ledger_list.clear();
    filteredLedger.clear();
    bills_list.clear();
    filteredBills.clear();
    vchtype_list.clear();
    filteredVchtype.clear();
    costcenter_list.clear();
    filteredCostcenter.clear();
  }

  Future<void> _fetchGroup(String group) async {
    String groupby, orderby;
    switch (group) {
      case 'Ledger':
        groupby = orderby = 'Partyledger';
        break;
      case 'Bills':
        groupby = orderby = 'vchno';
        break;
      case 'Voucher Type':
        groupby = orderby = 'vchname';
        break;
      case 'Cost Center':
        groupby = orderby = 'costcentre';
        break;
      default:
        return;
    }

    setState(() {
      _isLoading = true;
      showDateSort = group == 'Bills';
      if (group != 'Bills' &&
          (selectedSortOption == 'Newest to Oldest' ||
              selectedSortOption == 'Oldest to Newest')) {
        selectedSortOption = 'Default';
      }
      if (group == 'Bills') {
        try {
          selectedSortOption = prefs.getString('sort') ?? 'Default';
        } catch (_) {
          selectedSortOption = 'Default';
        }
      }
    });

    _clearLists();

    try {
      final response = await http.post(
        Uri.parse(HttpURL),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(_buildBody(groupby, orderby)),
      );

      if (response.statusCode == 200) {
        final List<dynamic> raw = jsonDecode(response.body);
        if (raw.isNotEmpty) {
          isVisibleNoDataFound = false;
          switch (group) {
            case 'Ledger':
              ledger_list.addAll(raw.map((j) => _DrillLedger.fromJson(j)));
              filteredLedger = List.from(ledger_list);
              break;
            case 'Bills':
              bills_list.addAll(raw.map((j) => _DrillBill.fromJson(j)));
              filteredBills = List.from(bills_list);
              break;
            case 'Voucher Type':
              vchtype_list.addAll(raw.map((j) => _DrillVchType.fromJson(j)));
              filteredVchtype = List.from(vchtype_list);
              break;
            case 'Cost Center':
              costcenter_list.addAll(
                raw.map((j) => _DrillCostCenter.fromJson(j)),
              );
              filteredCostcenter = List.from(costcenter_list);
              break;
          }
        }
      }
    } catch (e) {
      debugPrint('ItemsDrillDown fetch error: $e');
    }

    setState(() {
      _isLoading = false;
      final empty =
          ledger_list.isEmpty &&
          bills_list.isEmpty &&
          vchtype_list.isEmpty &&
          costcenter_list.isEmpty;
      isVisibleNoDataFound = empty;
      isSortVisible = !empty;
      _applySortOption(selectedSortOption);
    });
  }

  // ---------------------------------------------------------------------------
  // Sort
  // ---------------------------------------------------------------------------

  void _applySortOption(String option) {
    switch (option) {
      case 'Default':
        _sortDefault();
        break;
      case 'Newest to Oldest':
        _sortDateDesc();
        break;
      case 'Oldest to Newest':
        _sortDateAsc();
        break;
      case 'A->Z':
        _sortAlphaAsc();
        break;
      case 'Z->A':
        _sortAlphaDesc();
        break;
      case 'Amount High to Low':
        _sortAmountDesc();
        break;
      case 'Amount Low to High':
        _sortAmountAsc();
        break;
    }
  }

  void _sortDefault() {
    setState(() {
      filteredLedger = List.from(ledger_list);
      filteredBills = List.from(bills_list);
      filteredVchtype = List.from(vchtype_list);
      filteredCostcenter = List.from(costcenter_list);
    });
  }

  void _sortAlphaAsc() {
    setState(() {
      filteredLedger.sort((a, b) => a.Partyledger.compareTo(b.Partyledger));
      filteredBills.sort((a, b) => a.Partyledger.compareTo(b.Partyledger));
      filteredVchtype.sort((a, b) => a.vchname.compareTo(b.vchname));
      filteredCostcenter.sort((a, b) => a.costcentre.compareTo(b.costcentre));
    });
  }

  void _sortAlphaDesc() {
    setState(() {
      filteredLedger.sort((a, b) => b.Partyledger.compareTo(a.Partyledger));
      filteredBills.sort((a, b) => b.Partyledger.compareTo(a.Partyledger));
      filteredVchtype.sort((a, b) => b.vchname.compareTo(a.vchname));
      filteredCostcenter.sort((a, b) => b.costcentre.compareTo(a.costcentre));
    });
  }

  void _sortDateAsc() {
    setState(() {
      filteredBills.sort((a, b) => a.vchdate.compareTo(b.vchdate));
    });
  }

  void _sortDateDesc() {
    setState(() {
      filteredBills.sort((a, b) => b.vchdate.compareTo(a.vchdate));
    });
  }

  void _sortAmountAsc() {
    final isSales = widget.type == 'Sales';
    setState(() {
      filteredLedger.sort(
        (a, b) => isSales
            ? a.amount.compareTo(b.amount)
            : b.amount.compareTo(a.amount),
      );
      filteredBills.sort(
        (a, b) => isSales
            ? a.amount.compareTo(b.amount)
            : b.amount.compareTo(a.amount),
      );
      filteredVchtype.sort(
        (a, b) => isSales
            ? a.amount.compareTo(b.amount)
            : b.amount.compareTo(a.amount),
      );
      filteredCostcenter.sort(
        (a, b) => isSales
            ? a.amount.compareTo(b.amount)
            : b.amount.compareTo(a.amount),
      );
    });
  }

  void _sortAmountDesc() {
    final isSales = widget.type == 'Sales';
    setState(() {
      filteredLedger.sort(
        (a, b) => isSales
            ? b.amount.compareTo(a.amount)
            : a.amount.compareTo(b.amount),
      );
      filteredBills.sort(
        (a, b) => isSales
            ? b.amount.compareTo(a.amount)
            : a.amount.compareTo(b.amount),
      );
      filteredVchtype.sort(
        (a, b) => isSales
            ? b.amount.compareTo(a.amount)
            : a.amount.compareTo(b.amount),
      );
      filteredCostcenter.sort(
        (a, b) => isSales
            ? b.amount.compareTo(a.amount)
            : a.amount.compareTo(b.amount),
      );
    });
  }

  void _showSortSheet() {
    final icons = [
      Icons.sort_rounded,
      if (showDateSort) Icons.date_range_sharp,
      if (showDateSort) Icons.date_range_sharp,
      Icons.sort_by_alpha_rounded,
      Icons.sort_by_alpha_rounded,
      Icons.attach_money_outlined,
      Icons.attach_money_outlined,
    ];
    final options = [
      'Default',
      if (showDateSort) 'Newest to Oldest',
      if (showDateSort) 'Oldest to Newest',
      'A->Z',
      'Z->A',
      'Amount High to Low',
      'Amount Low to High',
    ];
    final height = options.length * 50.0 + 80;

    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (_) => SizedBox(
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Sort',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: options.length,
                itemExtent: 50,
                itemBuilder: (ctx, i) => GestureDetector(
                  onTap: () {
                    setState(() => selectedSortOption = options[i]);
                    _applySortOption(options[i]);
                    Navigator.pop(ctx);
                  },
                  child: ListTile(
                    leading: Icon(icons[i]),
                    title: Text(
                      options[i],
                      style: GoogleFonts.poppins(
                        fontWeight: options[i] == selectedSortOption
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    trailing: options[i] == selectedSortOption
                        ? Icon(Icons.check, color: app_color)
                        : null,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Search
  // ---------------------------------------------------------------------------

  void _handleSearch(String value) {
    final q = value.toLowerCase();
    setState(() {
      if (value.isEmpty) {
        filteredLedger = List.from(ledger_list);
        filteredBills = List.from(bills_list);
        filteredVchtype = List.from(vchtype_list);
        filteredCostcenter = List.from(costcenter_list);
      } else {
        filteredLedger = ledger_list
            .where((e) => e.Partyledger.toLowerCase().contains(q))
            .toList();
        filteredBills = bills_list
            .where((e) => e.vchno.toLowerCase().contains(q))
            .toList();
        filteredVchtype = vchtype_list
            .where((e) => e.vchname.toLowerCase().contains(q))
            .toList();
        filteredCostcenter = costcenter_list
            .where((e) => e.costcentre.toLowerCase().contains(q))
            .toList();
      }
    });
  }

  // ---------------------------------------------------------------------------
  // PDF / CSV Export
  // ---------------------------------------------------------------------------

  Future<void> _shareAsPDF() async {
    final font = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans.ttf'),
    );
    final pdf = pw.Document();
    final reportname = '$_selectedgroup Wise ${widget.type} Summary';

    List<String> headers;
    List<List<String>> rows;

    switch (_selectedgroup) {
      case 'Ledger':
        headers = ['Party Name', 'Qty', 'Amount'];
        rows = ledger_list
            .map((e) => [e.Partyledger, e.qty, _formatAmount(e.amount)])
            .toList();
        break;
      case 'Bills':
        headers = ['Vch Date', 'Vch No', 'Party Name', 'Amount'];
        rows = bills_list
            .map(
              (e) => [
                _convertDate(e.vchdate),
                e.vchno,
                e.Partyledger,
                _formatAmount(e.amount),
              ],
            )
            .toList();
        break;
      case 'Voucher Type':
        headers = ['Vch Name', 'Qty', 'Amount'];
        rows = vchtype_list
            .map((e) => [e.vchname, e.qty, _formatAmount(e.amount)])
            .toList();
        break;
      default:
        headers = ['Cost Center', 'Qty', 'Amount'];
        rows = costcenter_list
            .map(
              (e) => [
                _formatCostCenter(e.costcentre),
                e.qty,
                _formatAmount(e.amount),
              ],
            )
            .toList();
    }

    const perPage = 8;
    for (int p = 0; p < (rows.length / perPage).ceil(); p++) {
      final subset = rows.sublist(
        p * perPage,
        ((p + 1) * perPage).clamp(0, rows.length),
      );
      pdf.addPage(
        pw.Page(
          build: (_) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text(
                company ?? '',
                style: pw.TextStyle(
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Text(
                reportname,
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                '${_convertDate(widget.startdate_string)} to ${_convertDate(widget.enddate_string)}',
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                'Stock Item: ${widget.item_name}',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: font),
              ),
              pw.SizedBox(height: 14),
              pw.Expanded(
                child: pw.Table.fromTextArray(
                  headers: headers,
                  data: subset,
                  border: pw.TableBorder.all(width: 1),
                  headerDecoration: pw.BoxDecoration(color: PdfColors.grey300),
                  headerStyle: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    font: font,
                  ),
                  cellStyle: pw.TextStyle(fontSize: 12, font: font),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final path =
        '${(await getTemporaryDirectory()).path}/${widget.type}_Report.pdf';
    await File(path).writeAsBytes(await pdf.save());
    await SharePlus.instance.share(
      ShareParams(
        text: 'Sharing $_selectedgroup wise ${widget.type} Report of $company',
        files: [XFile(path)],
      ),
    );
  }

  Future<void> _shareAsCSV() async {
    List<List<dynamic>> csvData;
    switch (_selectedgroup) {
      case 'Ledger':
        csvData = [
          ['Party Name', 'Qty', 'Amount'],
          ...ledger_list.map(
            (e) => [e.Partyledger, e.qty, _formatAmount(e.amount)],
          ),
        ];
        break;
      case 'Bills':
        csvData = [
          ['Vch Date', 'Vch No', 'Party Name', 'Amount'],
          ...bills_list.map(
            (e) => [
              _convertDate(e.vchdate),
              e.vchno,
              e.Partyledger,
              _formatAmount(e.amount),
            ],
          ),
        ];
        break;
      case 'Voucher Type':
        csvData = [
          ['Vch Name', 'Qty', 'Amount'],
          ...vchtype_list.map(
            (e) => [e.vchname, e.qty, _formatAmount(e.amount)],
          ),
        ];
        break;
      default:
        csvData = [
          ['Cost Center', 'Qty', 'Amount'],
          ...costcenter_list.map(
            (e) => [
              _formatCostCenter(e.costcentre),
              e.qty,
              _formatAmount(e.amount),
            ],
          ),
        ];
    }

    final path =
        '${(await Directory.systemTemp.createTemp()).path}/${widget.type}_Report.csv';
    await File(path).writeAsString(const ListToCsvConverter().convert(csvData));
    await SharePlus.instance.share(
      ShareParams(
        text: 'Sharing $_selectedgroup wise ${widget.type} Report of $company',
        files: [XFile(path)],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Init
  // ---------------------------------------------------------------------------

  Future<void> _initSharedPreferences() async {
    prefs = await SharedPreferences.getInstance();
    setState(() {
      hostname = prefs.getString('hostname');
      company = prefs.getString('company_name');
      company_lowercase = company!.replaceAll(' ', '').toLowerCase();
      serial_no = prefs.getString('serial_no');
      username = prefs.getString('username');
      token = prefs.getString('token')!;
      SecuritybtnAcessHolder = prefs.getString('secbtnaccess');
      isRolesVisible = isUserVisible = SecuritybtnAcessHolder == 'True';
      HttpURL =
          '$hostname/api/item/getTotalAmount/$company_lowercase/$serial_no';
    });

    try {
      selectedSortOption = prefs.getString('sort') ?? 'Default';
      if (selectedSortOption == 'null') selectedSortOption = 'Default';
    } catch (_) {
      selectedSortOption = 'Default';
    }

    final emailNav = prefs.getString('email_nav');
    final nameNav = prefs.getString('name_nav');
    if (emailNav != null && nameNav != null) {
      email = emailNav;
      name = nameNav;
    }

    startdate_text = _convertDate(widget.startdate_string);
    enddate_text = _convertDate(widget.enddate_string);

    await _fetchGroup(_selectedgroup);
  }

  @override
  void initState() {
    super.initState();
    _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
    _selectedgroup = _availableGroups.first;
    _initSharedPreferences();
  }

  @override
  void dispose() {
    _scrollFabController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: const AppBottomNav(activeTab: AppBottomNavTab.items),
      key: _scaffoldKey,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: AppBar(
          backgroundColor: app_color,
          elevation: 6,
          centerTitle: true,
          automaticallyImplyLeading: false,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => AppNavigation.backOrDashboard(context),
          ),
          title: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth:
                  MediaQuery.of(context).size.width - (kToolbarHeight * 5.2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.type,
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  widget.item_name,
                  style: GoogleFonts.poppins(
                    color: Colors.white70,
                    fontSize: 13,
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
                setState(() {
                  _isSearchViewVisible = !_isSearchViewVisible;
                  if (!_isSearchViewVisible) {
                    searchController.clear();
                    _handleSearch('');
                  }
                });
              },
              icon: const Icon(Icons.search, color: Colors.white, size: 28),
            ),
            IconButton(
              onPressed: () {
                final box = context.findRenderObject() as RenderBox;
                final overlay =
                    Overlay.of(context).context.findRenderObject() as RenderBox;
                final pos = box.localToGlobal(Offset.zero, ancestor: overlay);
                showMenu(
                  context: context,
                  position: RelativeRect.fromLTRB(
                    overlay.size.width - pos.dx,
                    pos.dy - box.size.height,
                    overlay.size.width - pos.dx,
                    pos.dy,
                  ),
                  items: [
                    PopupMenuItem(
                      child: GestureDetector(
                        onTap: () {
                          Navigator.pop(context);
                          _shareAsPDF();
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
                                color: app_color,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    PopupMenuItem(
                      child: GestureDetector(
                        onTap: () {
                          Navigator.pop(context);
                          _shareAsCSV();
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
              icon: const Icon(Icons.share, color: Colors.white, size: 28),
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
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 20,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Text(
                          widget.total,
                          style: GoogleFonts.poppins(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
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
                            border: Border.all(color: app_color),
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
                                '$startdate_text → $enddate_text',
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
                      // Breadcrumb trail
                      if (widget.trail.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        _buildBreadcrumb(),
                      ],
                      const SizedBox(height: 20),
                      // Group-by dropdown
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest
                                    .withOpacity(0.72)
                              : Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest
                                    .withOpacity(0.45),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: Theme.of(context).dividerColor,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.filter_alt_outlined,
                              size: 20,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Group by:',
                              style: GoogleFonts.poppins(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: _selectedgroup,
                                  dropdownColor: Theme.of(
                                    context,
                                  ).colorScheme.surface,
                                  borderRadius: BorderRadius.circular(18),
                                  style: GoogleFonts.poppins(
                                    fontSize: 15,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
                                  ),
                                  icon: Icon(
                                    Icons.arrow_drop_down,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                  onChanged: (v) {
                                    if (v == null) return;
                                    setState(() => _selectedgroup = v);
                                    _fetchGroup(v);
                                  },
                                  items: _availableGroups
                                      .map(
                                        (g) => DropdownMenuItem(
                                          value: g,
                                          child: Text(g),
                                        ),
                                      )
                                      .toList(),
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

              // List card
              SliverToBoxAdapter(
                child: Container(
                  margin: const EdgeInsets.only(
                    left: 16,
                    right: 16,
                    bottom: 16,
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
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                          child: Material(
                            elevation: 2,
                            borderRadius: BorderRadius.circular(18),
                            shadowColor: Colors.black12,
                            child: TextField(
                              controller: searchController,
                              onChanged: _handleSearch,
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
                      _buildListSection(),
                    ],
                  ),
                ),
              ),
            ],
          ),

          if (_isLoading) const Center(child: AppLogoLoader()),

          if (isSortVisible)
            Positioned(
              bottom: 28,
              left: 0,
              right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: _showSortSheet,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 15,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [app_color, app_color],
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
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          if (isVisibleNoDataFound)
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.5,
              child: Center(
                child: Text(
                  'No data found',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ScrollFab(controller: _scrollFabController),
        ],
      ),
    );
  }

  Widget _buildBreadcrumb() {
    final _iconMap = <String, IconData>{
      'Party': Icons.person_outline_rounded,
      'Vch Type': Icons.receipt_long_rounded,
      'Cost Center': Icons.business_center_rounded,
    };
    final crumbs = widget.trail
        .map(
          (e) => _Crumb(
            _iconMap[e['type']] ?? Icons.label_outline,
            e['type']!,
            e['label']!,
          ),
        )
        .toList();

    final isDark = Theme.of(context).brightness == Brightness.dark;

    final widgets = <Widget>[];
    for (int i = 0; i < crumbs.length; i++) {
      final c = crumbs[i];
      final isLast = i == crumbs.length - 1;
      widgets.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            gradient: isLast
                ? LinearGradient(
                    colors: [
                      app_color.withOpacity(isDark ? 0.35 : 0.18),
                      app_color.withOpacity(isDark ? 0.2 : 0.08),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: isLast
                ? null
                : (isDark
                      ? Colors.white.withOpacity(0.06)
                      : Colors.black.withOpacity(0.04)),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: isLast
                  ? app_color.withOpacity(0.7)
                  : Theme.of(context).dividerColor,
              width: isLast ? 1.4 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: isLast
                      ? app_color.withOpacity(0.18)
                      : Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  c.icon,
                  size: 11,
                  color: isLast
                      ? app_color
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 6),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    c.type,
                    style: GoogleFonts.poppins(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w500,
                      color: isLast
                          ? app_color.withOpacity(0.8)
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                      letterSpacing: 0.3,
                    ),
                  ),
                  Text(
                    c.label,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: isLast ? FontWeight.w700 : FontWeight.w500,
                      color: isLast
                          ? app_color
                          : Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
      if (i < crumbs.length - 1) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Icon(
              Icons.arrow_forward_ios_rounded,
              size: 10,
              color: Theme.of(
                context,
              ).colorScheme.onSurfaceVariant.withOpacity(0.5),
            ),
          ),
        );
      }
    }

    return Wrap(
      spacing: 6,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: widgets,
    );
  }

  // ---------------------------------------------------------------------------
  // List section
  // ---------------------------------------------------------------------------

  Widget _buildListSection() {
    switch (_selectedgroup) {
      case 'Ledger':
        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: filteredLedger.length,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          itemBuilder: (_, i) {
            final item = filteredLedger[i];
            return _buildCard(
              title: item.Partyledger,
              amount: item.amount,
              qty: item.qty,
              listType: 'Ledger',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ItemsDrillDown(
                    startdate_string: widget.startdate_string,
                    enddate_string: widget.enddate_string,
                    type: widget.type,
                    total: _formatAmount(item.amount),
                    item_name: widget.item_name,
                    lockedLedger: item.Partyledger,
                    lockedCostcenter: widget.lockedCostcenter,
                    lockedVchname: widget.lockedVchname,
                    trail: [
                      ...widget.trail,
                      {'type': 'Party', 'label': item.Partyledger},
                    ],
                  ),
                ),
              ),
            );
          },
        );

      case 'Bills':
        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: filteredBills.length,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          itemBuilder: (_, i) {
            final item = filteredBills[i];
            return _buildCard(
              title: item.vchno,
              subtitle: item.Partyledger,
              amount: item.amount,
              date: item.vchdate,
              listType: 'Bills',
            );
          },
        );

      case 'Voucher Type':
        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: filteredVchtype.length,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          itemBuilder: (_, i) {
            final item = filteredVchtype[i];
            return _buildCard(
              title: item.vchname,
              amount: item.amount,
              qty: item.qty,
              listType: 'Voucher Type',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ItemsDrillDown(
                    startdate_string: widget.startdate_string,
                    enddate_string: widget.enddate_string,
                    type: widget.type,
                    total: _formatAmount(item.amount),
                    item_name: widget.item_name,
                    lockedLedger: widget.lockedLedger,
                    lockedCostcenter: widget.lockedCostcenter,
                    lockedVchname: item.vchname,
                    trail: [
                      ...widget.trail,
                      {'type': 'Vch Type', 'label': item.vchname},
                    ],
                  ),
                ),
              ),
            );
          },
        );

      case 'Cost Center':
        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: filteredCostcenter.length,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          itemBuilder: (_, i) {
            final item = filteredCostcenter[i];
            return _buildCard(
              title: _formatCostCenter(item.costcentre),
              amount: item.amount,
              qty: item.qty,
              listType: 'Cost Center',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ItemsDrillDown(
                    startdate_string: widget.startdate_string,
                    enddate_string: widget.enddate_string,
                    type: widget.type,
                    total: _formatAmount(item.amount),
                    item_name: widget.item_name,
                    lockedLedger: widget.lockedLedger,
                    lockedCostcenter: item.costcentre,
                    lockedVchname: widget.lockedVchname,
                    trail: [
                      ...widget.trail,
                      {
                        'type': 'Cost Center',
                        'label': item.costcentre == 'null'
                            ? 'Not Applicable'
                            : item.costcentre,
                      },
                    ],
                  ),
                ),
              ),
            );
          },
        );

      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildCard({
    required String title,
    String? subtitle,
    required double amount,
    String? date,
    String? qty,
    required String listType,
    VoidCallback? onTap,
  }) {
    final isBills = listType == 'Bills';
    final icons = <String, IconData>{
      'Ledger': Icons.account_balance_wallet_rounded,
      'Bills': Icons.receipt_long_rounded,
      'Voucher Type': Icons.assignment_outlined,
      'Cost Center': Icons.business_center_rounded,
    };
    final topRightLabel = isBills
        ? (date != null && date.isNotEmpty ? _convertDate(date) : null)
        : (qty != null ? 'Qty: $qty' : null);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(18),
          border: Theme.of(context).brightness == Brightness.dark
              ? Border.all(color: Colors.white.withOpacity(0.10), width: 1)
              : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  height: 44,
                  width: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        app_color.withOpacity(0.9),
                        app_color.withOpacity(0.5),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: app_color.withOpacity(0.25),
                        blurRadius: 6,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Icon(
                    icons[listType] ?? Icons.circle,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              softWrap: true,
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w600,
                                fontSize: 15.5,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ),
                          if (topRightLabel != null)
                            Container(
                              margin: const EdgeInsets.only(left: 8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.orangeAccent.withOpacity(0.9),
                                    Colors.deepOrangeAccent.withOpacity(0.8),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(30),
                              ),
                              child: Text(
                                topRightLabel,
                                style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          softWrap: true,
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Theme.of(context).colorScheme.primary.withOpacity(
                          Theme.of(context).brightness == Brightness.dark
                              ? 0.22
                              : 0.12,
                        ),
                        Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest.withOpacity(
                          Theme.of(context).brightness == Brightness.dark
                              ? 0.55
                              : 0.35,
                        ),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Theme.of(context).dividerColor.withOpacity(0.75),
                    ),
                  ),
                  child: Text(
                    _formatAmount(amount),
                    style: GoogleFonts.poppins(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
                if (onTap != null)
                  Icon(
                    Icons.chevron_right_rounded,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    size: 22,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
