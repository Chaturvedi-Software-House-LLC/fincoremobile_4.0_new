import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class _Col {
  final String text;
  final double flex;
  final bool bold;
  final bool right;
  final double gapAfter;
  _Col(this.text, this.flex, {this.bold = false, this.right = false, this.gapAfter = 1});
}

class SaleItem {
  final String itemName;
  String itemQuantity;
  double itemPrice;
  final double itemAmount;
  final String itemLocation;
  final String itemUnit;
  SaleItem({
    required this.itemName,
    required this.itemQuantity,
    required this.itemPrice,
    required this.itemAmount,
    required this.itemLocation,
    required this.itemUnit,
  });
}

class FakeRootBundle {
  Future<ByteData> load(String path) async {
    final f = File('/Users/saadan/Desktop/Saadan_Work/Flutter_Codes/FincoreGo/fincoremobile_4.0_new/$path');
    final bytes = await f.readAsBytes();
    return ByteData.view(Uint8List.fromList(bytes).buffer);
  }
}
final rootBundle = FakeRootBundle();

class FakeSharedPreferences {
  String? getString(String key) {
    if (key == 'spectra_allocations') {
      return '[{"godown":"#PKS01 - 53262"}]';
    }
    return null;
  }
}

class FakeXFile {
  final String path;
  final String mimeType;
  FakeXFile(this.path, {required this.mimeType});
}
class Share {
  static Future<void> shareXFiles(List<FakeXFile> files, {String? text}) async {
    print('shared: ${files.map((f) => f.path).join(", ")}');
  }
}
typedef XFile = FakeXFile;

Future<Directory> getApplicationDocumentsDirectory() async {
  return Directory('/tmp/invtaxtest3');
}

void debugPrint(String s) => print(s);

class Harness {
  final int itemCount;
  Harness(this.itemCount);

  String? serial_no = 'UNIGAS123';
  String company = 'United Gas Co. H.O.';
  String token = 'faketoken';
  int? decimal = 2;
  final _vchnoController = _FakeController()..text = '28';
  String? _selectedpartyledger = 'Al-Naseeb Gas Tr.';
  String? username = 'SYED EHTSHAM';
  String? _selectedPartyMobile = null;
  String? _selectedPartyEmail = null;
  final prefs = FakeSharedPreferences();

  double totalPriceOfItems = 2508;
  double totalVatAmount = 125.40;
  double roundedtotalAmount = 2633.40;

  late List<SaleItem> saleItems = [
    SaleItem(
      itemName: 'LPG Gas Large 100Lbs (44Kg)',
      itemQuantity: '12',
      itemPrice: 209.00,
      itemAmount: 2508.00,
      itemLocation: '',
      itemUnit: 'Nos',
    ),
  ];

  String formatAmountInvoice(String amount) {
    if (amount == "null" || amount.isEmpty) amount = "0";
    double amount_double = double.parse(amount);
    final formatted = amount_double.toStringAsFixed(2);
    return formatted;
  }

  String convertAmountToWords(num amount) {
    return 'UAE dirham Two thousand Six hundred Thirty Three and Forty fils Only';
  }

