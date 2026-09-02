import 'dart:io';
import 'package:FincoreGo/ItemsDrillDown.dart';
import 'package:FincoreGo/currencyFormat.dart';
import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'CompanySelectTallyOauth.dart';
import 'constants.dart';
import 'package:FincoreGo/widgets/app_bottom_nav.dart';
import 'package:FincoreGo/widgets/app_navigation.dart';
import 'package:FincoreGo/widgets/entry_widgets.dart';
import 'providers/items_clicked_notifier.dart';

class Sale_Purc {
  final String month, amount;

  Sale_Purc({required this.month, required this.amount});

  factory Sale_Purc.fromJson(Map<String, dynamic> json) {
    return Sale_Purc(
      month: json['mname'].toString(),
      amount: json['amount'].toString(),
    );
  }
}

class ItemsClicked extends ConsumerStatefulWidget {
  final String itemname,
      unit,
      item_desc,
      item_lastsaledate,
      item_lastpurchdate,
      item_rate,
      inventory_closing,
      lastpurcrate,
      alias;
  /// The stock item's tally-api `masterId` - `stockItemSummary`/
  /// `stockItemMovement` are both masterId-keyed.
  final int? stockItemMasterId;
  const ItemsClicked({
    required this.itemname,
    required this.unit,
    required this.item_desc,
    required this.item_lastsaledate,
    required this.item_lastpurchdate,
    required this.item_rate,
    required this.inventory_closing,
    required this.lastpurcrate,
    required this.alias,
    this.stockItemMasterId,
  });
  @override
  ConsumerState<ItemsClicked> createState() => _ItemsClickedPageState(
    itemname: itemname,
    unit: unit,
    item_desc: item_desc,
    item_lastsaledate: item_lastsaledate,
    item_lastpurchdate: item_lastpurchdate,
    item_rate: item_rate,
    inventory_closing: inventory_closing,
    lastpurcrate: lastpurcrate,
    alias: alias,
    stockItemMasterId: stockItemMasterId,
  );
}

