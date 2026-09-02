import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:fl_chart/fl_chart.dart';
import 'package:FincoreGo/Items.dart';
import 'package:FincoreGo/currencyFormat.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'PartyClickedRecPayClicked.dart';
import 'PartyClickedSalePurcOrder.dart';
import 'PartyClickedSoldPurchaseClicked.dart';
import 'PartyDrillDown.dart';
import 'PartyTotalClickedRest.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'constants.dart';
import 'utils/number_formatter.dart';
import 'package:FincoreGo/widgets/app_bottom_nav.dart';
import 'package:FincoreGo/widgets/app_navigation.dart';
import 'widgets/entry_widgets.dart';
import 'providers/party_clicked_notifier.dart';

class Summary {
  final String vchtype, totalInvoice, averageAmount, lastdate, totalAmount;

  Summary({
    required this.vchtype,
    required this.totalInvoice,
    required this.averageAmount,
    required this.lastdate,
    required this.totalAmount,
  });

  factory Summary.fromJson(Map<String, dynamic> json) {
    return Summary(
      vchtype: json['vchtype'].toString(),
      totalInvoice: json['totalInvoice'].toString(),
      averageAmount: json['averageAmount'].toString(),
      lastdate: json['lastdate'].toString(),
      totalAmount: json['totalAmount'].toString(),
    );
  }
}

class Sold_Purchased {
  final String item, qty, unit, lastdate, rate;

  Sold_Purchased({
    required this.item,
    required this.qty,
    required this.unit,
    required this.lastdate,
    required this.rate,
  });

  factory Sold_Purchased.fromJson(Map<String, dynamic> json) {
    return Sold_Purchased(
      item: json['item'].toString(),
      qty: json['qty'].toString(),
      unit: json['unit'].toString(),
      lastdate: json['lastdate'].toString(),
      rate: json['rate'].toString(),
    );
  }
}

class months {
  final String mname, total;

  months({required this.mname, required this.total});

  factory months.fromJson(Map<String, dynamic> json) {
    return months(
      mname: json['mname'].toString(),
      total: json['total'].toString(),
    );
  }
}

class Rec_Pay {
  final String mname, total;

  Rec_Pay({required this.mname, required this.total});

  factory Rec_Pay.fromJson(Map<String, dynamic> json) {
    return Rec_Pay(
      mname: json['mname'].toString(),
      total: json['total'].toString(),
    );
  }
}

class PartyClicked extends ConsumerStatefulWidget {
  final String partyname;
  /// The ledger's tally-api `masterId` - every migrated report endpoint
  /// (`ledgerSummary`/`outstandingTotal`/`outstandingBills`/`itemSummary`)
  /// is masterId-keyed, not name-keyed. Nullable only so a legacy-paired
  /// session (which has no such id) still compiles/renders; those sessions
  /// simply see the "not available" empty states this file falls back to.
  final int? ledgerMasterId;
  const PartyClicked({required this.partyname, this.ledgerMasterId});
  @override
  ConsumerState<PartyClicked> createState() =>
      _PartyClickedPageState(partyname: partyname, ledgerMasterId: ledgerMasterId);
}

