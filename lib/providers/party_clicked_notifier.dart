import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../PartyClicked.dart';
import '../api/monthly_bucket_helper.dart';
import '../api/voucher_drilldown_helper.dart';
import '../currencyFormat.dart';
import 'repository_providers.dart';

/// Mirrors `_PartyClickedPageState`'s field set almost 1:1 (see the class
/// doc-comment on [PartyClickedNotifier] for why) - one immutable snapshot
/// consumed by the widget via `_s`.
class PartyClickedState {
  final bool isLoading;
  final bool isTextEnabled;
  final String selectedDate;
  final String startDateString;
  final String endDateString;
  final String startDateText;
  final String endDateText;
  final String company;
  final int decimal;
  final String currencySymbol;
  final String currencyCode;

  final bool isClickedSummary;
  final bool isClickedSold;
  final bool isClickedPurchase;
  final bool isVisibleSoldList;
  final bool isVisiblePurchaseList;
  final bool isVisibleNoDataFound;
  final bool isVisibleSummaryBtn;
  final bool isVisibleSoldBtn;
  final bool isVisiblePurchaseBtn;
  final bool isSearchViewVisible;
  final bool isSearchLayoutVisible;
  final String itemCount;

  final List<Sold_Purchased> filteredItemsSold;
  final List<Sold_Purchased> soldList;
  final List<Sold_Purchased> filteredItemsPurchase;
  final List<Sold_Purchased> purchaseList;

  final bool salesVisibility;
  final bool purchaseVisibility;
  final bool receiptVisibility;
  final bool paymentVisibility;
  final bool creditnoteVisibility;
  final bool debitnoteVisibility;
  final bool journalVisibility;
  final bool receivableVisibility;
  final bool payableVisibility;
  final bool salesOrderVisibility;
  final bool purchaseOrderVisibility;

  final String totalsaleamt, avgsalesinvoiceamt, noofsalesinvoice, lastsaledate;
  final String totalpurchaseamt, avgpurchaseinvoiceamt, noofpurchaseinvoice, lastpurchasedate;
  final String totalreceiptamt, avgreceiptinvoiceamt, noofreceiptinvoice, lastreceiptdate;
  final String totalpaymentamt, avgpaymentinvoiceamt, noofpaymentinvoice, lastpaymentdate;
  final String totalcreditnoteamt, avgcreditnoteinvoiceamt, noofcreditnoteinvoice, lastcreditnotedate;
  final String totaldebitnoteamt, avgdebitnoteinvoiceamt, noofdebitnoteinvoice, lastdebitnotedate;
  final String totaljournalamt, avgjournalinvoiceamt, noofjournalinvoice, lastjournaldate;

  final List<months> monthsListSales;
  final List<months> monthsListPurchase;
  final List<months> monthsListReceipt;
  final List<months> monthsListPayment;
  final List<months> monthsListCreditnote;
  final List<months> monthsListDebitnote;
  final List<months> monthsListJournal;

  final String receivabletotal, onAccountReceivable;
  final String row1Receivable, row2Receivable, row3Receivable, row4Receivable, row5Receivable, row6Receivable;
  final String row1ReceivableHeading, row2ReceivableHeading, row3ReceivableHeading, row4ReceivableHeading, row5ReceivableHeading, row6ReceivableHeading;
  final String row1ReceivableHeadingValue, row2ReceivableHeadingValue, row3ReceivableHeadingValue, row4ReceivableHeadingValue, row5ReceivableHeadingValue, row6ReceivableHeadingValue;

  final String payabletotal, onAccountPayable;
  final String row1Payable, row2Payable, row3Payable, row4Payable, row5Payable, row6Payable;
  final String row1PayableHeading, row2PayableHeading, row3PayableHeading, row4PayableHeading, row5PayableHeading, row6PayableHeading;
  final String row1PayableHeadingValue, row2PayableHeadingValue, row3PayableHeadingValue, row4PayableHeadingValue, row5PayableHeadingValue, row6PayableHeadingValue;

  final String pendingsalesorder, pendingpurchaseorder;

  const PartyClickedState({
    this.isLoading = false,
    this.isTextEnabled = true,
    this.selectedDate = 'Today',
    this.startDateString = '',
    this.endDateString = '',
    this.startDateText = '',
    this.endDateText = '',
    this.company = '',
    this.decimal = 2,
    this.currencySymbol = '',
    this.currencyCode = 'AED',
    this.isClickedSummary = true,
    this.isClickedSold = false,
    this.isClickedPurchase = false,
    this.isVisibleSoldList = false,
    this.isVisiblePurchaseList = false,
    this.isVisibleNoDataFound = false,
    this.isVisibleSummaryBtn = false,
    this.isVisibleSoldBtn = false,
    this.isVisiblePurchaseBtn = false,
    this.isSearchViewVisible = false,
    this.isSearchLayoutVisible = false,
    this.itemCount = '0',
    this.filteredItemsSold = const [],
    this.soldList = const [],
    this.filteredItemsPurchase = const [],
    this.purchaseList = const [],
    this.salesVisibility = false,
    this.purchaseVisibility = false,
    this.receiptVisibility = false,
    this.paymentVisibility = false,
    this.creditnoteVisibility = false,
    this.debitnoteVisibility = false,
    this.journalVisibility = false,
    this.receivableVisibility = false,
    this.payableVisibility = false,
    this.salesOrderVisibility = false,
    this.purchaseOrderVisibility = false,
    this.totalsaleamt = '0',
    this.avgsalesinvoiceamt = '0',
    this.noofsalesinvoice = '0',
    this.lastsaledate = '',
    this.totalpurchaseamt = '0',
    this.avgpurchaseinvoiceamt = '0',
    this.noofpurchaseinvoice = '0',
    this.lastpurchasedate = '',
    this.totalreceiptamt = '0',
    this.avgreceiptinvoiceamt = '0',
    this.noofreceiptinvoice = '0',
    this.lastreceiptdate = '',
    this.totalpaymentamt = '0',
    this.avgpaymentinvoiceamt = '0',
    this.noofpaymentinvoice = '0',
    this.lastpaymentdate = '',
    this.totalcreditnoteamt = '0',
    this.avgcreditnoteinvoiceamt = '0',
    this.noofcreditnoteinvoice = '0',
    this.lastcreditnotedate = '',
    this.totaldebitnoteamt = '0',
    this.avgdebitnoteinvoiceamt = '0',
    this.noofdebitnoteinvoice = '0',
    this.lastdebitnotedate = '',
    this.totaljournalamt = '0',
    this.avgjournalinvoiceamt = '0',
    this.noofjournalinvoice = '0',
    this.lastjournaldate = '',
    this.monthsListSales = const [],
    this.monthsListPurchase = const [],
    this.monthsListReceipt = const [],
    this.monthsListPayment = const [],
    this.monthsListCreditnote = const [],
    this.monthsListDebitnote = const [],
    this.monthsListJournal = const [],
    this.receivabletotal = '0',
    this.onAccountReceivable = '0',
    this.row1Receivable = '0',
    this.row2Receivable = '0',
    this.row3Receivable = '0',
    this.row4Receivable = '0',
    this.row5Receivable = '0',
    this.row6Receivable = '0',
    this.row1ReceivableHeading = '>180',
    this.row2ReceivableHeading = '>120',
    this.row3ReceivableHeading = '>90',
    this.row4ReceivableHeading = '>60',
    this.row5ReceivableHeading = '>30',
    this.row6ReceivableHeading = '>0',
    this.row1ReceivableHeadingValue = '180',
    this.row2ReceivableHeadingValue = '120',
    this.row3ReceivableHeadingValue = '90',
    this.row4ReceivableHeadingValue = '60',
    this.row5ReceivableHeadingValue = '30',
    this.row6ReceivableHeadingValue = '0',
    this.payabletotal = '0',
    this.onAccountPayable = '0',
    this.row1Payable = '0',
    this.row2Payable = '0',
    this.row3Payable = '0',
    this.row4Payable = '0',
    this.row5Payable = '0',
    this.row6Payable = '0',
    this.row1PayableHeading = '>180',
    this.row2PayableHeading = '>120',
    this.row3PayableHeading = '>90',
    this.row4PayableHeading = '>60',
    this.row5PayableHeading = '>30',
    this.row6PayableHeading = '>0',
    this.row1PayableHeadingValue = '180',
    this.row2PayableHeadingValue = '120',
    this.row3PayableHeadingValue = '90',
    this.row4PayableHeadingValue = '60',
    this.row5PayableHeadingValue = '30',
    this.row6PayableHeadingValue = '0',
    this.pendingsalesorder = '0',
    this.pendingpurchaseorder = '0',
  });
}

