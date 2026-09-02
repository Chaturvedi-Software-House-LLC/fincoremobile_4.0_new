import 'package:FincoreGo/PartyClickedSalePurcOrder.dart';
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
import 'dart:io';

import 'constants.dart';
import 'package:FincoreGo/widgets/app_bottom_nav.dart';
import 'package:FincoreGo/widgets/app_navigation.dart';
import 'providers/party_clicked_sale_purc_order_clicked_notifier.dart';

class Data_List {
  final String orderno;
  final String pendingQty;
  final double pendingAmount;
  final String vchdate;

  Data_List({
    required this.orderno,
    required this.pendingQty,
    required this.pendingAmount,
    required this.vchdate,
  });
}

class PartyClickedSalePurcOrderClicked extends ConsumerStatefulWidget {
  final String startdate_string, enddate_string, type, ledger, vchtype, item;
  final List<Data> dropdownItems;
  final int ledgerMasterId;
  final int stockItemMasterId;

  const PartyClickedSalePurcOrderClicked({
    required this.startdate_string,
    required this.enddate_string,
    required this.type,
    required this.ledger,
    required this.vchtype,
    required this.item,
    required this.dropdownItems,
    required this.ledgerMasterId,
    required this.stockItemMasterId,
  });
  @override
  ConsumerState<PartyClickedSalePurcOrderClicked> createState() =>
      _PartyClickedSalePurcOrderClickedPageState(
        startDateString: startdate_string,
        endDateString: enddate_string,
        type: type,
        ledger: ledger,
        vchtype: vchtype,
        item: item,
        dropdownItems: dropdownItems,
        ledgerMasterId: ledgerMasterId,
        stockItemMasterId: stockItemMasterId,
      );
}

