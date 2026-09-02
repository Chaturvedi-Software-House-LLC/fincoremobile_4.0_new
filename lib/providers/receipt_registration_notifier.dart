import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../Items.dart' show formatlastsaledate;
import '../ReceiptRegistration.dart';
import '../api/api_exception.dart';
import '../api/ledger_repository.dart';
import '../api/monthly_bucket_helper.dart' show parseMoneyField, parseCompactDate;
import '../api/pagination_helper.dart';
import '../api/tally_api_client.dart';
import '../api/voucher_entry_dropdowns_repository.dart';
import '../api/voucher_entry_repository.dart';
import '../constants.dart' show uniGasSerialNumber;

/// Riverpod migration of `ReceiptRegistration.dart`'s
/// `_ReceiptRegistrationPageState`. Same verbatim `_commit`/`_snapshot` port
/// strategy as `sales_registration_notifier.dart`/
/// `sales_order_registration_notifier.dart` (read those first - this is
/// their closest sibling, structurally simpler since Receipt is ledger-only,
/// no item/inventory section at all).
///
/// Structural deviations from the two sibling screens, specific to this
/// screen:
/// - No item/inventory accumulator (`SaleItem`/`_recalculateTotals` over
///   items) - this screen's own "line items" are `Bills` (bill allocations
///   against the party ledger) and `Cheque` (bank/cash instrument
///   allocations), both defined in `ReceiptRegistration.dart` itself
///   (mirrors how `SaleItem`/`LedgerEntry` live in `SalesRegistration.dart`).
/// - `loadData()` is backed by `VoucherEntryDropdownsRepository.receiptData()`
///   (`vchTypes`/`partyLedgers`/`cashLedgers`, already
///   GroupReservedName/VoucherReservedName-classified server-side) plus a
///   `/currencies` lookup - no stock-item/godown data at all.
/// - `saveEntry()`'s payload is two ledger entries (party ledger credited
///   with bill allocations, bank/cash ledger debited with optional bank
///   allocations from `cheque`) - no inventory entries.
/// - Party-wise outstanding bills (`fetchPartyOutstanding`/
///   `buildOutstandingCard`) is a UniGas-only feature gated by
///   `isUniGasSerial` (`showOutstandingBills` is a permanently-on manual
///   kill-switch, kept verbatim even though it's never flipped).
/// - `_selectedbill`/`isVisibleDueDate`/`isVisibleBillNo`/`billsdata`/
///   `_billsFormkey`/`billAmountController`/`billNoController`/
///   `_billduedateController` (the "Add Bill" dialog) and
///   `selectedbankname`/`_banknameController`/`instNoController`/`instdate`/
///   `instdatestring`/`instdatetxt`/`instDateController`/
///   `chequeAmountController`/`_chequedetailsFormkey` (the "Add
///   Cheque/Instrument" dialog) are dialog-composition-only, exactly like
///   the sibling screens' item/ledger-add dialogs - they stay widget-local.
///   `addBill()`/`addCheque()` become notifier methods
///   (`addBill`/`addCheque` below) taking the dialog's resolved plain values
///   and returning a result enum; the widget's same-named wrapper shows the
///   matching `AlertDialog`/pops the sheet based on that result, mirroring
///   the `XActionResult` pattern used for other button-triggered actions
///   across this migration.
/// - `receiverNameController`/`receiverMobileController`/
///   `receiverSignatureBytes` (UniGas-only "Receiver Information", used only
///   for PDF rendering, never sent to `saveEntry`'s payload) stay
///   widget-local alongside the other controllers - they're presentation-only.
/// - Two distinct "reset the form" paths exist in the original and are kept
///   distinct rather than unified: `showReceiptVoucherDialog`'s "No, Thanks"
///   button has its own inline reset (ported as [declineShareReset]) that
///   does NOT clear the receiver name/mobile/signature fields, while
///   `_resetReceiptFormAfterShare` (ported as [resetAfterShare], used by
///   both the regular share flow and the UniGas print flow) DOES clear them
///   (via the widget's own wrapper, since those three fields are
///   widget-local). This mirrors a genuine asymmetry already present in the
///   original - not "fixed" here.
/// - `loadData()`'s own internal `fetchvchnos(...)` call is `await`-ed here
///   (the original fires it off without awaiting) - the same normalization
///   `sales_registration_notifier.dart`'s own `loadData()` already applies
///   for the identical reason (avoids a load-order race with `isLoading`
///   flipping false before the voucher-number fetch resolves); every other
///   call site that fires `fetchvchnos` without awaiting in the original
///   (dropdown `onChanged`, date-range picker, "No, Thanks" reset) stays
///   fire-and-forget, via the widget's own `fetchvchnos` wrapper.
///
/// Dead fields dropped rather than ported (declared/written but never read
/// for logic/UI outside their own declaration, confirmed via grep before
/// dropping): `isDashEnable`, `isRolesVisible`, `isUserVisible`,
/// `isUserEnable`, `isRolesEnable`, `isVisibleNoUserFound`, `hostname`
/// (write-only), `company_lowercase` (write-only), `username` (write-only),
/// `HttpURL`, `HttpURL_loadData`/`HttpURL_receiptEntry`/`HttpURL_fetchvchnos`/
/// `HttpURL_fetchoutstanding`/`HttpURL_loadLedgerData` (all declared-only,
/// pre-tally-api leftovers), `email` (write-only - fed from nav args but
/// never read; `name` IS live, read by the UniGas receipt PDF's "Driver
/// Name" line, so it's kept), `jsonEntryData` (declared-only legacy Tally
/// XML payload shape), `user_email_fetched` (declared-only),
/// `isVanSalesUser` (a getter declared but never called anywhere outside
/// its own declaration). `SecuritybtnAcessHolder` IS live (read by
/// `canEditVoucherNo` in `build()`) and is kept. `isVchEditable` is a pure
/// UI toggle (locks/unlocks the voucher-no field for editing) with no
/// business-logic reader - kept widget-local via plain `setState`, same
/// treatment as the dialog-composition fields.
///
/// Also deleted outright (not ported): a large block-commented dead legacy
/// `loadData()` (the pre-tally-api hostname/http version, ~200 lines
/// immediately before the live `loadData()`), a block-commented dead
/// `_showBillsDetailsPopup` (superseded by the live `showModalBottomSheet`
/// version immediately below it), and a block-commented dead
/// `_showChequeDetailsPopup` (superseded the same way) - all three were
/// already fully commented out in the source, confirmed dead by inspection
/// (their live, call-site-reachable replacements sit immediately after each
/// one), not merely assumed dead from proximity.
class ReceiptRegistrationState {
  final List<String> vchTypeNameData;
  final List<String> partyData;
  final List<Map<String, String>> bankCashNameData;
  final List<String> paymentModeData;
  final List<String> bankNameData;

  final List<Bills> bills;
  final List<Cheque> cheque;

  final double totalBillAmount;
  final double roundedTotalBillAmount;
  final String formattedTotalBillAmount;
  final double totalChequeAmount;
  final double roundedTotalChequeAmount;

