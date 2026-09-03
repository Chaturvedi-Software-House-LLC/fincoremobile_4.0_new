import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../Items.dart' show formatlastsaledate;
import '../ModifyReceiptEntry.dart';
import '../api/api_exception.dart';
import '../api/currency_repository.dart';
import '../api/group_repository.dart';
import '../api/ledger_repository.dart';
import '../api/monthly_bucket_helper.dart' show parseCompactDate;
import '../api/voucher_entry_repository.dart';
import '../api/voucher_type_repository.dart';

/// Identifies one [ModifyReceiptEntry] screen instance for the `.family`
/// provider below - this screen (unlike `ReceiptRegistration.dart`'s
/// create-flow) is parameterized per existing voucher entry, so a single
/// global provider can't work. Equality/hashCode are based on [id] alone,
/// mirroring `modify_sales_entry_notifier.dart`'s `ModifySalesEntryArgs`
/// (the closest sibling *Modify* screen - read that file's doc-comment
/// first, this follows the exact same shape).
class ModifyReceiptEntryArgs {
  final String id;
  final Map<String, dynamic> data;

  const ModifyReceiptEntryArgs({required this.id, required this.data});

  @override
  bool operator ==(Object other) =>
      other is ModifyReceiptEntryArgs && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Riverpod migration of `ModifyReceiptEntry.dart`'s
/// `_ModifyReceiptEntryPageState`. Closest sibling by far is
/// `receipt_registration_notifier.dart` (this screen shares its `Bills`/
/// `Cheque` model shapes and accumulator logic nearly verbatim) - read that
/// file's doc-comment first. This is a *Modify* screen though (edits an
/// existing app-originated `VoucherEntry` rather than creating one), so it
/// deviates structurally in several places documented below - the same kind
/// of deviations `modify_sales_entry_notifier.dart` already documents
/// relative to its own create-flow sibling `sales_registration_notifier.dart`.
///
/// Structural deviations from `receipt_registration_notifier.dart`:
/// - No UniGas "party outstanding bills" feature at all (no
///   `fetchPartyOutstanding`/`outstandingBills`/`showOutstandingCard`/etc.) -
///   confirmed via a whole-file grep before assuming otherwise (zero matches
///   for `outstanding`/`Outstanding`/`receiverName`/`receiverMobile`/
///   `receiverSignature` in the pre-migration source). `isUniGasSerial` is
///   only ever called here as the free top-level function from
///   `constants.dart` (`isUniGasSerial(serial_no)`), not as a notifier
///   getter - it only gates the receipt-date field (locked, can't be
///   changed) in this screen, so there's no notifier-side equivalent to
///   port; the widget calls the free function directly with `_s.serialNo`.
/// - `loadData()` fetches master lists directly (`LedgerRepository.
///   listLedgers()`/`listAllLedgers()`, `GroupRepository.listAll()`,
///   `VoucherTypeRepository.byReservedName('RECEIPT')`,
///   `CurrencyRepository.listAll()`) and classifies bank/cash ledgers by
///   `reservedName` (`{'CASH', 'BANK', 'BANK_OD'}`) client-side, rather than
///   the sibling's single `VoucherEntryDropdownsRepository.receiptData()`
///   bundle call - a pre-existing difference in this screen's own
///   pre-migration (already-tally-api-ported) code, not something
///   introduced by this migration; mirrors `modify_sales_entry_notifier.dart`'s
///   identical deviation from `sales_registration_notifier.dart`.
/// - `loadData()` additionally prefills every field of the *existing*
///   voucher entry being edited from `data` (a `VoucherEntryRepository` row)
///   - the party ledger (the `ledgerEntries` row with `isPartyLedger ==
///   true`), the bank/cash ledger (the row with `isPartyLedger == false`),
///   every bill allocation off the party ledger's `billAllocations`, and
///   every cheque/instrument off the bank ledger's `bankAllocations`. There
///   is no equivalent step in `receipt_registration_notifier.dart`.
/// - `updateEntry(id, ...)` (`VoucherEntryRepository.update`) replaces
///   `saveEntry()`/`create()` - otherwise builds the exact same
///   `ledgerEntries` payload shape (party ledger entry with
///   `billAllocations`, bank/cash ledger entry with `bankAllocations`),
///   always rebuilt wholesale from the current form state, matching the
///   server's delete-then-reinsert semantics for `ledgerEntries`.
/// - `fetchVchNos` excludes this entry's own original voucher number (one
///   occurrence) from the returned pool, via [_originalVoucherNumber] set
///   by `loadData()` - so re-saving this entry with its number unchanged
///   never flags itself as a duplicate. This entry's own voucher-number
///   *text* is never regenerated/auto-filled the way
///   `ReceiptRegistration.dart` does (`isVchEditable` - a widget-local,
///   always-false, half-wired toggle whose "edit" button `onPressed` is a
///   no-op in the pre-migration code - kept exactly that way, not fixed,
///   same treatment `modify_sales_entry_notifier.dart` gives its own
///   identical `isVchEditable`) - `loadData()` seeds it once from
///   `data['voucherNumber']` and it's otherwise left alone.
/// - The post-update `data = Map<String, dynamic>.from(updated)` reassignment
///   in the pre-migration `updateEntry()` is dropped - nothing in the
///   pre-migration source ever reads `data` again after that point (verified
///   via a whole-file grep for `data[`), so it was a dead write with no
///   observable effect; [ModifyReceiptEntryArgs.data] is `final` and not
///   re-assignable in the new shape anyway.
/// - `Cheque` here (unlike `receipt_registration_notifier.dart`'s simpler
///   one) also carries `date`/`paymentFavouring`/`bankPartyName` fields -
///   all three are write-only in the pre-migration source (set at
///   construction in `addCheque()`/`loadData()`, never read anywhere else -
///   confirmed via grep), kept verbatim rather than pruned since trimming a
///   shared model class's fields is out of scope for this migration.
///
/// Dialog-composition-only fields that stay widget-local (unmigrated, same
/// treatment as `TextEditingController`s, per this migration's established
/// convention): `_selectedbill`, `isVisibleDueDate`, `isVisibleBillNo`,
/// `billsdata`, `_billsFormkey`, `billAmountController`, `billNoController`,
/// `_billduedateController` (the "Add Bill" dialog) and `selectedbankname`,
/// `_banknameController`, `instNoController`, `instdate`/`instdatestring`/
/// `instdatetxt`, `instDateController`, `chequeAmountController`,
/// `_chequedetailsFormkey` (the "Add Cheque/Instrument" dialog) -
/// `isVchEditable` (always false - see above) stays widget-local too.
///
/// Dead fields/methods dropped rather than ported (confirmed unreferenced
/// outside their own declaration/assignment via a whole-file grep):
/// `isDashEnable`, `isRolesVisible`, `isUserVisible`, `isUserEnable`,
/// `isRolesEnable`, `isVisibleNoUserFound`, `hostname`, `company_lowercase`,
/// `username`, `HttpURL`, `token`, `name`, `email` (all write-only - `name`/
/// `email` are fed from nav args but never read anywhere in this screen,
/// confirmed via a targeted grep before dropping, unlike some siblings where
/// one of the pair turned out live), `SecuritybtnAcessHolder` (its only
/// reader fed the now-dead `isRolesVisible`/`isUserVisible` pair, so the
/// whole chain is dead - same situation `modify_sales_entry_notifier.dart`
/// documents for its own `SecuritybtnAcessHolder`), `jsonEntryData` (zero
/// matches at all in this screen - already fully absent, not merely dead),
/// `billduedate`/`billduedatestring`/`billduedatetxt` (only ever
/// read/written inside the block-commented-out `_selectbilldueDate` below),
/// `_confirmBillDeletion` (declared, zero call sites - the actual bill
/// delete swipe-to-dismiss in `build()` calls `_deleteBill` directly with no
/// confirmation dialog, exactly like `modify_sales_entry_notifier.dart`'s
/// identical `_confirmLedgerDeletion`/`_confirmItemDeletion` situation).
///
/// Also deleted outright (not ported): a block-commented dead
/// `_selectbilldueDate` (~30 lines), a block-commented dead
/// `_showBillsDetailsPopup` (superseded by the live `showModalBottomSheet`
/// version immediately below it), and a block-commented dead
/// `_showChequeDetailsPopup` (superseded the same way) - all three were
/// already fully commented out in the source, confirmed dead by inspection
/// (their live, call-site-reachable replacements sit immediately after each
/// one), not merely assumed dead from proximity - the same three-way
/// situation `receipt_registration_notifier.dart` documents for its own
/// sibling screen.
class ModifyReceiptEntryState {
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

