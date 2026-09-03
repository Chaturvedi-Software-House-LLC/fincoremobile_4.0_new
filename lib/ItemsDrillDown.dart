import 'dart:io';
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
import 'constants.dart';
import 'package:FincoreGo/widgets/app_bottom_nav.dart';
import 'package:FincoreGo/widgets/app_navigation.dart';
import 'widgets/scroll_fab.dart';
import 'providers/items_drill_down_notifier.dart';

class _Crumb {
  final IconData icon;
  final String type;
  final String label;
  const _Crumb(this.icon, this.type, this.label);
}

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

class DrillLedger {
  final String Partyledger, qty;
  final double amount;
  DrillLedger({
    required this.Partyledger,
    required this.qty,
    required this.amount,
  });
  factory DrillLedger.fromJson(Map<String, dynamic> j) => DrillLedger(
    Partyledger: j['Partyledger'].toString(),
    qty: j['qty'].toString(),
    amount: double.tryParse(j['amount'].toString()) ?? 0,
  );
}

class DrillBill {
  final String vchno, Partyledger, vchdate;
  final double amount;
  DrillBill({
    required this.vchno,
    required this.Partyledger,
    required this.vchdate,
    required this.amount,
  });
  factory DrillBill.fromJson(Map<String, dynamic> j) => DrillBill(
    vchno: j['vchno'].toString(),
    Partyledger: j['Partyledger'].toString(),
    vchdate: j['vchdate'].toString(),
    amount: double.tryParse(j['amount'].toString()) ?? 0,
  );
}

class DrillVchType {
  final String vchname, qty;
  final double amount;
  DrillVchType({
    required this.vchname,
    required this.qty,
    required this.amount,
  });
  factory DrillVchType.fromJson(Map<String, dynamic> j) => DrillVchType(
    vchname: j['vchname'].toString(),
    qty: j['qty'].toString(),
    amount: double.tryParse(j['amount'].toString()) ?? 0,
  );
}

class DrillCostCenter {
  final String costcentre, qty;
  final double amount;
  DrillCostCenter({
    required this.costcentre,
    required this.qty,
    required this.amount,
  });
  factory DrillCostCenter.fromJson(Map<String, dynamic> j) => DrillCostCenter(
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
class ItemsDrillDown extends ConsumerStatefulWidget {
  final String startdate_string, enddate_string, type, item_name, total;
  final int? stockItemMasterId;
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
    this.stockItemMasterId,
    this.lockedLedger,
    this.lockedCostcenter,
    this.lockedVchname,
    this.trail = const [],
  });

  @override
  ConsumerState<ItemsDrillDown> createState() => _ItemsDrillDownState();
}

