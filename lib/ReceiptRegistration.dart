import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:FincoreGo/Items.dart';
import 'package:FincoreGo/PendingReceiptEntry.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'constants.dart';
import 'package:FincoreGo/widgets/app_bottom_nav.dart';
import 'widgets/entry_widgets.dart';
import 'widgets/signature_capture.dart';
import 'providers/receipt_registration_notifier.dart';

class ReceiptRegistration extends ConsumerStatefulWidget {
  const ReceiptRegistration({Key? key}) : super(key: key);
  @override
  ConsumerState<ReceiptRegistration> createState() =>
      _ReceiptRegistrationPageState();
}

class Bills {
  final String billName;
  final double billAmount;
  final String? billNo;
  final String? billDueDate;

  Bills({
    required this.billName,
    required this.billAmount,
    required this.billNo,
    required this.billDueDate,
  });
}

class Cheque {
  final String instno;
  final String? instdate;
  final String? bankname;
  final double chequeAmount;
  final String paymentMode;

  Cheque({
    required this.instno,
    required this.instdate,
    required this.bankname,
    required this.chequeAmount,
    required this.paymentMode,
  });
}

class _ReceiptRegistrationPageState extends ConsumerState<ReceiptRegistration>
    with TickerProviderStateMixin {
  ReceiptRegistrationNotifier get _notifier =>
      ref.read(receiptRegistrationNotifierProvider.notifier);
  ReceiptRegistrationState get _s =>
      ref.read(receiptRegistrationNotifierProvider);

  // ---- read-only aliases onto the notifier's state ----------------------
  // Same names/types the original State class declared, so every method
  // body below (dialogs, PDF builders, validation) stays textually
  // unchanged. Each one re-reads the current snapshot, so there is no
  // stale-read window the way a cached copy would have.
  int? get decimal => _s.decimal;
  String get currencycode => _s.currencyCode;
  String? get company => _s.company;
  String? get serial_no => _s.serialNo;
  String? get SecuritybtnAcessHolder => _s.secBtnAccessHolder;
  String get name => _s.name;
  DateTime get receiptdate => _s.receiptDate;
  String get receiptdatestring => _s.receiptDateString;
  String get receiptdatetxt => _s.receiptDateText;
  DateTime get yearStartDate => _s.yearStartDate;
  DateTime get yearEndDate => _s.yearEndDate;
  List<String> get vchtypenamedata => _s.vchTypeNameData;
  List<String> get partydata => _s.partyData;
  List<Map<String, String>> get bankcashname_data => _s.bankCashNameData;
  List<String> get paymentmode_data => _s.paymentModeData;
  List<String> get bankname_data => _s.bankNameData;
  List<String> get vchnos => _s.vchNos;
  List<Bills> get bills => _s.bills;
  List<Cheque> get cheque => _s.cheque;
  double get totalBillAmount => _s.totalBillAmount;
  double get roundedtotalBillAmount => _s.roundedTotalBillAmount;
  double get roundedtotalChequeAmount => _s.roundedTotalChequeAmount;
  bool get isPaymentModeVisible => _s.isPaymentModeVisible;
  bool get isChequeVisible => _s.isChequeVisible;
  bool get isVoucherTypeLocked => _s.isVoucherTypeLocked;
  bool get isBankCashLedgerLocked => _s.isBankCashLedgerLocked;
  String get errorMessageVchNo => _s.errorMessageVchNo;
  String get _selectedvchtypename => _s.selectedVchTypeName;
  dynamic get _selectedparty => _s.selectedParty;
  Map<String, String>? get _selectedbankcashname => _s.selectedBankCashName;
  dynamic get _selectedpaymentmode => _s.selectedPaymentMode;
  bool get isOutstandingLoading => _s.isOutstandingLoading;
  String get outstandingError => _s.outstandingError;
  double get totalOutstanding => _s.totalOutstanding;
  List<dynamic> get outstandingBills => _s.outstandingBills;
  bool get showOutstandingCard => _s.showOutstandingCard;
  bool get isOutstandingExpanded => _s.isOutstandingExpanded;
  int get visibleOutstandingBillCount => _s.visibleOutstandingBillCount;

  // Raw prefs, kept widget-side purely for the two reads that never went
  // through a state field of their own: `formatAmountVoucher`'s own
  // `decimalplace` lookup and `_generateUniGasReceiptPDF`'s
  // `spectra_allocations` vehicle lookup. Loaded in `initState`; both reads
  // are null-tolerant, so an early frame can't crash on it.
  SharedPreferences? prefs;

  // Party-wise outstanding bills is a Spectra/UniGas-only feature (per the
  // legacy backend) - `showOutstandingBills` itself stays a manual
  // kill-switch (never actually flipped in this codebase), so every call
  // site below additionally requires `isUniGasSerial` rather than folding
  // the check into this flag's own value (which can't see `serial_no` yet
  // at field-declaration time, before the notifier loads it from prefs).
  bool get showOutstandingBills => _notifier.showOutstandingBills;

  bool isVchEditable = false; // state variable

  TextEditingController _partyController = TextEditingController();

  // UniGas only - Receiver Information shown on the printed Receipt.
  // Same fields as the Delivery Note's Receiver Information (minus EID#) -
  // Name is mandatory before saving, Mobile/Signature are optional.
  final TextEditingController receiverNameController = TextEditingController();
  final TextEditingController receiverMobileController = TextEditingController();
  Uint8List? receiverSignatureBytes;

  TextEditingController _bankcashnameController = TextEditingController();

  final TextEditingController _vchnoController = TextEditingController();

  TextEditingController billNoController = TextEditingController();

  TextEditingController _banknameController = TextEditingController();

  bool get isSelectedBankCashInHand => _notifier.isSelectedBankCashInHand;

  bool get isVanSalesUser =>
      serial_no != null && vanSalesSerialNo.contains(serial_no);

  late final TextEditingController controller_narration =
      TextEditingController();

  final FocusNode _textFieldFocusNodeNarration = FocusNode();

  bool get isUniGasSerial => _notifier.isUniGasSerial;

  /// Thin wrapper - the notifier owns the bill removal/total recompute, the
  /// widget only pushes the new total into `controller_totalamt`.
  void removeOutstandingBillFromReceipt(Map<String, dynamic> bill) {
    _notifier.removeOutstandingBillFromReceipt(bill);
    controller_totalamt.text = _s.formattedTotalBillAmount;

    // showAppMessage(context, "Bill removed from receipt");
  }

  /// Thin wrapper - `false` back from the notifier means the bill was
  /// already on the receipt, which is the original's `showAppMessage`
  /// branch (it also returns `false` for the "no bill no / non-positive
  /// amount" early return, where the original silently returned - hence
  /// the extra guard here so that case still shows nothing).
  void addOutstandingBillToReceipt(Map<String, dynamic> bill) {
    final String billNo = bill["billno"]?.toString() ?? "";
    final double amount =
        double.tryParse(bill["outstanding"].toString())?.abs() ?? 0.0;
    if (billNo.isEmpty || amount <= 0) return;

    final bool added = _notifier.addOutstandingBillToReceipt(bill);
    if (!added) {
      showAppMessage(context, "Bill already added", isError: false);
      return;
    }
    controller_totalamt.text = _s.formattedTotalBillAmount;

    // showAppMessage(context, "Bill added to receipt", isError: false);
  }

  /// Thin wrapper around the notifier's `fetchPartyOutstanding` - keeps the
  /// original's leading `closeKeyboard(context)` on the widget side (the
  /// notifier surfaces its own `ApiException` message into
  /// `outstandingError`, which `buildOutstandingCard` already renders, so
  /// there is nothing to `showAppMessage` here).
  Future<void> fetchPartyOutstanding(String ledgerName) async {
    closeKeyboard(context);
    await _notifier.fetchPartyOutstanding(ledgerName);
  }

  Widget buildOutstandingCard() {
    if (!showOutstandingBills || !isUniGasSerial) {
      return const SizedBox.shrink();
    }
    if (!showOutstandingCard) return const SizedBox.shrink();

    final int totalBills = outstandingBills.length;
    final int visibleCount = visibleOutstandingBillCount > totalBills
        ? totalBills
        : visibleOutstandingBillCount;

    final visibleBills = outstandingBills.take(visibleCount).toList();

    String balanceType;

    if (totalOutstanding < 0) {
      balanceType = "DR";
    } else if (totalOutstanding > 0) {
      balanceType = "CR";
    } else {
      balanceType = "";
    }
    double displayBalance = totalOutstanding.abs();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Theme.of(context).dividerColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                _notifier.toggleOutstandingExpanded();
              },
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Container(
                      height: 42,
                      width: 42,
                      decoration: BoxDecoration(
                        color: app_color.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.account_balance_wallet_outlined,
                        color: app_color,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),

                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Outstanding Balance",
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 3),

                          if (isOutstandingLoading)
                            Text(
                              "Loading outstanding...",
                              style: GoogleFonts.poppins(fontSize: 13),
                            )
                          else if (outstandingError.isNotEmpty)
                            Text(
                              outstandingError,
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                color: Colors.redAccent,
                              ),
                            )
                          else
                            Row(
                              children: [
                                _currencyValueWidget(
                                  formatAmountVoucher(
                                    displayBalance.toString(),
                                  ),
                                  GoogleFonts.poppins(
                                    fontSize: 18,
                                    color: balanceType == "DR"
                                        ? Colors.redAccent
                                        : balanceType == "CR"
                                        ? Colors.green
                                        : Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),

                                if (balanceType.isNotEmpty) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 7,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: balanceType == "DR"
                                          ? Colors.redAccent.withOpacity(0.12)
                                          : Colors.green.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      balanceType,
                                      style: GoogleFonts.poppins(
                                        fontSize: 11,
                                        color: balanceType == "DR"
                                            ? Colors.redAccent
                                            : Colors.green,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),

                          if (!isOutstandingLoading && outstandingError.isEmpty)
                            Text(
                              "$totalBills pending bill(s)",
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),

                    if (isOutstandingLoading)
                      SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator.adaptive(
                          strokeWidth: 2,
                          //color: app_color,
                        ),
                      )
                    else
                      Icon(
                        isOutstandingExpanded
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                  ],
                ),
              ),
            ),

            if (isOutstandingExpanded &&
                !isOutstandingLoading &&
                outstandingError.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                child: Column(
                  children: [
                    Divider(color: Theme.of(context).dividerColor),

                    if (outstandingBills.isEmpty)
                      Text(
                        "No outstanding bills found",
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      )
                    else
                      Column(
                        children: [
                          Column(
                            children: visibleBills.map((bill) {
                              final double billOutstanding =
                                  double.tryParse(
                                    bill["outstanding"].toString(),
                                  ) ??
                                  0.0;

                              final String billType = billOutstanding < 0
                                  ? "DR"
                                  : "CR";

                              final double billDisplayAmount = billOutstanding
                                  .abs();

                              final bool isAdded = bills.any(
                                (b) =>
                                    b.billNo == bill["billno"]?.toString() &&
                                    b.billName == "Agst Ref",
                              );

                              return GestureDetector(
                                onTap: () {
                                  closeKeyboard(context);

                                  if (!isAdded) {
                                    addOutstandingBillToReceipt(
                                      Map<String, dynamic>.from(bill),
                                    );
                                  }
                                  if (isAdded) {
                                    removeOutstandingBillFromReceipt(
                                      Map<String, dynamic>.from(bill),
                                    );
                                  }
                                },
                                /*onLongPress: () {
                                  if (isAdded) {
                                    removeOutstandingBillFromReceipt(Map<String, dynamic>.from(bill));
                                  }
                                },*/
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 220),
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: isAdded
                                        ? app_color.withOpacity(0.04)
                                        : (Theme.of(context).brightness ==
                                                  Brightness.dark
                                              ? Theme.of(context)
                                                    .colorScheme
                                                    .surfaceContainerHighest
                                              : Colors.grey.shade50),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isAdded
                                          ? app_color.withOpacity(0.55)
                                          : Colors.grey.shade200,
                                      width: isAdded ? 1.3 : 1,
                                    ),
                                  ),
                                  child: LayoutBuilder(
                                    builder: (context, constraints) {
                                      return Row(
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Flexible(
                                                      child: Text(
                                                        bill["billno"]
                                                                ?.toString() ??
                                                            "No Bill No",
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style:
                                                            GoogleFonts.poppins(
                                                              fontSize: 13,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                            ),
                                                      ),
                                                    ),

                                                    if (isAdded) ...[
                                                      const SizedBox(width: 6),
                                                      Container(
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 7,
                                                              vertical: 2,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color: app_color
                                                              .withOpacity(
                                                                0.10,
                                                              ),
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                20,
                                                              ),
                                                        ),
                                                        child: Text(
                                                          "Added",
                                                          style:
                                                              GoogleFonts.poppins(
                                                                fontSize: 9,
                                                                color:
                                                                    app_color,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700,
                                                              ),
                                                        ),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  "${bill["billtype"] ?? ""} • ${formatlastsaledate(bill["billdate"].toString())}",
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: GoogleFonts.poppins(
                                                    fontSize: 11,
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .onSurfaceVariant,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),

                                          const SizedBox(width: 8),

                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              _currencyValueWidget(
                                                formatAmountVoucher(
                                                  billDisplayAmount.toString(),
                                                ),
                                                GoogleFonts.poppins(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w700,
                                                  color: billType == "DR"
                                                      ? Colors.redAccent
                                                      : Colors.green,
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 7,
                                                      vertical: 2,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: billType == "DR"
                                                      ? Colors.redAccent
                                                            .withOpacity(0.10)
                                                      : Colors.green
                                                            .withOpacity(0.10),
                                                  borderRadius:
                                                      BorderRadius.circular(20),
                                                ),
                                                child: Text(
                                                  billType,
                                                  style: GoogleFonts.poppins(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w700,
                                                    color: billType == "DR"
                                                        ? Colors.redAccent
                                                        : Colors.green,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ),
                              );
                            }).toList(),
                          ),

                          if (totalBills > 5)
                            TextButton.icon(
                              onPressed: () {
                                _notifier.setVisibleOutstandingBillCount(
                                  totalBills,
                                );
                              },
                              icon: Icon(
                                visibleOutstandingBillCount >= totalBills
                                    ? Icons.keyboard_arrow_up
                                    : Icons.keyboard_arrow_down,
                                size: 18,
                                color: app_color,
                              ),
                              label: Text(
                                visibleOutstandingBillCount >= totalBills
                                    ? "View Less"
                                    : "View More ($visibleCount/$totalBills)",
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  color: app_color,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Thin wrapper - the notifier owns the whole delete/recompute/
  /// payment-mode-visibility cascade; the widget pushes the new total into
  /// `controller_totalamt` and, when that emptied the bill list, resets the
  /// Add-Cheque dialog's own controllers/fields back to their defaults
  /// (exactly the subset of the original's `bills.isEmpty` branch that
  /// touched widget-local state).
  void _deleteBill(int index) {
    _notifier.deleteBill(index);
    controller_totalamt.text = _s.formattedTotalBillAmount;

    if (bills.isEmpty) {
      instNoController.clear();
      selectedbankname = bankname_data.first;
      _banknameController.text = selectedbankname;
      chequeAmountController.clear();
      instdate = DateTime.now();
      instdatestring = _dateFormat.format(instdate);
      instdatetxt = formatlastsaledate(instdatestring);
      instDateController.text = instdatetxt;
    }
  }

  final _formKey = GlobalKey<FormState>();

  // Dialog-composition-only (Add Cheque/Instrument sheet) - see the
  // notifier's doc-comment.
  String selectedbankname = '';

  /// Thin wrapper around the notifier's own `checkVchNoExistence`.
  void checkVchNoExistence(String vchNo) {
    _notifier.checkVchNoExistence(vchNo);
  }

  GlobalKey<FormState> _billsFormkey = GlobalKey<FormState>();

  GlobalKey<FormState> _chequedetailsFormkey = GlobalKey<FormState>();

  // Dialog-composition-only (Add Bill sheet).
  List<String> billsdata = ['On Account', 'New Ref', 'Agst Ref'];

  bool isVisibleDueDate = false, isVisibleBillNo = false;

  // Dialog-composition-only: the Add-Cheque sheet's instrument date, plus
  // the bill-due-date pair only `_selectbilldueDate` (zero call sites,
  // deliberately left in place) ever touches.
  String instdatestring = '',
      instdatetxt = '',
      billduedatestring = '',
      billduedatetxt = '';

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // Dialog-composition-only (Add Bill sheet).
  dynamic _selectedbill;

  late final TextEditingController controller_totalamt =
      TextEditingController();

  String formatAmountVoucher(String amount) {
    int? decimal = prefs?.getInt('decimalplace') ?? 2;

    String amount_string = "";
    if (amount == "null" || amount.isEmpty) {
      amount = "0";
    }
    double amount_double = double.parse(amount);

    NumberFormat formatter = NumberFormat.decimalPatternDigits(
      locale: 'en_us',
      decimalDigits: decimal,
    );
    String formattedAmount = formatter.format(amount_double);

    return formattedAmount;
  }

  void showReceiptVoucherDialog(BuildContext context) {
    // UniGas prints directly - no "created successfully / Share" dialog.
    if (isUniGasSerial) {
      generateVoucherPDF();
      return;
    }

    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: "ReceiptVoucher",
      barrierColor: Colors.black.withValues(alpha: 0.35),
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: MediaQuery.of(context).size.width * 0.85,
              padding: const EdgeInsets.all(20.0),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(28),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.green, width: 4.0),
                    ),
                    child: const Icon(
                      Icons.done,
                      size: 40,
                      color: Colors.green,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Do you want to share the receipt voucher?',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(fontSize: 18.0),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Receipt Voucher Created Successfully',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: 16.0,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 12,
                    runSpacing: 12,
                    children: <Widget>[
                      ElevatedButton.icon(
                        onPressed: () {
                          // Drop focus first - otherwise clearing
                          // _partyController's text below while the Party
                          // TypeAheadField still has focus makes it re-run
                          // its suggestionsCallback('') (which matches
                          // everything) and pop its suggestions overlay
                          // back open right after reset. A bare unfocus()
                          // leaves the scope's "last focused descendant"
                          // pointer intact, so popping this dialog can still
                          // silently hand focus straight back to that field
                          // - requesting a disposable FocusNode instead
                          // fully severs that link.
                          FocusScope.of(context).requestFocus(FocusNode());

                          _notifier.declineShareReset();

                          _partyController.clear();
                          controller_narration.clear();
                          _textFieldFocusNodeNarration.unfocus();
                          _dateController.text = receiptdatetxt;
                          fetchvchnos(_selectedvchtypename);
                          if (serial_no != uniGasSerialNumber) {
                            _bankcashnameController.text = "";
                          }
                          controller_totalamt.text =
                              _s.formattedTotalBillAmount;

                          Navigator.pop(context);
                        },
                        icon: const Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: Colors.white,
                        ),
                        label: Text(
                          'No, Thanks',
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                      ),

                      ElevatedButton.icon(
                        onPressed: () async {
                          Navigator.pop(context);
                          await generateVoucherPDF();
                        },
                        icon: const Icon(
                          Icons.share_rounded,
                          size: 18,
                          color: Colors.white,
                        ),
                        label: Text(
                          'Share',
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: app_color,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                      ),
                    ],
                  ),

                  /*Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      ElevatedButton.icon(
                        onPressed: () {
                          setState(() {
                            _selectedparty = null;
                            _partyController.clear();
                            showOutstandingCard = false;
                            totalOutstanding = 0.0;
                            outstandingError = "";

                            isChequeVisible = false;

                            openingOutstanding = 0.0;
                            outstandingBills.clear();

                            controller_narration.clear();
                            _textFieldFocusNodeNarration.unfocus();

                            receiptdate = DateTime.now();
                            receiptdatestring = _dateFormat.format(receiptdate);
                            receiptdatetxt = formatlastsaledate(receiptdatestring);
                            _dateController.text = receiptdatetxt;

                            _selectedvchtypename = vchtypenamedata.isNotEmpty ? vchtypenamedata.first : '';
                            fetchvchnos(_selectedvchtypename);

                            // _selectedparty = partydata.first;
                            // _partyController.text = _selectedparty;

                            _selectedbankcashname = null;
                            _bankcashnameController.text =
                            _selectedbankcashname != null
                                ? _selectedbankcashname!['name']!
                                : "";

                            bills.clear();
                            cheque.clear();

                            updateChequeAmount();

                            totalBillAmount = bills.fold(
                              0.0,
                                  (double previousAmount, Bills bill) {
                                return previousAmount + bill.billAmount;
                              },
                            );

                            roundedtotalBillAmount = double.parse(
                              totalBillAmount.toStringAsFixed(decimal!),
                            );

                            NumberFormat formatter = NumberFormat(
                              '#,##0.${'0' * decimal!}',
                              'en_US',
                            );

                            String formattedtotal =
                            formatter.format(roundedtotalBillAmount);

                            controller_totalamt.text = formattedtotal.toString();

                            isVisibleBillHeading = bills.isNotEmpty;
                            isVisibleChequeHeading = cheque.isNotEmpty;
                          });

                          Navigator.pop(context);
                        },
                        icon: const Icon(
                          Icons.close_rounded,
                          size: 20,
                          color: Colors.white,
                        ),
                        label: Text(
                          'No, Thanks',
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 22, vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          elevation: 4,
                          shadowColor: Colors.redAccent.withOpacity(0.3),
                        ),
                      ),
                      const SizedBox(width: 20),
                      ElevatedButton.icon(
                        onPressed: () async {
                          Navigator.pop(context);
                          await generateVoucherPDF();
                        },
                        icon: const Icon(
                          Icons.share_rounded,
                          size: 20,
                          color: Colors.white,
                        ),
                        label: Text(
                          'Share',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: app_color,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 22, vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          elevation: 4,
                          shadowColor: app_color.withOpacity(0.3),
                        ),
                      ),
                    ],
                  ),*/
                ],
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return Transform.scale(
          scale: Curves.easeOutBack.transform(animation.value),
          child: Opacity(opacity: animation.value, child: child),
        );
      },
    );
  }

  String convertAmountToWords(num amount) {
    if (amount == null) return "Invalid input";

    List<String> units = [
      '',
      'One',
      'Two',
      'Three',
      'Four',
      'Five',
      'Six',
      'Seven',
      'Eight',
      'Nine',
    ];
    List<String> teens = [
      'Ten',
      'Eleven',
      'Twelve',
      'Thirteen',
      'Fourteen',
      'Fifteen',
      'Sixteen',
      'Seventeen',
      'Eighteen',
      'Nineteen',
    ];
    List<String> tens = [
      '',
      '',
      'Twenty',
      'Thirty',
      'Forty',
      'Fifty',
      'Sixty',
      'Seventy',
      'Eighty',
      'Ninety',
    ];

    NumberFormat formatter = NumberFormat.decimalPatternDigits(
      locale: 'en_us',
      decimalDigits: decimal,
    );
    String formattedAmount = formatter.format(amount);

    int integerPart = amount.toInt();
    String decimalPartStr = formattedAmount.split('.')[1] ?? "0";
    int decimalPart = int.parse(decimalPartStr);

    String currencyWords = getCurrencyWords(currencycode);
    String fractionalUnit = getFractionalUnit(currencycode);

    String integerWords = convertIntegerToWords(
      units,
      teens,
      tens,
      integerPart,
    );
    String result = '$currencyWords $integerWords';

    if (decimalPart > 0) {
      String decimalWords = convertIntegerToWords(
        units,
        teens,
        tens,
        decimalPart,
      );
      result += ' and $decimalWords $fractionalUnit Only';
    } else {
      result += ' Only';
    }

    return result;
  }

  String getCurrencyWords(String currencyCode) {
    switch (currencyCode.toLowerCase()) {
      case 'aed':
        return 'UAE dirham';
      case 'usd':
        return 'US dollar';
      case 'inr':
        return 'Indian rupee';
      case 'pkr':
        return 'Pakistani rupee';
      case 'eur':
        return 'Euro';
      case 'lkr':
        return 'Sri Lankan rupee';
      case 'sar':
        return 'Saudi riyal';
      case 'omr':
        return 'Omani rial';
      case 'bhd':
        return 'Bahraini dinar';
      case 'qar':
        return 'Qatari riyal';
      case 'kwd':
        return 'Kuwaiti dinar';
      case 'sle':
        return 'Sierra Leonean leone';
      default:
        return '';
    }
  }

  String getFractionalUnit(String currencyCode) {
    switch (currencyCode.toLowerCase()) {
      case 'aed':
        return 'fils';
      case 'usd':
        return 'cents';
      case 'inr':
        return 'paise';
      case 'pkr':
        return 'paisa';
      case 'eur':
        return 'cents';
      case 'lkr':
        return 'cents';
      case 'sar':
        return 'halala';
      case 'omr':
        return 'baisa';
      case 'bhd':
        return 'fils';
      case 'qar':
        return 'dirham';
      case 'kwd':
        return 'fils';
      case 'sle':
        return 'cents';
      default:
        return '';
    }
  }

  String convertIntegerToWords(
    List<String> units,
    List<String> teens,
    List<String> tens,
    int amount,
  ) {
    if (amount == 0) return 'zero';

    String words = '';

    if (amount >= 1000000000) {
      words +=
          '${convertIntegerToWords(units, teens, tens, amount ~/ 1000000000)} billion ';
      amount %= 1000000000;
    }

    if (amount >= 1000000) {
      words +=
          '${convertIntegerToWords(units, teens, tens, amount ~/ 1000000)} million ';
      amount %= 1000000;
    }

    if (amount >= 1000) {
      words +=
          '${convertIntegerToWords(units, teens, tens, amount ~/ 1000)} thousand ';
      amount %= 1000;
    }

    if (amount >= 100) {
      words += '${units[amount ~/ 100]} hundred ';
      amount %= 100;
    }

    if (amount >= 10 && amount < 20) {
      words += '${teens[amount - 10]}';
      return words;
    } else if (amount >= 20) {
      words += '${tens[amount ~/ 10]}';
      if (amount % 10 != 0) words += ' ';
      amount %= 10;
    }
    if (amount > 0) {
      words += '${units[amount]}';
    }
    return words.trim();
  }

  Future<void> generateVoucherPDF() async {
    if (isUniGasSerial) {
      await _generateUniGasReceiptPDF();
      return;
    }

    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        build: (pw.Context context) {
          return pw.Stack(
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  // Tax Invoice Heading
                  pw.Header(
                    level: 0,
                    decoration: pw.BoxDecoration(
                      border: pw.Border(bottom: pw.BorderSide.none),
                    ),

                    child: pw.Center(
                      child: pw.Column(
                        children: [
                          pw.Text(
                            company!,
                            textAlign: pw.TextAlign.center,
                            style: pw.TextStyle(fontSize: 18),
                          ),
                          pw.SizedBox(height: 20),
                          pw.Text(
                            'Receipt Voucher',
                            textAlign: pw.TextAlign.center,
                            style: pw.TextStyle(fontSize: 18),
                          ),
                        ],
                      ),
                    ),
                  ),

                  pw.SizedBox(height: 10),

                  pw.Table(
                    border: pw.TableBorder(
                      horizontalInside: pw.BorderSide.none,
                      verticalInside: pw.BorderSide.none,
                      bottom: pw.BorderSide.none,
                    ),
                    children: [
                      pw.TableRow(
                        children: [
                          pw.Expanded(
                            flex: 5,
                            child: pw.Container(
                              padding: pw.EdgeInsets.fromLTRB(5, 5, 5, 5),
                              alignment: pw.Alignment.centerLeft,

                              child: pw.Row(
                                children: [
                                  pw.Text(
                                    'No. : ',
                                    style: pw.TextStyle(fontSize: 12),
                                  ),

                                  pw.Text(
                                    _vchnoController.text,
                                    style: pw.TextStyle(fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          pw.Expanded(
                            flex: 5,
                            child: pw.Container(
                              padding: pw.EdgeInsets.fromLTRB(5, 5, 5, 5),
                              alignment: pw.Alignment.centerRight,

                              child: pw.Row(
                                mainAxisAlignment: pw.MainAxisAlignment.end,
                                crossAxisAlignment: pw.CrossAxisAlignment.end,
                                children: [
                                  pw.Text(
                                    'Dated : ',
                                    style: pw.TextStyle(fontSize: 12),
                                  ),

                                  pw.Text(
                                    formatlastsaledate(receiptdatestring),
                                    style: pw.TextStyle(fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  pw.SizedBox(height: 5),

                  pw.Table(
                    border: pw.TableBorder(
                      horizontalInside: pw.BorderSide.none,
                      verticalInside: pw.BorderSide.none,
                      bottom: pw.BorderSide.none,
                    ),
                    children: [
                      pw.TableRow(
                        children: [
                          pw.Expanded(
                            flex: 5,
                            child: pw.Container(
                              padding: pw.EdgeInsets.fromLTRB(5, 5, 5, 15),
                              alignment: pw.Alignment.centerLeft,

                              child: pw.Row(
                                children: [
                                  pw.Text(
                                    'Remarks : ',
                                    style: pw.TextStyle(fontSize: 12),
                                  ),

                                  pw.Text(
                                    controller_narration.text,
                                    style: pw.TextStyle(fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  pw.SizedBox(height: 20),

                  pw.Table(
                    border: pw.TableBorder(
                      horizontalInside: pw.BorderSide(
                        color: PdfColor.fromHex('#050400'),
                      ),
                      verticalInside: pw.BorderSide(
                        color: PdfColor.fromHex('#050400'),
                      ),
                      bottom: pw.BorderSide(color: PdfColor.fromHex('#050400')),
                      top: pw.BorderSide(color: PdfColor.fromHex('#050400')),
                    ),
                    children: [
                      pw.TableRow(
                        children: [
                          pw.Expanded(
                            flex: 7,
                            child: pw.Container(
                              padding: pw.EdgeInsets.fromLTRB(10, 2, 5, 2),
                              alignment: pw.Alignment.centerLeft,

                              child: pw.Text(
                                'Particulars',
                                style: pw.TextStyle(fontSize: 11),
                              ),
                            ),
                          ),

                          pw.Expanded(
                            flex: 3,
                            child: pw.Container(
                              padding: pw.EdgeInsets.fromLTRB(5, 2, 10, 2),
                              alignment: pw.Alignment.centerRight,

                              child: pw.Text(
                                'Amount',
                                style: pw.TextStyle(fontSize: 11),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  pw.Table(
                    border: pw.TableBorder(
                      horizontalInside: pw.BorderSide.none,
                      verticalInside: pw.BorderSide(
                        color: PdfColor.fromHex('#050400'),
                      ),
                      bottom: pw.BorderSide.none,
                      top: pw.BorderSide.none,
                    ),
                    children: [
                      pw.TableRow(
                        children: [
                          pw.Expanded(
                            flex: 7,
                            child: pw.Container(
                              padding: pw.EdgeInsets.fromLTRB(5, 3, 5, 2),
                              alignment: pw.Alignment.centerLeft,

                              child: pw.Text(
                                'Account :',
                                style: pw.TextStyle(fontSize: 11),
                              ),
                            ),
                          ),

                          pw.Expanded(
                            flex: 3,
                            child: pw.Container(
                              padding: pw.EdgeInsets.fromLTRB(5, 2, 10, 2),
                              alignment: pw.Alignment.centerRight,

                              child: pw.Text(
                                '',
                                style: pw.TextStyle(fontSize: 11),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  pw.Table(
                    border: pw.TableBorder(
                      horizontalInside: pw.BorderSide.none,
                      verticalInside: pw.BorderSide(
                        color: PdfColor.fromHex('#050400'),
                      ),
                      bottom: pw.BorderSide.none,
                      top: pw.BorderSide.none,
                    ),
                    children: [
                      pw.TableRow(
                        children: [
                          pw.Expanded(
                            flex: 7,
                            child: pw.Container(
                              padding: pw.EdgeInsets.fromLTRB(15, 3, 5, 2),
                              alignment: pw.Alignment.centerLeft,

                              child: pw.Text(
                                _selectedparty,
                                style: pw.TextStyle(fontSize: 11),
                              ),
                            ),
                          ),

                          pw.Expanded(
                            flex: 3,
                            child: pw.Container(
                              padding: pw.EdgeInsets.fromLTRB(5, 2, 5, 2),
                              alignment: pw.Alignment.centerRight,

                              child: pw.Text(
                                formatAmountVoucher(
                                  roundedtotalBillAmount.toString(),
                                ),
                                style: pw.TextStyle(fontSize: 11),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  pw.Table(
                    border: pw.TableBorder(
                      horizontalInside: pw.BorderSide.none,
                      verticalInside: pw.BorderSide(
                        color: PdfColor.fromHex('#050400'),
                      ),
                      bottom: pw.BorderSide.none,
                      top: pw.BorderSide.none,
                    ),
                    children: [
                      for (var bill in bills.asMap().entries)
                        pw.TableRow(
                          children: [
                            pw.Expanded(
                              flex: 7,
                              child: pw.Container(
                                padding: pw.EdgeInsets.fromLTRB(20, 2, 10, 2),
                                alignment: pw.Alignment.centerLeft,

                                child: pw.Row(
                                  children: [
                                    pw.Text(
                                      bill.value.billName,
                                      style: pw.TextStyle(
                                        fontSize: 11,
                                        fontWeight: pw.FontWeight.bold,
                                      ),
                                    ),
                                    pw.SizedBox(width: 2),
                                    pw.Text(
                                      formatAmountVoucher(
                                        bill.value.billAmount.toString(),
                                      ),
                                      style: pw.TextStyle(
                                        fontSize: 11,
                                        fontWeight: pw.FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            pw.Expanded(
                              flex: 3,
                              child: pw.Container(
                                padding: pw.EdgeInsets.fromLTRB(5, 2, 10, 2),
                                alignment: pw.Alignment.centerRight,

                                child: pw.Text(
                                  '',
                                  style: pw.TextStyle(fontSize: 11),
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),

                  pw.Table(
                    border: pw.TableBorder(
                      horizontalInside: pw.BorderSide.none,
                      verticalInside: pw.BorderSide(
                        color: PdfColor.fromHex('#050400'),
                      ),
                      bottom: pw.BorderSide.none,
                      top: pw.BorderSide.none,
                    ),
                    children: [
                      pw.TableRow(
                        children: [
                          pw.Expanded(
                            flex: 7,
                            child: pw.Container(
                              padding: pw.EdgeInsets.fromLTRB(20, 2, 5, 2),
                              alignment: pw.Alignment.centerLeft,

                              child: pw.SizedBox(height: 25),
                            ),
                          ),

                          pw.Expanded(
                            flex: 3,
                            child: pw.Container(
                              padding: pw.EdgeInsets.fromLTRB(5, 2, 10, 2),
                              alignment: pw.Alignment.centerRight,

                              child: pw.SizedBox(height: 25),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  pw.Table(
                    border: pw.TableBorder(
                      horizontalInside: pw.BorderSide.none,
                      verticalInside: pw.BorderSide(
                        color: PdfColor.fromHex('#050400'),
                      ),
                      bottom: pw.BorderSide.none,
                      top: pw.BorderSide.none,
                    ),
                    children: [
                      pw.TableRow(
                        children: [
                          pw.Expanded(
                            flex: 7,
                            child: pw.Container(
                              padding: pw.EdgeInsets.fromLTRB(5, 2, 5, 2),
                              alignment: pw.Alignment.centerLeft,

                              child: pw.Text(
                                'Through : ',
                                style: pw.TextStyle(
                                  fontSize: 11,
                                  fontWeight: pw.FontWeight.normal,
                                ),
                              ),
                            ),
                          ),

                          pw.Expanded(
                            flex: 3,
                            child: pw.Container(
                              padding: pw.EdgeInsets.fromLTRB(5, 2, 10, 2),
                              alignment: pw.Alignment.centerRight,

                              child: pw.Text(
                                '',
                                style: pw.TextStyle(
                                  fontSize: 11,
                                  fontWeight: pw.FontWeight.normal,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  pw.Table(
                    border: pw.TableBorder(
                      horizontalInside: pw.BorderSide.none,
                      verticalInside: pw.BorderSide(
                        color: PdfColor.fromHex('#050400'),
                      ),
                      bottom: pw.BorderSide.none,
                      top: pw.BorderSide.none,
                    ),
                    children: [
                      pw.TableRow(
                        children: [
                          pw.Expanded(
                            flex: 7,
                            child: pw.Container(
                              padding: pw.EdgeInsets.fromLTRB(5, 2, 5, 2),
                              alignment: pw.Alignment.centerLeft,

                              child: pw.Text(
                                _selectedbankcashname!['name']!,
                                style: pw.TextStyle(
                                  fontSize: 11,
                                  fontWeight: pw.FontWeight.normal,
                                ),
                              ),
                            ),
                          ),

                          pw.Expanded(
                            flex: 3,
                            child: pw.Container(
                              padding: pw.EdgeInsets.fromLTRB(5, 2, 10, 2),
                              alignment: pw.Alignment.centerRight,

                              child: pw.Text(
                                '',
                                style: pw.TextStyle(
                                  fontSize: 11,
                                  fontWeight: pw.FontWeight.normal,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  if (cheque.isNotEmpty)
                    pw.Column(
                      children: [
                        pw.Table(
                          border: pw.TableBorder(
                            horizontalInside: pw.BorderSide.none,
                            verticalInside: pw.BorderSide(
                              color: PdfColor.fromHex('#050400'),
                            ),
                            bottom: pw.BorderSide.none,
                            top: pw.BorderSide.none,
                          ),
                          children: [
                            pw.TableRow(
                              children: [
                                pw.Expanded(
                                  flex: 7,
                                  child: pw.Container(
                                    padding: pw.EdgeInsets.fromLTRB(5, 2, 5, 2),
                                    alignment: pw.Alignment.centerLeft,

                                    child: pw.Text(
                                      'Bank Transaction Details:',
                                      style: pw.TextStyle(
                                        fontSize: 11,
                                        fontWeight: pw.FontWeight.normal,
                                      ),
                                    ),
                                  ),
                                ),

                                pw.Expanded(
                                  flex: 3,
                                  child: pw.Container(
                                    padding: pw.EdgeInsets.fromLTRB(
                                      5,
                                      2,
                                      10,
                                      2,
                                    ),
                                    alignment: pw.Alignment.centerRight,

                                    child: pw.Text(
                                      '',
                                      style: pw.TextStyle(
                                        fontSize: 11,
                                        fontWeight: pw.FontWeight.normal,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),

                        for (var cheque in cheque.asMap().entries)
                          pw.Table(
                            border: pw.TableBorder(
                              horizontalInside: pw.BorderSide.none,
                              verticalInside: pw.BorderSide(
                                color: PdfColor.fromHex('#050400'),
                              ),
                              bottom: pw.BorderSide.none,
                              top: pw.BorderSide.none,
                            ),
                            children: [
                              pw.TableRow(
                                children: [
                                  pw.Expanded(
                                    flex: 7,
                                    child: pw.Container(
                                      padding: pw.EdgeInsets.fromLTRB(
                                        5,
                                        2,
                                        5,
                                        2,
                                      ),
                                      alignment: pw.Alignment.centerLeft,

                                      child: pw.Row(
                                        children: [
                                          pw.Text(
                                            cheque.value.paymentMode,
                                            style: pw.TextStyle(
                                              fontSize: 11,
                                              fontWeight: pw.FontWeight.normal,
                                            ),
                                          ),

                                          pw.SizedBox(width: 10),

                                          pw.Text(
                                            formatlastsaledate(
                                              cheque.value.instdate.toString(),
                                            ),
                                            style: pw.TextStyle(
                                              fontSize: 11,
                                              fontWeight: pw.FontWeight.normal,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),

                                  pw.Expanded(
                                    flex: 3,
                                    child: pw.Container(
                                      padding: pw.EdgeInsets.fromLTRB(
                                        5,
                                        2,
                                        10,
                                        2,
                                      ),
                                      alignment: pw.Alignment.centerRight,

                                      child: pw.Text(
                                        '',
                                        style: pw.TextStyle(
                                          fontSize: 11,
                                          fontWeight: pw.FontWeight.normal,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                      ],
                    ),
                  pw.Column(
                    children: [
                      pw.Table(
                        border: pw.TableBorder(
                          horizontalInside: pw.BorderSide.none,
                          verticalInside: pw.BorderSide(
                            color: PdfColor.fromHex('#050400'),
                          ),
                          bottom: pw.BorderSide.none,
                          top: pw.BorderSide.none,
                        ),
                        children: [
                          pw.TableRow(
                            children: [
                              pw.Expanded(
                                flex: 7,
                                child: pw.Container(
                                  padding: pw.EdgeInsets.fromLTRB(5, 30, 5, 2),
                                  alignment: pw.Alignment.centerLeft,

                                  child: pw.Text(
                                    'Amount (in words) :',
                                    style: pw.TextStyle(
                                      fontSize: 11,
                                      fontWeight: pw.FontWeight.normal,
                                    ),
                                  ),
                                ),
                              ),

                              pw.Expanded(
                                flex: 3,
                                child: pw.Container(
                                  padding: pw.EdgeInsets.fromLTRB(5, 30, 10, 2),
                                  alignment: pw.Alignment.centerRight,

                                  child: pw.Text(
                                    '',
                                    style: pw.TextStyle(
                                      fontSize: 11,
                                      fontWeight: pw.FontWeight.normal,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),

                      pw.Table(
                        border: pw.TableBorder(
                          horizontalInside: pw.BorderSide.none,
                          verticalInside: pw.BorderSide(
                            color: PdfColor.fromHex('#050400'),
                          ),
                          bottom: pw.BorderSide.none,
                          top: pw.BorderSide.none,
                        ),
                        children: [
                          pw.TableRow(
                            children: [
                              pw.Expanded(
                                flex: 7,
                                child: pw.Container(
                                  padding: pw.EdgeInsets.fromLTRB(5, 2, 5, 2),
                                  alignment: pw.Alignment.centerLeft,

                                  child: pw.Text(
                                    convertAmountToWords(totalBillAmount),
                                    style: pw.TextStyle(
                                      fontSize: 11,
                                      fontWeight: pw.FontWeight.normal,
                                    ),
                                  ),
                                ),
                              ),

                              pw.Expanded(
                                flex: 3,
                                child: pw.Container(
                                  padding: pw.EdgeInsets.fromLTRB(5, 2, 10, 2),
                                  alignment: pw.Alignment.centerRight,

                                  child: pw.Text(
                                    '',
                                    style: pw.TextStyle(
                                      fontSize: 11,
                                      fontWeight: pw.FontWeight.normal,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),

                      pw.Table(
                        border: pw.TableBorder(
                          horizontalInside: pw.BorderSide.none,
                          verticalInside: pw.BorderSide(
                            color: PdfColor.fromHex('#050400'),
                          ),
                          bottom: pw.BorderSide.none,
                          top: pw.BorderSide.none,
                          right: pw.BorderSide.none,
                        ),
                        children: [
                          pw.TableRow(
                            children: [
                              pw.Expanded(
                                flex: 7,
                                child: pw.Container(
                                  padding: pw.EdgeInsets.fromLTRB(5, 5, 5, 0),
                                  alignment: pw.Alignment.centerLeft,

                                  child: pw.Text(
                                    '',
                                    style: pw.TextStyle(
                                      fontSize: 11,
                                      fontWeight: pw.FontWeight.normal,
                                    ),
                                  ),
                                ),
                              ),

                              pw.Expanded(
                                flex: 3,
                                child: pw.Container(
                                  padding: pw.EdgeInsets.fromLTRB(0, 5, 0, 0),
                                  alignment: pw.Alignment.centerRight,

                                  child: pw.Table(
                                    border: pw.TableBorder(
                                      horizontalInside: pw.BorderSide.none,
                                      verticalInside: pw.BorderSide.none,
                                      bottom: pw.BorderSide(
                                        color: PdfColor.fromHex('#050400'),
                                      ),
                                      top: pw.BorderSide(
                                        color: PdfColor.fromHex('#050400'),
                                      ),
                                      right: pw.BorderSide.none,
                                    ),
                                    children: [
                                      pw.TableRow(
                                        children: [
                                          pw.Expanded(
                                            flex: 3,
                                            child: pw.Container(
                                              padding: pw.EdgeInsets.fromLTRB(
                                                0,
                                                5,
                                                10,
                                                5,
                                              ),
                                              alignment:
                                                  pw.Alignment.centerRight,

                                              child: pw.Text(
                                                formatAmountVoucher(
                                                  totalBillAmount.toString(),
                                                ),
                                                style: pw.TextStyle(
                                                  fontSize: 11,
                                                  fontWeight:
                                                      pw.FontWeight.normal,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),

                      pw.Table(
                        border: pw.TableBorder(
                          horizontalInside: pw.BorderSide.none,
                          verticalInside: pw.BorderSide.none,
                          bottom: pw.BorderSide.none,
                          top: pw.BorderSide.none,
                          right: pw.BorderSide.none,
                        ),
                        children: [
                          pw.TableRow(
                            children: [
                              pw.Expanded(
                                flex: 7,
                                child: pw.Container(
                                  padding: pw.EdgeInsets.fromLTRB(5, 50, 5, 0),
                                  alignment: pw.Alignment.centerLeft,

                                  child: pw.Text(
                                    '',
                                    style: pw.TextStyle(
                                      fontSize: 11,
                                      fontWeight: pw.FontWeight.normal,
                                    ),
                                  ),
                                ),
                              ),

                              pw.Expanded(
                                flex: 3,
                                child: pw.Container(
                                  padding: pw.EdgeInsets.fromLTRB(0, 50, 5, 0),
                                  alignment: pw.Alignment.centerLeft,

                                  child: pw.Text(
                                    'Authorised Signatory',
                                    style: pw.TextStyle(
                                      fontSize: 11,
                                      fontWeight: pw.FontWeight.normal,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
              pw.Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: pw.Container(
                  padding: pw.EdgeInsets.fromLTRB(5, 5, 5, 5),
                  alignment: pw.Alignment.center,
                  child: pw.Text(
                    'Created in Fincore Go',
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(
                      fontSize: 10,
                      color: PdfColor.fromInt(0xFFCCCCCC),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );

    final pdfData = await pdf.save();

    final dir = await getApplicationDocumentsDirectory();
    final filePath = '${dir.path}/$_selectedparty.pdf';

    final file = File(filePath);
    await file.writeAsBytes(pdfData);

    await Share.shareXFiles([
      XFile(filePath, mimeType: 'application/pdf'),
    ], text: 'Sharing Receipt Voucher for $_selectedparty');

    _resetReceiptFormAfterShare();
  }

  // Shared by both the regular A4 receipt voucher path and the UniGas
  // POS receipt path so the post-share reset stays in sync between them.
  void _resetReceiptFormAfterShare() {
    // Drop focus first - otherwise clearing a party/ledger TypeAheadField's
    // text below while it still has focus makes it re-run its
    // suggestionsCallback('') (which matches everything) and pop its
    // suggestions overlay back open right after reset. Request a disposable
    // FocusNode rather than a bare unfocus() so the scope's "last focused
    // descendant" pointer can't hand focus straight back to that field.
    FocusScope.of(context).requestFocus(FocusNode());

    // UniGas only: this reset runs right after printUniGasPdf's full-screen
    // printing animation dialog pops itself (Navigator.pop() inside a
    // delayed callback in _PrintingAnimationOverlay, not synchronously with
    // this function). Navigator's own focus-restoration-to-previous-route
    // can land on the NEXT frame, after the drop above already ran -
    // reclaiming focus for the Party field and popping its suggestions
    // list back open. A second drop scheduled for the next frame beats
    // that race instead of just the first one.
    if (isUniGasSerial) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) FocusScope.of(context).requestFocus(FocusNode());
      });
    }

    _notifier.resetAfterShare();

    setState(() {
      _partyController.clear();

      receiverNameController.clear();
      receiverMobileController.clear();
      receiverSignatureBytes = null;

      controller_narration.clear();
      _textFieldFocusNodeNarration.unfocus(); // Unfocus the TextField

      _dateController.text = receiptdatetxt;

      fetchvchnos(_selectedvchtypename);

      if (serial_no != uniGasSerialNumber) {
        _bankcashnameController.text = _selectedbankcashname != null
            ? _selectedbankcashname!['name']!
            : "";
      }

      controller_totalamt.text = _s.formattedTotalBillAmount;
    });
  }

  // UniGas-only POS receipt format (76mm wide, shared/viewed rather than
  // printed on the Sunmi's thermal paper), built to match the reference
  // "Unigas Receipt Format.pdf" - mirrors the styling of the UniGas Tax
  // Invoice/Delivery Note formats in SalesRegistration.dart /
  // DeliveryNoteRegistration.dart.
  Future<void> _generateUniGasReceiptPDF() async {
    // Vehicle lookup, same cached-prefs pattern as the other UniGas PDFs.
    String vehicleName = '';
    try {
      final String? spectraAllocationsString = prefs?.getString(
        'spectra_allocations',
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
      debugPrint("UNIGAS RECEIPT VEHICLE LOOKUP ERROR: $e");
    }

    // Party TRN/address/phone/email aren't preloaded for Receipt (unlike
    // Sales Invoice's loadLedgerData) - resolved here from the party ledger
    // list already cached by loadData() (tally-api replacement for legacy's
    // getLedger/:company/:serial - no need for a second round trip since
    // the full ledger row, including these fields, was already fetched).
    String customerTrn = '';
    String customerAddress = '';
    String customerMobile = '';
    String customerEmail = '';
    try {
      if (_selectedparty != null &&
          _selectedparty.toString().trim().isNotEmpty) {
        final ledger = _notifier.partyLedgersRaw.firstWhere(
          (l) => l['name'] == _selectedparty,
          orElse: () => const <String, dynamic>{},
        );
        if (ledger.isNotEmpty) {
          customerTrn = ledger['tinNumber']?.toString() ?? '';
          final address =
              (ledger['address'] as List?)?.cast<String>() ?? const [];
          final emirate = ledger['stateName']?.toString() ?? '';
          final country = ledger['countryName']?.toString() ?? '';
          customerAddress = [...address, emirate, country]
              .where(
                (p) => p.trim().isNotEmpty && p.trim().toLowerCase() != 'null',
              )
              .join(', ');
          customerMobile = ledger['mobileNumber']?.toString() ?? '';
          customerEmail = ledger['email']?.toString() ?? '';
        }
      }
    } catch (e) {
      debugPrint("UNIGAS RECEIPT LEDGER LOOKUP ERROR: $e");
    }

    String cleanOrNotAvailable(String? value) {
      if (value == null) return 'Not Available';
      final trimmed = value.trim();
      return (trimmed.isEmpty || trimmed.toLowerCase() == 'null')
          ? 'Not Available'
          : trimmed;
    }

    final logoBytes = await rootBundle.load("assets/uigas-logo.jpeg");
    final uniGasLogo = pw.MemoryImage(logoBytes.buffer.asUint8List());

    // Arabic-capable font - NotoSans.ttf (used for everything else) has
    // no Arabic glyphs.
    final arabicFontData = await rootBundle.load(
      "assets/fonts/NotoSansArabic.ttf",
    );
    final arabicFont = pw.Font.ttf(arabicFontData);

    final now = DateTime.now();
    final dateTimeText =
        '${DateFormat('dd-MM-yyyy').format(now)}    ${DateFormat('HH:mm').format(now)}';

    final NumberFormat amountFormatter = NumberFormat(
      '#,##0.${'0' * decimal!}',
      'en_US',
    );
    String formatAmount(num value) => amountFormatter.format(value);

    pw.Widget leftText(String text, {double size = 9, pw.FontWeight? weight}) {
      return pw.Align(
        alignment: pw.Alignment.centerLeft,
        child: pw.Text(
          text,
          style: pw.TextStyle(fontSize: size, fontWeight: weight),
        ),
      );
    }

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
              pw.TextSpan(
                text: value,
                style: pw.TextStyle(fontSize: size),
              ),
            ],
          ),
        ),
      );
    }

    pw.Widget spaceBetweenLine(String label, String value) {
      return pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(width: 6),
          pw.Flexible(
            child: pw.Text(
              value,
              textAlign: pw.TextAlign.right,
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
            ),
          ),
        ],
      );
    }

    pw.Widget billRow(
      String sn,
      String docNo,
      String amount, {
      bool bold = false,
    }) {
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(
          children: [
            pw.Expanded(
              flex: 2,
              child: pw.Text(
                sn,
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: bold ? pw.FontWeight.bold : null,
                ),
              ),
            ),
            pw.Expanded(
              flex: 4,
              child: pw.Text(
                docNo,
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: bold ? pw.FontWeight.bold : null,
                ),
              ),
            ),
            pw.Expanded(
              flex: 4,
              child: pw.Text(
                amount,
                textAlign: pw.TextAlign.right,
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: bold ? pw.FontWeight.bold : null,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        // Shared/viewed only, so widened to 76mm to match the UniGas Tax
        // Invoice/Delivery Note formats.
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
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Text(
                    'RECEIPT',
                    style: pw.TextStyle(
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    'إيصال استلام',
                    textDirection: pw.TextDirection.rtl,
                    style: pw.TextStyle(fontSize: 10, font: arabicFont),
                  ),
                ],
              ),
              pw.SizedBox(height: 10),
              leftText('CUSTOMER DETAILS', size: 9, weight: pw.FontWeight.bold),
              pw.SizedBox(height: 4),
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(6),
                decoration: pw.BoxDecoration(border: pw.Border.all(width: 1)),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    detailLine(
                      'Name',
                      cleanOrNotAvailable(_selectedparty?.toString()),
                      size: 9,
                      boldLabel: false,
                    ),
                    pw.SizedBox(height: 6),
                    detailLine('TRN', cleanOrNotAvailable(customerTrn)),
                    pw.SizedBox(height: 6),
                    detailLine('Address', cleanOrNotAvailable(customerAddress)),
                    pw.SizedBox(height: 6),
                    detailLine('Phone', cleanOrNotAvailable(customerMobile)),
                    pw.SizedBox(height: 6),
                    detailLine('Email', cleanOrNotAvailable(customerEmail)),
                  ],
                ),
              ),
              pw.SizedBox(height: 10),
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(6),
                decoration: pw.BoxDecoration(border: pw.Border.all(width: 1)),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    spaceBetweenLine(
                      'Receipt No. :',
                      cleanOrNotAvailable(_vchnoController.text),
                    ),
                    pw.SizedBox(height: 4),
                    spaceBetweenLine(
                      'Payment Mode:',
                      // Payment Mode is only a meaningful, user-chosen
                      // value when the field is actually shown in the UI
                      // (i.e. the ledger isn't Cash-in-Hand) - otherwise
                      // _selectedpaymentmode still holds its leftover
                      // paymentmode_data.first default ("ATM"), which was
                      // never really selected, so show "Cash" instead.
                      isPaymentModeVisible
                          ? cleanOrNotAvailable(
                              _selectedpaymentmode?.toString(),
                            )
                          : 'Cash',
                    ),
                    pw.SizedBox(height: 4),
                    spaceBetweenLine(
                      'Amount Received (AED):',
                      formatAmount(roundedtotalBillAmount),
                    ),
                    pw.SizedBox(height: 4),
                    spaceBetweenLine('Date & Time:', dateTimeText),
                    pw.SizedBox(height: 4),
                    spaceBetweenLine(
                      'Vehicle No. :',
                      cleanOrNotAvailable(vehicleName),
                    ),
                    pw.SizedBox(height: 4),
                    spaceBetweenLine('Driver Name:', cleanOrNotAvailable(name)),
                    if (controller_narration.text.trim().isNotEmpty) ...[
                      pw.SizedBox(height: 6),
                      pw.RichText(
                        text: pw.TextSpan(
                          children: [
                            pw.TextSpan(
                              text: 'Remarks: ',
                              style: pw.TextStyle(
                                fontSize: 9,
                                fontWeight: pw.FontWeight.bold,
                                fontStyle: pw.FontStyle.italic,
                              ),
                            ),
                            pw.TextSpan(
                              text: controller_narration.text,
                              style: pw.TextStyle(fontSize: 9),
                            ),
                          ],
                        ),
                      ),
                    ],
                    pw.SizedBox(height: 8),
                    pw.Divider(thickness: 0.75),
                    pw.SizedBox(height: 4),
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
                            text: convertAmountToWords(roundedtotalBillAmount),
                            style: pw.TextStyle(fontSize: 9),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (bills.isNotEmpty) ...[
                pw.SizedBox(height: 10),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Text(
                      'Bill Allocations:',
                      style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 4),
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
                      billRow(
                        'Sr. #',
                        'Document No.',
                        'Invoice Value',
                        bold: true,
                      ),
                      pw.SizedBox(height: 3),
                      pw.Divider(thickness: 0.75),
                      pw.SizedBox(height: 3),
                      for (var bill in bills.asMap().entries)
                        billRow(
                          '${bill.key + 1}',
                          cleanOrNotAvailable(bill.value.billNo),
                          formatAmount(bill.value.billAmount),
                        ),
                    ],
                  ),
                ),
              ],
              pw.SizedBox(height: 10),
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(6),
                decoration: pw.BoxDecoration(border: pw.Border.all(width: 1)),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Text(
                          'PAYER SIGNATURE',
                          style: pw.TextStyle(
                            fontSize: 8,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.Text(
                          'توقيع الدافع',
                          textDirection: pw.TextDirection.rtl,
                          style: pw.TextStyle(fontSize: 8, font: arabicFont),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 6),
                    pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        // Shows the receiver's captured on-screen signature
                        // when available, otherwise a blank box for the
                        // payer's physical signature/stamp.
                        receiverSignatureBytes != null
                            ? pw.Container(
                                width: 60,
                                height: 60,
                                decoration: pw.BoxDecoration(
                                  border: pw.Border.all(width: 1),
                                ),
                                child: pw.Image(
                                  pw.MemoryImage(receiverSignatureBytes!),
                                  fit: pw.BoxFit.contain,
                                ),
                              )
                            : pw.Container(
                                width: 60,
                                height: 60,
                                decoration: pw.BoxDecoration(
                                  border: pw.Border.all(width: 1),
                                ),
                              ),
                        pw.SizedBox(width: 10),
                        pw.Expanded(
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(
                                'Name: ${receiverNameController.text.trim()}',
                                style: pw.TextStyle(fontSize: 9),
                              ),
                              pw.SizedBox(height: 20),
                              pw.Text(
                                'Phone: ${receiverMobileController.text.trim()}',
                                style: pw.TextStyle(fontSize: 9),
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
                'Please ensure the payment amount matches this receipt before signing',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(fontSize: 8),
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                'Electronic receipt. No signature or stamp required from issuer',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(fontSize: 8),
              ),
              pw.SizedBox(height: 6),
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
    final dir = await getApplicationDocumentsDirectory();
    final formattedDate = DateFormat('yyyyMMdd_HHmmss').format(now);
    final filePath = '${dir.path}/Receipt_$formattedDate.pdf';
    final file = File(filePath);
    await file.writeAsBytes(pdfData);

    // UniGas is direct-print only - no share sheet. Reset always runs,
    // even if the print flow itself throws (e.g. no printer available,
    // user cancels, raster/platform error) - otherwise a failed/aborted
    // print silently leaves the form filled with no way to know why.
    try {
      await printUniGasPdf(
        context,
        pdfData,
        documentName: 'Receipt_$formattedDate',
      );
    } catch (e) {
      debugPrint('UNIGAS RECEIPT PRINT ERROR: $e');
    } finally {
      _resetReceiptFormAfterShare();
    }
  }

  String getCurrencySymbol(String currencyCode) {
    NumberFormat format;

    // Number/currency formatting is intentionally locale-independent -
    // amounts must show Western digits and standard symbol placement
    // regardless of the app's display language (Arabic UI still shows
    // '1,234.50 AED', not Arabic-Indic digits), matching how real
    // finance apps in the region behave.
    Locale locale = const Locale('en');

    try {
      if (currencyCode == 'INR' ||
          currencyCode == 'EUR' ||
          currencyCode == 'PKR' ||
          currencyCode == 'USD') {
        format = NumberFormat.simpleCurrency(
          locale: locale.toString(),
          name: currencyCode,
        );
      } else {
        format = NumberFormat.currency(
          locale: locale.toString(),
          name: currencyCode,
        );
      }
      return format.currencySymbol;
    } catch (e) {
      return 'AED';
    }
  }

  // Currency-symbol-aware value display - renders the Dirham glyph for AED
  // instead of the literal "AED" text that getCurrencySymbol() falls back
  // to (there's no distinct AED symbol glyph in the standard locale data).
  Widget _currencyValueWidget(String numberText, TextStyle style) {
    return currencyAmountText(
      currencyCode: currencycode,
      symbol: getCurrencySymbol(currencycode),
      amountText: numberText,
      style: style,
    );
  }

  bool isNumeric(String s) {
    if (s == null) {
      return false;
    }
    return double.tryParse(s) != null;
  }

  // `billduedate` is only ever touched by `_selectbilldueDate` (zero call
  // sites - see the notifier's doc-comment); `instdate` is the Add-Cheque
  // sheet's own dialog-composition field.
  late DateTime billduedate;
  late DateTime instdate;

  final DateFormat _dateFormat = DateFormat('yyyyMMdd');

  final TextEditingController billAmountController = TextEditingController();
  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _billduedateController = TextEditingController();
  final TextEditingController instDateController = TextEditingController();
  final TextEditingController instNoController = TextEditingController();
  final TextEditingController chequeAmountController = TextEditingController();

  /// Thin wrapper - every `showAppMessage`-based pre-save validation stays
  /// here (they need `context`), the payload build/POST is the notifier's
  /// `saveEntry`, and the success dialog is pure UI so it stays here too.
  Future<void> saveEntry() async {
    // Prevent save if party not selected
    if (_selectedparty == null || _selectedparty.toString().trim().isEmpty) {
      showAppMessage(context, "Please select Party");
      return;
    }

    // Prevent save if bank/cash not selected
    if (_selectedbankcashname == null ||
        _selectedbankcashname!['name'] == null ||
        _selectedbankcashname!['name']!.trim().isEmpty) {
      showAppMessage(context, "Please select Bank / Cash Ledger");
      return;
    }

    // UniGas only: Receiver Name is mandatory before saving.
    if (isUniGasSerial && receiverNameController.text.trim().isEmpty) {
      showAppMessage(context, "Please enter the Receiver's Name before saving");
      return;
    }

    if (bills.isEmpty) {
      showAppMessage(context, 'Atleast add 1 bill');
      return;
    }

    final String? error = await _notifier.saveEntry(
      narration: controller_narration.text,
      vchno: _vchnoController.text,
    );

    if (!mounted) return;

    if (error != null) {
      showAppMessage(context, error);
      return;
    }

    showReceiptVoucherDialog(context);
  }

  Future<void> _selectreceiptDate(BuildContext context) async {
    if (isUniGasSerial) {
      closeKeyboard(context);
      showAppMessage(context, "Voucher date cannot be changed");
      return;
    }
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: receiptdate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
      builder: (BuildContext context, Widget? child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(
              context,
            ).colorScheme.copyWith(primary: app_color),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != receiptdate) {
      _notifier.setReceiptDate(picked);
      _dateController.text = receiptdatetxt;
      if (_selectedparty != null &&
          _selectedparty.toString().trim().isNotEmpty) {
        if (showOutstandingBills && isUniGasSerial) {
          fetchPartyOutstanding(_selectedparty.toString());
        }
      }
    }
  } // main receipt date

  Future<void> _selectinstDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: instdate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
      builder: (BuildContext context, Widget? child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(
              context,
            ).colorScheme.copyWith(primary: app_color),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != instdate) {
      setState(() {
        instdate = picked;
        instdatestring = _dateFormat.format(instdate);
        instdatetxt = formatlastsaledate(instdatestring);
        instDateController.text = instdatetxt;
      });
    }
  }

  Future<void> _selectbilldueDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: billduedate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
      builder: (BuildContext context, Widget? child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(
              context,
            ).colorScheme.copyWith(primary: app_color),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != receiptdate) {
      setState(() {
        billduedate = picked;
        billduedatestring = _dateFormat.format(billduedate);
        billduedatetxt = formatlastsaledate(billduedatestring);
        _billduedateController.text = billduedatetxt;
      });
    }
  } // bill due date selection

  Future<void> _showBillsDetailsPopup(BuildContext context) async {
    setState(() {
      showModalBottomSheet(
        useSafeArea: true,
        barrierColor: Colors.black.withValues(alpha: 0.45),
        context: context,
        isScrollControlled: true,
        enableDrag: false,
        backgroundColor: Colors.transparent,
        builder: (BuildContext context) {
          return StatefulBuilder(
            builder: (context, setState) {
              final mediaQuery = MediaQuery.of(context);
              final screenHeight = mediaQuery.size.height;
              final isKeyboardOpen = mediaQuery.viewInsets.bottom > 0;

              double sheetHeight;

              if (isKeyboardOpen) {
                if (screenHeight < 700) {
                  sheetHeight = 0.95;
                } else if (screenHeight < 850) {
                  sheetHeight = 0.88;
                } else {
                  sheetHeight = 0.78;
                }
              } else {
                if (isVisibleBillNo || isVisibleDueDate) {
                  if (screenHeight < 700) {
                    sheetHeight = 0.86;
                  } else if (screenHeight < 850) {
                    sheetHeight = 0.70;
                  } else {
                    sheetHeight = 0.60;
                  }
                } else {
                  if (screenHeight < 700) {
                    sheetHeight = 0.62;
                  } else if (screenHeight < 850) {
                    sheetHeight = 0.50;
                  } else {
                    sheetHeight = 0.42;
                  }
                }
              }

              return AnimatedPadding(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                padding: EdgeInsets.only(bottom: mediaQuery.viewInsets.bottom),
                child: FractionallySizedBox(
                  heightFactor: sheetHeight,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(24),
                      ),
                      border: Border.all(
                        color: Theme.of(
                          context,
                        ).dividerColor.withValues(alpha: 0.45),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.18),
                          blurRadius: 24,
                          offset: const Offset(0, -8),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        const SizedBox(height: 10),

                        Container(
                          width: 45,
                          height: 5,
                          decoration: BoxDecoration(
                            color: Theme.of(context).dividerColor,
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),

                        const SizedBox(height: 12),

                        if (!isKeyboardOpen) ...[
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: app_color,
                            ),
                            child: const Icon(
                              Icons.receipt_long,
                              color: Colors.white,
                              size: 26,
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],

                        Text(
                          "Add Bill",
                          style: GoogleFonts.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),

                        const SizedBox(height: 10),

                        Expanded(
                          child: SingleChildScrollView(
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.manual,
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                            child: Form(
                              key: _billsFormkey,
                              child: Column(
                                children: <Widget>[
                                  DropdownButtonFormField<String>(
                                    isExpanded: true,
                                    decoration: InputDecoration(
                                      labelText: "Bill Type",
                                      hintText: "Select Bill Type",
                                      labelStyle: GoogleFonts.poppins(
                                        fontSize: 12.5,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                      hintStyle: GoogleFonts.poppins(
                                        fontSize: 12.5,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                      prefixIcon: Container(
                                        margin: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          gradient: const LinearGradient(
                                            colors: [
                                              Colors.indigo,
                                              Colors.cyan,
                                            ],
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.book,
                                          color: Colors.white,
                                          size: 16,
                                        ),
                                      ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(14),
                                        borderSide: BorderSide(
                                          color: Theme.of(context).dividerColor,
                                        ),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(14),
                                        borderSide: BorderSide(
                                          color: Theme.of(context).dividerColor,
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(14),
                                        borderSide: BorderSide(
                                          color: app_color,
                                          width: 1.3,
                                        ),
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 10,
                                          ),
                                    ),
                                    value: _selectedbill,
                                    items: billsdata.map((String value) {
                                      return DropdownMenuItem(
                                        value: value,
                                        child: Text(
                                          value,
                                          style: GoogleFonts.poppins(
                                            fontSize: 13,
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                    onChanged: (newValue) {
                                      setState(() {
                                        _selectedbill = newValue!;

                                        if (_selectedbill == 'New Ref' ||
                                            _selectedbill == 'Agst Ref') {
                                          isVisibleDueDate = true;
                                          isVisibleBillNo = true;
                                        } else {
                                          isVisibleDueDate = false;
                                          isVisibleBillNo = false;
                                          billNoController.clear();
                                          _billduedateController.clear();
                                        }

                                        _billsFormkey = GlobalKey<FormState>();
                                      });
                                    },
                                  ),

                                  Visibility(
                                    visible: isVisibleBillNo,
                                    child: Padding(
                                      padding: const EdgeInsets.only(top: 12),
                                      child: TextFormField(
                                        controller: billNoController,
                                        validator: (value) => value!.isEmpty
                                            ? 'Please enter bill no'
                                            : null,
                                        decoration: InputDecoration(
                                          labelText: "Bill No",
                                          hintText: "Enter Bill No",
                                          labelStyle: GoogleFonts.poppins(
                                            fontSize: 12.5,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                          ),
                                          hintStyle: GoogleFonts.poppins(
                                            fontSize: 12.5,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                          ),
                                          prefixIcon: Container(
                                            margin: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              gradient: const LinearGradient(
                                                colors: [
                                                  Colors.orange,
                                                  Colors.deepOrangeAccent,
                                                ],
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: const Icon(
                                              Icons.confirmation_num_outlined,
                                              color: Colors.white,
                                              size: 20,
                                            ),
                                          ),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                          ),
                                          enabledBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                            borderSide: BorderSide(
                                              color: Theme.of(
                                                context,
                                              ).dividerColor,
                                            ),
                                          ),
                                          focusedBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                            borderSide: BorderSide(
                                              color: app_color,
                                              width: 1.5,
                                            ),
                                          ),
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                horizontal: 12,
                                                vertical: 10,
                                              ),
                                        ),
                                      ),
                                    ),
                                  ),

                                  Visibility(
                                    visible: isVisibleDueDate,
                                    child: Padding(
                                      padding: const EdgeInsets.only(top: 12),
                                      child: TextFormField(
                                        controller: _billduedateController,
                                        validator: (value) {
                                          if (value!.isNotEmpty) {
                                            if (double.tryParse(value) ==
                                                null) {
                                              return 'Invalid input, please enter a number';
                                            } else if (double.parse(value) <
                                                0) {
                                              return 'Due date days cannot be negative';
                                            }
                                          }
                                          return null;
                                        },
                                        decoration: InputDecoration(
                                          labelText: "Due Date (days)",
                                          hintText: "Enter due date",
                                          labelStyle: GoogleFonts.poppins(
                                            fontSize: 13,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                          ),
                                          hintStyle: GoogleFonts.poppins(
                                            fontSize: 13,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                          ),
                                          prefixIcon: Container(
                                            margin: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              gradient: const LinearGradient(
                                                colors: [
                                                  Colors.pinkAccent,
                                                  Colors.redAccent,
                                                ],
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: const Icon(
                                              Icons.calendar_today,
                                              color: Colors.white,
                                              size: 20,
                                            ),
                                          ),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                          ),
                                          enabledBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                            borderSide: BorderSide(
                                              color: Theme.of(
                                                context,
                                              ).dividerColor,
                                            ),
                                          ),
                                          focusedBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                            borderSide: BorderSide(
                                              color: app_color,
                                              width: 1.5,
                                            ),
                                          ),
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                horizontal: 12,
                                                vertical: 10,
                                              ),
                                        ),
                                      ),
                                    ),
                                  ),

                                  Padding(
                                    padding: const EdgeInsets.only(top: 12),
                                    child: TextFormField(
                                      controller: billAmountController,
                                      keyboardType: TextInputType.number,
                                      validator: (value) {
                                        if (value!.isEmpty) {
                                          return 'Please enter amount';
                                        }
                                        if (!isNumeric(value)) {
                                          return 'Enter valid amount';
                                        }
                                        if (double.parse(value) == 0) {
                                          return 'Amount should not be 0';
                                        }
                                        return null;
                                      },
                                      decoration: InputDecoration(
                                        labelText: "Amount",
                                        hintText: "0",
                                        labelStyle: GoogleFonts.poppins(
                                          fontSize: 13,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                        hintStyle: GoogleFonts.poppins(
                                          fontSize: 13,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                        prefix: Container(
                                          margin: const EdgeInsets.only(
                                            right: 8,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: const BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: [
                                                Colors.green,
                                                Colors.teal,
                                              ],
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                            ),
                                            borderRadius: BorderRadius.all(
                                              Radius.circular(8),
                                            ),
                                          ),
                                          child: currencySymbolWidget(
                                            currencycode,
                                            getCurrencySymbol(currencycode),
                                            GoogleFonts.poppins(
                                              color: Colors.white,
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          borderSide: BorderSide(
                                            color: Theme.of(
                                              context,
                                            ).dividerColor,
                                          ),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          borderSide: BorderSide(
                                            color: app_color,
                                            width: 1.5,
                                          ),
                                        ),
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 10,
                                            ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        SafeArea(
                          top: false,
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                            decoration: BoxDecoration(
                              color: Theme.of(context).cardColor,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.08),
                                  blurRadius: 10,
                                  offset: const Offset(0, -2),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 14,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                    onPressed: () {
                                      Navigator.of(context).pop();
                                      _selectedbill = billsdata.first;
                                      isVisibleDueDate =
                                          _selectedbill == 'New Ref' ||
                                          _selectedbill == 'Agst Ref';
                                      isVisibleBillNo = isVisibleDueDate;
                                      _billduedateController.clear();
                                      billAmountController.clear();
                                    },
                                    child: Text(
                                      'Cancel',
                                      style: GoogleFonts.poppins(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ),

                                const SizedBox(width: 12),

                                Expanded(
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: app_color,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 14,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                    onPressed: () {
                                      if (_billsFormkey.currentState!
                                          .validate()) {
                                        _billsFormkey.currentState!.save();
                                        addBill();
                                      }
                                    },
                                    child: Text(
                                      "Add Bill",
                                      style: GoogleFonts.poppins(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 15,
                                      ),
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
              );
            },
          );
        },
      );
    });
  }

  Future<void> _showChequeDetailsPopup(BuildContext context) async {
    setState(() {
      showModalBottomSheet(
        useSafeArea: true,
        barrierColor: Colors.black.withValues(alpha: 0.45),
        context: context,
        isScrollControlled: true,
        enableDrag: false,
        backgroundColor: Colors.transparent,
        builder: (BuildContext context) {
          return StatefulBuilder(
            builder: (context, setStateDialog) {
              final mediaQuery = MediaQuery.of(context);
              final screenHeight = mediaQuery.size.height;
              final isKeyboardOpen = mediaQuery.viewInsets.bottom > 0;

              double sheetHeight;

              if (isKeyboardOpen) {
                if (screenHeight < 700) {
                  sheetHeight = 0.95;
                } else if (screenHeight < 850) {
                  sheetHeight = 0.88;
                } else {
                  sheetHeight = 0.78;
                }
              } else {
                if (screenHeight < 700) {
                  sheetHeight = 0.90;
                } else if (screenHeight < 850) {
                  sheetHeight = 0.74;
                } else {
                  sheetHeight = 0.64;
                }
              }

              return AnimatedPadding(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                padding: EdgeInsets.only(bottom: mediaQuery.viewInsets.bottom),
                child: FractionallySizedBox(
                  heightFactor: sheetHeight,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(24),
                      ),
                      border: Border.all(
                        color: Theme.of(
                          context,
                        ).dividerColor.withValues(alpha: 0.45),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.18),
                          blurRadius: 24,
                          offset: const Offset(0, -8),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        const SizedBox(height: 10),

                        Container(
                          width: 45,
                          height: 5,
                          decoration: BoxDecoration(
                            color: Theme.of(context).dividerColor,
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),

                        const SizedBox(height: 12),

                        if (!isKeyboardOpen) ...[
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: app_color,
                            ),
                            child: const Icon(
                              Icons.payment,
                              color: Colors.white,
                              size: 26,
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],

                        Text(
                          "$_selectedpaymentmode Details",
                          style: GoogleFonts.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                          textAlign: TextAlign.center,
                        ),

                        const SizedBox(height: 10),

                        Expanded(
                          child: SingleChildScrollView(
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.manual,
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                            child: Form(
                              key: _chequedetailsFormkey,
                              child: Column(
                                children: <Widget>[
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                    child: TextFormField(
                                      controller: instNoController,
                                      decoration: InputDecoration(
                                        labelText: 'Inst No',
                                        hintText: 'Enter Inst No',
                                        labelStyle: GoogleFonts.poppins(
                                          fontSize: 13,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 10,
                                            ),
                                        filled: true,
                                        fillColor:
                                            Theme.of(
                                              context,
                                            ).inputDecorationTheme.fillColor ??
                                            (Theme.of(context)
                                                    .inputDecorationTheme
                                                    .fillColor ??
                                                Theme.of(
                                                  context,
                                                ).cardColor.withOpacity(0.95)),
                                        prefixIcon: Container(
                                          margin: const EdgeInsets.all(8),
                                          decoration: const BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: [
                                                Colors.orange,
                                                Colors.deepOrangeAccent,
                                              ],
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                            ),
                                            borderRadius: BorderRadius.all(
                                              Radius.circular(12),
                                            ),
                                          ),
                                          child: const Icon(
                                            Icons.confirmation_number_outlined,
                                            color: Colors.white,
                                            size: 20,
                                          ),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                          borderSide: BorderSide(
                                            color: Theme.of(
                                              context,
                                            ).dividerColor,
                                            width: 1,
                                          ),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                          borderSide: BorderSide(
                                            color: app_color,
                                            width: 1.5,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),

                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 4,
                                    ),
                                    child: TextFormField(
                                      controller: instDateController,
                                      readOnly: true,
                                      enableInteractiveSelection: false,
                                      onTap: () => _selectinstDate(context),
                                      decoration: InputDecoration(
                                        labelText: 'Inst Date',
                                        hintText: 'Select Date',
                                        labelStyle: GoogleFonts.poppins(
                                          fontSize: 13,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 10,
                                            ),
                                        filled: true,
                                        fillColor:
                                            Theme.of(
                                              context,
                                            ).inputDecorationTheme.fillColor ??
                                            (Theme.of(context)
                                                    .inputDecorationTheme
                                                    .fillColor ??
                                                Theme.of(
                                                  context,
                                                ).cardColor.withOpacity(0.95)),
                                        prefixIcon: Container(
                                          margin: const EdgeInsets.all(8),
                                          decoration: const BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: [
                                                Colors.teal,
                                                Colors.cyan,
                                              ],
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                            ),
                                            borderRadius: BorderRadius.all(
                                              Radius.circular(12),
                                            ),
                                          ),
                                          child: const Icon(
                                            Icons.calendar_today,
                                            color: Colors.white,
                                            size: 20,
                                          ),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                          borderSide: BorderSide(
                                            color: Theme.of(
                                              context,
                                            ).dividerColor,
                                            width: 1,
                                          ),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                          borderSide: BorderSide(
                                            color: app_color,
                                            width: 1.5,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),

                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 4,
                                    ),
                                    child: TypeAheadField<String>(
                                      suggestionsCallback: (pattern) {
                                        return bankname_data.where((item) {
                                          final name = item
                                              .toString()
                                              .toLowerCase();
                                          return name.contains(
                                            pattern.toLowerCase(),
                                          );
                                        }).toList();
                                      },
                                      builder: (context, controller, focusNode) {
                                        controller.text =
                                            _banknameController.text;

                                        return TextField(
                                          controller: controller,
                                          focusNode: focusNode,
                                          decoration: InputDecoration(
                                            labelText: "Bank",
                                            hintText: 'Search Bank',
                                            labelStyle: GoogleFonts.poppins(
                                              fontSize: 13,
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.onSurfaceVariant,
                                            ),
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                  horizontal: 12,
                                                  vertical: 10,
                                                ),
                                            filled: true,
                                            fillColor:
                                                Theme.of(context)
                                                    .inputDecorationTheme
                                                    .fillColor ??
                                                (Theme.of(context)
                                                        .inputDecorationTheme
                                                        .fillColor ??
                                                    Colors.white.withOpacity(
                                                      0.95,
                                                    )),
                                            prefixIcon: Container(
                                              margin: const EdgeInsets.all(8),
                                              decoration: const BoxDecoration(
                                                gradient: LinearGradient(
                                                  colors: [
                                                    Colors.purple,
                                                    Colors.deepPurpleAccent,
                                                  ],
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                ),
                                                borderRadius: BorderRadius.all(
                                                  Radius.circular(12),
                                                ),
                                              ),
                                              child: const Icon(
                                                Icons.account_balance_outlined,
                                                color: Colors.white,
                                                size: 20,
                                              ),
                                            ),
                                            suffixIcon: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                if (controller.text.isNotEmpty)
                                                  GestureDetector(
                                                    onTap: () {
                                                      setState(() {
                                                        controller.clear();
                                                        selectedbankname = "";
                                                      });
                                                    },
                                                    child: Icon(
                                                      Icons.close,
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .onSurfaceVariant,
                                                      size: 20,
                                                    ),
                                                  ),
                                                const SizedBox(width: 4),
                                                Icon(
                                                  Icons.arrow_drop_down,
                                                  color: Theme.of(
                                                    context,
                                                  ).colorScheme.onSurface,
                                                ),
                                                const SizedBox(width: 8),
                                              ],
                                            ),
                                            enabledBorder: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                              borderSide: BorderSide(
                                                color: Theme.of(
                                                  context,
                                                ).dividerColor,
                                                width: 1,
                                              ),
                                            ),
                                            focusedBorder: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                              borderSide: BorderSide(
                                                color: app_color,
                                                width: 1.5,
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                      itemBuilder:
                                          (context, String suggestion) {
                                            return ListTile(
                                              title: Text(
                                                suggestion,
                                                style: GoogleFonts.poppins(
                                                  fontSize: 13,
                                                ),
                                              ),
                                            );
                                          },
                                      onSelected: (String suggestion) {
                                        closeKeyboard(context);

                                        setStateDialog(() {
                                          selectedbankname = suggestion;
                                          _banknameController.text = suggestion;
                                        });
                                      },
                                      emptyBuilder: (context) => Padding(
                                        padding: EdgeInsets.all(8.0),
                                        child: Text(
                                          'No matching bank found',
                                          style: TextStyle(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),

                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 4,
                                    ),
                                    child: TextFormField(
                                      controller: chequeAmountController,
                                      keyboardType: TextInputType.number,
                                      validator: (value) {
                                        if (value!.isEmpty) {
                                          return 'Please enter amount';
                                        }
                                        if (double.parse(value) == 0) {
                                          return 'Amount should not be 0';
                                        }
                                        return null;
                                      },
                                      decoration: InputDecoration(
                                        labelText: 'Amount',
                                        hintText: '0',
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 10,
                                            ),
                                        labelStyle: GoogleFonts.poppins(
                                          fontSize: 13,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                        filled: true,
                                        fillColor:
                                            Theme.of(
                                              context,
                                            ).inputDecorationTheme.fillColor ??
                                            (Theme.of(context)
                                                    .inputDecorationTheme
                                                    .fillColor ??
                                                Theme.of(
                                                  context,
                                                ).cardColor.withOpacity(0.95)),
                                        prefixIcon: Container(
                                          margin: const EdgeInsets.all(8),
                                          width: 32,
                                          height: 32,
                                          decoration: BoxDecoration(
                                            gradient: const LinearGradient(
                                              colors: [
                                                Colors.grey,
                                                Colors.brown,
                                              ],
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          alignment: Alignment.center,
                                          child: currencySymbolWidget(
                                            currencycode,
                                            getCurrencySymbol(currencycode),
                                            GoogleFonts.poppins(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                          borderSide: BorderSide(
                                            color: Theme.of(
                                              context,
                                            ).dividerColor,
                                            width: 1,
                                          ),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                          borderSide: BorderSide(
                                            color: app_color,
                                            width: 1.5,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        SafeArea(
                          top: false,
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                            decoration: BoxDecoration(
                              color: Theme.of(context).cardColor,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.08),
                                  blurRadius: 10,
                                  offset: const Offset(0, -2),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 14,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                    onPressed: () {
                                      Navigator.of(context).pop();

                                      setState(() {
                                        selectedbankname = bankname_data.first;
                                        _banknameController.text =
                                            selectedbankname;
                                        instNoController.clear();
                                        instdate = DateTime.now();
                                        instdatestring = _dateFormat.format(
                                          instdate,
                                        );
                                        instdatetxt = formatlastsaledate(
                                          instdatestring,
                                        );
                                        instDateController.text = instdatetxt;
                                        chequeAmountController.clear();
                                      });
                                    },
                                    child: Text(
                                      'Cancel',
                                      style: GoogleFonts.poppins(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ),

                                const SizedBox(width: 12),

                                Expanded(
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: app_color,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 14,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                    onPressed: () {
                                      if (_chequedetailsFormkey.currentState !=
                                              null &&
                                          _chequedetailsFormkey.currentState!
                                              .validate()) {
                                        _chequedetailsFormkey.currentState!
                                            .save();
                                        addCheque();
                                      }
                                    },
                                    child: Text(
                                      'Add $_selectedpaymentmode',
                                      style: GoogleFonts.poppins(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
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
              );
            },
          );
        },
      );
    });
  }

  /// Thin wrapper - the notifier owns the duplicate-check/append/total
  /// recompute and the whole payment-mode-visibility cascade (including the
  /// trailing unconditional Cash-in-Hand reset); the widget keeps the
  /// duplicate-bill `AlertDialog`, the sheet pop, the `controller_totalamt`
  /// write, the focus drop and its own dialog-composition resets.
  ///
  /// One knock-on of moving the duplicate check into the notifier: it now
  /// runs before (rather than inside) the original's
  /// `if (billAmount.isNotEmpty)` guard, so an empty-amount duplicate
  /// "On Account" add would show the dialog where the original silently
  /// did nothing. Unreachable in practice - the Add Bill form's own
  /// validator rejects an empty amount before this is ever called.
  void addBill() {
    final billAmount = billAmountController.text;
    final billName = _selectedbill;
    final billNo = billNoController.text;

    String dueDateString = '';
    if (billName == "New Ref" || billName == "Agst Ref") {
      String billDueDateinDaysString = _billduedateController.text;
      if (billDueDateinDaysString.isNotEmpty) {
        int billDueDateinDaysint = int.parse(billDueDateinDaysString);

        DateTime currentDate = DateTime.now();
        DateTime finalDate = currentDate.add(
          Duration(days: billDueDateinDaysint),
        );
        dueDateString = DateFormat('yyyyMMdd').format(finalDate);
      } else {
        DateTime currentDate = DateTime.now();
        DateTime finalDate = currentDate;
        dueDateString = DateFormat('yyyyMMdd').format(finalDate);
      }
    }

    final AddBillOutcome outcome = _notifier.addBill(
      billAmountText: billAmount,
      billName: billName,
      billNo: billNo,
      dueDateString: dueDateString,
    );

    if (outcome == AddBillOutcome.duplicateOnAccount) {
      // Show message that the bill already exists
      showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text("Duplicate Bill"),
            content: Text("A bill with the name 'On Account' already exists."),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: Text("OK"),
              ),
            ],
          );
        },
      );
      return; // Exit the function without adding the bill
    }

    if (outcome == AddBillOutcome.added) {
      Navigator.of(context).pop();
      controller_totalamt.text = _s.formattedTotalBillAmount;

      // Reset selected bill and visibility of due date and bill number
      setState(() {
        _selectedbill = billsdata.first;
        isVisibleDueDate =
            (_selectedbill == 'New Ref' || _selectedbill == "Agst Ref");
        isVisibleBillNo =
            (_selectedbill == "Agst Ref" || _selectedbill == 'New Ref');
      });

      // Clear input fields
      billAmountController.clear();
      _billduedateController.clear();
    }

    if (isSelectedBankCashInHand) {
      FocusManager.instance.primaryFocus?.unfocus();
    }
  } // add bill function

  /// Thin wrapper - the notifier owns the validation cascade and the
  /// append/total recompute, returning which of the original's five
  /// `AlertDialog` branches (or the success path) applies; the widget shows
  /// that dialog / pops the sheet and resets its own dialog-composition
  /// controllers, exactly as the original's second `setState` did.
  void addCheque() {
    final instNo = instNoController.text;
    final instDate = instdate;
    final bankName = selectedbankname;
    final chequeAmount = chequeAmountController.text;
    final paymentMode = _selectedpaymentmode;

    void showChequeAlert(String message) {
      showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text("Alert"),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: Text("OK", style: GoogleFonts.poppins(color: app_color)),
              ),
            ],
          );
        },
      );
    }

    final AddChequeOutcome outcome = _notifier.addCheque(
      instNo: instNo,
      instDate: instDate,
      bankName: bankName,
      chequeAmountText: chequeAmount,
      paymentMode: paymentMode,
    );

    switch (outcome) {
      case AddChequeOutcome.added:
        Navigator.of(context).pop();

        // Reset the Add-Cheque sheet's own fields back to their defaults
        setState(() {
          instNoController.clear();
          instdate = DateTime.now();
          instdatestring = _dateFormat.format(instdate);
          instdatetxt = formatlastsaledate(instdatestring);
          instDateController.text = instdatetxt;
          selectedbankname = bankname_data.first;
          _banknameController.text = selectedbankname;
          chequeAmountController.clear();
        });
      case AddChequeOutcome.exceedsRemaining:
        showChequeAlert(
          "Entered $_selectedpaymentmode amount exceeds remaining total amount",
        );
      case AddChequeOutcome.duplicateInstNo:
        showChequeAlert("A cheque with the inst no '$instNo' already exists.");
      case AddChequeOutcome.noBillsYet:
        showChequeAlert("First add bills then proceed for payment details");
      case AddChequeOutcome.chequeAlreadyFullyAllocated:
        showChequeAlert("Cheques for the total amount already added");
      case AddChequeOutcome.exceedsTotal:
        showChequeAlert(
          "Entered $_selectedpaymentmode amount should not be greater than total amount",
        );
    }
  } // add cheque function

  /// Mirrors `sales_order_registration_notifier.dart`'s widget: the
  /// notifier is constructed (kicking off its own `_init()` - prefs load +
  /// `loadData()`) the first time it's read, here. `build()`'s own
  /// `!_isInitialDataLoaded` skeleton gate (unchanged from the original)
  /// handles showing/hiding the loading state as the notifier's state
  /// changes; this only clears/seeds this screen's own controllers and
  /// loads the raw `SharedPreferences` handle the two widget-side prefs
  /// reads still need (see the `prefs` field's comment).
  Future<void> _initSharedPreferences() async {
    billAmountController.clear();

    instdate = DateTime.now();
    instdatestring = _dateFormat.format(instdate);
    instdatetxt = formatlastsaledate(instdatestring);
    instDateController.text = instdatetxt;

    _billduedateController.clear();

    controller_totalamt.text = 0.toString();

    // Trigger provider creation (and its _init()) eagerly, matching the
    // original's initState-time kickoff rather than waiting for build().
    _notifier;

    final loadedPrefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      prefs = loadedPrefs;
    });
  }

  /// Seeds the controllers/dialog-composition fields that used to be filled
  /// inline by `_initSharedPreferences`/`loadData`'s own `setState`, once
  /// the notifier's initial load resolves - plus surfaces that load's error
  /// (the original `showAppMessage`d it from inside `loadData` itself).
  void _onInitialDataLoaded() {
    final error = _notifier.consumeInitError();
    if (error != null && mounted) {
      showAppMessage(context, error);
    }

    setState(() {
      selectedbankname = bankname_data.isNotEmpty ? bankname_data.first : '';
      _banknameController.text = selectedbankname;
      _bankcashnameController.text = _selectedbankcashname != null
          ? _selectedbankcashname!['name']!
          : "";
    });

    _dateController.text = receiptdatetxt;
    controller_totalamt.text = _s.formattedTotalBillAmount;
    _vchnoController.text = _notifier.generateNextVchNo(vchnos);
  }

  Future<void> _selectDateRangeVchNo(BuildContext context) async {
    final initialDateRange = DateTimeRange(
      start: yearStartDate,
      end: yearEndDate,
    );

    DateTimeRange? selectedDateRange = await showDateRangePicker(
      context: context,
      initialDateRange: initialDateRange,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
      builder: (BuildContext context, Widget? child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: app_color, // main accent color
              onPrimary: Colors.white,
              surface: Theme.of(context).colorScheme.surface,
              onSurface: Theme.of(context).colorScheme.onSurface,
            ),
            datePickerTheme: DatePickerThemeData(
              rangeSelectionBackgroundColor: app_color.withOpacity(
                0.15,
              ), // 🔹 light shade of your app_color
              rangeSelectionOverlayColor: MaterialStatePropertyAll(
                app_color.withOpacity(0.15),
              ),
            ),
          ),
          child: child!,
        );
      },
    );

    if (selectedDateRange != null && selectedDateRange != initialDateRange) {
      _notifier.setVchNoDateRange(
        selectedDateRange.start,
        selectedDateRange.end,
      );

      fetchvchnos(_selectedvchtypename);
    }
  }

  /// Backed by tally-api's `GET .../voucher-entries/voucher-numbers` (see
  /// `VoucherEntryRepository.voucherNumbers`'s doc-comment) - unions this
  /// app's own draft `VoucherEntry` numbers with the real Tally-synced
  /// `Voucher.number`s for this vchtype/date-range. Thin wrapper around the
  /// notifier's `fetchVchNos`; the `_vchnoController.text` write stays here
  /// and, matching the original (which computed/wrote it inside its own
  /// `try`), only happens when the fetch itself didn't fail. The field
  /// stays exactly as user-editable/lockable as before (see
  /// canEditVoucherNo further down).
  Future<void> fetchvchnos(String vchname) async {
    final String? error = await _notifier.fetchVchNos(vchname);

    if (!mounted) return;

    if (error != null) {
      showAppMessage(context, error);
      return;
    }

    // GENERATE NEXT
    _vchnoController.text = _notifier.generateNextVchNo(vchnos);
  }

  @override
  void initState() {
    super.initState();
    _initSharedPreferences();
    // Once the notifier's initial `loadData()` resolves, seed this screen's
    // own controllers/dialog-composition fields from the freshly-loaded
    // data - the original did this inline inside `loadData()`'s own
    // `setState`.
    ref.listenManual<ReceiptRegistrationState>(
      receiptRegistrationNotifierProvider,
      (previous, next) {
        if (next.isInitialDataLoaded &&
            previous?.isInitialDataLoaded != true) {
          _onInitialDataLoaded();
        }
      },
    );
  }

  // Skeleton stand-in for the entry form while the initial dropdown/lookup
  // data (parties, ledgers, items, locations, etc.) is being fetched -
  // replaces the old full-page spinner so the loading state mirrors the
  // shape of the form (label + input pairs) instead of a blank centered spinner.
  Widget _buildSkeletonForm() {
    return ShimmerLoading(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int i = 0; i < 6; i++) ...[
              const ShimmerBox(height: 13, width: 110),
              const SizedBox(height: 8),
              const ShimmerBox(height: 46, borderRadius: 12),
              const SizedBox(height: 18),
            ],
            const ShimmerBox(height: 46, borderRadius: 12),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(receiptRegistrationNotifierProvider);
    final vm = _s;
    final _isInitialDataLoaded = vm.isInitialDataLoaded;
    final _isLoading = vm.isLoading;
    final int? decimal = vm.decimal;
    final currencycode = vm.currencyCode;
    final SecuritybtnAcessHolder = vm.secBtnAccessHolder;
    final vchtypenamedata = vm.vchTypeNameData;
    final partydata = vm.partyData;
    final bankcashname_data = vm.bankCashNameData;
    final paymentmode_data = vm.paymentModeData;
    final bills = vm.bills;
    final cheque = vm.cheque;
    final errorMessageVchNo = vm.errorMessageVchNo;
    final _selectedvchtypename = vm.selectedVchTypeName;
    final _selectedpaymentmode = vm.selectedPaymentMode;
    final isVoucherTypeLocked = vm.isVoucherTypeLocked;
    final isBankCashLedgerLocked = vm.isBankCashLedgerLocked;
    final isPaymentModeVisible = vm.isPaymentModeVisible;
    final isChequeVisible = vm.isChequeVisible;

    if (!_isInitialDataLoaded) {
      return Scaffold(
        bottomNavigationBar: const AppBottomNav(
          activeTab: AppBottomNavTab.entries,
          activeEntryType: AppEntryType.receipt,
        ),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        key: _scaffoldKey,
        appBar: entryAppBar(
          context: context,
          title: "New Receipt Entry",
          onBack: () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => PendingReceiptEntry()),
            );
          },
        ),
        body: _buildSkeletonForm(),
      );
    }

    final NumberFormat currencyFormat = NumberFormat("#,##0.${'0' * decimal!}");
    final bool canEditVoucherNo =
        SecuritybtnAcessHolder.toString().toLowerCase() == 'true';

    return Scaffold(
      bottomNavigationBar: const AppBottomNav(
        activeTab: AppBottomNavTab.entries,
        activeEntryType: AppEntryType.receipt,
      ),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      key: _scaffoldKey,
      appBar: entryAppBar(
        context: context,
        title: "New Receipt Entry",
        onBack: () {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => PendingReceiptEntry()),
          );
        },
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {
          closeKeyboard(context);
        },
        child: WillPopScope(
          onWillPop: () async {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => PendingReceiptEntry()),
            );
            return false;
          },
          child: Stack(
            children: [
              ListView(
                children: [
                  Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        const SizedBox(height: 8),

                        // ── Entry Details Section ──
                        EntrySection(
                          icon: Icons.receipt_long_outlined,
                          title: "Entry Details",
                          iconGradient: [
                            app_color,
                            app_color.withValues(alpha: 0.7),
                          ],
                          children: [
                            // Date
                            EntryFormField(
                              label: "Date",
                              icon: Icons.calendar_today,
                              iconGradient: [
                                app_color,
                                app_color.withValues(alpha: 0.7),
                              ],
                              controller: _dateController,
                              readOnly: true,
                              enabled: !isUniGasSerial,
                              suffixIcon: isUniGasSerial
                                  ? Icon(
                                      Icons.lock,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    )
                                  : null,
                              onTap: isUniGasSerial
                                  ? null
                                  : () {
                                      _selectreceiptDate(context);
                                    },
                            ),

                            // Voucher No
                            EntryFormField(
                              label: "Voucher No.",
                              icon: canEditVoucherNo
                                  ? Icons.edit_note_rounded
                                  : Icons.confirmation_num_outlined,
                              iconGradient: canEditVoucherNo
                                  ? [Colors.teal, Colors.tealAccent]
                                  : [
                                      Colors.deepOrangeAccent,
                                      Colors.orangeAccent,
                                    ],
                              controller: _vchnoController,
                              readOnly: !canEditVoucherNo,
                              enabled: canEditVoucherNo,
                              onChanged: canEditVoucherNo
                                  ? (value) {
                                      checkVchNoExistence(value.trim());
                                    }
                                  : null,
                              keyboardType: TextInputType.text,
                              errorText: errorMessageVchNo.isNotEmpty
                                  ? errorMessageVchNo
                                  : null,
                              suffixIcon: canEditVoucherNo
                                  ? IconButton(
                                      icon: Icon(
                                        isVchEditable
                                            ? Icons.lock_open
                                            : Icons.edit,
                                        color: app_color,
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          isVchEditable = !isVchEditable;
                                        });
                                      },
                                    )
                                  : Icon(
                                      Icons.lock_outline,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                      size: 20,
                                    ),
                            ),

                            // Info Banner
                            const EntryInfoBanner(
                              text:
                                  'Duplicate voucher numbers in Tally will trigger automatic assignment of a new number.',
                            ),

                            // Voucher Type Dropdown
                            EntryDropdownField<String>(
                              label: "Voucher Type Name",
                              icon: Icons.receipt_long_outlined,
                              iconGradient: [
                                Colors.purpleAccent,
                                Colors.deepPurple,
                              ],
                              value: _selectedvchtypename.isNotEmpty
                                  ? _selectedvchtypename
                                  : null,
                              locked: isVoucherTypeLocked,
                              hintText: isVoucherTypeLocked
                                  ? "Voucher Type Locked"
                                  : "Voucher Type Name",
                              items: vchtypenamedata.map((item) {
                                return DropdownMenuItem<String>(
                                  value: item,
                                  child: Text(
                                    item,
                                    style: GoogleFonts.poppins(
                                      fontSize: 13,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface,
                                    ),
                                  ),
                                );
                              }).toList(),
                              onChanged: (value) {
                                if (value == null) return;
                                _notifier.setSelectedVchType(value);
                                fetchvchnos(value);
                              },
                            ),

                            // Party TypeAheadField
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 6,
                              ),
                              child: SizedBox(
                                width: MediaQuery.of(context).size.width,
                                child: TypeAheadField<String>(
                                  suggestionsCallback: (pattern) {
                                    return partydata.where((item) {
                                      final name = item
                                          .toString()
                                          .toLowerCase();
                                      return name.contains(
                                        pattern.toLowerCase(),
                                      );
                                    }).toList();
                                  },
                                  builder: (context, controller, focusNode) {
                                    _partyController = controller;
                                    return TextField(
                                      controller: controller,
                                      focusNode: focusNode,
                                      style: GoogleFonts.poppins(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurface,
                                      ),
                                      decoration: InputDecoration(
                                        labelText: "Party",
                                        hintText: 'Search',
                                        hintStyle: GoogleFonts.poppins(
                                          fontSize: 13,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                        labelStyle: GoogleFonts.poppins(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                        filled: true,
                                        fillColor:
                                            Theme.of(
                                              context,
                                            ).inputDecorationTheme.fillColor ??
                                            Theme.of(
                                              context,
                                            ).cardColor.withValues(alpha: 0.95),
                                        prefixIcon: Container(
                                          margin: const EdgeInsets.all(6),
                                          decoration: const BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: [
                                                Colors.purple,
                                                Colors.deepOrange,
                                              ],
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                            ),
                                            borderRadius: BorderRadius.all(
                                              Radius.circular(10),
                                            ),
                                          ),
                                          child: const Icon(
                                            Icons.person_outline,
                                            color: Colors.white,
                                            size: 20,
                                          ),
                                        ),
                                        suffixIcon: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (controller.text.isNotEmpty)
                                              GestureDetector(
                                                onTap: () {
                                                  controller.clear();
                                                  _notifier
                                                      .clearSelectedParty();
                                                },
                                                child: Icon(
                                                  Icons.close,
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                                  size: 20,
                                                ),
                                              ),
                                            const SizedBox(width: 4),
                                            Icon(
                                              Icons.arrow_drop_down,
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.onSurface,
                                            ),
                                            const SizedBox(width: 8),
                                          ],
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                          borderSide: BorderSide(
                                            color: Theme.of(
                                              context,
                                            ).dividerColor,
                                            width: 1,
                                          ),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                          borderSide: BorderSide(
                                            color: app_color,
                                            width: 1.5,
                                          ),
                                        ),
                                        errorBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                          borderSide: const BorderSide(
                                            color: Colors.redAccent,
                                            width: 1.5,
                                          ),
                                        ),
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 14,
                                              vertical: 16,
                                            ),
                                      ),
                                    );
                                  },
                                  decorationBuilder: (context, child) {
                                    return Material(
                                      elevation: 6,
                                      borderRadius: BorderRadius.circular(16),
                                      color: Theme.of(context).cardColor,
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(16),
                                        child: child,
                                      ),
                                    );
                                  },
                                  itemBuilder: (context, String suggestion) {
                                    return ListTile(
                                      title: Text(
                                        suggestion,
                                        style: GoogleFonts.poppins(
                                          fontSize: 14,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurface,
                                        ),
                                      ),
                                    );
                                  },
                                  onSelected: (String suggestion) {
                                    closeKeyboard(context);
                                    _notifier.selectParty(suggestion);
                                    _partyController.text = _selectedparty;
                                    if (showOutstandingBills &&
                                        isUniGasSerial) {
                                      fetchPartyOutstanding(suggestion);
                                    }
                                  },
                                  emptyBuilder: (context) => Padding(
                                    padding: const EdgeInsets.all(8.0),
                                    child: Text(
                                      'No matching party found',
                                      style: TextStyle(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),

                            buildOutstandingCard(),

                            // Bank / Cash Ledger TypeAheadField
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 6,
                              ),
                              child: SizedBox(
                                width: MediaQuery.of(context).size.width,
                                child: TypeAheadField<Map<String, String>>(
                                  controller: _bankcashnameController,
                                  suggestionsCallback: (pattern) async {
                                    if (isBankCashLedgerLocked) return [];
                                    return bankcashname_data
                                        .where(
                                          (item) => item['name']!
                                              .toLowerCase()
                                              .contains(pattern.toLowerCase()),
                                        )
                                        .toList();
                                  },
                                  itemBuilder: (context, suggestion) {
                                    return ListTile(
                                      title: Text(
                                        suggestion['name']!,
                                        style: GoogleFonts.poppins(
                                          fontSize: 14,
                                        ),
                                      ),
                                    );
                                  },
                                  onSelected: isBankCashLedgerLocked
                                      ? null
                                      : (suggestion) {
                                          // The notifier applies the whole
                                          // Cash-in-Hand / bank-ledger
                                          // payment-mode-visibility cascade
                                          // that used to live in these two
                                          // branches.
                                          _notifier.selectBankCashName(
                                            suggestion,
                                          );
                                          debugPrint(
                                            'cash in hand -> ${_selectedbankcashname!['type']}',
                                          );
                                          _bankcashnameController.text =
                                              suggestion['name']!;
                                          if (isSelectedBankCashInHand) {
                                            FocusManager.instance.primaryFocus
                                                ?.unfocus();
                                          }
                                        },
                                  decorationBuilder: (context, child) {
                                    return Material(
                                      elevation: 6,
                                      borderRadius: BorderRadius.circular(16),
                                      color: Theme.of(context).cardColor,
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(16),
                                        child: child,
                                      ),
                                    );
                                  },
                                  builder: (context, controller, focusNode) {
                                    return TextFormField(
                                      controller: controller,
                                      focusNode: isBankCashLedgerLocked
                                          ? AlwaysDisabledFocusNode()
                                          : focusNode,
                                      readOnly: isBankCashLedgerLocked,
                                      enabled: !isBankCashLedgerLocked,
                                      style: GoogleFonts.poppins(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: isBankCashLedgerLocked
                                            ? Theme.of(
                                                context,
                                              ).colorScheme.onSurfaceVariant
                                            : Theme.of(
                                                context,
                                              ).colorScheme.onSurface,
                                      ),
                                      decoration: InputDecoration(
                                        labelText: "Bank / Cash Ledger",
                                        labelStyle: GoogleFonts.poppins(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                        filled: true,
                                        fillColor: isBankCashLedgerLocked
                                            ? (Theme.of(context).brightness ==
                                                      Brightness.dark
                                                  ? Theme.of(context)
                                                        .colorScheme
                                                        .surfaceContainerHighest
                                                  : Colors.grey.shade100)
                                            : (Theme.of(context)
                                                      .inputDecorationTheme
                                                      .fillColor ??
                                                  Theme.of(context).cardColor
                                                      .withValues(alpha: 0.95)),
                                        prefixIcon: Container(
                                          margin: const EdgeInsets.all(6),
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: isBankCashLedgerLocked
                                                  ? [
                                                      Colors.grey,
                                                      Colors.grey.shade600,
                                                    ]
                                                  : [
                                                      app_color,
                                                      app_color.withValues(
                                                        alpha: 0.7,
                                                      ),
                                                    ],
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                          ),
                                          child: Icon(
                                            isBankCashLedgerLocked
                                                ? Icons.lock_outline
                                                : Icons
                                                      .account_balance_wallet_outlined,
                                            color: Colors.white,
                                            size: 20,
                                          ),
                                        ),
                                        suffixIcon: Icon(
                                          isBankCashLedgerLocked
                                              ? Icons.lock_outline
                                              : Icons.arrow_drop_down,
                                          color: isBankCashLedgerLocked
                                              ? Theme.of(
                                                  context,
                                                ).colorScheme.onSurfaceVariant
                                              : Theme.of(
                                                  context,
                                                ).colorScheme.onSurface,
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                          borderSide: BorderSide(
                                            color: Theme.of(
                                              context,
                                            ).dividerColor,
                                            width: 1,
                                          ),
                                        ),
                                        disabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                          borderSide: BorderSide(
                                            color: Theme.of(
                                              context,
                                            ).dividerColor,
                                            width: 1,
                                          ),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                          borderSide: BorderSide(
                                            color: app_color,
                                            width: 1.5,
                                          ),
                                        ),
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 14,
                                              vertical: 16,
                                            ),
                                      ),
                                    );
                                  },
                                  emptyBuilder: (context) => Padding(
                                    padding: const EdgeInsets.all(8.0),
                                    child: Text(
                                      'No ledger found',
                                      style: GoogleFonts.poppins(
                                        fontSize: 13,
                                        color: Colors.redAccent,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),

                        // ── Bills Section ──
                        EntrySection(
                          icon: Icons.receipt_long,
                          title: "Bills",
                          iconGradient: [Colors.blueGrey, Colors.grey],
                          trailing: GestureDetector(
                            onTap: () {
                              _selectedbill = billsdata.first;
                              if (_selectedbill == 'New Ref' ||
                                  _selectedbill == 'Agst Ref') {
                                setState(() {
                                  isVisibleDueDate = true;
                                  isVisibleBillNo = true;
                                });
                              } else {
                                setState(() {
                                  isVisibleDueDate = false;
                                  isVisibleBillNo = false;
                                });
                              }
                              billAmountController.clear();
                              billNoController.clear();
                              _billduedateController.clear();
                              closeKeyboard(context);
                              _showBillsDetailsPopup(context);
                            },
                            child: Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: const LinearGradient(
                                  colors: [Colors.orange, Colors.deepOrange],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.orange.withValues(alpha: 0.3),
                                    blurRadius: 6,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.add,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ),
                          children: [
                            ListView.builder(
                              physics: const NeverScrollableScrollPhysics(),
                              shrinkWrap: true,
                              itemCount: bills.length,
                              itemBuilder: (context, index) {
                                final bill = bills[index];
                                final bool showBillNo =
                                    (bill.billName == "Agst Ref" ||
                                        bill.billName == "New Ref") &&
                                    bill.billNo != 'null' &&
                                    bill.billNo != '';
                                return Dismissible(
                                  key: UniqueKey(),
                                  direction: DismissDirection.endToStart,
                                  background: Container(
                                    alignment: Alignment.centerRight,
                                    padding: const EdgeInsets.only(right: 24),
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [
                                          Color(0xFFFF6B6B),
                                          Color(0xFFEE5A24),
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: const Icon(
                                      Icons.delete_outline,
                                      color: Colors.white,
                                      size: 26,
                                    ),
                                  ),
                                  onDismissed: (direction) {
                                    _deleteBill(index);
                                  },
                                  child: Container(
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 4,
                                    ),
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).cardColor,
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: Theme.of(context).dividerColor,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(
                                            alpha: 0.03,
                                          ),
                                          blurRadius: 6,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Expanded(
                                              flex: 5,
                                              child: Text(
                                                bill.billName,
                                                style: GoogleFonts.poppins(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w600,
                                                  color: Theme.of(
                                                    context,
                                                  ).colorScheme.onSurface,
                                                ),
                                              ),
                                            ),
                                            Expanded(
                                              flex: 5,
                                              child: Text(
                                                "Bill No: ${showBillNo ? bill.billNo ?? "N/A" : "N/A"}",
                                                textAlign: TextAlign.end,
                                                style: GoogleFonts.poppins(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w500,
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 10),
                                        Row(
                                          children: [
                                            Container(
                                              width: 26,
                                              height: 26,
                                              decoration: const BoxDecoration(
                                                shape: BoxShape.circle,
                                                gradient: LinearGradient(
                                                  colors: [
                                                    Colors.teal,
                                                    Colors.cyan,
                                                  ],
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                ),
                                              ),
                                              alignment: Alignment.center,
                                              child: currencySymbolWidget(
                                                currencycode,
                                                getCurrencySymbol(
                                                  currencycode,
                                                ),
                                                GoogleFonts.poppins(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 11,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              currencyFormat.format(
                                                bill.billAmount,
                                              ),
                                              style: GoogleFonts.poppins(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w600,
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.onSurface,
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

                        // ── Payment Mode Section ──
                        Visibility(
                          visible:
                              isPaymentModeVisible && !isSelectedBankCashInHand,
                          child: EntrySection(
                            icon: Icons.payment_outlined,
                            title: "Payment Mode",
                            iconGradient: [Colors.teal, Colors.indigo],
                            children: [
                              EntryDropdownField<String>(
                                label: "Payment Mode",
                                icon: Icons.payment_outlined,
                                iconGradient: [Colors.teal, Colors.indigo],
                                value: _selectedpaymentmode,
                                hintText: 'Select Payment Mode',
                                items: paymentmode_data.map((item) {
                                  return DropdownMenuItem<String>(
                                    value: item.toString(),
                                    child: Text(
                                      item.toString(),
                                      style: GoogleFonts.poppins(
                                        fontSize: 14,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurface,
                                      ),
                                    ),
                                  );
                                }).toList(),
                                onChanged: (value) async {
                                  // The notifier applies the selection plus
                                  // (for the empty-bills case) the
                                  // cheque-list/visibility reset, and tells
                                  // us which branch ran; the widget keeps
                                  // the message and its own dialog-field
                                  // resets.
                                  final bool billsEmpty = _notifier
                                      .setSelectedPaymentMode(value!);
                                  if (billsEmpty) {
                                    showAppMessage(
                                      context,
                                      'At least add 1 bill',
                                    );
                                    setState(() {
                                      selectedbankname = bankname_data.first;
                                      _banknameController.text =
                                          selectedbankname;
                                      instNoController.clear();
                                      instdate = DateTime.now();
                                      instdatestring = _dateFormat.format(
                                        instdate,
                                      );
                                      instdatetxt = formatlastsaledate(
                                        instdatestring,
                                      );
                                      instDateController.text = instdatetxt;
                                      chequeAmountController.clear();
                                    });
                                  }
                                },
                              ),
                            ],
                          ),
                        ),

                        // ── Cheque / Instrument Section ──
                        Visibility(
                          visible: isChequeVisible,
                          child: EntrySection(
                            icon: Icons.payment,
                            title: _selectedpaymentmode,
                            iconGradient: [
                              Colors.purpleAccent,
                              Colors.deepPurple,
                            ],
                            trailing: GestureDetector(
                              onTap: () => _showChequeDetailsPopup(context),
                              child: Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: const LinearGradient(
                                    colors: [
                                      Colors.orange,
                                      Colors.deepOrangeAccent,
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.orange.withValues(
                                        alpha: 0.3,
                                      ),
                                      blurRadius: 6,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.add,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            ),
                            children: [
                              ListView.builder(
                                physics: const NeverScrollableScrollPhysics(),
                                shrinkWrap: true,
                                itemCount: cheque.length,
                                itemBuilder: (context, index) {
                                  final cheques = cheque[index];
                                  final bool showInstNo =
                                      !(cheques.instno == "null" ||
                                          cheques.instno.isEmpty ||
                                          cheques.instno == "");
                                  return Dismissible(
                                    key: UniqueKey(),
                                    direction: DismissDirection.endToStart,
                                    background: Container(
                                      alignment: Alignment.centerRight,
                                      padding: const EdgeInsets.only(right: 24),
                                      margin: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(
                                          colors: [
                                            Color(0xFFFF6B6B),
                                            Color(0xFFEE5A24),
                                          ],
                                        ),
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: const Icon(
                                        Icons.delete_outline,
                                        color: Colors.white,
                                        size: 26,
                                      ),
                                    ),
                                    onDismissed: (direction) {
                                      _notifier.deleteCheque(index);
                                    },
                                    child: Container(
                                      margin: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 4,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 12,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context).cardColor,
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color:
                                              Theme.of(context).brightness ==
                                                  Brightness.dark
                                              ? Colors.white.withValues(
                                                  alpha: 0.08,
                                                )
                                              : Colors.grey.shade200,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(
                                              alpha: 0.03,
                                            ),
                                            blurRadius: 6,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Row(
                                                children: [
                                                  const Icon(
                                                    Icons
                                                        .confirmation_num_outlined,
                                                    color: Colors.deepPurple,
                                                    size: 18,
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Text(
                                                    "Inst No: ${showInstNo ? cheques.instno : "N/A"}",
                                                    style: GoogleFonts.poppins(
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                      color: Theme.of(
                                                        context,
                                                      ).colorScheme.onSurface,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              Row(
                                                children: [
                                                  const Icon(
                                                    Icons.date_range,
                                                    color: Colors.teal,
                                                    size: 18,
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Text(
                                                    formatdate(
                                                      cheques.instdate ?? '',
                                                    ),
                                                    style: GoogleFonts.poppins(
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                      color: Theme.of(
                                                        context,
                                                      ).colorScheme.onSurface,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Row(
                                            children: [
                                              Container(
                                                width: 26,
                                                height: 26,
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  gradient: LinearGradient(
                                                    colors: [
                                                      Colors
                                                          .deepPurple
                                                          .shade400,
                                                      Colors.blue.shade600,
                                                    ],
                                                    begin: Alignment.topLeft,
                                                    end: Alignment.bottomRight,
                                                  ),
                                                ),
                                                child: Center(
                                                  child: currencySymbolWidget(
                                                    currencycode,
                                                    getCurrencySymbol(
                                                      currencycode,
                                                    ),
                                                    GoogleFonts.poppins(
                                                      color: Colors.white,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 11,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                currencyFormat.format(
                                                  cheques.chequeAmount,
                                                ),
                                                style: GoogleFonts.poppins(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w600,
                                                  color: Theme.of(
                                                    context,
                                                  ).colorScheme.onSurface,
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

                        // ── Receiver Information Section (UniGas only) ──
                        if (isUniGasSerial)
                          EntrySection(
                            icon: Icons.assignment_ind_outlined,
                            title: "Receiver Information",
                            iconGradient: [Colors.teal, Colors.tealAccent],
                            children: [
                              EntryFormField(
                                label: "Receiver Name *",
                                icon: Icons.person_outline,
                                iconGradient: [Colors.teal, Colors.tealAccent],
                                controller: receiverNameController,
                              ),
                              EntryFormField(
                                label: "Receiver Mobile",
                                icon: Icons.phone_outlined,
                                iconGradient: [Colors.blue, Colors.blueAccent],
                                controller: receiverMobileController,
                                keyboardType: TextInputType.phone,
                                validator: (value) => null,
                              ),
                              ReceiverSignatureTile(
                                signatureBytes: receiverSignatureBytes,
                                onCaptured: (bytes) => setState(() {
                                  receiverSignatureBytes = bytes;
                                }),
                              ),
                            ],
                          ),

                        // ── Narration Section ──
                        EntrySection(
                          icon: Icons.notes_rounded,
                          title: "Narration",
                          iconGradient: [Colors.deepPurple, Colors.indigo],
                          children: [
                            EntryFormField(
                              label: "Narration",
                              icon: Icons.notes_rounded,
                              iconGradient: [Colors.deepPurple, Colors.indigo],
                              controller: controller_narration,
                              validator: (value) => null,
                              maxLines: 3,
                            ),
                          ],
                        ),

                        // ── Total Amount ──
                        EntryTotalBar(
                          label: "Total Amount",
                          value: controller_totalamt.text.isNotEmpty
                              ? controller_totalamt.text
                              : "0.00",
                          currencySymbol: getCurrencySymbol(currencycode),
                          currencyCode: currencycode,
                        ),

                        // ── Save Button ──
                        EntrySaveButton(
                          label: "Save",
                          onPressed: errorMessageVchNo.isNotEmpty
                              ? null
                              : () {
                                  if (_formKey.currentState != null &&
                                      _formKey.currentState!.validate()) {
                                    _formKey.currentState!.save();
                                    saveEntry();
                                  }
                                },
                        ),

                        const SizedBox(height: 30),
                      ],
                    ),
                  ),
                ],
              ),
              Visibility(
                visible: _isLoading,
                child: Center(child: AppLogoLoader()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AlwaysDisabledFocusNode extends FocusNode {
  @override
  bool get hasFocus => false;
}