  Future<void> _generateUniGasTaxInvoicePDF(
    String trn,
    String address,
    String emirate,
    String country,
  ) async {
    // Resolve the van (vehicle) allocated to this device's serial number
    // from the locally-cached 'spectra_allocations' SharedPreferences
    // value rather than making a fresh network call.
    String vehicleName = '';
    try {
      final String? spectraAllocationsString = prefs.getString(
        'spectra_allocations',
      );
      debugPrint(
        "UNIGAS TAX INVOICE VEHICLE LOOKUP (prefs): $spectraAllocationsString",
      );

      if (spectraAllocationsString != null &&
          spectraAllocationsString.isNotEmpty) {
        final List<dynamic> spectraAllocations = jsonDecode(
          spectraAllocationsString,
        );
        if (spectraAllocations.isNotEmpty) {
          final first = Map<String, dynamic>.from(spectraAllocations.first);
          vehicleName = first['godown']?.toString() ?? '';
        }
      }
    } catch (e) {
      debugPrint("UNIGAS TAX INVOICE VEHICLE LOOKUP ERROR: $e");
    }

    final logoBytes = await rootBundle.load("assets/uigas-logo.jpeg");
    final uniGasLogo = pw.MemoryImage(logoBytes.buffer.asUint8List());

    // Arabic-capable font for "فاتورة ضريبية" / "توقيع العميل" -
    // NotoSans.ttf (used for everything else) has no Arabic glyphs.
    final arabicFontData = await rootBundle.load(
      "assets/fonts/NotoSansArabic.ttf",
    );
    final arabicFont = pw.Font.ttf(arabicFontData);

    // Any party-ledger detail that's missing/null/empty shows as
    // "Not Available" rather than a blank line or the literal word "null".
    String cleanOrNotAvailable(String? value) {
      if (value == null) return 'Not Available';
      final trimmed = value.trim();
      return (trimmed.isEmpty || trimmed.toLowerCase() == 'null')
          ? 'Not Available'
          : trimmed;
    }

    List<String> placeParts = [];
    if (address != "null" && address.trim().isNotEmpty) {
      placeParts.add(address.trim());
    }
    if (emirate != "null" && emirate.trim().isNotEmpty) {
      placeParts.add(emirate.trim());
    }
    if (country != "null" && country.trim().isNotEmpty) {
      placeParts.add(country.trim());
    }
    final String customerAddress = placeParts.isEmpty
        ? 'Not Available'
        : placeParts.join(", ");

    final String customerTrn = cleanOrNotAvailable(trn);
    final String customerMobile = cleanOrNotAvailable(_selectedPartyMobile);
    final String customerEmail = cleanOrNotAvailable(_selectedPartyEmail);

    final now = DateTime.now();
    final dateTimeText =
        '${DateFormat('yyyy-MM-dd').format(now)}  ${DateFormat('HH:mm').format(now)}';

    pw.Widget leftText(String text, {double size = 9, pw.FontWeight? weight}) {
      return pw.Align(
        alignment: pw.Alignment.centerLeft,
        child: pw.Text(
          text,
          style: pw.TextStyle(fontSize: size, fontWeight: weight),
        ),
      );
    }

    // Bold "Label:" followed by the value, for the customer details box.
    pw.Widget detailLine(
      String label,
      String value, {
      double size = 8,
      bool boldLabel = true,
    }) {
      return pw.Align(
        alignment: pw.Alignment.centerLeft,
        child: pw.RichText(
          text: pw.TextSpan(
            children: [
              pw.TextSpan(
                text: '$label: ',
                style: pw.TextStyle(
                  fontSize: size,
                  fontWeight: boldLabel ? pw.FontWeight.bold : null,
                ),
              ),
              pw.TextSpan(text: value, style: pw.TextStyle(fontSize: size)),
            ],
          ),
        ),
      );
    }

    // Label on the left, value on the right - used for Delivered
    // by/Vehicle.
    pw.Widget spaceBetweenLine(
      String label,
      String value, {
      bool bold = true,
      double size = 9,
    }) {
      return pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: size,
              fontWeight: bold ? pw.FontWeight.bold : null,
            ),
          ),
          pw.SizedBox(width: 6),
          pw.Flexible(
            child: pw.Text(
              value,
              textAlign: pw.TextAlign.right,
              style: pw.TextStyle(
                fontSize: size,
                fontWeight: bold ? pw.FontWeight.bold : null,
              ),
            ),
          ),
        ],
      );
    }

    // Builds one row of the borderless item table from Expanded/flex
    // columns (no pw.Table, no cell grid lines - matches the reference's
    // plain-row look inside the single bordered box).
    pw.Widget itemRow(List<_Col> cols) {
      final children = <pw.Widget>[];
      for (final c in cols) {
        children.add(
          pw.Expanded(
            flex: (c.flex * 10).round(),
            child: pw.Text(
              c.text,
              textAlign: c.right ? pw.TextAlign.right : pw.TextAlign.left,
              style: pw.TextStyle(
                fontSize: 9,
                fontWeight: c.bold ? pw.FontWeight.bold : null,
              ),
            ),
          ),
        );
        // A dedicated spacer between columns - unlike padding inside the
        // Expanded, this adds real extra width instead of shrinking the
        // column's own text area.
        children.add(pw.SizedBox(width: c.gapAfter));
      }
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: children,
        ),
      );
    }

    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        // Wider than the Delivery Note's 58mm: with 6 item-table columns
        // (SN/ITEM/QTY/UNIT/RATE/AMOUNT) 58mm was too cramped to stay
        // legible - 76mm matches the reference PDF's own export width.
        pageFormat: PdfPageFormat(
          76 * PdfPageFormat.mm,
          double.infinity,
          marginLeft: 10,
          marginRight: 10,
          marginTop: 8,
          marginBottom: 8,
        ),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Image(uniGasLogo, height: 60),
              pw.SizedBox(height: 4),
              pw.Text(
                'UNITED GAS CO. LLC',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Divider(thickness: 1),
              leftText('A Partner You Can Trust'),
              leftText('Sharjah | Dubai | RAK | UAQ | Fujairah', size: 8),
              pw.SizedBox(height: 6),
              detailLine('Tel', '800 864427'),
              detailLine('Email', 'Info@unigastt.com'),
              detailLine('Web', 'www.unigastt.com'),
              detailLine('TRN', '100206964700003'),
              pw.SizedBox(height: 6),
              pw.Divider(thickness: 1),
              // "TAX INVOICE" + Arabic "فاتورة ضريبية" stay on one line,
              // matching the reference exactly (unlike the signature
              // box below, this heading fits fine at this width).
              pw.Container(
                width: double.infinity,
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'TAX INVOICE',
                      style: pw.TextStyle(
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      'فاتورة ضريبية',
                      textDirection: pw.TextDirection.rtl,
                      style: pw.TextStyle(fontSize: 10, font: arabicFont),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 4),
              leftText('Invoice No: ${_vchnoController.text}'),
              leftText('Date & Time: $dateTimeText'),
              pw.SizedBox(height: 10),
              leftText(
                'CUSTOMER DETAILS',
                size: 9,
                weight: pw.FontWeight.bold,
              ),
              pw.SizedBox(height: 4),
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(6),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(width: 1),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    detailLine(
                      'Name',
                      cleanOrNotAvailable(_selectedpartyledger),
                      size: 9,
                      boldLabel: false,
                    ),
                    pw.SizedBox(height: 6),
                    detailLine('TRN', customerTrn),
                    pw.SizedBox(height: 6),
                    detailLine('Address', customerAddress),
                    pw.SizedBox(height: 6),
                    detailLine('Phone', customerMobile),
                    pw.SizedBox(height: 6),
                    detailLine('Email', customerEmail),
                  ],
                ),
              ),
              pw.SizedBox(height: 10),
              // One continuous box covering headings, item rows, taxable
              // value/VAT and the total - matching the reference exactly.
              // No per-cell grid lines (left/right/inside borders) -
              // columns are aligned with Expanded flex instead of a
              // pw.Table, matching the reference's plain-row look. Top
              // and bottom borders are bold to frame the whole block.
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 6,
                ),
                decoration: const pw.BoxDecoration(
                  border: pw.Border(
                    left: pw.BorderSide(width: 1),
                    right: pw.BorderSide(width: 1),
                    top: pw.BorderSide(width: 2),
                    bottom: pw.BorderSide(width: 2),
                  ),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    itemRow([
                      _Col('SN', 1.2, bold: true),
                      _Col('ITEM', 1.7, bold: true, gapAfter: 6),
                      _Col('QTY', 1.5, bold: true, right: true),
                      _Col('UNIT', 1.7, bold: true),
                      _Col('RATE', 2, bold: true, right: true, gapAfter: 2),
                      _Col('AMOUNT (AED)', 3.2, bold: true, right: true),
                    ]),
                    pw.SizedBox(height: 3),
                    pw.Divider(thickness: 0.75),
                    pw.SizedBox(height: 3),
                    for (var item in saleItems.asMap().entries)
                      itemRow([
                        _Col('${item.key + 1}', 1.2),
                        _Col(item.value.itemName, 1.7, gapAfter: 6),
                        _Col(
                          item.value.itemQuantity,
                          1.5,
                          right: true,
                        ),
                        _Col(item.value.itemUnit, 1.7),
                        _Col(
                          formatAmountInvoice(item.value.itemPrice.toString()),
                          2,
                          right: true,
                          gapAfter: 2,
                        ),
                        _Col(
                          formatAmountInvoice(
                            item.value.itemAmount.toString(),
                          ),
                          3.2,
                          right: true,
                        ),
                      ]),
                    pw.SizedBox(height: 8),
                    spaceBetweenLine(
                      'Taxable Value (AED)',
                      formatAmountInvoice(totalPriceOfItems.toString()),
                      bold: false,
                    ),
                    pw.SizedBox(height: 4),
                    spaceBetweenLine(
                      'VAT (5%)',
                      formatAmountInvoice(totalVatAmount.toString()),
                      bold: false,
                    ),
                    pw.SizedBox(height: 4),
                    pw.Divider(thickness: 1),
                    spaceBetweenLine(
                      'TOTAL Incl. VAT (AED)',
                      formatAmountInvoice(roundedtotalAmount.toString()),
                    ),
                    pw.SizedBox(height: 8),
                    pw.RichText(
                      text: pw.TextSpan(
                        children: [
                          pw.TextSpan(
                            text: 'Amount in Words: ',
                            style: pw.TextStyle(
                              fontSize: 9,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                          pw.TextSpan(
                            text: convertAmountToWords(roundedtotalAmount),
                            style: pw.TextStyle(fontSize: 9),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 10),
              spaceBetweenLine(
                'Delivered by:',
                cleanOrNotAvailable(username),
              ),
              pw.SizedBox(height: 2),
              spaceBetweenLine(
                'Vehicle:',
                cleanOrNotAvailable(vehicleName),
              ),
              pw.SizedBox(height: 10),
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(6),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(width: 1),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    // Stacked rather than side-by-side on one line: at
                    // this narrow (58mm) width, "CUSTOMER SIGNATURE" +
                    // the Arabic label together can overflow the box on
                    // some devices/fonts. Arabic sits above, right-
                    // aligned; English below, left-aligned.
                    pw.Container(
                      width: double.infinity,
                      child: pw.Align(
                        alignment: pw.Alignment.centerRight,
                        child: pw.Text(
                          'توقيع العميل',
                          textDirection: pw.TextDirection.rtl,
                          style: pw.TextStyle(fontSize: 8, font: arabicFont),
                        ),
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'CUSTOMER SIGNATURE',
                      style: pw.TextStyle(
                        fontSize: 8,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 6),
                    pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        // Blank box for the customer's physical
                        // signature/stamp.
                        pw.Container(
                          width: 60,
                          height: 60,
                          decoration: pw.BoxDecoration(
                            border: pw.Border.all(width: 1),
                          ),
                        ),
                        pw.SizedBox(width: 8),
                        pw.Expanded(
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(
                                'Name:',
                                style: pw.TextStyle(
                                  fontSize: 8,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                              pw.SizedBox(height: 20),
                              pw.Text(
                                'Phone:',
                                style: pw.TextStyle(
                                  fontSize: 8,
                                  fontWeight: pw.FontWeight.bold,
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
              pw.SizedBox(height: 10),
              pw.Text(
                "This document doesn't serve as payment proof",
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(fontSize: 9),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'Please request and maintain separate receipt as a proof of payment',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(fontSize: 9),
              ),
              pw.SizedBox(height: 8),
              pw.Text(
                'Thank you for your business!',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          );
        },
      ),
    );

    final pdfData = await pdf.save();
    final formattedDate =
        "${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}";
    final dir = await getApplicationDocumentsDirectory();
    final filePath = '${dir.path}/SaleInvoice_$formattedDate.pdf';
    final file = File(filePath);
    await file.writeAsBytes(pdfData);

    await Share.shareXFiles([
      XFile(filePath, mimeType: 'application/pdf'),
    ], text: 'Sharing Sale Invoice for $_selectedpartyledger');
  }
}

class _FakeController {
  String text = '';
}

void main() async {
  final h = Harness(1);
  await h._generateUniGasTaxInvoicePDF('100222162800003', 'Sharjah', '', 'UAE');
  print('done');
}