/// Args identify the ledger this screen is scoped to.
class PartyClickedArgs {
  final String partyname;
  final int? ledgerMasterId;

  const PartyClickedArgs({required this.partyname, this.ledgerMasterId});

  @override
  bool operator ==(Object other) =>
      other is PartyClickedArgs &&
      other.partyname == partyname &&
      other.ledgerMasterId == ledgerMasterId;

  @override
  int get hashCode => Object.hash(partyname, ledgerMasterId);
}

/// This screen's original State class (`_PartyClickedPageState`) has ~150
/// fields and several methods (`formatOnAccountWithBillNo`,
/// `_refreshReceivablePayableGrandTotals`, `_fetchSummaryDataTallyApi`, ...)
/// that mutate a handful of running-total accumulators
/// (`_sumReceivable0`..`_sumReceivable180` etc.) across many call sites, not
/// all of them wrapped in `setState`. Rather than hand-translate every
/// mutation site into a `state.copyWith(...)` call (very easy to drop or
/// double-count a bucket at this scale), this notifier keeps the *exact
/// same* plain mutable fields and method bodies as the original, and
/// replaces every `setState(() { ... })` call with `_commit(() { ... })`
/// (same signature, same semantics: run the mutation, then publish a fresh
/// immutable snapshot to `state`). This is a mechanical relocation, not a
/// rewrite, specifically to avoid introducing a bug in real
/// receivable/payable money figures.
class PartyClickedNotifier extends StateNotifier<PartyClickedState> {
  final Ref _ref;
  final PartyClickedArgs args;

  PartyClickedNotifier(this._ref, this.args) : super(const PartyClickedState()) {
    _init();
  }

  void _commit(void Function() fn) {
    fn();
    state = _snapshot();
  }