class _PartyClickedSalePurcOrderClickedPageState
    extends ConsumerState<PartyClickedSalePurcOrderClicked>
    with TickerProviderStateMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  String startDateString = "",
      endDateString = "",
      type = "",
      ledger = "",
      vchtype = "",
      item = "";

  final int ledgerMasterId;
  final int stockItemMasterId;

  List<Data> dropdownItems;

  _PartyClickedSalePurcOrderClickedPageState({
    required this.startDateString,
    required this.endDateString,
    required this.type,
    required this.ledger,
    required this.vchtype,
    required this.item,
    required this.dropdownItems,
    required this.ledgerMasterId,
    required this.stockItemMasterId,
  });

  final List<String> itemList = [
    'Default',
    'Newest to Oldest',
    'Oldest to Newest',
    'Amount High to Low',
    'Amount Low to High',
  ];

  TextEditingController searchController = TextEditingController();

  ScrollController _scrollController = ScrollController();

  late final _args = PartyClickedSalePurcOrderClickedArgs(
    startDateString: startDateString,
    endDateString: endDateString,
    vchtype: vchtype,
    item: item,
    dropdownItems: dropdownItems,
    ledgerMasterId: ledgerMasterId,
    stockItemMasterId: stockItemMasterId,
  );

  PartyClickedSalePurcOrderClickedNotifier get _notifier => ref.read(
        partyClickedSalePurcOrderClickedNotifierProvider(_args).notifier,
      );
  PartyClickedSalePurcOrderClickedState get _s =>
      ref.read(partyClickedSalePurcOrderClickedNotifierProvider(_args));

  void _scrollToTop() {
    _scrollController.animateTo(
      0.0,
      duration: Duration(milliseconds: 500),
      curve: Curves.easeInOut,
    );
  }

  void _selectSort(String option) {
    if (_notifier.selectSortOption(option)) {
      _scrollToTop();
    }
  }

  void _showSelectionWindow(BuildContext context) {
    final List<IconData> icons = [
      Icons.sort_rounded,
      Icons.date_range_sharp,
      Icons.date_range_sharp,
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
                        _selectSort(itemList[index]);
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
                              fontWeight:
                                  itemList[index] == _s.selectedSortOption
                                      ? FontWeight.bold
                                      : FontWeight
                                            .normal, // Apply bold style to the text if the tile is selected
                            ),
                          ),
                          trailing: itemList[index] == _s.selectedSortOption
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

  Future<void> generateAndSharePDF_SalePurc() async {
    final vm = _s;
    if (vm.selectedTopValue == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select an item first")),
      );
      return;
    }
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

    final companyName = vm.company;
    final reportname = '$typee Summary';
    final partyname = ledger;
    final item_name = vm.selectedTopValue!.item;

    final headersRow3 = ['Date', 'Order No', 'Pending Qty', 'Amount'];

    final itemsPerPage = 10;
    final orders = vm.itemList;
    final pageCount = (orders.length / itemsPerPage).ceil();

    for (int pageNumber = 0; pageNumber < pageCount; pageNumber++) {
      final startIndex = pageNumber * itemsPerPage;
      final endIndex = (pageNumber + 1) * itemsPerPage > orders.length
          ? orders.length
          : (pageNumber + 1) * itemsPerPage;
      final itemsSubset = orders.sublist(startIndex, endIndex);

      final tableSubsetRows = itemsSubset.map((item) {
        return [
          convertDateFormat(item.vchdate),
          item.orderno,
          item.pendingQty,
          formatAmount(item.pendingAmount.toString()),
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
        },
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
                  pw.SizedBox(height: 10),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.center,
                    children: [
                      pw.Text(
                        'Item:',
                        style: pw.TextStyle(
                          fontSize: 16,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(width: 5),
                      pw.Text(
                        item_name,
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
              ),
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

    // ✅ Updated Share Plus usage
    await Share.shareXFiles([
      XFile(tempFilePath),
    ], text: 'Sharing $typee Report of ${vm.company}');
  }

  Future<void> generateAndShareCSV_SalePurc() async {
    final vm = _s;
    String typee = '';
    if (type == 'salesorder') {
      typee = 'Pending Sales Order';
    } else if (type == 'purcorder') {
      typee = 'Pending Purchase Order';
    }

    final List<List<dynamic>> csvData = [];
    final headersRow = ['Date', 'Order No', 'Pending Qty', 'Amount'];
    csvData.add(headersRow);

    for (final item in vm.itemList) {
      final rowData = [
        convertDateFormat(item.vchdate),
        item.orderno,
        item.pendingQty,
        formatAmount(item.pendingAmount.toString()),
      ];
      csvData.add(rowData);
    }

    final csvString = const ListToCsvConverter().convert(csvData);
    final tempDir = await Directory.systemTemp.createTemp();
    final tempFilePath = '${tempDir.path}/PendingSales_PurchaseOrder.csv';
    final file = File(tempFilePath);
    await file.writeAsString(csvString);

    // ✅ Updated Share Plus usage
    await Share.shareXFiles([
      XFile(tempFilePath),
    ], text: 'Sharing $typee Report of ${vm.company}');
  }

  String convertDateFormat(String dateStr) {
    // Parse the input date string
    DateTime date = DateTime.parse(dateStr);

    // Format the date to the desired output format
    String formattedDate = DateFormat("dd-MMM-yyyy").format(date);

    return formattedDate;
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(partyClickedSalePurcOrderClickedNotifierProvider(_args));
    final vm = _s;
    return Scaffold(
      bottomNavigationBar: const AppBottomNav(activeTab: AppBottomNavTab.party),
      key: _scaffoldKey,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(52),
        child: AppBar(
          backgroundColor: app_color,
          elevation: 2,
          automaticallyImplyLeading: false,

          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
            onPressed: () {
              AppNavigation.backOrDashboard(context);
            },
          ),
          centerTitle: false,
          title: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth:
                  MediaQuery.of(context).size.width - (kToolbarHeight * 2.6),
            ),
            child: Flexible(
              child: Text(
                ledger,
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),

          actions: [
            IconButton(
              onPressed: _notifier.toggleSearchView,
              icon: Icon(Icons.search, color: Colors.white, size: 22),
            ),
            // Sort now lives in the app bar (standard Material/iOS
            // placement) instead of a floating pill hovering over the
            // list - that pattern covered content, was easy to miss, and
            // isn't how sort controls are usually surfaced. Disabled
            // (greyed out) rather than hidden when there's nothing to sort,
            // so its position doesn't jump around as data loads.
            IconButton(
              onPressed: vm.isSortVisible
                  ? () => _showSelectionWindow(context)
                  : null,
              icon: Icon(
                Icons.sort_rounded,
                color: vm.isSortVisible ? Colors.white : Colors.white38,
                size: 22,
              ),
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
                          if (!vm.itemList.isEmpty) {
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

                          if (!vm.itemList.isEmpty) {
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

      body: Stack(
        children: [
          Column(
            children: [
              Container(
                margin: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                padding: const EdgeInsets.all(10),
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
                    children: [
                      /// 🔽 Dropdown
                      Container(
                        height: 38,
                        decoration: BoxDecoration(
                          color: Theme.of(context).brightness ==
                                  Brightness.dark
                              ? Colors.white.withOpacity(0.06)
                              : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<Data>(
                            value: vm.selectedTopValue,
                            isExpanded: true,
                            isDense: true,
                            icon: Icon(
                              Icons.expand_more,
                              size: 18,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                            style: GoogleFonts.poppins(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                            ),
                            dropdownColor: Theme.of(
                              context,
                            ).colorScheme.surface,
                            underline: SizedBox(), // Remove default underline
                            onChanged: (newValue) {
                              _notifier.selectTopValue(newValue!);
                            },
                            items: dropdownItems.map((Data value) {
                              return DropdownMenuItem<Data>(
                                value: value,
                                child: Text(
                                  value.item,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.poppins(
                                    fontSize: 14,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ],
                  ),
              ),

              Expanded(
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(
                    left: 10,
                    right: 10,
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
                      Expanded(
                        child: Container(
                          color: Theme.of(context).scaffoldBackgroundColor,
                          child: Column(
                            children: [
                              if (vm.isSearchViewVisible) ...[
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
                                      onChanged: _notifier.filter,
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

                              if (vm.isVisibleNoDataFound)
                                SizedBox(
                                  height:
                                      MediaQuery.of(context).size.height * 0.5,
                                  child: Center(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
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
                                visible: vm.isListVisible,
                                child: Expanded(
                                  child: ListView.builder(
                                    controller: _scrollController,
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                    itemCount: vm.filteredItems.length,
                                    itemBuilder: (context, index) {
                                      final card = vm.filteredItems[index];

                                      return Container(
                                        margin: EdgeInsets.only(bottom: 7),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          color: Theme.of(context).cardColor,
                                          border:
                                              Theme.of(context).brightness ==
                                                  Brightness.dark
                                              ? Border.all(
                                                  color: Colors.white
                                                      .withOpacity(0.10),
                                                  width: 1,
                                                )
                                              : null,
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withOpacity(
                                                0.05,
                                              ),
                                              blurRadius: 12,
                                              spreadRadius: 2,
                                              offset: Offset(0, 6),
                                            ),
                                          ],
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 14,
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              // Order No
                                              Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment
                                                        .spaceBetween,
                                                children: [
                                                  Text(
                                                    card.orderno,
                                                    style: GoogleFonts.poppins(
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: Theme.of(
                                                        context,
                                                      ).colorScheme.onSurface,
                                                    ),
                                                  ),

                                                  _buildMetaChip(
                                                    convertDateFormat(
                                                      card.vchdate,
                                                    ),
                                                    app_color.withOpacity(0.1),
                                                    app_color,
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

                                              // Chips Row (Qty + Amount)
                                              Wrap(
                                                spacing: 8,
                                                runSpacing: 6,
                                                children: [
                                                  // Pending Qty chip
                                                  _buildMetaChipWithIcon(
                                                    Icons.inventory_2_rounded,
                                                    'Pending Qty: ${card.pendingQty}',
                                                    Colors.orange.withOpacity(
                                                      Theme.of(
                                                                context,
                                                              ).brightness ==
                                                              Brightness.dark
                                                          ? 0.22
                                                          : 0.1,
                                                    ),
                                                    Theme.of(
                                                              context,
                                                            ).brightness ==
                                                            Brightness.dark
                                                        ? Colors.orange.shade200
                                                        : Colors
                                                              .orange
                                                              .shade800,
                                                  ),

                                                  // Pending Amount chip
                                                  _buildMetaChip(
                                                    '',
                                                    Colors.green.withOpacity(
                                                      Theme.of(
                                                                context,
                                                              ).brightness ==
                                                              Brightness.dark
                                                          ? 0.22
                                                          : 0.1,
                                                    ),
                                                    Theme.of(
                                                              context,
                                                            ).brightness ==
                                                            Brightness.dark
                                                        ? Colors.green.shade200
                                                        : Colors.green.shade800,
                                                    textWidget: formatAmountRich(
                                                      card.pendingAmount
                                                          .toString(),
                                                      style: GoogleFonts.poppins(
                                                        color:
                                                            Theme.of(
                                                                      context,
                                                                    ).brightness ==
                                                                    Brightness
                                                                        .dark
                                                                ? Colors
                                                                      .green
                                                                      .shade200
                                                                : Colors
                                                                      .green
                                                                      .shade800,
                                                        fontSize: 13,
                                                        fontWeight:
                                                            FontWeight.w600,
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
              ),
            ],
          ),

          if (vm.isLoading)
            Positioned.fill(
              child: Container(
                color: Theme.of(context).scaffoldBackgroundColor,
                child: _buildSkeletonList(),
              ),
            ),
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

  Widget _buildMetaChip(
    String text,
    Color bgColor,
    Color textColor, {
    Widget? textWidget,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child:
          textWidget ??
          Text(
            text,
            style: GoogleFonts.poppins(
              color: textColor,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
    );
  }

  Widget _buildMetaChipWithIcon(
    IconData icon,
    String text,
    Color bgColor,
    Color textColor,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: textColor),
          const SizedBox(width: 6),
          Text(
            text,
            style: GoogleFonts.poppins(
              color: textColor,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