class _ItemsClickedPageState extends ConsumerState<ItemsClicked>
    with TickerProviderStateMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  String itemname = "",
      unit = "",
      item_desc = "",
      item_lastsaledate = "",
      item_lastpurchdate = "",
      item_rate = "",
      inventory_closing = "",
      lastpurcrate = "",
      alias = "";
  int? stockItemMasterId;

  List<String> date_range = [
    'Today',
    'Yesterday',
    'This Month',
    'Last Month',
    'This Year',
    'Last Year',
    'Year To Date',
    'Custom Date',
  ];

  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now().add(Duration(days: 7));

  _ItemsClickedPageState({
    required this.itemname,
    required this.unit,
    required this.item_desc,
    required this.item_lastsaledate,
    required this.item_lastpurchdate,
    required this.item_rate,
    required this.inventory_closing,
    required this.lastpurcrate,
    required this.alias,
    this.stockItemMasterId,
  });

  late final _args = ItemsClickedArgs(
    itemDesc: item_desc,
    itemLastSaleDate: item_lastsaledate,
    itemLastPurchDate: item_lastpurchdate,
    itemRate: item_rate,
    lastPurcRate: lastpurcrate,
    alias: alias,
    stockItemMasterId: stockItemMasterId,
  );

  ItemsClickedNotifier get _notifier =>
      ref.read(itemsClickedNotifierProvider(_args).notifier);
  ItemsClickedState get _s => ref.read(itemsClickedNotifierProvider(_args));

  String formatRate(String value, {int decimals = 2}) =>
      _notifier.formatRate(value, decimals: decimals);

  String formatBackendValue(String value, {int decimals = 2}) =>
      _notifier.formatBackendValue(value, decimals: decimals);

  String convertDateFormat(String dateStr) =>
      _notifier.convertDateFormat(dateStr);

  String formatTotal(dynamic amount, {int decimals = 2}) =>
      _notifier.formatTotal(amount, decimals: decimals);

  Future<void> _selectDateRange(BuildContext context) async {
    if (!_s.isTextEnabled) return;
    final initialDateRange = DateTimeRange(start: _startDate, end: _endDate);
    final earliestDate = DateTime.parse(_s.startFrom!);

    final selectedDateRange = await showDateRangePicker(
      context: context,
      initialDateRange: initialDateRange,
      firstDate: earliestDate,
      lastDate: DateTime(2100),
      builder: (BuildContext context, Widget? child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: app_color,
              onPrimary: Colors.white,
              surface: Theme.of(context).colorScheme.surface,
              onSurface: Theme.of(context).colorScheme.onSurface,
            ),
            datePickerTheme: DatePickerThemeData(
              rangeSelectionBackgroundColor: app_color.withOpacity(0.15),
              rangeSelectionOverlayColor: MaterialStatePropertyAll(
                app_color.withOpacity(0.15),
              ),
            ),
          ),
          child: child!,
        );
      },
    );

    if (selectedDateRange != null) {
      setState(() {
        _startDate = selectedDateRange.start;
        _endDate = selectedDateRange.end;
      });
      _notifier.setCustomDateRange(selectedDateRange.start, selectedDateRange.end);
    }
  }

  Future<void> _selectDateRange_auto(BuildContext context) async {
    if (!_s.isTextEnabled) return;
    final initialDateRange = DateTimeRange(start: _startDate, end: _endDate);
    final earliestDate = DateTime.parse(_s.startFrom!);

    final selectedDateRange = await showDateRangePicker(
      context: context,
      initialDateRange: initialDateRange,
      firstDate: earliestDate,
      lastDate: DateTime(2100),
      builder: (BuildContext context, Widget? child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: app_color,
              onPrimary: Colors.white,
              surface: Theme.of(context).colorScheme.surface,
              onSurface: Theme.of(context).colorScheme.onSurface,
            ),
            datePickerTheme: DatePickerThemeData(
              rangeSelectionBackgroundColor: app_color.withOpacity(0.15),
              rangeSelectionOverlayColor: MaterialStatePropertyAll(
                app_color.withOpacity(0.15),
              ),
            ),
          ),
          child: child!,
        );
      },
    );

    if (selectedDateRange == null) return;
    setState(() {
      _startDate = selectedDateRange.start;
      _endDate = selectedDateRange.end;
    });
    _notifier.setCustomDateRange(selectedDateRange.start, selectedDateRange.end);
  }

  void _handleDate(String value) {
    _notifier.handleDate(value);
    if (value == 'Custom Date') {
      _selectDateRange_auto(context);
    }
  }

  void showToast(String message) {
    showAppMessage(context, message);
  }

  Future<void> generateAndShareCSV_ItemDetail() async {
    final vm = _s;
    final List<List<dynamic>> csvData = [];
    csvData.add(['Item Name', itemname]);
    // alias/inventory_closing can come back as the literal string "null"
    // from the API (not Dart null) - isItemAliasVisible already guards
    // against that for alias; inventory_closing gets the same guard here.
    if (vm.isItemAliasVisible) csvData.add(['Alias', alias]);
    csvData.add([
      'Inventory Closing',
      inventory_closing == 'null' ? '0' : inventory_closing,
    ]);
    csvData.add([]);

    if (vm.salesSummaryVisible && vm.listSale.isNotEmpty) {
      csvData.add(['Sales Summary']);
      csvData.add(['Month', 'Amount']);
      for (final row in vm.listSale) {
        csvData.add([row.month, formatAmount(row.amount)]);
      }
      csvData.add([]);
    }

    if (vm.purchaseSummaryVisible && vm.listPurchase.isNotEmpty) {
      csvData.add(['Purchase Summary']);
      csvData.add(['Month', 'Amount']);
      for (final row in vm.listPurchase) {
        csvData.add([row.month, formatAmount(row.amount)]);
      }
    }

    final csvString = const ListToCsvConverter().convert(csvData);
    final tempDir = await Directory.systemTemp.createTemp();
    final tempFilePath = '${tempDir.path}/${itemname}_Detail.csv';
    final file = File(tempFilePath);
    await file.writeAsString(csvString);

    await SharePlus.instance.share(
      ShareParams(
        text: 'Sharing $itemname Detail Report of ${vm.company}',
        files: [XFile(tempFilePath)],
      ),
    );
  }

  Future<void> generateAndSharePDF_ItemDetail() async {
    final vm = _s;
    final font = pw.Font.ttf(
      await rootBundle.load("assets/fonts/NotoSans.ttf"),
    );
    final pdf = pw.Document();
    final companyName = vm.company;

    pw.Widget buildSummaryTable(String title, List<Sale_Purc> list) {
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(height: 14),
          pw.Text(
            title,
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, font: font),
          ),
          pw.SizedBox(height: 6),
          pw.Table.fromTextArray(
            border: pw.TableBorder.all(width: 1),
            headerDecoration: pw.BoxDecoration(
              borderRadius: pw.BorderRadius.circular(2),
              color: PdfColors.grey300,
            ),
            headerHeight: 26,
            cellAlignment: pw.Alignment.center,
            cellPadding: const pw.EdgeInsets.all(5),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: font),
            cellStyle: pw.TextStyle(fontSize: 11, font: font),
            headers: ['Month', 'Amount'],
            data: list
                .map((row) => [row.month, formatAmount(row.amount)])
                .toList(),
          ),
        ],
      );
    }

    pdf.addPage(
      pw.Page(
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Center(
              child: pw.Text(
                companyName,
                style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, font: font),
              ),
            ),
            pw.SizedBox(height: 10),
            pw.Center(
              child: pw.Text(
                itemname,
                style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, font: font),
              ),
            ),
            if (vm.isItemAliasVisible)
              pw.Center(
                child: pw.Text(
                  alias,
                  style: pw.TextStyle(fontSize: 11, font: font),
                ),
              ),
            pw.SizedBox(height: 4),
            pw.Text(
              'Inventory Closing: ${inventory_closing == 'null' ? '0' : inventory_closing}',
              style: pw.TextStyle(fontSize: 11, font: font),
            ),
            if (vm.salesSummaryVisible && vm.listSale.isNotEmpty)
              buildSummaryTable('Sales Summary', vm.listSale),
            if (vm.purchaseSummaryVisible && vm.listPurchase.isNotEmpty)
              buildSummaryTable('Purchase Summary', vm.listPurchase),
          ],
        ),
      ),
    );

    final pdfData = await pdf.save();
    final tempDir = await getTemporaryDirectory();
    final tempFilePath = '${tempDir.path}/${itemname}_Detail.pdf';
    final file = File(tempFilePath);
    await file.writeAsBytes(pdfData);

    await SharePlus.instance.share(
      ShareParams(
        text: 'Sharing $itemname Detail Report of ${vm.company}',
        files: [XFile(tempFilePath)],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(itemsClickedNotifierProvider(_args));
    final vm = _s;
    return Scaffold(
      bottomNavigationBar: const AppBottomNav(activeTab: AppBottomNavTab.items),
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
          title: GestureDetector(
            onTap: () => navigateToCompanySwitch(context),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    vm.company,
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
          centerTitle: true,
          actions: [
            IconButton(
              icon: Icon(Icons.share_outlined, color: Colors.white, size: 24),
              onPressed: () {
                final RenderBox button =
                    context.findRenderObject() as RenderBox;
                final RenderBox overlay =
                    Overlay.of(context).context.findRenderObject()
                        as RenderBox;
                final Offset buttonPosition = button.localToGlobal(
                  Offset.zero,
                  ancestor: overlay,
                );

                showMenu(
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
                          if (vm.listSale.isNotEmpty || vm.listPurchase.isNotEmpty) {
                            generateAndSharePDF_ItemDetail();
                          } else {
                            showToast('Data Not Found');
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
                              style: TextStyle(
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
                          if (vm.listSale.isNotEmpty || vm.listPurchase.isNotEmpty) {
                            generateAndShareCSV_ItemDetail();
                          } else {
                            showToast('Data Not Found');
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
                              style: TextStyle(
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
            ),
          ],
        ),
      ),
      body: vm.isLoading
          ? _buildSkeletonItemDetail()
          : ListView(
              padding: EdgeInsets.only(left: 16, right: 16, bottom: 12, top: 8),
              children: [
                if (vm.isDateVisible) _buildDateSelector(context),
                if (vm.isDateVisible) SizedBox(height: 8),

                _buildItemOverviewCard(),

                if (vm.salesSummaryVisible || vm.purchaseSummaryVisible)
                  SizedBox(height: 8),
                if (vm.salesSummaryVisible)
                  _buildSummaryCard(context, isSales: true),
                if (vm.purchaseSummaryVisible)
                  _buildSummaryCard(context, isSales: false),
              ],
            ),
    );
  }

  // Skeleton stand-in for the item overview card + sales/purchase summary
  // cards while the initial fetch is in flight - mirrors
  // _buildItemOverviewCard/_buildSummaryCard's rough layout (icon badge +
  // text rows) at a placeholder level so the transition into real content
  // doesn't visibly jump. Replaces the old centered AppLogoLoader spinner.
  Widget _buildSkeletonItemDetail() {
    Widget skeletonRow() {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
        child: Row(
          children: [
            const ShimmerBox(width: 34, height: 34, borderRadius: 12),
            const SizedBox(width: 14),
            Expanded(child: const ShimmerBox(height: 13)),
            const SizedBox(width: 12),
            const ShimmerBox(width: 60, height: 13),
          ],
        ),
      );
    }

    Widget skeletonCard({int rows = 3}) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 0),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black12.withOpacity(0.08),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const ShimmerBox(width: 34, height: 34, borderRadius: 12),
                  const SizedBox(width: 10),
                  Expanded(child: const ShimmerBox(height: 16, width: 140)),
                ],
              ),
              const SizedBox(height: 12),
              for (int i = 0; i < rows; i++) skeletonRow(),
            ],
          ),
        ),
      );
    }

    return ShimmerLoading(
      child: ListView(
        padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12, top: 8),
        children: [
          skeletonCard(rows: 4),
          const SizedBox(height: 8),
          skeletonCard(rows: 3),
          const SizedBox(height: 8),
          skeletonCard(rows: 3),
        ],
      ),
    );
  }

  Widget _buildItemOverviewCard() {
    final vm = _s;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 0),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Theme.of(context).brightness == Brightness.dark
            ? Border.all(color: Colors.white.withOpacity(0.10), width: 1)
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black12.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            /// 🔹 Item Name
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.blue.shade400, Colors.cyan.shade600],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.blue.withOpacity(0.3),
                        blurRadius: 6,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.shopping_bag_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    itemname,
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            /// 🔹 Alias
            if (vm.isItemAliasVisible) ...[
              Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.transparent
                      : Colors.grey.shade50.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    // 🔹 Gradient Icon Badge
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.indigo.shade400,
                            Colors.deepPurple.shade600,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.indigo.withOpacity(0.3),
                            blurRadius: 6,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.badge_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),

                    const SizedBox(width: 14),

                    // 🔹 Alias Value
                    Expanded(
                      child: Text(
                        alias,
                        style: GoogleFonts.poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            /// 🔹 Inventory
            Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.transparent
                    : Colors.grey.shade50.withOpacity(0.6),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  // 🔹 Gradient Icon Badge
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.orangeAccent.shade200,
                          Colors.deepOrange.shade400,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.orangeAccent.withOpacity(0.3),
                          blurRadius: 6,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.inventory_2_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 14),

                  // 🔹 Label
                  Expanded(
                    child: Text(
                      "Inventory Closing",
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),

                  // 🔹 Value
                  Text(
                    inventory_closing == 'null' ? '0' : inventory_closing,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),

            /// 🔹 Description
            if (vm.isItemDescVisible) ...[
              const Divider(height: 28, thickness: 0.5),

              // 🔹 Title Row with Gradient Badge
              Container(
                margin: const EdgeInsets.symmetric(vertical: 2),
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.transparent
                      : Colors.grey.shade50.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.blueGrey.shade400,
                            Colors.blueGrey.shade700,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.blueGrey.withOpacity(0.3),
                            blurRadius: 6,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.description_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Text(
                      "Description",
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // 🔹 Description Text
              Text(
                item_desc,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDateSelector(BuildContext context) {
    final vm = _s;
    final tintColor = Theme.of(context).brightness == Brightness.dark
        ? Colors.white.withOpacity(0.06)
        : Colors.grey.shade100;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Theme.of(context).brightness == Brightness.dark
            ? Border.all(color: Colors.white.withOpacity(0.10), width: 1)
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black12.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          /// Dropdown
          Container(
            width: double.infinity,
            height: 38,
            padding: EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: tintColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                isDense: true,
                value: vm.selectedDate,
                icon: Icon(
                  Icons.expand_more,
                  size: 18,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                style: GoogleFonts.poppins(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
                dropdownColor: Theme.of(context).colorScheme.surface,
                onChanged: (String? val) {
                  if (val != null) _handleDate(val);
                },
                items: date_range.map((e) {
                  return DropdownMenuItem<String>(value: e, child: Text(e));
                }).toList(),
              ),
            ),
          ),

          SizedBox(height: 8),

          /// Date Range Display (Clickable)
          InkWell(
            onTap: () => _selectDateRange(context),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: BoxDecoration(
                color: tintColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.calendar_month_rounded, size: 15, color: app_color),
                  SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      "${vm.startDateText} → ${vm.endDateText}",
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600,
                        fontSize: 12.5,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      softWrap: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthlyList(
    BuildContext context,
    List<Sale_Purc> list,
    bool isSales,
  ) {
    final vm = _s;
    return Column(
      children: list
          .map((card) {
            final month = card.month;
            final parsedAmount = double.tryParse(card.amount);
            DateTime? parsedDate;
            try {
              parsedDate = DateFormat('MMMM yyyy').parse(month);
            } catch (_) {
              parsedDate = null;
            }
            // Skip entries the backend sent with an unparseable amount/month
            // instead of throwing and crashing the whole list.
            if (parsedAmount == null || parsedDate == null) {
              return const SizedBox.shrink();
            }
            final amount = parsedAmount.toStringAsFixed(vm.decimal);
            final date = parsedDate;
            final startOfMonth = DateFormat(
          'yyyyMMdd',
        ).format(DateTime(date.year, date.month, 1));
        final endOfMonth = DateFormat(
          'yyyyMMdd',
        ).format(DateTime(date.year, date.month + 1, 0));
        final vchtype = isSales ? 'Sales' : 'Purchase';

        return InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ItemsDrillDown(
                  startdate_string: startOfMonth,
                  enddate_string: endOfMonth,
                  type: vchtype,
                  total: amount,
                  item_name: itemname,
                  stockItemMasterId: stockItemMasterId,
                ),
              ),
            );
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            margin: EdgeInsets.symmetric(vertical: 6),
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,

              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.orange.withOpacity(0.3),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                // 🔹 Gradient Icon Badge
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.orange.withOpacity(0.6), Colors.orange],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.orange.withOpacity(0.25),
                        blurRadius: 6,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.calendar_month_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),

                const SizedBox(width: 14),

                // 🔹 Month Name
                Expanded(
                  child: Text(
                    month,
                    style: GoogleFonts.poppins(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),

                // 🔹 Amount with arrow
                currencyAmountText(
                  currencyCode: vm.currencyCode,
                  symbol: vm.currencySymbol,
                  amountText: formatTotal(amount, decimals: vm.decimal),
                  style: GoogleFonts.poppins(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),

                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget buildSectionTitle(IconData icon, String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [app_color.withOpacity(0.7), app_color],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: app_color.withOpacity(0.3),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Icon(icon, size: 20, color: Colors.white),
          ),
          const SizedBox(width: 10),
          Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  // Matches _buildSummaryMetric's value Text style (fontSize 14, w700,
  // onSurface) so the Dirham glyph swap-in is visually seamless.
  Widget _summaryCurrencyValue(String amountText) {
    return currencyAmountText(
      currencyCode: _s.currencyCode,
      symbol: _s.currencySymbol,
      amountText: amountText,
      style: GoogleFonts.poppins(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: Theme.of(context).colorScheme.onSurface,
      ),
    );
  }

  Widget _buildSummaryMetric(String label, String value, {Widget? valueWidget}) {
    IconData icon = Icons.info;
    LinearGradient gradient = LinearGradient(
      colors: [Colors.grey.shade400, Colors.grey.shade600],
    );

    final labelLower = label.toLowerCase();

    if (labelLower.contains('total net')) {
      icon = Icons.attach_money_rounded;
      gradient = LinearGradient(
        colors: [Colors.green.shade400, Colors.green.shade700],
      );
    } else if (labelLower.contains('last') && labelLower.contains('date')) {
      icon = Icons.event;
      gradient = LinearGradient(
        colors: [Colors.indigo.shade400, Colors.indigo.shade700],
      );
    } else if (labelLower.contains('last') && labelLower.contains('price')) {
      icon = Icons.price_change_rounded;
      gradient = LinearGradient(
        colors: [Colors.orange.shade400, Colors.deepOrange.shade600],
      );
    } else if (labelLower.contains('qty')) {
      icon = Icons.numbers_rounded;
      gradient = LinearGradient(
        colors: [Colors.blueGrey.shade400, Colors.blueGrey.shade700],
      );
    } else if (labelLower.contains('min rate')) {
      icon = Icons.trending_down_rounded;
      gradient = LinearGradient(
        colors: [Colors.red.shade400, Colors.red.shade700],
      );
    } else if (labelLower.contains('max rate')) {
      icon = Icons.trending_up_rounded;
      gradient = LinearGradient(
        colors: [Colors.teal.shade400, Colors.teal.shade700],
      );
    } else if (labelLower.contains('invoices')) {
      icon = Icons.receipt_long_rounded;
      gradient = LinearGradient(
        colors: [Colors.deepPurple.shade400, Colors.deepPurple.shade700],
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? Colors.transparent
            : Colors.grey.shade50.withOpacity(0.6),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          // 🔹 Icon Badge with gradient
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              gradient: gradient,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black12.withOpacity(0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 14),

          // 🔹 Label
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),

          // 🔹 Value
          valueWidget ??
              Text(
                value,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(BuildContext context, {required bool isSales}) {
    final vm = _s;
    final title = isSales ? 'SALES SUMMARY' : 'PURCHASE SUMMARY';
    final icon = isSales
        ? Icons.trending_up_rounded
        : Icons.shopping_cart_outlined;
    final total = _formatIntValue(
      isSales ? vm.salesTotalNetSales : vm.purchaseTotalNetPurchase,
    );
    final lastDate = _formatValue(
      isSales ? vm.salesLastSaleDate : vm.purchaseLastPurchaseDate,
    );
    final lastPrice = _formatIntValue(
      isSales ? vm.salesLastSalePrice : vm.purchaseLastPurchasePrice,
    );

    print('last $isSales price $lastPrice');
    final qty = _formatValue(
      isSales ? vm.salesTotalSalesQty : vm.purchaseTotalPurchaseQty,
    );
    final minRate =
        _formatIntValue(isSales ? vm.salesMinRate : vm.purchaseMinRate);
    final maxRate =
        _formatIntValue(isSales ? vm.salesMaxRate : vm.purchaseMaxRate);
    final invoices = _formatValue(
      isSales ? vm.salesNoOfInvoices : vm.purchaseNoOfInvoices,
    );
    final listData = isSales ? vm.listSale : vm.listPurchase;
    final isClickable = isSales
        ? vm.isSalesClickableCard
        : vm.isPurchaseClickableCard;
    final isExpanded =
        isSales ? vm.isClickedSalesIcon : vm.isClickedPurchaseIcon;
    final isVisible =
        isSales ? vm.isVisibleSalesList : vm.isVisiblePurchaseList;
    final hasData =
        (isSales ? vm.salesNoOfInvoices : vm.purchaseNoOfInvoices) !=
        'Not Available';

    if (!hasData) {
      return _buildSummaryEmptyState(title, icon, isSales);
    }

    return Container(
      margin: EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Theme.of(context).brightness == Brightness.dark
            ? Border.all(color: Colors.white.withOpacity(0.10), width: 1)
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black12.withOpacity(0.08),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            /// Title Row
            buildSectionTitle(Icons.analytics_rounded, title),

            SizedBox(height: 16),

            /// Data Rows
            _buildSummaryMetric(
              'Total Net ${isSales ? 'Sales' : 'Purchase'}',
              '',
              valueWidget: _summaryCurrencyValue(total),
            ),
            _buildSummaryMetric(
              'Last ${isSales ? 'Sale' : 'Purchase'} Date',
              lastDate,
            ),
            _buildSummaryMetric(
              'Last ${isSales ? 'Sale' : 'Purchase'} Price',
              '',
              valueWidget: _summaryCurrencyValue(lastPrice),
            ),
            _buildSummaryMetric(
              'Total ${isSales ? 'Sale' : 'Purchase'} Qty',
              qty,
            ),
            _buildSummaryMetric(
              'Min Rate',
              '',
              valueWidget: _summaryCurrencyValue(minRate),
            ),
            _buildSummaryMetric(
              'Max Rate',
              '',
              valueWidget: _summaryCurrencyValue(maxRate),
            ),
            _buildSummaryMetric('No of Invoices', invoices),

            Divider(height: 18),

            /// Expand Section Header
            InkWell(
              onTap: () {
                if (isClickable) {
                  if (isSales) {
                    _notifier.toggleSalesExpanded();
                  } else {
                    _notifier.togglePurchaseExpanded();
                  }
                }
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.orange.withOpacity(0.3),
                    width: 0.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.orange.withOpacity(0.05),
                      blurRadius: 8,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    // 🔹 Gradient Icon Badge
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.orange.withOpacity(0.6),
                            Colors.orange,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.orange.withOpacity(0.25),
                            blurRadius: 6,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.calendar_month_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),

                    const SizedBox(width: 14),

                    // 🔹 Title
                    Expanded(
                      child: Text(
                        'Month Wise ${isSales ? 'Sales' : 'Purchase'}',
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),

                    SizedBox(width: 4),

                    // 🔹 Total value
                    currencyAmountText(
                      currencyCode: vm.currencyCode,
                      symbol: vm.currencySymbol,
                      amountText: total,
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(width: 8),

                    // 🔹 Expand/Collapse Icon with subtle bg
                    Icon(
                      isExpanded ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),

            /// Expanded Monthly List
            if (isVisible)
              AnimatedContainer(
                duration: Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                child: Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: _buildMonthlyList(context, listData, isSales),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // 🔹 Shown instead of the full metrics list when there's no Sales/Purchase
  // data for the selected period, so the card doesn't fill up with
  // meaningless "0"/"Not Available" rows.
  Widget _buildSummaryEmptyState(String title, IconData icon, bool isSales) {
    return Container(
      margin: EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Theme.of(context).brightness == Brightness.dark
            ? Border.all(color: Colors.white.withOpacity(0.10), width: 1)
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black12.withOpacity(0.08),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            buildSectionTitle(icon, title),
            SizedBox(height: 16),
            Center(
              child: Column(
                children: [
                  Icon(
                    Icons.inbox_outlined,
                    size: 32,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'No ${isSales ? 'sales' : 'purchase'} recorded for this period',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatIntValue(String? value) {
    if (value == null || value.trim().toLowerCase() == 'not available') {
      return '0';
    }
    return value;
  }

  String _formatValue(String? value) {
    if (value == null || value.trim().toLowerCase() == 'not available') {
      return 'N/A';
    }
    return value;
  }
}