  PartyClickedState _snapshot() => PartyClickedState(
        isLoading: _isLoading,
        isTextEnabled: _isTextEnabled,
        selectedDate: _selecteddate,
        startDateString: startDateString,
        endDateString: endDateString,
        startDateText: startdate_text,
        endDateText: enddate_text,
        company: company,
        decimal: decimal,
        currencySymbol: currencysymbol,
        currencyCode: _currencyCode,
        isClickedSummary: isClicked_Summary,
        isClickedSold: isClicked_Sold,
        isClickedPurchase: isClicked_Purchase,
        isVisibleSoldList: isVisibleSoldList,
        isVisiblePurchaseList: isVisiblePurchaseList,
        isVisibleNoDataFound: isVisibleNoDataFound,
        isVisibleSummaryBtn: isVisibleSummaryBtn,
        isVisibleSoldBtn: isVisibleSoldBtn,
        isVisiblePurchaseBtn: isVisiblePurchaseBtn,
        isSearchViewVisible: _isSearchViewVisible,
        isSearchLayoutVisible: isSearchLayoutVisible,
        itemCount: item_count,
        filteredItemsSold: List.of(filteredItems_sold),
        soldList: List.of(sold_list),
        filteredItemsPurchase: List.of(filteredItems_purchase),
        purchaseList: List.of(purchase_list),
        salesVisibility: SalesVisibility,
        purchaseVisibility: PurchaseVisibility,
        receiptVisibility: ReceiptVisibility,
        paymentVisibility: PaymentVisibility,
        creditnoteVisibility: CreditnoteVisibility,
        debitnoteVisibility: DebitnoteVisibility,
        journalVisibility: JournalVisibility,
        receivableVisibility: ReceivableVisibility,
        payableVisibility: PayableVisibility,
        salesOrderVisibility: SalesOrderVisibility,
        purchaseOrderVisibility: PurchaseOrderVisibility,
        totalsaleamt: totalsaleamt,
        avgsalesinvoiceamt: avgsalesinvoiceamt,
        noofsalesinvoice: noofsalesinvoice,
        lastsaledate: lastsaledate,
        totalpurchaseamt: totalpurchaseamt,
        avgpurchaseinvoiceamt: avgpurchaseinvoiceamt,
        noofpurchaseinvoice: noofpurchaseinvoice,
        lastpurchasedate: lastpurchasedate,
        totalreceiptamt: totalreceiptamt,
        avgreceiptinvoiceamt: avgreceiptinvoiceamt,
        noofreceiptinvoice: noofreceiptinvoice,
        lastreceiptdate: lastreceiptdate,
        totalpaymentamt: totalpaymentamt,
        avgpaymentinvoiceamt: avgpaymentinvoiceamt,
        noofpaymentinvoice: noofpaymentinvoice,
        lastpaymentdate: lastpaymentdate,
        totalcreditnoteamt: totalcreditnoteamt,
        avgcreditnoteinvoiceamt: avgcreditnoteinvoiceamt,
        noofcreditnoteinvoice: noofcreditnoteinvoice,
        lastcreditnotedate: lastcreditnotedate,
        totaldebitnoteamt: totaldebitnoteamt,
        avgdebitnoteinvoiceamt: avgdebitnoteinvoiceamt,
        noofdebitnoteinvoice: noofdebitnoteinvoice,
        lastdebitnotedate: lastdebitnotedate,
        totaljournalamt: totaljournalamt,
        avgjournalinvoiceamt: avgjournalinvoiceamt,
        noofjournalinvoice: noofjournalinvoice,
        lastjournaldate: lastjournaldate,
        monthsListSales: List.of(months_list_sales),
        monthsListPurchase: List.of(months_list_purchase),
        monthsListReceipt: List.of(months_list_receipt),
        monthsListPayment: List.of(months_list_payment),
        monthsListCreditnote: List.of(months_list_creditnote),
        monthsListDebitnote: List.of(months_list_debitnote),
        monthsListJournal: List.of(months_list_journal),
        receivabletotal: receivabletotal,
        onAccountReceivable: onAccountReceivable,
        row1Receivable: row1_receivable,
        row2Receivable: row2_receivable,
        row3Receivable: row3_receivable,
        row4Receivable: row4_receivable,
        row5Receivable: row5_receivable,
        row6Receivable: row6_receivable,
        row1ReceivableHeading: row1_receivable_heading,
        row2ReceivableHeading: row2_receivable_heading,
        row3ReceivableHeading: row3_receivable_heading,
        row4ReceivableHeading: row4_receivable_heading,
        row5ReceivableHeading: row5_receivable_heading,
        row6ReceivableHeading: row6_receivable_heading,
        row1ReceivableHeadingValue: row1_receivable_heading_value,
        row2ReceivableHeadingValue: row2_receivable_heading_value,
        row3ReceivableHeadingValue: row3_receivable_heading_value,
        row4ReceivableHeadingValue: row4_receivable_heading_value,
        row5ReceivableHeadingValue: row5_receivable_heading_value,
        row6ReceivableHeadingValue: row6_receivable_heading_value,
        payabletotal: payabletotal,
        onAccountPayable: onAccountPayable,
        row1Payable: row1_payable,
        row2Payable: row2_payable,
        row3Payable: row3_payable,
        row4Payable: row4_payable,
        row5Payable: row5_payable,
        row6Payable: row6_payable,
        row1PayableHeading: row1_payable_heading,
        row2PayableHeading: row2_payable_heading,
        row3PayableHeading: row3_payable_heading,
        row4PayableHeading: row4_payable_heading,
        row5PayableHeading: row5_payable_heading,
        row6PayableHeading: row6_payable_heading,
        row1PayableHeadingValue: row1_payable_heading_value,
        row2PayableHeadingValue: row2_payable_heading_value,
        row3PayableHeadingValue: row3_payable_heading_value,
        row4PayableHeadingValue: row4_payable_heading_value,
        row5PayableHeadingValue: row5_payable_heading_value,
        row6PayableHeadingValue: row6_payable_heading_value,
        pendingsalesorder: pendingsalesorder,
        pendingpurchaseorder: pendingpurchaseorder,
      );

  // ---- verbatim fields from _PartyClickedPageState ----
  String startDateString = "", endDateString = "";

  bool isVisibleSoldList = false, isVisiblePurchaseList = false;

  String lastsaledate = "",
      noofsalesinvoice = "0",
      avgsalesinvoiceamt = "0",
      totalsaleamt = "0";
  String lastpurchasedate = "",
      noofpurchaseinvoice = "0",
      avgpurchaseinvoiceamt = "0",
      totalpurchaseamt = "0";
  String lastreceiptdate = "",
      noofreceiptinvoice = "0",
      avgreceiptinvoiceamt = "0",
      totalreceiptamt = "0";
  String lastpaymentdate = "",
      noofpaymentinvoice = "0",
      avgpaymentinvoiceamt = "0",
      totalpaymentamt = "0";
  String lastcreditnotedate = "",
      noofcreditnoteinvoice = "0",
      avgcreditnoteinvoiceamt = "0",
      totalcreditnoteamt = "0";
  String lastdebitnotedate = "",
      noofdebitnoteinvoice = "0",
      avgdebitnoteinvoiceamt = "0",
      totaldebitnoteamt = "0";
  String lastjournaldate = "",
      noofjournalinvoice = "0",
      avgjournalinvoiceamt = "0",
      totaljournalamt = "0";

  String receivabletotal = "0",
      onAccountReceivable = "0",
      row1_receivable = "0",
      row2_receivable = "0",
      row3_receivable = "0",
      row4_receivable = "0",
      row5_receivable = "0",
      row6_receivable = "0",
      row1_receivable_heading = "180",
      row2_receivable_heading = "120",
      row3_receivable_heading = "90",
      row4_receivable_heading = "60",
      row5_receivable_heading = "30",
      row6_receivable_heading = "0",
      row1_receivable_heading_value = "180",
      row2_receivable_heading_value = "120",
      row3_receivable_heading_value = "90",
      row4_receivable_heading_value = "60",
      row5_receivable_heading_value = "30",
      row6_receivable_heading_value = "0";

  String payabletotal = "0",
      onAccountPayable = "0",
      row1_payable = "0",
      row2_payable = "0",
      row3_payable = "0",
      row4_payable = "0",
      row5_payable = "0",
      row6_payable = "0",
      row1_payable_heading = "180",
      row2_payable_heading = "120",
      row3_payable_heading = "90",
      row4_payable_heading = "60",
      row5_payable_heading = "30",
      row6_payable_heading = "0",
      row1_payable_heading_value = "180",
      row2_payable_heading_value = "120",
      row3_payable_heading_value = "90",
      row4_payable_heading_value = "60",
      row5_payable_heading_value = "30",
      row6_payable_heading_value = "0";

  // Running ageing-bucket accumulators for the Receivable/Payable summary.
  // These must persist across the whole recpay_list loop (one call to
  // formatOnAccountWithBillNo per bill).
  double _sumReceivable0 = 0,
      _sumReceivable30 = 0,
      _sumReceivable60 = 0,
      _sumReceivable90 = 0,
      _sumReceivable120 = 0,
      _sumReceivable180 = 0;
  double _sumPayable0 = 0,
      _sumPayable30 = 0,
      _sumPayable60 = 0,
      _sumPayable90 = 0,
      _sumPayable120 = 0,
      _sumPayable180 = 0;