  final bool isVisibleBillHeading;
  final bool isVisibleChequeHeading;
  final bool isChequeVisible;
  final bool isPaymentModeVisible;

  final bool isVoucherTypeLocked;
  final bool isBankCashLedgerLocked;

  final bool isLoading;
  final bool isInitialDataLoaded;

  final String? company;
  final String? serialNo;
  final String token;
  final String currencyCode;
  final String name;
  final int decimal;
  final String? secBtnAccessHolder;

  final DateTime receiptDate;
  final String receiptDateString;
  final String receiptDateText;

  final DateTime yearStartDate;
  final DateTime yearEndDate;

  final String selectedVchTypeName;
  final dynamic selectedParty;
  final Map<String, String>? selectedBankCashName;
  final dynamic selectedPaymentMode;

  final String errorMessageVchNo;
  final List<String> vchNos;

  final bool isOutstandingLoading;
  final String outstandingError;
  final double openingOutstanding;
  final double totalOutstanding;
  final List<dynamic> outstandingBills;
  final bool showOutstandingCard;
  final bool isOutstandingExpanded;
  final int visibleOutstandingBillCount;

  const ReceiptRegistrationState({
    required this.vchTypeNameData,
    required this.partyData,
    required this.bankCashNameData,
    required this.paymentModeData,
    required this.bankNameData,
    required this.bills,
    required this.cheque,
    required this.totalBillAmount,
    required this.roundedTotalBillAmount,
    required this.formattedTotalBillAmount,
    required this.totalChequeAmount,
    required this.roundedTotalChequeAmount,
    required this.isVisibleBillHeading,
    required this.isVisibleChequeHeading,
    required this.isChequeVisible,
    required this.isPaymentModeVisible,
    required this.isVoucherTypeLocked,
    required this.isBankCashLedgerLocked,
    required this.isLoading,
    required this.isInitialDataLoaded,
    required this.company,
    required this.serialNo,
    required this.token,
    required this.currencyCode,
    required this.name,
    required this.decimal,
    required this.secBtnAccessHolder,
    required this.receiptDate,
    required this.receiptDateString,
    required this.receiptDateText,
    required this.yearStartDate,
    required this.yearEndDate,
    required this.selectedVchTypeName,
    required this.selectedParty,
    required this.selectedBankCashName,
    required this.selectedPaymentMode,
    required this.errorMessageVchNo,
    required this.vchNos,
    required this.isOutstandingLoading,
    required this.outstandingError,
    required this.openingOutstanding,
    required this.totalOutstanding,
    required this.outstandingBills,
    required this.showOutstandingCard,
    required this.isOutstandingExpanded,
    required this.visibleOutstandingBillCount,
  });
}

enum AddBillOutcome { added, duplicateOnAccount, notAdded }

enum AddChequeOutcome {
  added,
  exceedsRemaining,
  duplicateInstNo,
  noBillsYet,
  chequeAlreadyFullyAllocated,
  exceedsTotal,
}