class _PartyClickedPageState extends ConsumerState<PartyClicked>
    with TickerProviderStateMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  String partyname = "";
  int? ledgerMasterId;

  _PartyClickedPageState({required this.partyname, this.ledgerMasterId});

  late final _args =
      PartyClickedArgs(partyname: partyname, ledgerMasterId: ledgerMasterId);

  PartyClickedNotifier get _notifier =>
      ref.read(partyClickedNotifierProvider(_args).notifier);
  PartyClickedState get _s => ref.read(partyClickedNotifierProvider(_args));

  TextEditingController searchController = TextEditingController();

  // Used to capture the Trend Overview chart as an image for the Summary
  // PDF export - the chart itself (fl_chart) has no direct PDF renderer,
  // so it's rendered normally on-screen and grabbed as a PNG snapshot.
  final GlobalKey _trendChartRepaintKey = GlobalKey();
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

  Future<void> _selectDateRange(BuildContext context) async {
    if (!_s.isTextEnabled) return;
    final initialDateRange = DateTimeRange(start: _startDate, end: _endDate);
    final earliestDate = DateTime.parse((await SharedPreferences.getInstance()).getString('startfrom')!);

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
    final earliestDate = DateTime.parse((await SharedPreferences.getInstance()).getString('startfrom')!);

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

  String _pdfFormatCrDr(String raw) {
    final value = double.tryParse(raw.replaceAll(',', '')) ?? 0.0;
    final formatted = CurrencyFormatter.formatCurrency_double(value.abs());
    return value >= 0 ? '$formatted CR' : '$formatted DR';
  }

  Future<Uint8List?> _captureTrendChartImage() async {
    try {
      final boundary =
          _trendChartRepaintKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final image = await boundary.toImage(pixelRatio: 2.5);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (e) {
      debugPrint('Trend chart capture failed: $e');
      return null;
    }
  }

  Future<void> generateAndSharePDF_Summary() async {
    final vm = _s;
    final company = vm.company;
    final SalesVisibility = vm.salesVisibility;
    final PurchaseVisibility = vm.purchaseVisibility;
    final ReceiptVisibility = vm.receiptVisibility;
    final PaymentVisibility = vm.paymentVisibility;
    final CreditnoteVisibility = vm.creditnoteVisibility;
    final DebitnoteVisibility = vm.debitnoteVisibility;
    final JournalVisibility = vm.journalVisibility;
    final ReceivableVisibility = vm.receivableVisibility;
    final PayableVisibility = vm.payableVisibility;
    final SalesOrderVisibility = vm.salesOrderVisibility;
    final PurchaseOrderVisibility = vm.purchaseOrderVisibility;
    final totalsaleamt = vm.totalsaleamt;
    final avgsalesinvoiceamt = vm.avgsalesinvoiceamt;
    final noofsalesinvoice = vm.noofsalesinvoice;
    final lastsaledate = vm.lastsaledate;
    final totalpurchaseamt = vm.totalpurchaseamt;
    final avgpurchaseinvoiceamt = vm.avgpurchaseinvoiceamt;
    final noofpurchaseinvoice = vm.noofpurchaseinvoice;
    final lastpurchasedate = vm.lastpurchasedate;
    final totalreceiptamt = vm.totalreceiptamt;
    final avgreceiptinvoiceamt = vm.avgreceiptinvoiceamt;
    final noofreceiptinvoice = vm.noofreceiptinvoice;
    final lastreceiptdate = vm.lastreceiptdate;
    final totalpaymentamt = vm.totalpaymentamt;
    final avgpaymentinvoiceamt = vm.avgpaymentinvoiceamt;
    final noofpaymentinvoice = vm.noofpaymentinvoice;
    final lastpaymentdate = vm.lastpaymentdate;
    final totalcreditnoteamt = vm.totalcreditnoteamt;
    final avgcreditnoteinvoiceamt = vm.avgcreditnoteinvoiceamt;
    final noofcreditnoteinvoice = vm.noofcreditnoteinvoice;
    final lastcreditnotedate = vm.lastcreditnotedate;
    final totaldebitnoteamt = vm.totaldebitnoteamt;
    final avgdebitnoteinvoiceamt = vm.avgdebitnoteinvoiceamt;
    final noofdebitnoteinvoice = vm.noofdebitnoteinvoice;
    final lastdebitnotedate = vm.lastdebitnotedate;
    final totaljournalamt = vm.totaljournalamt;
    final avgjournalinvoiceamt = vm.avgjournalinvoiceamt;
    final noofjournalinvoice = vm.noofjournalinvoice;
    final lastjournaldate = vm.lastjournaldate;
    final receivabletotal = vm.receivabletotal;
    final onAccountReceivable = vm.onAccountReceivable;
    final row1_receivable = vm.row1Receivable;
    final row2_receivable = vm.row2Receivable;
    final row3_receivable = vm.row3Receivable;
    final row4_receivable = vm.row4Receivable;
    final row5_receivable = vm.row5Receivable;
    final row6_receivable = vm.row6Receivable;
    final row1_receivable_heading = vm.row1ReceivableHeading;
    final row2_receivable_heading = vm.row2ReceivableHeading;
    final row3_receivable_heading = vm.row3ReceivableHeading;
    final row4_receivable_heading = vm.row4ReceivableHeading;
    final row5_receivable_heading = vm.row5ReceivableHeading;
    final row6_receivable_heading = vm.row6ReceivableHeading;
    final payabletotal = vm.payabletotal;
    final onAccountPayable = vm.onAccountPayable;
    final row1_payable = vm.row1Payable;
    final row2_payable = vm.row2Payable;
    final row3_payable = vm.row3Payable;
    final row4_payable = vm.row4Payable;
    final row5_payable = vm.row5Payable;
    final row6_payable = vm.row6Payable;
    final row1_payable_heading = vm.row1PayableHeading;
    final row2_payable_heading = vm.row2PayableHeading;
    final row3_payable_heading = vm.row3PayableHeading;
    final row4_payable_heading = vm.row4PayableHeading;
    final row5_payable_heading = vm.row5PayableHeading;
    final row6_payable_heading = vm.row6PayableHeading;
    final pendingsalesorder = vm.pendingsalesorder;
    final pendingpurchaseorder = vm.pendingpurchaseorder;
    final startDateString = vm.startDateString;
    final endDateString = vm.endDateString;

    final font = pw.Font.ttf(
      await rootBundle.load("assets/fonts/NotoSans.ttf"),
    );
    final pdf = pw.Document();

    final companyName = company;
    const reportname = 'Party Summary Report';

    final chartImageBytes =
        (SalesVisibility || PurchaseVisibility || ReceiptVisibility)
        ? await _captureTrendChartImage()
        : null;
    final chartImage = chartImageBytes != null
        ? pw.MemoryImage(chartImageBytes)
        : null;

    // One row per voucher type currently visible on the Summary screen -
    // mirrors the figures already shown on each SummaryExpansionCard.
    final summaryRows = <List<String>>[
      if (SalesVisibility)
        [
          'Sales',
          _pdfFormatCrDr(totalsaleamt),
          _pdfFormatCrDr(avgsalesinvoiceamt),
          noofsalesinvoice,
          convertDateFormat(lastsaledate),
        ],
      if (PurchaseVisibility)
        [
          'Purchase',
          _pdfFormatCrDr(totalpurchaseamt),
          _pdfFormatCrDr(avgpurchaseinvoiceamt),
          noofpurchaseinvoice,
          convertDateFormat(lastpurchasedate),
        ],
      if (ReceiptVisibility)
        [
          'Receipt',
          _pdfFormatCrDr(totalreceiptamt),
          _pdfFormatCrDr(avgreceiptinvoiceamt),
          noofreceiptinvoice,
          convertDateFormat(lastreceiptdate),
        ],
      if (PaymentVisibility)
        [
          'Payment',
          _pdfFormatCrDr(totalpaymentamt),
          _pdfFormatCrDr(avgpaymentinvoiceamt),
          noofpaymentinvoice,
          convertDateFormat(lastpaymentdate),
        ],
      if (CreditnoteVisibility)
        [
          'Credit Note',
          _pdfFormatCrDr(totalcreditnoteamt),
          _pdfFormatCrDr(avgcreditnoteinvoiceamt),
          noofcreditnoteinvoice,
          convertDateFormat(lastcreditnotedate),
        ],
      if (DebitnoteVisibility)
        [
          'Debit Note',
          _pdfFormatCrDr(totaldebitnoteamt),
          _pdfFormatCrDr(avgdebitnoteinvoiceamt),
          noofdebitnoteinvoice,
          convertDateFormat(lastdebitnotedate),
        ],
      if (JournalVisibility)
        [
          'Journal',
          _pdfFormatCrDr(totaljournalamt),
          _pdfFormatCrDr(avgjournalinvoiceamt),
          noofjournalinvoice,
          convertDateFormat(lastjournaldate),
        ],
    ];

    final summaryTable = pw.Table.fromTextArray(
      border: pw.TableBorder.all(width: 1),
      headerDecoration: pw.BoxDecoration(
        borderRadius: pw.BorderRadius.circular(2),
        color: PdfColors.grey300,
      ),
      headerHeight: 28,
      cellAlignment: pw.Alignment.centerLeft,
      cellPadding: const pw.EdgeInsets.all(6),
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: font),
      cellStyle: pw.TextStyle(fontSize: 11, font: font),
      headers: ['Type', 'Total', 'Average', 'Invoices', 'Last Date'],
      data: summaryRows,
    );

    // Ageing bucket breakdown - same 6 buckets + "On Account" shown on the
    // Receivable/Payable cards on screen.
    final receivableRows = <List<String>>[
      if (ReceivableVisibility) ...[
        ['On Account', _pdfFormatCrDr(onAccountReceivable)],
        [row1_receivable_heading, _pdfFormatCrDr(row1_receivable)],
        [row2_receivable_heading, _pdfFormatCrDr(row2_receivable)],
        [row3_receivable_heading, _pdfFormatCrDr(row3_receivable)],
        [row4_receivable_heading, _pdfFormatCrDr(row4_receivable)],
        [row5_receivable_heading, _pdfFormatCrDr(row5_receivable)],
        [row6_receivable_heading, _pdfFormatCrDr(row6_receivable)],
      ],
    ];

    final payableRows = <List<String>>[
      if (PayableVisibility) ...[
        ['On Account', _pdfFormatCrDr(onAccountPayable)],
        [row1_payable_heading, _pdfFormatCrDr(row1_payable)],
        [row2_payable_heading, _pdfFormatCrDr(row2_payable)],
        [row3_payable_heading, _pdfFormatCrDr(row3_payable)],
        [row4_payable_heading, _pdfFormatCrDr(row4_payable)],
        [row5_payable_heading, _pdfFormatCrDr(row5_payable)],
        [row6_payable_heading, _pdfFormatCrDr(row6_payable)],
      ],
    ];

    final pendingOrderRows = <List<String>>[
      if (SalesOrderVisibility)
        ['Pending Sales Order', _pdfFormatCrDr(pendingsalesorder)],
      if (PurchaseOrderVisibility)
        ['Pending Purchase Order', _pdfFormatCrDr(pendingpurchaseorder)],
    ];

    pw.Widget bucketTable(String title, List<List<String>> rows) {
      if (rows.isEmpty) return pw.SizedBox();
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(height: 16),
          pw.Text(
            title,
            style: pw.TextStyle(
              fontSize: 13,
              fontWeight: pw.FontWeight.bold,
              font: font,
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Table.fromTextArray(
            border: pw.TableBorder.all(width: 1),
            headerDecoration: pw.BoxDecoration(
              borderRadius: pw.BorderRadius.circular(2),
              color: PdfColors.grey300,
            ),
            headerHeight: 24,
            cellAlignment: pw.Alignment.centerLeft,
            cellPadding: const pw.EdgeInsets.all(6),
            headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              fontSize: 10,
              font: font,
            ),
            cellStyle: pw.TextStyle(fontSize: 10, font: font),
            headers: const ['Bucket (Days)', 'Amount'],
            data: rows,
          ),
        ],
      );
    }

    pw.Widget reportHeader() => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text(
          companyName,
          style: pw.TextStyle(
            fontSize: 20,
            fontWeight: pw.FontWeight.bold,
            font: font,
          ),
        ),
        pw.SizedBox(height: 10),
        pw.Text(
          reportname,
          style: pw.TextStyle(
            fontSize: 18,
            fontWeight: pw.FontWeight.bold,
            font: font,
          ),
        ),
        pw.SizedBox(height: 10),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.center,
          children: [
            pw.Text(
              convertDateFormat(startDateString),
              style: pw.TextStyle(fontSize: 14, font: font),
            ),
            pw.SizedBox(width: 5),
            pw.Text('to', style: pw.TextStyle(fontSize: 14, font: font)),
            pw.SizedBox(width: 5),
            pw.Text(
              convertDateFormat(endDateString),
              style: pw.TextStyle(fontSize: 14, font: font),
            ),
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.center,
          children: [
            pw.Text(
              'Ledger: ',
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
                font: font,
              ),
            ),
            pw.Text(
              partyname,
              style: pw.TextStyle(fontSize: 14, font: font),
            ),
          ],
        ),
      ],
    );

    pw.Widget outstandingBlock() {
      if (!(ReceivableVisibility || PayableVisibility)) {
        return pw.SizedBox();
      }
      return pw.Container(
        margin: const pw.EdgeInsets.only(top: 16),
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(width: 1, color: PdfColors.grey400),
          borderRadius: pw.BorderRadius.circular(6),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
          children: [
            if (ReceivableVisibility)
              pw.Column(
                children: [
                  pw.Text(
                    'Receivable',
                    style: pw.TextStyle(fontSize: 12, font: font),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    _pdfFormatCrDr(receivabletotal),
                    style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                      font: font,
                    ),
                  ),
                ],
              ),
            if (PayableVisibility)
              pw.Column(
                children: [
                  pw.Text(
                    'Payable',
                    style: pw.TextStyle(fontSize: 12, font: font),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    _pdfFormatCrDr(payabletotal),
                    style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                      font: font,
                    ),
                  ),
                ],
              ),
          ],
        ),
      );
    }

    pdf.addPage(
      pw.MultiPage(
        build: (context) => [
          reportHeader(),
          outstandingBlock(),
          if (chartImage != null) ...[
            pw.SizedBox(height: 20),
            pw.Text(
              'Trend Overview',
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
                font: font,
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Image(chartImage, height: 220),
          ],
          pw.SizedBox(height: 20),
          pw.Text(
            'Summary',
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
              font: font,
            ),
          ),
          pw.SizedBox(height: 8),
          summaryTable,
          bucketTable('Receivable Breakdown', receivableRows),
          bucketTable('Payable Breakdown', payableRows),
          if (pendingOrderRows.isNotEmpty) ...[
            pw.SizedBox(height: 16),
            pw.Text(
              'Pending Orders',
              style: pw.TextStyle(
                fontSize: 13,
                fontWeight: pw.FontWeight.bold,
                font: font,
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Table.fromTextArray(
              border: pw.TableBorder.all(width: 1),
              headerDecoration: pw.BoxDecoration(
                borderRadius: pw.BorderRadius.circular(2),
                color: PdfColors.grey300,
              ),
              headerHeight: 24,
              cellAlignment: pw.Alignment.centerLeft,
              cellPadding: const pw.EdgeInsets.all(6),
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 10,
                font: font,
              ),
              cellStyle: pw.TextStyle(fontSize: 10, font: font),
              headers: const ['Order Type', 'Amount'],
              data: pendingOrderRows,
            ),
          ],
        ],
      ),
    );

    final pdfData = await pdf.save();
    final tempDir = await getTemporaryDirectory();
    final tempFilePath = '${tempDir.path}/PartySummaryReport.pdf';
    final file = File(tempFilePath);
    await file.writeAsBytes(pdfData);

    await Share.shareXFiles([
      XFile(tempFilePath),
    ], text: 'Sharing $reportname of $company');
  }

  // ------------------------ SOLD PDF ------------------------
  Future<void> generateAndSharePDF_Sold() async {
    final vm = _s;
    final company = vm.company;
    final sold_list = vm.soldList;
    final startDateString = vm.startDateString;
    final endDateString = vm.endDateString;

    final font = pw.Font.ttf(
      await rootBundle.load("assets/fonts/NotoSans.ttf"),
    );
    final pdf = pw.Document();

    final companyName = company;
    final reportname = 'Party Wise Sales Summary';
    final party_name = partyname;

    final headersRow3 = ['Item', 'Qty', 'Last Sold', 'Rate'];

    final itemsPerPage = 10;
    final pageCount = (sold_list.length / itemsPerPage).ceil();

    for (int pageNumber = 0; pageNumber < pageCount; pageNumber++) {
      final startIndex = pageNumber * itemsPerPage;
      final endIndex = (pageNumber + 1) * itemsPerPage;
      final itemsSubset = sold_list.sublist(
        startIndex,
        endIndex > sold_list.length ? sold_list.length : endIndex,
      );

      final tableSubsetRows = itemsSubset.map((item) {
        return [
          item.item,
          item.qty,
          convertDateFormat(item.lastdate),
          item.rate,
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
            return pw.Column(
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
                      convertDateFormat(startDateString),
                      style: pw.TextStyle(fontSize: 16),
                    ),
                    pw.SizedBox(width: 5),
                    pw.Text('to', style: pw.TextStyle(fontSize: 16)),
                    pw.SizedBox(width: 5),
                    pw.Text(
                      convertDateFormat(endDateString),
                      style: pw.TextStyle(fontSize: 16),
                    ),
                  ],
                ),
                pw.SizedBox(height: 10),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  children: [
                    pw.Text(
                      'Ledger:',
                      style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(width: 5),
                    pw.Text(party_name, style: pw.TextStyle(fontSize: 16)),
                  ],
                ),
                pw.SizedBox(height: 20),
                pw.Expanded(child: tableSubset),
              ],
            );
          },
        ),
      );
    }

    final pdfData = await pdf.save();
    final tempDir = await getTemporaryDirectory();
    final tempFilePath = '${tempDir.path}/SoldReport.pdf';
    final file = File(tempFilePath);
    await file.writeAsBytes(pdfData);

    // ✅ Updated share method
    await Share.shareXFiles([
      XFile(tempFilePath),
    ], text: 'Sharing $reportname Report of $company');
  }

  // ------------------------ PURCHASE PDF ------------------------
  Future<void> generateAndSharePDF_Purchase() async {
    final vm = _s;
    final company = vm.company;
    final purchase_list = vm.purchaseList;
    final startDateString = vm.startDateString;
    final endDateString = vm.endDateString;

    final font = pw.Font.ttf(
      await rootBundle.load("assets/fonts/NotoSans.ttf"),
    );
    final pdf = pw.Document();

    final companyName = company;
    final reportname = 'Party Wise Purchase Summary';
    final party_name = partyname;
    final headersRow3 = ['Item', 'Qty', 'Last Purchased', 'Rate'];

    final itemsPerPage = 10;
    final pageCount = (purchase_list.length / itemsPerPage).ceil();

    for (int pageNumber = 0; pageNumber < pageCount; pageNumber++) {
      final startIndex = pageNumber * itemsPerPage;
      final endIndex = (pageNumber + 1) * itemsPerPage;
      final itemsSubset = purchase_list.sublist(
        startIndex,
        endIndex > purchase_list.length ? purchase_list.length : endIndex,
      );

      final tableSubsetRows = itemsSubset.map((item) {
        return [
          item.item,
          item.qty,
          convertDateFormat(item.lastdate),
          item.rate,
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
            return pw.Column(
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
                      convertDateFormat(startDateString),
                      style: pw.TextStyle(fontSize: 16),
                    ),
                    pw.SizedBox(width: 5),
                    pw.Text('to', style: pw.TextStyle(fontSize: 16)),
                    pw.SizedBox(width: 5),
                    pw.Text(
                      convertDateFormat(endDateString),
                      style: pw.TextStyle(fontSize: 16),
                    ),
                  ],
                ),
                pw.SizedBox(height: 10),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  children: [
                    pw.Text(
                      'Ledger:',
                      style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(width: 5),
                    pw.Text(party_name, style: pw.TextStyle(fontSize: 16)),
                  ],
                ),
                pw.SizedBox(height: 20),
                pw.Expanded(child: tableSubset),
              ],
            );
          },
        ),
      );
    }

    final pdfData = await pdf.save();
    final tempDir = await getTemporaryDirectory();
    final tempFilePath = '${tempDir.path}/PurchaseReport.pdf';
    final file = File(tempFilePath);
    await file.writeAsBytes(pdfData);

    // ✅ Updated share method
    await Share.shareXFiles([
      XFile(tempFilePath),
    ], text: 'Sharing $reportname Report of $company');
  }

  // ------------------------ SOLD CSV ------------------------
  Future<void> generateAndShareCSV_Sold() async {
    final vm = _s;
    final company = vm.company;
    final sold_list = vm.soldList;
    final List<List<dynamic>> csvData = [];
    final reportname = 'Party Wise Sales Summary';

    final headersRow = ['Item', 'Qty', 'Last Sold', 'Rate'];
    csvData.add(headersRow);

    for (final item in sold_list) {
      final rowData = [
        item.item,
        item.qty,
        convertDateFormat(item.lastdate),
        item.rate,
      ];
      csvData.add(rowData);
    }

    final csvString = const ListToCsvConverter().convert(csvData);
    final tempDir = await Directory.systemTemp.createTemp();
    final tempFilePath = '${tempDir.path}/SoldReport.csv';
    final file = File(tempFilePath);
    await file.writeAsString(csvString);

    // ✅ Updated share method
    await Share.shareXFiles([
      XFile(tempFilePath),
    ], text: 'Sharing $reportname Report of $company');
  }

  // ------------------------ PURCHASE CSV ------------------------
  Future<void> generateAndShareCSV_Purchase() async {
    final vm = _s;
    final company = vm.company;
    final purchase_list = vm.purchaseList;
    final List<List<dynamic>> csvData = [];
    final reportname = 'Party Wise Purchase Summary';

    final headersRow = ['Item', 'Qty', 'Last Purchased', 'Rate'];
    csvData.add(headersRow);

    for (final item in purchase_list) {
      final rowData = [
        item.item,
        item.qty,
        convertDateFormat(item.lastdate),
        item.rate,
      ];
      csvData.add(rowData);
    }

    final csvString = const ListToCsvConverter().convert(csvData);
    final tempDir = await Directory.systemTemp.createTemp();
    final tempFilePath = '${tempDir.path}/PurchaseReport.csv';
    final file = File(tempFilePath);
    await file.writeAsString(csvString);

    // ✅ Updated share method
    await Share.shareXFiles([
      XFile(tempFilePath),
    ], text: 'Sharing $reportname Report of $company');
  }

  String convertDateFormat(String dateStr) {
    String formattedDate = "";

    if (dateStr == '' || dateStr == 'null') {
    } else {
      DateTime date = DateTime.parse(dateStr);

      // Format the date to the desired output format
      formattedDate = DateFormat("dd-MMM-yy").format(date);
    }
    // Parse the input date string

    return formattedDate;
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(partyClickedNotifierProvider(_args));
    final vm = _s;
    final CreditnoteVisibility = vm.creditnoteVisibility;
    final DebitnoteVisibility = vm.debitnoteVisibility;
    final JournalVisibility = vm.journalVisibility;
    final PayableVisibility = vm.payableVisibility;
    final PaymentVisibility = vm.paymentVisibility;
    final PurchaseOrderVisibility = vm.purchaseOrderVisibility;
    final PurchaseVisibility = vm.purchaseVisibility;
    final ReceiptVisibility = vm.receiptVisibility;
    final ReceivableVisibility = vm.receivableVisibility;
    final SalesOrderVisibility = vm.salesOrderVisibility;
    final SalesVisibility = vm.salesVisibility;
    final _currencyCode = vm.currencyCode;
    final _isSearchViewVisible = vm.isSearchViewVisible;
    final _isLoading = vm.isLoading;
    final _selecteddate = vm.selectedDate;
    final avgcreditnoteinvoiceamt = vm.avgcreditnoteinvoiceamt;
    final avgdebitnoteinvoiceamt = vm.avgdebitnoteinvoiceamt;
    final avgjournalinvoiceamt = vm.avgjournalinvoiceamt;
    final avgpaymentinvoiceamt = vm.avgpaymentinvoiceamt;
    final avgpurchaseinvoiceamt = vm.avgpurchaseinvoiceamt;
    final avgreceiptinvoiceamt = vm.avgreceiptinvoiceamt;
    final avgsalesinvoiceamt = vm.avgsalesinvoiceamt;
    final currencysymbol = vm.currencySymbol;
    final date_range = this.date_range;
    final decimal = vm.decimal;
    final filteredItems_purchase = vm.filteredItemsPurchase;
    final filteredItems_sold = vm.filteredItemsSold;
    final isClicked_Purchase = vm.isClickedPurchase;
    final isClicked_Sold = vm.isClickedSold;
    final isClicked_Summary = vm.isClickedSummary;
    final isVisibleNoDataFound = vm.isVisibleNoDataFound;
    final isVisiblePurchaseList = vm.isVisiblePurchaseList;
    final isVisiblePurchaseBtn = vm.isVisiblePurchaseBtn;
    final isVisibleSoldBtn = vm.isVisibleSoldBtn;
    final isVisibleSoldList = vm.isVisibleSoldList;
    final isVisibleSummaryBtn = vm.isVisibleSummaryBtn;
    final isSearchLayoutVisible = vm.isSearchLayoutVisible;
    final item_count = vm.itemCount;
    final lastcreditnotedate = vm.lastcreditnotedate;
    final lastdebitnotedate = vm.lastdebitnotedate;
    final lastjournaldate = vm.lastjournaldate;
    final lastpaymentdate = vm.lastpaymentdate;
    final lastpurchasedate = vm.lastpurchasedate;
    final lastreceiptdate = vm.lastreceiptdate;
    final lastsaledate = vm.lastsaledate;
    final months_list_creditnote = vm.monthsListCreditnote;
    final months_list_debitnote = vm.monthsListDebitnote;
    final months_list_journal = vm.monthsListJournal;
    final months_list_payment = vm.monthsListPayment;
    final months_list_purchase = vm.monthsListPurchase;
    final months_list_receipt = vm.monthsListReceipt;
    final months_list_sales = vm.monthsListSales;
    final noofcreditnoteinvoice = vm.noofcreditnoteinvoice;
    final noofdebitnoteinvoice = vm.noofdebitnoteinvoice;
    final noofjournalinvoice = vm.noofjournalinvoice;
    final noofpaymentinvoice = vm.noofpaymentinvoice;
    final noofpurchaseinvoice = vm.noofpurchaseinvoice;
    final noofreceiptinvoice = vm.noofreceiptinvoice;
    final noofsalesinvoice = vm.noofsalesinvoice;
    final onAccountPayable = vm.onAccountPayable;
    final onAccountReceivable = vm.onAccountReceivable;
    final payabletotal = vm.payabletotal;
    final pendingsalesorder = vm.pendingsalesorder;
    final pendingpurchaseorder = vm.pendingpurchaseorder;
    final purchase_list = vm.purchaseList;
    final receivabletotal = vm.receivabletotal;
    final row1_payable = vm.row1Payable;
    final row1_payable_heading = vm.row1PayableHeading;
    final row1_payable_heading_value = vm.row1PayableHeadingValue;
    final row1_receivable = vm.row1Receivable;
    final row1_receivable_heading = vm.row1ReceivableHeading;
    final row1_receivable_heading_value = vm.row1ReceivableHeadingValue;
    final row2_payable = vm.row2Payable;
    final row2_payable_heading = vm.row2PayableHeading;
    final row2_payable_heading_value = vm.row2PayableHeadingValue;
    final row2_receivable = vm.row2Receivable;
    final row2_receivable_heading = vm.row2ReceivableHeading;
    final row2_receivable_heading_value = vm.row2ReceivableHeadingValue;
    final row3_payable = vm.row3Payable;
    final row3_payable_heading = vm.row3PayableHeading;
    final row3_payable_heading_value = vm.row3PayableHeadingValue;
    final row3_receivable = vm.row3Receivable;
    final row3_receivable_heading = vm.row3ReceivableHeading;
    final row3_receivable_heading_value = vm.row3ReceivableHeadingValue;
    final row4_payable = vm.row4Payable;
    final row4_payable_heading = vm.row4PayableHeading;
    final row4_payable_heading_value = vm.row4PayableHeadingValue;
    final row4_receivable = vm.row4Receivable;
    final row4_receivable_heading = vm.row4ReceivableHeading;
    final row4_receivable_heading_value = vm.row4ReceivableHeadingValue;
    final row5_payable = vm.row5Payable;
    final row5_payable_heading = vm.row5PayableHeading;
    final row5_payable_heading_value = vm.row5PayableHeadingValue;
    final row5_receivable = vm.row5Receivable;
    final row5_receivable_heading = vm.row5ReceivableHeading;
    final row5_receivable_heading_value = vm.row5ReceivableHeadingValue;
    final row6_payable = vm.row6Payable;
    final row6_payable_heading = vm.row6PayableHeading;
    final row6_payable_heading_value = vm.row6PayableHeadingValue;
    final row6_receivable = vm.row6Receivable;
    final row6_receivable_heading = vm.row6ReceivableHeading;
    final row6_receivable_heading_value = vm.row6ReceivableHeadingValue;
    final sold_list = vm.soldList;
    final startDateString = vm.startDateString;
    final endDateString = vm.endDateString;
    final startdate_text = vm.startDateText;
    final enddate_text = vm.endDateText;
    final totalcreditnoteamt = vm.totalcreditnoteamt;
    final totaldebitnoteamt = vm.totaldebitnoteamt;
    final totaljournalamt = vm.totaljournalamt;
    final totalpaymentamt = vm.totalpaymentamt;
    final totalpurchaseamt = vm.totalpurchaseamt;
    final totalreceiptamt = vm.totalreceiptamt;
    final totalsaleamt = vm.totalsaleamt;
    final company = vm.company;
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
          title: Text(
            partyname,
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          centerTitle: false,
          actions: [
            Visibility(
              visible: isClicked_Summary &&
                  (SalesVisibility ||
                      PurchaseVisibility ||
                      ReceiptVisibility ||
                      PaymentVisibility ||
                      CreditnoteVisibility ||
                      DebitnoteVisibility ||
                      JournalVisibility ||
                      ReceivableVisibility ||
                      PayableVisibility ||
                      SalesOrderVisibility ||
                      PurchaseOrderVisibility),
              child: IconButton(
                tooltip: 'Share Summary',
                icon: const Icon(Icons.share, color: Colors.white, size: 22),
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
                            generateAndSharePDF_Summary();
                          },
                          child: Row(
                            children: [
                              const Icon(
                                Icons.picture_as_pdf,
                                size: 16,
                                color: Colors.teal,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                'Share as PDF',
                                style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.normal,
                                  color: Colors.teal,
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
            ),
            Visibility(
              visible: isSearchLayoutVisible,
              child: Align(
                alignment: Alignment.centerRight,
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () {
                        final wasVisible = _isSearchViewVisible;
                        _notifier.toggleSearchView();
                        if (wasVisible) {
                          searchController.clear();
                        }
                      },
                      icon: Icon(Icons.search, color: Colors.white, size: 30),
                    ),
                    IconButton(
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
                                  if (isClicked_Sold) {
                                    if (!sold_list.isEmpty) {
                                      generateAndSharePDF_Sold();
                                    }
                                  } else if (isClicked_Purchase) {
                                    if (!purchase_list.isEmpty) {
                                      generateAndSharePDF_Purchase();
                                    }
                                  }
                                },
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.picture_as_pdf,
                                      size: 16,
                                      color: Colors.teal,
                                    ),
                                    SizedBox(width: 5),

                                    Text(
                                      'Share as PDF',
                                      style: GoogleFonts.poppins(
                                        fontWeight: FontWeight.normal,
                                        color: Colors.teal,
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

                                  if (isClicked_Sold) {
                                    if (!sold_list.isEmpty) {
                                      generateAndShareCSV_Sold();
                                    }
                                  } else if (isClicked_Purchase) {
                                    if (!purchase_list.isEmpty) {
                                      generateAndShareCSV_Purchase();
                                    }
                                  }
                                },
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.add_chart_outlined,
                                      size: 16,
                                      color: Colors.teal,
                                    ),
                                    SizedBox(width: 5),
                                    Text(
                                      'Share as CSV',
                                      style: GoogleFonts.poppins(
                                        fontWeight: FontWeight.normal,
                                        color: Colors.teal,
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
            ),
          ],
        ),
      ),

      body: Stack(
        children: [
          SizedBox.expand(
            child: Column(
              children: [
                Container(
                  margin: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                          width: double.infinity,
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
                            child: DropdownButton<dynamic>(
                              value: _selecteddate,
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
                              onChanged: (value) {
                                if (value != null) _handleDate(value);
                              },

                              items: date_range.map((item) {
                                return DropdownMenuItem<dynamic>(
                                  value: item,
                                  child: Text(item),
                                );
                              }).toList(),
                            ),
                          ),
                        ),

                        SizedBox(height: 8),

                        /// 📆 Date Range (Single Widget)
                        InkWell(
                          onTap: () => _selectDateRange(context),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            width: double.infinity,
                            padding: EdgeInsets.symmetric(
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
                                SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    "$startdate_text → $enddate_text",
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
                        ),
                      ],
                    ),
                ),

                Expanded(
                  child: Container(
                    margin: const EdgeInsets.only(
                      left: 16,
                      right: 16,
                      bottom: 16,
                    ),
                    padding: const EdgeInsets.only(
                      left: 0,
                      right: 0,
                      top: 4,
                      bottom: 10,
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
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          LayoutBuilder(
                            builder: (context, constraints) {
                              int countPerRow = constraints.maxWidth > 600
                                  ? 3
                                  : 2;
                              double buttonWidth =
                                  (constraints.maxWidth -
                                      (countPerRow - 1) * 12) /
                                  countPerRow;

                              return Wrap(
                                spacing: 12,
                                runSpacing: 12,
                                alignment: WrapAlignment.center,
                                children: [
                                  if (isVisibleSummaryBtn)
                                    SizedBox(
                                      width: buttonWidth,
                                      child: _buildModernTabButton(
                                        label: 'SUMMARY',
                                        isSelected: isClicked_Summary,
                                        onTap: _notifier.fetchSummary,
                                      ),
                                    ),
                                  if (isVisibleSoldBtn)
                                    SizedBox(
                                      width: buttonWidth,
                                      child: _buildModernTabButton(
                                        label: 'SOLD',
                                        isSelected: isClicked_Sold,
                                        onTap: () {
                                          _notifier.selectSoldTab();
                                        },
                                      ),
                                    ),
                                  if (isVisiblePurchaseBtn)
                                    SizedBox(
                                      width: buttonWidth,
                                      child: _buildModernTabButton(
                                        label: 'PURCHASED',
                                        isSelected: isClicked_Purchase,
                                        onTap: () {
                                          _notifier.selectPurchaseTab();
                                        },
                                      ),
                                    ),
                                ],
                              );
                            },
                          ),

                          /* Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 25),
                            child: Divider(
                              thickness: 1,
                              color: Theme.of(context).dividerColor,
                            ),
                          ),*/
                          if (isClicked_Summary)
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (isVisibleNoDataFound &&
                                    !ReceivableVisibility &&
                                    !PayableVisibility &&
                                    !SalesOrderVisibility &&
                                    !PurchaseOrderVisibility)
                                  SizedBox(
                                    height:
                                        MediaQuery.of(context).size.height *
                                        0.5,
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
                                if (SalesVisibility ||
                                    PurchaseVisibility ||
                                    ReceiptVisibility)
                                  RepaintBoundary(
                                    key: _trendChartRepaintKey,
                                    child: PartyTrendChartCard(
                                      series: [
                                        if (SalesVisibility)
                                          PartyTrendSeries(
                                            label: 'Sales',
                                            color: const Color(0xFF00BFA5),
                                            monthsList: months_list_sales,
                                          ),
                                        if (PurchaseVisibility)
                                          PartyTrendSeries(
                                            label: 'Purchase',
                                            color: const Color(0xFFFF6D00),
                                            monthsList: months_list_purchase,
                                          ),
                                        if (ReceiptVisibility)
                                          PartyTrendSeries(
                                            label: 'Receipt',
                                            color: const Color(0xFF2979FF),
                                            monthsList: months_list_receipt,
                                          ),
                                      ],
                                    ),
                                  ),
                                if (SalesVisibility)
                                  SummaryExpansionCard(
                                    title: 'Sales',
                                    totalAmount: totalsaleamt,
                                    lastDate: lastsaledate,
                                    count: noofsalesinvoice,
                                    type: "Sales",
                                    partyname: partyname,

                                    averageAmount: avgsalesinvoiceamt,
                                    months: months_list_sales,
                                    onTapTotal: () =>
                                        navigateToDetail('Sales', totalsaleamt),
                                    currencysymbol: currencysymbol,
                                    currencyCode: _currencyCode,
                                    decimal: decimal,
                                    ledgerMasterId: ledgerMasterId,
                                  ),

                                if (PurchaseVisibility)
                                  SummaryExpansionCard(
                                    title: 'Purchase',
                                    totalAmount: totalpurchaseamt,
                                    lastDate: lastpurchasedate,
                                    count: noofpurchaseinvoice,
                                    averageAmount: avgpurchaseinvoiceamt,
                                    months: months_list_purchase,
                                    type: "Purchase",
                                    partyname: partyname,
                                    currencysymbol: currencysymbol,
                                    currencyCode: _currencyCode,
                                    decimal: decimal,
                                    ledgerMasterId: ledgerMasterId,
                                    onTapTotal: () => navigateToDetail(
                                      'Purchase',
                                      totalpurchaseamt,
                                    ),
                                  ),

                                if (ReceiptVisibility)
                                  SummaryExpansionCard(
                                    title: 'Receipt',
                                    totalAmount: totalreceiptamt,
                                    lastDate: lastreceiptdate,
                                    count: noofreceiptinvoice,
                                    averageAmount: avgreceiptinvoiceamt,
                                    months: months_list_receipt,
                                    type: "Receipt",
                                    partyname: partyname,
                                    currencysymbol: currencysymbol,
                                    currencyCode: _currencyCode,
                                    decimal: decimal,
                                    ledgerMasterId: ledgerMasterId,
                                    onTapTotal: () {
                                      String amount = totalreceiptamt;

                                      print('amount -> $amount');
                                      String vchtype = 'Receipt';
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              PartyTotalClickedRest(
                                                startdate_string:
                                                    startDateString,
                                                enddate_string: endDateString,
                                                type: vchtype,
                                                total: amount,
                                                ledger: partyname,
                                                ledgerMasterId: ledgerMasterId,
                                              ),
                                        ),
                                      );
                                    },
                                  ),

                                if (PaymentVisibility)
                                  SummaryExpansionCard(
                                    title: 'Payment',
                                    totalAmount: totalpaymentamt,
                                    lastDate: lastpaymentdate,
                                    count: noofpaymentinvoice,
                                    averageAmount: avgpaymentinvoiceamt,
                                    months: months_list_payment,
                                    type: "Payment",
                                    partyname: partyname,
                                    currencysymbol: currencysymbol,
                                    currencyCode: _currencyCode,
                                    decimal: decimal,
                                    ledgerMasterId: ledgerMasterId,
                                    onTapTotal: () {
                                      String amount = totalpaymentamt;
                                      print('amount -> $amount');

                                      String vchtype = 'Payment';
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              PartyTotalClickedRest(
                                                startdate_string:
                                                    startDateString,
                                                enddate_string: endDateString,
                                                type: vchtype,
                                                total: amount,
                                                ledger: partyname,
                                                ledgerMasterId: ledgerMasterId,
                                              ),
                                        ),
                                      );
                                    },
                                  ),

                                if (CreditnoteVisibility)
                                  SummaryExpansionCard(
                                    title: 'Credit Note',
                                    totalAmount: totalcreditnoteamt,
                                    lastDate: lastcreditnotedate,
                                    count: noofcreditnoteinvoice,
                                    averageAmount: avgcreditnoteinvoiceamt,
                                    months: months_list_creditnote,
                                    type: "Credit Note",
                                    partyname: partyname,
                                    currencysymbol: currencysymbol,
                                    currencyCode: _currencyCode,
                                    decimal: decimal,
                                    ledgerMasterId: ledgerMasterId,
                                    onTapTotal: () => navigateToDetail(
                                      'Credit Note',
                                      totalcreditnoteamt,
                                    ),
                                  ),
                                if (DebitnoteVisibility)
                                  SummaryExpansionCard(
                                    title: 'Debit Note',
                                    totalAmount: totaldebitnoteamt,
                                    lastDate: lastdebitnotedate,
                                    count: noofdebitnoteinvoice,
                                    averageAmount: avgdebitnoteinvoiceamt,
                                    months: months_list_debitnote,
                                    type: "Debit Note",
                                    partyname: partyname,
                                    currencysymbol: currencysymbol,
                                    currencyCode: _currencyCode,
                                    decimal: decimal,
                                    ledgerMasterId: ledgerMasterId,
                                    onTapTotal: () => navigateToDetail(
                                      'Debit Note',
                                      totaldebitnoteamt,
                                    ),
                                  ),
                                if (JournalVisibility)
                                  SummaryExpansionCard(
                                    title: 'Journal',
                                    totalAmount: totaljournalamt,
                                    lastDate: lastjournaldate,
                                    count: noofjournalinvoice,
                                    averageAmount: avgjournalinvoiceamt,
                                    months: months_list_journal,
                                    type: "Journal",
                                    partyname: partyname,
                                    currencysymbol: currencysymbol,
                                    currencyCode: _currencyCode,
                                    decimal: decimal,
                                    ledgerMasterId: ledgerMasterId,
                                    onTapTotal: () {
                                      String amount = totaljournalamt;
                                      print('amount -> $amount');
                                      String vchtype = 'Journal';
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              PartyTotalClickedRest(
                                                startdate_string:
                                                    startDateString,
                                                enddate_string: endDateString,
                                                type: vchtype,
                                                total: amount,
                                                ledger: partyname,
                                                ledgerMasterId: ledgerMasterId,
                                              ),
                                        ),
                                      );
                                    },
                                  ),

                                if (ReceivableVisibility)
                                  ReceivableBreakdownCard(
                                    total: receivabletotal,
                                    onAccount: onAccountReceivable,
                                    currencysymbol: currencysymbol,
                                    currencyCode: _currencyCode,
                                    onTotalTap: () {
                                      navigateToReceivable(
                                        'Receivable',
                                        receivabletotal,
                                        '',
                                        'All',
                                      );
                                    },

                                    rows: [
                                      {
                                        'label': row1_receivable_heading,
                                        'value': row1_receivable,
                                        'onTap': () {
                                          navigateToReceivable(
                                            'Receivable',
                                            row1_receivable,
                                            ">",
                                            row1_receivable_heading_value,
                                          );
                                        },
                                      },
                                      {
                                        'label': row2_receivable_heading,
                                        'value': row2_receivable,
                                        'onTap': () {
                                          navigateToReceivable(
                                            'Receivable',
                                            row2_receivable,
                                            ">",
                                            row2_receivable_heading_value,
                                          );
                                        },
                                      },
                                      {
                                        'label': row3_receivable_heading,
                                        'value': row3_receivable,
                                        'onTap': () {
                                          navigateToReceivable(
                                            'Receivable',
                                            row3_receivable,
                                            ">",
                                            row3_receivable_heading_value,
                                          );
                                        },
                                      },
                                      {
                                        'label': row4_receivable_heading,
                                        'value': row4_receivable,
                                        'onTap': () {
                                          navigateToReceivable(
                                            'Receivable',
                                            row4_receivable,
                                            ">",
                                            row4_receivable_heading_value,
                                          );
                                        },
                                      },
                                      {
                                        'label': row5_receivable_heading,
                                        'value': row5_receivable,
                                        'onTap': () {
                                          navigateToReceivable(
                                            'Receivable',
                                            row5_receivable,
                                            ">",
                                            row5_receivable_heading_value,
                                          );
                                        },
                                      },
                                      {
                                        'label': row6_receivable_heading,
                                        'value': row6_receivable,
                                        'onTap': () {
                                          navigateToReceivable(
                                            'Receivable',
                                            row6_receivable,
                                            ">",
                                            row6_receivable_heading_value,
                                          );
                                        },
                                      },
                                    ],
                                  ),

                                if (PayableVisibility)
                                  PayableBreakdownCard(
                                    total: payabletotal,
                                    onAccount: onAccountPayable,
                                    currencysymbol: currencysymbol,
                                    currencyCode: _currencyCode,
                                    onTotalTap: () {
                                      navigateToPayable(
                                        'Payable',
                                        payabletotal.toString(),
                                        '',
                                        'All',
                                      );
                                    },
                                    rows: [
                                      {
                                        'label': row1_payable_heading,
                                        'value': row1_payable,
                                        'onTap': () {
                                          navigateToPayable(
                                            'Payable',
                                            row1_payable,
                                            ">",
                                            row1_payable_heading_value,
                                          );
                                        },
                                      },
                                      {
                                        'label': row2_payable_heading,
                                        'value': row2_payable,
                                        'onTap': () {
                                          navigateToPayable(
                                            'Payable',
                                            row2_payable,
                                            ">",
                                            row2_payable_heading_value,
                                          );
                                        },
                                      },
                                      {
                                        'label': row3_payable_heading,
                                        'value': row3_payable,
                                        'onTap': () {
                                          navigateToPayable(
                                            'Payable',
                                            row3_payable,
                                            ">",
                                            row3_payable_heading_value,
                                          );
                                        },
                                      },
                                      {
                                        'label': row4_payable_heading,
                                        'value': row4_payable,
                                        'onTap': () {
                                          navigateToPayable(
                                            'Payable',
                                            row4_payable,
                                            ">",
                                            row4_payable_heading_value,
                                          );
                                        },
                                      },
                                      {
                                        'label': row5_payable_heading,
                                        'value': row5_payable,
                                        'onTap': () {
                                          navigateToPayable(
                                            'Payable',
                                            row5_payable,
                                            ">",
                                            row5_payable_heading_value,
                                          );
                                        },
                                      },
                                      {
                                        'label': row6_payable_heading,
                                        'value': row6_payable,
                                        'onTap': () {
                                          navigateToPayable(
                                            'Payable',
                                            row6_payable,
                                            ">",
                                            row6_payable_heading_value,
                                          );
                                        },
                                      },
                                    ],
                                  ),

                                if (SalesOrderVisibility)
                                  PendingOrderTile(
                                    label: 'Pending Sales Order',
                                    amount: pendingsalesorder,
                                    currencysymbol: currencysymbol,
                                    currencyCode: _currencyCode,
                                    decimal: decimal!,
                                    onTap: () => navigateToOrder('salesorder'),
                                  ),

                                if (PurchaseOrderVisibility)
                                  PendingOrderTile(
                                    label: 'Pending Purchase Order',
                                    amount: pendingpurchaseorder,
                                    currencysymbol: currencysymbol,
                                    currencyCode: _currencyCode,
                                    decimal: decimal,
                                    onTap: () => navigateToOrder('purcorder'),
                                  ),
                              ],
                            ),

                          Visibility(
                            visible: isClicked_Sold,
                            child: Column(
                              children: [
                                // Header Count
                                Container(
                                  width: double.infinity,
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 10,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).cardColor,
                                    borderRadius: BorderRadius.circular(30),
                                    border: Border.all(
                                      color: Colors.teal,
                                      width: 1.2,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black12.withOpacity(0.05),
                                        blurRadius: 6,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(
                                        Icons.inventory_2_rounded,
                                        color: Colors.teal,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        '$item_count Items',
                                        style: GoogleFonts.poppins(
                                          fontSize: 14.5,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.teal,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                // Search Bar
                                if (_isSearchViewVisible)
                                  Padding(
                                    padding: EdgeInsets.only(
                                      left: 12,
                                      right: 12,
                                      top: 12,
                                    ),
                                    child: Material(
                                      elevation: 2,
                                      borderRadius: BorderRadius.circular(18),
                                      shadowColor: Colors.black12,

                                      child: TextField(
                                        controller: searchController,
                                        onChanged: (value) {
                                          _notifier.filterSold(value);
                                        },
                                        style: GoogleFonts.poppins(
                                          fontSize: 15,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurface,
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
                                              Theme.of(context)
                                                  .inputDecorationTheme
                                                  .fillColor ??
                                              Theme.of(context)
                                                  .colorScheme
                                                  .surfaceContainerHighest,
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                vertical: 14,
                                                horizontal: 16,
                                              ),
                                          enabledBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                            borderSide: BorderSide(
                                              color: Theme.of(
                                                context,
                                              ).dividerColor,
                                            ),
                                          ),
                                          focusedBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                            borderSide: const BorderSide(
                                              color: app_color,
                                              width: 1.5,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),

                                // No Data Message
                                if (isVisibleNoDataFound)
                                  SizedBox(
                                    height:
                                        MediaQuery.of(context).size.height *
                                        0.5,
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

                                // Sold List
                                if (isVisibleSoldList)
                                  ListView.builder(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    shrinkWrap: true,
                                    physics:
                                        const NeverScrollableScrollPhysics(),
                                    itemCount: filteredItems_sold.length,
                                    itemBuilder: (context, index) {
                                      final card = filteredItems_sold[index];
                                      return _buildSoldPurchaseCard(
                                        context: context,
                                        item: card.item,
                                        qty: card.qty,
                                        lastDate: card.lastdate,
                                        rate: card.rate,
                                        isSale: true,
                                        onTap: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  PartyClickedSoldPurchaseClicked(
                                                    startdate_string:
                                                        startDateString,
                                                    enddate_string:
                                                        endDateString,
                                                    type: 'Sales',
                                                    item: card.item,
                                                    unit: card.unit,
                                                    ledger: partyname,
                                                    ledgerMasterId:
                                                        ledgerMasterId,
                                                  ),
                                            ),
                                          );
                                        },
                                      );
                                    },
                                  ),
                              ],
                            ),
                          ),

                          Visibility(
                            visible: isClicked_Purchase,
                            child: Container(
                              width: double.infinity,
                              color: Theme.of(context).scaffoldBackgroundColor,
                              child: Column(
                                children: [
                                  /// 🔢 Item Count
                                  Container(
                                    width: double.infinity,
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 10,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).cardColor,
                                      borderRadius: BorderRadius.circular(30),
                                      border: Border.all(
                                        color: Colors.teal,
                                        width: 1.2,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black12.withOpacity(
                                            0.05,
                                          ),
                                          blurRadius: 6,
                                          offset: const Offset(0, 3),
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        const Icon(
                                          Icons.inventory_2_rounded,
                                          color: Colors.teal,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          '$item_count Items',
                                          style: GoogleFonts.poppins(
                                            fontSize: 14.5,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.teal,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  /// 🔍 Search Box
                                  if (_isSearchViewVisible)
                                    Padding(
                                      padding: EdgeInsets.only(
                                        left: 12,
                                        right: 12,
                                        top: 12,
                                      ),
                                      child: Material(
                                        elevation: 2,
                                        borderRadius: BorderRadius.circular(18),
                                        shadowColor: Colors.black12,

                                        child: TextField(
                                          controller: searchController,
                                          onChanged: (value) {
                                            _notifier.filterPurchase(value);
                                          },
                                          style: GoogleFonts.poppins(
                                            fontSize: 15,
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
                                                Theme.of(context)
                                                    .inputDecorationTheme
                                                    .fillColor ??
                                                Theme.of(context)
                                                    .colorScheme
                                                    .surfaceContainerHighest,
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                  vertical: 14,
                                                  horizontal: 16,
                                                ),
                                            enabledBorder: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(18),
                                              borderSide: BorderSide(
                                                color: Theme.of(
                                                  context,
                                                ).dividerColor,
                                              ),
                                            ),
                                            focusedBorder: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(18),
                                              borderSide: const BorderSide(
                                                color: app_color,
                                                width: 1.5,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),

                                  const SizedBox(height: 10),

                                  /// ❌ No Data
                                  if (isVisibleNoDataFound)
                                    SizedBox(
                                      height:
                                          MediaQuery.of(context).size.height *
                                          0.5,
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

                                  /// 📦 Purchase List
                                  if (isVisiblePurchaseList)
                                    ListView.builder(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 8,
                                      ),
                                      shrinkWrap: true,
                                      physics:
                                          const NeverScrollableScrollPhysics(),
                                      itemCount: filteredItems_purchase.length,
                                      itemBuilder: (context, index) {
                                        final card =
                                            filteredItems_purchase[index];
                                        return _buildSoldPurchaseCard(
                                          context: context,
                                          item: card.item,
                                          qty: card.qty,
                                          lastDate: card.lastdate,
                                          rate: card.rate,
                                          isSale: false,
                                          onTap: () {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (context) =>
                                                    PartyClickedSoldPurchaseClicked(
                                                      startdate_string:
                                                          startDateString,
                                                      enddate_string:
                                                          endDateString,
                                                      type: "Purchase",
                                                      item: card.item,
                                                      unit: card.unit,
                                                      ledger: partyname,
                                                      ledgerMasterId:
                                                          ledgerMasterId,
                                                    ),
                                              ),
                                            );
                                          },
                                        );
                                      },
                                    ),
                                ],
                              ),
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

          if (_isLoading)
            Positioned.fill(
              child: Container(
                color: Theme.of(context).scaffoldBackgroundColor,
                child: _buildSkeletonPartyDetail(),
              ),
            ),
        ],
      ),
    );
  }

  // Skeleton stand-in for the summary header + breakdown cards while the
  // initial fetch is in flight - replaces the old dimmed spinner overlay so
  // the loading state reads as "content incoming" instead of a blank page.
  // Generic (icon badge + title line + amount line per card) rather than
  // mirroring every SummaryExpansionCard/_BreakdownCardBase variant, since
  // the shape is close enough across all of them for the transition to
  // feel seamless.
  Widget _buildSkeletonPartyDetail() {
    return ShimmerLoading(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 90),
        children: [
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black12.withOpacity(0.12),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    ShimmerBox(width: 34, height: 34, borderRadius: 12),
                    SizedBox(width: 10),
                    Expanded(child: ShimmerBox(height: 16, width: 120)),
                    SizedBox(width: 8),
                    ShimmerBox(height: 16, width: 70),
                  ],
                ),
                const SizedBox(height: 14),
                const ShimmerBox(height: 12, width: 180),
                const SizedBox(height: 8),
                const ShimmerBox(height: 12, width: 150),
              ],
            ),
          ),
          for (int i = 0; i < 5; i++)
            Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 14,
              ),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12.withOpacity(0.12),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Row(
                children: const [
                  ShimmerBox(width: 34, height: 34, borderRadius: 12),
                  SizedBox(width: 10),
                  Expanded(child: ShimmerBox(height: 15, width: 130)),
                  SizedBox(width: 8),
                  ShimmerBox(height: 15, width: 80),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildModernTabButton({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            gradient: isSelected
                ? LinearGradient(
                    colors: [Colors.teal.shade400, Colors.teal.shade600],
                  )
                : LinearGradient(
                    colors: Theme.of(context).brightness == Brightness.dark
                        ? [
                            Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest
                                .withOpacity(0.7),
                            Theme.of(context).cardColor.withOpacity(0.95),
                          ]
                        : [Colors.grey.shade200, Colors.grey.shade100],
                  ),
            borderRadius: BorderRadius.circular(50),
            boxShadow: [
              if (isSelected)
                BoxShadow(
                  color: Colors.teal.withOpacity(0.2),
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              if (!isSelected &&
                  Theme.of(context).brightness == Brightness.light)
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.circle,
                size: 8,
                color: isSelected
                    ? Colors.white
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: isSelected
                      ? Colors.white
                      : Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void navigateToDetail(String vchtype, String amount) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PartyDrillDown(
          startdate_string: _s.startDateString,
          enddate_string: _s.endDateString,
          type: vchtype,
          total: amount,
          ledger: partyname,
          ledgerMasterId: ledgerMasterId,
        ),
      ),
    );
  }

  void navigateToReceivable(
    String type,
    String total,
    String variable,
    String variableType,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PartyTotalClickedRecPayClicked(
          startdate_string: _s.startDateString,
          enddate_string: _s.endDateString,
          type: type,
          total: total,
          ledger: partyname,
          variable: variable,
          variabletype: variableType,
          ledgerMasterId: ledgerMasterId,
        ),
      ),
    );
  }

  void navigateToPayable(
    String type,
    String total,
    String variable,
    String variableType,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PartyTotalClickedRecPayClicked(
          startdate_string: _s.startDateString,
          enddate_string: _s.endDateString,
          type: type,
          total: total,
          ledger: partyname,
          variable: variable,
          variabletype: variableType,
          ledgerMasterId: ledgerMasterId,
        ),
      ),
    );
  }

  void navigateToOrder(String type) {
    String vchtype = type == 'salesorder' ? 'sales' : 'purchase';

    print('vchtype -> $vchtype and type->$type');
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PartyClickedSalePurcOrder(
          startdate_string: _s.startDateString,
          enddate_string: _s.endDateString,
          type: type,
          ledger: partyname,
          vchtype: vchtype,
          ledgerMasterId: ledgerMasterId,
        ),
      ),
    );
  }
}

