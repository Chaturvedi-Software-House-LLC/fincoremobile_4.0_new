import 'dart:convert';
import 'dart:io';
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
import 'constants.dart';
import 'package:FincoreGo/widgets/app_bottom_nav.dart';
import 'package:FincoreGo/widgets/app_navigation.dart';

class _PCrumb {
  final IconData icon;
  final String type;
  final String label;
  const _PCrumb(this.icon, this.type, this.label);
}

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

class _PItem {
  final String item, qty;
  final double amount;
  _PItem({required this.item, required this.qty, required this.amount});
  factory _PItem.fromJson(Map<String, dynamic> j) => _PItem(
    item: j['item'].toString(),
    qty: j['qty'].toString(),
    amount: double.tryParse(j['amount'].toString()) ?? 0,
  );
}

class _PBill {
  final String vchno, Partyledger, vchdate;
  final double amount;
  _PBill({
    required this.vchno,
    required this.Partyledger,
    required this.vchdate,
    required this.amount,
  });
  factory _PBill.fromJson(Map<String, dynamic> j) => _PBill(
    vchno: j['vchno'].toString(),
    Partyledger: j['Partyledger'].toString(),
    vchdate: j['vchdate'].toString(),
    amount: double.tryParse(j['amount'].toString()) ?? 0,
  );
}

class _PVchType {
  final String vchname, qty;
  final double amount;
  _PVchType({required this.vchname, required this.qty, required this.amount});
  factory _PVchType.fromJson(Map<String, dynamic> j) => _PVchType(
    vchname: j['vchname'].toString(),
    qty: j['qty'].toString(),
    amount: double.tryParse(j['amount'].toString()) ?? 0,
  );
}

class _PCostCenter {
  final String costcentre, qty;
  final double amount;
  _PCostCenter({
    required this.costcentre,
    required this.qty,
    required this.amount,
  });
  factory _PCostCenter.fromJson(Map<String, dynamic> j) => _PCostCenter(
    costcentre: j['costcentre'].toString(),
    qty: j['qty'].toString(),
    amount: double.tryParse(j['amount'].toString()) ?? 0,
  );
}

// ---------------------------------------------------------------------------
// Widget
// ---------------------------------------------------------------------------

/// Unified drill-down screen for the Party module.
/// Replaces all 16 PartyTotalClicked*.dart files (PartyTotalClickedRest is separate).
///
/// Pass optional lock params to indicate already-fixed dimensions:
///   [lockedItem]       – item filter already applied
///   [lockedCostcenter] – cost-centre filter already applied
///   [lockedVchname]    – voucher-type filter already applied
class PartyDrillDown extends StatefulWidget {
  final String startdate_string, enddate_string, type, ledger, total;
  final String? lockedItem;
  final String? lockedCostcenter;
  final String? lockedVchname;

  /// Ordered navigation history: each entry has 'type' and 'label' keys.
  final List<Map<String, String>> trail;

  const PartyDrillDown({
    required this.startdate_string,
    required this.enddate_string,
    required this.type,
    required this.ledger,
    required this.total,
    this.lockedItem,
    this.lockedCostcenter,
    this.lockedVchname,
    this.trail = const [],
  });

  @override
  _PartyDrillDownState createState() => _PartyDrillDownState();
}