class ReceiptRegistrationNotifier
    extends StateNotifier<ReceiptRegistrationState> {
  final Ref _ref;

  ReceiptRegistrationNotifier(this._ref)
    : super(
        ReceiptRegistrationState(
          vchTypeNameData: const [],
          partyData: const [],
          bankCashNameData: const [],
          paymentModeData: const [],
          bankNameData: const [],
          bills: const [],
          cheque: const [],
          totalBillAmount: 0,
          roundedTotalBillAmount: 0,
          formattedTotalBillAmount: '0',
          totalChequeAmount: 0,
          roundedTotalChequeAmount: 0,
          isVisibleBillHeading: false,
          isVisibleChequeHeading: false,
          isChequeVisible: false,
          isPaymentModeVisible: false,
          isVoucherTypeLocked: false,
          isBankCashLedgerLocked: false,
          isLoading: true,
          isInitialDataLoaded: false,
          company: '',
          serialNo: '',
          token: '',
          currencyCode: '',
          name: '',
          decimal: 2,
          secBtnAccessHolder: '',
          receiptDate: DateTime.now(),
          receiptDateString: '',
          receiptDateText: '',
          yearStartDate: DateTime(DateTime.now().year, 1, 1),
          yearEndDate: DateTime(DateTime.now().year, 12, 31),
          selectedVchTypeName: '',
          selectedParty: null,
          selectedBankCashName: null,
          selectedPaymentMode: '',
          errorMessageVchNo: '',
          vchNos: const [],
          isOutstandingLoading: false,
          outstandingError: '',
          openingOutstanding: 0.0,
          totalOutstanding: 0.0,
          outstandingBills: const [],
          showOutstandingCard: false,
          isOutstandingExpanded: false,
          visibleOutstandingBillCount: 5,
        ),
      ) {
    _init();
  }

  void _commit(void Function() fn) {
    fn();
    state = _snapshot();
  }

  ReceiptRegistrationState _snapshot() => ReceiptRegistrationState(
    vchTypeNameData: List.unmodifiable(vchtypenamedata),
    partyData: List.unmodifiable(partydata),
    bankCashNameData: List.unmodifiable(bankcashname_data),
    paymentModeData: List.unmodifiable(paymentmode_data),
    bankNameData: List.unmodifiable(bankname_data),
    bills: List.unmodifiable(bills),
    cheque: List.unmodifiable(cheque),
    totalBillAmount: totalBillAmount,
    roundedTotalBillAmount: roundedtotalBillAmount,
    formattedTotalBillAmount: _formatDecimal(roundedtotalBillAmount),
    totalChequeAmount: totalChequeAmount,
    roundedTotalChequeAmount: roundedtotalChequeAmount,
    isVisibleBillHeading: isVisibleBillHeading,
    isVisibleChequeHeading: isVisibleChequeHeading,
    isChequeVisible: isChequeVisible,
    isPaymentModeVisible: isPaymentModeVisible,
    isVoucherTypeLocked: isVoucherTypeLocked,
    isBankCashLedgerLocked: isBankCashLedgerLocked,
    isLoading: _isLoading,
    isInitialDataLoaded: _isInitialDataLoaded,
    company: company,
    serialNo: serial_no,
    token: token,
    currencyCode: currencycode,
    name: name,
    decimal: decimal ?? 2,
    secBtnAccessHolder: SecuritybtnAcessHolder,
    receiptDate: receiptdate,
    receiptDateString: receiptdatestring,
    receiptDateText: receiptdatetxt,
    yearStartDate: yearStartDate,
    yearEndDate: yearEndDate,
    selectedVchTypeName: _selectedvchtypename,
    selectedParty: _selectedparty,
    selectedBankCashName: _selectedbankcashname,
    selectedPaymentMode: _selectedpaymentmode,
    errorMessageVchNo: errorMessageVchNo,
    vchNos: List.unmodifiable(vchnos),
    isOutstandingLoading: isOutstandingLoading,
    outstandingError: outstandingError,
    openingOutstanding: openingOutstanding,
    totalOutstanding: totalOutstanding,
    outstandingBills: List.unmodifiable(outstandingBills),
    showOutstandingCard: showOutstandingCard,
    isOutstandingExpanded: isOutstandingExpanded,
    visibleOutstandingBillCount: visibleOutstandingBillCount,
  );

  String _formatDecimal(double value) {
    final d = decimal ?? 2;
    return NumberFormat('#,##0.${'0' * d}', 'en_US').format(value);
  }

  // ---- verbatim-ported mutable fields (same names as the original State) ----

  List<String> vchtypenamedata = [];
  List<String> partydata = [];
  List<Map<String, String>> bankcashname_data = [];
  List<String> paymentmode_data = [];

  List<String> bankname_data = [
    'Not Applicable',
    "RAK Bank (UAE)",
    "Mashreq Bank (UAE)",
    "National Bank of Abu Dhabi (UAE)",
    "ADCB (UAE)",
    "Arab Bank (UAE)",
    "Commercial Bank of Dubai (UAE)",
    "Emirates NBD (UAE)",
    "Habib Bank AG Zurich (UAE)",
    "National Bank of Fujairah (UAE)",
    "Standard Chartered Bank (UAE)",
    "Bank of Baroda (UAE)",
    "HSBC Bank (UAE)",
    "Union National Bank (UAE)",
    "United Arab Bank (UAE)",
    "Al Ahli Bank of Kuwait (UAE)",
    "Noor Islamic Bank (UAE)",
    "Emirates Bank (UAE)",
    "Emirates Islamic Bank (UAE)",
    "United Bank Ltd. (UAE)",
    "Dubai Islamic Bank (UAE)",
    "ADIB (UAE)",
    "Bank of Sharjah (UAE)",
    "Blom Bank France (UAE)",
    "First Gulf Bank (UAE)",
    "Invest Bank (UAE)",
    "Habib Bank Limited (UAE)",
    "Oman Arab Bank (UAE)",
    "NBAD(UAE)",
    "NCB Bank(UAE)",
    "NBQ Bank (UAE)",
    "HBL Bank (UAE)",
    "Al Hilal Bank(UAE)",
    "FGB (UAE)",
    "Sharjah Islamic Bank(UAE)",
    "Noor Bank(UAE)",
    "CBI - Commercial Bank International (UAE)",
    "Janata Bank Ltd (UAE)",
    "Ajman Bank (UAE)",
    "Bank Melli Iran (UAE)",
    "FAB - First Abu Dhabi Bank (UAE)",
    "Citi Bank (UAE)",
    "The Saudi British Bank (UAE)",
    "BNP Paribas (UAE)",
    "Arab African International Bank (UAE)",
    "AL Masraf (UAE)",
    "Banque Misr (UAE)",
    "Samba Financial Group (UAE)",
  ];

  final TallyApiClient _tallyApiClient = TallyApiClient();
  Map<String, int> _partyLedgerMasterIdByName = {};
  Map<String, int> _bankCashLedgerMasterIdByName = {};
  Map<String, int> _voucherTypeMasterIdByName = {};
  List<Map<String, dynamic>> _partyLedgersRaw = [];
  int? _currencyMasterId;

  /// The raw party-ledger rows `loadData()` cached, exposed for the widget's
  /// `_generateUniGasReceiptPDF`, which resolves the selected party's
  /// TRN/address/mobile/email off them (tally-api replacement for legacy's
  /// `getLedger/:company/:serial` - no second round trip needed since the
  /// full ledger row was already fetched). Read-only for the widget; it's a
  /// pure cache, never rendered directly, so it stays off the state class.
  List<Map<String, dynamic>> get partyLedgersRaw => _partyLedgersRaw;

  /// `prefs.getString('startfrom')` captured once in [_init] - the
  /// financial-year start [fetchVchNos] bounds its `from` param by, exactly
  /// as the original's `fetchvchnos` read it (falling back to
  /// `yearStartDate` when the pref is absent).
  String? _startFromPref;

  List<Bills> bills = [];
  List<Cheque> cheque = [];

  double totalBillAmount = 0;
  double roundedtotalBillAmount = 0;
  double totalChequeAmount = 0;
  double roundedtotalChequeAmount = 0;

  bool isVisibleBillHeading = false;
  bool isVisibleChequeHeading = false;
  bool isChequeVisible = false;
  bool isPaymentModeVisible = false;

  bool isVoucherTypeLocked = false;
  bool isBankCashLedgerLocked = false;

  bool _isLoading = true;
  bool _isInitialDataLoaded = false;

  String? company = '';
  String? serial_no = '';
  String token = '';
  String currencycode = '';
  String name = '';
  int? decimal = 2;
  String? SecuritybtnAcessHolder = '';

  late DateTime receiptdate = DateTime.now();
  String receiptdatestring = '';
  String receiptdatetxt = '';

  late DateTime now = DateTime.now();
  late DateTime yearStartDate = DateTime(now.year, 1, 1);
  late DateTime yearEndDate = DateTime(now.year, 12, 31);

  final DateFormat _dateFormat = DateFormat('yyyyMMdd');

  late String _selectedvchtypename = '';
  dynamic _selectedparty;
  Map<String, String>? _selectedbankcashname;
  late dynamic _selectedpaymentmode = '';

  String errorMessageVchNo = '';
  List<String> vchnos = [];

  bool isOutstandingLoading = false;
  String outstandingError = "";
  double openingOutstanding = 0.0;
  double totalOutstanding = 0.0;
  List<dynamic> outstandingBills = [];
  bool showOutstandingCard = false;
  bool isOutstandingExpanded = false;
  int visibleOutstandingBillCount = 5;

  // `showOutstandingBills` is a permanently-on manual kill-switch in the
  // original (never actually flipped anywhere in this codebase) - kept as a
  // bare constant-ish field rather than plumbed through state, matching how
  // the original declares it directly on the State class.
  final bool showOutstandingBills = true;

  bool get isUniGasSerial {
    final currentSerial = serial_no?.trim() ?? '';
    return currentSerial == uniGasSerialNumber;
  }

  bool get isSelectedBankCashInHand {
    final type = _selectedbankcashname?['type']
        ?.toString()
        .trim()
        .toLowerCase()
        .replaceAll('-', ' ');
    return type == 'cash in hand';
  }

  // -------------------------------------------------------------------
  // Outstanding bills (UniGas-only "party outstanding" feature)
  // -------------------------------------------------------------------

  void removeOutstandingBillFromReceipt(Map<String, dynamic> bill) {
    final String billNo = bill["billno"]?.toString() ?? "";
    _commit(() {
      bills.removeWhere((b) => b.billNo == billNo && b.billName == "Agst Ref");
      _recalculateBillTotals();
      isVisibleBillHeading = bills.isNotEmpty;
    });
  }

  DateTime? _parseBillDate(String value) {
    if (value.isEmpty) return null;
    try {
      return DateTime.parse(value);
    } catch (_) {
      try {
        return DateFormat('d-MMM-yy').parse(value);
      } catch (_) {
        return null;
      }
    }
  }

  String getBillDueDate(dynamic bill) {
    final String dueDateStr = bill["duedate"]?.toString() ?? "";
    final DateTime? dueDate =
        _parseBillDate(dueDateStr) ??
        _parseBillDate(bill["billdate"]?.toString() ?? "");
    if (dueDate == null) return "";
    return DateFormat('yyyyMMdd').format(dueDate);
  }

  /// Returns `true` if the bill was added, `false` if it was already added
  /// (the widget shows "Bill already added" itself in that case, matching
  /// the original's `showAppMessage` call).
  bool addOutstandingBillToReceipt(Map<String, dynamic> bill) {
    final String billNo = bill["billno"]?.toString() ?? "";
    final double amount =
        double.tryParse(bill["outstanding"].toString())?.abs() ?? 0.0;

    if (billNo.isEmpty || amount <= 0) return false;

    final bool alreadyAdded = bills.any(
      (b) => b.billNo == billNo && b.billName == "Agst Ref",
    );
    if (alreadyAdded) return false;

    _commit(() {
      bills.add(
        Bills(
          billName: "Agst Ref",
          billAmount: amount,
          billNo: billNo,
          billDueDate: getBillDueDate(bill),
        ),
      );
      _recalculateBillTotals();
      isVisibleBillHeading = bills.isNotEmpty;

      if (_selectedbankcashname != null && !isSelectedBankCashInHand) {
        isPaymentModeVisible = true;
        isChequeVisible = true;
      }
    });
    return true;
  }

  Future<String?> fetchPartyOutstanding(String ledgerName) async {
    if (ledgerName.trim().isEmpty) return null;

    _commit(() {
      isOutstandingLoading = true;
      outstandingError = "";
      showOutstandingCard = true;
      openingOutstanding = 0.0;
      totalOutstanding = 0.0;
      outstandingBills = [];
      isOutstandingExpanded = false;
    });

    final int? ledgerMasterId = _partyLedgerMasterIdByName[ledgerName.trim()];
    if (ledgerMasterId == null) {
      _commit(() {
        outstandingError = "Unable to load outstanding";
        isOutstandingLoading = false;
      });
      return null;
    }

    String? error;
    try {
      final rawBills = await LedgerRepository.instance.outstandingBills(
        ledgerMasterId: ledgerMasterId,
      );

      List<Map<String, dynamic>> rawPendingBills = [];
      try {
        rawPendingBills = await VoucherEntryRepository.instance.pendingBills(
          ledgerMasterId: ledgerMasterId,
        );
      } catch (e) {
        // matches original: swallowed, logged only
      }

      final values = rawBills.map((row) {
        final date = row['date']?.toString();
        final dueDate = row['dueDate']?.toString();
        return <String, dynamic>{
          'billno': row['name'],
          'outstanding': parseMoneyField(row['finalBalance']),
          'billdate': date != null && date.isNotEmpty
              ? DateFormat('yyyyMMdd').format(DateTime.parse(date))
              : '',
          'duedate': dueDate != null && dueDate.isNotEmpty
              ? DateFormat('yyyyMMdd').format(DateTime.parse(dueDate))
              : '',
          'billtype': row['isAdvance'] == true ? 'Advance' : '',
        };
      }).toList();

      values.addAll(
        rawPendingBills.map((row) {
          final date = row['date']?.toString();
          final dueDate = row['dueDate']?.toString();
          return <String, dynamic>{
            'billno': row['billName'],
            'outstanding': parseMoneyField(row['amount']),
            'billdate': date != null && date.isNotEmpty
                ? DateFormat('yyyyMMdd').format(DateTime.parse(date))
                : '',
            'duedate': dueDate != null && dueDate.isNotEmpty
                ? DateFormat('yyyyMMdd').format(DateTime.parse(dueDate))
                : '',
            'billtype': 'Pending',
          };
        }),
      );

      double billsOutstanding = 0.0;
      for (var item in values) {
        billsOutstanding +=
            double.tryParse(item["outstanding"].toString()) ?? 0.0;
      }

      if (isUniGasSerial) {
        values.sort((a, b) {
          final int dateA = int.tryParse(a["billdate"].toString()) ?? 0;
          final int dateB = int.tryParse(b["billdate"].toString()) ?? 0;
          return dateB.compareTo(dateA);
        });
      }

      _commit(() {
        openingOutstanding = 0.0;
        outstandingBills = values;
        totalOutstanding = billsOutstanding;
        visibleOutstandingBillCount = 5;
      });
    } on ApiException catch (e) {
      error = e.message;
      _commit(() => outstandingError = e.message);
    } catch (e) {
      _commit(() => outstandingError = "Outstanding fetch failed");
    } finally {
      _commit(() => isOutstandingLoading = false);
    }
    return error;
  }

  void setVisibleOutstandingBillCount(int totalBills) {
    _commit(() {
      if (visibleOutstandingBillCount >= totalBills) {
        visibleOutstandingBillCount = 5;
      } else {
        visibleOutstandingBillCount += 5;
        if (visibleOutstandingBillCount > totalBills) {
          visibleOutstandingBillCount = totalBills;
        }
      }
    });
  }

  void toggleOutstandingExpanded() {
    _commit(() => isOutstandingExpanded = !isOutstandingExpanded);
  }

  // -------------------------------------------------------------------
  // Bill / cheque totals + delete
  // -------------------------------------------------------------------

  void _recalculateBillTotals() {
    totalBillAmount = bills.fold(0.0, (double previousAmount, Bills bill) {
      return previousAmount + bill.billAmount;
    });
    roundedtotalBillAmount = double.parse(
      totalBillAmount.toStringAsFixed(decimal!),
    );
  }

  void updateChequeAmount() {
    totalChequeAmount = cheque.fold(0.0, (
      double previousAmount,
      Cheque cheque,
    ) {
      return previousAmount + cheque.chequeAmount;
    });
    roundedtotalChequeAmount = double.parse(
      totalChequeAmount.toStringAsFixed(decimal!),
    );
  }

  /// Verbatim port of `_deleteBill`'s data-mutation half.
  void deleteBill(int index) {
    _commit(() {
      bills.removeAt(index);
      _recalculateBillTotals();

      if (bills.isEmpty) {
        isVisibleBillHeading = false;
        isChequeVisible = false;
        _selectedpaymentmode = paymentmode_data.isNotEmpty
            ? paymentmode_data.first
            : '';
        cheque.clear();
        updateChequeAmount();
        isVisibleChequeHeading = false;
        isPaymentModeVisible = false;
      } else {
        isVisibleBillHeading = true;
        if (_selectedbankcashname != null && isSelectedBankCashInHand) {
          isPaymentModeVisible = false;
          _selectedpaymentmode = paymentmode_data.isNotEmpty
              ? paymentmode_data.first
              : '';
          cheque.clear();
          updateChequeAmount();
          isVisibleChequeHeading = false;
          isChequeVisible = false;
        } else {
          if (bills.isNotEmpty) {
            if (cheque.isNotEmpty) {
              isPaymentModeVisible = true;
              isChequeVisible = true;
              isVisibleChequeHeading = true;
            } else {
              isPaymentModeVisible = true;
              _selectedpaymentmode = paymentmode_data.isNotEmpty
                  ? paymentmode_data.first
                  : '';
              cheque.clear();
              updateChequeAmount();
              isVisibleChequeHeading = false;
              isChequeVisible = true;
            }
          } else {
            isPaymentModeVisible = true;
            _selectedpaymentmode = paymentmode_data.isNotEmpty
                ? paymentmode_data.first
                : '';
            cheque.clear();
            updateChequeAmount();
            isVisibleChequeHeading = false;
            isChequeVisible = false;
          }
        }
      }
      if (roundedtotalBillAmount < roundedtotalChequeAmount) {
        cheque.clear();
        updateChequeAmount();
        isVisibleChequeHeading = false;
      }
    });
  }

  // -------------------------------------------------------------------
  // Add Bill dialog
  // -------------------------------------------------------------------

  bool isDuplicateOnAccountBill(String billName) {
    return billName == "On Account" &&
        bills.any((bill) => bill.billName == "On Account");
  }

  /// Verbatim port of `addBill()`'s data-mutation half. [dueDateString] is
  /// already resolved by the widget from `_billduedateController` (a
  /// days-from-now offset, same as the original). Returns whether a bill
  /// was actually added (mirrors the original's `if (billAmount.isNotEmpty)`
  /// guard) - the final `isSelectedBankCashInHand` reset always runs
  /// afterward regardless, matching the original running it unconditionally
  /// after (not inside) that guard.
  AddBillOutcome addBill({
    required String billAmountText,
    required String billName,
    required String billNo,
    required String dueDateString,
  }) {
    if (isDuplicateOnAccountBill(billName)) {
      return AddBillOutcome.duplicateOnAccount;
    }

    AddBillOutcome outcome = AddBillOutcome.notAdded;

    if (billAmountText.isNotEmpty) {
      double parsedAmount = double.parse(billAmountText.replaceAll(',', ''));
      final newBill = Bills(
        billName: billName,
        billAmount: parsedAmount,
        billNo: (billName == "New Ref" || billName == "Agst Ref")
            ? billNo
            : null,
        billDueDate: (billName == "New Ref" || billName == "Agst Ref")
            ? dueDateString
            : null,
      );

      _commit(() {
        bills.add(newBill);
        isVisibleBillHeading = bills.isNotEmpty;
        _recalculateBillTotals();
      });

      _commit(() {
        if (_selectedbankcashname != null && isSelectedBankCashInHand) {
          isPaymentModeVisible = false;
          _selectedpaymentmode = paymentmode_data.isNotEmpty
              ? paymentmode_data.first
              : '';
          cheque.clear();
          updateChequeAmount();
          isVisibleChequeHeading = false;
          isChequeVisible = false;
        } else {
          if (bills.isNotEmpty) {
            if (cheque.isNotEmpty) {
              isPaymentModeVisible = true;
              isChequeVisible = true;
              isVisibleChequeHeading = true;
            } else {
              isPaymentModeVisible = true;
              _selectedpaymentmode = paymentmode_data.isNotEmpty
                  ? paymentmode_data.first
                  : '';
              cheque.clear();
              updateChequeAmount();
              isVisibleChequeHeading = false;
              isChequeVisible = true;
            }
          } else {
            isPaymentModeVisible = true;
            _selectedpaymentmode = paymentmode_data.isNotEmpty
                ? paymentmode_data.first
                : '';
            cheque.clear();
            updateChequeAmount();
            isVisibleChequeHeading = false;
            isChequeVisible = false;
          }
        }
      });

      outcome = AddBillOutcome.added;
    }

    if (isSelectedBankCashInHand) {
      _commit(() {
        isPaymentModeVisible = false;
        _selectedpaymentmode = paymentmode_data.isNotEmpty
            ? paymentmode_data.first
            : '';
        cheque.clear();
        updateChequeAmount();
        isVisibleChequeHeading = false;
        isChequeVisible = false;
      });
    }

    return outcome;
  }

  // -------------------------------------------------------------------
  // Add Cheque/Instrument dialog
  // -------------------------------------------------------------------

  bool isInstNoRepeated(String instNo) {
    if (instNo.isEmpty) return false;
    for (var c in cheque) {
      if (c.instno == instNo) return true;
    }
    return false;
  }

  /// Verbatim port of `addCheque()`'s validation + data-mutation half. The
  /// widget's own `instNoController`/`instdate`/`selectedbankname`/
  /// `chequeAmountController` dialog fields are resolved to plain values
  /// before calling; on [AddChequeOutcome.added] the widget resets those
  /// same controllers back to their defaults itself (mirrors the original's
  /// second `setState` block, which only touches widget-local
  /// controllers/fields).
  AddChequeOutcome addCheque({
    required String instNo,
    required DateTime instDate,
    required String bankName,
    required String chequeAmountText,
    required dynamic paymentMode,
  }) {
    double parsedAmount = double.parse(chequeAmountText.replaceAll(',', ''));
    String formattedAmount = parsedAmount.toStringAsFixed(decimal!);
    double formattedAmountDouble = double.parse(formattedAmount);
    String instDateString = DateFormat('yyyyMMdd').format(instDate);
    bool hasRepeatedInstNo = isInstNoRepeated(instNo);
    double remainingChequeAmount =
        roundedtotalBillAmount - roundedtotalChequeAmount;

    if (chequeAmountText.isNotEmpty &&
        roundedtotalChequeAmount <= roundedtotalBillAmount &&
        roundedtotalChequeAmount != roundedtotalBillAmount &&
        !hasRepeatedInstNo &&
        formattedAmountDouble <= roundedtotalBillAmount &&
        formattedAmountDouble <= remainingChequeAmount) {
      final newCheque = Cheque(
        instno: instNo,
        instdate: instDateString,
        bankname: bankName,
        chequeAmount: parsedAmount,
        paymentMode: paymentMode,
      );

      _commit(() {
        cheque.add(newCheque);
        isVisibleChequeHeading = cheque.isNotEmpty;
        updateChequeAmount();
      });
      return AddChequeOutcome.added;
    } else if (formattedAmountDouble > remainingChequeAmount) {
      return AddChequeOutcome.exceedsRemaining;
    } else if (hasRepeatedInstNo) {
      return AddChequeOutcome.duplicateInstNo;
    } else if (roundedtotalBillAmount < 0 || roundedtotalBillAmount == 0) {
      return AddChequeOutcome.noBillsYet;
    } else if (roundedtotalChequeAmount == roundedtotalBillAmount) {
      return AddChequeOutcome.chequeAlreadyFullyAllocated;
    } else if (formattedAmountDouble > roundedtotalBillAmount) {
      return AddChequeOutcome.exceedsTotal;
    }
    return AddChequeOutcome.exceedsTotal;
  }

  /// Verbatim port of the cheque row's `Dismissible.onDismissed` body.
  void deleteCheque(int index) {
    _commit(() {
      cheque.removeAt(index);
      updateChequeAmount();
      isVisibleChequeHeading = cheque.isNotEmpty;
    });
  }

  // -------------------------------------------------------------------
  // Simple field setters
  // -------------------------------------------------------------------

  void checkVchNoExistence(String vchNo) {
    _commit(() {
      if (vchNo.isEmpty) {
        errorMessageVchNo = 'Voucher No. cannot be empty';
      } else if (vchnos.contains(vchNo)) {
        errorMessageVchNo =
            'Voucher no: $vchNo against $_selectedvchtypename already exists';
      } else {
        errorMessageVchNo = '';
      }
    });
  }

  void setSelectedVchType(String value) {
    _commit(() => _selectedvchtypename = value);
  }

  void clearSelectedParty() {
    _commit(() {
      _selectedparty = "";
      showOutstandingCard = false;
      totalOutstanding = 0.0;
      outstandingError = "";
    });
  }

  void selectParty(String suggestion) {
    _commit(() => _selectedparty = suggestion);
  }

  void selectBankCashName(Map<String, String> suggestion) {
    _commit(() {
      _selectedbankcashname = suggestion;
      if (isSelectedBankCashInHand) {
        isPaymentModeVisible = false;
        _selectedpaymentmode = paymentmode_data.isNotEmpty
            ? paymentmode_data.first
            : '';
        cheque.clear();
        updateChequeAmount();
        isVisibleChequeHeading = false;
        isChequeVisible = false;
      } else {
        if (bills.isNotEmpty && cheque.isNotEmpty) {
          isPaymentModeVisible = true;
          isChequeVisible = true;
          isVisibleChequeHeading = true;
        } else {
          isPaymentModeVisible = true;
          _selectedpaymentmode = paymentmode_data.isNotEmpty
              ? paymentmode_data.first
              : '';
          cheque.clear();
          updateChequeAmount();
          isVisibleChequeHeading = false;
          isChequeVisible = bills.isNotEmpty;
        }
      }
    });
  }

  /// Verbatim port of the Payment Mode dropdown's `onChanged` body. Ported
  /// as a single commit (the original's mid-branch field writes for the
  /// `bills.isEmpty` case aren't wrapped in their own `setState` there,
  /// which in the original just meant that branch's UI update rides along
  /// on the next unrelated rebuild rather than not happening at all - not a
  /// data bug, so unifying into one commit here changes nothing observable
  /// about what ends up saved/rendered, only exactly which frame it paints
  /// on).
  bool setSelectedPaymentMode(String value) {
    final bool billsEmpty = bills.isEmpty;
    _commit(() {
      _selectedpaymentmode = value;
      if (billsEmpty) {
        isChequeVisible = false;
        cheque.clear();
        updateChequeAmount();
      } else {
        isChequeVisible = true;
      }
    });
    return billsEmpty;
  }

  void setReceiptDate(DateTime picked) {
    _commit(() {
      receiptdate = picked;
      receiptdatestring = _dateFormat.format(receiptdate);
      receiptdatetxt = formatlastsaledate(receiptdatestring);
    });
  }

  void setVchNoDateRange(DateTime start, DateTime end) {
    _commit(() {
      yearStartDate = start;
      yearEndDate = end;
    });
  }

  // -------------------------------------------------------------------
  // Network / data-loading methods (return result info, no context)
  // -------------------------------------------------------------------

  Future<String?> loadData() async {
    vchtypenamedata.clear();
    partydata.clear();
    bankcashname_data.clear();
    bills.clear();

    _recalculateBillTotals();

    cheque.clear();
    updateChequeAmount();

    _commit(() => _isLoading = true);

    String? error;
    try {
      final receiptData =
          await VoucherEntryDropdownsRepository.instance.receiptData();
      final partyLedgers = (receiptData['partyLedgers'] as List)
          .cast<Map<String, dynamic>>();
      final cashLedgers = (receiptData['cashLedgers'] as List)
          .cast<Map<String, dynamic>>();
      final receiptVoucherTypes = (receiptData['vchTypes'] as List)
          .cast<Map<String, dynamic>>();

      final currencies = await fetchAllPages(
        (page) =>
            _tallyApiClient.getForCompany('/currencies?page=$page&limit=100'),
      );
      final currencyRow = currencies.firstWhere(
        (c) =>
            (c['isoCurrencyCode'] as String?)?.toUpperCase() ==
            currencycode.toUpperCase(),
        orElse: () =>
            currencies.isNotEmpty ? currencies.first : const <String, dynamic>{},
      );

      String? tallyAutoCashLedgerName;
      final tallyCashLedgers = cashLedgers
          .where((l) => l['groupReservedName'] == 'CASH')
          .toList();
      if (tallyCashLedgers.length == 1) {
        tallyAutoCashLedgerName = tallyCashLedgers.first['name']?.toString();
      }

      String? voucherTypeToFetch;

      _commit(() {
        _partyLedgersRaw = partyLedgers;
        _partyLedgerMasterIdByName = {
          for (final l in partyLedgers)
            l['name'] as String: l['masterId'] as int,
        };
        _bankCashLedgerMasterIdByName = {
          for (final l in cashLedgers)
            l['name'] as String: l['masterId'] as int,
        };
        _voucherTypeMasterIdByName = {
          for (final vt in receiptVoucherTypes)
            vt['name'] as String: vt['masterId'] as int,
        };
        _currencyMasterId = currencyRow['masterId'] as int?;

        vchtypenamedata = receiptVoucherTypes
            .map((vt) => vt['name']?.toString().trim() ?? '')
            .where((name) => name.isNotEmpty)
            .toList();

        isVoucherTypeLocked = vchtypenamedata.length == 1;
        _selectedvchtypename =
            vchtypenamedata.isNotEmpty ? vchtypenamedata.first : '';
        voucherTypeToFetch = _selectedvchtypename;

        partydata = partyLedgers.map((l) => l['name'] as String).toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
        partydata.sort();

        bankcashname_data = cashLedgers.map((l) {
          final reservedName = l['groupReservedName'];
          return {
            'name': l['name'] as String,
            'type': reservedName == 'CASH' ? 'Cash-in-Hand' : 'Bank',
            'masterId': (l['masterId'] as int).toString(),
          };
        }).toList();

        _selectedbankcashname = null;
        isBankCashLedgerLocked = false;

        if (tallyAutoCashLedgerName != null &&
            tallyAutoCashLedgerName.isNotEmpty) {
          final matchedCashLedger = bankcashname_data.where(
            (ledger) => ledger['name'] == tallyAutoCashLedgerName,
          );
          if (matchedCashLedger.isNotEmpty) {
            _selectedbankcashname = matchedCashLedger.first;
          }
        }

        if (_selectedbankcashname != null) {
          if (isSelectedBankCashInHand) {
            isPaymentModeVisible = false;
            _selectedpaymentmode = paymentmode_data.isNotEmpty
                ? paymentmode_data.first
                : '';
            cheque.clear();
            updateChequeAmount();
            isVisibleChequeHeading = false;
            isChequeVisible = false;
          } else {
            if (bills.isNotEmpty) {
              if (cheque.isNotEmpty) {
                isPaymentModeVisible = true;
                isChequeVisible = true;
                isVisibleChequeHeading = true;
              } else {
                isPaymentModeVisible = true;
                _selectedpaymentmode = paymentmode_data.isNotEmpty
                    ? paymentmode_data.first
                    : '';
                cheque.clear();
                updateChequeAmount();
                isVisibleChequeHeading = false;
                isChequeVisible = true;
              }
            } else {
              isPaymentModeVisible = true;
              _selectedpaymentmode = paymentmode_data.isNotEmpty
                  ? paymentmode_data.first
                  : '';
              cheque.clear();
              updateChequeAmount();
              isVisibleChequeHeading = false;
              isChequeVisible = false;
            }
          }
        }
      });

      // Normalized to `await` here - see this file's doc-comment.
      if (voucherTypeToFetch != null && voucherTypeToFetch!.isNotEmpty) {
        await fetchVchNos(voucherTypeToFetch!);
      }
    } on ApiException catch (e) {
      error = e.message;
    } catch (e) {
      // matches original: swallowed, logged only
    }

    _commit(() => _isLoading = false);
    return error;
  }

  /// Verbatim port of `fetchvchnos`, minus the `_vchnoController.text`
  /// write - the widget sets it from [state]'s `vchNos` via
  /// `generateNextVchNo` itself after this resolves.
  Future<String?> fetchVchNos(String vchname) async {
    final String formattedStartDateVchNo =
        _startFromPref ?? _dateFormat.format(yearStartDate);
    final String formattedEndDateVchNo = DateFormat(
      'yyyy-MM-dd',
    ).format(yearEndDate);

    vchnos.clear();
    _commit(() => _isLoading = true);

    String? error;
    try {
      final int? voucherTypeMasterId = _voucherTypeMasterIdByName[vchname];

      if (voucherTypeMasterId != null) {
        final DateTime startDate = parseCompactDate(formattedStartDateVchNo);
        final String fromParam = DateFormat('yyyy-MM-dd').format(startDate);

        vchnos = await VoucherEntryRepository.instance.voucherNumbers(
          voucherTypeMasterId: voucherTypeMasterId,
          from: fromParam,
          to: formattedEndDateVchNo,
        );
      }

      _commit(() {
        vchnos.sort((a, b) {
          RegExp regExp = RegExp(r'(\d+)(?!.*\d)');
          int numA = int.tryParse(regExp.firstMatch(a)?.group(0) ?? '0') ?? 0;
          int numB = int.tryParse(regExp.firstMatch(b)?.group(0) ?? '0') ?? 0;
          return numA.compareTo(numB);
        });
      });
    } on ApiException catch (e) {
      vchnos.clear();
      error = e.message;
    } catch (e) {
      vchnos.clear();
    }

    _commit(() => _isLoading = false);
    return error;
  }

  /// Verbatim port of `generateNextVchNo`.
  String generateNextVchNo(List<String> vchnos) {
    if (vchnos.isEmpty) return "1";

    Map<String, List<Map<String, dynamic>>> patternGroups = {};

    for (String vch in vchnos) {
      List<RegExpMatch> matches = RegExp(r'\d+').allMatches(vch).toList();

      if (matches.isNotEmpty) {
        RegExpMatch selectedMatch = matches.last;

        if (matches.length > 1) {
          for (int i = matches.length - 1; i >= 0; i--) {
            String val = matches[i].group(0)!;
            int num = int.tryParse(val) ?? 0;

            if (!(val.length == 4 && num >= 2000 && num <= 2099)) {
              selectedMatch = matches[i];
              break;
            }
          }
        }

        String numberPart = selectedMatch.group(0)!;
        int number = int.tryParse(numberPart) ?? 0;

        String prefix = vch.substring(0, selectedMatch.start);
        String suffix = vch.substring(selectedMatch.end);

        String patternKey = prefix + "#" + suffix;

        patternGroups.putIfAbsent(patternKey, () => []);

        bool exists = patternGroups[patternKey]!.any(
          (e) => e["number"] == number,
        );

        if (!exists) {
          patternGroups[patternKey]!.add({
            "original": vch,
            "number": number,
            "length": numberPart.length,
          });
        }
      }
    }

    if (patternGroups.isEmpty) {
      return vchnos.last + "1";
    }

    String selectedPattern = patternGroups.entries
        .reduce((a, b) => a.value.length > b.value.length ? a : b)
        .key;

    List<Map<String, dynamic>> selectedList = patternGroups[selectedPattern]!;

    List<int> numbers = selectedList.map((e) => e["number"] as int).toList();
    numbers = numbers.toSet().toList();
    numbers.sort();

    int length = selectedList.first["length"];

    int expected = numbers.first;
    int nextNumber = numbers.last + 1;

    for (int num in numbers) {
      if (num != expected) {
        nextNumber = expected;
        break;
      }
      expected++;
    }

    String newNumber = nextNumber.toString().padLeft(length, '0');

    List<String> parts = selectedPattern.split("#");
    String prefix = parts[0];
    String suffix = parts[1];

    return prefix + newNumber + suffix;
  }

  /// Verbatim port of `saveEntry()`'s payload-building/submit logic, minus
  /// the pre-save validation (party/bank-cash/receiver-name checks, which
  /// read `context` via `showAppMessage` - the widget performs those itself
  /// before calling this) and minus the trailing `showReceiptVoucherDialog`
  /// call (pure UI - the widget does that on success).
  Future<String?> saveEntry({
    required String narration,
    required String vchno,
  }) async {
    _commit(() => _isLoading = true);

    final int? partyLedgerMasterId = _partyLedgerMasterIdByName[_selectedparty];
    final int? bankCashLedgerMasterId =
        _bankCashLedgerMasterIdByName[_selectedbankcashname?['name']];
    final int? voucherTypeMasterId =
        _voucherTypeMasterIdByName[_selectedvchtypename];

    if (partyLedgerMasterId == null ||
        bankCashLedgerMasterId == null ||
        voucherTypeMasterId == null ||
        _currencyMasterId == null) {
      _commit(() => _isLoading = false);
      return 'Master data not loaded yet - please try again';
    }

    final String narrationValue = narration.trim();
    final String isoDate = DateFormat(
      'yyyy-MM-dd',
    ).format(parseCompactDate(receiptdatestring));

    double roundedAmount(double amount) =>
        double.parse(amount.toStringAsFixed(decimal!));

    final List<Map<String, dynamic>> nonOnAccountBills = bills
        .where((bill) => bill.billName != "On Account")
        .map((bill) {
          final Map<String, dynamic> billData = {
            "billType": bill.billName,
            "billName": bill.billNo ?? '',
            "amount": roundedAmount(bill.billAmount),
            "date": isoDate,
          };
          if (bill.billDueDate != null && bill.billDueDate!.isNotEmpty) {
            billData["dueDate"] = DateFormat(
              'yyyy-MM-dd',
            ).format(parseCompactDate(bill.billDueDate!));
          }
          return billData;
        })
        .toList();

    final List<Map<String, dynamic>> onAccountBills = bills
        .where((bill) => bill.billName == "On Account")
        .map(
          (bill) => <String, dynamic>{
            "billType": bill.billName,
            "billName": (bill.billNo?.isNotEmpty ?? false)
                ? bill.billNo!
                : "On Account",
            "amount": roundedAmount(bill.billAmount),
            "date": isoDate,
          },
        )
        .toList();

    final List<Map<String, dynamic>> allBillAllocations = [
      ...nonOnAccountBills,
      ...onAccountBills,
    ];

    final Map<String, dynamic> partyLedgerEntry = {
      "ledgerMasterId": partyLedgerMasterId,
      "amount": roundedAmount(totalBillAmount),
      "isDebit": false,
      "isPartyLedger": true,
      "billAllocations": allBillAllocations,
    };

    final List<Map<String, dynamic>> bankAllocations = isSelectedBankCashInHand
        ? const []
        : cheque.map((c) {
            final String transactionType = switch (c.paymentMode) {
              'ATM' => 'ATM',
              'Card' => 'CARD',
              _ => 'CHEQUE',
            };
            return <String, dynamic>{
              "date": isoDate,
              "instrumentDate": DateFormat(
                'yyyy-MM-dd',
              ).format(parseCompactDate(c.instdate ?? receiptdatestring)),
              "instrumentNumber": c.instno,
              "bankName": (c.bankname != null && c.bankname != "Not Applicable")
                  ? c.bankname!
                  : "N/A",
              "transactionType": transactionType,
              "amount": roundedAmount(c.chequeAmount),
              "partyLedgerMasterId": partyLedgerMasterId,
              "favouringLedgerMasterId": partyLedgerMasterId,
            };
          }).toList();

    final Map<String, dynamic> bankLedgerEntry = {
      "ledgerMasterId": bankCashLedgerMasterId,
      "amount": roundedAmount(totalBillAmount),
      "isDebit": true,
      "isPartyLedger": false,
      "bankAllocations": bankAllocations,
    };

    final Map<String, dynamic> body = {
      "voucherTypeMasterId": voucherTypeMasterId,
      "date": isoDate,
      "currencyMasterId": _currencyMasterId,
      "narration": narrationValue,
      "voucherNumber": vchno,
      "ledgerEntries": [partyLedgerEntry, bankLedgerEntry],
    };

    String? error;
    try {
      await VoucherEntryRepository.instance.create(body);
    } on ApiException catch (e) {
      error = e.message;
    } catch (e) {
      error = 'Could not reach the server. Please try again.';
    }

    _commit(() => _isLoading = false);
    return error;
  }

  /// Verbatim port of `showReceiptVoucherDialog`'s "No, Thanks" button's
  /// data-mutation half (the non-UniGas share-decline path - `generateVoucherPDF`
  /// already early-returns to the UniGas print path before this dialog is
  /// ever shown for a UniGas serial, so the `serial_no != uniGasSerialNumber`
  /// guards below are always true in practice, kept verbatim regardless).
  /// Deliberately does NOT clear `receiverNameController`/
  /// `receiverMobileController`/`receiverSignatureBytes` (widget-local) -
  /// unlike [resetAfterShare] below, matching a genuine asymmetry already
  /// present in the original (see this file's doc-comment).
  void declineShareReset() {
    _commit(() {
      _selectedparty = null;
      showOutstandingCard = false;
      totalOutstanding = 0.0;
      outstandingError = "";
      isChequeVisible = false;
      openingOutstanding = 0.0;
      outstandingBills.clear();

      receiptdate = DateTime.now();
      receiptdatestring = _dateFormat.format(receiptdate);
      receiptdatetxt = formatlastsaledate(receiptdatestring);

      if (serial_no != uniGasSerialNumber) {
        _selectedvchtypename = vchtypenamedata.isNotEmpty
            ? vchtypenamedata.first
            : '';
      }

      if (serial_no != uniGasSerialNumber) {
        _selectedbankcashname = null;
      }

      bills.clear();
      cheque.clear();
      updateChequeAmount();
      _recalculateBillTotals();

      isVisibleBillHeading = bills.isNotEmpty;
      isVisibleChequeHeading = cheque.isNotEmpty;
    });
  }

  /// Verbatim port of `_resetReceiptFormAfterShare`'s data-mutation half
  /// (shared by both the regular A4 receipt-voucher share flow and the
  /// UniGas print flow) - see [declineShareReset] for how this differs.
  void resetAfterShare() {
    _commit(() {
      _selectedparty = null;
      showOutstandingCard = false;
      totalOutstanding = 0.0;
      outstandingError = "";

      isChequeVisible = false;

      openingOutstanding = 0.0;
      outstandingBills.clear();

      receiptdate = DateTime.now();
      receiptdatestring = _dateFormat.format(receiptdate);
      receiptdatetxt = formatlastsaledate(receiptdatestring);

      if (serial_no != uniGasSerialNumber) {
        _selectedvchtypename = vchtypenamedata.isNotEmpty
            ? vchtypenamedata.first
            : '';
      }

      if (serial_no != uniGasSerialNumber) {
        _selectedbankcashname = null;
      }

      bills.clear();
      cheque.clear();
      updateChequeAmount();
      _recalculateBillTotals();

      isVisibleBillHeading = bills.isNotEmpty;
      isVisibleChequeHeading = cheque.isNotEmpty;
    });
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();

    company = prefs.getString('company_name');
    serial_no = prefs.getString('serial_no');
    token = prefs.getString('token') ?? '';
    currencycode = prefs.getString('currencycode') ?? 'AED';
    _startFromPref = prefs.getString('startfrom');

    bankname_data.sort((a, b) {
      if (a == 'Not Applicable') {
        return -1;
      } else if (b == 'Not Applicable') {
        return 1;
      } else {
        return a.compareTo(b);
      }
    });

    decimal = prefs.getInt('decimalplace') ?? 2;

    paymentmode_data.add("ATM");
    paymentmode_data.add("Card");
    paymentmode_data.add('Cheque/DD');
    _selectedpaymentmode = paymentmode_data.isNotEmpty
        ? paymentmode_data.first
        : '';

    receiptdate = DateTime.now();
    receiptdatestring = _dateFormat.format(receiptdate);
    receiptdatetxt = formatlastsaledate(receiptdatestring);

    SecuritybtnAcessHolder = prefs.getString('secbtnaccess');

    String? name_nav = prefs.getString('name_nav');
    String? email_nav = prefs.getString('email_nav');
    if (email_nav != null && name_nav != null) {
      name = name_nav;
    }

    _commit(() {});

    final err = await loadData();
    _commit(() => _isInitialDataLoaded = true);
    _lastInitError = err;
  }

  /// The widget reads this once, right after the first frame where
  /// `isInitialDataLoaded` flips true, to show `loadData()`'s error (if
  /// any) via `showAppMessage` - mirrors the original calling
  /// `showAppMessage` directly inside `loadData()`.
  String? _lastInitError;
  String? consumeInitError() {
    final e = _lastInitError;
    _lastInitError = null;
    return e;
  }
}

final receiptRegistrationNotifierProvider = StateNotifierProvider.autoDispose<
    ReceiptRegistrationNotifier, ReceiptRegistrationState>(
  (ref) => ReceiptRegistrationNotifier(ref),
);