class SummaryExpansionCard extends StatelessWidget {
  final String title;
  final String totalAmount;
  final String lastDate;
  final String count;
  final String averageAmount;
  final List<dynamic> months;
  final VoidCallback onTapTotal;
  final String type;
  final String partyname;
  final int? decimal;
  final String? currencysymbol;
  final String? currencyCode;
  final int? ledgerMasterId;

  const SummaryExpansionCard({
    super.key,
    required this.title,
    required this.totalAmount,
    required this.lastDate,
    required this.count,
    required this.averageAmount,
    required this.months,
    required this.onTapTotal,
    required this.type,
    required this.partyname,
    this.decimal,
    this.currencysymbol,
    this.currencyCode,
    this.ledgerMasterId,
  });

  String formatAmountWithCrDr(String amount) {
    double value = double.tryParse(amount.replaceAll(',', '')) ?? 0.0;

    // ✅ Use provided decimal or fallback to 2
    final decimals = decimal ?? 2;
    final pattern = "#,##0.${'0' * decimals}";
    final formatted = NumberFormat(pattern).format(value.abs());

    // ✅ Add symbol only if provided
    final symbol = (currencysymbol != null && currencysymbol!.isNotEmpty)
        ? "${currencysymbol!} "
        : "";

    return value >= 0 ? "$symbol$formatted CR" : "$symbol$formatted DR";
  }

