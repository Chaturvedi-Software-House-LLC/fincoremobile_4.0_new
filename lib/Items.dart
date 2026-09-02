import 'dart:io';
import 'package:FincoreGo/currencyFormat.dart';
import 'package:FincoreGo/utils/currency_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'ItemsClicked.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'constants.dart';
import 'package:FincoreGo/widgets/app_bottom_nav.dart';
import 'package:FincoreGo/widgets/app_navigation.dart';
import 'widgets/scroll_fab.dart';
import 'widgets/searchable_selector.dart';
import 'widgets/entry_widgets.dart';
import 'providers/items_notifier.dart';

class items {
  final int masterId;
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
    required this.masterId,
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

  /// Maps a tally-api stock-items row (base `/stock-items` list, or
  /// `reports/stock-items/movement-analysis` for the fast/slow/inactive
  /// lists) - no legacy `getitem`/`getMoving` shape survives here.
  ///
  /// `standardprice` maps to tally-api's `stardardPrice` (its own literal
  /// field name, misspelled server-side - not a typo introduced here) -
  /// Tally's "Standard Selling Price", not "standardCost" (a separate
  /// field this repo doesn't currently surface). Movement-analysis rows
  /// don't carry contact-style detail fields at all (only
  /// masterId/name/closingQuantity/totalQuantitySold/totalAmountSold), so
  /// every field below is null/'null' for those - matching how the legacy
  /// `items` model already tolerates missing fields via `.toString()`.
  factory items.fromJson(Map<String, dynamic> json) {
    final alias = (json['alias'] as List?)?.cast<String>() ?? const [];
    return items(
      masterId: json['masterId'] as int,
      itemname: (json['name'] ?? '').toString(),
      alias: alias.isEmpty ? 'null' : alias.join(', '),
      unit: (json['baseUnitSymbol'] ?? 'null').toString(),
      saleprice: (json['lastSalePrice'] ?? 'null').toString(),
      c_qty: (json['closingQuantity'] ?? 'null').toString(),
      c_rate: (json['closingRate'] ?? 'null').toString(),
      c_amount: (json['closingAmount'] ?? 'null').toString(),
      description: (json['description'] ?? 'null').toString(),
      lastsale: (json['lastSaleDate'] ?? 'null').toString(),
      lastpurc: (json['lastPurchaseDate'] ?? 'null').toString(),
      purcprice: (json['lastPurchaseCost'] ?? 'null').toString(),
      standardprice: (json['stardardPrice'] ?? 'null').toString(),
      alternate_unit: (json['additionalUnitSymbol'] ?? 'null').toString(),
      denominator: (json['denominator'] ?? 'null').toString(),
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

class Items extends ConsumerStatefulWidget {
  @override
  ConsumerState<Items> createState() => _ItemsPageState();
}

class _ItemsPageState extends ConsumerState<Items>
    with TickerProviderStateMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ScrollController _scrollFabController = ScrollController();

  // Never toggled via setState in this screen (the IconButton that would
  // flip it is commented out below) - kept as a plain widget-local
  // constant rather than moved into ItemsState.
  final bool _isSearchViewVisible = true;

  ItemsState get _s => ref.read(itemsNotifierProvider);
  ItemsNotifier get _notifier => ref.read(itemsNotifierProvider.notifier);

  // Renders without the leading symbol, for use with _currencyValueWidget
  // (which renders the symbol itself so it can swap in the Dirham glyph
  // for AED).
  String _formatAmountWithDRCRSuffix(String value) {
    if (value == "null" || value.isEmpty) {
      return "-";
    }

    double amount = double.tryParse(value) ?? 0;
    String formatted = formatAmountinDecimals(amount.abs(), _s.decimal!);
    return amount < 0 ? "$formatted DR" : "$formatted CR";
  }

  void showToast(String message) {
    showAppMessage(context, message);
  }

  TextEditingController searchController = TextEditingController();

  String allitems = 'All Items';

  late GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey;

  Future<void> generateAndShareCSV_AllItems(List<items> items) async {
    final List<List<dynamic>> csvData = [];
    csvData.add([
      'Item Name',
      'Qty',
      'Rate',
      'Last Sale Price',
      'Standard Selling Price',
      'Amount',
    ]);

    for (final item in items) {
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
        text: 'Sharing All Items Report of ${_s.company}',
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

    for (final item in _s.filteredItems_active_items) {
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
        text: 'Sharing Fast/Slow Moving Items Report of ${_s.company}',
        files: [XFile(tempFilePath)],
      ),
    );
  }

  Future<void> generateAndShareCSV_ItemAgeing() async {
    final List<List<dynamic>> csvData = [];

    if (_s.selectedItemAgeingBucket != null) {
      csvData.add(['Item Name', 'Qty', 'Last Sale', 'Last Purchase', 'Amount']);
      for (final item in _s.selectedItemAgeingBucket!.itemsList) {
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
      for (final bucket in _s.itemAgeingBuckets) {
        csvData.add([
          bucket.label,
          bucket.count,
          formatAmount(bucket.value.toString()),
        ]);
      }
    }

    final csvString = const ListToCsvConverter().convert(csvData);
    final tempDir = await Directory.systemTemp.createTemp();
    final fileName = _s.selectedItemAgeingBucket != null
        ? 'ItemAgeing_${_s.selectedItemAgeingBucket!.label}.csv'
        : 'ItemAgeing_Summary.csv';
    final tempFilePath = '${tempDir.path}/$fileName';
    final file = File(tempFilePath);
    await file.writeAsString(csvString);

    await SharePlus.instance.share(
      ShareParams(
        text:
            'Sharing Item Ageing Report${_s.selectedItemAgeingBucket != null ? ' (${_s.selectedItemAgeingBucket!.label})' : ''} of ${_s.company}',
        files: [XFile(tempFilePath)],
      ),
    );
  }

  Future<void> generateAndSharePDF_ItemAgeing() async {
    final font = pw.Font.ttf(
      await rootBundle.load("assets/fonts/NotoSans.ttf"),
    );
    final pdf = pw.Document();
    final companyName = _s.company;
    final bucket = _s.selectedItemAgeingBucket;

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
        : _s.itemAgeingBuckets
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
            'Sharing Item Ageing Report${bucket != null ? ' (${bucket.label})' : ''} of ${_s.company}',
        files: [XFile(tempFilePath)],
      ),
    );
  }

  Future<void> generateAndShareCSV_StockValuation() async {
    final List<List<dynamic>> csvData = [];
    csvData.add(['Rank', 'Item Name', 'Qty', 'Rate', 'Amount']);

    for (var i = 0; i < _s.stockValuationList.length; i++) {
      final item = _s.stockValuationList[i];
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
        text: 'Sharing Stock Valuation Report of ${_s.company}',
        files: [XFile(tempFilePath)],
      ),
    );
  }