  double _currentReceivableOnAccount = 0;
  double _currentPayableOnAccount = 0;

  int decimal = 2;
  late NumberFormat currencyFormat;
  String currencysymbol = '';
  String _currencyCode = 'AED';

  bool isClicked_Summary = true,
      isClicked_Sold = false,
      isClicked_Purchase = false;

  bool SalesVisibility = false,
      PurchaseVisibility = false,
      ReceiptVisibility = false,
      PaymentVisibility = false,
      CreditnoteVisibility = false,
      DebitnoteVisibility = false,
      JournalVisibility = false,
      ReceivableVisibility = false,
      PayableVisibility = false,
      SalesOrderVisibility = false,
      PurchaseOrderVisibility = false;

  String pendingsalesorder = "0", pendingpurchaseorder = "0";

  dynamic _selecteddate = 'Today';

  List<Sold_Purchased> filteredItems_sold = [];
  List<Sold_Purchased> sold_list = [];
  List<Sold_Purchased> filteredItems_purchase = [];
  List<Sold_Purchased> purchase_list = [];

  String item_count = "0";

  bool _isSearchViewVisible = false, isSearchLayoutVisible = false;

  List<months> months_list_sales = [];
  List<months> months_list_purchase = [];
  List<months> months_list_receipt = [];
  List<months> months_list_payment = [];
  List<months> months_list_creditnote = [];
  List<months> months_list_debitnote = [];
  List<months> months_list_journal = [];

  bool isVisibleNoDataFound = false;
  bool isVisibleSummaryBtn = false;
  bool isVisibleSoldBtn = false;
  bool isVisiblePurchaseBtn = false;

  late SharedPreferences prefs;
  String startdate_text = "", enddate_text = "";
  bool _isLoading = false;

  String heading1 = '', heading2 = '', heading3 = '', heading4 = '', heading5 = '';

  bool _isTextEnabled = true;

  String salesparty = '';
  String purchaseparty = '';
  String creditnoteparty = '';
  String journalparty = '';
  String payableparty = '';
  String pendingpurchaseorderparty = '';
  String receiptparty = '';
  String paymentparty = '';
  String debitnoteparty = '';
  String receivableparty = '';
  String pendingsalesorderparty = '';
  String party_suppliers = '';
  String party_customers = '';

  String company = '';

  // ---- verbatim-ported business logic ----

  String formatRemainingOverdue(String outstanding) {
    double outstanding_double = double.parse(outstanding);
    return CurrencyFormatter.formatCurrencyParts(outstanding_double).number;
  }

  void formatRecPayTotal(String outstanding) {
    final double value = double.tryParse(outstanding) ?? 0.0;

    if (value == 0) {
      _commit(() {
        ReceivableVisibility = false;
        PayableVisibility = false;
        receivabletotal = "0";
        payabletotal = "0";
      });
      return;
    }

    if (value > 0) {
      if (receivableparty == 'True') {
        _commit(() {
          ReceivableVisibility = true;
          PayableVisibility = false;
          receivabletotal = outstanding;
          payabletotal = "0";
        });
      }
    } else {
      if (payableparty == 'True') {
        _commit(() {
          PayableVisibility = true;
          ReceivableVisibility = false;
          payabletotal = outstanding;
          receivabletotal = "0";
        });
      }
    }
  }

  // Recomputes the headline receivabletotal/payabletotal from the same
  // bucket sums the row1-row6 breakdown uses, so the big total figure can
  // never drift from (or silently stay at 0 relative to) what the buckets
  // below it actually show.
  void _refreshReceivablePayableGrandTotals() {
    final receivableGrand = _sumReceivable0 +
        _sumReceivable30 +
        _sumReceivable60 +
        _sumReceivable90 +
        _sumReceivable120 +
        _sumReceivable180 +
        _currentReceivableOnAccount;
    final payableGrand = _sumPayable0 +
        _sumPayable30 +
        _sumPayable60 +
        _sumPayable90 +
        _sumPayable120 +
        _sumPayable180 +
        _currentPayableOnAccount;

    if (receivableGrand > 0) {
      receivabletotal = '-${receivableGrand.toStringAsFixed(2)}';
    }
    if (payableGrand > 0) {
      payabletotal = payableGrand.toStringAsFixed(2);
    }
  }

  void formatOnAccountWithBillNo(int overdue_int, String rawTotal) {
    final total = rawTotal.replaceAll(',', '');
    if (total.contains("-")) {
      if (receivableparty == 'True') {
        _commit(() {
          ReceivableVisibility = true;
        });
        if (overdue_int > 0 && overdue_int <= int.parse(heading1)) {
          final amount = double.parse(total.replaceAll("-", ""));
          _sumReceivable0 += amount;
          row6_receivable =
              '${CurrencyFormatter.formatCurrencyParts(_sumReceivable0).number} DR';
        }

        if (overdue_int > int.parse(heading1) && overdue_int <= int.parse(heading2)) {
          final amount = double.parse(total.replaceAll("-", ""));
          _sumReceivable30 += amount;
          row5_receivable =
              '${CurrencyFormatter.formatCurrencyParts(_sumReceivable30).number} DR';
        }

        if (overdue_int > int.parse(heading2) && overdue_int <= int.parse(heading3)) {
          final amount = double.parse(total.replaceAll("-", ""));
          _sumReceivable60 += amount;
          row4_receivable =
              '${CurrencyFormatter.formatCurrencyParts(_sumReceivable60).number} DR';
        }

        if (overdue_int > int.parse(heading3) && overdue_int <= int.parse(heading4)) {
          final amount = double.parse(total.replaceAll("-", ""));
          _sumReceivable90 += amount;
          row3_receivable =
              '${CurrencyFormatter.formatCurrencyParts(_sumReceivable90).number} DR';
        }

        if (overdue_int > int.parse(heading4) && overdue_int <= int.parse(heading5)) {
          final amount = double.parse(total.replaceAll("-", ""));
          _sumReceivable120 += amount;
          row2_receivable =
              '${CurrencyFormatter.formatCurrencyParts(_sumReceivable120).number} DR';
        }

        if (overdue_int > int.parse(heading5)) {
          final amount = double.parse(total.replaceAll("-", ""));
          _sumReceivable180 += amount;
          row1_receivable =
              '${CurrencyFormatter.formatCurrencyParts(_sumReceivable180).number} DR';
        }

        _commit(_refreshReceivablePayableGrandTotals);
      }
    } else {
      if (payableparty == 'True') {
        _commit(() {
          PayableVisibility = true;
        });
        if (overdue_int > 0 && overdue_int <= int.parse(heading1)) {
          final amount = double.parse(total);
          _sumPayable0 += amount;
          row6_payable =
              '${CurrencyFormatter.formatCurrencyParts(_sumPayable0).number} CR';
        }

        if (overdue_int > int.parse(heading1) && overdue_int <= int.parse(heading2)) {
          final amount = double.parse(total);
          _sumPayable30 += amount;
          row5_payable =
              '${CurrencyFormatter.formatCurrencyParts(_sumPayable30).number} CR';
        }

        if (overdue_int > int.parse(heading2) && overdue_int <= int.parse(heading3)) {
          final amount = double.parse(total);
          _sumPayable60 += amount;
          row4_payable =
              '${CurrencyFormatter.formatCurrencyParts(_sumPayable60).number} CR';
        }

        if (overdue_int > int.parse(heading3) && overdue_int <= int.parse(heading4)) {
          final amount = double.parse(total);
          _sumPayable90 += amount;
          row3_payable =
              '${CurrencyFormatter.formatCurrencyParts(_sumPayable90).number} CR';
        }

        if (overdue_int > int.parse(heading4) && overdue_int <= int.parse(heading5)) {
          final amount = double.parse(total);
          _sumPayable120 += amount;
          row2_payable =
              '${CurrencyFormatter.formatCurrencyParts(_sumPayable120).number} CR';
        }

        if (overdue_int > int.parse(heading5)) {
          final amount = double.parse(total);
          _sumPayable180 += amount;
          row1_payable =
              '${CurrencyFormatter.formatCurrencyParts(_sumPayable180).number} CR';
        }

        _commit(_refreshReceivablePayableGrandTotals);
      }
    }
  }