  // Widget counterpart of formatAmountWithCrDr - renders the Dirham glyph
  // for AED in its own span, matching every other currency's plain text.
  Widget formatAmountWithCrDrRich(
    String amount,
    TextStyle style, {
    TextAlign? textAlign,
    bool? softWrap,
    TextOverflow? overflow,
  }) {
    double value = double.tryParse(amount.replaceAll(',', '')) ?? 0.0;
    final decimals = decimal ?? 2;
    final pattern = "#,##0.${'0' * decimals}";
    final formatted = NumberFormat(pattern).format(value.abs());
    final suffix = value >= 0 ? 'CR' : 'DR';

    return currencyAmountText(
      currencyCode: currencyCode ?? 'AED',
      symbol: currencysymbol ?? '',
      amountText: '$formatted $suffix',
      textAlign: textAlign,
      softWrap: softWrap,
      overflow: overflow,
      style: style,
    );
  }

  IconData _getIconForTitle(String title) {
    switch (title.toLowerCase()) {
      case 'sales':
        return Icons.trending_up;
      case 'purchase':
        return Icons.shopping_cart_outlined;
      case 'receipt':
        return Icons.receipt_long;
      case 'payment':
        return Icons.payment;
      case 'credit note':
        return Icons.note_add_outlined;
      case 'debit note':
        return Icons.note_outlined;
      case 'journal':
        return Icons.book_online_outlined;
      default:
        return Icons.insert_chart_outlined_rounded;
    }
  }