class _PartyDrillDownState extends State<PartyDrillDown>
    with TickerProviderStateMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ScrollController _scrollFabController = ScrollController();
  late GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey;
  late SharedPreferences prefs;

  String? hostname, company, serial_no, company_lowercase, username;
  String HttpURL = '', token = '';
  String email = '', name = '';
  String? SecuritybtnAcessHolder;
  bool isDashEnable = true,
      isRolesEnable = true,
      isUserEnable = true,
      isRolesVisible = true,
      isUserVisible = true;

  late String _selectedgroup;
  bool _isLoading = false,
      _isSearchViewVisible = false,
      isSortVisible = false,
      showDateSort = false,
      isVisibleNoDataFound = false;
  String selectedSortOption = 'Default';
  String startdate_text = '', enddate_text = '';

  List<_PItem> item_list = [], filteredItems = [];
  List<_PBill> bills_list = [], filteredBills = [];
  List<_PVchType> vchtype_list = [], filteredVchtype = [];
  List<_PCostCenter> costcenter_list = [], filteredCostcenter = [];

  final TextEditingController searchController = TextEditingController();
  final ScrollController _scItems = ScrollController(),
      _scBills = ScrollController(),
      _scVchtype = ScrollController(),
      _scCostcenter = ScrollController();

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  List<String> get _availableGroups {
    final all = <String>['Items', 'Bills', 'Voucher Type', 'Cost Center'];
    if (widget.lockedItem != null) all.remove('Items');
    if (widget.lockedVchname != null) all.remove('Voucher Type');
    if (widget.lockedCostcenter != null) all.remove('Cost Center');
    return all;
  }

  Map<String, dynamic> _buildBody(String groupby, String orderby) {
    final body = <String, dynamic>{
      'startdate': widget.startdate_string,
      'enddate': widget.enddate_string,
      'party': widget.ledger,
      'vchtype': widget.type,
      'groupby': groupby,
      'orderby': orderby,
    };
    if (widget.lockedItem != null) body['item'] = widget.lockedItem;
    if (widget.lockedCostcenter != null)
      body['costcentre'] = widget.lockedCostcenter;
    if (widget.lockedVchname != null) body['vchname'] = widget.lockedVchname;
    return body;
  }

  String _formatCostCenter(String v) => v == 'null' ? '*Not Applicable' : v;
  String _convertDate(String s) =>
      DateFormat('dd-MMM-yyyy').format(DateTime.parse(s));
  String _formatAmount(double v) => formatAmount(v.toString());

  // ---------------------------------------------------------------------------
  // Fetch
  // ---------------------------------------------------------------------------

  void _clearLists() {
    item_list.clear();
    filteredItems.clear();
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
      case 'Items':
        groupby = orderby = 'Item';
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
            case 'Items':
              item_list.addAll(raw.map((j) => _PItem.fromJson(j)));
              filteredItems = List.from(item_list);
              break;
            case 'Bills':
              bills_list.addAll(raw.map((j) => _PBill.fromJson(j)));
              filteredBills = List.from(bills_list);
              break;
            case 'Voucher Type':
              vchtype_list.addAll(raw.map((j) => _PVchType.fromJson(j)));
              filteredVchtype = List.from(vchtype_list);
              break;
            case 'Cost Center':
              costcenter_list.addAll(raw.map((j) => _PCostCenter.fromJson(j)));
              filteredCostcenter = List.from(costcenter_list);
              break;
          }
        }
      }
    } catch (e) {
      debugPrint('PartyDrillDown fetch error: $e');
    }

    setState(() {
      _isLoading = false;
      final empty =
          item_list.isEmpty &&
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

  void _sortDefault() => setState(() {
    filteredItems = List.from(item_list);
    filteredBills = List.from(bills_list);
    filteredVchtype = List.from(vchtype_list);
    filteredCostcenter = List.from(costcenter_list);
  });

  void _sortAlphaAsc() => setState(() {
    filteredItems.sort((a, b) => a.item.compareTo(b.item));
    filteredBills.sort((a, b) => a.Partyledger.compareTo(b.Partyledger));
    filteredVchtype.sort((a, b) => a.vchname.compareTo(b.vchname));
    filteredCostcenter.sort((a, b) => a.costcentre.compareTo(b.costcentre));
  });

  void _sortAlphaDesc() => setState(() {
    filteredItems.sort((a, b) => b.item.compareTo(a.item));
    filteredBills.sort((a, b) => b.Partyledger.compareTo(a.Partyledger));
    filteredVchtype.sort((a, b) => b.vchname.compareTo(a.vchname));
    filteredCostcenter.sort((a, b) => b.costcentre.compareTo(a.costcentre));
  });

  void _sortDateAsc() => setState(() {
    filteredBills.sort((a, b) => a.vchdate.compareTo(b.vchdate));
  });
  void _sortDateDesc() => setState(() {
    filteredBills.sort((a, b) => b.vchdate.compareTo(a.vchdate));
  });

  void _sortAmountAsc() {
    final isSales = widget.type == 'Sales';
    setState(() {
      filteredItems.sort(
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
      filteredItems.sort(
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
    final options = [
      'Default',
      if (showDateSort) 'Newest to Oldest',
      if (showDateSort) 'Oldest to Newest',
      'A->Z',
      'Z->A',
      'Amount High to Low',
      'Amount Low to High',
    ];
    final icons = [
      Icons.sort_rounded,
      if (showDateSort) Icons.date_range_sharp,
      if (showDateSort) Icons.date_range_sharp,
      Icons.sort_by_alpha_rounded,
      Icons.sort_by_alpha_rounded,
      Icons.attach_money_outlined,
      Icons.attach_money_outlined,
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (_) => SizedBox(
        height: options.length * 50.0 + 80,
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
        filteredItems = List.from(item_list);
        filteredBills = List.from(bills_list);
        filteredVchtype = List.from(vchtype_list);
        filteredCostcenter = List.from(costcenter_list);
      } else {
        filteredItems = item_list
            .where((e) => e.item.toLowerCase().contains(q))
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
  // PDF / CSV
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
      case 'Items':
        headers = ['Item', 'Qty', 'Amount'];
        rows = item_list
            .map((e) => [e.item, e.qty, _formatAmount(e.amount)])
            .toList();
        break;
      case 'Bills':
        headers = ['Vch Date', 'Vch No', 'Amount'];
        rows = bills_list
            .map(
              (e) => [
                _convertDate(e.vchdate),
                e.vchno,
                _formatAmount(e.amount),
              ],
            )
            .toList();
        break;
      case 'Voucher Type':
        headers = ['Vch Name', 'Amount'];
        rows = vchtype_list
            .map((e) => [e.vchname, _formatAmount(e.amount)])
            .toList();
        break;
      default:
        headers = ['Cost Center', 'Amount'];
        rows = costcenter_list
            .map(
              (e) => [_formatCostCenter(e.costcentre), _formatAmount(e.amount)],
            )
            .toList();
    }

    const perPage = 12;
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
                'Party: ${widget.ledger}',
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
      case 'Items':
        csvData = [
          ['Item', 'Qty', 'Amount'],
          ...item_list.map((e) => [e.item, e.qty, _formatAmount(e.amount)]),
        ];
        break;
      case 'Bills':
        csvData = [
          ['Vch Date', 'Vch No', 'Amount'],
          ...bills_list.map(
            (e) => [_convertDate(e.vchdate), e.vchno, _formatAmount(e.amount)],
          ),
        ];
        break;
      case 'Voucher Type':
        csvData = [
          ['Vch Name', 'Amount'],
          ...vchtype_list.map((e) => [e.vchname, _formatAmount(e.amount)]),
        ];
        break;
      default:
        csvData = [
          ['Cost Center', 'Amount'],
          ...costcenter_list.map(
            (e) => [_formatCostCenter(e.costcentre), _formatAmount(e.amount)],
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

  Future<void> _initPrefs() async {
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
    _initPrefs();
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
      bottomNavigationBar: const AppBottomNav(activeTab: AppBottomNavTab.party),
      key: _scaffoldKey,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(52),
        child: AppBar(
          backgroundColor: app_color,
          elevation: 2,
          centerTitle: false,
          automaticallyImplyLeading: false,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
            onPressed: () => AppNavigation.backOrDashboard(context),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.type,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                widget.ledger,
                maxLines: 1,
                style: GoogleFonts.poppins(
                  color: Colors.white70,
                  fontSize: 12,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          actions: [
            IconButton(
              onPressed: () => setState(() {
                _isSearchViewVisible = !_isSearchViewVisible;
                if (!_isSearchViewVisible) {
                  searchController.clear();
                  _handleSearch('');
                }
              }),
              icon: const Icon(Icons.search, color: Colors.white, size: 22),
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
                    horizontal: 12,
                    vertical: 8,
                  ),
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
                      Center(
                        child: formatAmountRich(
                          widget.total,
                          style: GoogleFonts.poppins(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
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
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.calendar_month_rounded,
                              size: 16,
                              color: app_color,
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                '$startdate_text → $enddate_text',
                                style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12.5,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Breadcrumb trail
                      if (widget.trail.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        _buildBreadcrumb(),
                      ],
                      const SizedBox(height: 10),
                      Container(
                        height: 38,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context).brightness ==
                                  Brightness.dark
                              ? Colors.white.withOpacity(0.06)
                              : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.filter_alt_outlined,
                              size: 16,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Group by:',
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: _selectedgroup,
                                  isDense: true,
                                  dropdownColor: Theme.of(
                                    context,
                                  ).colorScheme.surface,
                                  borderRadius: BorderRadius.circular(14),
                                  style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
                                  ),
                                  icon: Icon(
                                    Icons.expand_more_rounded,
                                    size: 18,
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
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isSearchViewVisible) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                          child: SizedBox(
                            height: 46,
                            child: TextField(
                              controller: searchController,
                              onChanged: _handleSearch,
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
                    ],
                  ),
                ),
              ),
              _buildListSection(),
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
      'Item': Icons.inventory_2_rounded,
      'Vch Type': Icons.receipt_long_rounded,
      'Cost Center': Icons.business_center_rounded,
    };
    final crumbs = widget.trail
        .map(
          (e) => _PCrumb(
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

  // Returns a real sliver (SliverList) instead of a shrinkWrap ListView.builder
  // so the CustomScrollView only builds cards near the viewport - a
  // shrinkWrap+NeverScrollableScrollPhysics list forces eager layout of
  // every item up front, which hangs scrolling on large lists.
  Widget _buildListSection() {
    switch (_selectedgroup) {
      case 'Items':
        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate((_, i) {
              final item = filteredItems[i];
              return _buildCard(
                title: item.item,
                amount: item.amount,
                qty: item.qty,
                listType: 'Items',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PartyDrillDown(
                      startdate_string: widget.startdate_string,
                      enddate_string: widget.enddate_string,
                      type: widget.type,
                      total: item.amount.toString(),
                      ledger: widget.ledger,
                      lockedItem: item.item,
                      lockedCostcenter: widget.lockedCostcenter,
                      lockedVchname: widget.lockedVchname,
                      trail: [
                        ...widget.trail,
                        {'type': 'Item', 'label': item.item},
                      ],
                    ),
                  ),
                ),
              );
            }, childCount: filteredItems.length),
          ),
        );

      case 'Bills':
        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate((_, i) {
              final item = filteredBills[i];
              return _buildCard(
                title: item.vchno,
                amount: item.amount,
                date: item.vchdate,
                listType: 'Bills',
              );
            }, childCount: filteredBills.length),
          ),
        );

      case 'Voucher Type':
        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate((_, i) {
              final item = filteredVchtype[i];
              return _buildCard(
                title: item.vchname,
                amount: item.amount,
                listType: 'Voucher Type',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PartyDrillDown(
                      startdate_string: widget.startdate_string,
                      enddate_string: widget.enddate_string,
                      type: widget.type,
                      total: item.amount.toString(),
                      ledger: widget.ledger,
                      lockedItem: widget.lockedItem,
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
            }, childCount: filteredVchtype.length),
          ),
        );

      case 'Cost Center':
        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate((_, i) {
              final item = filteredCostcenter[i];
              return _buildCard(
                title: _formatCostCenter(item.costcentre),
                amount: item.amount,
                listType: 'Cost Center',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PartyDrillDown(
                      startdate_string: widget.startdate_string,
                      enddate_string: widget.enddate_string,
                      type: widget.type,
                      total: item.amount.toString(),
                      ledger: widget.ledger,
                      lockedItem: widget.lockedItem,
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
            }, childCount: filteredCostcenter.length),
          ),
        );

      default:
        return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
  }

  Widget _buildCard({
    required String title,
    required double amount,
    String? qty,
    String? date,
    required String listType,
    VoidCallback? onTap,
  }) {
    final isBills = listType == 'Bills';
    final icons = <String, IconData>{
      'Items': Icons.inventory_2_rounded,
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
                  child: Row(
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
                  child: formatAmountRich(
                    amount.toString(),
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