  void formatSalePurc(String total, String vchtype) {
    double i = 0;
    String total_string = "";

    if (total != 'null') {
      i = double.parse(total);
    }
    if (total != 'null') {
      if (total.contains("-")) {
        total_string = i.toString();
        total_string = total_string.replaceAll("-", "");
        double total_double = double.parse(total_string);
        total_string = CurrencyFormatter.formatCurrency_double(total_double);
        total_string = total_string + " DR";
      } else {
        total_string = i.toString();
        double total_double = double.parse(total_string);
        total_string = CurrencyFormatter.formatCurrency_double(total_double);
        total_string = total_string + " CR";
      }
    }
    if (vchtype == 'SalesOrder') {
      if (pendingsalesorderparty == 'True') {
        if (total == 'null') {
          _commit(() {
            SalesOrderVisibility = false;
            pendingsalesorder = "0";
          });
        } else {
          _commit(() {
            SalesOrderVisibility = true;
            pendingsalesorder = total;
          });
        }
      }
    }
    if (vchtype == 'PurcOrder') {
      if (pendingpurchaseorderparty == 'True') {
        if (total == 'null') {
          _commit(() {
            PurchaseOrderVisibility = false;
            pendingpurchaseorder = "0";
          });
        } else {
          _commit(() {
            PurchaseOrderVisibility = true;
            pendingpurchaseorder = total_string;
          });
        }
      }
    }
  }

  /// A single `GET vouchers` drilldown + client-side aggregation - see
  /// `fetchDrilldownVouchers` (unchanged, was already tally-api-backed).
  Future<void> fetchSoldPurchase(String vchtype) async {
    final ledgerMasterId = args.ledgerMasterId;
    if (ledgerMasterId == null) return;

    final isSold = vchtype == 'Sales';

    _commit(() {
      item_count = "0";
      _isLoading = true;
      if (isSold) {
        isVisibleSoldList = false;
      } else {
        isVisiblePurchaseList = false;
      }
      isVisibleNoDataFound = false;
      _isSearchViewVisible = false;
    });

    filteredItems_sold.clear();
    sold_list.clear();
    filteredItems_purchase.clear();
    purchase_list.clear();

    try {
      final from = parseCompactDate(startDateString);
      final to = parseCompactDate(endDateString);
      final vouchers = await fetchDrilldownVouchers(
        from: from,
        to: to,
        partyLedgerName: args.partyname,
        voucherTypeName: vchtype,
      );

      final totals = <String, Map<String, dynamic>>{};
      for (final voucher in vouchers) {
        final inventoryEntries =
            (voucher['inventoryEntries'] as List?)?.cast<Map<String, dynamic>>() ??
                const [];
        final date = voucher['date']?.toString() ?? '';
        for (final entry in inventoryEntries) {
          final name = (entry['stockItemName'] ?? '').toString();
          final bucket = totals.putIfAbsent(
            name,
            () => {'qty': 0.0, 'unit': '', 'lastdate': '', 'rate': '0'},
          );
          bucket['qty'] = (bucket['qty'] as double) + parseMoneyField(entry['quantity']);
          bucket['unit'] = entry['unitSymbol'] ?? bucket['unit'];
          if (date.compareTo(bucket['lastdate'] as String) >= 0) {
            bucket['lastdate'] = date;
            bucket['rate'] = (entry['rate'] ?? '0').toString();
          }
        }
      }

      final items = [
        for (final entry in totals.entries)
          Sold_Purchased(
            item: entry.key,
            qty: (entry.value['qty'] as double).toString(),
            unit: (entry.value['unit'] as String),
            lastdate: (entry.value['lastdate'] as String),
            rate: (entry.value['rate'] as String),
          ),
      ];

      _commit(() {
        if (isSold) {
          sold_list.addAll(items);
          filteredItems_sold = sold_list;
          isVisibleSoldList = items.isNotEmpty;
        } else {
          purchase_list.addAll(items);
          filteredItems_purchase = purchase_list;
          isVisiblePurchaseList = items.isNotEmpty;
        }
        item_count = items.length.toString();
        isVisibleNoDataFound = items.isEmpty;
        _isLoading = false;
      });
    } catch (e) {
      _commit(() {
        if (isSold) {
          isVisibleSoldList = false;
        } else {
          isVisiblePurchaseList = false;
        }
        isVisibleNoDataFound = true;
        _isLoading = false;
      });
      debugPrint('PartyClicked tally-api sold/purchase fetch failed: $e');
    }
  }

  void filterSold(String query) {
    final lower = query.toLowerCase();
    _commit(() {
      filteredItems_sold = query.isEmpty
          ? sold_list
          : sold_list.where((item) => item.item.toLowerCase().contains(lower)).toList();
    });
  }