  LinearGradient _getGradientForTitle(String title) {
    switch (title.toLowerCase()) {
      case 'sales':
        return LinearGradient(
          colors: [Colors.teal.shade400, Colors.teal.shade700],
        );
      case 'purchase':
        return LinearGradient(
          colors: [Colors.indigo.shade400, Colors.indigo.shade700],
        );
      case 'receipt':
        return LinearGradient(
          colors: [Colors.green.shade400, Colors.green.shade700],
        );
      case 'payment':
        return LinearGradient(
          colors: [Colors.redAccent.shade200, Colors.redAccent.shade400],
        );
      case 'credit note':
        return LinearGradient(
          colors: [Colors.orange.shade400, Colors.deepOrange.shade600],
        );
      case 'debit note':
        return LinearGradient(
          colors: [Colors.purple.shade400, Colors.purple.shade700],
        );
      case 'journal':
        return LinearGradient(
          colors: [Colors.brown.shade400, Colors.brown.shade700],
        );
      default:
        return LinearGradient(
          colors: [Colors.grey.shade400, Colors.grey.shade600],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalValueStyle = GoogleFonts.poppins(
      fontSize: 16,
      fontWeight: FontWeight.w700,
      color: Theme.of(context).brightness == Brightness.dark
          ? Colors.tealAccent.shade100
          : Colors.teal.shade700,
    );

    return Container(
      margin: const EdgeInsets.only(left: 12, right: 12, top: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Theme.of(context).cardColor,
            Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(
              Theme.of(context).brightness == Brightness.dark ? 0.55 : 0.28,
            ),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black12.withOpacity(0.12),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ExpansionTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        tilePadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        childrenPadding: EdgeInsets.zero,
        title: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  // 🔹 Gradient Icon Badge
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      gradient: _getGradientForTitle(title),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black12.withOpacity(0.2),
                          blurRadius: 8,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Icon(
                      _getIconForTitle(title),
                      color: Colors.white,
                      size: 18,
                    ),
                  ),

                  const SizedBox(width: 12),

                  // 🔹 Title Text
                  Expanded(
                    child: Text(
                      title,
                      style: GoogleFonts.poppins(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            SizedBox(width: 12),

            // 🔹 Total value (right aligned, wraps to next line if long)
            Flexible(
              child: formatAmountWithCrDrRich(
                totalAmount,
                totalValueStyle,
                textAlign: TextAlign.right,
                softWrap: true,
                overflow: TextOverflow.visible,
              ),
            ),
          ],
        ),

        children: [
          Divider(thickness: 1, color: Theme.of(context).dividerColor),

          // 🔹 Detail Rows
          DetailRowTile(label: 'Last $title Date', value: formatdate(lastDate)),
          DetailRowTile(label: 'No. of Invoices', value: count),
          DetailRowTile(
            label: 'Avg Invoice Amount',
            value: '',
            valueWidget: formatAmountWithCrDrRich(
              averageAmount,
              GoogleFonts.poppins(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),

          const SizedBox(height: 6),
          Divider(thickness: 1, color: Theme.of(context).dividerColor),

          // 🔹 Monthly Breakdown Expansion
          Theme(
            data: Theme.of(context).copyWith(
              dividerColor: Colors.transparent,
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
            ),
            child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 18),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // 🔹 Left side (icon + "Monthly Breakdown")
                  Expanded(
                    child: Row(
                      children: [
                        Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.blueGrey.shade400,
                                Colors.blueGrey.shade700,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.timeline_rounded,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Monthly Breakdown',
                            style: GoogleFonts.poppins(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 12),

                  // 🔹 Right side (formatted total) - sized to content so it
                  // doesn't compete for width with the label above and end
                  // up cramped against it.
                  formatAmountWithCrDrRich(
                    totalAmount,
                    GoogleFonts.poppins(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    softWrap: false,
                  ),
                ],
              ),

              children: [
                // 🔹 Total Row
                GestureDetector(
                  onTap: onTapTotal,
                  child: Container(
                    margin: const EdgeInsets.only(
                      left: 16,
                      right: 16,
                      bottom: 12,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black12.withOpacity(0.05),
                          blurRadius: 6,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.teal.shade400,
                                    Colors.teal.shade700,
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.link,
                                size: 16,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Total',
                              style: GoogleFonts.poppins(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w500,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            formatAmountWithCrDrRich(
                              totalAmount,
                              GoogleFonts.poppins(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                color:
                                    Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? Colors.white10
                                    : Colors.grey.shade200,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.chevron_right_rounded,
                                size: 16,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // 🔹 Monthly Rows
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: months.length,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  itemBuilder: (context, index) {
                    final card = months[index];
                    final month = card.mname;
                    final rawAmount = card.total.toString();

                    return GestureDetector(
                      onTap: () {
                        final dateTimeFormatter = DateFormat('MMMM yyyy');
                        final date = dateTimeFormatter.parse(month);
                        final startStr = DateFormat(
                          'yyyyMMdd',
                        ).format(DateTime(date.year, date.month, 1));
                        final endStr = DateFormat(
                          'yyyyMMdd',
                        ).format(DateTime(date.year, date.month + 1, 0));

                        if (type == "Receipt" ||
                            type == "Payment" ||
                            type == "Journal") {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => PartyTotalClickedRest(
                                startdate_string: startStr,
                                enddate_string: endStr,
                                type: type,
                                total: rawAmount,
                                ledger: partyname,
                                ledgerMasterId: ledgerMasterId,
                              ),
                            ),
                          );
                        } else {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => PartyDrillDown(
                                startdate_string: startStr,
                                enddate_string: endStr,
                                type: type,
                                total: rawAmount,
                                ledger: partyname,
                                ledgerMasterId: ledgerMasterId,
                              ),
                            ),
                          );
                        }
                        // NOTE: `ledgerMasterId` above resolves to
                        // `SummaryExpansionCard.ledgerMasterId` (this class
                        // is a StatelessWidget, not the page state).
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          borderRadius: BorderRadius.circular(18),
                          border:
                              Theme.of(context).brightness == Brightness.dark
                              ? Border.all(
                                  color: Colors.white.withOpacity(0.10),
                                  width: 1,
                                )
                              : null,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black12.withOpacity(0.05),
                              blurRadius: 6,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // 🔹 Left side (icon + month text)
                            Expanded(
                              child: Row(
                                children: [
                                  Container(
                                    width: 30,
                                    height: 30,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          Colors.indigo.shade400,
                                          Colors.indigo.shade700,
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(
                                      Icons.calendar_month_rounded,
                                      size: 16,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    // ✅ Prevents overflow
                                    child: Text(
                                      month,
                                      style: GoogleFonts.poppins(
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.w500,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurface,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow
                                          .ellipsis, // ✅ truncate instead of overlapping the amount
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(width: 12),

                            // 🔹 Right side (amount + arrow)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                formatAmountWithCrDrRich(
                                  rawAmount,
                                  GoogleFonts.poppins(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w600,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
                                  ),
                                  overflow: TextOverflow.visible,
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.all(3),
                                  decoration: BoxDecoration(
                                    color:
                                        Theme.of(context).brightness ==
                                            Brightness.dark
                                        ? Colors.white10
                                        : Colors.grey.shade200,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.chevron_right_rounded,
                                    size: 16,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Combines the already-fetched per-vchtype month summaries (Sales,
// Purchase, Receipt) into one multi-line trend chart, instead of the
// separate isolated month lists each SummaryExpansionCard already shows -
// no extra API calls, this just re-renders data already in memory.
enum _TrendGranularity { month, quarter, year }

class _TrendBucket {
  final String key;
  final DateTime sortDate;
  final String shortLabel;

  _TrendBucket({
    required this.key,
    required this.sortDate,
    required this.shortLabel,
  });
}

class PartyTrendChartCard extends StatelessWidget {
  final List<PartyTrendSeries> series;

  const PartyTrendChartCard({super.key, required this.series});

  // Finer-grained "nice number" steps than the usual 1/2/5/10 - the old
  // 5->10 gap meant a value just above 5x magnitude got rounded all the
  // way up to 10x (up to ~2x taller axis than the data needed).
  static const List<double> _niceSteps = [1, 1.5, 2, 2.5, 3, 4, 5, 6, 8, 10];

  double _niceMax(double rawMax) {
    if (rawMax <= 0 || !rawMax.isFinite) return 1;
    final padded = rawMax * 1.1;
    final exponent = (math.log(padded) / math.ln10).floor();
    final magnitude = math.pow(10, exponent).toDouble();
    final normalized = padded / magnitude;
    final nice = _niceSteps.firstWhere(
      (step) => normalized <= step,
      orElse: () => 10,
    );
    return nice * magnitude;
  }

  double _amount(String raw) {
    return (double.tryParse(raw.replaceAll(',', '')) ?? 0.0).abs();
  }

  DateTime? _parseMonth(String mname) {
    try {
      return DateFormat('MMMM yyyy').parse(mname);
    } catch (_) {
      return null;
    }
  }

  // Always plot at monthly resolution - crowding on long ranges is instead
  // handled by capping visible x-axis labels and simplifying the line
  // rendering (see isDense below), not by changing the data granularity.
  _TrendGranularity _pickGranularity(int distinctMonthCount) {
    return _TrendGranularity.month;
  }

  _TrendBucket _bucketFor(DateTime date, _TrendGranularity granularity) {
    switch (granularity) {
      case _TrendGranularity.month:
        return _TrendBucket(
          key: DateFormat('yyyy-MM').format(date),
          sortDate: DateTime(date.year, date.month, 1),
          // Always include the year - a bare "Jan" reads as ambiguous
          // (which year?) even when the visible data happens to be a
          // single year, so keep the label unambiguous in every case.
          shortLabel: DateFormat("MMM ''yy").format(date),
        );
      case _TrendGranularity.quarter:
        final quarter = ((date.month - 1) ~/ 3) + 1;
        final quarterStart = DateTime(date.year, (quarter - 1) * 3 + 1, 1);
        return _TrendBucket(
          key: '${date.year}-Q$quarter',
          sortDate: quarterStart,
          shortLabel: "Q$quarter '${DateFormat('yy').format(date)}",
        );
      case _TrendGranularity.year:
        return _TrendBucket(
          key: '${date.year}',
          sortDate: DateTime(date.year, 1, 1),
          shortLabel: '${date.year}',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibleSeries = series.where((s) => s.monthsList.isNotEmpty).toList();
    if (visibleSeries.isEmpty) return const SizedBox.shrink();

    final distinctMonths = <String>{};
    for (final s in visibleSeries) {
      for (final m in s.monthsList) {
        distinctMonths.add(m.mname);
      }
    }
    if (distinctMonths.isEmpty) return const SizedBox.shrink();

    final granularity = _pickGranularity(distinctMonths.length);

    // Aggregate each series' raw monthly totals into the chosen bucket
    // resolution (sum within a bucket), then union + sort the bucket keys
    // across all series so every line shares the same x-axis.
    final bucketsByKey = <String, _TrendBucket>{};
    final valuesBySeriesAndBucket = <int, Map<String, double>>{};

    for (var i = 0; i < visibleSeries.length; i++) {
      final totals = <String, double>{};
      for (final m in visibleSeries[i].monthsList) {
        final date = _parseMonth(m.mname);
        if (date == null) continue;
        final bucket = _bucketFor(date, granularity);
        bucketsByKey[bucket.key] = bucket;
        totals[bucket.key] = (totals[bucket.key] ?? 0.0) + _amount(m.total);
      }
      valuesBySeriesAndBucket[i] = totals;
    }

    final orderedBuckets = bucketsByKey.values.toList()
      ..sort((a, b) => a.sortDate.compareTo(b.sortDate));
    if (orderedBuckets.isEmpty) return const SizedBox.shrink();

    final shortLabels = orderedBuckets.map((b) => b.shortLabel).toList();

    var maxValue = 0.0;
    for (final totals in valuesBySeriesAndBucket.values) {
      for (final v in totals.values) {
        maxValue = math.max(maxValue, v);
      }
    }
    final maxY = _niceMax(maxValue);
    final interval = maxY / 4;

    // Even after bucketing, cap how many labels actually render so they
    // never overlap - the rest are simply skipped, evenly spaced.
    const maxVisibleLabels = 7;
    final labelStep = (orderedBuckets.length / maxVisibleLabels).ceil().clamp(
      1,
      orderedBuckets.length,
    );

    final isDense = orderedBuckets.length > 24;
    final barsData = <LineChartBarData>[
      for (var i = 0; i < visibleSeries.length; i++)
        LineChartBarData(
          spots: [
            for (var b = 0; b < orderedBuckets.length; b++)
              FlSpot(
                b.toDouble(),
                valuesBySeriesAndBucket[i]![orderedBuckets[b].key] ?? 0.0,
              ),
          ],
          isCurved: !isDense,
          curveSmoothness: 0.22,
          color: visibleSeries[i].color,
          barWidth: 3,
          isStrokeCapRound: true,
          dotData: FlDotData(
            show: !isDense,
            getDotPainter: (spot, percent, barData, index) =>
                FlDotCirclePainter(
                  radius: 3.5,
                  color: Colors.white,
                  strokeWidth: 2,
                  strokeColor: visibleSeries[i].color,
                ),
          ),
          belowBarData: BarAreaData(show: false),
        ),
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Theme.of(context).brightness == Brightness.dark
            ? Border.all(color: Colors.white.withOpacity(0.10), width: 1)
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black12.withOpacity(0.05),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Trend Overview',
            style: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: visibleSeries
                .map((s) => _TrendLegendDot(color: s.color, label: s.label))
                .toList(),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 220,
            child: LineChart(
              LineChartData(
                minX: orderedBuckets.length > 1 ? -0.15 : -0.5,
                maxX: orderedBuckets.length > 1
                    ? orderedBuckets.length - 0.85
                    : 0.5,
                minY: 0,
                maxY: maxY,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: interval,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: Theme.of(context).dividerColor,
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 52,
                      interval: interval,
                      getTitlesWidget: (value, meta) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Text(
                          formatNumberAbbreviation(
                            value,
                            decimalPlaces: 1,
                            showSuffix: false,
                          ),
                          style: GoogleFonts.poppins(
                            fontSize: 10,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      interval: labelStep.toDouble(),
                      getTitlesWidget: (value, meta) {
                        final index = value.round();
                        if ((value - index).abs() > 0.01) {
                          return const SizedBox.shrink();
                        }
                        if (index < 0 || index >= shortLabels.length) {
                          return const SizedBox.shrink();
                        }
                        if (index % labelStep != 0) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            shortLabels[index],
                            style: GoogleFonts.poppins(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                lineTouchData: LineTouchData(
                  enabled: true,
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (spots) {
                      return spots.map((spot) {
                        return LineTooltipItem(
                          formatNumberAbbreviation(
                            spot.y,
                            decimalPlaces: 1,
                            showSuffix: false,
                          ),
                          GoogleFonts.poppins(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        );
                      }).toList();
                    },
                  ),
                ),
                lineBarsData: barsData,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PartyTrendSeries {
  final String label;
  final Color color;
  final List<months> monthsList;

  const PartyTrendSeries({
    required this.label,
    required this.color,
    required this.monthsList,
  });
}

class _TrendLegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _TrendLegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class DetailRowTile extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onTap;
  final Widget? valueWidget;

  const DetailRowTile({
    required this.label,
    required this.value,
    this.onTap,
    this.valueWidget,
    super.key,
  });

  // Gradient chooser
  LinearGradient _getGradient(String label) {
    final lower = label.toLowerCase();
    if (lower.contains('last') && lower.contains('date')) {
      return LinearGradient(
        colors: [Colors.indigo.shade400, Colors.indigo.shade700],
      );
    } else if (lower.contains('no. of invoices')) {
      return LinearGradient(
        colors: [Colors.orange.shade400, Colors.deepOrange.shade600],
      );
    } else if (lower.contains('avg invoice amount')) {
      return LinearGradient(
        colors: [Colors.green.shade400, Colors.green.shade700],
      );
    }
    return LinearGradient(colors: [Colors.grey.shade400, Colors.grey.shade600]);
  }

  // Icon chooser
  IconData _getIcon(String label) {
    final lower = label.toLowerCase();
    if (lower.contains('last') && lower.contains('date')) {
      return Icons.calendar_today_rounded;
    } else if (lower.contains('no. of invoices')) {
      return Icons.receipt_long_rounded;
    } else if (lower.contains('avg invoice amount')) {
      return Icons.bar_chart_rounded;
    }
    return Icons.info_outline;
  }

  @override
  Widget build(BuildContext context) {
    final gradient = _getGradient(label);
    final icon = _getIcon(label);

    final row = Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? Colors.transparent
            : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          // 🔹 Gradient Icon
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              gradient: gradient,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: gradient.colors.last.withOpacity(0.25),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Icon(icon, size: 16, color: Colors.white),
          ),
          const SizedBox(width: 12),

          // 🔹 Label
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 13.5,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),

          // 🔹 Value
          valueWidget ??
              Text(
                value,
                style: GoogleFonts.poppins(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
        ],
      ),
    );

    return onTap != null ? GestureDetector(onTap: onTap, child: row) : row;
  }
}

class PendingOrderTile extends StatelessWidget {
  final String label;
  final String amount;
  final VoidCallback onTap;
  final int? decimal;
  final String? currencysymbol;
  final String? currencyCode;

  const PendingOrderTile({
    super.key,
    required this.label,
    required this.amount,
    required this.onTap,
    this.decimal,
    this.currencysymbol,
    this.currencyCode,
  });

  LinearGradient _getGradient(String label) {
    if (label.toLowerCase().contains('sales')) {
      return LinearGradient(
        colors: [Colors.teal.shade400, Colors.teal.shade700],
      );
    } else if (label.toLowerCase().contains('purchase')) {
      return LinearGradient(
        colors: [Colors.deepOrange.shade400, Colors.deepOrange.shade700],
      );
    }
    return LinearGradient(colors: [Colors.grey.shade400, Colors.grey.shade600]);
  }

  IconData _getIcon(String label) {
    if (label.toLowerCase().contains('sales')) {
      return Icons.shopping_cart_outlined;
    } else if (label.toLowerCase().contains('purchase')) {
      return Icons.local_shipping_outlined;
    }
    return Icons.receipt_long_outlined;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black12.withOpacity(0.12),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 🔹 Left (Icon + Label) → 50%
            Expanded(
              flex: 1,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      gradient: _getGradient(label),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(_getIcon(label), color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      style: GoogleFonts.poppins(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      softWrap: true,
                    ),
                  ),
                ],
              ),
            ),

            SizedBox(width: 5),
            // 🔹 Right (Amount + Arrow) → 50%
            Expanded(
              flex: 1,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Flexible(
                    child: currencyAmountText(
                      currencyCode: currencyCode ?? 'AED',
                      symbol: currencysymbol ?? '',
                      amountText: formatCurrency(
                        amount,
                        decimals: decimal ?? 2,
                        showCrDr: true,
                      ),
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      softWrap: true,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white10
                          : Colors.grey.shade200,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.chevron_right,
                      size: 18,
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
}

class ReceivableBreakdownCard extends StatelessWidget {
  final String total;
  final String onAccount;
  final List<Map<String, dynamic>> rows;
  final VoidCallback onTotalTap;
  final VoidCallback? onAccountTap;

  final int? decimal;
  final String? currencysymbol;
  final String? currencyCode;

  const ReceivableBreakdownCard({
    super.key,
    required this.total,
    required this.onAccount,
    required this.rows,
    required this.onTotalTap,
    this.onAccountTap,

    this.decimal,
    this.currencysymbol,
    this.currencyCode,
  });

  @override
  Widget build(BuildContext context) {
    return _BreakdownCardBase(
      title: 'Receivable',
      icon: Icons.call_received,
      gradient: LinearGradient(
        colors: [Colors.green.shade400, Colors.green.shade700],
      ),
      total: total,
      onAccount: onAccount,
      rows: rows,
      onTotalTap: onTotalTap,
      decimal: decimal,
      currencysymbol: currencysymbol,
      currencyCode: currencyCode,
    );
  }
}

class PayableBreakdownCard extends StatelessWidget {
  final String total;
  final String onAccount;
  final List<Map<String, dynamic>> rows;
  final VoidCallback onTotalTap;
  final int? decimal;
  final String? currencysymbol;
  final String? currencyCode;

  const PayableBreakdownCard({
    super.key,
    required this.total,
    required this.onAccount,
    required this.rows,
    required this.onTotalTap,
    this.decimal,
    this.currencysymbol,
    this.currencyCode,
  });

  @override
  Widget build(BuildContext context) {
    return _BreakdownCardBase(
      title: 'Payable',
      icon: Icons.call_made,
      gradient: LinearGradient(
        colors: [Colors.red.shade400, Colors.red.shade700],
      ),
      total: total,
      onAccount: onAccount,
      rows: rows,
      onTotalTap: onTotalTap,
      decimal: decimal,
      currencysymbol: currencysymbol,
      currencyCode: currencyCode,
    );
  }
}

class _BreakdownCardBase extends StatelessWidget {
  final String title;
  final IconData icon;
  final LinearGradient gradient;
  final String total;
  final String onAccount;
  final List<Map<String, dynamic>> rows;
  final VoidCallback onTotalTap;
  final int? decimal;
  final String? currencysymbol;
  final String? currencyCode;

  const _BreakdownCardBase({
    required this.title,
    required this.icon,
    required this.gradient,
    required this.total,
    required this.onAccount,
    required this.rows,
    required this.onTotalTap,
    this.decimal,
    this.currencysymbol,
    this.currencyCode,
  });

  Widget _amountWidget(String amount, TextStyle style) {
    String cleanAmount = amount;
    String suffix;

    if (amount.contains("-")) {
      cleanAmount = amount.replaceAll("-", "");
      suffix = "DR";
    } else {
      cleanAmount = amount == "null" ? "0" : amount;
      suffix = "CR";
    }

    final amountDouble = double.tryParse(cleanAmount) ?? 0.0;
    final parts = CurrencyFormatter.formatCurrencyParts(amountDouble);

    return currencyAmountText(
      currencyCode: currencyCode ?? 'AED',
      symbol: currencysymbol ?? parts.symbol,
      amountText: '${parts.number} $suffix',
      style: style,
    );
  }

  // For the bill-wise ageing rows (>180/>120/... etc): those come in as a
  // plain number already suffixed with "DR"/"CR" (no currency symbol), so
  // just prepend the symbol/Dirham glyph instead of re-parsing it.
  Widget _rowAmountWidget(String amountWithSuffix, TextStyle style) {
    return Text.rich(
      TextSpan(
        children: [
          currencySymbolSpan(currencyCode ?? 'AED', currencysymbol ?? '', style),
          TextSpan(text: ' $amountWithSuffix', style: style),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 12, right: 12, top: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Theme.of(context).cardColor,
            Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(
              Theme.of(context).brightness == Brightness.dark ? 0.55 : 0.28,
            ),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black12.withOpacity(0.12),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ExpansionTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        tilePadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        childrenPadding: EdgeInsets.zero,
        title: Row(
          children: [
            // 🔹 Gradient Icon Badge (same as SummaryExpansionCard)
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
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: GoogleFonts.poppins(
                  fontSize: 16.5,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
            const SizedBox(width: 8),
            _amountWidget(
              total,
              GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.tealAccent.shade100
                    : Colors.teal.shade700,
              ),
            ),
          ],
        ),
        children: [
          Divider(thickness: 1, color: Theme.of(context).dividerColor),

          // Different icon + color per row
          _DetailRowTile(
            label: 'Total',
            value: '',
            valueWidget: _amountWidget(
              total,
              GoogleFonts.poppins(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            icon: Icons.summarize,
            iconColor: Colors.teal,
            onTap: onTotalTap,
          ),
          _DetailRowTile(
            label: 'On Account',
            value: '',
            valueWidget: _amountWidget(
              onAccount,
              GoogleFonts.poppins(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            icon: Icons.account_balance_wallet,
            iconColor: Colors.indigo,
            // onTap: onTotalTap,
          ),

          Divider(thickness: 1, color: Theme.of(context).dividerColor),

          for (final row in rows)
            _DetailRowTile(
              label: row['label'] ?? '',
              value: '',
              valueWidget: _rowAmountWidget(
                row['value'] ?? '',
                GoogleFonts.poppins(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              icon: Icons.circle, // 👈 you can map this dynamically
              iconColor: Colors.orange, // 👈 different color per row
              onTap: row['onTap'],
            ),
        ],
      ),
    );
  }
}

class _DetailRowTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color iconColor;
  final VoidCallback? onTap;
  final Widget? valueWidget;

  const _DetailRowTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.iconColor,
    this.onTap,
    this.valueWidget,
  });

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 14, color: iconColor),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: GoogleFonts.poppins(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Row(
            children: [
              valueWidget ??
                  Text(
                    value,
                    style: GoogleFonts.poppins(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
              if (onTap != null)
                Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: Icon(
                    Icons.chevron_right,
                    size: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ],
      ),
    );

    return onTap != null ? GestureDetector(onTap: onTap, child: row) : row;
  }
}

// Some backends send qty as "12 Nos" (number + unit) rather than a bare
// number - the unit is already shown as its own field elsewhere, so strip
// it here to avoid showing it twice in a confusing "qty unit" run-on.
String _stripUnitSuffix(String value) {
  try {
    final numberOnly = value.replaceAll(RegExp(r'[^0-9.]'), '');
    if (numberOnly.isEmpty) return value;
    final parsed = double.parse(numberOnly);
    return parsed % 1 == 0 ? parsed.toInt().toString() : parsed.toString();
  } catch (_) {
    return value;
  }
}

Widget _buildSoldPurchaseCard({
  required BuildContext context,
  required String item,
  required String qty,
  required String lastDate,
  required String rate,
  required bool isSale,
  required VoidCallback onTap,
}) {
  return GestureDetector(
    onTap: onTap,
    child: Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Theme.of(context).brightness == Brightness.dark
            ? Border.all(color: Colors.white.withOpacity(0.10), width: 1)
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black12.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 🔹 Item + Qty badge
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 📦 Icon + Item Name
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isSale
                              ? [Colors.teal.shade400, Colors.teal.shade700]
                              : [
                                  Colors.deepOrange.shade400,
                                  Colors.deepOrange.shade700,
                                ],
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.inventory_2_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 10),
                    // 👇 Flexible text prevents overflow
                    Expanded(
                      child: Text(
                        item,
                        softWrap: true,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 🧮 Qty badge (fixed size, aligned right)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: (isSale ? Colors.teal : Colors.deepOrange).withOpacity(
                    0.1,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  "Qty: ${_stripUnitSuffix(qty)}",
                  style: GoogleFonts.poppins(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: isSale
                        ? Colors.teal.shade700
                        : Colors.deepOrange.shade700,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // 🔹 Last Date + Rate row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 📅 Date
              Flexible(
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.blueGrey.shade400,
                            Colors.blueGrey.shade700,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.calendar_today,
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        formatdate(lastDate),
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          fontSize: 13.2,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 💰 Rate (icon left + text top-aligned, wraps neatly)
              Flexible(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment
                      .center, // 👈 aligns icon with top of text
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.orange.shade300,
                            Colors.deepOrange.shade400,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.price_change_rounded,
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // 👇 this makes sure long text wraps and stays aligned to the right
                    Flexible(
                      child: _rateAmountWidget(
                        rate,
                        GoogleFonts.poppins(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

// Rate display for _buildSoldPurchaseCard - top-level function so it can't
// reach a widget's currencyCode field; reads the globally-saved currency
// instead, same source CurrencyFormatter.formatCurrency_normal used, but
// keeps the symbol in its own span so AED renders the Dirham glyph instead
// of literal "AED" text.
Widget _rateAmountWidget(String rate, TextStyle style) {
  String cleaned = rate.trim();
  String unit = "";
  if (cleaned.contains("/")) {
    final parts = cleaned.split("/");
    cleaned = parts[0];
    unit = "/${parts.sublist(1).join("/")}";
  }
  final parsed = double.tryParse(cleaned.replaceAll(",", "")) ?? 0.0;
  final parts = CurrencyFormatter.formatCurrencyParts(parsed);
  final currencyCode = CurrencyFormatter.getCurrencyCode();

  return Text.rich(
    TextSpan(
      children: [
        currencySymbolSpan(currencyCode, parts.symbol, style),
        TextSpan(text: ' ${parts.number}$unit', style: style),
      ],
    ),
    textAlign: TextAlign.right,
    softWrap: true,
    overflow: TextOverflow.visible,
  );
}

String formatCurrency(
  String amount, {
  int decimals = 2,
  String currencySymbol = '',
  bool showCrDr = false,
}) {
  double value =
      double.tryParse(
        amount.replaceAll(',', '').replaceAll(RegExp(r'[^0-9.-]'), ''),
      ) ??
      0.0;
  final formatter = NumberFormat.currency(
    locale: 'en_US',
    symbol: currencySymbol.isNotEmpty ? '$currencySymbol ' : '',
    decimalDigits: decimals,
  );

  String formatted = formatter.format(value.abs());

  if (showCrDr) {
    return value >= 0 ? "$formatted CR" : "$formatted DR";
  }
  return formatted;
}