class _ItemsDrillDownState extends ConsumerState<ItemsDrillDown> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ScrollController _scrollFabController = ScrollController();

  final TextEditingController searchController = TextEditingController();

  late String startdate_text, enddate_text;

  ItemsDrillDownArgs get _args => ItemsDrillDownArgs(
        startDateString: widget.startdate_string,
        endDateString: widget.enddate_string,
        type: widget.type,
        itemName: widget.item_name,
        stockItemMasterId: widget.stockItemMasterId,
        lockedLedger: widget.lockedLedger,
        lockedCostcenter: widget.lockedCostcenter,
        lockedVchname: widget.lockedVchname,
      );

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  String _formatCostCenter(String v) => v == 'null' ? '*Not Applicable' : v;

  String _convertDate(String dateStr) =>
      DateFormat('dd-MMM-yyyy').format(DateTime.parse(dateStr));

  String _formatAmount(double v) => formatAmount(v.toString());

  // ---------------------------------------------------------------------------
  // Sort
  // ---------------------------------------------------------------------------

  void _showSortSheet(ItemsDrillDownState state) {
    final icons = [
      Icons.sort_rounded,
      if (state.showDateSort) Icons.date_range_sharp,
      if (state.showDateSort) Icons.date_range_sharp,
      Icons.sort_by_alpha_rounded,
      Icons.sort_by_alpha_rounded,
      Icons.attach_money_outlined,
      Icons.attach_money_outlined,
    ];
    final options = [
      'Default',
      if (state.showDateSort) 'Newest to Oldest',
      if (state.showDateSort) 'Oldest to Newest',
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
                    ref
                        .read(itemsDrillDownNotifierProvider(_args).notifier)
                        .selectSortOption(options[i]);
                    Navigator.pop(ctx);
                  },
                  child: ListTile(
                    leading: Icon(icons[i]),
                    title: Text(
                      options[i],
                      style: GoogleFonts.poppins(
                        fontWeight: options[i] == state.selectedSortOption
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    trailing: options[i] == state.selectedSortOption
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

  // ---------------------------------------------------------------------------
  // PDF / CSV Export
  // ---------------------------------------------------------------------------

  Future<void> _shareAsPDF(ItemsDrillDownState state) async {
    final font = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans.ttf'),
    );
    final pdf = pw.Document();
    final reportname = '${state.selectedGroup} Wise ${widget.type} Summary';

    List<String> headers;
    List<List<String>> rows;

    switch (state.selectedGroup) {
      case 'Ledger':
        headers = ['Party Name', 'Qty', 'Amount'];
        rows = state.ledgerList
            .map((e) => [e.Partyledger, e.qty, _formatAmount(e.amount)])
            .toList();
        break;
      case 'Bills':
        headers = ['Vch Date', 'Vch No', 'Party Name', 'Amount'];
        rows = state.billsList
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
        rows = state.vchtypeList
            .map((e) => [e.vchname, e.qty, _formatAmount(e.amount)])
            .toList();
        break;
      default:
        headers = ['Cost Center', 'Qty', 'Amount'];
        rows = state.costcenterList
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
                state.company,
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
        text:
            'Sharing ${state.selectedGroup} wise ${widget.type} Report of ${state.company}',
        files: [XFile(path)],
      ),
    );
  }

  Future<void> _shareAsCSV(ItemsDrillDownState state) async {
    List<List<dynamic>> csvData;
    switch (state.selectedGroup) {
      case 'Ledger':
        csvData = [
          ['Party Name', 'Qty', 'Amount'],
          ...state.ledgerList.map(
            (e) => [e.Partyledger, e.qty, _formatAmount(e.amount)],
          ),
        ];
        break;
      case 'Bills':
        csvData = [
          ['Vch Date', 'Vch No', 'Party Name', 'Amount'],
          ...state.billsList.map(
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
          ...state.vchtypeList.map(
            (e) => [e.vchname, e.qty, _formatAmount(e.amount)],
          ),
        ];
        break;
      default:
        csvData = [
          ['Cost Center', 'Qty', 'Amount'],
          ...state.costcenterList.map(
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
        text:
            'Sharing ${state.selectedGroup} wise ${widget.type} Report of ${state.company}',
        files: [XFile(path)],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    startdate_text = _convertDate(widget.startdate_string);
    enddate_text = _convertDate(widget.enddate_string);
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
    final state = ref.watch(itemsDrillDownNotifierProvider(_args));
    return Scaffold(
      bottomNavigationBar: const AppBottomNav(activeTab: AppBottomNavTab.items),
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
                widget.item_name,
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
              onPressed: () {
                final notifier = ref.read(
                  itemsDrillDownNotifierProvider(_args).notifier,
                );
                notifier.toggleSearchView();
                if (state.isSearchViewVisible) {
                  searchController.clear();
                }
              },
              icon: const Icon(Icons.search, color: Colors.white, size: 22),
            ),
            // Sort in the app bar, matching standard Material/iOS
            // placement - see PartyDrillDown.dart's identical fix for why
            // the floating pill it replaces was a poor pattern.
            IconButton(
              onPressed: state.isSortVisible
                  ? () => _showSortSheet(state)
                  : null,
              icon: Icon(
                Icons.sort_rounded,
                color: state.isSortVisible ? Colors.white : Colors.white38,
                size: 22,
              ),
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
                          _shareAsPDF(state);
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
                          _shareAsCSV(state);
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
                      // Group-by dropdown
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 5,
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
                                  value: state.selectedGroup,
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
                                    ref
                                        .read(
                                          itemsDrillDownNotifierProvider(
                                            _args,
                                          ).notifier,
                                        )
                                        .selectGroup(v);
                                  },
                                  items: _args.availableGroups
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
                      if (state.isSearchViewVisible) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                          child: SizedBox(
                            height: 46,
                            child: TextField(
                              controller: searchController,
                              onChanged: (value) => ref
                                  .read(
                                    itemsDrillDownNotifierProvider(
                                      _args,
                                    ).notifier,
                                  )
                                  .filter(value),
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
                      _buildListSection(state),
                    ],
                  ),
                ),
              ),
            ],
          ),

          if (state.isLoading)
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

  // Skeleton stand-in for the summary card + detail list while the initial
  // fetch is in flight - replaces the old dimmed spinner-over-stale-content
  // overlay so the loading state reads as "content incoming" instead of a
  // blank/frozen page. Generic (icon + 2 text lines + amount) rather than
  // mirroring every row variant on this screen, since the shape is close
  // enough for the transition to feel seamless.
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

  // ---------------------------------------------------------------------------
  // List section
  // ---------------------------------------------------------------------------

  // Matches the "No Records Found" empty state used elsewhere in the app
  // (PartyClicked.dart, Transactions.dart) - rendered inline where the
  // list would otherwise go, instead of floating as an unpositioned Stack
  // overlay (which left a large dead white area between the message and
  // the bottom nav).
  Widget _buildEmptyState() {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.4,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 48,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'No Records Found',
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListSection(ItemsDrillDownState state) {
    if (state.isVisibleNoDataFound) return _buildEmptyState();
    switch (state.selectedGroup) {
      case 'Ledger':
        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: state.filteredLedger.length,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          itemBuilder: (_, i) {
            final item = state.filteredLedger[i];
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
                    total: item.amount.toString(),
                    item_name: widget.item_name,
                    stockItemMasterId: widget.stockItemMasterId,
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
          itemCount: state.filteredBills.length,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          itemBuilder: (_, i) {
            final item = state.filteredBills[i];
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
          itemCount: state.filteredVchtype.length,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          itemBuilder: (_, i) {
            final item = state.filteredVchtype[i];
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
                    total: item.amount.toString(),
                    item_name: widget.item_name,
                    stockItemMasterId: widget.stockItemMasterId,
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
          itemCount: state.filteredCostcenter.length,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          itemBuilder: (_, i) {
            final item = state.filteredCostcenter[i];
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
                    total: item.amount.toString(),
                    item_name: widget.item_name,
                    stockItemMasterId: widget.stockItemMasterId,
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
