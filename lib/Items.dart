import 'dart:convert';
import 'dart:io';
import 'package:FincoreGo/currencyFormat.dart';
import 'package:FincoreGo/utils/currency_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'ItemsClicked.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'constants.dart';
import 'package:FincoreGo/widgets/app_bottom_nav.dart';
import 'package:FincoreGo/widgets/app_navigation.dart';
import 'widgets/scroll_fab.dart';
import 'widgets/entry_widgets.dart';

class items {
  final String itemname;
  final String alias;
  final String unit;
  final String saleprice;
  final String c_qty;
  final String c_rate;
  final String c_amount;
  final String description;
  final String lastsale;
  final String lastpurc;
  final String purcprice;
  final String standardprice;
  final String alternate_unit;
  final String denominator;
  items({
    required this.itemname,
    required this.alias,
    required this.unit,
    required this.saleprice,
    required this.c_qty,
    required this.c_rate,
    required this.c_amount,
    required this.description,
    required this.lastsale,
    required this.lastpurc,
    required this.purcprice,
    required this.standardprice,
    required this.alternate_unit,
    required this.denominator,
  });

  factory items.fromJson(Map<String, dynamic> json) {
    return items(
      itemname: json['name'].toString(),
      alias: json['alias'].toString(),
      unit: json['unit'].toString(),
      saleprice: json['saleprice'].toString(),
      c_qty: json['c_qty'].toString(),
      c_rate: json['c_rate'].toString(),
      c_amount: json['c_amount'].toString(),
      description: json['description'].toString(),
      lastsale: json['lastsale'].toString(),
      lastpurc: json['lastpurc'].toString(),
      purcprice: json['purcprice'].toString(),
      standardprice: json['standardprice'].toString(),
      alternate_unit: json['alternateUnit'].toString(),
      denominator: json['denominator'].toString(),
    );
  }
}

class ItemAgeingBucket {
  final String label;
  int count = 0;
  double value = 0;
  final List<items> itemsList = [];

  ItemAgeingBucket(this.label);
}

class _TabConfig {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _TabConfig(this.label, this.icon, this.isSelected, this.onTap);
}

String formatlastsaledate(String saledate) {
  String formated_saledate = "";

  if (saledate == 'null' || saledate == '') {
    formated_saledate = 'N/A';
  } else {
    DateTime saledate_date = DateTime.parse(saledate);
    formated_saledate = DateFormat("dd-MMM-yyyy").format(saledate_date);
  }
  return formated_saledate;
}

String formatValue(String value) {
  String value_string = "";

  if (value == "null") {
    value = "0";
  }
  value_string = CurrencyFormatter.formatCurrency_normal(value);
  return value_string;
}

String formatQtyDescription(
  String c_qty,
  String unit,
  String alternate_unit,
  String denominator,
) {
  String qty = '';

  if (alternate_unit != 'null' || denominator != 'null') {
    qty = '1 $alternate_unit = $denominator $unit';
  }
  return qty;
}

String formatRate(String value) {
  if (value == "null") {
    value = "-";
  }
  return value;
}

String formatRate_Report(String value) {
  if (value == "null") {
    value = "-";
  }
  return value;
}

class Items extends StatefulWidget {
  @override
  _ItemsPageState createState() => _ItemsPageState();
}