  Future<void> generateAndSharePDF_StockValuation() async {
    final font = pw.Font.ttf(
      await rootBundle.load("assets/fonts/NotoSans.ttf"),
    );
    final pdf = pw.Document();
    final companyName = _s.company;
    final headersRow = ['Rank', 'Item Name', 'Qty', 'Rate', 'Amount'];

    final itemsPerPage = 8;
    final pageCount = (_s.stockValuationList.length / itemsPerPage)
        .ceil()
        .clamp(1, 1 << 30);

    for (int pageNumber = 0; pageNumber < pageCount; pageNumber++) {
      final startIndex = pageNumber * itemsPerPage;
      final endIndex = (pageNumber + 1) * itemsPerPage;
      final itemsSubset = _s.stockValuationList.sublist(
        startIndex,
        endIndex > _s.stockValuationList.length
            ? _s.stockValuationList.length
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
        text: 'Sharing Stock Valuation Report of ${_s.company}',
        files: [XFile(tempFilePath)],
      ),
    );
  }

  Future<void> generateAndShareCSV_MovingSummary() async {
    final List<List<dynamic>> csvData = [];

    if (_s.movingSummaryDrilldown != null) {
      final list = _s.movingSummaryDrilldown == 'fast'
          ? _s.fastMovingSummaryList
          : _s.slowMovingSummaryList;
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
        _s.fastMovingSummaryList.length,
        formatAmount(_movingListTotalValue(_s.fastMovingSummaryList).toString()),
      ]);
      csvData.add([
        'Slow Moving',
        _s.slowMovingSummaryList.length,
        formatAmount(_movingListTotalValue(_s.slowMovingSummaryList).toString()),
      ]);
    }

    final csvString = const ListToCsvConverter().convert(csvData);
    final tempDir = await Directory.systemTemp.createTemp();
    final fileName = _s.movingSummaryDrilldown != null
        ? '${_s.movingSummaryDrilldown == 'fast' ? 'FastMoving' : 'SlowMoving'}Items.csv'
        : 'MovingSummary.csv';
    final tempFilePath = '${tempDir.path}/$fileName';
    final file = File(tempFilePath);
    await file.writeAsString(csvString);

    await SharePlus.instance.share(
      ShareParams(
        text: 'Sharing Fast vs Slow Moving Summary of ${_s.company}',
        files: [XFile(tempFilePath)],
      ),
    );
  }

  Future<void> generateAndSharePDF_MovingSummary() async {
    final font = pw.Font.ttf(
      await rootBundle.load("assets/fonts/NotoSans.ttf"),
    );
    final pdf = pw.Document();
    final companyName = _s.company;

    if (_s.movingSummaryDrilldown != null) {
      final list = _s.movingSummaryDrilldown == 'fast'
          ? _s.fastMovingSummaryList
          : _s.slowMovingSummaryList;
      final reportname = _s.movingSummaryDrilldown == 'fast'
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
          _s.fastMovingSummaryList.length.toString(),
          formatAmount(_movingListTotalValue(_s.fastMovingSummaryList).toString()),
        ],
        [
          'Slow Moving',
          _s.slowMovingSummaryList.length.toString(),
          formatAmount(_movingListTotalValue(_s.slowMovingSummaryList).toString()),
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
    final fileName = _s.movingSummaryDrilldown != null
        ? '${_s.movingSummaryDrilldown == 'fast' ? 'FastMoving' : 'SlowMoving'}Items.pdf'
        : 'MovingSummary.pdf';
    final tempFilePath = '${tempDir.path}/$fileName';
    final file = File(tempFilePath);
    await file.writeAsBytes(pdfData);

    await SharePlus.instance.share(
      ShareParams(
        text: 'Sharing Fast vs Slow Moving Summary of ${_s.company}',
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

    for (final item in _s.filteredItems_inactive_items) {
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
        text: 'Sharing Inactive Items Report of ${_s.company}',
        files: [XFile(tempFilePath)],
      ),
    );
  }

  Future<void> generateAndSharePDF_AllItems(List<items> items) async {
    final font = pw.Font.ttf(
      await rootBundle.load("assets/fonts/NotoSans.ttf"),
    );

    final pdf = pw.Document();
    final companyName = _s.company;
    final reportname = 'Stock Summary';
    final parentname = _s.selectedItem ?? '';
    final headersRow3 = [
      'Item Name',
      'Qty',
      'Rate',
      'Last Sale Price',
      'Standard Selling Price',
      'Amount',
    ];

    final itemsPerPage = 8;
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
        text: 'Sharing All Items Report of ${_s.company}',
        files: [XFile(tempFilePath)],
      ),
    );
  }

  Future<void> generateAndSharePDF_FastSlowItems() async {
    final font = pw.Font.ttf(
      await rootBundle.load("assets/fonts/NotoSans.ttf"),
    );
    final pdf = pw.Document();
    final companyName = _s.company;
    final reportname = 'Stock Summary';
    final parentname = _s.selectedItem ?? '';
    final headersRow3 = [
      'Item Name',
      'Qty',
      'Rate',
      'Last Sale Price',
      'Standard Selling Price',
      'Amount',
    ];

    final itemsPerPage = 8;
    final pageCount = (_s.filteredItems_active_items.length / itemsPerPage).ceil();

    for (int pageNumber = 0; pageNumber < pageCount; pageNumber++) {
      final startIndex = pageNumber * itemsPerPage;
      final endIndex = (pageNumber + 1) * itemsPerPage;
      final itemsSubset = _s.filteredItems_active_items.sublist(
        startIndex,
        endIndex > _s.filteredItems_active_items.length
            ? _s.filteredItems_active_items.length
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
        text: 'Sharing Fast/Slow Moving Items Report of ${_s.company}',
        files: [XFile(tempFilePath)],
      ),
    );
  }

  Future<void> generateAndSharePDF_InactiveItems() async {
    final font = pw.Font.ttf(
      await rootBundle.load("assets/fonts/NotoSans.ttf"),
    );
    final pdf = pw.Document();
    final companyName = _s.company;
    final reportname = 'Stock Summary';
    final parentname = _s.selectedItem ?? '';
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
    final pageCount = (_s.filteredItems_inactive_items.length / itemsPerPage)
        .ceil();

    for (int pageNumber = 0; pageNumber < pageCount; pageNumber++) {
      final startIndex = pageNumber * itemsPerPage;
      final endIndex = (pageNumber + 1) * itemsPerPage;
      final itemsSubset = _s.inactive_items_list.sublist(
        startIndex,
        endIndex > _s.filteredItems_inactive_items.length
            ? _s.filteredItems_inactive_items.length
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
        text: 'Sharing Inactive Items Report of ${_s.company}',
        files: [XFile(tempFilePath)],
      ),
    );
  }

  void _onItemsScroll() {
    if (!_s.isClicked_allitems || !_s.isAllList) return;
    if (_s.isLoadingMoreItems || _s.itemsPage > _s.itemsTotalPages) return;
    if (!_scrollFabController.hasClients) return;
    final position = _scrollFabController.position;
    if (position.pixels >= position.maxScrollExtent - 400) {
      _notifier.loadMoreItemsIfNeeded(searchController.text);
    }
  }

  double _movingListTotalValue(List<items> list) {
    return list.fold<double>(
      0.0,
      (sum, item) => sum + (double.tryParse(item.c_amount) ?? 0.0),
    );
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

      // Agar value _s.decimal ke bagair hai → int dikhado
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
    _scrollFabController.removeListener(_onItemsScroll);
    _scrollFabController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
    _scrollFabController.addListener(_onItemsScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      checkCurrencyMismatch(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(itemsNotifierProvider);
    ref.listen<ItemsState>(itemsNotifierProvider, (previous, next) {
      if (next.errorMessage != null) {
        showAppMessage(context, next.errorMessage!);
        ref.read(itemsNotifierProvider.notifier).clearError();
      }
    });
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
                  _s.company,
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
                          if (_s.isClicked_movingsummary) {
                            if (_s.fastMovingSummaryList.isNotEmpty ||
                                _s.slowMovingSummaryList.isNotEmpty) {
                              generateAndSharePDF_MovingSummary();
                            } else {
                              showToast('Data Not Found');
                            }
                          } else if (_s.isClicked_stockvaluation) {
                            if (_s.stockValuationList.isNotEmpty) {
                              generateAndSharePDF_StockValuation();
                            } else {
                              showToast('Data Not Found');
                            }
                          } else if (_s.isClicked_itemageing) {
                            if (_s.itemAgeingBuckets.isNotEmpty) {
                              generateAndSharePDF_ItemAgeing();
                            } else {
                              showToast('Data Not Found');
                            }
                          } else if (_s.isAllList) {
                            if (!_s.all_items_list.isEmpty) {
                              _notifier.fullAllItemsForExport(searchController.text).then(
                                generateAndSharePDF_AllItems,
                              );
                            } else {
                              showToast('Data Not Found');
                            }
                          } else if (_s.isActiveList) {
                            if (!_s.active_items_list.isEmpty) {
                              generateAndSharePDF_FastSlowItems();
                            } else {
                              showToast('Data Not Found');
                            }
                          } else if (_s.isInactiveList) {
                            if (!_s.inactive_items_list.isEmpty) {
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

                          if (_s.isClicked_movingsummary) {
                            if (_s.fastMovingSummaryList.isNotEmpty ||
                                _s.slowMovingSummaryList.isNotEmpty) {
                              generateAndShareCSV_MovingSummary();
                            } else {
                              showToast('Data Not Found');
                            }
                          } else if (_s.isClicked_stockvaluation) {
                            if (_s.stockValuationList.isNotEmpty) {
                              generateAndShareCSV_StockValuation();
                            } else {
                              showToast('Data Not Found');
                            }
                          } else if (_s.isClicked_itemageing) {
                            if (_s.itemAgeingBuckets.isNotEmpty) {
                              generateAndShareCSV_ItemAgeing();
                            } else {
                              showToast('Data Not Found');
                            }
                          } else if (_s.isAllList) {
                            if (!_s.all_items_list.isEmpty) {
                              _notifier.fullAllItemsForExport(searchController.text).then(
                                generateAndShareCSV_AllItems,
                              );
                            } else {
                              showToast('Data Not Found');
                            }
                          } else if (_s.isActiveList) {
                            if (!_s.active_items_list.isEmpty) {
                              generateAndShareCSV_FastSlowItems();
                            } else {
                              showToast('Data Not Found');
                            }
                          } else if (_s.isInactiveList) {
                            if (!_s.inactive_items_list.isEmpty) {
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
            if (_s.isVisibleFilterby)
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
              if (_s.isVisibleParent)
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
                            !(_s.isClicked_movingsummary &&
                                _s.movingSummaryDrilldown == null) &&
                            !(_s.isClicked_itemageing &&
                                _s.selectedItemAgeingBucket == null))
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
                                onChanged: _s.isClicked_movingsummary
                                    ? _notifier.onMovingSummarySearchChanged
                                    : _s.isClicked_stockvaluation
                                    ? _notifier.onStockValuationSearchChanged
                                    : _s.isClicked_itemageing
                                    ? _notifier.onItemAgeingSearchChanged
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
              if (_s.isClicked_movingsummary)
                ..._buildMovingSummarySlivers()
              else if (_s.isClicked_stockvaluation)
                ..._buildStockValuationSlivers()
              else if (_s.isClicked_itemageing)
                ..._buildItemAgeingSlivers()
              else if (_s.isVisibleNoDataFound)
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

              // Bottom-of-list spinner while the next page of the "All
              // Items" tab loads - never shown for the other tabs, which
              // always load their full result set in one go.
              if (_s.isClicked_allitems && _s.isAllList && _s.isLoadingMoreItems)
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

          // 🔹 Loader Overlay - skeleton stand-in for the header (parent
          // dropdown + view selector) plus a list of item-card-shaped
          // placeholders while the initial fetch is in flight, replacing
          // the old dimmed spinner-over-stale-content overlay.
          if (_s.isLoading)
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
      child: SearchableSelectorField<String>(
        value: _s.selectedItem,
        items: _s.spinner_list,
        itemLabel: (v) => v,
        hintText: "Select Item",
        decorated: false,
        trailingIcon: Icons.keyboard_arrow_down_rounded,
        textStyle: GoogleFonts.poppins(
          fontSize: 13.5,
          color: Theme.of(context).colorScheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
        hintStyle: GoogleFonts.poppins(
          fontSize: 13,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        onChanged: (value) {
          _notifier.selectItem(value);
          searchController.clear();
          _notifier.fetchItemData('All Items', value);
        },
      ),
    );
  }

  List<_TabConfig> _buildViewOptions() {
    return [
      if (_s.allitems_visibility)
        _TabConfig(
          // Labeled "Item List" (not "All Items") to avoid duplicating
          // the parent-category dropdown right above it, which also
          // reads "All Items" when no category filter is applied - the
          // two together looked like an unexplained repeat.
          "Item List",
          Icons.inventory_2_outlined,
          _s.isClicked_allitems,
          () {
            searchController.clear();
            _notifier.fetchItemData('All Items', _s.selectedItem);
          },
        ),
      if (_s.fastmovingitems_visibility)
        _TabConfig(
          "Moving Summary",
          Icons.compare_arrows_rounded,
          _s.isClicked_movingsummary,
          () {
            searchController.clear();
            _notifier.fetchMovingSummary(_s.selectedItem ?? '');
          },
        ),
      if (_s.allitems_visibility)
        _TabConfig(
          "Stock Valuation",
          Icons.bar_chart_rounded,
          _s.isClicked_stockvaluation,
          () {
            searchController.clear();
            _notifier.fetchStockValuation(_s.selectedItem ?? '');
          },
        ),
      if (_s.allitems_visibility)
        _TabConfig(
          "Item Ageing",
          Icons.history_rounded,
          _s.isClicked_itemageing,
          () {
            searchController.clear();
            _notifier.fetchItemAgeing(_s.selectedItem ?? '');
          },
        ),
      if (_s.inactiveitems_visibility)
        _TabConfig(
          "Inactive",
          Icons.block,
          _s.isClicked_inactiveitems,
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
    if (_s.isLoading) {
      return [const SliverToBoxAdapter(child: SizedBox.shrink())];
    }

    if (_s.movingSummaryDrilldown != null) {
      final fullList = _s.movingSummaryDrilldown == 'fast'
          ? _s.fastMovingSummaryList
          : _s.slowMovingSummaryList;
      final visible = _isSearchViewVisible && searchController.text.isNotEmpty
          ? _s.movingSummaryFilteredDrilldown
          : fullList;

      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                _notifier.setMovingSummaryDrilldown(null);
                searchController.clear();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(Icons.arrow_back_rounded, size: 20, color: app_color),
                    const SizedBox(width: 8),
                    Text(
                      _s.movingSummaryDrilldown == 'fast'
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

    if (_s.fastMovingSummaryList.isEmpty && _s.slowMovingSummaryList.isEmpty) {
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
                list: _s.fastMovingSummaryList,
                onTap: () => _notifier.setMovingSummaryDrilldown('fast'),
              ),
              const SizedBox(height: 12),
              _buildMovingSummaryCard(
                title: 'Slow Moving',
                icon: Icons.timer_outlined,
                accentColor: Colors.deepOrange,
                list: _s.slowMovingSummaryList,
                onTap: () => _notifier.setMovingSummaryDrilldown('slow'),
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
    if (_s.isLoading) {
      return [const SliverToBoxAdapter(child: SizedBox.shrink())];
    }

    if (_s.stockValuationList.isEmpty) {
      return [
        SliverFillRemaining(hasScrollBody: false, child: _buildEmptyState()),
      ];
    }

    final visible = searchController.text.isNotEmpty
        ? _s.stockValuationFiltered
        : _s.stockValuationList;
    final totalValue = _stockValuationTotal(_s.stockValuationList);
    final absTotalValue = _stockValuationAbsTotal(_s.stockValuationList);

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
                        '${_s.stockValuationList.length} item${_s.stockValuationList.length == 1 ? '' : 's'}',
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
                _s.stockValuationList.indexOf(visible[index]) + 1,
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
                stockItemMasterId: item.masterId,
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
    if (_s.isLoading) {
      return [const SliverToBoxAdapter(child: SizedBox.shrink())];
    }

    if (_s.selectedItemAgeingBucket != null) {
      final bucket = _s.selectedItemAgeingBucket!;
      final visible = searchController.text.isNotEmpty
          ? _s.itemAgeingFilteredDrilldown
          : bucket.itemsList;

      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                _notifier.setSelectedItemAgeingBucket(null);
                searchController.clear();
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

    if (_s.itemAgeingBuckets.isEmpty) {
      return [
        SliverFillRemaining(hasScrollBody: false, child: _buildEmptyState()),
      ];
    }

    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Column(
            children: _s.itemAgeingBuckets.map((bucket) {
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
        _notifier.setSelectedItemAgeingBucket(bucket);
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
                stockItemMasterId: card.masterId,
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
                                _s.decimal!,
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
                                _s.decimal!,
                              ),
                            )
                          : null,
                    ),

                    if (_s.rate_visibility && card.c_rate != "null")
                      _modernDetailRow(
                        Icons.attach_money,
                        "Rate",
                        "-",
                        valueWidget: _currencyValueWidget(
                          formatAmountinDecimals(
                            double.parse(removeUnit(card.c_rate).toString()),
                            _s.decimal!,
                          ),
                        ),
                      ),

                    if (_s.amount_visibility)
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

                    if (_s.isInactiveList)
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
      currencyCode: _s.currencyCode,
      symbol: _s.currencysymbol,
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
            groupValue: _s.selectedFilter,
            onChanged: (v) {
              _notifier.selectFilter(v);
              Navigator.pop(context);
              if (_s.isClicked_movingsummary)
                _notifier.fetchMovingSummary(_s.selectedItem ?? '');
            },
            title: Text("Quantity"),
          ),
          RadioListTile<String>(
            value: "value",
            groupValue: _s.selectedFilter,
            onChanged: (v) {
              _notifier.selectFilter(v);
              Navigator.pop(context);
              if (_s.isClicked_movingsummary)
                _notifier.fetchMovingSummary(_s.selectedItem ?? '');
            },
            title: Text("Sale Price"),
          ),
          SizedBox(height: 12),
        ],
      ),
    );
  }

  List<dynamic> _getVisibleList() {
    if (_s.isAllList) return _s.filteredItems_all_items;
    if (_s.isActiveList) return _s.filteredItems_active_items;
    return _s.filteredItems_inactive_items;
  }

  /// Narrower than before on the "All Items" tab: tally-api's
  /// `/stock-items` list has no server-side name-search query param, so
  /// this only searches pages already loaded by infinite scroll
  /// (`_s.all_items_list`), not the whole _s.company's items. Fast/Slow Moving
  /// and Inactive Items are unaffected - those still load their full
  /// result set up front. See [ItemsNotifier.onSearchChanged] (and its
  /// private `_autoLoadPagesForItemSearch` helper) for the live-text-reread
  /// background-paging behavior this now drives.
  void _onSearchChanged(String value) {
    _notifier.onSearchChanged(value, () => searchController.text.toLowerCase());
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
    daysController.text = _s.inactivedays.toString();
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
                          _notifier.setInactiveDays(input);

                          // Call your same logic with days
                          _notifier.fetchItemData('InactiveItems', _s.selectedItem);
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
