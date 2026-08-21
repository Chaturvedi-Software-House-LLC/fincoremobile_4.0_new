import 'dart:convert';
import 'package:FincoreGo/utils/currency_helper.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'SerialSelect.dart';
import 'CompanySelectTallyOauth.dart';
import 'package:http/http.dart' as http;
import 'constants.dart';
import 'currencyFormat.dart';
import 'package:FincoreGo/widgets/app_bottom_nav.dart';
import 'package:FincoreGo/widgets/app_navigation.dart';
import 'widgets/entry_widgets.dart';
import 'api/voucher_repository.dart';
import 'api/api_exception.dart';

class LedgerEntries {
  final String ledger, amount;

  LedgerEntries({required this.ledger, required this.amount});

  factory LedgerEntries.fromJson(Map<String, dynamic> json) {
    return LedgerEntries(
      ledger: json['ledger'].toString(),
      amount: json['amount'].toString(),
    );
  }
}

class Bills {
  final String billno, amount, billtype, duedate, billdate, ledger;

  Bills({
    required this.billno,
    required this.amount,
    required this.billtype,
    required this.duedate,
    required this.billdate,
    required this.ledger,
  });

  factory Bills.fromJson(Map<String, dynamic> json) {
    return Bills(
      billno: json['billno'].toString(),
      amount: json['amount'].toString(),
      billtype: json['billtype'].toString(),
      duedate: json['duedate'].toString(),
      billdate: json['billdate'].toString(),
      ledger: json['ledger'].toString(),
    );
  }
}

class InventoryEntries {
  final String item, qty, rate, discount, amount, godown;

  InventoryEntries({
    required this.item,
    required this.qty,
    required this.rate,
    required this.discount,
    required this.amount,
    required this.godown,
  });

  factory InventoryEntries.fromJson(Map<String, dynamic> json) {
    return InventoryEntries(
      item: json['item'].toString(),
      qty: json['qty'].toString(),
      rate: json['rate'].toString(),
      discount: json['discount'].toString(),
      amount: json['amount'].toString(),
      godown: json['godown'].toString(),
    );
  }
}

class CostCenter {
  final String costcentre, amount;

  CostCenter({required this.costcentre, required this.amount});

  factory CostCenter.fromJson(Map<String, dynamic> json) {
    return CostCenter(
      costcentre: json['costcentre'].toString(),
      amount: json['amount'].toString(),
    );
  }
}

class TransactionsClicked extends StatefulWidget {
  final String vchtype,
      startdate,
      enddate,
      vchno,
      vchdate,
      ispostdated,
      refno,
      refdate,
      masterid,
      isoptional,
      ledger;
  TransactionsClicked({
    required this.vchtype,
    required this.startdate,
    required this.enddate,
    required this.vchno,
    required this.vchdate,
    required this.ispostdated,
    required this.refno,
    required this.refdate,
    required this.masterid,
    required this.isoptional,
    required this.ledger,
  });
  @override
  _TransactionsClickedPageState createState() => _TransactionsClickedPageState(
    vchtype: vchtype,
    startDateString: startdate,
    endDateString: enddate,
    vchno: vchno,
    vchdate: vchdate,
    ispostdated: ispostdated,
    refno: refno,
    refdate: refdate,
    masterid: masterid,
    isoptional: isoptional,
    ledger: ledger,
  );
}

