import 'dart:convert';
import 'dart:io';
import 'package:FincoreGo/Items.dart';
import 'package:FincoreGo/PendingReceiptEntry.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'constants.dart';
import 'package:FincoreGo/widgets/app_bottom_nav.dart';
import 'widgets/entry_widgets.dart';

class ReceiptRegistration extends StatefulWidget {
  const ReceiptRegistration({Key? key}) : super(key: key);
  @override
  _ReceiptRegistrationPageState createState() =>
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

class _ReceiptRegistrationPageState extends State<ReceiptRegistration>
    with TickerProviderStateMixin {
  bool isDashEnable = true,
      isRolesVisible = true,
      isUserEnable = true,
      isUserVisible = true,
      isRolesEnable = true,
      _isLoading = true,
      isVisibleNoUserFound = false;

  bool _isInitialDataLoaded = false;

  late DateTime now = DateTime.now();

  bool showOutstandingBills = true; // temporary hide

  bool isVchEditable = false; // state variable

  // Current year start date
  late DateTime yearStartDate = DateTime(now.year, 1, 1);

  // Current year end date
  late DateTime yearEndDate = DateTime(now.year, 12, 31);

  TextEditingController _partyController = TextEditingController();

  TextEditingController _bankcashnameController = TextEditingController();

  final TextEditingController _vchnoController = TextEditingController();

  TextEditingController billNoController = TextEditingController();

  TextEditingController _banknameController = TextEditingController();

  bool get isSelectedBankCashInHand {
    final type = _selectedbankcashname?['type']
        ?.toString()
        .trim()
        .toLowerCase()
        .replaceAll('-', ' ');

    return type == 'cash in hand';
  }

  bool get isVanSalesUser =>
      serial_no != null && vanSalesSerialNo.contains(serial_no);

  late final TextEditingController controller_narration =
      TextEditingController();

  final FocusNode _textFieldFocusNodeNarration = FocusNode();

  double totalBillAmount = 0;

  double totalChequeAmount = 0;

  int visibleOutstandingBillCount = 5;

  bool isVoucherTypeLocked = false;
  bool isBankCashLedgerLocked = false;

  late List<String> vchtypenamedata = [];

  bool isOutstandingLoading = false;
  String outstandingError = "";
  double openingOutstanding = 0.0;
  double totalOutstanding = 0.0;
  List<dynamic> outstandingBills = [];
  bool showOutstandingCard = false;
  bool isOutstandingExpanded = false;

  bool get isUniGasSerial {
    final currentSerial = serial_no?.trim() ?? '';

    // 👇 put only that one serial here

    return currentSerial == uniGasSerialNumber;
  }

  void removeOutstandingBillFromReceipt(Map<String, dynamic> bill) {
    final String billNo = bill["billno"]?.toString() ?? "";

    setState(() {
      bills.removeWhere((b) => b.billNo == billNo && b.billName == "Agst Ref");

      totalBillAmount = bills.fold(
        0.0,
        (double previousAmount, Bills bill) => previousAmount + bill.billAmount,
      );

      roundedtotalBillAmount = double.parse(
        totalBillAmount.toStringAsFixed(decimal!),
      );

      NumberFormat formatter = NumberFormat('#,##0.${'0' * decimal!}', 'en_US');

      controller_totalamt.text = formatter
          .format(roundedtotalBillAmount)
          .toString();

      isVisibleBillHeading = bills.isNotEmpty;
    });

    // showAppMessage(context, "Bill removed from receipt");
  }

  String getBillDueDays(dynamic bill) {
    final String billDateStr = bill["billdate"]?.toString() ?? "";
    final String dueDateStr = bill["duedate"]?.toString() ?? "";

    if (billDateStr.length != 8 || dueDateStr.length != 8) {
      return "";
    }

    try {
      final DateTime billDate = DateTime.parse(billDateStr);
      final DateTime dueDate = DateTime.parse(dueDateStr);

      final int days = dueDate.difference(billDate).inDays;

      return days < 0 ? "" : days.toString();
    } catch (e) {
      return "";
    }
  }

  void addOutstandingBillToReceipt(Map<String, dynamic> bill) {
    final String billNo = bill["billno"]?.toString() ?? "";
    final double amount =
        double.tryParse(bill["outstanding"].toString())?.abs() ?? 0.0;

    if (billNo.isEmpty || amount <= 0) return;

    final bool alreadyAdded = bills.any(
      (b) => b.billNo == billNo && b.billName == "Agst Ref",
    );

    if (alreadyAdded) {
      showAppMessage(context, "Bill already added", isError: false);
      return;
    }

    setState(() {
      bills.add(
        Bills(
          billName: "Agst Ref",
          billAmount: amount,
          billNo: billNo,
          billDueDate: getBillDueDays(bill),
        ),
      );

      totalBillAmount = bills.fold(0.0, (double previousAmount, Bills bill) {
        return previousAmount + bill.billAmount;
      });

      roundedtotalBillAmount = double.parse(
        totalBillAmount.toStringAsFixed(decimal!),
      );

      NumberFormat formatter = NumberFormat('#,##0.${'0' * decimal!}', 'en_US');

      controller_totalamt.text = formatter
          .format(roundedtotalBillAmount)
          .toString();

      isVisibleBillHeading = bills.isNotEmpty;

      if (_selectedbankcashname != null && !isSelectedBankCashInHand) {
        isPaymentModeVisible = true;
        isChequeVisible = true;
      }
    });

    // showAppMessage(context, "Bill added to receipt", isError: false);
  }

  Future<void> fetchPartyOutstanding(String ledgerName) async {
    closeKeyboard(context);
    if (ledgerName.trim().isEmpty) return;

    setState(() {
      isOutstandingLoading = true;
      outstandingError = "";
      showOutstandingCard = true;
      openingOutstanding = 0.0;
      totalOutstanding = 0.0;
      outstandingBills = [];
      isOutstandingExpanded = false;
    });

    try {
      final url = Uri.parse(HttpURL_fetchoutstanding!);

      final headers = {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

      final body = jsonEncode({
        "startdate":
            int.tryParse(prefs.getString('startfrom') ?? '') ??
            int.parse(_dateFormat.format(yearStartDate)),
        "enddate": int.parse(receiptdatestring),
        "orderby": "billdate",
        "isDebit": true,
        "ledger": ledgerName,
      });

      final response = await http.post(url, headers: headers, body: body);
      print('outstanding -> ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        final values = data["values"] ?? [];

        double billsOutstanding = 0.0;

        for (var item in values) {
          billsOutstanding +=
              double.tryParse(item["outstanding"].toString()) ?? 0.0;
        }

        setState(() {
          openingOutstanding =
              double.tryParse(data["opening"].toString()) ?? 0.0;
          outstandingBills = values;
          // totalOutstanding = openingOutstanding + billsOutstanding;
          totalOutstanding = billsOutstanding;
          visibleOutstandingBillCount = 5;
        });
      } else {
        setState(() {
          outstandingError = "Unable to load outstanding";
        });
      }
    } catch (e) {
      setState(() {
        outstandingError = "Outstanding fetch failed";
      });
    } finally {
      setState(() {
        isOutstandingLoading = false;
      });
    }
  }

  Widget buildOutstandingCard() {
    if (!showOutstandingBills) return const SizedBox.shrink();
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
                setState(() {
                  isOutstandingExpanded = !isOutstandingExpanded;
                });
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
                                setState(() {
                                  if (visibleOutstandingBillCount >=
                                      totalBills) {
                                    visibleOutstandingBillCount = 5;
                                  } else {
                                    visibleOutstandingBillCount += 5;
                                    if (visibleOutstandingBillCount >
                                        totalBills) {
                                      visibleOutstandingBillCount = totalBills;
                                    }
                                  }
                                });
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

  void _deleteBill(int index) {
    setState(() {
      bills.removeAt(index);
      // Calculate the total price of items
      totalBillAmount = bills.fold(0.0, (double previousAmount, Bills bill) {
        return previousAmount + bill.billAmount;
      });

      roundedtotalBillAmount = double.parse(
        totalBillAmount.toStringAsFixed(decimal!),
      );
      NumberFormat formatter = NumberFormat('#,##0.${'0' * decimal!}', 'en_US');
      String formattedtotal = formatter.format(roundedtotalBillAmount);
      controller_totalamt.text = formattedtotal.toString();

      if (bills.isEmpty) {
        isVisibleBillHeading = false;
        isChequeVisible = false;
        _selectedpaymentmode = paymentmode_data.isNotEmpty ? paymentmode_data.first : '';
        cheque.clear();
        updateChequeAmount();
        instNoController.clear();
        selectedbankname = bankname_data.first;
        _banknameController.text = selectedbankname;
        chequeAmountController.clear();
        instdate = DateTime.now();
        instdatestring = _dateFormat.format(instdate);
        instdatetxt = formatlastsaledate(instdatestring);
        instDateController.text = instdatetxt;
        isVisibleChequeHeading = false;
        isPaymentModeVisible = false;
      } else {
        isVisibleBillHeading = true;
        if (_selectedbankcashname != null && isSelectedBankCashInHand) {
          isPaymentModeVisible = false;
          _selectedpaymentmode = paymentmode_data.isNotEmpty ? paymentmode_data.first : '';
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
              _selectedpaymentmode = paymentmode_data.isNotEmpty ? paymentmode_data.first : '';
              cheque.clear();
              updateChequeAmount();

              isVisibleChequeHeading = false;
              isChequeVisible = true;
            }
          } else {
            isPaymentModeVisible = true;
            _selectedpaymentmode = paymentmode_data.isNotEmpty ? paymentmode_data.first : '';
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

  Map<String, dynamic> jsonEntryData = {
    "DATE": "",
    "VOUCHERTYPENAME": "",
    "PARTYLEDGERNAME": "",
    "VOUCHERNUMBER": "",
    "ENTEREDBY": "",
    "NARRATION": "",
    "ALLLEDGERENTRIES.LIST": [],
  };

  bool isVisibleBillHeading = false,
      isVisibleChequeHeading = false,
      isChequeVisible = false;

  final _formKey = GlobalKey<FormState>();

  late String _selectedvchtypename = '';

  String selectedbankname = '';

  String errorMessageVchNo = '';

  List<String> vchnos = [];

  void checkVchNoExistence(String vchNo) {
    if (vchNo.isEmpty || vchNo == '') {
      setState(() {
        errorMessageVchNo = 'Voucher No. cannot be empty';
      });
    } else {
      if (vchnos.contains(vchNo)) {
        setState(() {
          errorMessageVchNo =
              'Voucher no: $vchNo against $_selectedvchtypename already exists';
        });
      } else {
        setState(() {
          errorMessageVchNo = '';
        });
      }
    }
  }

  bool isInstNoRepeated(String instNo, List<Cheque> cheques) {
    if (instNo.isNotEmpty) {
      for (var cheque in cheques) {
        if (cheque.instno == instNo) {
          return true; // Found a match, instno is repeated
        }
      }
    }
    return false; // No match found
  }

  GlobalKey<FormState> _billsFormkey = GlobalKey<FormState>();

  GlobalKey<FormState> _chequedetailsFormkey = GlobalKey<FormState>();

  double roundedtotalVatAmount = 0.0;

  double roundedtotalBillAmount = 0.0;

  double roundedtotalChequeAmount = 0.0;

  List<Map<String, String>> bankcashname_data = [];

  List<String> paymentmode_data = [];

  bool isPaymentModeVisible = false;

  int? decimal = 2;

  late List<String> partydata = [];

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

  List<String> billsdata = ['On Account', 'New Ref', 'Agst Ref'];

  String user_email_fetched = "", token = '';

  bool isVisibleDueDate = false, isVisibleBillNo = false;

  String name = "",
      email = "",
      receiptdatestring = '',
      receiptdatetxt = '',
      instdatestring = '',
      instdatetxt = '',
      currencycode = '',
      billduedatestring = '',
      billduedatetxt = '';

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  late SharedPreferences prefs;

  dynamic _selectedbill, _selectedparty;

  Map<String, String>? _selectedbankcashname;

  late dynamic _selectedpaymentmode = '';

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
                          // back open right after reset.
                          FocusManager.instance.primaryFocus?.unfocus();
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
                            receiptdatetxt = formatlastsaledate(
                              receiptdatestring,
                            );
                            _dateController.text = receiptdatetxt;

                            if (serial_no != uniGasSerialNumber) {
                              _selectedvchtypename = vchtypenamedata.isNotEmpty ? vchtypenamedata.first : '';
                            }
                            fetchvchnos(_selectedvchtypename);

                            if (serial_no != uniGasSerialNumber) {
                              _selectedbankcashname = null;
                              _bankcashnameController.text = "";
                            }

                            bills.clear();
                            cheque.clear();

                            updateChequeAmount();

                            totalBillAmount = bills.fold(0.0, (
                              double previousAmount,
                              Bills bill,
                            ) {
                              return previousAmount + bill.billAmount;
                            });

                            roundedtotalBillAmount = double.parse(
                              totalBillAmount.toStringAsFixed(decimal!),
                            );

                            NumberFormat formatter = NumberFormat(
                              '#,##0.${'0' * decimal!}',
                              'en_US',
                            );

                            controller_totalamt.text = formatter.format(
                              roundedtotalBillAmount,
                            );

                            isVisibleBillHeading = bills.isNotEmpty;
                            isVisibleChequeHeading = cheque.isNotEmpty;
                          });

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
    // suggestions overlay back open right after reset.
    FocusManager.instance.primaryFocus?.unfocus();

    setState(() {
      _selectedparty = null;
      showOutstandingCard = false;
      totalOutstanding = 0.0;
      outstandingError = "";
      _selectedparty = null;
      _partyController.clear();

      isChequeVisible = false;

      openingOutstanding = 0.0;
      outstandingBills.clear();

      controller_narration.clear();
      _textFieldFocusNodeNarration.unfocus(); // Unfocus the TextField

      receiptdate = DateTime.now();
      receiptdatestring = _dateFormat.format(receiptdate);
      receiptdatetxt = formatlastsaledate(receiptdatestring);
      _dateController.text = receiptdatetxt;
      if (serial_no != uniGasSerialNumber) {
        _selectedvchtypename = vchtypenamedata.isNotEmpty ? vchtypenamedata.first : '';
      }

      fetchvchnos(_selectedvchtypename);

      if (serial_no != uniGasSerialNumber) {
        _selectedbankcashname = null;
        _bankcashnameController.text = _selectedbankcashname != null
            ? _selectedbankcashname!['name']!
            : "";
      }

      bills.clear();
      cheque.clear();

      updateChequeAmount();

      totalBillAmount = bills.fold(0.0, (double previousAmount, Bills bill) {
        return previousAmount + bill.billAmount;
      });
      roundedtotalBillAmount = double.parse(
        totalBillAmount.toStringAsFixed(decimal!),
      );
      NumberFormat formatter = NumberFormat('#,##0.${'0' * decimal!}', 'en_US');
      String formattedtotal = formatter.format(roundedtotalBillAmount);
      controller_totalamt.text = formattedtotal.toString();

      if (bills.isEmpty) {
        isVisibleBillHeading = false;
      } else {
        isVisibleBillHeading = true;
      }

      if (cheque.isEmpty) {
        isVisibleChequeHeading = false;
      } else {
        isVisibleChequeHeading = true;
      }
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
      final String? spectraAllocationsString = prefs.getString(
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
    // Sales Invoice's loadLedgerData) - fetched here on demand.
    String customerTrn = '';
    String customerAddress = '';
    String customerMobile = '';
    String customerEmail = '';
    try {
      if (HttpURL_loadLedgerData != null &&
          _selectedparty != null &&
          _selectedparty.toString().trim().isNotEmpty) {
        final url = Uri.parse(HttpURL_loadLedgerData!);
        final headers = {
          'Authorization': 'Bearer $token',
          "Content-Type": "application/json",
        };
        final body = jsonEncode({"ledger": _selectedparty});
        final response = await http.post(url, headers: headers, body: body);
        if (response.statusCode == 200) {
          final List<dynamic> data = json.decode(response.body);
          if (data.isNotEmpty) {
            final first = Map<String, dynamic>.from(data.first);
            customerTrn = first['tin']?.toString() ?? '';
            final address = first['address']?.toString() ?? '';
            final emirate = first['state']?.toString() ?? '';
            final country = first['country']?.toString() ?? '';
            customerAddress = [address, emirate, country]
                .where(
                  (p) =>
                      p.trim().isNotEmpty && p.trim().toLowerCase() != 'null',
                )
                .join(', ');
            customerMobile = first['mobile']?.toString() ?? '';
            customerEmail = first['email']?.toString() ?? '';
          }
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
                        pw.Container(
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
                                'Name:',
                                style: pw.TextStyle(fontSize: 9),
                              ),
                              pw.SizedBox(height: 20),
                              pw.Text(
                                'Phone:',
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

  void updateChequeAmount() {
    totalChequeAmount = cheque.fold(0.0, (
      double previousAmount,
      Cheque cheque,
    ) {
      return previousAmount + cheque.chequeAmount;
    });
    // Update formatted total amount
    roundedtotalChequeAmount = double.parse(
      totalChequeAmount.toStringAsFixed(decimal!),
    );
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

  String? hostname = "",
      company = "",
      company_lowercase = "",
      serial_no = "",
      username = "",
      HttpURL = "",
      SecuritybtnAcessHolder = "";

  late DateTime receiptdate;
  late DateTime billduedate;
  late DateTime instdate;

  String? HttpURL_loadData,
      HttpURL_receiptEntry,
      HttpURL_fetchvchnos,
      HttpURL_fetchoutstanding,
      HttpURL_loadLedgerData;

  final DateFormat _dateFormat = DateFormat('yyyyMMdd');

  List<Bills> bills = [];

  List<Cheque> cheque = [];

  final TextEditingController billAmountController = TextEditingController();
  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _billduedateController = TextEditingController();
  final TextEditingController instDateController = TextEditingController();
  final TextEditingController instNoController = TextEditingController();
  final TextEditingController chequeAmountController = TextEditingController();

  String generateNextVchNo(List<String> vchnos) {
    if (vchnos.isEmpty) return "1";

    Map<String, List<Map<String, dynamic>>> patternGroups = {};

    for (String vch in vchnos) {
      List<RegExpMatch> matches = RegExp(r'\d+').allMatches(vch).toList();

      if (matches.isNotEmpty) {
        RegExpMatch selectedMatch = matches.last;

        // 🔥 Ignore year like 2026
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

    // ✅ Dominant pattern
    String selectedPattern = patternGroups.entries
        .reduce((a, b) => a.value.length > b.value.length ? a : b)
        .key;

    List<Map<String, dynamic>> selectedList = patternGroups[selectedPattern]!;

    // 🔥 STEP 1: Extract & sort numbers
    List<int> numbers = selectedList.map((e) => e["number"] as int).toList();
    numbers = numbers.toSet().toList();

    numbers.sort();

    int length = selectedList.first["length"];

    // 🔥 STEP 2: Find missing number (gap)
    int expected = numbers.first;

    int nextNumber = numbers.last + 1; // fallback

    for (int num in numbers) {
      if (num != expected) {
        nextNumber = expected;
        break;
      }
      expected++;
    }

    // 🔥 STEP 3: Format number
    String newNumber = nextNumber.toString().padLeft(length, '0');

    // reconstruct
    List<String> parts = selectedPattern.split("#");
    String prefix = parts[0];
    String suffix = parts[1];

    return prefix + newNumber + suffix;
  }

  Future<void> saveEntry() async {
    // ❌ Prevent save if party not selected
    if (_selectedparty == null || _selectedparty.toString().trim().isEmpty) {
      showAppMessage(context, "Please select Party");
      return;
    }

    // ❌ Prevent save if bank/cash not selected
    if (_selectedbankcashname == null ||
        _selectedbankcashname!['name'] == null ||
        _selectedbankcashname!['name']!.trim().isEmpty) {
      showAppMessage(context, "Please select Bank / Cash Ledger");
      return;
    }

    if (bills.isEmpty) {
      showAppMessage(context, 'Atleast add 1 bill');
    } else {
      setState(() {
        _isLoading = true;
      });
      jsonEntryData.clear();
      String narrationValue = controller_narration.text;
      String vchnoValue = _vchnoController.text;

      jsonEntryData["DATE"] = receiptdatestring;
      jsonEntryData["VOUCHERTYPENAME"] = _selectedvchtypename;
      jsonEntryData["PARTYLEDGERNAME"] = _selectedparty;
      jsonEntryData["ENTEREDBY"] = name;
      jsonEntryData["VOUCHERNUMBER"] = vchnoValue;
      jsonEntryData["NARRATION"] = narrationValue;

      final List<Map<String, dynamic>> allLedgerEntriesList = [];

      // Get the list of non-"On Account" bills
      final List<Map<String, dynamic>> nonOnAccountBills = bills
          .where((bill) => bill.billName != "On Account")
          .map((bill) {
            final Map<String, dynamic> billData = {
              "BILLTYPE": bill.billName,
              "AMOUNT": bill.billAmount,
            };

            // Conditionally add BILLNO and BILL CREDIT PERIOD if BILLTYPE is not "On Account"
            if (bill.billName != "On Account") {
              billData["NAME"] = bill.billNo;
              billData["BILLCREDITPERIOD"] =
                  bill.billDueDate ??
                  ""; // Assuming billDueDate is part of the bill object
            }

            return billData;
          })
          .toList();

      // Get the list of "On Account" bills
      final List<Map<String, dynamic>> onAccountBills = bills
          .where((bill) => bill.billName == "On Account")
          .map((bill) {
            final Map<String, dynamic> billData = {
              "BILLTYPE": bill.billName,
              "AMOUNT": bill.billAmount,
            };
            return billData;
          })
          .toList();

      // Combine the lists, placing "On Account" bills at the end
      final List<Map<String, dynamic>> allBillAllocations = [
        ...nonOnAccountBills,
        ...onAccountBills,
      ];

      final Map<String, dynamic> allLedgerEntry = {
        "LEDGERNAME": _selectedparty,
        "AMOUNT": totalBillAmount,
        "ISPARTYLEDGER": "Yes",
        "ISDEEMEDPOSITIVE": "No",
        "BILLALLOCATIONS.LIST": allBillAllocations,
      };
      allLedgerEntriesList.add(allLedgerEntry);

      // Add bank allocation details
      final Map<String, dynamic> bankAllocation = {
        "LEDGERNAME":
            _selectedbankcashname!['name'], // Assuming you're getting bank name dynamically
        "AMOUNT":
            -totalBillAmount, // Assuming you have totalBankAmount calculated
        "ISPARTYLEDGER": "No",
        "ISDEEMEDPOSITIVE": "Yes",
        "BANKALLOCATIONS.LIST":
            [], // Conditionally empty list based on the type of selected bank/cash
      };
      allLedgerEntriesList.add(bankAllocation);

      // If the selected bank/cash type is not 'Cash-in-Hand', add cheque details to bank allocation list
      if (!isSelectedBankCashInHand) {
        bankAllocation["BANKALLOCATIONS.LIST"] = cheque.map((cheque) {
          return {
            "DATE": receiptdatestring,
            "INSTRUMENTDATE": cheque.instdate ?? receiptdatestring,
            "TRANSACTIONTYPE": cheque.paymentMode,
            "BANKNAME": (cheque.bankname != "Not Applicable")
                ? cheque.bankname
                : "",
            "PAYMENTFAVOURING": _selectedparty,
            "INSTRUMENTNUMBER": cheque.instno,
            "BANKPARTYNAME": _selectedparty,
            "AMOUNT": -cheque.chequeAmount,
          };
        }).toList();
      }

      jsonEntryData['ALLLEDGERENTRIES.LIST'] = allLedgerEntriesList;

      Map<String, dynamic> jsonData = {
        'type': 'receipt',
        'data': jsonEntryData,
      };

      final jsonString = json.encode(jsonData);

      print(jsonString);
      try {
        final url_receiptentry = Uri.parse(HttpURL_receiptEntry!);
        Map<String, String> headers_receiptentry = {
          'Authorization': 'Bearer $token',
          "Content-Type": "application/json",
        };

        var body_receiptentry = jsonString;

        final response_receiptentry = await http.post(
          url_receiptentry,
          body: body_receiptentry,
          headers: headers_receiptentry,
        );

        if (response_receiptentry.statusCode == 200) {
          if (response_receiptentry.body == 'Entry created successfully') {
            showReceiptVoucherDialog(context);
          } else {
            showAppMessage(context, 'an error occoured');
          }
        } else {
          Map<String, dynamic> data = json.decode(response_receiptentry.body);
          String error = '';

          if (data.containsKey('error')) {
            setState(() {
              error = data['error'];
            });
          } else {
            error = "Error in data fetching!!!";
          }
          showAppMessage(context, error);
        }
      } catch (e) {
        setState(() {
          _isLoading = false;
        });
        print(e);
      }
    }
    setState(() {
      _isLoading = false;
    });
  }

  /*Future<void> loadData() async {
    vchtypenamedata.clear();
    partydata.clear();
    bankcashname_data.clear();
    bills.clear();
    totalBillAmount = bills.fold(0.0,
          (double previousAmount, Bills bill) {
        return previousAmount + bill.billAmount;
      },
    );
    // Update formatted total amount
    roundedtotalBillAmount = double.parse(totalBillAmount.toStringAsFixed(decimal!));
    NumberFormat formatter = NumberFormat('#,##0.${'0' * decimal!}', 'en_US');
    String formattedtotal = formatter.format(roundedtotalBillAmount);
    controller_totalamt.text = formattedtotal.toString();
    cheque.clear();
    updateChequeAmount();

    billAmountController.clear();
    chequeAmountController.clear();
    instNoController.clear();
    selectedbankname = bankname_data.first;
    _banknameController.text = selectedbankname;
    controller_totalamt.text = '0';

    setState(() {
      _isLoading = true;
    });

    // data fetching
    try {
      final url = Uri.parse(HttpURL_loadData!);
      Map<String,String> headers =
      {
        'Authorization' : 'Bearer $token',
        "Content-Type": "application/json"
      };
      final response = await http.post
        (
          url,
          headers:headers
      );

      if (response.statusCode == 200)
      {
        final Map<String, dynamic> jsonResponse = json.decode(response.body);

        */ /*print(response.body);*/ /*
        setState(() {
          final String currentSerialNo = serial_no?.trim() ?? '';
          final bool isUniGasSerial = vanSalesSerialNo.contains(currentSerialNo);

          String? allocationString = prefs.getString('spectra_allocations');
          Map<String, dynamic>? allocation;

          if (isUniGasSerial &&
              allocationString != null &&
              allocationString.isNotEmpty) {
            try {
              final List<dynamic> allocations = jsonDecode(allocationString);

              if (allocations.isNotEmpty) {
                allocation = Map<String, dynamic>.from(allocations.first);
              }
            } catch (e) {
              debugPrint('receipt allocation decode error -> $e');
            }
          }

          vchtypenamedata = List<String>.from(jsonResponse['vchTypes']);

          _selectedvchtypename = vchtypenamedata.isNotEmpty ? vchtypenamedata.first : '';
          isVoucherTypeLocked = false;

          if (isUniGasSerial && allocation != null) {
            final String savedReceiptVoucherType =
                allocation['receipt_voucher_type']?.toString().trim() ??
                    allocation['voucher_type']?.toString().trim() ??
                    '';

            if (savedReceiptVoucherType.isNotEmpty &&
                vchtypenamedata.contains(savedReceiptVoucherType)) {
              _selectedvchtypename = savedReceiptVoucherType;
              isVoucherTypeLocked = true;
            }
          }

          fetchvchnos(_selectedvchtypename);

          partydata = List<String>.from(jsonResponse['partyLedgers']);
          partydata.sort();

          bankcashname_data = List<Map<String, String>>.from(
            jsonResponse['cashLedgers']
                ?.map((cashLedger) => Map<String, String>.from(cashLedger)) ??
                [],
          );

          _selectedbankcashname = null;
          isBankCashLedgerLocked = false;

          if (isUniGasSerial && allocation != null) {
            final String savedCashLedger =
                allocation['cash_ledger']?.toString().trim() ??
                    allocation['cashledger']?.toString().trim() ??
                    allocation['bank_cash_ledger']?.toString().trim() ??
                    '';

            if (savedCashLedger.isNotEmpty) {
              final matchedCashLedger = bankcashname_data.where(
                    (ledger) => ledger['name'] == savedCashLedger,
              );

              if (matchedCashLedger.isNotEmpty) {
                _selectedbankcashname = matchedCashLedger.first;
                isBankCashLedgerLocked = true;
              }
            }
          }

          _bankcashnameController.text =
          _selectedbankcashname != null ? _selectedbankcashname!['name']! : "";


          // Only recalculate Payment Mode visibility when a bank/cash
          // ledger actually got auto-selected above - otherwise leave it
          // at its default (hidden) instead of falling through to the
          // "not Cash-in-Hand" else branch for a null ledger.
          if (_selectedbankcashname != null) {
            if (isSelectedBankCashInHand) {
              isPaymentModeVisible = false;
              _selectedpaymentmode = paymentmode_data.isNotEmpty ? paymentmode_data.first : '';
              cheque.clear();
              updateChequeAmount();

              isVisibleChequeHeading = false;
              isChequeVisible = false;
            }
            else
            {
              if(bills.isNotEmpty)
              {
                if(cheque.isNotEmpty)
                {
                  isPaymentModeVisible = true;
                  isChequeVisible = true;
                  isVisibleChequeHeading = true;
                }
                else
                {
                  isPaymentModeVisible = true;
                  _selectedpaymentmode = paymentmode_data.isNotEmpty ? paymentmode_data.first : '';
                  cheque.clear();
                  updateChequeAmount();

                  isVisibleChequeHeading = false;
                  isChequeVisible = true;
                }
              }
              else
              {
                isPaymentModeVisible = true;
                _selectedpaymentmode = paymentmode_data.isNotEmpty ? paymentmode_data.first : '';
                cheque.clear();
                updateChequeAmount();

                isVisibleChequeHeading = false;
                isChequeVisible = false;
              }
            }
          }

        });
      }
      else
      {
        Map<String, dynamic> data = json.decode(response.body);
        String error = '';
        if (data.containsKey('error'))
        {
          setState(() {
            error = data['error'];
          });
        }
        else
        {
          error = 'Something went wrong!!!';
        }
        showAppMessage(context, error);
      }
    }
    catch (e)
    {
      */ /*print(e);*/ /*
    }

    setState(() {
      _isLoading = false;
    });
  }*/

  Future<void> loadData() async {
    vchtypenamedata.clear();
    partydata.clear();
    bankcashname_data.clear();
    bills.clear();

    totalBillAmount = bills.fold(0.0, (double previousAmount, Bills bill) {
      return previousAmount + bill.billAmount;
    });

    roundedtotalBillAmount = double.parse(
      totalBillAmount.toStringAsFixed(decimal!),
    );
    NumberFormat formatter = NumberFormat('#,##0.${'0' * decimal!}', 'en_US');
    String formattedtotal = formatter.format(roundedtotalBillAmount);
    controller_totalamt.text = formattedtotal.toString();

    cheque.clear();
    updateChequeAmount();

    billAmountController.clear();
    chequeAmountController.clear();
    instNoController.clear();
    selectedbankname = bankname_data.first;
    _banknameController.text = selectedbankname;
    controller_totalamt.text = '0';

    setState(() {
      _isLoading = true;
    });

    try {
      final url = Uri.parse(HttpURL_loadData!);

      Map<String, String> headers = {
        'Authorization': 'Bearer $token',
        "Content-Type": "application/json",
      };

      final response = await http.post(url, headers: headers);

      debugPrint('receipt load data -> ${response.body}');

      if (response.statusCode == 200) {
        final Map<String, dynamic> jsonResponse = json.decode(response.body);

        final String currentSerialNo = serial_no?.trim() ?? '';
        final bool isUniGasSerial = vanSalesSerialNo.contains(currentSerialNo);

        String? allocationString = prefs.getString('spectra_allocations');
        Map<String, dynamic>? allocation;

        if (isUniGasSerial &&
            allocationString != null &&
            allocationString.isNotEmpty) {
          try {
            final List<dynamic> allocations = jsonDecode(allocationString);

            if (allocations.isNotEmpty) {
              allocation = Map<String, dynamic>.from(allocations.first);
            }
          } catch (e) {
            debugPrint('receipt allocation decode error -> $e');
          }
        }

        String? voucherTypeToFetch;

        setState(() {
          vchtypenamedata = List<String>.from(
            (jsonResponse['vchTypes'] ?? [])
                .where((e) => e != null)
                .map((e) => e.toString()),
          );

          String savedReceiptVoucherType = '';

          if (isUniGasSerial && allocation != null) {
            final String receiptVoucherType =
                allocation['receipt_voucher_type']?.toString().trim() ?? '';

            final String commonVoucherType =
                allocation['voucher_type']?.toString().trim() ?? '';

            savedReceiptVoucherType = receiptVoucherType.isNotEmpty
                ? receiptVoucherType
                : commonVoucherType;
          }

          final bool hasValidSavedVoucherType =
              savedReceiptVoucherType.isNotEmpty &&
              savedReceiptVoucherType.toLowerCase() != 'null' &&
              vchtypenamedata.contains(savedReceiptVoucherType);

          _selectedvchtypename = (hasValidSavedVoucherType
              ? savedReceiptVoucherType
              : (vchtypenamedata.isNotEmpty ? vchtypenamedata.first : null))!;

          isVoucherTypeLocked = hasValidSavedVoucherType;
          voucherTypeToFetch = _selectedvchtypename;

          partydata = List<String>.from(jsonResponse['partyLedgers']);
          partydata.sort();

          bankcashname_data = List<Map<String, String>>.from(
            jsonResponse['cashLedgers']?.map(
                  (cashLedger) => Map<String, String>.from(cashLedger),
                ) ??
                [],
          );

          _selectedbankcashname = null;
          isBankCashLedgerLocked = false;

          if (isUniGasSerial && allocation != null) {
            final String savedCashLedger =
                allocation!['cash_ledger']?.toString().trim() ??
                allocation!['cashledger']?.toString().trim() ??
                allocation!['bank_cash_ledger']?.toString().trim() ??
                '';

            if (savedCashLedger.isNotEmpty) {
              final matchedCashLedger = bankcashname_data.where(
                (ledger) => ledger['name'] == savedCashLedger,
              );

              if (matchedCashLedger.isNotEmpty) {
                _selectedbankcashname = matchedCashLedger.first;
                isBankCashLedgerLocked = true;
              }
            }
          }

          _bankcashnameController.text = _selectedbankcashname != null
              ? _selectedbankcashname!['name']!
              : "";

          // Only recalculate Payment Mode visibility when a bank/cash
          // ledger actually got auto-selected above - otherwise leave it
          // at its default (hidden) instead of falling through to the
          // "not Cash-in-Hand" else branch for a null ledger.
          if (_selectedbankcashname != null) {
            if (isSelectedBankCashInHand) {
              isPaymentModeVisible = false;
              _selectedpaymentmode = paymentmode_data.isNotEmpty ? paymentmode_data.first : '';
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
                  _selectedpaymentmode = paymentmode_data.isNotEmpty ? paymentmode_data.first : '';
                  cheque.clear();
                  updateChequeAmount();

                  isVisibleChequeHeading = false;
                  isChequeVisible = true;
                }
              } else {
                isPaymentModeVisible = true;
                _selectedpaymentmode = paymentmode_data.isNotEmpty ? paymentmode_data.first : '';
                cheque.clear();
                updateChequeAmount();

                isVisibleChequeHeading = false;
                isChequeVisible = false;
              }
            }
          }
        });

        if (voucherTypeToFetch != null && voucherTypeToFetch!.isNotEmpty) {
          fetchvchnos(voucherTypeToFetch!);
        }
      } else {
        Map<String, dynamic> data = json.decode(response.body);
        String error = '';

        if (data.containsKey('error')) {
          error = data['error'];
        } else {
          error = 'Something went wrong!!!';
        }

        showAppMessage(context, error);
      }
    } catch (e) {
      /*print(e);*/
    }

    setState(() {
      _isLoading = false;
    });
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
      setState(() {
        receiptdate = picked;
        receiptdatestring = _dateFormat.format(receiptdate);
        receiptdatetxt = formatlastsaledate(receiptdatestring);
        _dateController.text = receiptdatetxt;
        if (_selectedparty != null &&
            _selectedparty.toString().trim().isNotEmpty) {
          if (showOutstandingBills) {
            fetchPartyOutstanding(_selectedparty.toString());
          }
        }
      });
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

  /*Future<void> _showBillsDetailsPopup(BuildContext context) async {
    setState(() {
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            titlePadding: EdgeInsets.zero,
            title: Column(
              children: [
                Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: app_color,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [Colors.white, Colors.white],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: const Icon(Icons.receipt_long, color: app_color, size: 26),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Add Bill",
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),


            content: SingleChildScrollView(
              child: Form(
                key: _billsFormkey,
                child: Column(
                  children: <Widget>[
                    // 🔹 Bill Type Dropdown
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: "Bill Type",
                        hintText: "Select Bill Type",
                        labelStyle: GoogleFonts.poppins(
                          fontSize: 12.5,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        hintStyle: GoogleFonts.poppins(
                          fontSize: 12.5,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        prefixIcon: Container(
                          margin: const EdgeInsets.all(8), // 👈 smaller margin
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Colors.indigo, Colors.cyan],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.book, color: Colors.white, size: 16), // 👈 smaller icon
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14), // 👈 slightly tighter radius
                          borderSide: BorderSide(color: Theme.of(context).dividerColor),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: app_color, width: 1.3),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10, // 👈 tighter padding
                        ),
                      ),
                      value: _selectedbill,
                      items: billsdata.map((String value) {
                        return DropdownMenuItem(
                          value: value,
                          child: Text(value, style: GoogleFonts.poppins(fontSize: 13)),
                        );
                      }).toList(),
                      onChanged: (newValue) {
                        setState(() {
                          _selectedbill = newValue!;
                          if (_selectedbill == 'New Ref' || _selectedbill == 'Agst Ref') {
                            isVisibleDueDate = true;
                            isVisibleBillNo = true;
                          } else {
                            isVisibleDueDate = false;
                            isVisibleBillNo = false;
                            billNoController.clear();
                            _billduedateController.clear();
                          }
                          Navigator.of(context).pop();
                          _billsFormkey = GlobalKey<FormState>();
                          _showBillsDetailsPopup(context);
                        });
                      },
                    ),


                    // 🔹 Bill No
                    Visibility(
                      visible: isVisibleBillNo,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: TextFormField(
                          controller: billNoController,
                          validator: (value) => value!.isEmpty ? 'Please enter bill no' : null,
                          decoration: InputDecoration(
                            labelText: "Bill No",
                            hintText: "Enter Bill No",
                            labelStyle: GoogleFonts.poppins(
                              fontSize: 12.5,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                            hintStyle: GoogleFonts.poppins(
                              fontSize: 12.5,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                            prefixIcon: Container(
                              margin: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Colors.orange, Colors.deepOrangeAccent],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.confirmation_num_outlined, color: Colors.white, size: 20),
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(color: app_color, width: 1.5),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),

                          ),
                        ),
                      ),
                    ),

                    // 🔹 Due Date
                    Visibility(
                      visible: isVisibleDueDate,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: TextFormField(
                          controller: _billduedateController,
                          validator: (value) {
                            if (value!.isNotEmpty) {
                              if (double.tryParse(value) == null) {
                                return 'Invalid input, please enter a number';
                              } else if (double.parse(value) < 0) {
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
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                            hintStyle: GoogleFonts.poppins(
                              fontSize: 13,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                            prefixIcon: Container(
                              margin: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Colors.pinkAccent, Colors.redAccent],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.calendar_today, color: Colors.white, size: 20),
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(color: app_color, width: 1.5),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),

                          ),
                        ),
                      ),
                    ),

                    // 🔹 Amount
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: TextFormField(
                        controller: billAmountController,
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          if (value!.isEmpty) return 'Please enter amount';
                          if (!isNumeric(value)) return 'Enter valid amount';
                          if (double.parse(value) == 0) return 'Amount should not be 0';
                          return null;
                        },
                        decoration: InputDecoration(
                          labelText: "Amount",
                          hintText: "0",
                          labelStyle: GoogleFonts.poppins(
                            fontSize: 13,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          hintStyle: GoogleFonts.poppins(
                            fontSize: 13,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          prefix: Container(
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Colors.green, Colors.teal], // ✅ distinct from Ledger
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.all(Radius.circular(8)),
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
                            borderRadius: BorderRadius.circular(16),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: app_color, width: 1.5),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),

                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  _selectedbill = billsdata.first;
                  isVisibleDueDate = _selectedbill == 'New Ref' || _selectedbill == 'Agst Ref';
                  isVisibleBillNo = isVisibleDueDate;
                  _billduedateController.clear();
                  billAmountController.clear();
                },
                child: Text('Cancel',
                  style: GoogleFonts.poppins(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),

              // ✅ Premium Add Bill button
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: app_color,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                onPressed: () {
                  if (_billsFormkey.currentState!.validate()) {
                    _billsFormkey.currentState!.save();
                    addBill();
                  }
                },
                child: Text("Add Bill",
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          );
        },
      );
    });
  }*/

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

  /*Future<void> _showChequeDetailsPopup(BuildContext context) async {
    setState(() {
      showDialog(
          context: context,
          builder: (BuildContext context) {
            return StatefulBuilder(
              builder: (context, setStateDialog) {
                return AlertDialog(
                  titlePadding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),

                  title:

                  Column(
                    children: [
                      Container(
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          color: app_color,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                        ),
                        child: Column(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  colors: [Colors.white, Colors.white],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),
                              child: const Icon(Icons.payment, color: app_color, size: 26),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              "$_selectedpaymentmode Details",
                              style: GoogleFonts.poppins(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),



                  content: SingleChildScrollView(
                    child: Form(
                      key: _chequedetailsFormkey,
                      child: Column(
                        children: <Widget>[

                          // 🔹 Inst No
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: TextFormField(
                              controller: instNoController,
                              decoration: InputDecoration(
                                labelText: 'Inst No',
                                hintText: 'Enter Inst No',
                                labelStyle: GoogleFonts.poppins(
                                  fontSize: 13,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10, // 👈 tighter padding
                                ),
                                filled: true,
                                fillColor: Theme.of(context).inputDecorationTheme.fillColor ?? Theme.of(context).cardColor.withOpacity(0.95),
                                prefixIcon: Container(
                                  margin: const EdgeInsets.all(8),
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [Colors.orange, Colors.deepOrangeAccent],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius: BorderRadius.all(Radius.circular(12)),
                                  ),
                                  child: const Icon(Icons.confirmation_number_outlined, color: Colors.white, size: 20),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(color: Theme.of(context).dividerColor, width: 1),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(color: app_color, width: 1.5),
                                ),
                              ),
                            ),
                          ),

                          // 🔹 Inst Date
                          Padding(
                            padding:  EdgeInsets.symmetric(vertical: 4),
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
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10, // 👈 tighter padding
                                ),
                                filled: true,
                                fillColor: Theme.of(context).inputDecorationTheme.fillColor ?? Theme.of(context).cardColor.withOpacity(0.95),
                                prefixIcon: Container(
                                  margin: const EdgeInsets.all(8),
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [Colors.teal, Colors.cyan],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius: BorderRadius.all(Radius.circular(12)),
                                  ),
                                  child: const Icon(Icons.calendar_today, color: Colors.white, size: 20),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(color: Theme.of(context).dividerColor, width: 1),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(color: app_color, width: 1.5),
                                ),
                              ),
                            ),
                          ),

                          // 🔹 Bank Name
                          Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: TypeAheadField<String>(
                                suggestionsCallback: (pattern) {
                                  return bankname_data.where((item) {
                                    final name = item.toString().toLowerCase();
                                    return name.contains(pattern.toLowerCase());
                                  }).toList();
                                },

                                builder: (context, controller, focusNode) {
                                  controller.text = _banknameController.text;

                                  return TextField(
                                    controller: controller,
                                    focusNode: focusNode,
                                    decoration: InputDecoration(
                                      labelText: "Bank",
                                      hintText: 'Search Bank',
                                      labelStyle: GoogleFonts.poppins(
                                        fontSize: 13,
                                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                                      ),
                                      contentPadding:
                                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                      filled: true,
                                      fillColor: Theme.of(context).inputDecorationTheme.fillColor ?? Theme.of(context).cardColor.withOpacity(0.95),
                                      prefixIcon: Container(
                                        margin: const EdgeInsets.all(8),
                                        decoration: const BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [Colors.purple, Colors.deepPurpleAccent],
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                          ),
                                          borderRadius: BorderRadius.all(Radius.circular(12)),
                                        ),
                                        child: const Icon(Icons.account_balance_outlined,
                                            color: Colors.white, size: 20),
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
                                              child:
                                              Icon(Icons.close, color: Theme.of(context).colorScheme.onSurfaceVariant, size: 20),
                                            ),
                                          const SizedBox(width: 4),
                                          Icon(Icons.arrow_drop_down, color: Theme.of(context).colorScheme.onSurface),
                                          const SizedBox(width: 8),
                                        ],
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(14),
                                        borderSide:
                                        BorderSide(color: Theme.of(context).dividerColor, width: 1),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(14),
                                        borderSide:
                                        BorderSide(color: app_color, width: 1.5),
                                      ),
                                    ),
                                  );
                                },

                                itemBuilder: (context, String suggestion) {
                                  return ListTile(
                                    title: Text(
                                      suggestion,
                                      style: GoogleFonts.poppins(fontSize: 13),
                                    ),
                                  );
                                },

                                onSelected: (String suggestion) {
                                  setStateDialog(() {
                                    selectedbankname = suggestion;
                                    _banknameController.text = suggestion;
                                  });
                                },




                                // ✅ New API uses EmptyBuilder instead of noItemsFoundBuilder
                                emptyBuilder: (context) => Padding(
                                  padding: EdgeInsets.all(8.0),
                                  child: Text(
                                    'No matching bank found',
                                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                                  ),
                                ),
                              )



                          ),

                          // 🔹 Amount
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: TextFormField(
                              controller: chequeAmountController,
                              keyboardType: TextInputType.number,
                              validator: (value) {
                                if (value!.isEmpty) return 'Please enter amount';
                                if (double.parse(value) == 0) return 'Amount should not be 0';
                                return null;
                              },
                              decoration: InputDecoration(
                                labelText: 'Amount',
                                hintText: '0',
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10, // 👈 tighter padding
                                ),
                                labelStyle: GoogleFonts.poppins(
                                  fontSize: 13,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                                filled: true,
                                fillColor: Theme.of(context).inputDecorationTheme.fillColor ?? Theme.of(context).cardColor.withOpacity(0.95),
                                prefixIcon: Container(
                                  margin:  EdgeInsets.all(8),
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    gradient:  LinearGradient(
                                      colors: [Colors.grey, Colors.brown],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
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
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(color: Theme.of(context).dividerColor, width: 1),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(color: app_color, width: 1.5),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // 🔹 Actions
                  actions: <Widget>[
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        setState(() {
                          selectedbankname = bankname_data.first;
                          _banknameController.text = selectedbankname;
                          instNoController.clear();
                          instdate = DateTime.now();
                          instdatestring = _dateFormat.format(instdate);
                          instdatetxt = formatlastsaledate(instdatestring);
                          instDateController.text = instdatetxt;
                          chequeAmountController.clear();
                        });
                      },
                      child: Text('Cancel', style: GoogleFonts.poppins(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: app_color,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      ),
                      onPressed: () {
                        if (_chequedetailsFormkey.currentState != null &&
                            _chequedetailsFormkey.currentState!.validate()) {
                          _chequedetailsFormkey.currentState!.save();
                          addCheque();
                        }
                      },
                      child: Text(
                        'Add $_selectedpaymentmode',
                        style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                );
              },);}
      );
    });
  }*/

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

    if (billAmount.isNotEmpty) {
      // Check if a bill with name "On Account" already exists
      if (billName == "On Account" &&
          bills.any((bill) => bill.billName == "On Account")) {
        // Show message that the bill already exists
        showDialog(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: Text("Duplicate Bill"),
              content: Text(
                "A bill with the name 'On Account' already exists.",
              ),
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

      // Create a new bill
      Navigator.of(context).pop();
      double parsedAmount = double.parse(billAmount.replaceAll(',', ''));
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

      // Add the new bill to the list and update the total bill amount
      setState(() {
        bills.add(newBill);
        // Update visibility of bill heading
        isVisibleBillHeading = bills.isNotEmpty;
        totalBillAmount = bills.fold(0.0, (double previousAmount, Bills bill) {
          return previousAmount + bill.billAmount;
        });
        // Update formatted total amount
        roundedtotalBillAmount = double.parse(
          totalBillAmount.toStringAsFixed(decimal!),
        );
        NumberFormat formatter = NumberFormat(
          '#,##0.${'0' * decimal!}',
          'en_US',
        );
        String formattedtotal = formatter.format(roundedtotalBillAmount);
        controller_totalamt.text = formattedtotal.toString();
      });

      // Reset selected bill and visibility of due date and bill number
      setState(() {
        _selectedbill = billsdata.first;
        isVisibleDueDate =
            (_selectedbill == 'New Ref' || _selectedbill == "Agst Ref");
        isVisibleBillNo =
            (_selectedbill == "Agst Ref" || _selectedbill == 'New Ref');
        if (_selectedbankcashname != null && isSelectedBankCashInHand) {
          isPaymentModeVisible = false;
          _selectedpaymentmode = paymentmode_data.isNotEmpty ? paymentmode_data.first : '';
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
              _selectedpaymentmode = paymentmode_data.isNotEmpty ? paymentmode_data.first : '';
              cheque.clear();
              updateChequeAmount();
              isVisibleChequeHeading = false;
              isChequeVisible = true;
            }
          } else {
            isPaymentModeVisible = true;
            _selectedpaymentmode = paymentmode_data.isNotEmpty ? paymentmode_data.first : '';
            cheque.clear();
            updateChequeAmount();
            isVisibleChequeHeading = false;
            isChequeVisible = false;
          }
        }
      });

      // Clear input fields
      billAmountController.clear();
      _billduedateController.clear();

      /*if(_selectedpaymentmode == 'Cheque/DD')
        {
          setState(() {
            isChequeVisible = true;
          });
        }
      else
        {
          setState(() {
            isChequeVisible = false;
          });
        }*/
    }

    if (isSelectedBankCashInHand) {
      setState(() {
        FocusManager.instance.primaryFocus?.unfocus();
        isPaymentModeVisible = false;
        _selectedpaymentmode = paymentmode_data.isNotEmpty ? paymentmode_data.first : '';
        cheque.clear();
        updateChequeAmount();
        isVisibleChequeHeading = false;
        isChequeVisible = false;
      });
    }
  } // add bill function

  void addCheque() {
    final instNo = instNoController.text;
    final instDate = instdate;
    final bankName = selectedbankname;
    final chequeAmount = chequeAmountController.text;
    final paymentMode = _selectedpaymentmode;

    double parsedAmount = double.parse(chequeAmount.replaceAll(',', ''));

    String formattedAmount = parsedAmount.toStringAsFixed(decimal!);

    double formattedAmountDouble = double.parse(formattedAmount);

    String instDateString = DateFormat('yyyyMMdd').format(instDate);

    bool hasRepeatedInstNo = isInstNoRepeated(instNo, cheque);

    double remainingchequeamount =
        roundedtotalBillAmount - roundedtotalChequeAmount;

    print(
      'before processing cheque amount $chequeAmount and roundedbillamount $roundedtotalBillAmount and roundedchequeAmount $roundedtotalChequeAmount and entered cheque amount $formattedAmountDouble and remaining cheque amount $remainingchequeamount',
    );

    if (chequeAmount.isNotEmpty &&
        roundedtotalChequeAmount <= roundedtotalBillAmount &&
        roundedtotalChequeAmount != roundedtotalBillAmount &&
        !hasRepeatedInstNo &&
        formattedAmountDouble <= roundedtotalBillAmount &&
        formattedAmountDouble <= remainingchequeamount) {
      Navigator.of(context).pop();

      final newCheque = Cheque(
        instno: instNo,
        instdate: instDateString,
        bankname: bankName,
        chequeAmount: parsedAmount,
        paymentMode: paymentMode,
      );

      // Add the new bill to the list and update the total bill amount
      setState(() {
        cheque.add(newCheque);
        // Update visibility of bill heading
        isVisibleChequeHeading = cheque.isNotEmpty;
        updateChequeAmount();
      });
      print(
        'after processing cheque amount $chequeAmount and roundedbillamount $roundedtotalBillAmount and roundedchequeAmount $roundedtotalChequeAmount and entered cheque amount $formattedAmountDouble and remaining cheque amount $remainingchequeamount',
      );

      // Reset selected bill and visibility of due date and bill number
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
    } else if (formattedAmountDouble > remainingchequeamount) {
      showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text("Alert"),
            content: Text(
              "Entered $_selectedpaymentmode amount exceeds remaining total amount",
            ),
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
      return;
    } else if (hasRepeatedInstNo) {
      showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text("Alert"),
            content: Text(
              "A cheque with the inst no '$instNo' already exists.",
            ),
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
      return;
    } else if (roundedtotalBillAmount < 0 || roundedtotalBillAmount == 0) {
      showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text("Alert"),
            content: Text("First add bills then proceed for payment details"),
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
      return;
    } else if (roundedtotalChequeAmount == roundedtotalBillAmount) {
      showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text("Alert"),
            content: Text("Cheques for the total amount already added"),
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
      return; // Exit the function without adding the bill
    } else if (formattedAmountDouble > roundedtotalBillAmount) {
      showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text("Alert"),
            content: Text(
              "Entered $_selectedpaymentmode amount should not be greater than total amount",
            ),
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
      return;
    }
  } // add cheque function

  Future<void> _initSharedPreferences() async {
    prefs = await SharedPreferences.getInstance();
    setState(() {
      hostname = prefs.getString('hostname');
      company = prefs.getString('company_name');
      company_lowercase = company!.replaceAll(' ', '').toLowerCase();
      serial_no = prefs.getString('serial_no');
      username = prefs.getString('username');
      token = prefs.getString('token')!;
      currencycode = prefs.getString('currencycode') ?? 'AED';
      bankname_data.sort((a, b) {
        if (a == 'Not Applicable') {
          return -1; // 'Not Applicable' comes before everything else
        } else if (b == 'Not Applicable') {
          return 1; // 'Not Applicable' comes before everything else
        } else {
          return a.compareTo(b); // Compare other elements alphabetically
        }
      });

      decimal = prefs.getInt('decimalplace') ?? 2;

      paymentmode_data.add("ATM");
      paymentmode_data.add("Card");
      paymentmode_data.add('Cheque/DD');
      _selectedpaymentmode = paymentmode_data.isNotEmpty ? paymentmode_data.first : '';

      billAmountController.clear();

      receiptdate = DateTime.now();
      receiptdatestring = _dateFormat.format(receiptdate);
      receiptdatetxt = formatlastsaledate(receiptdatestring);
      _dateController.text = receiptdatetxt;

      instdate = DateTime.now();
      instdatestring = _dateFormat.format(instdate);
      instdatetxt = formatlastsaledate(instdatestring);
      instDateController.text = instdatetxt;

      _billduedateController.clear();

      SecuritybtnAcessHolder = prefs.getString('secbtnaccess');

      String? email_nav = prefs.getString('email_nav');
      String? name_nav = prefs.getString('name_nav');

      /*print('hostname: $hostname');*/

      HttpURL_fetchvchnos =
          '$hostname/api/entry/nos/$company_lowercase/$serial_no';

      HttpURL_fetchoutstanding =
          '$hostname/api/ledger/getOutstandingOpening/$company_lowercase/$serial_no';

      /*HttpURL_fetchvchnos = 'http://192.168.2.110:4999/api/entry/nos/$company_lowercase/$serial_no';*/

      HttpURL_loadData =
          '$hostname/api/entry/getReceiptData/$company_lowercase/$serial_no';
      /*HttpURL_loadData = 'http://192.168.2.110:4999/api/entry/getReceiptData/$company_lowercase/$serial_no';*/

      HttpURL_receiptEntry = '$hostname/api/entry/create/$company/$serial_no';
      /*HttpURL_receiptEntry = 'http://192.168.2.110:4999/api/entry/create/demonewformobilepp/767060064';*/

      HttpURL_loadLedgerData =
          '$hostname/api/ledger/getLedger/$company_lowercase/$serial_no';

      controller_totalamt.text = 0.toString();

      if (email_nav != null && name_nav != null) {
        name = name_nav;
        email = email_nav;
      }
      if (SecuritybtnAcessHolder == "True") {
        isRolesVisible = true;
        isUserVisible = true;
      } else {
        isRolesVisible = false;
        isUserVisible = false;
      }
    });
    await loadData();
    if (mounted) {
      setState(() {
        _isInitialDataLoaded = true;
      });
    }
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
      setState(() {
        yearStartDate = selectedDateRange.start;
        yearEndDate = selectedDateRange.end;
      });

      fetchvchnos(_selectedvchtypename);
    }
  }

  Future<void> fetchvchnos(String vchname) async {
    // Format the dates as yyyyMMdd
    String formattedStartDateVchNo =
        prefs.getString('startfrom') ?? _dateFormat.format(yearStartDate);

    String formattedEndDateVchNo = DateFormat('yyyyMMdd').format(yearEndDate);

    vchnos.clear();
    setState(() {
      _isLoading = true;
    });

    // vchnos fetching
    try {
      final url = Uri.parse(HttpURL_fetchvchnos!);
      Map<String, String> headers = {
        'Authorization': 'Bearer $token',
        "Content-Type": "application/json",
      };

      Map<String, dynamic> jsonDatabody = {
        "to": formattedEndDateVchNo,
        "from": formattedStartDateVchNo,
        "vchname": vchname,
      };

      String jsonDatabodyString = jsonEncode(jsonDatabody);

      var body = jsonDatabodyString;
      final response = await http.post(url, headers: headers, body: body);

      if (response.statusCode == 200) {
        /*print(response.body);*/
        /*setState(() {
          final Map<String, dynamic> jsonResponse = json.decode(response.body);

          final List<dynamic> vchnosJson = jsonResponse['vchnos'];
          vchnos = vchnosJson.cast<String>();
          int q = vchnos.length;
          print('vchno list containes $q nos whos values are $vchnos');

          _vchnoController.clear();
          checkVchNoExistence(_vchnoController.text);

        });*/

        setState(() {
          final Map<String, dynamic> jsonResponse = json.decode(response.body);
          final List<dynamic> vchnosJson = jsonResponse['vchnos'];

          print(response.body);
          vchnos = vchnosJson.cast<String>();

          // SORT first
          vchnos.sort((a, b) {
            RegExp regExp = RegExp(r'(\d+)(?!.*\d)');
            int numA = int.tryParse(regExp.firstMatch(a)?.group(0) ?? '0') ?? 0;
            int numB = int.tryParse(regExp.firstMatch(b)?.group(0) ?? '0') ?? 0;
            return numA.compareTo(numB);
          });

          // GENERATE NEXT
          String nextVch = generateNextVchNo(vchnos);

          _vchnoController.text = nextVch;
        });
      } else {
        vchnos.clear();
        Map<String, dynamic> data = json.decode(response.body);
        String error = '';
        if (data.containsKey('error')) {
          setState(() {
            error = data['error'];
          });
        } else {
          error = 'Something went wrong!!!';
        }
        showAppMessage(context, error);
      }
    } catch (e) {
      vchnos.clear();
      print(e);
    }

    setState(() {
      _isLoading = false;
    });
  }

  @override
  void initState() {
    super.initState();
    _initSharedPreferences();
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
                                setState(() {
                                  _selectedvchtypename = value;
                                });
                                fetchvchnos(_selectedvchtypename);
                              },
                            ),

                            // Party TypeAheadField
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
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
                                          margin: const EdgeInsets.all(8),
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
                                                  setState(() {
                                                    controller.clear();
                                                    _selectedparty = "";
                                                    showOutstandingCard = false;
                                                    totalOutstanding = 0.0;
                                                    outstandingError = "";
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
                                    setState(() {
                                      _selectedparty = suggestion;
                                      _partyController.text = _selectedparty;
                                    });
                                    if (showOutstandingBills) {
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
                                horizontal: 16,
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
                                          setState(() {
                                            _selectedbankcashname = suggestion;
                                            debugPrint(
                                              'cash in hand -> ${_selectedbankcashname!['type']}',
                                            );
                                            _bankcashnameController.text =
                                                suggestion['name']!;
                                          });
                                          if (isSelectedBankCashInHand) {
                                            setState(() {
                                              FocusManager.instance.primaryFocus
                                                  ?.unfocus();
                                              isPaymentModeVisible = false;
                                              _selectedpaymentmode =
                                                  paymentmode_data.isNotEmpty
                                                  ? paymentmode_data.first
                                                  : '';
                                              cheque.clear();
                                              updateChequeAmount();
                                              isVisibleChequeHeading = false;
                                              isChequeVisible = false;
                                            });
                                          } else {
                                            setState(() {
                                              if (bills.isNotEmpty &&
                                                  cheque.isNotEmpty) {
                                                isPaymentModeVisible = true;
                                                isChequeVisible = true;
                                                isVisibleChequeHeading = true;
                                              } else {
                                                isPaymentModeVisible = true;
                                                _selectedpaymentmode =
                                                    paymentmode_data.isNotEmpty
                                                    ? paymentmode_data.first
                                                    : '';
                                                cheque.clear();
                                                updateChequeAmount();
                                                isVisibleChequeHeading = false;
                                                isChequeVisible =
                                                    bills.isNotEmpty;
                                              }
                                            });
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
                                          margin: const EdgeInsets.all(8),
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
                                  setState(() {
                                    _selectedpaymentmode = value!;
                                  });
                                  if (bills.isEmpty) {
                                    showAppMessage(
                                      context,
                                      'At least add 1 bill',
                                    );
                                    isChequeVisible = false;
                                    selectedbankname = bankname_data.first;
                                    _banknameController.text = selectedbankname;
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
                                    cheque.clear();
                                    updateChequeAmount();
                                  } else {
                                    setState(() {
                                      isChequeVisible = true;
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
                                      setState(() {
                                        cheque.removeAt(index);
                                        updateChequeAmount();
                                        isVisibleChequeHeading =
                                            cheque.isNotEmpty;
                                      });
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