  void filterPurchase(String query) {
    final lower = query.toLowerCase();
    _commit(() {
      filteredItems_purchase = query.isEmpty
          ? purchase_list
          : purchase_list
              .where((item) => item.item.toLowerCase().contains(lower))
              .toList();
    });
  }

  void toggleSearchView() {
    _commit(() {
      _isSearchViewVisible = !_isSearchViewVisible;
      if (!_isSearchViewVisible) {
        if (isClicked_Sold) {
          filteredItems_sold = sold_list;
        } else if (isClicked_Purchase) {
          filteredItems_purchase = purchase_list;
        }
      }
    });
  }

  void selectSoldTab() {
    _commit(() {
      isClicked_Summary = false;
      isClicked_Sold = true;
      isClicked_Purchase = false;
      isSearchLayoutVisible = true;
    });
    fetchSoldPurchase('Sales');
  }

  void selectPurchaseTab() {
    _commit(() {
      isClicked_Purchase = true;
      isClicked_Sold = false;
      isClicked_Summary = false;
      isSearchLayoutVisible = true;
    });
    fetchSoldPurchase('Purchase');
  }

  /// tally-api equivalent of legacy `fetchSummaryData` - populates the exact
  /// same state fields the existing UI (`SummaryExpansionCard`,
  /// `ReceivableBreakdownCard`/`PayableBreakdownCard`, `PendingOrderTile`)
  /// already renders.
  Future<void> _fetchSummaryDataTallyApi(
    String startdate_string,
    String enddate_string,
  ) async {
    final ledgerMasterId = args.ledgerMasterId;
    if (ledgerMasterId == null) return;

    months_list_sales.clear();
    months_list_purchase.clear();
    months_list_receipt.clear();
    months_list_payment.clear();
    months_list_creditnote.clear();
    months_list_debitnote.clear();
    months_list_journal.clear();

    row1_receivable = formatRemainingOverdue("0");
    row2_receivable = formatRemainingOverdue("0");
    row3_receivable = formatRemainingOverdue("0");
    row4_receivable = formatRemainingOverdue("0");
    row5_receivable = formatRemainingOverdue("0");
    row6_receivable = formatRemainingOverdue("0");

    row1_payable = formatRemainingOverdue("0");
    row2_payable = formatRemainingOverdue("0");
    row3_payable = formatRemainingOverdue("0");
    row4_payable = formatRemainingOverdue("0");
    row5_payable = formatRemainingOverdue("0");
    row6_payable = formatRemainingOverdue("0");

    _commit(() {
      _isLoading = true;
      isClicked_Summary = true;
      isClicked_Sold = false;
      isClicked_Purchase = false;
      isSearchLayoutVisible = false;
      isVisibleNoDataFound = false;

      SalesVisibility = false;
      PurchaseVisibility = false;
      ReceiptVisibility = false;
      PaymentVisibility = false;
      CreditnoteVisibility = false;
      DebitnoteVisibility = false;
      JournalVisibility = false;
      ReceivableVisibility = false;
      PayableVisibility = false;
      PurchaseOrderVisibility = false;
      SalesOrderVisibility = false;
    });

    try {
      final from = parseCompactDate(startdate_string);
      final to = parseCompactDate(enddate_string);
      final ledgerRepo = _ref.read(ledgerRepositoryProvider);

      final summaryRows = await ledgerRepo.ledgerSummary(
        ledgerMasterId,
        from: from,
        to: to,
      );

      if (summaryRows.isEmpty) {
        _commit(() => isVisibleNoDataFound = true);
      }

      for (final row in summaryRows) {
        final vchtype = (row['voucherTypeName'] as String? ?? '').replaceAll(' ', '');
        final totalAmount = (row['totalAmount'] ?? '0').toString();
        final averageAmount = (row['averageAmount'] ?? '0').toString();
        final invoiceCount = (row['invoiceCount'] ?? 0).toString();
        final lastDate = (row['lastDate'] ?? '').toString();

        switch (vchtype) {
          case 'Sales':
            if (salesparty != 'True') continue;
            _commit(() => SalesVisibility = true);
            totalsaleamt = totalAmount;
            avgsalesinvoiceamt = averageAmount;
            noofsalesinvoice = invoiceCount;
            lastsaledate = lastDate;
          case 'Purchase':
            if (purchaseparty != 'True') continue;
            _commit(() => PurchaseVisibility = true);
            totalpurchaseamt = totalAmount;
            avgpurchaseinvoiceamt = averageAmount;
            noofpurchaseinvoice = invoiceCount;
            lastpurchasedate = lastDate;
          case 'Receipt':
            if (receiptparty != 'True') continue;
            _commit(() => ReceiptVisibility = true);
            totalreceiptamt = totalAmount;
            avgreceiptinvoiceamt = averageAmount;
            noofreceiptinvoice = invoiceCount;
            lastreceiptdate = lastDate;
          case 'Payment':
            if (paymentparty != 'True') continue;
            _commit(() => PaymentVisibility = true);
            totalpaymentamt = totalAmount;
            avgpaymentinvoiceamt = averageAmount;
            noofpaymentinvoice = invoiceCount;
            lastpaymentdate = lastDate;
          case 'CreditNote':
            if (creditnoteparty != 'True') continue;
            _commit(() => CreditnoteVisibility = true);
            totalcreditnoteamt = totalAmount;
            avgcreditnoteinvoiceamt = averageAmount;
            noofcreditnoteinvoice = invoiceCount;
            lastcreditnotedate = lastDate;
          case 'DebitNote':
            if (debitnoteparty != 'True') continue;
            _commit(() => DebitnoteVisibility = true);
            totaldebitnoteamt = totalAmount;
            avgdebitnoteinvoiceamt = averageAmount;
            noofdebitnoteinvoice = invoiceCount;
            lastdebitnotedate = lastDate;
          case 'Journal':
            if (journalparty != 'True') continue;
            _commit(() => JournalVisibility = true);
            totaljournalamt = totalAmount;
            avgjournalinvoiceamt = averageAmount;
            noofjournalinvoice = invoiceCount;
            lastjournaldate = lastDate;
          default:
          // DeliveryNote/other reserved names - not shown in this summary.
        }
      }

      if (SalesVisibility ||
          PurchaseVisibility ||
          ReceiptVisibility ||
          PaymentVisibility ||
          CreditnoteVisibility ||
          DebitnoteVisibility ||
          JournalVisibility) {
        final vouchers = await _ref.read(voucherRepositoryProvider).listInRange(
              from: from,
              to: to,
            );

        void bucketInto(List<months> target, String vchtypeKey) {
          final rows = <Map<String, dynamic>>[];
          for (final voucher in vouchers) {
            final voucherType =
                (voucher['voucherTypeName'] as String? ?? '').replaceAll(' ', '');
            if (voucherType != vchtypeKey) continue;
            final entries =
                (voucher['ledgerEntries'] as List?)?.cast<Map<String, dynamic>>() ??
                    const [];
            for (final entry in entries) {
              if (entry['ledgerMasterId'] != ledgerMasterId) continue;
              rows.add({
                'date': voucher['date'],
                'amount': parseMoneyField(entry['amount']).abs(),
              });
            }
          }
          final buckets = bucketByMonth(
            rows,
            dateOf: (r) => DateTime.parse(r['date'] as String),
            amountOf: (r) => r['amount'] as double,
          );
          target.addAll([
            for (final b in buckets) months(mname: b.label, total: b.total.toString()),
          ]);
        }

        if (SalesVisibility) bucketInto(months_list_sales, 'Sales');
        if (PurchaseVisibility) bucketInto(months_list_purchase, 'Purchase');
        if (ReceiptVisibility) bucketInto(months_list_receipt, 'Receipt');
        if (PaymentVisibility) bucketInto(months_list_payment, 'Payment');
        if (CreditnoteVisibility) bucketInto(months_list_creditnote, 'CreditNote');
        if (DebitnoteVisibility) bucketInto(months_list_debitnote, 'DebitNote');
        if (JournalVisibility) bucketInto(months_list_journal, 'Journal');
      }

      if (receivableparty == 'True' || payableparty == 'True') {
        _sumReceivable0 = 0;
        _sumReceivable30 = 0;
        _sumReceivable60 = 0;
        _sumReceivable90 = 0;
        _sumReceivable120 = 0;
        _sumReceivable180 = 0;
        _sumPayable0 = 0;
        _sumPayable30 = 0;
        _sumPayable60 = 0;
        _sumPayable90 = 0;
        _sumPayable120 = 0;
        _sumPayable180 = 0;
        _currentReceivableOnAccount = 0;
        _currentPayableOnAccount = 0;

        final totals = await ledgerRepo.outstandingTotal(ledgerMasterId);
        formatRecPayTotal((totals['outstanding'] ?? '0').toString());

        final bills = await ledgerRepo.outstandingBills(ledgerMasterId: ledgerMasterId);
        for (final bill in bills) {
          final outstanding = (bill['finalBalance'] ?? '0').toString();
          final overdueDays = bill['overdueDays'] as int?;
          formatOnAccountWithBillNo(overdueDays ?? 0, outstanding);
        }
      }

      if (pendingsalesorderparty == 'True') {
        final row = await ledgerRepo.pendingOrderTotal(
          ledgerMasterId,
          isSales: true,
          from: from,
          to: to,
        );
        formatSalePurc((row?['totalAmount'] ?? 'null').toString(), 'SalesOrder');
      }
      if (pendingpurchaseorderparty == 'True') {
        final row = await ledgerRepo.pendingOrderTotal(
          ledgerMasterId,
          isSales: false,
          from: from,
          to: to,
        );
        formatSalePurc((row?['totalAmount'] ?? 'null').toString(), 'PurcOrder');
      }

      _commit(() => _isLoading = false);
    } catch (e) {
      _commit(() => _isLoading = false);
      debugPrint('PartyClicked tally-api summary fetch failed: $e');
    }
  }