class _TransactionsClickedPageState extends State<TransactionsClicked>
    with TickerProviderStateMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  String vchtype = "",
      vchno = "",
      vchdate = "",
      ispostdated = "",
      refno = "",
      refdate = "",
      masterid = "",
      isoptional = "",
      ledger = "";

  String startDateString = "", endDateString = "", token = '';

  List<LedgerEntries> ledgerentries_list = [];
  List<Bills> bills_list = [];
  List<InventoryEntries> inventoryentries_list = [];
  List<CostCenter> costcenter_list = [];
  bool isLedgerExpanded = false;

  bool isInventoryExpanded = false;

  bool isCostCenterExpanded = false;

  bool isBillsExpanded = false;
  int visibleLedgerCount = 3;
  int visibleBillsCount = 3;

  int visibleInventoryCount = 3;
  int visibleCostCenterCount = 3;
  _TransactionsClickedPageState({
    required this.vchtype,
    required this.startDateString,
    required this.endDateString,
    required this.vchno,
    required this.vchdate,
    required this.ispostdated,
    required this.refno,
    required this.refdate,
    required this.masterid,
    required this.isoptional,
    required this.ledger,
  });

  String? SecuritybtnAcessHolder;
  bool isDashEnable = true,
      isRolesEnable = true,
      isUserEnable = true,
      isRolesVisible = true,
      isUserVisible = true;

  String email = "";
  String name = "";

  String billno = "", billtype = "", billduedate = "", billamount = "";

  String? opening_value = "0", openingheading = "";

  TextEditingController searchController = TextEditingController();

  bool isVisibleNoDataFound = false;
  bool isVisibleLedgerEntry = false,
      isVisibleBills = false,
      isVisibleInventoryEntry = false,
      isVisibleCostCenter = false;

  bool isTopPanelBillsVisible = true, isDueDateBillsVisible = true;
  late GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey;
  late SharedPreferences prefs;

  String HttpURL = "";

  String? hostname = "",
      company = "",
      serial_no = "",
      company_lowercase = "",
      username = "";
  List<dynamic> myData = [];
  bool _isLoading = false;

  String ledgerentries = '';
  String inventoryentries = '';
  String billsentries = '';
  String costcentreentries = '';

  // True for a tally-oauth-only session (no legacy serial_no) - drives
  // fetchData()'s dispatch to the tally-api path instead of the legacy
  // collection-based HTTP calls, which require `hostname`/`token` that are
  // never populated for these sessions (see CompanySelectTallyOauth.dart).
  bool _useTallyApi = false;

  // tally-api's vouchers/:masterId has no bill-wise breakdown (bills are a
  // separate ledger-scoped model, not attached to a voucher) - the Bills
  // section shows this instead of silently staying empty. Same pattern as
  // PartyClicked's Pending Order gap.
  bool _billsUnavailable = false;

  String handleGodown(String godown) {
    if (godown == 'null' || godown.isEmpty) {
      godown = 'Not Available';
    }
    return godown;
  }

  String formatCostCenter(String costcenter) {
    String costcenter_string = "";
    if (costcenter == 'null') {
      costcenter_string = '*Not Applicable';
    } else {
      costcenter_string = costcenter;
    }
    // Apply any transformations or formatting to the 'amount' variable here
    return costcenter_string;
  }

  String formatRate(String rate) {
    if (rate == 'null') {
      rate = 'Not Available';
    }
    // Apply any transformations or formatting to the 'amount' variable here
    return rate;
  }

  String convertDateFormat(String dateStr) {
    String formattedDate = "";

    if (dateStr == '' || dateStr == 'null') {
    } else {
      DateTime date = DateTime.parse(dateStr);

      // Format the date to the desired output format
      formattedDate = DateFormat("dd-MMM-yyyy").format(date);
    }
    // Parse the input date string

    return formattedDate;
  }

  Future<void> fetchData(
    final String ledgercollection,
    final String billscollection,
    final String inventorycollections,
    String costcentercollections,
    final String masterid,
  ) async {
    if (_useTallyApi) {
      return _fetchDataTallyApi(masterid);
    }
    return _fetchDataLegacy(
      ledgercollection,
      billscollection,
      inventorycollections,
      costcentercollections,
      masterid,
    );
  }

  /// tally-api path: a single `GET vouchers/:masterId` call already returns
  /// ledger/inventory/cost-centre entries together (see `VoucherRepository`),
  /// replacing the 4 separate legacy collection calls below. Bills have no
  /// tally-api equivalent for this endpoint (see `_billsUnavailable`).
  Future<void> _fetchDataTallyApi(String masterid) async {
    setState(() {
      isVisibleLedgerEntry = false;
      isVisibleBills = false;
      isVisibleInventoryEntry = false;
      isVisibleCostCenter = false;
      _billsUnavailable = false;
      _isLoading = true;
    });

    try {
      final voucherId = int.tryParse(masterid);
      if (voucherId == null) {
        throw Exception('Missing voucher masterId');
      }
      final voucher = await VoucherRepository.instance.getByMasterId(
        voucherId,
      );

      final ledgerRows =
          (voucher['ledgerEntries'] as List?)?.cast<Map<String, dynamic>>() ??
          const [];
      final inventoryRows =
          (voucher['inventoryEntries'] as List?)
              ?.cast<Map<String, dynamic>>() ??
          const [];
      final costCentreRows =
          (voucher['costCentreAllocations'] as List?)
              ?.cast<Map<String, dynamic>>() ??
          const [];

      ledgerentries_list = ledgerRows
          .map(
            (row) => LedgerEntries(
              ledger: (row['ledgerName'] ?? '').toString(),
              amount: (row['amount'] ?? '0').toString(),
            ),
          )
          .toList();

      inventoryentries_list = inventoryRows
          .map(
            (row) => InventoryEntries(
              item: (row['stockItemName'] ?? '').toString(),
              qty: (row['quantity'] ?? '0').toString(),
              rate: (row['rate'] ?? '0').toString(),
              discount: (row['discountPercentage'] ?? '0').toString(),
              amount: (row['amount'] ?? '0').toString(),
              godown: (row['godownName'] ?? 'null').toString(),
            ),
          )
          .toList();

      costcenter_list = costCentreRows
          .map(
            (row) => CostCenter(
              costcentre: (row['costCentreName'] ?? '').toString(),
              amount: (row['amount'] ?? '0').toString(),
            ),
          )
          .toList();

      setState(() {
        isVisibleLedgerEntry = ledgerentries_list.isNotEmpty;
        isVisibleInventoryEntry = inventoryentries_list.isNotEmpty;
        isVisibleCostCenter = costcenter_list.isNotEmpty;
        _billsUnavailable = true;
        _isLoading = false;
      });
    } on ApiException catch (e) {
      setState(() {
        isVisibleLedgerEntry = false;
        isVisibleBills = false;
        isVisibleInventoryEntry = false;
        isVisibleCostCenter = false;
        _isLoading = false;
      });
      showAppMessage(context, e.message);
    } catch (e) {
      setState(() {
        isVisibleLedgerEntry = false;
        isVisibleBills = false;
        isVisibleInventoryEntry = false;
        isVisibleCostCenter = false;
        _isLoading = false;
      });
    }
  }

  Future<void> _fetchDataLegacy(
    final String ledgercollection,
    final String billscollection,
    final String inventorycollections,
    String costcentercollections,
    final String masterid,
  ) async {
    setState(() {
      isVisibleLedgerEntry = false;
      isVisibleBills = false;
      isVisibleInventoryEntry = false;
      isVisibleCostCenter = false;
      _isLoading = true;
    });

    try {
      // These 4 collections are independent of each other (ledger/bills/
      // inventory/cost-center) and were previously fetched one after
      // another with `await`, adding up their latencies serially even
      // though none depends on another's result. Firing them together
      // with Future.wait cuts this screen's load time to whichever single
      // call is slowest, instead of the sum of all four.
      await Future.wait([
        _fetchLedgerEntries(ledgercollection, masterid),
        _fetchBills(billscollection, masterid),
        _fetchInventoryEntries(inventorycollections, masterid),
        _fetchCostCenter(costcentercollections, masterid),
      ]);

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        isVisibleLedgerEntry = false;
        isVisibleBills = false;
        isVisibleInventoryEntry = false;
        isVisibleCostCenter = false;
        _isLoading = false;
      });
    }
  }

  Future<void> _fetchLedgerEntries(
    String ledgercollection,
    String masterid,
  ) async {
    if (ledgerentries != 'True') return;

    final url_ledgerentry = Uri.parse(HttpURL!);

    Map<String, String> headers_ledgerentry = {
      'Authorization': 'Bearer $token',
      "Content-Type": "application/json",
    };

    var body_ledgerentry = jsonEncode({
      'collection': ledgercollection,
      'masterid': masterid,
    });

    final response_ledgerentry = await http.post(
      url_ledgerentry,
      body: body_ledgerentry,
      headers: headers_ledgerentry,
    );

    if (response_ledgerentry.statusCode == 200) {
      final List<dynamic> values_list_ledgerentry = jsonDecode(
        response_ledgerentry.body,
      );

      print('ledger entries -> ${values_list_ledgerentry}');
      if (values_list_ledgerentry != null) {
        ledgerentries_list.addAll(
          values_list_ledgerentry
              .map((json) => LedgerEntries.fromJson(json))
              .toList(),
        );

        if (!ledgerentries_list.isEmpty) {
          setState(() {
            isVisibleLedgerEntry = true;
          });
        }
      } else {
        throw Exception('Failed to fetch data');
      }
    } else {
      Map<String, dynamic> data = json.decode(response_ledgerentry.body);
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
  }

  Future<void> _fetchBills(String billscollection, String masterid) async {
    if (billsentries != 'True') return;

    final url_bills = Uri.parse(HttpURL!);

    Map<String, String> headers_bills = {
      'Authorization': 'Bearer $token',
      "Content-Type": "application/json",
    };

    var body_bills = jsonEncode({
      'collection': billscollection,
      'masterid': masterid,
    });

    final response_bills = await http.post(
      url_bills,
      body: body_bills,
      headers: headers_bills,
    );

    if (response_bills.statusCode == 200) {
      List<dynamic> values_list_bills = jsonDecode(response_bills.body);
      print('bills -> ${values_list_bills}');

      if (values_list_bills != null) {
        if (!values_list_bills.isEmpty) {
          bills_list.addAll(
            values_list_bills.map((json) => Bills.fromJson(json)).toList(),
          );
          if (bills_list.isNotEmpty) {
            for (var item in values_list_bills) {
              String billnoo = item['billno'].toString();
              String billamountt = item['amount'].toString();
              String billtypee = item['billtype'].toString();
              String billduedatee = item['duedate'].toString();
              String billdatee = item['billdate'].toString();

              if (billtypee == "On Account") {
                setState(() {
                  isTopPanelBillsVisible = false;
                  isDueDateBillsVisible = false;
                });
                billtype = billtypee;
                billamount = formatAmount(billamountt);
              } else if (billtypee == "Advance") {
                setState(() {
                  isTopPanelBillsVisible = true;
                  isDueDateBillsVisible = false;
                });
                billno = billnoo;
                billtype = billtypee;
                billamount = formatAmount(billamountt);
              } else if (billtypee == "Agst Ref" || billtypee == "New Ref") {
                setState(() {
                  isTopPanelBillsVisible = true;
                  isDueDateBillsVisible = true;
                });

                if (billduedatee == "null") {
                  billduedate = "N/A";
                } else {
                  try {
                    int days = int.parse(billduedatee.split(' ')[0]);

                    DateTime billdate_date = DateTime.parse(billdatee);

                    // Add the days to the billdate
                    DateTime dueDate = billdate_date.add(
                      Duration(days: days),
                    );
                    DateFormat dateFormat = DateFormat('dd-MMM-yy');
                    String duedateafter_string = dateFormat.format(dueDate);

                    billduedate = duedateafter_string;
                  } catch (e) {
                    billduedate = billduedatee;
                  }
                }
                billno = billnoo;
                billtype = billtypee;
                billamount = formatAmount(billamountt);
              }
            }

            setState(() {
              isVisibleBills = true;
            });
          }
        }
      } else {
        throw Exception('Failed to fetch data');
      }
    } else {
      Map<String, dynamic> data = json.decode(response_bills.body);
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
  }

  Future<void> _fetchInventoryEntries(
    String inventorycollections,
    String masterid,
  ) async {
    if (inventoryentries != 'True') return;

    final url_inventoryentry = Uri.parse(HttpURL!);

    Map<String, String> headers_inventoryentry = {
      'Authorization': 'Bearer $token',
      "Content-Type": "application/json",
    };

    var body_inventoryentry = jsonEncode({
      'collection': inventorycollections,
      'masterid': masterid,
    });

    final response_inventoryentry = await http.post(
      url_inventoryentry,
      body: body_inventoryentry,
      headers: headers_inventoryentry,
    );

    if (response_inventoryentry.statusCode == 200) {
      final List<dynamic> values_list_inventoryentry = jsonDecode(
        response_inventoryentry.body,
      );
      if (values_list_inventoryentry != null) {
        inventoryentries_list.addAll(
          values_list_inventoryentry
              .map((json) => InventoryEntries.fromJson(json))
              .toList(),
        );

        if (!inventoryentries_list.isEmpty) {
          setState(() {
            isVisibleInventoryEntry = true;
          });
        }
      } else {
        throw Exception('Failed to fetch data');
      }
    } else {
      Map<String, dynamic> data = json.decode(response_inventoryentry.body);
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
  }

  Future<void> _fetchCostCenter(
    String costcentercollections,
    String masterid,
  ) async {
    if (costcentreentries != 'True') return;

    final url_costcenter = Uri.parse(HttpURL!);

    Map<String, String> headers_costcenter = {
      'Authorization': 'Bearer $token',
      "Content-Type": "application/json",
    };

    var body_costcenter = jsonEncode({
      'collection': costcentercollections,
      'masterid': masterid,
    });

    final response_costcenter = await http.post(
      url_costcenter,
      body: body_costcenter,
      headers: headers_costcenter,
    );

    if (response_costcenter.statusCode == 200) {
      final List<dynamic> values_list_costcenter = jsonDecode(
        response_costcenter.body,
      );

      if (values_list_costcenter != null) {
        costcenter_list.addAll(
          values_list_costcenter
              .map((json) => CostCenter.fromJson(json))
              .toList(),
        );

        if (!costcenter_list.isEmpty) {
          setState(() {
            isVisibleCostCenter = true;
          });
        }
      } else {
        throw Exception('Failed to fetch data');
      }
    } else {
      Map<String, dynamic> data = json.decode(response_costcenter.body);
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
  }

  Future<void> _initSharedPreferences() async {
    prefs = await SharedPreferences.getInstance();

    setState(() {
      hostname = prefs.getString('hostname');
      company = prefs.getString('company_name');
      company_lowercase = company!.replaceAll(' ', '').toLowerCase();
      serial_no = prefs.getString('serial_no');
      username = prefs.getString('username');
      token = prefs.getString('token') ?? '';  // absent for tally-oauth-only sessions (Phase 6) - was a crashing force-unwrap
      _useTallyApi = serial_no == null || serial_no!.isEmpty;
    });

    ledgerentries = prefs.getString("ledgerentries") ?? 'False';
    inventoryentries = prefs.getString("inventoryentries") ?? 'False';
    billsentries = prefs.getString("billsentries") ?? 'False';
    costcentreentries = prefs.getString("costcentreentries") ?? 'False';

    SecuritybtnAcessHolder = prefs.getString('secbtnaccess');

    HttpURL =
        '$hostname/api/voucher/getcollection/$company_lowercase/$serial_no';

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

    fetchData("LedgerEntry", "Bills", "Inventory", "CostCentre", masterid);
  }

  List<Widget> _buildLedgerWithBillsList() {
    // Group bills by ledger (case-insensitive + trim)
    final Map<String, List<Bills>> billsByLedger = {};

    print('bills list -> $bills_list');
    for (var bill in bills_list) {
      final ledgerKey = bill.ledger.trim().toLowerCase();
      billsByLedger.putIfAbsent(ledgerKey, () => []).add(bill);
    }

    return ledgerentries_list.map((entry) {
      final key = entry.ledger.trim().toLowerCase();
      final relatedBills = billsByLedger[key] ?? [];
      return LedgerExpandableTile(
        ledgerName: entry.ledger,
        amount: entry.amount,
        bills: relatedBills,
      );
    }).toList();
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

  String formatDate(String d) {
    if (d == '' || d == 'null') return 'N/A';
    try {
      return DateFormat('dd-MMM-yyyy').format(DateTime.parse(d));
    } catch (_) {
      return d;
    }
  }

  LinearGradient iconGradient() => const LinearGradient(
    colors: [Color(0xFF00B4DB), Color(0xFF0083B0)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: const AppBottomNav(
        activeTab: AppBottomNavTab.transactions,
      ),
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
          title: GestureDetector(
            onTap: () => navigateToCompanySwitch(context),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    company ?? '',

                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                SizedBox(width: 2),
                Icon(Icons.arrow_drop_down, color: Colors.white, size: 20),
              ],
            ),
          ),
          centerTitle: false,
          actions: [],
        ),
      ),

      body: Stack(
        children: [
          SingleChildScrollView(
            child: Column(
              children: [
                _buildVoucherCard(),

                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 0,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 10,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      if (isVisibleLedgerEntry)
                        ModernExpandableCard(
                          title: 'Accounting Details',
                          icon: Icons.account_balance,
                          children: [..._buildLedgerWithBillsList()],
                        ),

                      /*if (isVisibleBills)
                        ModernExpandableCard(
                          title: 'Reference Details',
                          icon: Icons.description_outlined,
                          children: [
                            if (isTopPanelBillsVisible)
                              buildBillRow('Bill No', billno, Icons.receipt_long),
                            if (isDueDateBillsVisible)
                              buildBillRow('Due Date', billduedate, Icons.calendar_today),
                            buildBillRow('Bill Type', billtype, Icons.label_important_outline),
                            buildBillRow('Amount', billamount, Icons.money),
                          ],
                        ),*/
                      if (isVisibleInventoryEntry)
                        ModernExpandableCard(
                          title: 'Item Details',
                          icon: Icons.inventory_2_outlined,
                          children: [
                            ...inventoryentries_list
                                .take(visibleInventoryCount)
                                .map(
                                  (card) => Column(
                                    children: [
                                      buildInventoryRow(
                                        context,
                                        'Item',
                                        card.item,
                                        'Qty',
                                        formatNullto0(card.qty),
                                        leftIcon: Icons.inventory_outlined,
                                        rightIcon:
                                            Icons.confirmation_num_outlined,
                                      ),
                                      buildInventoryRow(
                                        context,
                                        'Rate',
                                        '',
                                        'Disc',
                                        "${formatNullto0(card.discount)}%",
                                        leftIcon: Icons.price_change,
                                        rightIcon: Icons.percent,
                                        leftValueWidget: _inventoryRateWidget(
                                          card.rate,
                                          GoogleFonts.poppins(
                                            fontSize: 13.5,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurface,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                      buildInventoryRow(
                                        context,
                                        'Godown',
                                        handleGodown(card.godown),
                                        'Amt',
                                        '',
                                        leftIcon: Icons.store,
                                        rightIcon: Icons.money,
                                        rightValueWidget: formatAmountRich(
                                          card.amount,
                                          style: GoogleFonts.poppins(
                                            fontSize: 13.5,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurface,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                      const Divider(height: 24, thickness: 0.6),
                                    ],
                                  ),
                                )
                                .toList(),

                            if (inventoryentries_list.length > 3)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8.0,
                                ),
                                child: Center(
                                  child: TextButton(
                                    onPressed: () {
                                      setState(() {
                                        if (isInventoryExpanded) {
                                          visibleInventoryCount = 3;
                                          isInventoryExpanded = false;
                                        } else {
                                          visibleInventoryCount =
                                              inventoryentries_list.length;
                                          isInventoryExpanded = true;
                                        }
                                      });
                                    },
                                    child: Text(
                                      isInventoryExpanded
                                          ? 'View Less'
                                          : 'View More',
                                      style: GoogleFonts.poppins(
                                        color: app_color,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),

                      if (isVisibleCostCenter)
                        ModernExpandableCard(
                          title: 'Cost Centre Details',
                          icon: Icons.account_tree_outlined,
                          children: [
                            ...costcenter_list
                                .take(visibleCostCenterCount)
                                .map(
                                  (card) => buildCostCenterRow(
                                    context,
                                    formatCostCenter(card.costcentre),
                                    card.amount,
                                  ),
                                )
                                .toList(),

                            if (costcenter_list.length > 3)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8.0,
                                ),
                                child: Center(
                                  child: TextButton(
                                    onPressed: () {
                                      setState(() {
                                        if (isCostCenterExpanded) {
                                          visibleCostCenterCount = 3;
                                          isCostCenterExpanded = false;
                                        } else {
                                          visibleCostCenterCount =
                                              costcenter_list.length;
                                          isCostCenterExpanded = true;
                                        }
                                      });
                                    },
                                    child: Text(
                                      isCostCenterExpanded
                                          ? 'View Less'
                                          : 'View More',
                                      style: GoogleFonts.poppins(
                                        color: app_color,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),

                // Add bottom spacing
                const SizedBox(height: 20),
              ],
            ),
          ),

          // Skeleton stays outside of scrollable content, overlaying the
          // whole screen while the initial fetch is in flight - replaces
          // the old dimmed spinner-over-stale-content overlay so the
          // loading state reads as "content incoming" instead of a blank
          // page.
          if (_isLoading)
            Positioned.fill(
              child: Container(
                color: Theme.of(context).scaffoldBackgroundColor,
                child: _buildSkeletonDetail(),
              ),
            ),
        ],
      ),
    );
  }

  // Skeleton stand-in for the voucher detail card + expandable
  // accounting/inventory rows - mirrors _buildVoucherCard's icon-row
  // layout at a generic level (icon + label line + value line, repeated),
  // plus a couple of section blocks for the expandable ledger/cost-center
  // lists further down the page.
  Widget _buildSkeletonDetail() {
    return ShimmerLoading(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 90),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.blueGrey.withOpacity(0.1),
                  blurRadius: 12,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (int i = 0; i < 4; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        const ShimmerBox(
                          width: 32,
                          height: 32,
                          borderRadius: 10,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const ShimmerBox(height: 10, width: 80),
                              const SizedBox(height: 6),
                              ShimmerBox(
                                height: 13,
                                width: MediaQuery.of(context).size.width * 0.4,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          for (int i = 0; i < 2; i++)
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.blueGrey.withOpacity(0.1),
                    blurRadius: 12,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const ShimmerBox(height: 14, width: 120),
                  const SizedBox(height: 10),
                  const ShimmerBox(height: 40, borderRadius: 12),
                  const SizedBox(height: 8),
                  const ShimmerBox(height: 40, borderRadius: 12),
                  const SizedBox(height: 8),
                  const ShimmerBox(height: 40, borderRadius: 12),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildVoucherCard() {
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(left: 12, right: 12, top: 8, bottom: 0),

      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.blueGrey.withOpacity(0.1),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.ledger.trim().isNotEmpty && widget.ledger != 'null')
            _buildRow(Icons.person_outline, "Party", widget.ledger),
          _buildRow(Icons.receipt_long_rounded, "Voucher No", widget.vchno),
          _buildRow(
            Icons.calendar_today,
            "Voucher Date",
            formatDate(widget.vchdate),
          ),
          if (widget.refno != 'null')
            _buildRow(
              Icons.confirmation_number_outlined,
              "Ref No",
              widget.refno,
            ),
          if (widget.refdate != 'null')
            _buildRow(
              Icons.date_range_outlined,
              "Ref Date",
              formatDate(widget.refdate),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            children: [
              if (widget.ispostdated == "1")
                _chip("Post Dated", const Color(0xFF00B4DB)),
              if (widget.isoptional == "1")
                _chip("Optional", const Color(0xFF8E2DE2)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRow(IconData icon, String label, String value) {
    // 🌈 Assign a unique gradient color based on the icon type
    LinearGradient getIconGradient() {
      if (icon == Icons.person_outline) {
        return const LinearGradient(
          colors: [Color(0xFF11998E), Color(0xFF38EF7D)], // teal-green
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      } else if (icon == Icons.receipt_long_rounded) {
        return const LinearGradient(
          colors: [Color(0xFFFF9966), Color(0xFFFF5E62)], // orange-red
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      } else if (icon == Icons.calendar_today ||
          icon == Icons.calendar_month ||
          icon == Icons.date_range_outlined) {
        return const LinearGradient(
          colors: [Color(0xFF56CCF2), Color(0xFF2F80ED)], // blue gradient
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      } else if (icon == Icons.confirmation_number_outlined) {
        return const LinearGradient(
          colors: [Color(0xFF00B09B), Color(0xFF96C93D)], // green gradient
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      } else {
        return const LinearGradient(
          colors: [Color(0xFF8E2DE2), Color(0xFF4A00E0)], // purple default
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          // 🎨 Rounded gradient icon background
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: getIconGradient(),
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: Colors.black12.withOpacity(0.1),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Center(child: Icon(icon, size: 18, color: Colors.white)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              "$label",
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withOpacity(0.8), color.withOpacity(0.5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.circle, size: 8, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            text,
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class ModernExpandableCard extends StatefulWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const ModernExpandableCard({
    required this.title,
    required this.icon,
    required this.children,
    super.key,
  });

  @override
  State<ModernExpandableCard> createState() => _ModernExpandableCardState();
}

class _ModernExpandableCardState extends State<ModernExpandableCard>
    with SingleTickerProviderStateMixin {
  bool _isExpanded = false;
  bool _isHovered = false;

  // 🌈 Unique gradient per icon type
  LinearGradient _getIconGradient(IconData icon) {
    if (icon == Icons.account_balance_wallet_rounded) {
      return const LinearGradient(
        colors: [Color(0xFF00C9FF), Color(0xFF92FE9D)], // cyan-green
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
    } else if (icon == Icons.receipt_long_rounded ||
        icon == Icons.description_outlined) {
      return const LinearGradient(
        colors: [Color(0xFFFF9966), Color(0xFFFF5E62)], // orange-red
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
    } else if (icon == Icons.inventory_2_outlined) {
      return const LinearGradient(
        colors: [Color(0xFF56CCF2), Color(0xFF2F80ED)], // blue
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
    } else if (icon == Icons.account_tree_outlined) {
      return const LinearGradient(
        colors: [Color(0xFF8E2DE2), Color(0xFF4A00E0)], // purple
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
    } else {
      return const LinearGradient(
        colors: [Color(0xFF11998E), Color(0xFF38EF7D)], // green
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final LinearGradient borderGradient = _getIconGradient(widget.icon);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        transform: Matrix4.translationValues(0, _isHovered ? -2 : 0, 0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Theme.of(context).cardColor,
          boxShadow: [
            BoxShadow(
              color: _isHovered
                  ? borderGradient.colors.first.withOpacity(0.25)
                  : Colors.black12.withOpacity(0.05),
              blurRadius: _isHovered ? 16 : 8,
              offset: const Offset(0, 5),
            ),
          ],
          border: Border.all(
            width: 1.3,
            color: _isHovered
                ? borderGradient.colors.last.withOpacity(0.5)
                : Theme.of(context).brightness == Brightness.dark
                ? Colors.white.withOpacity(0.10)
                : Colors.transparent,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          splashColor: borderGradient.colors.last.withOpacity(0.08),
          highlightColor: Colors.transparent,
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    // 🌈 Gradient background for icon
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        gradient: _getIconGradient(widget.icon),
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: borderGradient.colors.last.withOpacity(0.25),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Icon(widget.icon, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.title,
                        style: GoogleFonts.poppins(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                    AnimatedRotation(
                      turns: _isExpanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 250),
                      child: Icon(
                        Icons.expand_more,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),

              // 🔽 Expandable content
              AnimatedSize(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: _isExpanded
                      ? const BoxConstraints()
                      : const BoxConstraints(maxHeight: 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: widget.children,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget buildLedgerRow(String ledger, String amount) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
    child: LayoutBuilder(
      builder: (context, constraints) {
        double halfWidth = constraints.maxWidth / 2;

        return Row(
          children: [
            // Left side (icon + name)
            SizedBox(
              width: halfWidth,
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF00C9FF), Color(0xFF92FE9D)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.all(Radius.circular(8)),
                    ),
                    child: const Icon(
                      Icons.account_balance_wallet_rounded,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      ledger,
                      maxLines: 2,
                      softWrap: true,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Right side (amount)
            SizedBox(
              width: halfWidth,
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  amount,
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  softWrap: true,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.tealAccent.shade100
                        : Colors.teal.shade700, // softer than green
                  ),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}

Widget buildBillRow(
  BuildContext context,
  String label,
  String value,
  IconData icon,
) {
  LinearGradient gradient = const LinearGradient(
    colors: [Color(0xFFFF9966), Color(0xFFFF5E62)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
    child: Row(
      children: [
        // 🔸 Icon
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 14, color: Colors.white),
        ),
        const SizedBox(width: 8),

        // 🔸 Label
        Text(
          '$label:',
          style: GoogleFonts.poppins(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),

        const SizedBox(width: 8),

        // 🔸 Value (right aligned, ellipsis if too long)
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              textAlign: TextAlign.right,
              style: GoogleFonts.poppins(
                fontSize: 13.5,
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

// Currency-aware rate display for buildInventoryRow's "Rate" field - shows
// the Dirham glyph for AED instead of a bare, symbol-less number.
Widget _inventoryRateWidget(String rate, TextStyle style) {
  if (rate == 'null' || rate.trim().isEmpty) {
    return Text('Not Available', style: style);
  }
  // Rate arrives as "209.00/Nos" (number/unit) - split off the unit suffix
  // before parsing, otherwise double.tryParse on the whole string fails
  // and silently falls back to 0.
  String cleaned = rate.trim();
  String unit = "";
  if (cleaned.contains("/")) {
    final parts = cleaned.split("/");
    cleaned = parts[0];
    unit = "/${parts.sublist(1).join("/")}";
  }
  final parsed = double.tryParse(cleaned.replaceAll(',', '')) ?? 0.0;
  final parts = CurrencyFormatter.formatCurrencyParts(parsed);
  final currencyCode = CurrencyFormatter.getCurrencyCode();
  return Text.rich(
    TextSpan(
      children: [
        currencySymbolSpan(currencyCode, parts.symbol, style),
        TextSpan(text: ' ${parts.number}$unit', style: style),
      ],
    ),
    softWrap: true,
  );
}

Widget buildInventoryRow(
  BuildContext context,
  String leftLabel,
  String leftValue,
  String rightLabel,
  String rightValue, {
  IconData? leftIcon,
  IconData? rightIcon,
  Widget? leftValueWidget,
  Widget? rightValueWidget,
}) {
  return Container(
    margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
    decoration: BoxDecoration(color: Theme.of(context).cardColor),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // 🔹 Top Row: Left + Right info side-by-side (wraps if text is long)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 🔸 Left Section
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (leftIcon != null)
                    Container(
                      width: 30,
                      height: 30,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF56CCF2), Color(0xFF2F80ED)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.all(Radius.circular(8)),
                      ),
                      child: Icon(leftIcon, size: 16, color: Colors.white),
                    ),
                  if (leftIcon != null) const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          leftLabel,
                          style: GoogleFonts.poppins(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 2),
                        leftValueWidget ??
                            Text(
                              leftValue,
                              softWrap: true,
                              style: GoogleFonts.poppins(
                                fontSize: 13.5,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            SizedBox(width: 9),

            // 🔸 Right Section
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (rightIcon != null)
                    Container(
                      width: 30,
                      height: 30,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF8E2DE2), Color(0xFF4A00E0)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.all(Radius.circular(8)),
                      ),
                      child: Icon(rightIcon, size: 16, color: Colors.white),
                    ),
                  if (rightIcon != null) const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          rightLabel,
                          style: GoogleFonts.poppins(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 2),
                        rightValueWidget ??
                            Text(
                              rightValue,
                              softWrap: true,
                              style: GoogleFonts.poppins(
                                fontSize: 13.5,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

Widget buildCostCenterRow(
  BuildContext context,
  String costCentre,
  String amount,
) {
  return Container(
    width: double.infinity,
    margin: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(18),
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
        // 🔹 Top Row: Cost Centre Label with Icon
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF11998E), Color(0xFF38EF7D)], // green
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.all(Radius.circular(8)),
              ),
              child: const Icon(
                Icons.account_tree_outlined,
                size: 16,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                costCentre,
                softWrap: true,
                style: GoogleFonts.poppins(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 10),

        // 🔹 Bottom Row: Amount aligned to the right
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFFF9966), Color(0xFFFF5E62)], // orange
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.all(Radius.circular(8)),
              ),
              child: const Icon(Icons.money, size: 16, color: Colors.white),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: formatAmountRich(
                amount,
                textAlign: TextAlign.right,
                softWrap: true,
                style: GoogleFonts.poppins(
                  fontSize: 13.5,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class LedgerExpandableTile extends StatefulWidget {
  final String ledgerName;
  final String amount;
  final List<Bills> bills;

  const LedgerExpandableTile({
    Key? key,
    required this.ledgerName,
    required this.amount,
    required this.bills,
  }) : super(key: key);

  @override
  State<LedgerExpandableTile> createState() => _LedgerExpandableTileState();
}

class _LedgerExpandableTileState extends State<LedgerExpandableTile>
    with SingleTickerProviderStateMixin {
  bool _isExpanded = false;
  TextEditingController _searchController = TextEditingController();
  List<Bills> _filteredBills = [];
  @override
  void initState() {
    super.initState();
    _filteredBills = widget.bills; // initialize with all bills

    print('bills -> $_filteredBills');
    _searchController.addListener(_filterBills);
  }

  String _formatSafeDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty || dateStr == "null") {
      return "N/A";
    }
    try {
      final parsed = DateTime.tryParse(dateStr);
      if (parsed == null) return "N/A";
      return DateFormat('dd-MMM-yyyy').format(parsed);
    } catch (_) {
      return "N/A";
    }
  }

  String _formatSafeText(String? value) {
    if (value == null || value.isEmpty || value == "null") {
      return "N/A";
    }
    return value;
  }

  void _filterBills() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredBills = widget.bills
          .where((bill) => bill.billno.toString().toLowerCase().contains(query))
          .toList();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant LedgerExpandableTile oldWidget) {
    super.didUpdateWidget(oldWidget);

    // If new bills are loaded (e.g., after fetchData completes)
    if (oldWidget.bills != widget.bills) {
      setState(() {
        _filteredBills = widget.bills;
      });
    }
  }

  LinearGradient iconGradient(IconData icon) {
    if (icon == Icons.receipt_long) {
      return const LinearGradient(
        colors: [Color(0xFFFF9966), Color(0xFFFF5E62)], // orange-red
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
    } else if (icon == Icons.calendar_today || icon == Icons.calendar_month) {
      return const LinearGradient(
        colors: [Color(0xFF56CCF2), Color(0xFF2F80ED)], // blue
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
    } else if (icon == Icons.label_important_outline) {
      return const LinearGradient(
        colors: [Color(0xFF00B09B), Color(0xFF96C93D)], // green
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
    } else {
      return const LinearGradient(
        colors: [Color(0xFF11998E), Color(0xFF38EF7D)], // teal-green
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool hasBills = widget.bills.isNotEmpty;
    LinearGradient iconGradient(IconData icon) {
      if (icon == Icons.receipt_long) {
        return const LinearGradient(
          colors: [Color(0xFFFF9966), Color(0xFFFF5E62)], // orange-red
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      } else if (icon == Icons.calendar_today || icon == Icons.calendar_month) {
        return const LinearGradient(
          colors: [Color(0xFF56CCF2), Color(0xFF2F80ED)], // blue
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      } else if (icon == Icons.label_important_outline) {
        return const LinearGradient(
          colors: [Color(0xFF00B09B), Color(0xFF96C93D)], // green
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      } else {
        return const LinearGradient(
          colors: [Color(0xFF11998E), Color(0xFF38EF7D)], // teal-green
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      }
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black12.withOpacity(0.06),
            blurRadius: 6,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: hasBills && _isExpanded
              ? Colors.teal.withOpacity(0.4)
              : Colors.transparent,
          width: 1.2,
        ),
      ),
      child: Column(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: hasBills
                ? () => setState(() => _isExpanded = !_isExpanded)
                : null,
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF00C9FF), Color(0xFF92FE9D)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                  ),
                  child: const Icon(
                    Icons.account_balance_wallet_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.ledgerName,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
                formatAmountRich(
                  widget.amount,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.tealAccent.shade100
                        : Colors.teal.shade700,
                  ),
                ),
                if (hasBills)
                  AnimatedRotation(
                    turns: _isExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 250),
                    child: Icon(
                      Icons.expand_more,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),

          // 🔽 Expandable bill section
          AnimatedSize(
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeInOut,
            child: _isExpanded
                ? AnimatedOpacity(
                    opacity: _isExpanded ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 300),
                    child: Padding(
                      padding: const EdgeInsets.only(
                        left: 6,
                        top: 12,
                        right: 6,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 🔍 Search Field
                          SizedBox(
                            height: 46,
                            child: TextField(
                              controller: _searchController,
                              decoration: InputDecoration(
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                prefixIcon: Icon(
                                  Icons.search,
                                  size: 18,
                                  color:
                                      Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? Colors.tealAccent.shade100
                                      : Colors.teal.shade600,
                                ),
                                hintText: "Search by Bill No...",
                                hintStyle: GoogleFonts.poppins(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                  fontSize: 13,
                                ),
                                filled: true,
                                fillColor:
                                    Theme.of(context).brightness ==
                                            Brightness.dark
                                        ? Colors.white.withOpacity(0.06)
                                        : Colors.grey.shade100,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(24),
                                  borderSide: BorderSide.none,
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
                              ),

                              style: GoogleFonts.poppins(
                                color: Theme.of(context).colorScheme.onSurface,
                                fontSize: 13.5,
                              ),
                            ),
                          ),

                          const SizedBox(height: 14),

                          // 🧾 Bills List or Empty State
                          _filteredBills.isNotEmpty
                              ? Column(
                                  children: _filteredBills.asMap().entries.map((
                                    entry,
                                  ) {
                                    final index = entry.key + 1;
                                    final bill = entry.value;

                                    // 🎨 Bill type color scheme
                                    final bool isDark =
                                        Theme.of(context).brightness ==
                                        Brightness.dark;
                                    Color chipColor;
                                    Color chipTextColor;
                                    switch (bill.billtype) {
                                      case 'New Ref':
                                        chipColor = Colors.orange.withOpacity(
                                          isDark ? 0.18 : 0.12,
                                        );
                                        chipTextColor = isDark
                                            ? Colors.orange.shade200
                                            : Colors.orange.shade700;
                                        break;
                                      case 'Advance':
                                        chipColor = Colors.blue.withOpacity(
                                          isDark ? 0.18 : 0.12,
                                        );
                                        chipTextColor = isDark
                                            ? Colors.blue.shade200
                                            : Colors.blue.shade700;
                                        break;
                                      case 'On Account':
                                        chipColor = Colors.green.withOpacity(
                                          isDark ? 0.18 : 0.12,
                                        );
                                        chipTextColor = isDark
                                            ? Colors.green.shade200
                                            : Colors.green.shade700;
                                        break;
                                      default:
                                        chipColor = Theme.of(
                                          context,
                                        ).colorScheme.surfaceContainerHighest;
                                        chipTextColor = Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant;
                                    }

                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 10),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 12,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .surfaceContainerHighest
                                            .withOpacity(
                                              Theme.of(context).brightness ==
                                                      Brightness.dark
                                                  ? 0.72
                                                  : 0.36,
                                            ),
                                        borderRadius: BorderRadius.circular(18),
                                        border: Border.all(
                                          color: Colors.teal.withOpacity(0.15),
                                          width: 1,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.teal.withOpacity(
                                              0.05,
                                            ),
                                            blurRadius: 6,
                                            offset: const Offset(0, 3),
                                          ),
                                        ],
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          // Bill Header
                                          Row(
                                            children: [
                                              Text(
                                                "Bill #$index",
                                                style: GoogleFonts.poppins(
                                                  fontSize: 13.8,
                                                  fontWeight: FontWeight.w700,
                                                  color:
                                                      Theme.of(
                                                            context,
                                                          ).brightness ==
                                                          Brightness.dark
                                                      ? Colors
                                                            .tealAccent
                                                            .shade100
                                                      : Colors.teal.shade700,
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                      vertical: 4,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: chipColor,
                                                  borderRadius:
                                                      BorderRadius.circular(20),
                                                ),
                                                child: Text(
                                                  bill.billtype,
                                                  style: GoogleFonts.poppins(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                    color: chipTextColor,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),

                                          // Bill Details
                                          _billRow(
                                            Icons.receipt_long,
                                            'Bill No',
                                            _formatSafeText(bill.billno),
                                          ),
                                          _billRow(
                                            Icons.calendar_today,
                                            'Bill Date',
                                            _formatSafeDate(bill.billdate),
                                          ),

                                          _billRow(
                                            Icons.calendar_month,
                                            'Due Date',
                                            _getFormattedDueDate(
                                              bill.billtype,
                                              bill.billdate,
                                              bill.duedate,
                                            ),
                                          ),
                                          _billRow(
                                            Icons.attach_money,
                                            'Amount',
                                            '',
                                            valueWidget: formatAmountRich(
                                              bill.amount,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              textAlign: TextAlign.right,
                                              style: GoogleFonts.poppins(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w500,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSurface,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                )
                              : Center(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 50,
                                    ),
                                    child: Column(
                                      children: [
                                        Icon(
                                          Icons.receipt_long_outlined,
                                          size: 60,
                                          color: Colors.teal.shade300,
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          "No bills found",
                                          style: GoogleFonts.poppins(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurface,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          "Try searching with a different Bill No.",
                                          style: GoogleFonts.poppins(
                                            fontSize: 13,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                        ],
                      ),
                    ),
                  )
                : const SizedBox(),
          ),
        ],
      ),
    );
  }

  String _getFormattedDueDate(
    String billType,
    String billDate,
    String dueDate,
  ) {
    // For "On Account" or "Advance" → No due date shown
    if (billType == "On Account" || billType == "Advance") {
      return "N/A";
    }

    // For "Agst Ref" or "New Ref" → calculate due date if numeric days provided
    if (billType == "Agst Ref" || billType == "New Ref") {
      if (dueDate == "null" ||
          dueDate.isEmpty ||
          billDate == "null" ||
          billDate.isEmpty) {
        return "N/A";
      }

      try {
        // Check if dueDate is numeric (e.g., "30 days")
        final parts = dueDate.split(' ');
        final days = int.tryParse(parts[0]);

        if (days != null) {
          final billDateParsed = DateTime.tryParse(billDate);
          if (billDateParsed == null) return "N/A";

          final due = billDateParsed.add(Duration(days: days));
          return DateFormat('dd-MMM-yyyy').format(due);
        } else {
          // If not numeric (maybe already a date string), try parsing it directly
          final parsed = DateTime.tryParse(dueDate);
          return parsed != null
              ? DateFormat('dd-MMM-yyyy').format(parsed)
              : dueDate;
        }
      } catch (e) {
        return "N/A"; // fallback on any parsing error
      }
    }

    // Default case → return N/A for invalid or null
    if (dueDate == "null" || dueDate.isEmpty) {
      return "N/A";
    }

    final parsedDefault = DateTime.tryParse(dueDate);
    return parsedDefault != null
        ? DateFormat('dd-MMM-yyyy').format(parsedDefault)
        : dueDate;
  }

  Widget _billRow(
    IconData icon,
    String label,
    String value, {
    Widget? valueWidget,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 🎨 Gradient icon
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              gradient: iconGradient(icon),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 14, color: Colors.white),
          ),
          const SizedBox(width: 10),

          // 🏷️ Label on the left
          Expanded(
            child: Text(
              "$label:",
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),

          // 💰 Value fixed to the right
          SizedBox(
            width: 130, // 👈 you can adjust based on your layout width
            child: Align(
              alignment: Alignment.centerRight,
              child:
                  valueWidget ??
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