class _ItemsPageState extends State<Items> with TickerProviderStateMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ScrollController _scrollFabController = ScrollController();

  bool isClicked_allitems = true,
      isClicked_fastmoving = false,
      isClicked_inactiveitems = false,
      isClicked_slowmoving = false;

  int counter = 0;

  List<items> filteredItems_inactive_items =
      []; // Initialize an empty list to hold the filtered items
  List<items> filteredItems_all_items =
      []; // Initialize an empty list to hold the filtered items
  List<items> filteredItems_active_items =
      []; // Initialize an empty list to hold the filtered items

  // Fast vs Slow Moving Summary
  bool isClicked_movingsummary = false;
  List<items> fastMovingSummaryList = [];
  List<items> slowMovingSummaryList = [];
  // null = showing the two summary cards, 'fast'/'slow' = drilled into that list
  String? _movingSummaryDrilldown;
  List<items> _movingSummaryFilteredDrilldown = [];

  // Stock Valuation Report
  bool isClicked_stockvaluation = false;
  List<items> stockValuationList = [];
  List<items> _stockValuationFiltered = [];

  // Item Ageing Report
  bool isClicked_itemageing = false;
  List<ItemAgeingBucket> itemAgeingBuckets = [];
  ItemAgeingBucket? _selectedItemAgeingBucket;
  List<items> _itemAgeingFilteredDrilldown = [];

  String item_count = "0", token = '';

  String fastmovingdays = '',
      fastmovingqty = '',
      fastmovingvalue = '',
      inactivedays = '',
      slowmovingdays = '',
      slowmovingqty = '',
      slowmovingvalue = '';

  String? SecuritybtnAcessHolder;
  bool isDashEnable = true,
      isRolesEnable = true,
      isUserEnable = true,
      isRolesVisible = true,
      isUserVisible = true,
      _isSearchViewVisible = true,
      _isAllList = false,
      _isInactiveList = false,
      _isActiveList = false;

  bool allitems_visibility = false,
      fastmovingitems_visibility = false,
      inactiveitems_visibility = false,
      rate_visibility = false,
      amount_visibility = false;
  bool isVisibleNoAccess = false, isVisibleParent = false;
  String email = "";
  String name = "";

  bool isVisibleListLayout = false;

  String? _selectedFilter = 'qty';

  late String currencysymbol = '';
  String _currencyCode = 'AED';

  late int? decimal;

  // Renders without the leading symbol, for use with _currencyValueWidget
  // (which renders the symbol itself so it can swap in the Dirham glyph
  // for AED).
  String _formatAmountWithDRCRSuffix(String value) {
    if (value == "null" || value.isEmpty) {
      return "-";
    }

    double amount = double.tryParse(value) ?? 0;
    String formatted = formatAmountinDecimals(amount.abs(), decimal!);
    return amount < 0 ? "$formatted DR" : "$formatted CR";
  }

  void showToast(String message) {
    showAppMessage(context, message);
  }

  TextEditingController searchController = TextEditingController();

  bool isVisibleNoDataFound = false;

  String allitems = 'All Items';

  late GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey;
  late SharedPreferences prefs;

  String fastmovingdate = '';

  String? hostname = "",
      company = "",
      serial_no = "",
      company_lowercase = "",
      username = "";
  bool _isLoading = false;

  String? HttpURL_Parent, HttpURL_allitems, HttpURL_active_inactive_items;

  dynamic _selecteditem = "";
  List<String> spinner_list = [];

  List<items> all_items_list = [];
  List<items> inactive_items_list = [];
  List<items> active_items_list = [];

  late NumberFormat currencyFormat;

  bool isVisibleFilterby = false;

  Future<void> generateAndShareCSV_AllItems() async {
    final List<List<dynamic>> csvData = [];
    csvData.add([
      'Item Name',
      'Qty',
      'Rate',
      'Last Sale Price',
      'Standard Selling Price',
      'Amount',
    ]);

    for (final item in filteredItems_all_items) {
      csvData.add([
        item.itemname,
        item.c_qty,
        formatRate_Report(item.c_rate),
        formatValue(item.saleprice),
        formatValue(item.standardprice),
        formatAmount(item.c_amount),
      ]);
    }

    final csvString = const ListToCsvConverter().convert(csvData);
    final tempDir = await Directory.systemTemp.createTemp();
    final tempFilePath = '${tempDir.path}/AllItems.csv';
    final file = File(tempFilePath);
    await file.writeAsString(csvString);

    await SharePlus.instance.share(
      ShareParams(
        text: 'Sharing All Items Report of $company',
        files: [XFile(tempFilePath)],
      ),
    );
  }

  Future<void> generateAndShareCSV_FastSlowItems() async {
    final List<List<dynamic>> csvData = [];
    csvData.add([
      'Item Name',
      'Qty',
      'Rate',
      'Last Sale Price',
      'Standard Selling Price',
      'Amount',
    ]);

    for (final item in filteredItems_active_items) {
      csvData.add([
        item.itemname,
        item.c_qty,
        formatRate_Report(item.c_rate),
        formatValue(item.saleprice),
        formatValue(item.standardprice),
        formatAmount(item.c_amount),
      ]);
    }

    final csvString = const ListToCsvConverter().convert(csvData);
    final tempDir = await Directory.systemTemp.createTemp();
    final tempFilePath = '${tempDir.path}/Fast_SlowMovingItems.csv';
    final file = File(tempFilePath);
    await file.writeAsString(csvString);

    await SharePlus.instance.share(
      ShareParams(
        text: 'Sharing Fast/Slow Moving Items Report of $company',
        files: [XFile(tempFilePath)],
      ),
    );
  }

  Future<void> generateAndShareCSV_ItemAgeing() async {
    final List<List<dynamic>> csvData = [];

    if (_selectedItemAgeingBucket != null) {
      csvData.add(['Item Name', 'Qty', 'Last Sale', 'Last Purchase', 'Amount']);
      for (final item in _selectedItemAgeingBucket!.itemsList) {
        csvData.add([
          item.itemname,
          removeUnit(item.c_qty),
          formatlastsaledate(item.lastsale),
          formatlastsaledate(item.lastpurc),
          formatAmount(item.c_amount),
        ]);
      }
    } else {
      csvData.add(['Ageing Bucket', 'No. of Items', 'Value']);
      for (final bucket in itemAgeingBuckets) {
        csvData.add([
          bucket.label,
          bucket.count,
          formatAmount(bucket.value.toString()),
        ]);
      }
    }

    final csvString = const ListToCsvConverter().convert(csvData);
    final tempDir = await Directory.systemTemp.createTemp();
    final fileName = _selectedItemAgeingBucket != null
        ? 'ItemAgeing_${_selectedItemAgeingBucket!.label}.csv'
        : 'ItemAgeing_Summary.csv';
    final tempFilePath = '${tempDir.path}/$fileName';
    final file = File(tempFilePath);
    await file.writeAsString(csvString);

    await SharePlus.instance.share(
      ShareParams(
        text:
            'Sharing Item Ageing Report${_selectedItemAgeingBucket != null ? ' (${_selectedItemAgeingBucket!.label})' : ''} of $company',
        files: [XFile(tempFilePath)],
      ),
    );
  }

  Future<void> generateAndSharePDF_ItemAgeing() async {
    final font = pw.Font.ttf(
      await rootBundle.load("assets/fonts/NotoSans.ttf"),
    );
    final pdf = pw.Document();
    final companyName = company!;
    final bucket = _selectedItemAgeingBucket;

    final headersRow = bucket != null
        ? ['Item Name', 'Qty', 'Last Sale', 'Last Purchase', 'Amount']
        : ['Ageing Bucket', 'No. of Items', 'Value'];

    final rows = bucket != null
        ? bucket.itemsList
              .map(
                (item) => [
                  item.itemname,
                  removeUnit(item.c_qty),
                  formatlastsaledate(item.lastsale),
                  formatlastsaledate(item.lastpurc),
                  formatAmount(item.c_amount),
                ],
              )
              .toList()
        : itemAgeingBuckets
              .map(
                (b) => [
                  b.label,
                  b.count.toString(),
                  formatAmount(b.value.toString()),
                ],
              )
              .toList();

    final itemsPerPage = 8;
    final pageCount = (rows.length / itemsPerPage).ceil().clamp(1, 1 << 30);

    for (int pageNumber = 0; pageNumber < pageCount; pageNumber++) {
      final startIndex = pageNumber * itemsPerPage;
      final endIndex = (pageNumber + 1) * itemsPerPage;
      final rowsSubset = rows.sublist(
        startIndex,
        endIndex > rows.length ? rows.length : endIndex,
      );

      final tableSubset = pw.Table.fromTextArray(
        border: pw.TableBorder.all(width: 1),
        headerDecoration: pw.BoxDecoration(
          borderRadius: pw.BorderRadius.circular(2),
          color: PdfColors.grey300,
        ),
        headerHeight: 30,
        cellAlignment: pw.Alignment.center,
        cellPadding: const pw.EdgeInsets.all(5),
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: font),
        cellStyle: pw.TextStyle(fontSize: 12, font: font),
        headers: headersRow,
        data: rowsSubset,
      );

      pdf.addPage(
        pw.Page(
          build: (context) => pw.Column(
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
                bucket != null
                    ? 'Item Ageing Report - ${bucket.label}'
                    : 'Item Ageing Report Summary',
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 20),
              pw.Expanded(child: tableSubset),
            ],
          ),
        ),
      );
    }

    final pdfData = await pdf.save();
    final tempDir = await getTemporaryDirectory();
    final fileName = bucket != null
        ? 'ItemAgeing_${bucket.label}.pdf'
        : 'ItemAgeing_Summary.pdf';
    final tempFilePath = '${tempDir.path}/$fileName';
    final file = File(tempFilePath);
    await file.writeAsBytes(pdfData);

    await SharePlus.instance.share(
      ShareParams(
        text:
            'Sharing Item Ageing Report${bucket != null ? ' (${bucket.label})' : ''} of $company',
        files: [XFile(tempFilePath)],
      ),
    );
  }

  Future<void> generateAndShareCSV_StockValuation() async {
    final List<List<dynamic>> csvData = [];
    csvData.add(['Rank', 'Item Name', 'Qty', 'Rate', 'Amount']);

    for (var i = 0; i < stockValuationList.length; i++) {
      final item = stockValuationList[i];
      csvData.add([
        i + 1,
        item.itemname,
        item.c_qty,
        formatRate_Report(item.c_rate),
        formatAmount(item.c_amount),
      ]);
    }

    final csvString = const ListToCsvConverter().convert(csvData);
    final tempDir = await Directory.systemTemp.createTemp();
    final tempFilePath = '${tempDir.path}/StockValuation.csv';
    final file = File(tempFilePath);
    await file.writeAsString(csvString);

    await SharePlus.instance.share(
      ShareParams(
        text: 'Sharing Stock Valuation Report of $company',
        files: [XFile(tempFilePath)],
      ),
    );
  }

  Future<void> generateAndSharePDF_StockValuation() async {
    final font = pw.Font.ttf(
      await rootBundle.load("assets/fonts/NotoSans.ttf"),
    );
    final pdf = pw.Document();
    final companyName = company!;
    final headersRow = ['Rank', 'Item Name', 'Qty', 'Rate', 'Amount'];

    final itemsPerPage = 8;
    final pageCount = (stockValuationList.length / itemsPerPage)
        .ceil()
        .clamp(1, 1 << 30);

    for (int pageNumber = 0; pageNumber < pageCount; pageNumber++) {
      final startIndex = pageNumber * itemsPerPage;
      final endIndex = (pageNumber + 1) * itemsPerPage;
      final itemsSubset = stockValuationList.sublist(
        startIndex,
        endIndex > stockValuationList.length
            ? stockValuationList.length
            : endIndex,
      );

      final tableSubsetRows = itemsSubset.asMap().entries.map((entry) {
        final item = entry.value;
        return [
          (startIndex + entry.key + 1).toString(),
          item.itemname,
          item.c_qty,
          formatRate_Report(item.c_rate),
          formatAmount(item.c_amount),
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
        cellPadding: const pw.EdgeInsets.all(5),
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: font),
        cellStyle: pw.TextStyle(fontSize: 12, font: font),
        headers: headersRow,
        data: tableSubsetRows,
      );

      pdf.addPage(
        pw.Page(
          build: (context) => pw.Column(
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
                'Stock Valuation Report',
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 20),
              pw.Expanded(child: tableSubset),
            ],
          ),
        ),
      );
    }

    final pdfData = await pdf.save();
    final tempDir = await getTemporaryDirectory();
    final tempFilePath = '${tempDir.path}/StockValuation.pdf';
    final file = File(tempFilePath);
    await file.writeAsBytes(pdfData);

    await SharePlus.instance.share(
      ShareParams(
        text: 'Sharing Stock Valuation Report of $company',
        files: [XFile(tempFilePath)],
      ),
    );
  }

  Future<void> generateAndShareCSV_MovingSummary() async {
    final List<List<dynamic>> csvData = [];

    if (_movingSummaryDrilldown != null) {
      final list = _movingSummaryDrilldown == 'fast'
          ? fastMovingSummaryList
          : slowMovingSummaryList;
      csvData.add([
        'Item Name',
        'Qty',
        'Rate',
        'Last Sale Price',
        'Standard Selling Price',
        'Amount',
      ]);
      for (final item in list) {
        csvData.add([
          item.itemname,
          item.c_qty,
          formatRate_Report(item.c_rate),
          formatValue(item.saleprice),
          formatValue(item.standardprice),
          formatAmount(item.c_amount),
        ]);
      }
    } else {
      csvData.add(['Category', 'Item Count', 'Total Value']);
      csvData.add([
        'Fast Moving',
        fastMovingSummaryList.length,
        formatAmount(_movingListTotalValue(fastMovingSummaryList).toString()),
      ]);
      csvData.add([
        'Slow Moving',
        slowMovingSummaryList.length,
        formatAmount(_movingListTotalValue(slowMovingSummaryList).toString()),
      ]);
    }

    final csvString = const ListToCsvConverter().convert(csvData);
    final tempDir = await Directory.systemTemp.createTemp();
    final fileName = _movingSummaryDrilldown != null
        ? '${_movingSummaryDrilldown == 'fast' ? 'FastMoving' : 'SlowMoving'}Items.csv'
        : 'MovingSummary.csv';
    final tempFilePath = '${tempDir.path}/$fileName';
    final file = File(tempFilePath);
    await file.writeAsString(csvString);

    await SharePlus.instance.share(
      ShareParams(
        text: 'Sharing Fast vs Slow Moving Summary of $company',
        files: [XFile(tempFilePath)],
      ),
    );
  }

  Future<void> generateAndSharePDF_MovingSummary() async {
    final font = pw.Font.ttf(
      await rootBundle.load("assets/fonts/NotoSans.ttf"),
    );
    final pdf = pw.Document();
    final companyName = company!;

    if (_movingSummaryDrilldown != null) {
      final list = _movingSummaryDrilldown == 'fast'
          ? fastMovingSummaryList
          : slowMovingSummaryList;
      final reportname = _movingSummaryDrilldown == 'fast'
          ? 'Fast Moving Items'
          : 'Slow Moving Items';
      final headersRow = [
        'Item Name',
        'Qty',
        'Rate',
        'Last Sale Price',
        'Standard Selling Price',
        'Amount',
      ];

      final itemsPerPage = 8;
      final pageCount = (list.length / itemsPerPage).ceil().clamp(
        1,
        1 << 30,
      );

      for (int pageNumber = 0; pageNumber < pageCount; pageNumber++) {
        final startIndex = pageNumber * itemsPerPage;
        final endIndex = (pageNumber + 1) * itemsPerPage;
        final itemsSubset = list.sublist(
          startIndex,
          endIndex > list.length ? list.length : endIndex,
        );

        final tableSubsetRows = itemsSubset.map((item) {
          return [
            item.itemname,
            item.c_qty,
            formatRate_Report(item.c_rate),
            formatValue(item.saleprice),
            formatValue(item.standardprice),
            formatAmount(item.c_amount),
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
          cellPadding: const pw.EdgeInsets.all(5),
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: font),
          cellStyle: pw.TextStyle(fontSize: 12, font: font),
          headers: headersRow,
          data: tableSubsetRows,
        );

        pdf.addPage(
          pw.Page(
            build: (context) => pw.Column(
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
          ),
        );
      }
    } else {
      final headersRow = ['Category', 'Item Count', 'Total Value'];
      final rows = [
        [
          'Fast Moving',
          fastMovingSummaryList.length.toString(),
          formatAmount(_movingListTotalValue(fastMovingSummaryList).toString()),
        ],
        [
          'Slow Moving',
          slowMovingSummaryList.length.toString(),
          formatAmount(_movingListTotalValue(slowMovingSummaryList).toString()),
        ],
      ];

      final table = pw.Table.fromTextArray(
        border: pw.TableBorder.all(width: 1),
        headerDecoration: pw.BoxDecoration(
          borderRadius: pw.BorderRadius.circular(2),
          color: PdfColors.grey300,
        ),
        headerHeight: 30,
        cellAlignment: pw.Alignment.center,
        cellPadding: const pw.EdgeInsets.all(5),
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: font),
        cellStyle: pw.TextStyle(fontSize: 12, font: font),
        headers: headersRow,
        data: rows,
      );

      pdf.addPage(
        pw.Page(
          build: (context) => pw.Column(
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
                'Fast vs Slow Moving Summary',
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 20),
              table,
            ],
          ),
        ),
      );
    }

    final pdfData = await pdf.save();
    final tempDir = await getTemporaryDirectory();
    final fileName = _movingSummaryDrilldown != null
        ? '${_movingSummaryDrilldown == 'fast' ? 'FastMoving' : 'SlowMoving'}Items.pdf'
        : 'MovingSummary.pdf';
    final tempFilePath = '${tempDir.path}/$fileName';
    final file = File(tempFilePath);
    await file.writeAsBytes(pdfData);

    await SharePlus.instance.share(
      ShareParams(
        text: 'Sharing Fast vs Slow Moving Summary of $company',
        files: [XFile(tempFilePath)],
      ),
    );
  }

  Future<void> generateAndShareCSV_InactiveItems() async {
    final List<List<dynamic>> csvData = [];
    csvData.add([
      'Item Name',
      'Inactive Since',
      'Qty',
      'Rate',
      'Last Sale Price',
      'Standard Selling Price',
      'Amount',
    ]);

    for (final item in filteredItems_inactive_items) {
      csvData.add([
        item.itemname,
        formatlastsaledate(item.lastsale),
        item.c_qty,
        formatRate_Report(item.c_rate),
        formatValue(item.saleprice),
        formatValue(item.standardprice),
        formatAmount(item.c_amount),
      ]);
    }

    final csvString = const ListToCsvConverter().convert(csvData);
    final tempDir = await Directory.systemTemp.createTemp();
    final tempFilePath = '${tempDir.path}/InactiveItems.csv';
    final file = File(tempFilePath);
    await file.writeAsString(csvString);

    await SharePlus.instance.share(
      ShareParams(
        text: 'Sharing Inactive Items Report of $company',
        files: [XFile(tempFilePath)],
      ),
    );
  }

  Future<void> generateAndSharePDF_AllItems() async {
    final font = pw.Font.ttf(
      await rootBundle.load("assets/fonts/NotoSans.ttf"),
    );

    final pdf = pw.Document();
    final companyName = company!;
    final reportname = 'Stock Summary';
    final parentname = _selecteditem;
    final headersRow3 = [
      'Item Name',
      'Qty',
      'Rate',
      'Last Sale Price',
      'Standard Selling Price',
      'Amount',
    ];

    final itemsPerPage = 8;
    final pageCount = (filteredItems_all_items.length / itemsPerPage).ceil();

    for (int pageNumber = 0; pageNumber < pageCount; pageNumber++) {
      final startIndex = pageNumber * itemsPerPage;
      final endIndex = (pageNumber + 1) * itemsPerPage;
      final itemsSubset = filteredItems_all_items.sublist(
        startIndex,
        endIndex > filteredItems_all_items.length
            ? filteredItems_all_items.length
            : endIndex,
      );

      final tableSubsetRows = itemsSubset.map((item) {
        return [
          item.itemname,
          item.c_qty,
          formatRate_Report(item.c_rate),
          formatValue(item.saleprice),
          formatValue(item.standardprice),
          formatAmount(item.c_amount),
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
        cellPadding: const pw.EdgeInsets.all(5),
        headerStyle: pw.TextStyle(
          fontWeight: pw.FontWeight.bold,
          font: font,
        ), // ✅ Use your font
        cellStyle: pw.TextStyle(
          fontSize: 12,
          font: font,
        ), // ✅ Use your font here too
        headers: headersRow3,
        data: tableSubsetRows,
      );

      pdf.addPage(
        pw.Page(
          build: (context) => pw.Column(
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
                  pw.Text(parentname, style: const pw.TextStyle(fontSize: 16)),
                ],
              ),
              pw.SizedBox(height: 20),
              pw.Expanded(child: tableSubset),
            ],
          ),
        ),
      );
    }

    final pdfData = await pdf.save();
    final tempDir = await getTemporaryDirectory();
    final tempFilePath = '${tempDir.path}/AllItems.pdf';
    final file = File(tempFilePath);
    await file.writeAsBytes(pdfData);

    await SharePlus.instance.share(
      ShareParams(
        text: 'Sharing All Items Report of $company',
        files: [XFile(tempFilePath)],
      ),
    );
  }

  Future<void> generateAndSharePDF_FastSlowItems() async {
    final font = pw.Font.ttf(
      await rootBundle.load("assets/fonts/NotoSans.ttf"),
    );
    final pdf = pw.Document();
    final companyName = company!;
    final reportname = 'Stock Summary';
    final parentname = _selecteditem;
    final headersRow3 = [
      'Item Name',
      'Qty',
      'Rate',
      'Last Sale Price',
      'Standard Selling Price',
      'Amount',
    ];

    final itemsPerPage = 8;
    final pageCount = (filteredItems_active_items.length / itemsPerPage).ceil();

    for (int pageNumber = 0; pageNumber < pageCount; pageNumber++) {
      final startIndex = pageNumber * itemsPerPage;
      final endIndex = (pageNumber + 1) * itemsPerPage;
      final itemsSubset = filteredItems_active_items.sublist(
        startIndex,
        endIndex > filteredItems_active_items.length
            ? filteredItems_active_items.length
            : endIndex,
      );

      final tableSubsetRows = itemsSubset.map((item) {
        return [
          item.itemname,
          item.c_qty,
          formatRate_Report(item.c_rate),
          formatValue(item.saleprice),
          formatValue(item.standardprice),
          formatAmount(item.c_amount),
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
        cellPadding: const pw.EdgeInsets.all(5),
        headerStyle: pw.TextStyle(
          fontWeight: pw.FontWeight.bold,
          font: font,
        ), // ✅ Use your font
        cellStyle: pw.TextStyle(
          fontSize: 12,
          font: font,
        ), // ✅ Use your font here too
        headers: headersRow3,
        data: tableSubsetRows,
      );

      pdf.addPage(
        pw.Page(
          build: (context) => pw.Column(
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
                  pw.Text(parentname, style: const pw.TextStyle(fontSize: 16)),
                ],
              ),
              pw.SizedBox(height: 20),
              pw.Expanded(child: tableSubset),
            ],
          ),
        ),
      );
    }

    final pdfData = await pdf.save();
    final tempDir = await getTemporaryDirectory();
    final tempFilePath = '${tempDir.path}/Fast_SlowMovingItems.pdf';
    final file = File(tempFilePath);
    await file.writeAsBytes(pdfData);

    await SharePlus.instance.share(
      ShareParams(
        text: 'Sharing Fast/Slow Moving Items Report of $company',
        files: [XFile(tempFilePath)],
      ),
    );
  }

  Future<void> generateAndSharePDF_InactiveItems() async {
    final font = pw.Font.ttf(
      await rootBundle.load("assets/fonts/NotoSans.ttf"),
    );
    final pdf = pw.Document();
    final companyName = company!;
    final reportname = 'Stock Summary';
    final parentname = _selecteditem;
    final headersRow3 = [
      'Item Name',
      'Inactive Since',
      'Qty',
      'Rate',
      'Last Sale Price',
      'Standard Selling Price',
      'Amount',
    ];

    final itemsPerPage = 8;
    final pageCount = (filteredItems_inactive_items.length / itemsPerPage)
        .ceil();

    for (int pageNumber = 0; pageNumber < pageCount; pageNumber++) {
      final startIndex = pageNumber * itemsPerPage;
      final endIndex = (pageNumber + 1) * itemsPerPage;
      final itemsSubset = inactive_items_list.sublist(
        startIndex,
        endIndex > filteredItems_inactive_items.length
            ? filteredItems_inactive_items.length
            : endIndex,
      );

      final tableSubsetRows = itemsSubset.map((item) {
        return [
          item.itemname,
          formatlastsaledate(item.lastsale),
          item.c_qty,
          formatRate_Report(item.c_rate),
          formatValue(item.saleprice),
          formatValue(item.standardprice),
          formatAmount(item.c_amount),
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
        cellPadding: const pw.EdgeInsets.all(5),
        headerStyle: pw.TextStyle(
          fontWeight: pw.FontWeight.bold,
          font: font,
        ), // ✅ Use your font
        cellStyle: pw.TextStyle(
          fontSize: 12,
          font: font,
        ), // ✅ Use your font here too
        headers: headersRow3,
        data: tableSubsetRows,
      );

      pdf.addPage(
        pw.Page(
          build: (context) => pw.Column(
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
                  pw.Text(parentname, style: const pw.TextStyle(fontSize: 16)),
                ],
              ),
              pw.SizedBox(height: 20),
              pw.Expanded(child: tableSubset),
            ],
          ),
        ),
      );
    }

    final pdfData = await pdf.save();
    final tempDir = await getTemporaryDirectory();
    final tempFilePath = '${tempDir.path}/InactiveItems.pdf';
    final file = File(tempFilePath);
    await file.writeAsBytes(pdfData);

    await SharePlus.instance.share(
      ShareParams(
        text: 'Sharing Inactive Items Report of $company',
        files: [XFile(tempFilePath)],
      ),
    );
  }

  Future<void> fetchParentData() async {
    setState(() {
      _isLoading = true;
    });

    spinner_list.clear();

    try {
      final url = Uri.parse(HttpURL_Parent!);

      Map<String, String> headers = {
        'Authorization': 'Bearer $token',
        "Content-Type": "application/json",
      };

      final response = await http.post(url, headers: headers);

      if (response.statusCode == 200) {
        spinner_list.add(allitems);

        List<dynamic> data = jsonDecode(response.body);
        for (var item in data) {
          String itemname = item['parent'];
          spinner_list.add(itemname);
        }
        setState(() {
          _selecteditem = spinner_list[0];
        });

        if (allitems_visibility) {
          fetchItemData('All Items', _selecteditem);
        } else if (fastmovingitems_visibility) {
          fetchMovingSummary(_selecteditem);
        } else if (inactiveitems_visibility) {
          fetchItemData('InactiveItems', _selecteditem);
        }
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      print(e);
    }
  }

  void fetchItemData(String item_type, String item) {
    if (item == "All Items") {
      item = "";
    }
    if (item_type == "All Items") {
      fetchall_items(item);
    } else if (item_type == "FastMovingItems") {
      fetchactive_items(item, _selectedFilter!);
    } else if (item_type == "SlowMovingItems") {
      fetchslow_items(item, _selectedFilter!);
    } else if (item_type == "InactiveItems") {
      fetchinactive_items(item);
    }
  }

  Future<void> fetchall_items(final String parent) async {
    setState(() {
      item_count = "0";
      _isLoading = true;
      _isAllList = false;
      _isInactiveList = false;
      _isActiveList = false;
      isClicked_allitems = true;
      isClicked_fastmoving = false;
      isClicked_slowmoving = false;
      isClicked_inactiveitems = false;
      isClicked_movingsummary = false;
      isClicked_stockvaluation = false;
      isClicked_itemageing = false;
      isVisibleNoDataFound = false;
      isVisibleFilterby = false;
    });

    filteredItems_all_items.clear();
    all_items_list.clear();

    try {
      final url = Uri.parse(HttpURL_allitems!);

      Map<String, String> headers = {
        'Authorization': 'Bearer $token',
        "Content-Type": "application/json",
      };

      var body = jsonEncode({'parent': parent});

      final response = await http.post(url, body: body, headers: headers);

      if (response.statusCode == 200) {
        final List<dynamic> values_list = jsonDecode(response.body);

        if (values_list != null) {
          isVisibleNoDataFound = false;

          all_items_list.addAll(
            values_list.map((json) => items.fromJson(json)).toList(),
          );
          filteredItems_all_items = all_items_list;
        }
      }
    } catch (e) {
      setState(() {
        _isInactiveList = false;
        _isAllList = false;
        _isActiveList = false;
        _isLoading = false;
      });
      print(e);
    }

    setState(() {
      if (filteredItems_all_items.isEmpty) {
        item_count = "0";
        _isInactiveList = false;
        _isAllList = false;
        _isActiveList = false;
        isVisibleNoDataFound = true;
      } else {
        item_count = filteredItems_all_items.length.toString();
        _isInactiveList = false;
        _isAllList = true;
        _isActiveList = false;
      }
      _isLoading = false;
    });
  }

  Future<void> fetchactive_items(
    final String parent,
    final String filter,
  ) async {
    String qty = '';
    String value = '';

    if (filter == 'qty') {
      qty = fastmovingqty;
    }
    if (filter == 'value') {
      value = fastmovingvalue;
    }

    int fastdays = int.parse(fastmovingdays);
    DateTime currentDate = DateTime.now();
    DateTime newDate = currentDate.subtract(Duration(days: fastdays));
    String formattedDate = DateFormat('yyyyMMdd').format(newDate);

    setState(() {
      item_count = "0";
      isClicked_allitems = false;
      isClicked_fastmoving = true;
      isClicked_slowmoving = false;
      isClicked_inactiveitems = false;
      isClicked_movingsummary = false;
      isClicked_stockvaluation = false;
      isClicked_itemageing = false;
      _isLoading = true;
      _isAllList = false;
      _isInactiveList = false;
      _isActiveList = false;
      isVisibleNoDataFound = false;
      isVisibleFilterby = true;
    });

    filteredItems_active_items.clear();
    active_items_list.clear();

    try {
      final url = Uri.parse(HttpURL_active_inactive_items!);
      Map<String, String> headers = {
        'Authorization': 'Bearer $token',
        "Content-Type": "application/json",
      };

      var body = jsonEncode({
        "date": formattedDate,
        "status": "FAST",
        "qty": qty,
        "value": value,
        "parent": parent,
      });

      final response = await http.post(url, body: body, headers: headers);
      final decoded = jsonDecode(response.body);

      final prettyJson = const JsonEncoder.withIndent('  ').convert(decoded);
      print(prettyJson);

      if (response.statusCode == 200) {
        final List<dynamic> values_list = jsonDecode(response.body);

        if (values_list != null) {
          isVisibleNoDataFound = false;

          for (var entry in values_list.asMap().entries) {
            int index = entry.key;
            dynamic item = entry.value;

            /*String lastpurchdate = item['lastpurc'].toString();
            String lastsaledate = item['lastsale'].toString();

            DateTime lastsale_date;
            DateTime lastpurc_date;

            Duration difference_lastsaledate = Duration(days: 181) ;
            Duration difference_lastpurcdate = Duration(days: 181);
            DateTime current_date = DateTime.now();

            bool diff_sale = false;
            bool diff_purchase = false;

            if(lastsaledate != 'null' && lastsaledate != '')
            {
              lastsale_date = DateTime.parse(lastsaledate);
              difference_lastsaledate = current_date.difference(lastsale_date);

              diff_sale = difference_lastsaledate.inDays <=190;
            }

            if (lastpurchdate != 'null'&& lastpurchdate != '')
            {
              lastpurc_date = DateTime.parse(lastpurchdate);
              difference_lastpurcdate = current_date.difference(lastpurc_date);
              diff_purchase = difference_lastpurcdate.inDays <=190;
            }

            if(diff_sale || diff_purchase )
              {
                active_items_list.add(items.fromJson(values_list[index]));
              }*/

            active_items_list.add(items.fromJson(values_list[index]));
          }
          filteredItems_active_items = active_items_list;
        }
      }
    } catch (e) {
      setState(() {
        _isInactiveList = false;
        _isAllList = false;
        _isActiveList = false;
        _isLoading = false;
      });
      print(e);
    }

    setState(() {
      if (filteredItems_active_items.isEmpty) {
        item_count = "0";

        _isInactiveList = false;
        _isAllList = false;
        _isActiveList = false;
        isVisibleNoDataFound = true;
      } else {
        item_count = filteredItems_active_items.length.toString();
        _isInactiveList = false;
        _isActiveList = true;
        _isAllList = false;
      }
      _isLoading = false;
    });
  }

  Future<void> fetchslow_items(final String parent, final String filter) async {
    String qty = '';
    String value = '';

    if (filter == 'qty') {
      qty = slowmovingqty;
    }
    if (filter == 'value') {
      value = slowmovingvalue;
    }

    int slowdays = int.parse(slowmovingdays);
    DateTime currentDate = DateTime.now();
    DateTime newDate = currentDate.subtract(Duration(days: slowdays));
    String formattedDate = DateFormat('yyyyMMdd').format(newDate);

    setState(() {
      item_count = "0";
      isClicked_allitems = false;
      isClicked_fastmoving = false;
      isClicked_slowmoving = true;
      isClicked_inactiveitems = false;
      isClicked_movingsummary = false;
      isClicked_stockvaluation = false;
      isClicked_itemageing = false;
      _isLoading = true;
      _isAllList = false;
      _isInactiveList = false;
      _isActiveList = false;
      isVisibleNoDataFound = false;
      isVisibleFilterby = true;
    });

    filteredItems_active_items.clear();
    active_items_list.clear();

    try {
      final url = Uri.parse(HttpURL_active_inactive_items!);
      Map<String, String> headers = {
        'Authorization': 'Bearer $token',
        "Content-Type": "application/json",
      };

      var body = jsonEncode({
        "date": formattedDate,
        "status": "SLOW",
        "qty": qty,
        "value": value,
        "parent": parent,
      });

      final response = await http.post(url, body: body, headers: headers);

      if (response.statusCode == 200) {
        final List<dynamic> values_list = jsonDecode(response.body);

        if (values_list != null) {
          isVisibleNoDataFound = false;

          for (var entry in values_list.asMap().entries) {
            int index = entry.key;
            dynamic item = entry.value;

            /*String lastpurchdate = item['lastpurc'].toString();
            String lastsaledate = item['lastsale'].toString();

            DateTime lastsale_date;
            DateTime lastpurc_date;

            Duration difference_lastsaledate = Duration(days: 181) ;
            Duration difference_lastpurcdate = Duration(days: 181);
            DateTime current_date = DateTime.now();

            bool diff_sale = false;
            bool diff_purchase = false;

            if(lastsaledate != 'null' && lastsaledate != '')
            {
              lastsale_date = DateTime.parse(lastsaledate);
              difference_lastsaledate = current_date.difference(lastsale_date);

              diff_sale = difference_lastsaledate.inDays <=190;

            }

            if (lastpurchdate != 'null'&& lastpurchdate != '')
            {
              lastpurc_date = DateTime.parse(lastpurchdate);
              difference_lastpurcdate = current_date.difference(lastpurc_date);
              diff_purchase = difference_lastpurcdate.inDays <=190;

            }

            if(diff_sale || diff_purchase )
              {
                active_items_list.add(items.fromJson(values_list[index]));
              }*/
            active_items_list.add(items.fromJson(values_list[index]));
          }
          filteredItems_active_items = active_items_list;
        }
      }
    } catch (e) {
      setState(() {
        _isInactiveList = false;
        _isAllList = false;
        _isActiveList = false;
        _isLoading = false;
      });
      print(e);
    }

    setState(() {
      if (filteredItems_active_items.isEmpty) {
        item_count = "0";

        _isInactiveList = false;
        _isAllList = false;
        _isActiveList = false;
        isVisibleNoDataFound = true;
      } else {
        item_count = filteredItems_active_items.length.toString();
        _isInactiveList = false;
        _isActiveList = true;
        _isAllList = false;
      }
      _isLoading = false;
    });
  }

  Future<List<items>> _fetchMovingList(
    final String parent,
    final String filter,
    final String status,
  ) async {
    String qty = '';
    String value = '';

    if (status == 'FAST') {
      if (filter == 'qty') qty = fastmovingqty;
      if (filter == 'value') value = fastmovingvalue;
    } else {
      if (filter == 'qty') qty = slowmovingqty;
      if (filter == 'value') value = slowmovingvalue;
    }

    final days = int.tryParse(status == 'FAST' ? fastmovingdays : slowmovingdays) ?? 0;
    final cutoffDate = DateTime.now().subtract(Duration(days: days));
    final formattedDate = DateFormat('yyyyMMdd').format(cutoffDate);

    final url = Uri.parse(HttpURL_active_inactive_items!);
    final headers = <String, String>{
      'Authorization': 'Bearer $token',
      "Content-Type": "application/json",
    };
    final body = jsonEncode({
      "date": formattedDate,
      "status": status,
      "qty": qty,
      "value": value,
      "parent": parent,
    });

    final response = await http.post(url, body: body, headers: headers);
    if (response.statusCode != 200) return [];

    final List<dynamic> valuesList = jsonDecode(response.body);
    return valuesList
        .map((e) => items.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> fetchMovingSummary(final String parent) async {
    setState(() {
      item_count = "0";
      isClicked_allitems = false;
      isClicked_fastmoving = false;
      isClicked_slowmoving = false;
      isClicked_inactiveitems = false;
      isClicked_movingsummary = true;
      isClicked_stockvaluation = false;
      isClicked_itemageing = false;
      _isAllList = false;
      _isInactiveList = false;
      _isActiveList = false;
      isVisibleNoDataFound = false;
      isVisibleFilterby = true;
      _movingSummaryDrilldown = null;
      fastMovingSummaryList = [];
      slowMovingSummaryList = [];
      _movingSummaryFilteredDrilldown = [];
      searchController.clear();
      _isLoading = true;
    });

    final resolvedParent = parent == "All Items" ? "" : parent;

    try {
      final results = await Future.wait([
        _fetchMovingList(resolvedParent, _selectedFilter!, 'FAST'),
        _fetchMovingList(resolvedParent, _selectedFilter!, 'SLOW'),
      ]);

      if (!mounted) return;
      setState(() {
        fastMovingSummaryList = results[0];
        slowMovingSummaryList = results[1];
        _isLoading = false;
        isVisibleNoDataFound =
            fastMovingSummaryList.isEmpty && slowMovingSummaryList.isEmpty;
      });
    } catch (e) {
      print(e);
      if (!mounted) return;
      setState(() {
        fastMovingSummaryList = [];
        slowMovingSummaryList = [];
        _isLoading = false;
        isVisibleNoDataFound = true;
      });
    }
  }

  double _movingListTotalValue(List<items> list) {
    return list.fold<double>(
      0.0,
      (sum, item) => sum + (double.tryParse(item.c_amount) ?? 0.0),
    );
  }

  void _onMovingSummarySearchChanged(String value) {
    if (_movingSummaryDrilldown == null) return;
    final query = value.toLowerCase();
    final source = _movingSummaryDrilldown == 'fast'
        ? fastMovingSummaryList
        : slowMovingSummaryList;
    setState(() {
      _movingSummaryFilteredDrilldown = source
          .where((e) => e.itemname.toLowerCase().contains(query))
          .toList();
    });
  }

  double _stockValuationTotal(List<items> list) {
    return list.fold<double>(
      0.0,
      (sum, item) => sum + (double.tryParse(item.c_amount) ?? 0.0),
    );
  }

  // Used only as the denominator for each item's "% of total" bar/label.
  // Some items can carry a negative c_amount (e.g. write-offs/adjustments),
  // which would shrink the signed total below an individual item's own
  // value and push its share past 100%. Summing magnitudes instead keeps
  // every item's share within 0-100%, while the header card above still
  // shows the true signed net total.
  double _stockValuationAbsTotal(List<items> list) {
    return list.fold<double>(
      0.0,
      (sum, item) => sum + (double.tryParse(item.c_amount) ?? 0.0).abs(),
    );
  }

  void _onStockValuationSearchChanged(String value) {
    final query = value.toLowerCase();
    setState(() {
      _stockValuationFiltered = stockValuationList
          .where((e) => e.itemname.toLowerCase().contains(query))
          .toList();
    });
  }

  Future<void> fetchStockValuation(final String parent) async {
    setState(() {
      item_count = "0";
      isClicked_allitems = false;
      isClicked_fastmoving = false;
      isClicked_slowmoving = false;
      isClicked_inactiveitems = false;
      isClicked_movingsummary = false;
      isClicked_stockvaluation = true;
      isClicked_itemageing = false;
      _isAllList = false;
      _isInactiveList = false;
      _isActiveList = false;
      isVisibleNoDataFound = false;
      isVisibleFilterby = false;
      stockValuationList = [];
      _stockValuationFiltered = [];
      searchController.clear();
      _isLoading = true;
    });

    final resolvedParent = parent == "All Items" ? "" : parent;

    try {
      final url = Uri.parse(HttpURL_allitems!);
      final headers = <String, String>{
        'Authorization': 'Bearer $token',
        "Content-Type": "application/json",
      };
      final body = jsonEncode({'parent': resolvedParent});

      final response = await http.post(url, body: body, headers: headers);

      if (!mounted) return;

      if (response.statusCode == 200) {
        final List<dynamic> valuesList = jsonDecode(response.body);
        final parsed = valuesList
            .map((e) => items.fromJson(e as Map<String, dynamic>))
            .toList()
          ..sort(
            (a, b) => (double.tryParse(b.c_amount) ?? 0.0).compareTo(
              double.tryParse(a.c_amount) ?? 0.0,
            ),
          );

        setState(() {
          stockValuationList = parsed;
          item_count = parsed.length.toString();
          isVisibleNoDataFound = parsed.isEmpty;
          _isLoading = false;
        });
      } else {
        setState(() {
          isVisibleNoDataFound = true;
          _isLoading = false;
        });
      }
    } catch (e) {
      print(e);
      if (!mounted) return;
      setState(() {
        stockValuationList = [];
        isVisibleNoDataFound = true;
        _isLoading = false;
      });
    }
  }

  DateTime? _parseItemDateSafe(String value) {
    if (value == 'null' || value.isEmpty) return null;
    try {
      return DateTime.parse(value);
    } catch (_) {
      return null;
    }
  }

  void _onItemAgeingSearchChanged(String value) {
    if (_selectedItemAgeingBucket == null) return;
    final query = value.toLowerCase();
    setState(() {
      _itemAgeingFilteredDrilldown = _selectedItemAgeingBucket!.itemsList
          .where((e) => e.itemname.toLowerCase().contains(query))
          .toList();
    });
  }

  Future<void> fetchItemAgeing(final String parent) async {
    setState(() {
      item_count = "0";
      isClicked_allitems = false;
      isClicked_fastmoving = false;
      isClicked_slowmoving = false;
      isClicked_inactiveitems = false;
      isClicked_movingsummary = false;
      isClicked_stockvaluation = false;
      isClicked_itemageing = true;
      _isAllList = false;
      _isInactiveList = false;
      _isActiveList = false;
      isVisibleNoDataFound = false;
      isVisibleFilterby = false;
      itemAgeingBuckets = [];
      _selectedItemAgeingBucket = null;
      _itemAgeingFilteredDrilldown = [];
      searchController.clear();
      _isLoading = true;
    });

    final resolvedParent = parent == "All Items" ? "" : parent;

    try {
      final url = Uri.parse(HttpURL_allitems!);
      final headers = <String, String>{
        'Authorization': 'Bearer $token',
        "Content-Type": "application/json",
      };
      final body = jsonEncode({'parent': resolvedParent});

      final response = await http.post(url, body: body, headers: headers);

      if (!mounted) return;

      if (response.statusCode == 200) {
        final List<dynamic> valuesList = jsonDecode(response.body);
        final parsedItems = valuesList
            .map((e) => items.fromJson(e as Map<String, dynamic>))
            .toList();

        // Same configurable thresholds as the voucher Ageing Report
        // (AgeingConfig.dart), so both reports stay in sync from one
        // settings screen.
        final ageingPrefs = await SharedPreferences.getInstance();
        final h1 = int.tryParse(ageingPrefs.getString('heading1') ?? '30') ?? 30;
        final h2 = int.tryParse(ageingPrefs.getString('heading2') ?? '60') ?? 60;
        final h3 = int.tryParse(ageingPrefs.getString('heading3') ?? '90') ?? 90;
        final h4 =
            int.tryParse(ageingPrefs.getString('heading4') ?? '120') ?? 120;
        final h5 =
            int.tryParse(ageingPrefs.getString('heading5') ?? '180') ?? 180;

        final b1 = ItemAgeingBucket('0-$h1 Days');
        final b2 = ItemAgeingBucket('$h1-$h2 Days');
        final b3 = ItemAgeingBucket('$h2-$h3 Days');
        final b4 = ItemAgeingBucket('$h3-$h4 Days');
        final b5 = ItemAgeingBucket('$h4-$h5 Days');
        final b6 = ItemAgeingBucket('$h5+ Days');
        final noMovement = ItemAgeingBucket('No Sales/Purchase Data');

        final today = DateTime.now();
        final todayDate = DateTime(today.year, today.month, today.day);

        for (final item in parsedItems) {
          final saleDate = _parseItemDateSafe(item.lastsale);
          final purcDate = _parseItemDateSafe(item.lastpurc);

          DateTime? lastMovement;
          if (saleDate != null && purcDate != null) {
            lastMovement = saleDate.isAfter(purcDate) ? saleDate : purcDate;
          } else {
            lastMovement = saleDate ?? purcDate;
          }

          final amount = double.tryParse(item.c_amount)?.abs() ?? 0.0;

          if (lastMovement == null) {
            noMovement.count++;
            noMovement.value += amount;
            noMovement.itemsList.add(item);
            continue;
          }

          final daysSince = todayDate
              .difference(
                DateTime(
                  lastMovement.year,
                  lastMovement.month,
                  lastMovement.day,
                ),
              )
              .inDays;

          ItemAgeingBucket bucket;
          if (daysSince <= h1) {
            bucket = b1;
          } else if (daysSince <= h2) {
            bucket = b2;
          } else if (daysSince <= h3) {
            bucket = b3;
          } else if (daysSince <= h4) {
            bucket = b4;
          } else if (daysSince <= h5) {
            bucket = b5;
          } else {
            bucket = b6;
          }

          bucket.count++;
          bucket.value += amount;
          bucket.itemsList.add(item);
        }

        final buckets = [b1, b2, b3, b4, b5, b6, noMovement]
            .where((b) => b.count > 0)
            .toList();

        setState(() {
          itemAgeingBuckets = buckets;
          item_count = parsedItems.length.toString();
          isVisibleNoDataFound = parsedItems.isEmpty;
          _isLoading = false;
        });
      } else {
        setState(() {
          isVisibleNoDataFound = true;
          _isLoading = false;
        });
      }
    } catch (e) {
      print(e);
      if (!mounted) return;
      setState(() {
        itemAgeingBuckets = [];
        isVisibleNoDataFound = true;
        _isLoading = false;
      });
    }
  }

  Future<void> fetchinactive_items(final String parent) async {
    setState(() {
      item_count = "0";
      _isLoading = true;
      _isAllList = false;
      _isActiveList = false;
      _isInactiveList = false;
      isVisibleNoDataFound = false;
      isClicked_allitems = false;
      isClicked_fastmoving = false;
      isClicked_slowmoving = false;
      isClicked_movingsummary = false;
      isClicked_stockvaluation = false;
      isClicked_itemageing = false;
      isVisibleFilterby = false;

      isClicked_inactiveitems = true;
    });

    filteredItems_inactive_items.clear();
    inactive_items_list.clear();

    int inactivedayss = int.parse(inactivedays);
    DateTime currentDate = DateTime.now();
    DateTime newDate = currentDate.subtract(Duration(days: inactivedayss));
    String formattedDate = DateFormat('yyyyMMdd').format(newDate);

    try {
      final url = Uri.parse(HttpURL_active_inactive_items!);

      Map<String, String> headers = {
        'Authorization': 'Bearer $token',
        "Content-Type": "application/json",
      };

      var body = jsonEncode({
        "date": formattedDate,
        "status": "INACTIVE",
        "parent": parent,
      });

      final response = await http.post(url, body: body, headers: headers);

      if (response.statusCode == 200) {
        final List<dynamic> values_list = jsonDecode(response.body);

        if (values_list != null) {
          isVisibleNoDataFound = false;

          for (var entry in values_list.asMap().entries) {
            int index = entry.key;
            dynamic item = entry.value;
            inactive_items_list.add(items.fromJson(values_list[index]));
          }
          filteredItems_inactive_items = inactive_items_list;
        }
      }
    } catch (e) {
      setState(() {
        _isInactiveList = false;
        _isAllList = false;
        _isActiveList = false;
        _isLoading = false;
      });
      print(e);
    }

    setState(() {
      if (inactive_items_list.isEmpty) {
        _isInactiveList = false;
        _isAllList = false;
        _isActiveList = false;
        item_count = "0";
        isVisibleNoDataFound = true;
      } else {
        item_count = filteredItems_inactive_items.length.toString();
        _isInactiveList = true;
        _isActiveList = false;
        _isAllList = false;
      }
      _isLoading = false;
    });
  }

  Future<void> _initSharedPreferences() async {
    prefs = await SharedPreferences.getInstance();

    decimal = prefs.getInt('decimalplace') ?? 2;

    currencyFormat = new NumberFormat();

    String? currencyCode = '';

    currencyCode = prefs.getString('currencycode') ?? "AED";

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

    _currencyCode = currencyCode ?? 'AED';

    hostname = prefs.getString('hostname');
    company = prefs.getString('company_name');
    company_lowercase = company!.replaceAll(' ', '').toLowerCase();
    serial_no = prefs.getString('serial_no');
    username = prefs.getString('username');
    token = prefs.getString('token')!;

    fastmovingdays = prefs.getString('fastmovingdays') ?? '180';
    fastmovingqty = prefs.getString('fastmovingqty') ?? '1000';
    fastmovingvalue = prefs.getString('fastmovingvalue') ?? '10000';

    slowmovingdays = prefs.getString('slowmovingdays') ?? '181';
    slowmovingqty = prefs.getString('slowmovingqty') ?? '1000';
    slowmovingvalue = prefs.getString('slowmovingvalue') ?? '10000';

    inactivedays = prefs.getString('inactivedays') ?? '182';

    String allitemsaccess = prefs.getString("allitems") ?? 'False';
    String fastmovingitemsaccess = prefs.getString("activeitems") ?? 'False';
    String inactiveitemsaccess = prefs.getString("inactiveitems") ?? 'False';
    String rateaccess = prefs.getString("rate") ?? 'False';
    String amountaccess = prefs.getString("item_amount") ?? 'False';

    if (allitemsaccess == 'True') {
      allitems_visibility = true;
    } else {
      allitems_visibility = false;
    }
    if (fastmovingitemsaccess == 'True') {
      fastmovingitems_visibility = true;
    } else {
      fastmovingitems_visibility = false;
    }
    if (inactiveitemsaccess == 'True') {
      inactiveitems_visibility = true;
    } else {
      inactiveitems_visibility = false;
    }
    if (rateaccess == 'True') {
      rate_visibility = true;
    } else {
      rate_visibility = false;
    }
    if (amountaccess == 'True') {
      amount_visibility = true;
    } else {
      amount_visibility = false;
    }

    HttpURL_Parent =
        '$hostname/api/item/getParent/$company_lowercase/$serial_no';
    HttpURL_allitems =
        '$hostname/api/item/getitem/$company_lowercase/$serial_no';
    HttpURL_active_inactive_items =
        '$hostname/api/item/getMoving/$company_lowercase/$serial_no';

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
    if (allitems_visibility ||
        fastmovingitems_visibility ||
        inactiveitems_visibility) {
      isVisibleParent = true;
      isVisibleListLayout = true;
      await fetchParentData();
    } else {
      isVisibleListLayout = false;
      isVisibleNoAccess = true;
      isVisibleParent = false;
    }
  }

  String formatAmountinDecimals(num amount, int decimals) {
    final formatter = NumberFormat.decimalPattern('en')
      ..minimumFractionDigits = decimals
      ..maximumFractionDigits = decimals;
    return formatter.format(amount);
  }

  String removeUnit(String value) {
    try {
      // Preserve a leading minus (negative/oversold stock) - only strip the
      // unit suffix and thousands separators, not the sign, otherwise
      // negative quantities silently display as positive.
      final isNegative = value.trim().startsWith('-');
      String numberOnly = value.replaceAll(RegExp(r'[^0-9.]'), '');
      if (numberOnly.isEmpty) return value;

      double parsed = double.parse(numberOnly);
      if (isNegative) parsed = -parsed;

      // Agar value decimal ke bagair hai → int dikhado
      if (parsed % 1 == 0) {
        return parsed.toInt().toString(); // 731.0 → 731
      } else {
        return parsed.toString(); // 286.57 → 286.57
      }
    } catch (e) {
      return value; // agar parse fail ho jaye to original value
    }
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      checkCurrencyMismatch(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: const AppBottomNav(activeTab: AppBottomNavTab.items),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,

      appBar: PreferredSize(
        preferredSize: Size.fromHeight(90),
        child: AppBar(
          automaticallyImplyLeading: false,
          flexibleSpace: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  app_color.withOpacity(0.95),
                  app_color.withOpacity(0.75),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
            ),
          ),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
          ),
          title: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth:
                  MediaQuery.of(context).size.width - (kToolbarHeight * 2.6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  company ?? '',
                  style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 4),
                Text(
                  "Stock Summary",
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
          centerTitle: false,
          leading: IconButton(
            icon: Icon(Icons.arrow_back_ios_new, color: Colors.white),
            onPressed: () => AppNavigation.backOrDashboard(context),
          ),
          actions: [
            /*IconButton(
              icon: Icon(Icons.search, color: Colors.white, size: 26),
              onPressed: () => setState(() => _isSearchViewVisible = !_isSearchViewVisible),
            ),*/
            IconButton(
              icon: Icon(Icons.share_outlined, color: Colors.white, size: 26),
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
                          if (isClicked_movingsummary) {
                            if (fastMovingSummaryList.isNotEmpty ||
                                slowMovingSummaryList.isNotEmpty) {
                              generateAndSharePDF_MovingSummary();
                            } else {
                              showToast('Data Not Found');
                            }
                          } else if (isClicked_stockvaluation) {
                            if (stockValuationList.isNotEmpty) {
                              generateAndSharePDF_StockValuation();
                            } else {
                              showToast('Data Not Found');
                            }
                          } else if (isClicked_itemageing) {
                            if (itemAgeingBuckets.isNotEmpty) {
                              generateAndSharePDF_ItemAgeing();
                            } else {
                              showToast('Data Not Found');
                            }
                          } else if (_isAllList) {
                            if (!all_items_list.isEmpty) {
                              generateAndSharePDF_AllItems();
                            } else {
                              showToast('Data Not Found');
                            }
                          } else if (_isActiveList) {
                            if (!active_items_list.isEmpty) {
                              generateAndSharePDF_FastSlowItems();
                            } else {
                              showToast('Data Not Found');
                            }
                          } else if (_isInactiveList) {
                            if (!inactive_items_list.isEmpty) {
                              generateAndSharePDF_InactiveItems();
                            } else {
                              showToast('Data Not Found');
                            }
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

                          if (isClicked_movingsummary) {
                            if (fastMovingSummaryList.isNotEmpty ||
                                slowMovingSummaryList.isNotEmpty) {
                              generateAndShareCSV_MovingSummary();
                            } else {
                              showToast('Data Not Found');
                            }
                          } else if (isClicked_stockvaluation) {
                            if (stockValuationList.isNotEmpty) {
                              generateAndShareCSV_StockValuation();
                            } else {
                              showToast('Data Not Found');
                            }
                          } else if (isClicked_itemageing) {
                            if (itemAgeingBuckets.isNotEmpty) {
                              generateAndShareCSV_ItemAgeing();
                            } else {
                              showToast('Data Not Found');
                            }
                          } else if (_isAllList) {
                            if (!all_items_list.isEmpty) {
                              generateAndShareCSV_AllItems();
                            } else {
                              showToast('Data Not Found');
                            }
                          } else if (_isActiveList) {
                            if (!active_items_list.isEmpty) {
                              generateAndShareCSV_FastSlowItems();
                            } else {
                              showToast('Data Not Found');
                            }
                          } else if (_isInactiveList) {
                            if (!inactive_items_list.isEmpty) {
                              generateAndShareCSV_InactiveItems();
                            } else {
                              showToast('Data Not Found');
                            }
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
            if (isVisibleFilterby)
              IconButton(
                icon: Icon(
                  Icons.filter_alt_rounded,
                  color: Colors.white,
                  size: 26,
                ),
                onPressed: _showFilterBottomSheet, // 👇 new bottom sheet filter
              ),
            SizedBox(width: 6),
          ],
        ),
      ),

      body: Stack(
        children: [
          CustomScrollView(
            controller: _scrollFabController,
            slivers: [
              // 🔹 Dropdown + Tabs Container
              if (isVisibleParent)
                SliverToBoxAdapter(
                  child: Container(
                    margin: EdgeInsets.only(
                      top: 8,
                      left: 12,
                      right: 12,
                      bottom: 8,
                    ),
                    padding: EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black12.withOpacity(0.08),
                          blurRadius: 10,
                          spreadRadius: 2,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // Parent Dropdown
                        _buildParentDropdown(),

                        SizedBox(height: 8),

                        // View selector - a single compact pill showing
                        // the current view, opening a full-width bottom
                        // sheet list to switch. Replaces the earlier tab
                        // row/grid attempts (horizontal scroll hid options,
                        // a 2-col grid still left an awkward lone last
                        // tile) - a sheet gives every option full width
                        // with no wrapping/ellipsis/alignment compromises,
                        // and scales to more report types for free.
                        _buildViewSelector(),

                        if (_isSearchViewVisible &&
                            !(isClicked_movingsummary &&
                                _movingSummaryDrilldown == null) &&
                            !(isClicked_itemageing &&
                                _selectedItemAgeingBucket == null))
                          Padding(
                            padding: const EdgeInsets.only(
                              left: 0,
                              right: 0,
                              top: 8,
                              bottom: 0,
                            ),
                            child: SizedBox(
                              height: 46,
                              child: TextField(
                                controller: searchController,
                                onChanged: isClicked_movingsummary
                                    ? _onMovingSummarySearchChanged
                                    : isClicked_stockvaluation
                                    ? _onStockValuationSearchChanged
                                    : isClicked_itemageing
                                    ? _onItemAgeingSearchChanged
                                    : _onSearchChanged,
                                style: GoogleFonts.poppins(
                                  fontSize: 13.5,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface,
                                ),
                                decoration: InputDecoration(
                                  isDense: true,
                                  hintText: "Search items...",
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
                    ),
                  ),
                ),

              // 🔹 List / Empty State
              if (isClicked_movingsummary)
                ..._buildMovingSummarySlivers()
              else if (isClicked_stockvaluation)
                ..._buildStockValuationSlivers()
              else if (isClicked_itemageing)
                ..._buildItemAgeingSlivers()
              else if (isVisibleNoDataFound)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _buildEmptyState(),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final card = _getVisibleList()[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _buildItemCard(card),
                    );
                  }, childCount: _getVisibleList().length),
                ),
            ],
          ),

          // 🔹 Loader Overlay - skeleton stand-in for the header (parent
          // dropdown + view selector) plus a list of item-card-shaped
          // placeholders while the initial fetch is in flight, replacing
          // the old dimmed spinner-over-stale-content overlay.
          if (_isLoading)
            Positioned.fill(
              child: Container(
                color: Theme.of(context).scaffoldBackgroundColor,
                child: _buildSkeletonItemsList(),
              ),
            ),
          ScrollFab(controller: _scrollFabController),
        ],
      ),
    );
  }

  // ------------------- 🔹 Widgets 🔹 -------------------

  Widget _buildParentDropdown() {
    // Compact - a light tinted fill instead of its own bordered/shadowed
    // box (the outer header container already provides that), same
    // pattern used to slim down the Transactions screen's header.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? Colors.white.withOpacity(0.06)
            : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(14),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selecteditem,
          isExpanded: true,
          isDense: true,
          icon: Icon(
            Icons.keyboard_arrow_down_rounded,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),

          hint: Text(
            "Select Item",
            style: GoogleFonts.poppins(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),

          style: GoogleFonts.poppins(
            fontSize: 13.5,
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),

          items: spinner_list.map((value) {
            return DropdownMenuItem<String>(
              value: value,
              child: Container(
                width: double.infinity, // 🔥 important
                child: Text(
                  value,
                  softWrap: true, // 🔥 allow wrap
                  maxLines: 2, // 👈 adjust (2–3 recommended)
                  overflow: TextOverflow.visible, // 🔥 no ellipsis
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
            );
          }).toList(),

          selectedItemBuilder: (context) {
            return spinner_list.map((value) {
              return Container(
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis, // 👈 collapsed view clean
                  maxLines: 1,
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              );
            }).toList();
          },

          onChanged: (value) {
            setState(() => _selecteditem = value);
            fetchItemData('All Items', _selecteditem);
          },
        ),
      ),
    );
  }

  List<_TabConfig> _buildViewOptions() {
    return [
      if (allitems_visibility)
        _TabConfig(
          // Labeled "Item List" (not "All Items") to avoid duplicating
          // the parent-category dropdown right above it, which also
          // reads "All Items" when no category filter is applied - the
          // two together looked like an unexplained repeat.
          "Item List",
          Icons.inventory_2_outlined,
          isClicked_allitems,
          () => fetchItemData('All Items', _selecteditem),
        ),
      if (fastmovingitems_visibility)
        _TabConfig(
          "Moving Summary",
          Icons.compare_arrows_rounded,
          isClicked_movingsummary,
          () => fetchMovingSummary(_selecteditem),
        ),
      if (allitems_visibility)
        _TabConfig(
          "Stock Valuation",
          Icons.bar_chart_rounded,
          isClicked_stockvaluation,
          () => fetchStockValuation(_selecteditem),
        ),
      if (allitems_visibility)
        _TabConfig(
          "Item Ageing",
          Icons.history_rounded,
          isClicked_itemageing,
          () => fetchItemAgeing(_selecteditem),
        ),
      if (inactiveitems_visibility)
        _TabConfig(
          "Inactive",
          Icons.block,
          isClicked_inactiveitems,
          () => _showInactiveDaysDialog(context),
        ),
    ];
  }

  // Single compact pill showing the current view - tapping it opens a
  // full-width bottom sheet list to switch, instead of packing all 5
  // options into the header as tabs (which forced a tradeoff between
  // horizontal scroll, a cramped grid, or ellipsis on long labels).
  Widget _buildViewSelector() {
    final options = _buildViewOptions();
    final current = options.firstWhere(
      (o) => o.isSelected,
      orElse: () => options.first,
    );

    return GestureDetector(
      onTap: () => _showViewSelectorSheet(options),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.white.withOpacity(0.06)
              : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(current.icon, size: 16, color: app_color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                current.label,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
            Icon(
              Icons.unfold_more_rounded,
              size: 18,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  void _showViewSelectorSheet(List<_TabConfig> options) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.8,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(context).dividerColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "Switch View",
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    children: [
                      for (final option in options)
                        ListTile(
                          onTap: () {
                            Navigator.pop(sheetContext);
                            option.onTap();
                          },
                          leading: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: option.isSelected
                                  ? app_color
                                  : app_color.withOpacity(0.10),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              option.icon,
                              size: 18,
                              color: option.isSelected
                                  ? Colors.white
                                  : app_color,
                            ),
                          ),
                          title: Text(
                            option.label,
                            style: GoogleFonts.poppins(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          trailing: option.isSelected
                              ? Icon(
                                  Icons.check_circle_rounded,
                                  color: app_color,
                                )
                              : null,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildMovingSummarySlivers() {
    if (_isLoading) {
      return [const SliverToBoxAdapter(child: SizedBox.shrink())];
    }

    if (_movingSummaryDrilldown != null) {
      final fullList = _movingSummaryDrilldown == 'fast'
          ? fastMovingSummaryList
          : slowMovingSummaryList;
      final visible = _isSearchViewVisible && searchController.text.isNotEmpty
          ? _movingSummaryFilteredDrilldown
          : fullList;

      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                setState(() {
                  _movingSummaryDrilldown = null;
                  searchController.clear();
                  _movingSummaryFilteredDrilldown = [];
                });
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(Icons.arrow_back_rounded, size: 20, color: app_color),
                    const SizedBox(width: 8),
                    Text(
                      _movingSummaryDrilldown == 'fast'
                          ? 'Fast Moving Items'
                          : 'Slow Moving Items',
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: app_color,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (visible.isEmpty)
          SliverFillRemaining(hasScrollBody: false, child: _buildEmptyState())
        else
          SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _buildItemCard(visible[index]),
              );
            }, childCount: visible.length),
          ),
      ];
    }

    if (fastMovingSummaryList.isEmpty && slowMovingSummaryList.isEmpty) {
      return [
        SliverFillRemaining(hasScrollBody: false, child: _buildEmptyState()),
      ];
    }

    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Column(
            children: [
              _buildMovingSummaryCard(
                title: 'Fast Moving',
                icon: Icons.flash_on_rounded,
                accentColor: Colors.green,
                list: fastMovingSummaryList,
                onTap: () => setState(() => _movingSummaryDrilldown = 'fast'),
              ),
              const SizedBox(height: 12),
              _buildMovingSummaryCard(
                title: 'Slow Moving',
                icon: Icons.timer_outlined,
                accentColor: Colors.deepOrange,
                list: slowMovingSummaryList,
                onTap: () => setState(() => _movingSummaryDrilldown = 'slow'),
              ),
            ],
          ),
        ),
      ),
    ];
  }

  Widget _buildMovingSummaryCard({
    required String title,
    required IconData icon,
    required MaterialColor accentColor,
    required List<items> list,
    required VoidCallback onTap,
  }) {
    final totalValue = _movingListTotalValue(list);

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: Theme.of(context).cardColor,
          border: Border.all(color: Theme.of(context).dividerColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black12.withOpacity(0.08),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [accentColor.shade400, accentColor.shade700],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${list.length} item${list.length == 1 ? '' : 's'}',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  formatAmountRich(
                    totalValue.toString(),
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 22,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildStockValuationSlivers() {
    if (_isLoading) {
      return [const SliverToBoxAdapter(child: SizedBox.shrink())];
    }

    if (stockValuationList.isEmpty) {
      return [
        SliverFillRemaining(hasScrollBody: false, child: _buildEmptyState()),
      ];
    }

    final visible = searchController.text.isNotEmpty
        ? _stockValuationFiltered
        : stockValuationList;
    final totalValue = _stockValuationTotal(stockValuationList);
    final absTotalValue = _stockValuationAbsTotal(stockValuationList);

    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: Theme.of(context).cardColor,
              border: Border.all(color: Theme.of(context).dividerColor),
              boxShadow: [
                BoxShadow(
                  color: Colors.black12.withOpacity(0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.teal.shade400, Colors.teal.shade700],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.inventory_2_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total Inventory Value',
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${stockValuationList.length} item${stockValuationList.length == 1 ? '' : 's'}',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                formatAmountRich(
                  totalValue.toString(),
                  textAlign: TextAlign.right,
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      if (visible.isEmpty)
        SliverFillRemaining(hasScrollBody: false, child: _buildEmptyState())
      else
        SliverList(
          delegate: SliverChildBuilderDelegate((context, index) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildStockValuationCard(
                visible[index],
                stockValuationList.indexOf(visible[index]) + 1,
                absTotalValue,
              ),
            );
          }, childCount: visible.length),
        ),
    ];
  }

  Widget _buildStockValuationCard(items item, int rank, double absTotalValue) {
    final amount = double.tryParse(item.c_amount) ?? 0.0;
    final share = absTotalValue > 0 ? amount.abs() / absTotalValue : 0.0;
    final MaterialColor rankColor = switch (rank) {
      1 => Colors.amber,
      2 => Colors.blueGrey,
      3 => Colors.brown,
      _ => Colors.teal,
    };

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ItemsClicked(
                itemname: item.itemname,
                unit: item.unit,
                item_desc: item.description,
                item_lastsaledate: item.lastsale,
                item_lastpurchdate: item.lastpurc,
                item_rate: item.saleprice,
                inventory_closing: item.c_qty,
                lastpurcrate: item.purcprice,
                alias: item.alias,
              ),
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: Theme.of(context).cardColor,
            border: Border.all(color: Theme.of(context).dividerColor),
            boxShadow: [
              BoxShadow(
                color: Colors.black12.withOpacity(0.08),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [rankColor.shade400, rankColor.shade700],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Text(
                  "$rank",
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            item.itemname,
                            softWrap: true,
                            style: GoogleFonts.poppins(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        formatAmountRich(
                          item.c_amount,
                          maxLines: 1,
                          textAlign: TextAlign.right,
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Qty: ${removeUnit(item.c_qty)}',
                            softWrap: true,
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        Text(
                          '${(share * 100).toStringAsFixed(1)}%',
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: share.clamp(0.0, 1.0),
                        minHeight: 6,
                        backgroundColor:
                            Theme.of(context).brightness == Brightness.dark
                            ? Theme.of(context).colorScheme.surfaceContainerHighest
                            : const Color(0xFFF1F4F8),
                        valueColor: AlwaysStoppedAnimation<Color>(rankColor),
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
  }

  List<Widget> _buildItemAgeingSlivers() {
    if (_isLoading) {
      return [const SliverToBoxAdapter(child: SizedBox.shrink())];
    }

    if (_selectedItemAgeingBucket != null) {
      final bucket = _selectedItemAgeingBucket!;
      final visible = searchController.text.isNotEmpty
          ? _itemAgeingFilteredDrilldown
          : bucket.itemsList;

      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                setState(() {
                  _selectedItemAgeingBucket = null;
                  searchController.clear();
                  _itemAgeingFilteredDrilldown = [];
                });
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(Icons.arrow_back_rounded, size: 20, color: app_color),
                    const SizedBox(width: 8),
                    Text(
                      bucket.label,
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: app_color,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (visible.isEmpty)
          SliverFillRemaining(hasScrollBody: false, child: _buildEmptyState())
        else
          SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _buildItemCard(visible[index]),
              );
            }, childCount: visible.length),
          ),
      ];
    }

    if (itemAgeingBuckets.isEmpty) {
      return [
        SliverFillRemaining(hasScrollBody: false, child: _buildEmptyState()),
      ];
    }

    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Column(
            children: itemAgeingBuckets.map((bucket) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildItemAgeingBucketCard(bucket),
              );
            }).toList(),
          ),
        ),
      ),
    ];
  }

  Widget _buildItemAgeingBucketCard(ItemAgeingBucket bucket) {
    final bool isOverdue = bucket.label != 'No Sales/Purchase Data';
    // Single accent for every aged band (labels are dynamic based on the
    // configured thresholds, and bands with zero items get filtered out of
    // the list before this is called - so a position/label-based gradient
    // can't reliably reflect severity here). "No Sales/Purchase Data" gets
    // its own neutral color.
    final MaterialColor accentColor = isOverdue ? Colors.deepOrange : Colors.blueGrey;

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () {
        setState(() {
          _selectedItemAgeingBucket = bucket;
        });
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: Theme.of(context).cardColor,
          border: Border.all(color: Theme.of(context).dividerColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black12.withOpacity(0.08),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [accentColor.shade400, accentColor.shade700],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                isOverdue ? Icons.history_rounded : Icons.help_outline_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    bucket.label,
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${bucket.count} item${bucket.count == 1 ? '' : 's'}',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  formatAmountRich(
                    bucket.value.toString(),
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 22,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  // Skeleton stand-in for the header (parent dropdown + view selector card)
  // plus a list of item-card-shaped placeholders (icon badge + name line +
  // qty/amount line) while the initial fetch is in flight - mirrors
  // _buildParentDropdown/_buildViewSelector and _buildItemCard's rough
  // layout so the transition into real content doesn't visibly jump.
  Widget _buildSkeletonHeaderCard() {
    return Container(
      margin: const EdgeInsets.only(top: 8, left: 12, right: 12, bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black12.withOpacity(0.08),
            blurRadius: 10,
            spreadRadius: 2,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          const ShimmerBox(height: 40, borderRadius: 12),
          const SizedBox(height: 8),
          const ShimmerBox(height: 40, borderRadius: 20),
        ],
      ),
    );
  }

  Widget _buildSkeletonItemsList() {
    return ShimmerLoading(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 90),
        children: [
          _buildSkeletonHeaderCard(),
          for (int i = 0; i < 8; i++)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 4,
              ),
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black12.withOpacity(0.1),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
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
                    const ShimmerBox(height: 16, width: 160),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const ShimmerBox(
                          width: 70,
                          height: 22,
                          borderRadius: 30,
                        ),
                        const SizedBox(width: 8),
                        const ShimmerBox(
                          width: 80,
                          height: 22,
                          borderRadius: 20,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const ShimmerBox(height: 12, width: 100),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildItemCard(dynamic card) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 0),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        splashColor: app_color.withOpacity(0.1),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ItemsClicked(
                itemname: card.itemname,
                unit: card.unit,
                item_desc: card.description,
                item_lastsaledate: card.lastsale,
                item_lastpurchdate: card.lastpurc,
                item_rate: card.saleprice,
                inventory_closing: card.c_qty,
                lastpurcrate: card.purcprice,
                alias: card.alias,
              ),
            ),
          );
        },
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              colors: [
                Theme.of(context).cardColor.withOpacity(
                  Theme.of(context).brightness == Brightness.dark ? 0.96 : 0.9,
                ),
                Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest.withOpacity(
                  Theme.of(context).brightness == Brightness.dark ? 0.82 : 0.45,
                ),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black12.withOpacity(0.1),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
            border: Border.all(
              color: Theme.of(context).dividerColor.withOpacity(0.55),
              width: 1,
            ),
          ),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 🔹 Title & Unit
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 🔹 Left side (Item name + Unit)
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                card.itemname,
                                softWrap: true,
                                style: GoogleFonts.poppins(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: 8),

                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 5,
                                      horizontal: 14,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.teal,
                                      borderRadius: BorderRadius.circular(30),
                                    ),
                                    child: Text(
                                      "Qty: ${removeUnit(card.c_qty)}",
                                      style: GoogleFonts.poppins(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),

                                  const SizedBox(width: 8),

                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 5,
                                      horizontal: 14,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.orange.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: Colors.orange.shade300,
                                      ),
                                    ),
                                    child: Text(
                                      "Unit: ${card.unit}",
                                      style: GoogleFonts.poppins(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.orange.shade800,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color:
                                Theme.of(context).brightness == Brightness.dark
                                ? Theme.of(
                                    context,
                                  ).colorScheme.surfaceContainerHighest
                                : Theme.of(context).dividerColor.withOpacity(
                                    Theme.of(context).brightness ==
                                            Brightness.dark
                                        ? 0.35
                                        : 0.75,
                                  ),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black12,
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.chevron_right_rounded,
                            size: 20,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),

                    // 🔹 Alternate Unit
                    if (card.alternate_unit != 'null') ...[
                      const SizedBox(height: 8),
                      Text(
                        formatQtyDescription(
                          card.c_qty,
                          card.unit,
                          card.alternate_unit,
                          card.denominator,
                        ),
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],

                    const SizedBox(height: 16),
                    Divider(height: 1, color: Theme.of(context).dividerColor),
                    const SizedBox(height: 12),

                    // 🔹 Detail rows
                    _modernDetailRow(
                      Icons.sell_outlined,
                      "Last Sale Price",
                      "-",
                      valueWidget: card.saleprice != "null"
                          ? _currencyValueWidget(
                              formatAmountinDecimals(
                                double.parse(removeUnit(card.saleprice).toString()),
                                decimal!,
                              ),
                            )
                          : null,
                    ),

                    _modernDetailRow(
                      Icons.local_offer_outlined,
                      "Standard Price",
                      "-",
                      valueWidget: card.standardprice != "null"
                          ? _currencyValueWidget(
                              formatAmountinDecimals(
                                double.parse(removeUnit(card.standardprice).toString()),
                                decimal!,
                              ),
                            )
                          : null,
                    ),

                    if (rate_visibility && card.c_rate != "null")
                      _modernDetailRow(
                        Icons.attach_money,
                        "Rate",
                        "-",
                        valueWidget: _currencyValueWidget(
                          formatAmountinDecimals(
                            double.parse(removeUnit(card.c_rate).toString()),
                            decimal!,
                          ),
                        ),
                      ),

                    if (amount_visibility)
                      _modernDetailRow(
                        Icons.payments,
                        "Amount",
                        "-",
                        valueWidget: card.c_amount != "null"
                            ? _currencyValueWidget(
                                _formatAmountWithDRCRSuffix(card.c_amount.toString()),
                              )
                            : null,
                      ),

                    if (_isInactiveList)
                      _modernDetailRow(
                        Icons.calendar_today,
                        "Inactive Since",
                        formatlastsaledate(card.lastsale),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 🔹 Value widget for _modernDetailRow's currency rows - renders the new
  // Dirham glyph for AED (light/dark aware) while other currencies show
  // their plain symbol text unchanged, matching _modernDetailRow's style.
  Widget _currencyValueWidget(String amountText) {
    return currencyAmountText(
      currencyCode: _currencyCode,
      symbol: currencysymbol,
      amountText: amountText,
      overflow: TextOverflow.visible,
      style: GoogleFonts.poppins(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: Theme.of(context).colorScheme.onSurface,
      ),
    );
  }

  // 🔹 Modern detail row with icon pill
  Widget _modernDetailRow(
    IconData icon,
    String title,
    String value, {
    Widget? valueWidget,
  }) {
    // Gradient selection based on title
    LinearGradient getGradient(String title) {
      if (title.contains("Sale")) {
        return LinearGradient(
          colors: [Colors.blue.shade400, Colors.blue.shade700],
        );
      } else if (title.contains("Standard")) {
        return LinearGradient(
          colors: [Colors.purple.shade400, Colors.purple.shade700],
        );
      } else if (title.contains("Rate")) {
        return LinearGradient(
          colors: [Colors.green.shade400, Colors.green.shade700],
        );
      } else if (title.contains("Amount")) {
        return LinearGradient(
          colors: [Colors.orange.shade400, Colors.deepOrange.shade600],
        );
      } else if (title.contains("Inactive")) {
        return LinearGradient(
          colors: [Colors.grey.shade400, Colors.grey.shade600],
        );
      }
      return LinearGradient(
        colors: [app_color.withOpacity(0.4), app_color.withOpacity(0.7)],
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest.withOpacity(0.6)
            : Colors.grey.shade50.withOpacity(0.6),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          // 🔹 Icon Badge with dynamic gradient
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              gradient: getGradient(title),
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

          // 🔹 Title
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),

          // 🔹 Value
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: valueWidget ??
                  Text(
                    value,
                    textAlign:
                        TextAlign.right, // ✅ text inside also right aligned

                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    overflow: TextOverflow.visible,
                    softWrap: true,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: 16,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: app_color.withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.inventory_2_outlined,
              size: 40,
              color: app_color.withOpacity(0.6),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            "No items found",
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "Try a different search or filter",
            style: GoogleFonts.poppins(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  void _showFilterBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: 12),
          Text(
            "Filter By",
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          Divider(),
          RadioListTile<String>(
            value: "qty",
            groupValue: _selectedFilter,
            onChanged: (v) {
              setState(() => _selectedFilter = v);
              Navigator.pop(context);
              if (isClicked_movingsummary)
                fetchMovingSummary(_selecteditem);
            },
            title: Text("Quantity"),
          ),
          RadioListTile<String>(
            value: "value",
            groupValue: _selectedFilter,
            onChanged: (v) {
              setState(() => _selectedFilter = v);
              Navigator.pop(context);
              if (isClicked_movingsummary)
                fetchMovingSummary(_selecteditem);
            },
            title: Text("Sale Price"),
          ),
          SizedBox(height: 12),
        ],
      ),
    );
  }

  List<dynamic> _getVisibleList() {
    if (_isAllList) return filteredItems_all_items;
    if (_isActiveList) return filteredItems_active_items;
    return filteredItems_inactive_items;
  }

  void _onSearchChanged(String value) {
    final query = value.toLowerCase();
    setState(() {
      if (_isAllList) {
        filteredItems_all_items = all_items_list
            .where((e) => e.itemname.toLowerCase().contains(query))
            .toList();
      } else if (_isActiveList) {
        filteredItems_active_items = active_items_list
            .where((e) => e.itemname.toLowerCase().contains(query))
            .toList();
      } else if (_isInactiveList) {
        filteredItems_inactive_items = inactive_items_list
            .where((e) => e.itemname.toLowerCase().contains(query))
            .toList();
      }
    });
  }

  Widget buildNeumorphicTab({
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return AnimatedContainer(
      duration: Duration(milliseconds: 50),
      margin: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: isSelected
            ? LinearGradient(
                colors: [
                  app_color.withOpacity(
                    Theme.of(context).brightness == Brightness.dark
                        ? 0.24
                        : 0.18,
                  ),
                  Theme.of(context).cardColor.withOpacity(
                    Theme.of(context).brightness == Brightness.dark
                        ? 0.92
                        : 0.72,
                  ),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: isSelected
            ? Theme.of(context).cardColor.withOpacity(0.6)
            : Theme.of(context).cardColor,
        border: Border.all(
          color: isSelected ? app_color : Theme.of(context).dividerColor,
          width: isSelected ? 2 : 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: isSelected
                ? app_color.withOpacity(
                    Theme.of(context).brightness == Brightness.dark
                        ? 0.24
                        : 0.18,
                  )
                : Theme.of(context).dividerColor.withOpacity(
                    Theme.of(context).brightness == Brightness.dark
                        ? 0.35
                        : 0.75,
                  ),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          splashColor: app_color.withOpacity(0.2),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: isSelected
                      ? app_color
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                SizedBox(width: 6),
                Text(
                  label,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isSelected
                        ? app_color
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIconRow(IconData icon, String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 13.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),

        Text(
          value,
          style: GoogleFonts.poppins(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ],
    );
  }

  void _showInactiveDaysDialog(BuildContext context) {
    final TextEditingController daysController = TextEditingController();
    daysController.text = inactivedays.toString();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Theme.of(context).cardColor.withOpacity(0.85),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Theme.of(context).cardColor.withOpacity(0.9),
                  Theme.of(context).colorScheme.surfaceContainerHighest,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 12,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.timer_off, color: Colors.redAccent, size: 40),
                const SizedBox(height: 12),
                Text(
                  "Inactive Items",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "Enter number of days to filter inactive items:",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),

                // Modern TextField
                TextField(
                  controller: daysController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: "e.g. 30",
                    prefixIcon: Icon(
                      Icons.calendar_today,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    filled: true,
                    fillColor:
                        Theme.of(context).inputDecorationTheme.fillColor ??
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide(
                        color: Theme.of(context).dividerColor,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide(
                        color: Theme.of(context).dividerColor,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide(color: Colors.teal, width: 1.8),
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // Buttons row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        textStyle: TextStyle(fontSize: 16),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx); // close without action
                      },
                      child: const Text("Cancel"),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal,

                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                      onPressed: () {
                        final input = daysController.text.trim();
                        if (input.isNotEmpty && int.tryParse(input) != null) {
                          inactivedays = input;

                          // Call your same logic with days
                          fetchItemData('InactiveItems', _selecteditem);
                          Navigator.pop(ctx);
                        }
                      },
                      child: Text(
                        "Apply",
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
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