  void fetchSummary() {
    if (salesparty == 'False' &&
        purchaseparty == 'False' &&
        receiptparty == 'False' &&
        paymentparty == 'False' &&
        creditnoteparty == 'False' &&
        debitnoteparty == 'False' &&
        journalparty == 'False' &&
        receivableparty == 'False' &&
        payableparty == 'False' &&
        pendingsalesorderparty == 'False' &&
        pendingpurchaseorderparty == 'False') {
      isVisibleSummaryBtn = false;
      isClicked_Summary = false;
      if (party_suppliers == 'True') {
        isClicked_Purchase = true;
        isClicked_Sold = false;
        isClicked_Summary = false;
        isSearchLayoutVisible = true;
        fetchSoldPurchase('Purchase');
      } else if (party_customers == 'True') {
        isClicked_Summary = false;
        isClicked_Sold = true;
        isClicked_Purchase = false;
        isSearchLayoutVisible = true;
        fetchSoldPurchase('Sales');
      }
    } else {
      _commit(() {
        isVisibleSummaryBtn = true;
        isClicked_Summary = true;
      });
      _fetchSummaryDataTallyApi(startDateString, endDateString);
    }
  }

  Future<void> _init() async {
    prefs = await SharedPreferences.getInstance();

    company = prefs.getString('company_name') ?? '';
    _selecteddate = prefs.getString('datetype') ?? 'Today';

    decimal = prefs.getInt('decimalplace') ?? 2;
    currencyFormat = NumberFormat();

    String currencyCode = prefs.getString('currencycode') ?? "AED";
    try {
      if (currencyCode == 'INR' ||
          currencyCode == 'EUR' ||
          currencyCode == 'USD' ||
          currencyCode == 'PKR') {
        currencyFormat = NumberFormat('#,##0');
        NumberFormat format = NumberFormat.simpleCurrency(locale: 'en', name: currencyCode);
        currencysymbol = format.currencySymbol;
      } else {
        NumberFormat format = NumberFormat.currency(locale: 'en', name: currencyCode);
        currencysymbol = format.currencySymbol;
        currencyFormat = NumberFormat('#,##0');
      }
    } catch (e) {
      NumberFormat format = NumberFormat.currency(locale: 'en', name: currencyCode);
      currencysymbol = format.currencySymbol;
      currencyFormat = NumberFormat('#,##0');
    }
    _currencyCode = currencyCode;

    salesparty = prefs.getString("salesparty") ?? 'False';
    purchaseparty = prefs.getString("purchaseparty") ?? 'False';
    creditnoteparty = prefs.getString("creditnoteparty") ?? 'False';
    journalparty = prefs.getString("journalparty") ?? 'False';
    payableparty = prefs.getString("payableparty") ?? 'False';
    pendingpurchaseorderparty = prefs.getString("pendingpurchaseorderparty") ?? 'False';
    receiptparty = prefs.getString("receiptparty") ?? 'False';
    paymentparty = prefs.getString("paymentparty") ?? 'False';
    debitnoteparty = prefs.getString("debitnoteparty") ?? 'False';
    receivableparty = prefs.getString("receivableparty") ?? 'False';
    pendingsalesorderparty = prefs.getString("pendingsalesorderparty") ?? 'False';
    party_suppliers = prefs.getString("purchaseparty") ?? 'False';
    party_customers = prefs.getString("salesparty") ?? 'False';

    isVisiblePurchaseBtn = party_suppliers == 'True';
    isVisibleSoldBtn = party_customers == 'True';

    if (prefs.getString('heading1') == null) {
      heading1 = '30';
      heading2 = '60';
      heading3 = '90';
      heading4 = '120';
      heading5 = '180';
    } else {
      heading1 = prefs.getString('heading1')!;
      heading2 = prefs.getString('heading2')!;
      heading3 = prefs.getString('heading3')!;
      heading4 = prefs.getString('heading4')!;
      heading5 = prefs.getString('heading5')!;
    }

    row1_receivable_heading_value = heading5;
    row2_receivable_heading_value = heading4;
    row3_receivable_heading_value = heading3;
    row4_receivable_heading_value = heading2;
    row5_receivable_heading_value = heading1;
    row6_receivable_heading_value = '0';

    row1_payable_heading_value = heading5;
    row2_payable_heading_value = heading4;
    row3_payable_heading_value = heading3;
    row4_payable_heading_value = heading2;
    row5_payable_heading_value = heading1;
    row6_payable_heading_value = '0';

    row1_receivable_heading = ">$row1_receivable_heading_value";
    row2_receivable_heading = ">$row2_receivable_heading_value";
    row3_receivable_heading = ">$row3_receivable_heading_value";
    row4_receivable_heading = ">$row4_receivable_heading_value";
    row5_receivable_heading = ">$row5_receivable_heading_value";
    row6_receivable_heading = ">$row6_receivable_heading_value";

    row1_payable_heading = ">$row1_payable_heading_value";
    row2_payable_heading = ">$row2_payable_heading_value";
    row3_payable_heading = ">$row3_payable_heading_value";
    row4_payable_heading = ">$row4_payable_heading_value";
    row5_payable_heading = ">$row5_payable_heading_value";
    row6_payable_heading = ">$row6_payable_heading_value";

    if (_selecteddate == 'Custom Date') {
      final startfrom = prefs.getString('startdate');
      final endfrom = prefs.getString('enddate');
      if (startfrom != null && endfrom != null) {
        setCustomDateRangeFromPrefs(DateTime.parse(startfrom), DateTime.parse(endfrom));
        return;
      }
    }

    await handleDate(_selecteddate as String);
  }