  final bool isLoading;
  final bool isInitialDataLoaded;

  final String? company;
  final String? serialNo;
  final String currencyCode;
  final int decimal;

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

  /// One-shot values `loadData()` resolves for this existing entry - the
  /// widget seeds its own widget-local `TextEditingController`s from these
  /// exactly once, the first time [isInitialDataLoaded] flips `true`, same
  /// "seed once, guarded by a bool" pattern `modify_sales_entry_notifier.dart`
  /// already uses for `initialVoucherNumber`/`initialNarration`. Party/
  /// bank-cash/voucher-type/payment-mode don't need an equivalent one-shot
  /// field - they're plain dropdown/`TypeAheadField` selections that read
  /// straight off [selectedParty]/[selectedBankCashName]/
  /// [selectedVchTypeName]/[selectedPaymentMode] on every rebuild (the
  /// `TypeAheadField` builders already sync their own controller text from
  /// the selected value when empty, exactly as `ReceiptRegistration.dart`'s
  /// already do).
  final String initialVoucherNumber;
  final String initialNarration;

  const ModifyReceiptEntryState({
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
    required this.isLoading,
    required this.isInitialDataLoaded,
    required this.company,
    required this.serialNo,
    required this.currencyCode,
    required this.decimal,
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
    required this.initialVoucherNumber,
    required this.initialNarration,
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

class ModifyReceiptEntryNotifier
    extends StateNotifier<ModifyReceiptEntryState> {
  final Ref _ref;
  final ModifyReceiptEntryArgs _args;

  ModifyReceiptEntryNotifier(this._ref, this._args)
    : super(
        ModifyReceiptEntryState(
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
          isLoading: true,
          isInitialDataLoaded: false,
          company: '',
          serialNo: '',
          currencyCode: '',
          decimal: 2,
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
          initialVoucherNumber: '',
          initialNarration: '',
        ),
      ) {
    _init();
  }

  void _commit(void Function() fn) {
    fn();
    state = _snapshot();
  }

  ModifyReceiptEntryState _snapshot() => ModifyReceiptEntryState(
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
    isLoading: _isLoading,
    isInitialDataLoaded: _isInitialDataLoaded,
    company: company,
    serialNo: serial_no,
    currencyCode: currencycode,
    decimal: decimal ?? 2,
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
    initialVoucherNumber: _initialVoucherNumber,
    initialNarration: _initialNarration,
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

  // tally-api's voucher-entries endpoint is masterId-keyed
  // (voucherTypeMasterId/ledgerMasterId/currencyMasterId), unlike legacy's
  // update endpoint which took names straight from these same dropdowns -
  // resolved from the maps loadData() populates. Mirrors
  // receipt_registration_notifier.dart's fields of the same name.
  Map<String, int> _partyLedgerMasterIdByName = {};
  Map<String, int> _bankCashLedgerMasterIdByName = {};
  Map<String, int> _voucherTypeMasterIdByName = {};
  int? _currencyMasterId;

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

  bool _isLoading = true;
  bool _isInitialDataLoaded = false;

  String? company = '';
  String? serial_no = '';
  String currencycode = '';
  int? decimal = 2;

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

  /// This entry's own voucher number as loaded by `loadData()` - excluded
  /// from [vchnos] in `fetchVchNos()` so re-saving with the number
  /// unchanged never flags itself as a duplicate.
  String? _originalVoucherNumber;

  // One-shot values `loadData()` resolves for the widget to seed its own
  // controllers from - see [ModifyReceiptEntryState]'s doc-comment.
  String _initialVoucherNumber = '';
  String _initialNarration = '';

  bool get isSelectedBankCashInHand {
    final type = _selectedbankcashname?['type']
        ?.toString()
        .trim()
        .toLowerCase()
        .replaceAll('-', ' ');
    return type == 'cash in hand';
  }

  double _entryAmount(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString().replaceAll(',', '')) ?? 0;
  }

  List<dynamic> _entryList(dynamic value) {
    if (value is List) return value;
    return const [];
  }

  // tally-api's voucher-entry rows tag each ledger entry with an explicit
  // `isPartyLedger` boolean (unlike legacy's Tally-XML shape, which had to
  // be inferred from LEDGERNAME/BILLALLOCATIONS.LIST/ISPARTYLEDGER
  // fallbacks) - the party ledger entry is always the one carrying
  // billAllocations, so both finders key off that single flag now.
  Map<String, dynamic>? _findBillLedgerEntry(List<dynamic> ledgerEntries) {
    for (final entry in ledgerEntries) {
      if (entry is Map<String, dynamic> && entry['isPartyLedger'] == true) {
        return entry;
      }
    }
    return null;
  }

  Map<String, dynamic>? _findBankLedgerEntry(List<dynamic> ledgerEntries) {
    for (final entry in ledgerEntries) {
      if (entry is Map<String, dynamic> && entry['isPartyLedger'] == false) {
        return entry;
      }
    }
    return null;
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
        isPaymentModeVisible = false;
        isVisibleChequeHeading = false;
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
  /// days-from-now offset, same as `ReceiptRegistration.dart`). Returns
  /// whether a bill was actually added (mirrors the original's
  /// `if (billAmount.isNotEmpty)` guard).
  AddBillOutcome addBill({
    required String billAmountText,
    required String billName,
    required String billNo,
    required String dueDateString,
  }) {
    if (isDuplicateOnAccountBill(billName)) {
      return AddBillOutcome.duplicateOnAccount;
    }

    if (billAmountText.isEmpty) {
      return AddBillOutcome.notAdded;
    }

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

    return AddBillOutcome.added;
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

  /// Verbatim port of `addCheque()`'s validation + data-mutation half.
  /// `paymentFavouring`/`bankPartyName` are always this receipt's own party
  /// ledger name (matching the pre-migration source - see this file's
  /// doc-comment on why those two `Cheque` fields are write-only); `date` is
  /// always the receipt's own date.
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
        date: receiptdatestring,
        paymentFavouring: _selectedparty,
        bankPartyName: _selectedparty,
        instno: instNo,
        instdate: instDateString,
        bankname: bankName,
        chequeAmount: formattedAmountDouble,
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
    _commit(() => _selectedparty = "");
  }

  /// Verbatim port of the Bank/Cash `TypeAheadField`'s own clear button
  /// (`onTap`) - this screen has one, unlike `ReceiptRegistration.dart`'s
  /// otherwise-identical bank/cash field.
  void clearSelectedBankCashName() {
    _commit(() {
      _selectedbankcashname = null;
      isPaymentModeVisible = false;
      isChequeVisible = false;
      cheque.clear();
      updateChequeAmount();
    });
  }

  void selectParty(String suggestion) {
    _commit(() => _selectedparty = suggestion);
  }

  /// Verbatim port of the Bank/Cash `TypeAheadField`'s `onSelected` body.
  void selectBankCashName(Map<String, String> suggestion) {
    _commit(() {
      _selectedbankcashname = suggestion;
      if (_selectedbankcashname != null && isSelectedBankCashInHand) {
        isPaymentModeVisible = false;
        _selectedpaymentmode = paymentmode_data.isNotEmpty
            ? paymentmode_data.first
            : '';
        cheque.clear();
        updateChequeAmount();
        isVisibleChequeHeading = false;
        isChequeVisible = false;
      } else if (bills.isNotEmpty) {
        isPaymentModeVisible = true;
        isChequeVisible = true;
        isVisibleChequeHeading = cheque.isNotEmpty;
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
    });
  }

  /// Verbatim port of the Payment Mode dropdown's `onChanged` body. Returns
  /// whether `bills` was empty (mirrors `receipt_registration_notifier.dart`'s
  /// identically-shaped method) - the widget shows "At least add 1 bill" and
  /// resets its own cheque-dialog controllers in that case.
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
        // Both branches of the original's `bills.isNotEmpty` check are
        // identical (a pre-existing quirk, not introduced here) - kept
        // verbatim rather than "fixed" into a single branch.
        if (bills.isNotEmpty) {
          isPaymentModeVisible = true;
          _selectedpaymentmode = paymentmode_data.isNotEmpty
              ? paymentmode_data.first
              : '';
          cheque.clear();
          updateChequeAmount();
          isVisibleChequeHeading = false;
          isChequeVisible = true;
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

  /// Replaces legacy's `GET /api/entry/getReceiptData/:company/:serial` -
  /// master lists fetched individually via the shared repositories
  /// (`GroupRepository`/`VoucherTypeRepository`/`CurrencyRepository`/
  /// `LedgerRepository`), same classification approach as
  /// `receipt_registration_notifier.dart`'s `loadData()`, but going through
  /// those repos directly instead of the `VoucherEntryDropdownsRepository`
  /// bundle - see this file's doc-comment for why. The entry being edited
  /// itself is NOT re-fetched here - it arrives via [ModifyReceiptEntryArgs.data]
  /// (server-shaped, same as `VoucherEntryRepository.getById`/`listAll`).
  Future<String?> loadData() async {
    vchtypenamedata.clear();
    partydata.clear();
    bankcashname_data.clear();
    bills.clear();
    _recalculateBillTotals();
    cheque.clear();
    updateChequeAmount();

    _commit(() => _isLoading = true);

    final data = _args.data;
    String? error;

    try {
      final partyLedgers = await LedgerRepository.instance.listLedgers();

      final groups = await GroupRepository.instance.listAll();
      // Same reservedName set tally-api's own dashboard-reports uses to
      // classify a ledger as "bank/cash" (see dashboard-reports.service.ts)
      // - Tally's fixed reserved group names, not user-editable group names.
      const bankCashReservedNames = {'CASH', 'BANK', 'BANK_OD'};
      final groupReservedNameById = <int, String?>{
        for (final g in groups)
          g['masterId'] as int: g['reservedName'] as String?,
      };
      final bankCashGroupIds = groupReservedNameById.entries
          .where((e) => bankCashReservedNames.contains(e.value))
          .map((e) => e.key)
          .toSet();

      final allLedgers = await LedgerRepository.instance.listAllLedgers();
      final bankCashLedgers = allLedgers
          .where((l) => bankCashGroupIds.contains(l['groupMasterId'] as int?))
          .toList();

      // Tally's own reserved voucher-type name for the Receipt family.
      final receiptVoucherTypes = await VoucherTypeRepository.instance
          .byReservedName('RECEIPT');

      final currencies = await CurrencyRepository.instance.listAll();
      final currencyRow = currencies.firstWhere(
        (c) =>
            (c['isoCurrencyCode'] as String?)?.toUpperCase() ==
            currencycode.toUpperCase(),
        orElse: () =>
            currencies.isNotEmpty ? currencies.first : const <String, dynamic>{},
      );

      final List<dynamic> ledgerEntries = data['ledgerEntries'] is List
          ? data['ledgerEntries'] as List<dynamic>
          : const [];
      final Map<String, dynamic>? partyLedgerEntry = _findBillLedgerEntry(
        ledgerEntries,
      );

      String oldvchname = data['voucherTypeName']?.toString() ?? '';
      String oldpartyledger =
          partyLedgerEntry?['ledgerName']?.toString() ?? '';
      String oldvchno = data['voucherNumber']?.toString() ?? '';
      String oldnarration = data['narration']?.toString() ?? '';

      _commit(() {
        _partyLedgerMasterIdByName = {
          for (final l in partyLedgers)
            l['name'] as String: l['masterId'] as int,
        };
        _bankCashLedgerMasterIdByName = {
          for (final l in bankCashLedgers)
            l['name'] as String: l['masterId'] as int,
        };
        _voucherTypeMasterIdByName = {
          for (final vt in receiptVoucherTypes)
            vt['name'] as String: vt['masterId'] as int,
        };
        _currencyMasterId = currencyRow['masterId'] as int?;

        vchtypenamedata = receiptVoucherTypes
            .map((vt) => vt['name'] as String)
            .toList();

        _selectedvchtypename =
            oldvchname.isNotEmpty && vchtypenamedata.contains(oldvchname)
            ? oldvchname
            : (vchtypenamedata.isNotEmpty ? vchtypenamedata.first : '');

        partydata = partyLedgers.map((l) => l['name'] as String).toList();
        partydata.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
        _selectedparty = oldpartyledger;

        _initialNarration = oldnarration;

        _initialVoucherNumber = oldvchno;
        _originalVoucherNumber = oldvchno;

        bankcashname_data = bankCashLedgers.map((l) {
          final reservedName =
              groupReservedNameById[l['groupMasterId'] as int?];
          return {
            'name': l['name'] as String,
            'type': reservedName == 'CASH' ? 'Cash-in-Hand' : 'Bank',
          };
        }).toList();

        final bankLedgerEntry = _findBankLedgerEntry(ledgerEntries);
        final ledgerNameToMatch = bankLedgerEntry?['ledgerName']?.toString();

        Map<String, String>? selectedLedger;
        if (ledgerNameToMatch != null && ledgerNameToMatch.isNotEmpty) {
          try {
            selectedLedger = bankcashname_data.firstWhere(
              (item) => item['name'] == ledgerNameToMatch,
            );
          } catch (_) {
            selectedLedger = null;
          }
        }

        if (selectedLedger != null) {
          _selectedbankcashname = selectedLedger;
        }

        try {
          final billAllocations = _entryList(
            partyLedgerEntry?['billAllocations'],
          );

          for (final allocation in billAllocations) {
            if (allocation is! Map) continue;

            final billType = allocation['billType']?.toString() ?? 'Unknown';
            final billAmount = _entryAmount(allocation['amount']).abs();

            String? billNo;
            String? billDueDate;

            if (billType != 'On Account') {
              billNo = allocation['billName']?.toString();
              final dueDateIso = allocation['dueDate']?.toString();
              if (dueDateIso != null && dueDateIso.isNotEmpty) {
                billDueDate = DateFormat(
                  'yyyyMMdd',
                ).format(DateTime.parse(dueDateIso));
              }
            }

            bills.add(
              Bills(
                billName: billType,
                billAmount: billAmount,
                billNo: billNo,
                billDueDate: billDueDate,
              ),
            );
          }
        } catch (_) {
          // matches original: swallowed, logged only
        }

        try {
          final bankAllocations = _entryList(
            bankLedgerEntry?['bankAllocations'],
          );

          for (final allocation in bankAllocations) {
            if (allocation is! Map) continue;

            final instno = allocation['instrumentNumber']?.toString() ?? '';
            final instDateIso = allocation['instrumentDate']?.toString();
            final instdate = instDateIso != null && instDateIso.isNotEmpty
                ? DateFormat('yyyyMMdd').format(DateTime.parse(instDateIso))
                : null;
            // "N/A" is what saveEntry()/updateEntry() send for "Not
            // Applicable" (ATM/Card - see entryBankAllocationRowSchema's
            // required bankName) - mapped back to the bankname_data option
            // it originally came from.
            final rawBankname = allocation['bankName']?.toString();
            final bankname = rawBankname == 'N/A'
                ? 'Not Applicable'
                : rawBankname;
            final chequeAmount = _entryAmount(allocation['amount']).abs();
            // TRANSACTIONTYPE enum values map back onto paymentmode_data's
            // exact strings (ATM/Card/Cheque-DD) - the reverse of
            // updateEntry()'s own mapping.
            final transactionType =
                allocation['transactionType']?.toString() ?? '';
            final paymentMode = switch (transactionType) {
              'ATM' => 'ATM',
              'CARD' => 'Card',
              _ => 'Cheque/DD',
            };
            final dateIso = allocation['date']?.toString();
            final date = dateIso != null && dateIso.isNotEmpty
                ? DateFormat('yyyyMMdd').format(DateTime.parse(dateIso))
                : receiptdatestring;

            // paymentFavouring/bankPartyName are always the party ledger's
            // own name (see this file's doc-comment) - the new schema
            // stores only a `favouringLedgerMasterId`/`partyLedgerMasterId`
            // (always the same party ledger as this receipt's own party),
            // not a separate display name, so `_selectedparty` is used
            // directly rather than resolving those ids back to a name.
            cheque.add(
              Cheque(
                date: date,
                paymentFavouring: _selectedparty,
                bankPartyName: _selectedparty,
                instno: instno,
                instdate: instdate,
                bankname: bankname,
                chequeAmount: chequeAmount,
                paymentMode: paymentMode,
              ),
            );
          }
        } catch (_) {
          // matches original: swallowed, logged only
        }

        if (cheque.isNotEmpty) {
          _selectedpaymentmode = cheque.last.paymentMode;
        } else {
          _selectedpaymentmode = paymentmode_data.isNotEmpty
              ? paymentmode_data.first
              : '';
          isPaymentModeVisible = false;
        }

        if (bills.isEmpty) {
          isVisibleBillHeading = false;
          isPaymentModeVisible = false;
        } else {
          isVisibleBillHeading = true;
        }

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
            isChequeVisible = true;
          }
        }

        _recalculateBillTotals();
        updateChequeAmount();
      });

      // Normalized to `await` here (the pre-migration source fires this
      // off without awaiting, inside the same `setState` block) - the same
      // normalization `receipt_registration_notifier.dart`'s own
      // `loadData()` applies for the identical reason (avoids a load-order
      // race with `isLoading` flipping false before the voucher-number
      // fetch resolves).
      if (_selectedvchtypename.isNotEmpty) {
        await fetchVchNos(_selectedvchtypename);
      }
    } on ApiException catch (e) {
      error = e.message;
    } catch (_) {
      // matches original: swallowed, logged only
    }

    _commit(() => _isLoading = false);
    return error;
  }

  /// Backed by tally-api's `GET .../voucher-entries/voucher-numbers` (see
  /// `VoucherEntryRepository.voucherNumbers`'s doc-comment). This entry's
  /// own [_originalVoucherNumber] is excluded (one occurrence) so re-saving
  /// with it unchanged never flags itself as a duplicate.
  Future<String?> fetchVchNos(String vchname) async {
    vchnos.clear();
    _commit(() => _isLoading = true);

    String? error;
    try {
      final int? voucherTypeMasterId = _voucherTypeMasterIdByName[vchname];

      if (voucherTypeMasterId != null) {
        final DateTime startDate = parseCompactDate(
          _dateFormat.format(yearStartDate),
        );
        final DateTime endDate = parseCompactDate(
          _dateFormat.format(yearEndDate),
        );
        final String fromParam = DateFormat('yyyy-MM-dd').format(startDate);
        final String toParam = DateFormat('yyyy-MM-dd').format(endDate);

        final fetched = await VoucherEntryRepository.instance.voucherNumbers(
          voucherTypeMasterId: voucherTypeMasterId,
          from: fromParam,
          to: toParam,
        );

        vchnos = List<String>.from(fetched);
        final ownNumber = _originalVoucherNumber;
        if (ownNumber != null) {
          final ownIndex = vchnos.indexOf(ownNumber);
          if (ownIndex != -1) vchnos.removeAt(ownIndex);
        }
      }
    } on ApiException catch (e) {
      vchnos.clear();
      error = e.message;
    } catch (_) {
      vchnos.clear();
    }

    _commit(() => _isLoading = false);
    return error;
  }

  /// Replaces legacy's `POST /api/entry/updateEntry/:company/:serial` with
  /// `VoucherEntryRepository.update` - builds the same `ledgerEntries`
  /// payload shape `receipt_registration_notifier.dart`'s `saveEntry()`
  /// builds for create, always rebuilt wholesale from the current form
  /// state on every update (matching the server's delete-then-reinsert
  /// semantics). Minus the pre-save validation (party/bank-cash/empty-bills
  /// checks, which read `context` via `showAppMessage` - the widget performs
  /// those itself before calling this) and minus the trailing
  /// `showReceiptVoucherUpdatedDialog` call (pure UI - the widget does that
  /// on success). Returns `null` on success, an error message otherwise.
  Future<String?> updateEntry(
    String voucherEntryId, {
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
    final String vchnoValue = vchno;
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
      "voucherNumber": vchnoValue,
      "ledgerEntries": [partyLedgerEntry, bankLedgerEntry],
    };

    String? error;
    try {
      await VoucherEntryRepository.instance.update(voucherEntryId, body);
    } on ApiException catch (e) {
      error = e.message;
    } catch (e) {
      error = 'Could not reach the server. Please try again.';
    }

    _commit(() => _isLoading = false);
    return error;
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();

    company = prefs.getString('company_name');
    serial_no = prefs.getString('serial_no');
    currencycode = prefs.getString('currencycode') ?? 'AED';
    decimal = prefs.getInt('decimalplace') ?? 2;

    bankname_data.sort((a, b) {
      if (a == 'Not Applicable') {
        return -1;
      } else if (b == 'Not Applicable') {
        return 1;
      } else {
        return a.compareTo(b);
      }
    });

    paymentmode_data.add("ATM");
    paymentmode_data.add("Card");
    paymentmode_data.add('Cheque/DD');
    _selectedpaymentmode = paymentmode_data.isNotEmpty
        ? paymentmode_data.first
        : '';

    // tally-api's voucher entry stores `date` as an ISO date (YYYY-MM-DD),
    // unlike legacy's Tally-XML DATE field - DateTime.parse accepts both.
    final String? initialDateIso = _args.data['date'] as String?;
    receiptdate = initialDateIso != null
        ? DateTime.parse(initialDateIso)
        : DateTime.now();
    receiptdatestring = _dateFormat.format(receiptdate);
    receiptdatetxt = formatlastsaledate(receiptdatestring);

    _commit(() {});

    final err = await loadData();
    _commit(() => _isInitialDataLoaded = true);
    _lastInitError = err;
  }

  /// The widget reads this once, right after the first frame where
  /// `isInitialDataLoaded` flips true, to show `loadData()`'s error (if
  /// any) via `showAppMessage`.
  String? _lastInitError;
  String? consumeInitError() {
    final e = _lastInitError;
    _lastInitError = null;
    return e;
  }
}

final modifyReceiptEntryNotifierProvider = StateNotifierProvider.autoDispose
    .family<
      ModifyReceiptEntryNotifier,
      ModifyReceiptEntryState,
      ModifyReceiptEntryArgs
    >((ref, args) => ModifyReceiptEntryNotifier(ref, args));