  /// Only used when restoring a persisted "Custom Date" selection at
  /// startup - unlike [setCustomDateRange] (triggered by the date picker),
  /// this must not re-trigger a fetch itself; [_init] calls [handleDate]
  /// right after for that.
  void setCustomDateRangeFromPrefs(DateTime start, DateTime end) {
    final startMonth = DateFormat('MMM').format(start);
    final sdf = DateFormat('MM').format(start);
    final startDay = DateFormat('dd').format(start);
    final startYear = start.year;

    final endMonth = DateFormat('MMM').format(end);
    final sdfEnd = DateFormat('MM').format(end);
    final endDay = DateFormat('dd').format(end);
    final endYear = end.year;

    startDateString = '$startYear$sdf$startDay';
    endDateString = '$endYear$sdfEnd$endDay';
    startdate_text = '$startDay-$startMonth-$startYear';
    enddate_text = '$endDay-$endMonth-$endYear';

    fetchSummary();
  }

  void setCustomDateRange(DateTime start, DateTime end) {
    if (!_isTextEnabled) return;
    final startMonth = DateFormat('MMM').format(start);
    final sdf = DateFormat('MM').format(start);
    final startDay = DateFormat('dd').format(start);
    final startYear = start.year;

    final endMonth = DateFormat('MMM').format(end);
    final sdfEnd = DateFormat('MM').format(end);
    final endDay = DateFormat('dd').format(end);
    final endYear = end.year;

    _commit(() {
      startDateString = '$startYear$sdf$startDay';
      endDateString = '$endYear$sdfEnd$endDay';
      startdate_text = '$startDay-$startMonth-$startYear';
      enddate_text = '$endDay-$endMonth-$endYear';
      fetchSummary();
    });
  }

  Future<void> handleDate(String value) async {
    _commit(() => _selecteddate = value);

    DateTime start;
    DateTime end;
    var isTextEnabled = false;

    switch (value) {
      case 'Today':
        start = DateTime.now();
        end = start;
        break;
      case 'Yesterday':
        start = DateTime.now().subtract(const Duration(days: 1));
        end = start;
        break;
      case 'This Month':
        final now = DateTime.now();
        start = DateTime(now.year, now.month, 1);
        end = DateTime(now.year, now.month + 1, 0);
        break;
      case 'Last Month':
        final now = DateTime.now();
        start = DateTime(now.year, now.month - 1, 1);
        end = DateTime(start.year, start.month + 1, 0);
        break;
      case 'This Year':
        final now = DateTime.now();
        start = DateTime(now.year, 1, 1);
        end = DateTime(now.year, 12, 31);
        break;
      case 'Last Year':
        final now = DateTime.now();
        start = DateTime(now.year - 1, 1, 1);
        end = DateTime(now.year - 1, 12, 31);
        break;
      case 'Year To Date':
        final now = DateTime.now();
        start = DateTime(now.year, 1, 1);
        end = DateTime(now.year, now.month, now.day);
        break;
      case 'Custom Date':
      default:
        _commit(() => _isTextEnabled = true);
        return;
    }

    final startMonth = DateFormat('MMM').format(start);
    final sdf = DateFormat('MM').format(start);
    final startDay = DateFormat('dd').format(start);
    final startYear = start.year;

    final endMonth = DateFormat('MMM').format(end);
    final sdfEnd = DateFormat('MM').format(end);
    final endDay = DateFormat('dd').format(end);
    final endYear = end.year;

    startDateString = '$startYear$sdf$startDay';
    endDateString = '$endYear$sdfEnd$endDay';
    startdate_text = '$startDay-$startMonth-$startYear';
    enddate_text = '$endDay-$endMonth-$endYear';

    fetchSummary();

    _commit(() => _isTextEnabled = isTextEnabled);
  }
}

final partyClickedNotifierProvider = StateNotifierProvider.autoDispose
    .family<PartyClickedNotifier, PartyClickedState, PartyClickedArgs>(
  (ref, args) => PartyClickedNotifier(ref, args),
);
