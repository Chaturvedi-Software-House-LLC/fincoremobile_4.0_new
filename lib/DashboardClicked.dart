import 'dart:convert';
import 'widgets/scroll_fab.dart';
import 'package:FincoreGo/currencyFormat.dart';
import 'package:FincoreGo/utils/currency_helper.dart';
import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'Dashboard.dart';
import 'SerialSelect.dart';
import 'TransactionClicked.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'constants.dart';
import 'package:cross_file/cross_file.dart';
import 'package:FincoreGo/widgets/app_bottom_nav.dart';
import 'package:FincoreGo/widgets/app_navigation.dart';
import 'widgets/entry_widgets.dart';

class LedgerGroup {
  final String ledger;
  final double amount;
  final double opening;

  LedgerGroup({
    required this.ledger,
    required this.amount,
    required this.opening,
  });

  factory LedgerGroup.fromJson(Map<String, dynamic> json) {
    return LedgerGroup(
      ledger: json['ledger']?.toString() ?? '',
      amount: double.tryParse(json['amount'].toString()) ?? 0.0,
      opening: double.tryParse(json['opening'].toString()) ?? 0.0, // ✅ NEW
    );
  }
}

class Sale_purc_cash {
  final String vchname;
  final String vchno;
  final double amount;
  final String vchdate;
  final String ledger;
  final String isoptional;
  final String ispostdated;
  final String refno;
  final String refdate;
  final String masterid;
  final List<LedgerEntry> ledgers;

  Sale_purc_cash({
    required this.vchname,
    required this.vchno,
    required this.amount,
    required this.vchdate,
    required this.ledger,
    required this.isoptional,
    required this.ispostdated,
    required this.refno,
    required this.refdate,
    required this.masterid,
    required this.ledgers,
  });

  factory Sale_purc_cash.fromJson(Map<String, dynamic> json) {
    return Sale_purc_cash(
      vchname: json['vchname'].toString(),
      vchno: json['vchno'].toString(),
      amount: json['received'] != null
          ? double.tryParse(json['received'].toString()) ?? 0.0
          : double.tryParse(json['amount'].toString()) ?? 0.0,
      vchdate: json['vchdate'].toString(),
      ledger: json['ledger'].toString(),
      isoptional: json['isoptional'].toString(),
      ispostdated: json['ispostdated'].toString(),
      refno: json['refno'].toString(),
      refdate: json['refdate'].toString(),
      masterid: json['masterid'].toString(),
      ledgers:
          (json['ledgers'] as List<dynamic>?)
              ?.map((e) => LedgerEntry.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

class LedgerEntry {
  final String ledgername;
  final double amount;

  LedgerEntry({required this.ledgername, required this.amount});

  factory LedgerEntry.fromJson(Map<String, dynamic> json) {
    return LedgerEntry(
      ledgername: json['ledgername']?.toString() ?? '',
      amount: double.tryParse(json['amount'].toString()) ?? 0.0,
    );
  }
}

class Receivable_payable {
  final String ledger, billno, billdate, billtype, duedate;
  double outstanding;

  Receivable_payable({
    required this.ledger,
    required this.billno,
    required this.billdate,
    required this.billtype,
    required this.duedate,
    required this.outstanding,
  });

  factory Receivable_payable.fromJson(Map<String, dynamic> json) {
    return Receivable_payable(
      ledger: json['ledger'].toString(),
      billno: json['billno'].toString(),
      billdate: json['billdate'].toString(),
      billtype: json['billtype'].toString(),
      duedate: json['duedate'].toString(),
      outstanding: double.tryParse(json['outstanding'].toString()) ?? 0,
    );
  }
}

class AgeingBucket {
  final String label;
  int count = 0;
  double amount = 0;
  final List<Receivable_payable> items = [];

  AgeingBucket(this.label);
}

// --------------------
// Background parsing helpers (NO UI code here)
// --------------------

class _SalesTotalParsed {
  final String opening;
  final List<Sale_purc_cash> items;

  _SalesTotalParsed({required this.opening, required this.items});
}

class _ReceivableTotalParsed {
  final String opening;
  final List<Receivable_payable> items;

  _ReceivableTotalParsed({required this.opening, required this.items});
}

// ✅ Must be top-level/static for compute()
_SalesTotalParsed _parseSalesTotalResponse(String body) {
  final Map<String, dynamic> data = jsonDecode(body) as Map<String, dynamic>;
  final String opening = (data['opening'] ?? '').toString();

  final List<dynamic> values = (data['values'] ?? []) as List<dynamic>;
  final items = values
      .map((e) => Sale_purc_cash.fromJson(e as Map<String, dynamic>))
      .toList();

  return _SalesTotalParsed(opening: opening, items: items);
}

// ✅ Must be top-level/static for compute()
_ReceivableTotalParsed _parseReceivableTotalResponse(String body) {
  final Map<String, dynamic> data = jsonDecode(body) as Map<String, dynamic>;
  final String opening = (data['opening'] ?? '').toString();

  final List<dynamic> values = (data['values'] ?? []) as List<dynamic>;
  final items = values
      .map((e) => Receivable_payable.fromJson(e as Map<String, dynamic>))
      .toList();

  return _ReceivableTotalParsed(opening: opening, items: items);
}

// ✅ Must be top-level/static for compute()
List<Sale_purc_cash> _parseReceiptPaymentResponse(String body) {
  final List<dynamic> values = jsonDecode(body) as List<dynamic>;
  return values
      .map((e) => Sale_purc_cash.fromJson(e as Map<String, dynamic>))
      .toList();
}

class DashboardClicked extends StatefulWidget {
  final String startdate_string, enddate_string, vchtypes;

  const DashboardClicked({
    required this.startdate_string,
    required this.enddate_string,
    required this.vchtypes,
  });
  @override
  _DashboardClickedPageState createState() => _DashboardClickedPageState(
    startDateString: startdate_string,
    endDateString: enddate_string,
    vchtypes: vchtypes,
  );
}

class _DashboardClickedPageState extends State<DashboardClicked>
    with TickerProviderStateMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  String startDateString = "", endDateString = "", vchtypes = "";

  String selectedSortOption = '', token = '';

  int counter = 0;

  bool _isVisibleduedate = false;

  bool _isLedgerGroupVisible = false;
  String? _selectedLedgerGroup;
  List<LedgerGroup> ledgerGroupList = [];

  bool _isAgeingView = false;
  bool _isAgeingComputing = false;
  List<AgeingBucket> _ageingBuckets = [];
  AgeingBucket? _selectedAgeingBucket;

  List<Receivable_payable> filteredItems_receivable_payable =
      []; // Initialize an empty list to hold the filtered items
  List<Sale_purc_cash> filteredItems_sale_purc_cash = [];

  List<LedgerGroup> filteredLedgerGroupList = [];
  ScrollController _scrollController_salelist = ScrollController();
  ScrollController _scrollController_receivablellist = ScrollController();
  final ScrollController _scrollFabController = ScrollController();
  TextEditingController _voucherController = TextEditingController();

  _DashboardClickedPageState({
    required this.startDateString,
    required this.endDateString,
    required this.vchtypes,
  });

  String? SecuritybtnAcessHolder;
  bool isDashEnable = true,
      isRolesEnable = true,
      isUserEnable = true,
      isRolesVisible = true,
      isUserVisible = true,
      _isSearchViewVisible = false,
      _isSalesListVisible = false,
      _isOutstandingListVisible = false;

  String email = "";
  String name = "";

  String? opening_value = "0", openingheading = "";

  TextEditingController searchController = TextEditingController();

  bool isVisibleNoDataFound = false, _isopeningVisible = true;

  bool isSortVisible = false;

  int getExtraLedgerCount(List<LedgerEntry>? ledgers, String mainLedger) {
    if (ledgers == null || ledgers.isEmpty) return 0;

    return ledgers
        .where((l) => l.ledgername.toLowerCase() != mainLedger.toLowerCase())
        .length;
  }

  // 🔍 SEARCH LOGIC
  void _onSearchChanged(String query) {
    final q = query.toLowerCase();

    if (vchtypes == "Cash" && _isLedgerGroupVisible) {
      setState(() {
        filteredLedgerGroupList = ledgerGroupList.where((item) {
          return item.ledger.toLowerCase().contains(q);
        }).toList();
      });
    }
    // 🟢 STEP 2: SELECTED LEDGER VOUCHERS SEARCH
    else if (vchtypes == "Cash" && !_isLedgerGroupVisible) {
      setState(() {
        filteredItems_sale_purc_cash = sales_purc_cash_list.where((item) {
          return item.ledger.toLowerCase() ==
                  _selectedLedgerGroup?.toLowerCase() &&
              (item.vchno.toLowerCase().contains(q) ||
                  item.vchname.toLowerCase().contains(q) ||
                  item.ledger.toLowerCase().contains(q));
        }).toList();
      });
    } else if (vchtypes == "Receivable" || vchtypes == "Payable") {
      setState(() {
        filteredItems_receivable_payable = receivable_payable_list.where((
          item,
        ) {
          return item.ledger.toLowerCase().contains(q) ||
              item.billno.toLowerCase().contains(q) ||
              item.billtype.toLowerCase().contains(q);
        }).toList();
      });
    } else if (vchtypes == "Cash") {
      setState(() {
        filteredLedgerGroupList = ledgerGroupList.where((item) {
          return item.ledger.toLowerCase().contains(q);
        }).toList();
      });
    } else {
      setState(() {
        filteredItems_sale_purc_cash = sales_purc_cash_list.where((item) {
          return item.vchno.toLowerCase().contains(q) ||
              item.vchname.toLowerCase().contains(q) ||
              item.ledger.toLowerCase().contains(q);
        }).toList();
      });
    }
  }

  // 🔄 RESET SEARCH
  void _resetSearch() {
    setState(() {
      if (vchtypes == "Receivable" || vchtypes == "Payable") {
        filteredItems_receivable_payable = List.from(receivable_payable_list);
      } else if (vchtypes == "Cash" && _isLedgerGroupVisible) {
        filteredLedgerGroupList = List.from(ledgerGroupList);
      } else if (vchtypes == "Cash" && !_isLedgerGroupVisible) {
        filteredItems_sale_purc_cash = sales_purc_cash_list
            .where(
              (item) =>
                  item.ledger.toLowerCase() ==
                  _selectedLedgerGroup?.toLowerCase(),
            )
            .toList();
      } else {
        filteredItems_sale_purc_cash = List.from(sales_purc_cash_list);
      }
    });
  }

  @override
  void dispose() {
    _voucherController.dispose();
    _scrollFabController.dispose();
    super.dispose();
  }

  double getCashDebitTotal() {
    return filteredItems_sale_purc_cash.fold(0.0, (sum, item) {
      return item.amount < 0 ? sum - item.amount.abs() : sum;
    });
  }

  double getCashCreditTotal() {
    return filteredItems_sale_purc_cash.fold(0.0, (sum, item) {
      return item.amount > 0 ? sum + item.amount : sum;
    });
  }

  /*
  Widget buildDebitCreditSummary() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child:
    );
  }
*/

  double getTotalAmount() {
    if (vchtypes == "Receivable" || vchtypes == "Payable") {
      if (_isAgeingView && _selectedAgeingBucket != null) {
        return _selectedAgeingBucket!.amount;
      }
      double billsTotal = filteredItems_receivable_payable.fold(0.0, (
        sum,
        item,
      ) {
        print("Adding Outstanding: ${item.outstanding}");
        return sum + item.outstanding;
      });
      double opening = 0.0;
      setState(() {
        // print("Opening value $opening_value");

        opening = double.tryParse(opening_value ?? "0") ?? 0.0;
      });

      print("Opening (On Account): $opening");

      return billsTotal + opening;
    } else if (vchtypes == "Cash" && _isLedgerGroupVisible) {
      double voucherTotal = filteredLedgerGroupList.fold(0.0, (sum, item) {
        print(
          "Adding Amount+Opening (Ledger): ${(item.amount + item.opening)}",
        );
        return sum + (item.amount + item.opening);
      });
      /*double opening = 0.0;
      setState(() {
        // print("Opening value $opening_value");

        opening = double.tryParse(opening_value ?? "0") ?? 0.0;


      });*/

      //  print("Opening (Cash): $opening");

      return voucherTotal;
    } else if (vchtypes == "Cash" && !_isLedgerGroupVisible) {
      double voucherTotal = filteredItems_sale_purc_cash.fold(0.0, (sum, item) {
        print("Adding Amount (Ledger): ${item.amount}");
        return sum + item.amount;
      });
      double opening = 0.0;
      setState(() {
        // print("Opening value $opening_value");

        opening = double.tryParse(opening_value ?? "0") ?? 0.0;
      });

      print("Opening (Cash): $opening");

      return voucherTotal + opening;
      // return voucherTotal;
    } else {
      return filteredItems_sale_purc_cash.fold(0.0, (sum, item) {
        print("Adding Amount: ${item.amount}");
        return sum + item.amount;
      });
    }
  }

  String getFormattedTotal() {
    double total = getTotalAmount();
    return formatAmount(total.toString()); // you already have this
  }

  Future<void> fetchLedgerGroups() async {
    setState(() {
      filteredLedgerGroupList.clear();
      ledgerGroupList.clear();
      _isLoading = true;
      _isLedgerGroupVisible = false;
      _isSalesListVisible = false;
    });

    if (_selectedvoucher == "All Voucher Types") {
      _selectedvoucher = "";
    }

    try {
      final url = Uri.parse(HttpURL_sale_purc_cash!);
      Map<String, String> headers = {
        'Authorization': 'Bearer $token',
        "Content-Type": "application/json",
      };

      var body = jsonEncode({
        'ledgroup': "cash-in-hand,bank accounts",
        'startdate': startDateString,
        'enddate': endDateString,
        'vchtypes': '',
        'opening': 'true',
        'vchname': _selectedvoucher, // parent dropdown
        'isGroupByLedger': true, // key to trigger group mode
      });

      final response = await http.post(url, body: body, headers: headers);
      print('led group list -> ${response.body}');

      if (response.statusCode == 200) {
        final Map<String, dynamic> decoded = jsonDecode(response.body);

        // 🧮 Extract opening and list
        String opening = decoded['opening'].toString();
        final List<dynamic> values = decoded['values'] ?? [];

        setState(() {
          opening_value = opening; // reuse your existing method
          ledgerGroupList = values.map((e) => LedgerGroup.fromJson(e)).toList();
          filteredLedgerGroupList = ledgerGroupList;
          print('led group list -> ${ledgerGroupList[0]}');

          _isLedgerGroupVisible = true;
          _isSalesListVisible = false;
          _isOutstandingListVisible = false;
          isVisibleNoDataFound = false;
        });
      } else {
        setState(() {
          _isLedgerGroupVisible = false;
          _isSalesListVisible = false;
          _isOutstandingListVisible = false;
          isVisibleNoDataFound = true;
        });
        print("❌ Ledger group API failed: ${response.statusCode}");
      }
    } catch (e) {
      setState(() {
        _isLedgerGroupVisible = false;
        _isSalesListVisible = false;
        _isOutstandingListVisible = false;
        isVisibleNoDataFound = true;
      });
      print("⚠️ Error in fetchLedgerGroups: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showSelectionWindow(BuildContext context) {
    final sortGroups = [
      {
        'title': 'Default',
        'options': [
          {'label': 'Default', 'value': 'Default', 'icon': Icons.sort_rounded},
        ],
      },
      {
        'title': 'Date',
        'options': [
          {
            'label': 'Newest to Oldest',
            'value': 'Newest to Oldest',
            'icon': Icons.arrow_downward_rounded,
          },
          {
            'label': 'Oldest to Newest',
            'value': 'Oldest to Newest',
            'icon': Icons.arrow_upward_rounded,
          },
        ],
      },
      {
        'title': 'Name',
        'options': [
          {
            'label': 'A → Z',
            'value': 'A->Z',
            'icon': Icons.sort_by_alpha_rounded,
          },
          {
            'label': 'Z → A',
            'value': 'Z->A',
            'icon': Icons.sort_by_alpha_rounded,
          },
        ],
      },
      {
        'title': 'Amount',
        'options': [
          {
            'label': 'High to Low',
            'value': 'Amount High to Low',
            'icon': Icons.trending_down_rounded,
          },
          {
            'label': 'Low to High',
            'value': 'Amount Low to High',
            'icon': Icons.trending_up_rounded,
          },
        ],
      },
    ];

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurfaceVariant.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  'Sort By',
                  style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
              ...sortGroups.map((group) {
                final title = group['title'] as String;
                final options = group['options'] as List<Map<String, dynamic>>;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title != 'Default')
                      Padding(
                        padding: const EdgeInsets.only(
                          top: 8,
                          bottom: 6,
                          left: 4,
                        ),
                        child: Text(
                          title,
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ...options.map((opt) {
                      final isSelected = selectedSortOption == opt['value'];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Material(
                          color: isSelected
                              ? app_color.withOpacity(
                                  Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? 0.15
                                      : 0.08,
                                )
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () {
                              setState(() {
                                selectedSortOption = opt['value'] as String;
                              });
                              switch (selectedSortOption) {
                                case 'Default':
                                  sortByDefault();
                                  break;
                                case 'Newest to Oldest':
                                  sortByDateHightoLow();
                                  break;
                                case 'Oldest to Newest':
                                  sortByDateLowtoHigh();
                                  break;
                                case 'A->Z':
                                  sortByAlphabetAtoZ();
                                  break;
                                case 'Z->A':
                                  sortByAlphabetZtoA();
                                  break;
                                case 'Amount High to Low':
                                  sortByAmountHightoLow();
                                  break;
                                case 'Amount Low to High':
                                  sortByAmountLowtoHigh();
                                  break;
                              }
                              Navigator.pop(context);
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    opt['icon'] as IconData,
                                    size: 20,
                                    color: isSelected
                                        ? app_color
                                        : Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      opt['label'] as String,
                                      style: GoogleFonts.poppins(
                                        fontSize: 15,
                                        fontWeight: isSelected
                                            ? FontWeight.w600
                                            : FontWeight.w400,
                                        color: isSelected
                                            ? app_color
                                            : Theme.of(
                                                context,
                                              ).colorScheme.onSurface,
                                      ),
                                    ),
                                  ),
                                  if (isSelected)
                                    Icon(
                                      Icons.check_rounded,
                                      size: 20,
                                      color: app_color,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                );
              }),
            ],
          ),
        );
      },
    );
  }

  void sortByDefault() {
    setState(() {
      if (filteredItems_sale_purc_cash.isNotEmpty) {
        if (vchtypes == "Cash") {
          setState(() {
            filteredItems_sale_purc_cash = sales_purc_cash_list
                .where(
                  (e) =>
                      e.ledger.toLowerCase() ==
                      _selectedLedgerGroup!.toLowerCase(),
                )
                .toList();
          });
        } else {
          filteredItems_sale_purc_cash = List.from(sales_purc_cash_list);
          _scrollController_salelist.animateTo(
            0.0,
            duration: Duration(milliseconds: 500),
            curve: Curves.easeInOut,
          );
        }
      } else if (filteredItems_receivable_payable.isNotEmpty) {
        filteredItems_receivable_payable = List.from(receivable_payable_list);
        _scrollController_receivablellist.animateTo(
          0.0,
          duration: Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  void sortByAlphabetAtoZ() {
    setState(() {
      if (filteredItems_sale_purc_cash.isNotEmpty) {
        if (vchtypes == 'Sales' || vchtypes == 'Purchase') {
          filteredItems_sale_purc_cash.sort(
            (a, b) => a.vchname.compareTo(b.vchname),
          );
          _scrollController_salelist.animateTo(
            0.0,
            duration: Duration(milliseconds: 500),
            curve: Curves.easeInOut,
          );
        } else {
          filteredItems_sale_purc_cash.sort(
            (a, b) => a.ledger.compareTo(b.ledger),
          );
          _scrollController_salelist.animateTo(
            0.0,
            duration: Duration(milliseconds: 500),
            curve: Curves.easeInOut,
          );
        }
      } else if (filteredItems_receivable_payable.isNotEmpty) {
        filteredItems_receivable_payable.sort(
          (a, b) => a.ledger.compareTo(b.ledger),
        );
        _scrollController_receivablellist.animateTo(
          0.0,
          duration: Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  void sortByAlphabetZtoA() {
    setState(() {
      if (filteredItems_sale_purc_cash.isNotEmpty) {
        if (vchtypes == 'Sales' || vchtypes == 'Purchase') {
          filteredItems_sale_purc_cash.sort(
            (a, b) => b.vchname.compareTo(a.vchname),
          );
          _scrollController_salelist.animateTo(
            0.0,
            duration: Duration(milliseconds: 500),
            curve: Curves.easeInOut,
          );
        } else {
          filteredItems_sale_purc_cash.sort(
            (a, b) => b.ledger.compareTo(a.ledger),
          );
          _scrollController_salelist.animateTo(
            0.0,
            duration: Duration(milliseconds: 500),
            curve: Curves.easeInOut,
          );
        }
      } else if (filteredItems_receivable_payable.isNotEmpty) {
        filteredItems_receivable_payable.sort(
          (a, b) => b.ledger.compareTo(a.ledger),
        );
        _scrollController_receivablellist.animateTo(
          0.0,
          duration: Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  void sortByDateLowtoHigh() {
    setState(() {
      if (filteredItems_sale_purc_cash.isNotEmpty) {
        filteredItems_sale_purc_cash.sort(
          (a, b) => a.vchdate.compareTo(b.vchdate),
        );
        _scrollController_salelist.animateTo(
          0.0,
          duration: Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
      } else if (filteredItems_receivable_payable.isNotEmpty) {
        filteredItems_receivable_payable.sort(
          (a, b) =>
              DateTime.parse(a.billdate).compareTo(DateTime.parse(b.billdate)),
        );

        _scrollController_receivablellist.animateTo(
          0.0,
          duration: Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  void sortByDateHightoLow() {
    setState(() {
      if (filteredItems_sale_purc_cash.isNotEmpty) {
        filteredItems_sale_purc_cash.sort(
          (a, b) => b.vchdate.compareTo(a.vchdate),
        );
        _scrollController_salelist.animateTo(
          0.0,
          duration: Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
      } else if (filteredItems_receivable_payable.isNotEmpty) {
        filteredItems_receivable_payable.sort(
          (a, b) =>
              DateTime.parse(b.billdate).compareTo(DateTime.parse(a.billdate)),
        );

        _scrollController_receivablellist.animateTo(
          0.0,
          duration: Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  void sortByAmountLowtoHigh() {
    setState(() {
      if (filteredItems_sale_purc_cash.isNotEmpty) {
        if (vchtypes == 'Payment') {
          filteredItems_sale_purc_cash.sort(
            (a, b) => b.amount.compareTo(a.amount),
          );
          _scrollController_salelist.animateTo(
            0.0,
            duration: Duration(milliseconds: 500),
            curve: Curves.easeInOut,
          );
        } else {
          filteredItems_sale_purc_cash.sort(
            (a, b) => a.amount.compareTo(b.amount),
          );
          _scrollController_salelist.animateTo(
            0.0,
            duration: Duration(milliseconds: 500),
            curve: Curves.easeInOut,
          );
        }
      } else if (filteredItems_receivable_payable.isNotEmpty) {
        if (vchtypes == "Receivable") {
          filteredItems_receivable_payable.sort(
            (a, b) => b.outstanding.compareTo(a.outstanding),
          );
          _scrollController_receivablellist.animateTo(
            0.0,
            duration: Duration(milliseconds: 500),
            curve: Curves.easeInOut,
          );
        } else {
          filteredItems_receivable_payable.sort(
            (a, b) => a.outstanding.compareTo(b.outstanding),
          );
          _scrollController_receivablellist.animateTo(
            0.0,
            duration: Duration(milliseconds: 500),
            curve: Curves.easeInOut,
          );
        }
      }
    });
  }

  void sortByAmountHightoLow() {
    setState(() {
      if (filteredItems_sale_purc_cash.isNotEmpty) {
        if (vchtypes == "Payment") {
          filteredItems_sale_purc_cash.sort(
            (a, b) => a.amount.compareTo(b.amount),
          );
          _scrollController_salelist.animateTo(
            0.0,
            duration: Duration(milliseconds: 500),
            curve: Curves.easeInOut,
          );
        } else {
          filteredItems_sale_purc_cash.sort(
            (a, b) => b.amount.compareTo(a.amount),
          );
          _scrollController_salelist.animateTo(
            0.0,
            duration: Duration(milliseconds: 500),
            curve: Curves.easeInOut,
          );
        }
      } else if (filteredItems_receivable_payable.isNotEmpty) {
        if (vchtypes == "Receivable") {
          filteredItems_receivable_payable.sort(
            (a, b) => a.outstanding.compareTo(b.outstanding),
          );
          _scrollController_receivablellist.animateTo(
            0.0,
            duration: Duration(milliseconds: 500),
            curve: Curves.easeInOut,
          );
        } else {
          filteredItems_receivable_payable.sort(
            (a, b) => b.outstanding.compareTo(a.outstanding),
          );
          _scrollController_receivablellist.animateTo(
            0.0,
            duration: Duration(milliseconds: 500),
            curve: Curves.easeInOut,
          );
        }
      }
    });
  }

  void showToast(String message) {
    showAppMessage(context, message);
  }

  String allparties = 'All Parties', allvchtypes = 'All Voucher Types';

  late GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey;
  late SharedPreferences prefs;
  late String startdate_text = "", enddate_text = "";
  late DateTime _startDate;
  late DateTime _endDate;
  String? datetype;

  late String? startdate_pref, enddate_pref;

  String HttpURL = "";

  String? hostname = "",
      company = "",
      serial_no = "",
      company_lowercase = "",
      username = "";
  List<dynamic> myData = [];
  bool _isLoading = false;

  String? HttpURL_sale_purc_cash,
      HttpURL_receipt_payment,
      HttpURL_receivable_payable,
      HttpURL_sale_purc_cash_parent,
      HttpURL_receivable_payable_parent;

  dynamic _selectedvoucher = "";
  List<String> spinner_list = [];

  List<Sale_purc_cash> sales_purc_cash_list = [];
  List<Receivable_payable> receivable_payable_list = [];

  // csv of all
  Future<void> generateAndShareCSV_SalesList() async {
    final List<List<dynamic>> csvData = [];
    final headersRow = [
      'Vch No',
      'Vch Name',
      'Vch Date',
      'Party Name',
      'Amount',
    ];
    csvData.add(headersRow);

    for (final item in filteredItems_sale_purc_cash) {
      final rowData = [
        item.vchno,
        item.vchname,
        convertDateFormat(item.vchdate),
        item.ledger,
        formatAmount(item.amount.toString()),
      ];
      csvData.add(rowData);
    }

    final csvString = const ListToCsvConverter().convert(csvData);

    // Save CSV to a temporary file
    final tempDir = await Directory.systemTemp.createTemp();
    final tempFilePath = '${tempDir.path}/Vouchers.csv';
    final file = File(tempFilePath);
    await file.writeAsString(csvString);

    // ✅ Use ShareParams for new API
    await SharePlus.instance.share(
      ShareParams(
        text: 'Sharing $vchtypes Summary Report of $company',
        files: [XFile(tempFilePath)],
      ),
    );
  }

  Future<void> generateAndShareCSV_Outstanding() async {
    final List<List<dynamic>> csvData = [];
    final headersRow = [
      'Bill No',
      'Bill Type',
      'Due Date',
      'Party Name',
      'Amount',
    ];
    csvData.add(headersRow);

    for (final item in filteredItems_receivable_payable) {
      final rowData = [
        item.billno,
        item.billtype,
        formatDueDate(item.billdate, item.billtype, item.duedate),
        item.ledger,
        formatAmount(item.outstanding.toString()),
      ];
      csvData.add(rowData);
    }

    final csvString = const ListToCsvConverter().convert(csvData);

    // Save CSV to a temporary file
    final tempDir = await Directory.systemTemp.createTemp();
    final tempFilePath = '${tempDir.path}/Outstanding.csv';
    final file = File(tempFilePath);
    await file.writeAsString(csvString);

    // ✅ Share CSV file using the latest SharePlus API
    await SharePlus.instance.share(
      ShareParams(
        text: 'Sharing $vchtypes Summary Report of $company',
        files: [XFile(tempFilePath)],
      ),
    );
  }

  // pdf of all
  Future<void> generateAndSharePDF_SalesList() async {
    final font = pw.Font.ttf(
      await rootBundle.load("assets/fonts/NotoSans.ttf"),
    );

    final pdf = pw.Document();

    final companyName = company!;
    final reportname = '$vchtypes Summary';
    final parentname = _selectedvoucher;

    final headersRow3 = [
      'Vch No',
      'Vch Name',
      'Vch Date',
      'Party Name',
      'Amount',
    ];

    final itemsPerPage = 8; // Adjust this value as needed
    final pageCount = (filteredItems_sale_purc_cash.length / itemsPerPage)
        .ceil();

    for (int pageNumber = 0; pageNumber < pageCount; pageNumber++) {
      final startIndex = pageNumber * itemsPerPage;
      final endIndex = (pageNumber + 1) * itemsPerPage;
      final itemsSubset = filteredItems_sale_purc_cash.sublist(
        startIndex,
        endIndex > filteredItems_sale_purc_cash.length
            ? filteredItems_sale_purc_cash.length
            : endIndex,
      );

      final tableSubsetRows = itemsSubset.map((item) {
        return [
          item.vchno,
          item.vchname,
          convertDateFormat(item.vchdate),
          item.ledger,
          formatAmount(item.amount.toString()),
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
        columnWidths: {
          0: const pw.FractionColumnWidth(0.4),
          1: const pw.FractionColumnWidth(0.4),
          2: const pw.FractionColumnWidth(0.4),
          3: const pw.FractionColumnWidth(0.4),
          4: const pw.FractionColumnWidth(0.4),
        },
        headerStyle: pw.TextStyle(
          fontWeight: pw.FontWeight.bold,
          font: font,
        ), // ✅ Use your font
        cellStyle: pw.TextStyle(
          fontSize: 12,
          font: font,
        ), // ✅ Use your font here too
        rowDecoration: pw.BoxDecoration(
          border: pw.Border(
            top: pw.BorderSide(width: 1),
            bottom: pw.BorderSide(width: 1),
          ),
        ),
        headers: headersRow3,
        data: tableSubsetRows,
      );

      pdf.addPage(
        pw.Page(
          build: (pw.Context context) {
            return pw.Container(
              child: pw.Column(
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
                        'Vch Name:',
                        style: pw.TextStyle(
                          fontSize: 16,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(width: 5),
                      pw.Text(parentname, style: pw.TextStyle(fontSize: 16)),
                    ],
                  ),
                  pw.SizedBox(height: 20),
                  pw.Expanded(child: tableSubset),
                ],
              ),
            );
          },
        ),
      );
    }

    final pdfData = await pdf.save();

    // Save the PDF to a temporary file
    final tempDir = await getTemporaryDirectory();
    final tempFilePath = '${tempDir.path}/Vouchers.pdf';
    final file = File(tempFilePath);
    await file.writeAsBytes(pdfData);

    // ✅ Share using the latest SharePlus API
    await SharePlus.instance.share(
      ShareParams(
        text: 'Sharing $vchtypes Summary Report of $company',
        files: [XFile(tempFilePath)],
      ),
    );
  }

  Future<void> generateAndSharePDF_Outstanding() async {
    final font = pw.Font.ttf(
      await rootBundle.load("assets/fonts/NotoSans.ttf"),
    );

    final pdf = pw.Document();

    final companyName = company!;
    final reportname = '$vchtypes Summary';
    final parentname = _selectedvoucher;

    final headersRow3 = [
      'Bill No',
      'Bill Type',
      'Due Date',
      'Party Name',
      'Amount',
    ];
    final itemsPerPage = 8;
    final pageCount = (filteredItems_receivable_payable.length / itemsPerPage)
        .ceil();

    for (int pageNumber = 0; pageNumber < pageCount; pageNumber++) {
      final startIndex = pageNumber * itemsPerPage;
      final endIndex = (pageNumber + 1) * itemsPerPage;
      final itemsSubset = filteredItems_receivable_payable.sublist(
        startIndex,
        endIndex > filteredItems_receivable_payable.length
            ? filteredItems_receivable_payable.length
            : endIndex,
      );

      final tableSubsetRows = itemsSubset.map((item) {
        return [
          item.billno,
          item.billtype,
          formatDueDate(item.billdate, item.billtype, item.duedate),
          item.ledger,
          formatAmount(item.outstanding.toString()),
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
        columnWidths: {
          0: const pw.FractionColumnWidth(0.4),
          1: const pw.FractionColumnWidth(0.4),
          2: const pw.FractionColumnWidth(0.4),
          3: const pw.FractionColumnWidth(0.4),
          4: const pw.FractionColumnWidth(0.4),
        },
        headerStyle: pw.TextStyle(
          fontWeight: pw.FontWeight.bold,
          font: font,
        ), // ✅ Use your font
        cellStyle: pw.TextStyle(
          fontSize: 12,
          font: font,
        ), // ✅ Use your font here too
        rowDecoration: pw.BoxDecoration(
          border: pw.Border(
            top: pw.BorderSide(width: 1),
            bottom: pw.BorderSide(width: 1),
          ),
        ),
        headers: headersRow3,
        data: tableSubsetRows,
      );

      pdf.addPage(
        pw.Page(
          build: (pw.Context context) {
            return pw.Container(
              child: pw.Column(
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
                        style: const pw.TextStyle(fontSize: 16),
                      ),
                      pw.SizedBox(width: 5),
                      pw.Text('to', style: const pw.TextStyle(fontSize: 16)),
                      pw.SizedBox(width: 5),
                      pw.Text(
                        convertDateFormat(endDateString),
                        style: const pw.TextStyle(fontSize: 16),
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
                      pw.Text(
                        parentname,
                        style: const pw.TextStyle(fontSize: 16),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 20),
                  pw.Expanded(child: tableSubset),
                ],
              ),
            );
          },
        ),
      );
    }

    final pdfData = await pdf.save();

    // Save the PDF to a temporary file
    final tempDir = await getTemporaryDirectory();
    final tempFilePath = '${tempDir.path}/Outstanding.pdf';
    final file = File(tempFilePath);
    await file.writeAsBytes(pdfData);

    // ✅ Share using latest SharePlus API
    await SharePlus.instance.share(
      ShareParams(
        text: 'Sharing $vchtypes Summary Report of $company',
        files: [XFile(tempFilePath)],
      ),
    );
  }

  Future<void> generateAndShareCSV_Ageing() async {
    final List<List<dynamic>> csvData = [];

    if (_selectedAgeingBucket != null) {
      csvData.add(['Bill No', 'Bill Type', 'Due Date', 'Party Name', 'Amount']);
      for (final item in _selectedAgeingBucket!.items) {
        csvData.add([
          item.billno,
          item.billtype,
          formatDueDate(item.billdate, item.billtype, item.duedate),
          item.ledger,
          formatAmount(item.outstanding.toString()),
        ]);
      }
    } else {
      csvData.add(['Ageing Bucket', 'No. of Bills', 'Amount']);
      for (final bucket in _ageingBuckets) {
        csvData.add([
          bucket.label,
          bucket.count,
          formatAmount(bucket.amount.toString()),
        ]);
      }
    }

    final csvString = const ListToCsvConverter().convert(csvData);

    final tempDir = await Directory.systemTemp.createTemp();
    final fileName = _selectedAgeingBucket != null
        ? 'Ageing_${_selectedAgeingBucket!.label}.csv'
        : 'Ageing_Summary.csv';
    final tempFilePath = '${tempDir.path}/$fileName';
    final file = File(tempFilePath);
    await file.writeAsString(csvString);

    await SharePlus.instance.share(
      ShareParams(
        text:
            'Sharing $vchtypes Ageing Report${_selectedAgeingBucket != null ? ' (${_selectedAgeingBucket!.label})' : ''} of $company',
        files: [XFile(tempFilePath)],
      ),
    );
  }

  Future<void> generateAndSharePDF_Ageing() async {
    final font = pw.Font.ttf(
      await rootBundle.load("assets/fonts/NotoSans.ttf"),
    );

    final pdf = pw.Document();
    final companyName = company!;
    final bucket = _selectedAgeingBucket;

    final headers = bucket != null
        ? ['Bill No', 'Bill Type', 'Due Date', 'Party Name', 'Amount']
        : ['Ageing Bucket', 'No. of Bills', 'Amount'];

    final rows = bucket != null
        ? bucket.items
              .map(
                (item) => [
                  item.billno,
                  item.billtype,
                  formatDueDate(item.billdate, item.billtype, item.duedate),
                  item.ledger,
                  formatAmount(item.outstanding.toString()),
                ],
              )
              .toList()
        : _ageingBuckets
              .map(
                (b) => [
                  b.label,
                  b.count.toString(),
                  formatAmount(b.amount.toString()),
                ],
              )
              .toList();

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
      rowDecoration: pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(width: 1),
          bottom: pw.BorderSide(width: 1),
        ),
      ),
      headers: headers,
      data: rows,
    );

    pdf.addPage(
      pw.MultiPage(
        build: (pw.Context context) => [
          pw.Column(
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
                    ? '$vchtypes Ageing Report - ${bucket.label}'
                    : '$vchtypes Ageing Report Summary',
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 20),
              table,
            ],
          ),
        ],
      ),
    );

    final pdfData = await pdf.save();
    final tempDir = await getTemporaryDirectory();
    final fileName = bucket != null
        ? 'Ageing_${bucket.label}.pdf'
        : 'Ageing_Summary.pdf';
    final tempFilePath = '${tempDir.path}/$fileName';
    final file = File(tempFilePath);
    await file.writeAsBytes(pdfData);

    await SharePlus.instance.share(
      ShareParams(
        text:
            'Sharing $vchtypes Ageing Report${bucket != null ? ' (${bucket.label})' : ''} of $company',
        files: [XFile(tempFilePath)],
      ),
    );
  }

  void fetchParentData() {
    if (vchtypes == "Sales" ||
        vchtypes == "Purchase" ||
        vchtypes == "Receipt" ||
        vchtypes == "Payment" ||
        vchtypes == "Cash") {
      if (vchtypes == "Sales" || vchtypes == "Purchase" || vchtypes == "Cash") {
        _isopeningVisible = true;
        if (vchtypes == "Sales") {
          _isopeningVisible = false;
          fetchParent("");
        } else if (vchtypes == "Purchase") {
          _isopeningVisible = false;
          fetchParent("");
        } else if (vchtypes == "Cash") {
          _isopeningVisible = true;
          fetchParent("");
        }
      } else if (vchtypes == "Receipt" || vchtypes == "Payment") {
        _isopeningVisible = false;
        fetchParent(vchtypes);
      }
      setState(() {
        if (vchtypes == "Cash") {
          _isSalesListVisible = false;
        } else {
          _isSalesListVisible = true;
        }

        _isOutstandingListVisible = false;
      });
    } else if (vchtypes == "Receivable" || vchtypes == "Payable") {
      if (vchtypes == "Receivable") {
        fetchParent_Receivable_Payable("ledger", "true", "true", "true");
      } else if (vchtypes == "Payable") {
        fetchParent_Receivable_Payable("ledger", "", "true", "true");
      }
      setState(() {
        _isSalesListVisible = false;
        _isOutstandingListVisible = true;
      });
    }
  }

  void fetchListData() {
    if (_selectedvoucher == "All Voucher Types") {
      if (vchtypes == "Sales" || vchtypes == "Purchase" || vchtypes == "Cash") {
        if (vchtypes == "Sales") {
          fetchSales_purchase_cash(
            "Sales Accounts",
            startDateString,
            endDateString,
            "",
            "true",
            "",
            "",
          );
        } else if (vchtypes == "Purchase") {
          fetchSales_purchase_cash(
            "Purchase Accounts",
            startDateString,
            endDateString,
            "",
            "true",
            "",
            "",
          );
        } else if (vchtypes == "Cash") {
          // Then load ledger groups for this period
          WidgetsBinding.instance.addPostFrameCallback((_) {
            fetchLedgerGroups();
          });
        }
        /*else if (vchtypes =="Cash")
        {
          fetchSales_purchase_cash("cash-in-hand,bank accounts", startDateString, endDateString, "","true","");
        }*/
      } else if (vchtypes == "Receipt" || vchtypes == "Payment") {
        fetchReceipt_Payment(startDateString, endDateString, vchtypes, "");
      } else if (vchtypes == "Receivable" || vchtypes == "Payable") {
        if (vchtypes == "Receivable") {
          fetchReceivable_payable(
            "billno",
            startDateString,
            endDateString,
            "true",
            "",
          );
        } else if (vchtypes == "Payable") {
          fetchReceivable_payable(
            "billno",
            startDateString,
            endDateString,
            "",
            "",
          );
        }
      }
    } else {
      if (_selectedvoucher == "All Parties") {
        if (vchtypes == "Receivable") {
          fetchReceivable_payable(
            "billdate",
            startDateString,
            endDateString,
            "true",
            "",
          );
        } else if (vchtypes == "Payable") {
          fetchReceivable_payable(
            "billdate",
            startDateString,
            endDateString,
            "",
            "",
          );
        }
      } else {
        if (vchtypes == "Sales" ||
            vchtypes == "Purchase" ||
            vchtypes == "Cash") {
          if (vchtypes == "Sales") {
            fetchSales_purchase_cash(
              "Sales Accounts",
              startDateString,
              endDateString,
              "",
              "true",
              _selectedvoucher,
              "",
            );
          } else if (vchtypes == "Purchase") {
            fetchSales_purchase_cash(
              "Purchase Accounts",
              startDateString,
              endDateString,
              "",
              "true",
              _selectedvoucher,
              "",
            );
          } else if (vchtypes == "Cash") {
            // Then load ledger groups for this period
            WidgetsBinding.instance.addPostFrameCallback((_) {
              fetchLedgerGroups();
            });
          }
          /*else if (vchtypes =="Cash")
            {
              fetchSales_purchase_cash("cash-in-hand,bank accounts", startDateString, endDateString, "","true",_selectedvoucher);
            }*/
        } else if (vchtypes == "Receipt" || vchtypes == "Payment") {
          fetchReceipt_Payment(
            startDateString,
            endDateString,
            vchtypes,
            _selectedvoucher,
          );
        } else if (vchtypes == "Receivable" || vchtypes == "Payable") {
          if (vchtypes == "Receivable") {
            fetchReceivable_payable(
              "billdate",
              startDateString,
              endDateString,
              "true",
              _selectedvoucher,
            );
          } else if (vchtypes == "Payable") {
            fetchReceivable_payable(
              "billdate",
              startDateString,
              endDateString,
              "",
              _selectedvoucher,
            );
          }
        }
      }
    }
  }

  Future<void> fetchParent(final String type) async {
    setState(() {
      _isLoading = true;
    });

    spinner_list.clear();

    try {
      final url = Uri.parse(HttpURL_sale_purc_cash_parent!);

      Map<String, String> headers = {
        'Authorization': 'Bearer $token',
        "Content-Type": "application/json",
      };

      var body = jsonEncode({'vchtypes': type, 'orderby': 'vchname'});

      final response = await http.post(url, body: body, headers: headers);

      if (response.statusCode == 200) {
        if (vchtypes == "Receivable" || vchtypes == "Payable") {
          spinner_list.add(allparties);
          _selectedvoucher = allparties;
        } else {
          spinner_list.add(allvchtypes);
          _selectedvoucher = allvchtypes;
        }
        List<dynamic> data = jsonDecode(response.body);
        for (var item in data) {
          String vchname = item['vchname'];
          spinner_list.add(vchname);
        }
        setState(() {
          _selectedvoucher = spinner_list[0];
          _voucherController.text = _selectedvoucher;
          fetchListData();
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      print(e);
    }
  }

  Future<void> fetchParent_Receivable_Payable(
    final String orderby,
    final String isdebit,
    final String select,
    final String parent,
  ) async {
    setState(() {
      _isLoading = true;
    });

    spinner_list.clear();

    try {
      final url = Uri.parse(HttpURL_receivable_payable_parent!);
      Map<String, String> headers = {
        'Authorization': 'Bearer $token',
        "Content-Type": "application/json",
      };

      var body = jsonEncode({
        'orderby': orderby,
        'isDebit': isdebit,
        'select': select,
        'parent': parent,
      });

      final response = await http.post(url, body: body, headers: headers);

      if (response.statusCode == 200) {
        if (vchtypes == "Receivable" || vchtypes == "Payable") {
          spinner_list.add(allparties);
          _selectedvoucher = allparties;
        } else {
          spinner_list.add(allvchtypes);
          _selectedvoucher = allvchtypes;
        }

        List<dynamic> data = jsonDecode(response.body);
        for (var item in data) {
          String ledger = item['ledger'];
          spinner_list.add(ledger);
        }
        setState(() {
          _selectedvoucher = spinner_list[0];
          _voucherController.text = _selectedvoucher;
          fetchListData();
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      print(e);
    }
  }

  // new function fetchSales_purchase_cash
  Future<void> fetchSales_purchase_cash(
    final String ledgroup,
    final String startdate,
    final String enddate,
    final String vchtypes,
    final String opening,
    final String vchname,
    final String ledger,
  ) async {
    // ✅ keep same behavior: start loading + reset sort visibility
    setState(() {
      _isLoading = true;
      isSortVisible = false;
    });

    // ✅ clear lists same as your existing code
    sales_purc_cash_list.clear();
    filteredItems_sale_purc_cash.clear();

    receivable_payable_list.clear();
    filteredItems_receivable_payable.clear();

    try {
      final url = Uri.parse(HttpURL_sale_purc_cash!);
      final headers = <String, String>{
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

      final body = jsonEncode({
        'ledgroup': ledgroup,
        'startdate': startdate,
        'enddate': enddate,
        'vchtypes': vchtypes,
        'opening': opening,
        'vchname': vchname,
        'ledger': ledger,
      });

      final response = await http.post(url, body: body, headers: headers);

      if (response.statusCode == 200) {
        // ✅ heavy parsing moved off UI thread
        final parsed = await compute(_parseSalesTotalResponse, response.body);

        if (!mounted) return;

        // ✅ single setState with final results
        setState(() {
          opening_value = parsed.opening;

          sales_purc_cash_list
            ..clear()
            ..addAll(parsed.items);

          filteredItems_sale_purc_cash = List.from(sales_purc_cash_list);

          print('list ->>> ${response.body}');

          isVisibleNoDataFound = filteredItems_sale_purc_cash.isEmpty;
          isSortVisible = filteredItems_sale_purc_cash.isNotEmpty;

          _isLoading = false;
        });

        // ✅ keep exact sorting behavior (same options)
        if (filteredItems_sale_purc_cash.isNotEmpty) {
          switch (selectedSortOption) {
            case 'Default':
              sortByDefault();
              break;
            case 'Newest to Oldest':
              sortByDateHightoLow();
              break;
            case 'Oldest to Newest':
              sortByDateLowtoHigh();
              break;
            case 'A->Z':
              sortByAlphabetAtoZ();
              break;
            case 'Z->A':
              sortByAlphabetZtoA();
              break;
            case 'Amount High to Low':
              sortByAmountHightoLow();
              break;
            case 'Amount Low to High':
              sortByAmountLowtoHigh();
              break;
          }
        }

        return;
      }

      // non-200 => show no data (same end-result behavior)
      if (!mounted) return;
      setState(() {
        isVisibleNoDataFound = true;
        isSortVisible = false;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        isVisibleNoDataFound = true;
        isSortVisible = false;
        _isLoading = false;
      });
      print(e);
    }
  }

  // old function fetchSales_purchase_cash
  /*
  Future<void> fetchSales_purchase_cash(final String ledgroup, final String startdate, final String enddate, final String vchtypes,final String opening,final String vchname) async {
    setState(()
    {
      _isLoading = true;
      isSortVisible = false;
    });

    sales_purc_cash_list.clear();
    filteredItems_sale_purc_cash.clear();

    receivable_payable_list.clear();
    filteredItems_receivable_payable.clear();

    try
    {
      final url = Uri.parse(HttpURL_sale_purc_cash!);

      Map<String,String> headers = {
        'Authorization' : 'Bearer $token',
        "Content-Type": "application/json"
      };

      var body = jsonEncode( {
        'ledgroup': ledgroup,
        'startdate': startdate,
        'enddate': enddate,
        'vchtypes': vchtypes,
        'opening': opening,
        'vchname' : vchname
      });

      final response = await http.post(
          url,
          body: body,
          headers:headers
      );

      if (response.statusCode == 200)
      {
        print('$vchtypes -> ${response.body}');
        Map<String, dynamic> data = jsonDecode(response.body);
        String opening = data['opening'].toString();
        setState(()
        {
          opening_value = formatOpening(opening);
        });

        String values = jsonEncode(data['values']);

        final List<dynamic> values_list = jsonDecode(values);
        if (values_list != null) {
          isVisibleNoDataFound = false;

          sales_purc_cash_list.addAll(values_list.map((json) => Sale_purc_cash.fromJson(json)).toList());
          filteredItems_sale_purc_cash = sales_purc_cash_list;

        } else
        {
          throw Exception('Failed to fetch data');
        }
        setState(() {
          _isLoading = false;
        });
      }
    }
    catch (e)
    {
      setState(() {
        _isLoading = false;
      });
      print(e);
    }

    setState(() {
      if(sales_purc_cash_list.isEmpty)
      {
        isVisibleNoDataFound = true;
        isSortVisible = false;
      }
      else
        {
          isSortVisible = true;
          switch (selectedSortOption) {
            case 'Default':
              sortByDefault(); // Call the sorting function
              break;
            case 'Newest to Oldest':
              sortByDateHightoLow(); // Call the sorting function
              break;
            case 'Oldest to Newest':
              sortByDateLowtoHigh(); // Call the sorting function
              break;
            case 'A->Z':
              sortByAlphabetAtoZ(); // Call the sorting function
              break;
            case 'Z->A':
              sortByAlphabetZtoA(); // Call the sorting function
              break;
            case 'Amount High to Low':
              sortByAmountHightoLow(); // Call the sorting function
              break;
            case 'Amount Low to High':
              sortByAmountLowtoHigh(); // Call the sorting function
              break;
          }
        }
      _isLoading = false;
    });
  }
*/

  // new function fetchReceivable_payable

  Future<void> fetchReceivable_payable(
    final String orderby,
    final String startdate,
    final String enddate,
    final String isdebit,
    final String ledger,
  ) async {
    setState(() {
      _isLoading = true;
      isSortVisible = false;
    });

    receivable_payable_list.clear();
    filteredItems_receivable_payable.clear();

    sales_purc_cash_list.clear();
    filteredItems_sale_purc_cash.clear();

    try {
      final url = Uri.parse(HttpURL_receivable_payable!);
      final headers = <String, String>{
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

      final body = jsonEncode({
        'orderby': orderby,
        'startdate': startdate,
        'enddate': enddate,
        'isDebit': isdebit,
        'ledger': ledger,
      });

      final response = await http.post(url, body: body, headers: headers);

      if (response.statusCode == 200) {
        final parsed = await compute(
          _parseReceivableTotalResponse,
          response.body,
        );

        if (!mounted) return;

        setState(() {
          opening_value = parsed.opening;

          receivable_payable_list
            ..clear()
            ..addAll(parsed.items);

          filteredItems_receivable_payable = List.from(receivable_payable_list);
          print('list ->>> ${response.body}');

          isVisibleNoDataFound = filteredItems_receivable_payable.isEmpty;
          isSortVisible = filteredItems_receivable_payable.isNotEmpty;

          _isLoading = false;
        });

        // ✅ keep same sorting behavior
        if (filteredItems_receivable_payable.isNotEmpty) {
          switch (selectedSortOption) {
            case 'Default':
              sortByDefault();
              break;
            case 'Newest to Oldest':
              sortByDateHightoLow();
              break;
            case 'Oldest to Newest':
              sortByDateLowtoHigh();
              break;
            case 'A->Z':
              sortByAlphabetAtoZ();
              break;
            case 'Z->A':
              sortByAlphabetZtoA();
              break;
            case 'Amount High to Low':
              sortByAmountHightoLow();
              break;
            case 'Amount Low to High':
              sortByAmountLowtoHigh();
              break;
          }
        }
        if (_isAgeingView) {
          _computeAgeingBuckets();
        }
        return;
      }

      if (!mounted) return;
      setState(() {
        isVisibleNoDataFound = true;
        isSortVisible = false;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        isVisibleNoDataFound = true;
        isSortVisible = false;
        _isLoading = false;
      });
      print(e);
    }
  }

  // old function fetchReceivable_payable
  /*
    Future<void> fetchReceivable_payable(final String orderby, final String startdate, final String enddate, final String isdebit,final String ledger) async {
      setState(() {
        _isLoading = true;
        isSortVisible = false;
      });

      receivable_payable_list.clear();
      filteredItems_receivable_payable.clear();

      sales_purc_cash_list.clear();
      filteredItems_sale_purc_cash.clear();

      try
      {
        final url = Uri.parse(HttpURL_receivable_payable!);
        Map<String,String> headers = {
          'Authorization' : 'Bearer $token',
          "Content-Type": "application/json"
        };

        var body = jsonEncode({
          'orderby': orderby,
          'startdate': startdate,
          'enddate': enddate,
          'isDebit': isdebit,
          'ledger': ledger,
        });

        final response = await http.post(
            url,
            body: body,
            headers:headers
        );

        if (response.statusCode == 200)
        {
          print(response.body);

          Map<String, dynamic> data = jsonDecode(response.body);
          String opening = data['opening'].toString();
          setState(() {
            opening_value = formatOpening(opening);
          });
          String values = jsonEncode(data['values']);

          final List<dynamic> values_list = jsonDecode(values);
          if (values_list != null) {
            isVisibleNoDataFound = false;

            receivable_payable_list.addAll(values_list.map((json) => Receivable_payable.fromJson(json)).toList());

            filteredItems_receivable_payable = receivable_payable_list;
          } else {

            throw Exception('Failed to fetch data');
          }
          setState(() {
            _isLoading = false;
          });

        }
      }
      catch (e)
      {
        setState(() {
          _isLoading = false;
        });
        print(e);
      }

      setState(() {
        if(receivable_payable_list.isEmpty)
        {
          isVisibleNoDataFound = true;
          isSortVisible = false;
        }
        else
        {
          isSortVisible = true;
          switch (selectedSortOption) {
            case 'Default':
              sortByDefault(); // Call the sorting function
              break;
            case 'Newest to Oldest':
              sortByDateHightoLow(); // Call the sorting function
              break;
            case 'Oldest to Newest':
              sortByDateLowtoHigh(); // Call the sorting function
              break;
            case 'A->Z':
              sortByAlphabetAtoZ(); // Call the sorting function
              break;
            case 'Z->A':
              sortByAlphabetZtoA(); // Call the sorting function
              break;
            case 'Amount High to Low':
              sortByAmountHightoLow(); // Call the sorting function
              break;
            case 'Amount Low to High':
              sortByAmountLowtoHigh(); // Call the sorting function
              break;
          }
        }
        _isLoading = false;
      });

    }
  */

  // new function fetchReceipt_Payment

  Future<void> fetchReceipt_Payment(
    final String startdate,
    final String enddate,
    final String vchtypes,
    final String vchname,
  ) async {
    setState(() {
      _isLoading = true;
      isSortVisible = false;
    });

    sales_purc_cash_list.clear();
    filteredItems_sale_purc_cash.clear();

    receivable_payable_list.clear();
    filteredItems_receivable_payable.clear();

    try {
      final url = Uri.parse(HttpURL_receipt_payment!);
      final headers = <String, String>{
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

      final body = jsonEncode({
        'startdate': startdate,
        'enddate': enddate,
        'vchtypes': vchtypes,
        'vchname': vchname,
      });

      print('url ->> $url');
      print('token ->> $token');
      print('body ->> $body');

      final response = await http.post(url, body: body, headers: headers);

      if (response.statusCode == 200) {
        // ✅ heavy parsing moved off UI thread
        final items = await compute(
          _parseReceiptPaymentResponse,
          response.body,
        );

        if (!mounted) return;

        setState(() {
          sales_purc_cash_list
            ..clear()
            ..addAll(items);

          filteredItems_sale_purc_cash = List.from(sales_purc_cash_list);
          print('list length ->>> ${filteredItems_sale_purc_cash.length}');

          isVisibleNoDataFound = filteredItems_sale_purc_cash.isEmpty;
          isSortVisible = filteredItems_sale_purc_cash.isNotEmpty;

          _isLoading = false;
        });

        // ✅ same sorting behavior
        if (filteredItems_sale_purc_cash.isNotEmpty) {
          switch (selectedSortOption) {
            case 'Default':
              sortByDefault();
              break;
            case 'Newest to Oldest':
              sortByDateHightoLow();
              break;
            case 'Oldest to Newest':
              sortByDateLowtoHigh();
              break;
            case 'A->Z':
              sortByAlphabetAtoZ();
              break;
            case 'Z->A':
              sortByAlphabetZtoA();
              break;
            case 'Amount High to Low':
              sortByAmountHightoLow();
              break;
            case 'Amount Low to High':
              sortByAmountLowtoHigh();
              break;
          }
        }

        return;
      }

      if (!mounted) return;
      setState(() {
        isVisibleNoDataFound = true;
        isSortVisible = false;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        isVisibleNoDataFound = true;
        isSortVisible = false;
        _isLoading = false;
      });
      print(e);
    }
  }

  // old function fetchReceipt_Payment
  /*
  Future<void> fetchReceipt_Payment(final String startdate, final String enddate, final String vchtypes,final String vchname) async {
    setState(() {
      _isLoading = true;
      isSortVisible = false;


    });

    sales_purc_cash_list.clear();
    filteredItems_sale_purc_cash.clear();
    receivable_payable_list.clear();
    filteredItems_receivable_payable.clear();

    try
    {

      final url = Uri.parse(HttpURL_receipt_payment!);

      Map<String,String> headers = {
        'Authorization' : 'Bearer $token',
        "Content-Type": "application/json"
      };

      var body = jsonEncode( {
        'startdate': startdate,
        'enddate': enddate,
        'vchtypes': vchtypes,
        'vchname' : vchname
      });

      final response = await http.post(
          url,
          body: body,
          headers:headers
      );

      if (response.statusCode == 200)
      {

        final List<dynamic> values_list = jsonDecode(response.body);
        if (values_list != null) {
          isVisibleNoDataFound = false;

          sales_purc_cash_list.addAll(values_list.map((json) => Sale_purc_cash.fromJson(json)).toList());
          filteredItems_sale_purc_cash = sales_purc_cash_list;

        } else {

          throw Exception('Failed to fetch data');
        }
        setState(() {
          _isLoading = false;
        });

      }
    }
    catch (e)
    {
      setState(() {
        _isLoading = false;
      });
      print(e);
    }

    setState(() {
      if(sales_purc_cash_list.isEmpty)
      {
        isVisibleNoDataFound = true;
        isSortVisible = false;
      }
      else
      {
        isSortVisible = true;
        switch (selectedSortOption) {
          case 'Default':
            sortByDefault(); // Call the sorting function
            break;
          case 'Newest to Oldest':
            sortByDateHightoLow(); // Call the sorting function
            break;
          case 'Oldest to Newest':
            sortByDateLowtoHigh(); // Call the sorting function
            break;
          case 'A->Z':
            sortByAlphabetAtoZ(); // Call the sorting function
            break;
          case 'Z->A':
            sortByAlphabetZtoA(); // Call the sorting function
            break;
          case 'Amount High to Low':
            sortByAmountHightoLow(); // Call the sorting function
            break;
          case 'Amount Low to High':
            sortByAmountLowtoHigh(); // Call the sorting function
            break;
        }
      }
      _isLoading = false;
    });

  }
*/

  String formatOpening(String opening) {
    String opening_string = "";

    if (opening.contains("-")) {
      opening = opening.replaceAll("-", "");
      double opening_double = double.parse(opening);
      // int opening_int = opening_double.round();
      opening_string = CurrencyFormatter.formatCurrency_double(opening_double);
      opening_string = opening_string + " DR";
    } else {
      double opening_double = double.parse(opening);
      // int opening_int = opening_double.round();
      opening_string = CurrencyFormatter.formatCurrency_double(opening_double);
      opening_string = opening_string + " CR";
    }
    return opening_string;
  }

  String convertDateFormat(String dateStr) {
    // Parse the input date string
    DateTime date = DateTime.parse(dateStr);

    // Format the date to the desired output format
    String formattedDate = DateFormat("dd-MMM-yyyy").format(date);

    return formattedDate;
  }

  String formatDueDate(String billdate, String type, String duedate) {
    String formattedDate = '';

    if (type == 'On Account') {
      _isVisibleduedate = false;
    } else if (type == 'Advance') {
      _isVisibleduedate = false;
    } else if (type == 'Agst Ref' || type == 'New Ref') {
      _isVisibleduedate = true;

      if (duedate == 'null') {
        formattedDate = 'N/A';
      } else {
        try {
          if (duedate.contains("Days")) {
            String pattern = r'(\d+)';
            RegExp regex = RegExp(pattern);
            Match? match = regex.firstMatch(duedate);

            if (match != null) {
              String numberString = match.group(0)!;
              int nodays = int.parse(numberString);

              DateTime billdate_date = DateTime.parse(billdate);
              DateTime futureDate = billdate_date.add(Duration(days: nodays));

              formattedDate = DateFormat('dd-MMM-yy').format(futureDate);
            }
          } else {
            // Parse the input date string
            DateTime date = DateTime.parse(duedate);
            // Format the date to the desired output format
            formattedDate = DateFormat("dd-MMM-yy").format(date);
          }
        } catch (e) {
          formattedDate = duedate;
          print(e);
        }
      }
    }
    return formattedDate;
  }

  DateTime formatDueDate_Sort(String billdate, String type, String duedate) {
    DateTime formattedDate = DateTime.now();

    if (type == 'On Account') {
      _isVisibleduedate = false;
    } else if (type == 'Advance') {
      _isVisibleduedate = false;
    } else if (type == 'Agst Ref' || type == 'New Ref') {
      _isVisibleduedate = true;

      if (duedate == 'null') {
        formattedDate = DateTime.now();
      } else {
        try {
          if (duedate.contains("Days")) {
            String pattern = r'(\d+)';
            RegExp regex = RegExp(pattern);
            Match? match = regex.firstMatch(duedate);

            if (match != null) {
              String numberString = match.group(0)!;
              int nodays = int.parse(numberString);

              DateTime billdate_date = DateTime.parse(billdate);
              formattedDate = billdate_date.add(Duration(days: nodays));
            }
          } else {
            // Parse the input date string
            formattedDate = DateTime.parse(duedate);
            // Format the date to the desired output format
          }
        } catch (e) {
          formattedDate = DateTime.parse(duedate);
          print(e);
        }
      }
    }

    return formattedDate;
  }

  DateTime? _parseDueDateSafe(String billdate, String duedate) {
    if (duedate == 'null' || duedate.isEmpty) return null;
    try {
      if (duedate.contains('Days')) {
        final match = RegExp(r'(\d+)').firstMatch(duedate);
        if (match == null) return null;
        final nodays = int.parse(match.group(0)!);
        final bill = DateTime.tryParse(billdate);
        if (bill == null) return null;
        return bill.add(Duration(days: nodays));
      }
      try {
        return DateFormat('dd-MMM-yy').parse(duedate);
      } catch (_) {
        return DateTime.tryParse(duedate);
      }
    } catch (_) {
      return null;
    }
  }

  Future<void> _computeAgeingBuckets() async {
    if (mounted) {
      setState(() {
        _isAgeingComputing = true;
      });
    }
    final ageingPrefs = await SharedPreferences.getInstance();
    final h1 = int.tryParse(ageingPrefs.getString('heading1') ?? '30') ?? 30;
    final h2 = int.tryParse(ageingPrefs.getString('heading2') ?? '60') ?? 60;
    final h3 = int.tryParse(ageingPrefs.getString('heading3') ?? '90') ?? 90;
    final h4 = int.tryParse(ageingPrefs.getString('heading4') ?? '120') ?? 120;
    final h5 = int.tryParse(ageingPrefs.getString('heading5') ?? '180') ?? 180;

    final notDue = AgeingBucket('Not Due');
    final b1 = AgeingBucket('1-$h1 Days');
    final b2 = AgeingBucket('$h1-$h2 Days');
    final b3 = AgeingBucket('$h2-$h3 Days');
    final b4 = AgeingBucket('$h3-$h4 Days');
    final b5 = AgeingBucket('$h4-$h5 Days');
    final b6 = AgeingBucket('$h5+ Days');
    final others = AgeingBucket('Others');

    final today = DateTime.now();

    for (final card in filteredItems_receivable_payable) {
      if (card.billtype != 'Agst Ref' && card.billtype != 'New Ref') {
        others.count++;
        others.amount += card.outstanding;
        others.items.add(card);
        continue;
      }

      final dueDate = _parseDueDateSafe(card.billdate, card.duedate);
      if (dueDate == null) {
        others.count++;
        others.amount += card.outstanding;
        others.items.add(card);
        continue;
      }
      final daysOverdue = DateTime(
        today.year,
        today.month,
        today.day,
      ).difference(DateTime(dueDate.year, dueDate.month, dueDate.day)).inDays;

      AgeingBucket bucket;
      if (daysOverdue <= 0) {
        bucket = notDue;
      } else if (daysOverdue <= h1) {
        bucket = b1;
      } else if (daysOverdue <= h2) {
        bucket = b2;
      } else if (daysOverdue <= h3) {
        bucket = b3;
      } else if (daysOverdue <= h4) {
        bucket = b4;
      } else if (daysOverdue <= h5) {
        bucket = b5;
      } else {
        bucket = b6;
      }

      bucket.count++;
      bucket.amount += card.outstanding;
      bucket.items.add(card);
    }

    final buckets = [notDue, b1, b2, b3, b4, b5, b6, others]
        .where((b) => b.count > 0)
        .toList();

    if (mounted) {
      setState(() {
        _ageingBuckets = buckets;
        _selectedAgeingBucket = null;
        _isAgeingComputing = false;
      });
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
      token = prefs.getString('token')!;
    });

    try {
      selectedSortOption = prefs.getString('sort')!;
      if (selectedSortOption == null || selectedSortOption == 'null') {
        selectedSortOption = 'Default';
      }
    } catch (e) {
      selectedSortOption = 'Default';
    }

    HttpURL_sale_purc_cash_parent =
        '$hostname/api/voucher/getvoucherNames/$company_lowercase/$serial_no';
    HttpURL_receivable_payable_parent =
        '$hostname/api/ledger/getOutstandingList/$company_lowercase/$serial_no';

    HttpURL_sale_purc_cash =
        '$hostname/api/ledger/getTotal/$company_lowercase/$serial_no';
    HttpURL_receipt_payment =
        '$hostname/api/voucher/getVouchers/$company_lowercase/$serial_no';
    HttpURL_receivable_payable =
        '$hostname/api/ledger/getOutstandingOpening/$company_lowercase/$serial_no';
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

    startdate_pref = startDateString;
    enddate_pref = endDateString;

    _startDate = DateTime.parse(startdate_pref!);
    _endDate = DateTime.parse(enddate_pref!);

    DateTime start = _startDate;
    DateTime end = _endDate;

    String startMonth = DateFormat('MMM').format(start);
    String startDay = DateFormat('dd').format(start);
    int startYear = start.year;

    String endMonth = DateFormat('MMM').format(end);
    String endDay = DateFormat('dd').format(end);
    int endYear = end.year;

    startdate_text = startDay + "-" + startMonth + "-" + startYear.toString();
    enddate_text = endDay + "-" + endMonth + "-" + endYear.toString();

    fetchParentData();

    if (vchtypes == "Receivable" || vchtypes == "Payable") {
      setState(() {
        openingheading = 'OnAccount';
      });
    } else {
      setState(() {
        openingheading = 'Opening Balance';
      });
    }
  }

  Future<void> _selectDateRange(BuildContext context) async {
    final initialDateRange = DateTimeRange(start: _startDate, end: _endDate);
    String? startfrom = prefs.getString('startfrom');
    DateTime earliestDate = DateTime.parse(startfrom!);

    DateTimeRange? selectedDateRange = await showDateRangePicker(
      context: context,
      initialDateRange: initialDateRange,
      firstDate: earliestDate,
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

    if (selectedDateRange != null) {
      setState(() {
        _startDate = selectedDateRange.start;
        _endDate = selectedDateRange.end;

        DateTime start = _startDate;
        DateTime end = _endDate;

        String startMonth = DateFormat('MMM').format(start);
        String sdf = DateFormat(
          'MM',
        ).format(start); // converting month into string
        String startDay = DateFormat('dd').format(start);
        int startYear = start.year;

        String endMonth = DateFormat('MMM').format(end);
        String sdfEnd = DateFormat('MM').format(end);
        String endDay = DateFormat('dd').format(end);
        int endYear = end.year;

        startDateString = '$startYear$sdf$startDay';
        endDateString = '$endYear$sdfEnd$endDay';

        startdate_text =
            startDay + "-" + startMonth + "-" + startYear.toString();
        enddate_text = endDay + "-" + endMonth + "-" + endYear.toString();

        fetchListData();

        /*fetchDashData(startDateString,endDateString);*/
      });
    }
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

  Widget _buildTotalBar() {
    if (_isLoading) return const SizedBox();

    double total = getTotalAmount();
    if (total.abs() < 0.0001) total = 0.0;

    return Container(
      height:
          (vchtypes == "Cash" && !_isLedgerGroupVisible && _isSalesListVisible)
          ? 90
          : 60, // 🔥 dynamic height
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      margin: const EdgeInsets.only(bottom: 8, left: 12, right: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Theme.of(context).cardColor,
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8)],
      ),

      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 🔥 Credit
          if (vchtypes == "Cash" &&
              !_isLedgerGroupVisible &&
              _isSalesListVisible)
            _buildCompactLine("Credit", getCashCreditTotal(), Colors.green),
          // 🔥 Debit
          if (vchtypes == "Cash" &&
              !_isLedgerGroupVisible &&
              _isSalesListVisible)
            _buildCompactLine("Debit", getCashDebitTotal(), Colors.red),

          // 🔥 Total (always)
          Row(
            children: [
              Text(
                "Total",
                style: GoogleFonts.poppins(
                  color: app_color,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                formatAmount(total.toString()),
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: app_color,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCompactLine(String title, double amount, Color color) {
    final bool isDebit = title.toLowerCase().contains("debit");

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          Row(
            children: [
              Icon(
                isDebit ? Icons.south_west_rounded : Icons.north_east_rounded,
                size: 14,
                color: color,
              ),
              const SizedBox(width: 4),
              Text(
                formatAmount(amount.toString()),
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildTotalBar(),
          const AppBottomNav(
            activeTab: AppBottomNavTab.dashboard,
            activeMoreItem: AppMoreItem.dashboard,
          ),
        ],
      ),
      key: _scaffoldKey,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(50),
        child: AppBar(
          backgroundColor: app_color,
          elevation: 6,
          automaticallyImplyLeading: false,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
          ),
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () {
              AppNavigation.backOrDashboard(context);
            },
          ),
          title: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth:
                  MediaQuery.of(context).size.width -
                  (kToolbarHeight *
                      ((vchtypes == "Receivable" || vchtypes == "Payable")
                          ? 3.6
                          : 2.4)),
            ),
            child: GestureDetector(
              onTap: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => SerialSelect()),
                );
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      company ?? '',
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      softWrap: false,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_drop_down, color: Colors.white),
                ],
              ),
            ),
          ),

          centerTitle: true,
          actions: [
            /*IconButton(
              onPressed: () {
                counter++;
                setState(() {
                  _isSearchViewVisible = counter % 2 != 0;
                  if(!_isSearchViewVisible)
                  {
                    searchController.clear();
                    if (vchtypes == "Receivable" || vchtypes == "Payable") {
                      filteredItems_receivable_payable = receivable_payable_list;
                    } else {
                      filteredItems_sale_purc_cash = sales_purc_cash_list;
                    }
                  }
                });
              },
              icon: Icon(Icons.search, color: Colors.white, size: 26),
            ),*/
            if (vchtypes == "Receivable" || vchtypes == "Payable")
              IconButton(
                tooltip: _isAgeingView ? 'Show list' : 'Ageing report',
                onPressed: _isAgeingComputing
                    ? null
                    : () {
                        final togglingOn = !_isAgeingView;
                        setState(() {
                          _isAgeingView = togglingOn;
                          _selectedAgeingBucket = null;
                        });
                        if (togglingOn) {
                          _computeAgeingBuckets();
                        }
                      },
                icon: _isAgeingComputing
                    ? SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                    : Icon(
                        _isAgeingView
                            ? Icons.list_alt_rounded
                            : Icons.timelapse_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
              ),
            IconButton(
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
                  color: Theme.of(context).colorScheme.surface,
                  position: RelativeRect.fromLTRB(
                    overlay.size.width - buttonPosition.dx,
                    buttonPosition.dy - button.size.height,
                    overlay.size.width - buttonPosition.dx,
                    buttonPosition.dy,
                  ),
                  items: [
                    PopupMenuItem<String>(
                      child: GestureDetector(
                        onTap: () {
                          Navigator.pop(context);
                          if (_isOutstandingListVisible && _isAgeingView) {
                            if (_ageingBuckets.isNotEmpty) {
                              generateAndSharePDF_Ageing();
                            } else {
                              showToast('Data Not Found');
                            }
                          } else if (_isSalesListVisible &&
                              filteredItems_sale_purc_cash.isNotEmpty) {
                            generateAndSharePDF_SalesList();
                          } else if (_isOutstandingListVisible &&
                              filteredItems_receivable_payable.isNotEmpty) {
                            generateAndSharePDF_Outstanding();
                          } else {
                            showToast('Data Not Found');
                          }
                        },
                        child: Row(
                          children: [
                            Icon(
                              Icons.picture_as_pdf,
                              size: 16,
                              color: app_color,
                            ),
                            SizedBox(width: 6),
                            Text(
                              'Share as PDF',
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                color: app_color,
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
                          if (_isOutstandingListVisible && _isAgeingView) {
                            if (_ageingBuckets.isNotEmpty) {
                              generateAndShareCSV_Ageing();
                            } else {
                              showToast('Data Not Found');
                            }
                          } else if (_isSalesListVisible &&
                              filteredItems_sale_purc_cash.isNotEmpty) {
                            generateAndShareCSV_SalesList();
                          } else if (_isOutstandingListVisible &&
                              filteredItems_receivable_payable.isNotEmpty) {
                            generateAndShareCSV_Outstanding();
                          } else {
                            showToast('Data Not Found');
                          }
                        },
                        child: Row(
                          children: [
                            Icon(
                              Icons.add_chart_outlined,
                              size: 16,
                              color: app_color,
                            ),
                            SizedBox(width: 6),
                            Text(
                              'Share as CSV',
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                color: app_color,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
              icon: Icon(Icons.share, color: Colors.white, size: 26),
            ),
            SizedBox(width: 5),
          ],
        ),
      ),

      body: WillPopScope(
        onWillPop: () async {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => Dashboard()),
          );
          return true;
        },
        child: Stack(
          children: [
            CustomScrollView(
              controller: _scrollFabController,
              slivers: [
                SliverToBoxAdapter(
                  child: Container(
                    margin: EdgeInsets.only(
                      left: 16,
                      right: 16,
                      top: 10,
                      bottom: 10,
                    ),
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(16),
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
                        Container(
                          margin: const EdgeInsets.only(
                            left: 0,
                            right: 0,
                            bottom: 8,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(context).cardColor,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: Theme.of(context).dividerColor,
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black12,
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: TypeAheadField<String>(
                            controller: _voucherController,
                            suggestionsCallback: (pattern) {
                              return spinner_list
                                  .where(
                                    (item) => item.toLowerCase().contains(
                                      pattern.toLowerCase(),
                                    ),
                                  )
                                  .toList();
                            },

                            builder: (context, controller, focusNode) {
                              return TextField(
                                controller: controller,
                                focusNode: focusNode,
                                style: GoogleFonts.poppins(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface,
                                ),
                                decoration: InputDecoration(
                                  labelStyle: GoogleFonts.poppins(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 0,
                                    vertical: 6,
                                  ),
                                  hintText: 'Search',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(18),
                                    borderSide: const BorderSide(
                                      color: Colors.transparent,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderSide: const BorderSide(
                                      color: Colors.transparent,
                                    ),
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(18),
                                    borderSide: const BorderSide(
                                      color: Colors.transparent,
                                    ),
                                  ),
                                  suffixIcon: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (_voucherController.text.isNotEmpty)
                                        GestureDetector(
                                          onTap: () {
                                            setState(() {
                                              _voucherController.clear();
                                              _selectedvoucher =
                                                  spinner_list.first;
                                            });
                                          },
                                          child: Container(
                                            margin: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                            ),
                                            padding: const EdgeInsets.all(6),
                                            decoration: BoxDecoration(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .surfaceContainerHighest
                                                  .withOpacity(
                                                    Theme.of(
                                                              context,
                                                            ).brightness ==
                                                            Brightness.dark
                                                        ? 0.88
                                                        : 0.58,
                                                  ),
                                              shape: BoxShape.circle,
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black12,
                                                  blurRadius: 4,
                                                  offset: const Offset(0, 1),
                                                ),
                                              ],
                                            ),
                                            child: Icon(
                                              Icons.close_rounded,
                                              size: 16,
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                        ),
                                      Icon(
                                        Icons.arrow_drop_down,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurface,
                                      ),
                                    ],
                                  ),
                                  prefixIcon: Icon(
                                    Icons.receipt_long_outlined,
                                    color: app_color,
                                  ),
                                ),
                              );
                            },
                            itemBuilder: (context, suggestion) {
                              return ListTile(
                                leading: Icon(
                                  Icons.receipt_long_outlined,
                                  color: app_color,
                                ),
                                title: Text(
                                  suggestion,
                                  style: GoogleFonts.poppins(
                                    // 👈 Apply Poppins style to menu items
                                    fontSize: 15,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              );
                            },
                            onSelected: (suggestion) {
                              setState(() {
                                _selectedvoucher = suggestion;
                                _voucherController.text = suggestion;
                                fetchListData();
                              });
                            },
                            emptyBuilder: (context) => Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Text(
                                "No voucher found",
                                style: GoogleFonts.poppins(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                        ),

                        SizedBox(height: 4),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          margin: EdgeInsets.only(bottom: 5),
                          decoration: BoxDecoration(
                            color: Theme.of(context).cardColor,
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black12,
                                blurRadius: 10,
                                offset: Offset(0, 4),
                              ),
                            ],
                            border: Border.all(
                              color: Theme.of(context).dividerColor,
                            ),
                          ),
                          child: GestureDetector(
                            onTap: () => _selectDateRange(context),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.calendar_month_outlined,
                                  size: 18,
                                  color: Colors.teal.shade600,
                                ),
                                SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    '$startdate_text  ➜  $enddate_text',
                                    style: GoogleFonts.poppins(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface,
                                    ),
                                    overflow: TextOverflow.visible,
                                  ),
                                ),
                                SizedBox(width: 8),

                                Icon(
                                  Icons.calendar_month_outlined,
                                  size: 18,
                                  color: Colors.teal.shade600,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                SliverToBoxAdapter(
                  child: Container(
                    margin: EdgeInsets.only(left: 16, right: 16, bottom: 12),

                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 12,
                          offset: Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        if (_isopeningVisible)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 32,
                                  height: 32,
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
                                    Icons.account_balance_wallet_outlined,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  openingheading ?? '',
                                  style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  formatOpening(opening_value!),
                                  style: GoogleFonts.poppins(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
                                  ),
                                ),
                              ],
                            ),
                          ),

                        // if (_isSearchViewVisible)
                        if (sales_purc_cash_list.isNotEmpty ||
                            receivable_payable_list.isNotEmpty ||
                            ledgerGroupList.isNotEmpty)
                          Padding(
                            padding: EdgeInsets.only(
                              left: 12,
                              right: 12,
                              top: 5,
                              bottom: 5,
                            ),
                            child: Material(
                              elevation: 2,
                              borderRadius: BorderRadius.circular(18),
                              shadowColor: Colors.black12,
                              child: TextField(
                                controller: searchController,
                                onChanged: _onSearchChanged,

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
                                  suffixIcon: searchController.text.isNotEmpty
                                      ? IconButton(
                                          icon: const Icon(Icons.close),
                                          onPressed: () {
                                            searchController.clear();
                                            _resetSearch();
                                            setState(() {});
                                          },
                                        )
                                      : null,
                                  filled: true,
                                  fillColor:
                                      Theme.of(
                                        context,
                                      ).inputDecorationTheme.fillColor ??
                                      Theme.of(
                                        context,
                                      ).colorScheme.surfaceContainerHighest,
                                  contentPadding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                    horizontal: 16,
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(18),
                                    borderSide: BorderSide(
                                      color: Theme.of(context).dividerColor,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(18),
                                    borderSide: const BorderSide(
                                      color: app_color,
                                      width: 1.5,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),

                        if (_isLedgerGroupVisible &&
                            isVisibleNoDataFound &&
                            !_isLoading &&
                            filteredLedgerGroupList.isEmpty)
                          SizedBox(
                            height: MediaQuery.of(context).size.height * 0.5,
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.inbox_rounded,
                                    size: 40,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    "No records found",
                                    style: GoogleFonts.poppins(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        if (_isLedgerGroupVisible)
                          ListView.builder(
                            shrinkWrap: true,
                            physics: NeverScrollableScrollPhysics(),
                            itemCount: filteredLedgerGroupList.length,
                            itemBuilder: (context, index) {
                              final group = filteredLedgerGroupList[index];
                              double amount = group.amount + group.opening;

                              if (amount.abs() < 0.0001) {
                                amount = 0.0;
                              }
                              return InkWell(
                                onTap: () {
                                  setState(() {
                                    searchController.clear();
                                    FocusScope.of(context).unfocus();
                                    _selectedLedgerGroup = group.ledger;
                                    _isLedgerGroupVisible = false;
                                    _isSalesListVisible = true;
                                  });

                                  fetchSales_purchase_cash(
                                    "cash-in-hand,bank accounts",
                                    startDateString,
                                    endDateString,
                                    "",
                                    "true",
                                    _selectedvoucher ?? "",
                                    _selectedLedgerGroup!,
                                  );
                                },
                                child: Container(
                                  margin: const EdgeInsets.symmetric(
                                    vertical: 6,
                                    horizontal: 8,
                                  ),
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).cardColor,
                                    borderRadius: BorderRadius.circular(18),
                                    border:
                                        Theme.of(context).brightness ==
                                            Brightness.dark
                                        ? Border.all(
                                            color: Colors.white.withOpacity(
                                              0.10,
                                            ),
                                            width: 1,
                                          )
                                        : null,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black12,
                                        blurRadius: 6,
                                        offset: Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      Container(
                                        width: 38,
                                        height: 38,
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              Colors.indigo.shade400,
                                              Colors.indigo.shade700,
                                            ],
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.indigo.withOpacity(
                                                0.25,
                                              ),
                                              blurRadius: 6,
                                              offset: const Offset(0, 3),
                                            ),
                                          ],
                                        ),
                                        child: const Icon(
                                          Icons.account_balance_wallet_rounded,
                                          color: Colors.white,
                                          size: 20,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              group.ledger,
                                              style: GoogleFonts.poppins(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600,
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.onSurface,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Align(
                                              alignment: Alignment.centerRight,
                                              child: Text(
                                                textAlign: TextAlign.end,
                                                formatAmount(amount.toString()),
                                                style: GoogleFonts.poppins(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w700,
                                                  color: Colors.teal,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Icon(
                                        Icons.chevron_right_rounded,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                        size: 22,
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),

                        if (_isSalesListVisible)
                          Column(
                            children: [
                              if (vchtypes == "Cash" && !_isLedgerGroupVisible)
                                Container(
                                  margin: const EdgeInsets.only(
                                    left: 16,
                                    right: 16,
                                    top: 0,
                                    bottom: 0,
                                  ),
                                  alignment: Alignment.centerLeft,
                                  child: TextButton.icon(
                                    onPressed: () {
                                      setState(() {
                                        _isSalesListVisible = false;
                                        _isLedgerGroupVisible = true;
                                        searchController.clear();
                                        FocusScope.of(context).unfocus();
                                        fetchLedgerGroups();
                                        // filteredLedgerGroupList = ledgerGroupList;
                                      });
                                    },
                                    icon: const Icon(
                                      Icons.arrow_back_ios_new_rounded,
                                      size: 16,
                                      color: app_color, // use your theme color
                                    ),
                                    label: Text(
                                      "Previous",
                                      style: GoogleFonts.poppins(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color:
                                            app_color, // your app’s accent color
                                      ),
                                    ),
                                    style: TextButton.styleFrom(
                                      backgroundColor:
                                          Colors.transparent, // no fill color
                                      elevation: 0,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                        vertical: 6,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                  ),
                                ),

                              if (isVisibleNoDataFound && !_isLoading)
                                SizedBox(
                                  height:
                                      MediaQuery.of(context).size.height * 0.5,
                                  child: Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.inbox_rounded,
                                          size: 40,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                        const SizedBox(height: 10),
                                        Text(
                                          "No records found",
                                          style: GoogleFonts.poppins(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w500,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),

                              // The existing vouchers list
                              ListView.builder(
                                shrinkWrap: true,
                                physics: NeverScrollableScrollPhysics(),
                                controller: _scrollController_salelist,
                                itemCount: filteredItems_sale_purc_cash.length,
                                itemBuilder: (context, index) {
                                  final card =
                                      filteredItems_sale_purc_cash[index];
                                  return buildModernVoucherCard(
                                    card,
                                    index: index,
                                  );
                                },
                              ),
                            ],
                          ),

                        if (_isOutstandingListVisible && _isAgeingView) ...[
                          if (_isAgeingComputing)
                            SizedBox(
                              height: MediaQuery.of(context).size.height * 0.5,
                              child: const Center(child: AppLogoLoader()),
                            )
                          else if (_selectedAgeingBucket != null) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () {
                                  setState(() {
                                    _selectedAgeingBucket = null;
                                  });
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.arrow_back_rounded,
                                        size: 20,
                                        color: app_color,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        _selectedAgeingBucket!.label,
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
                            ListView.builder(
                              shrinkWrap: true,
                              physics: NeverScrollableScrollPhysics(),
                              itemCount: _selectedAgeingBucket!.items.length,
                              itemBuilder: (context, index) {
                                return buildReceivableCard(
                                  _selectedAgeingBucket!.items[index],
                                  index: index,
                                );
                              },
                            ),
                          ] else if (_ageingBuckets.isEmpty)
                            SizedBox(
                              height: MediaQuery.of(context).size.height * 0.5,
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.inbox_rounded,
                                      size: 40,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      "No records found",
                                      style: GoogleFonts.poppins(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          else
                            ListView.builder(
                              shrinkWrap: true,
                              physics: NeverScrollableScrollPhysics(),
                              itemCount: _ageingBuckets.length,
                              itemBuilder: (context, index) {
                                return buildAgeingBucketCard(_ageingBuckets[index]);
                              },
                            ),
                        ] else if (_isOutstandingListVisible) ...[
                          if (isVisibleNoDataFound && !_isLoading)
                            SizedBox(
                              height: MediaQuery.of(context).size.height * 0.5,
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.inbox_rounded,
                                      size: 40,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      "No records found",
                                      style: GoogleFonts.poppins(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ListView.builder(
                            shrinkWrap: true,
                            physics: NeverScrollableScrollPhysics(),
                            controller: _scrollController_receivablellist,
                            itemCount: filteredItems_receivable_payable.length,
                            itemBuilder: (context, index) {
                              final card =
                                  filteredItems_receivable_payable[index];
                              return buildReceivableCard(card, index: index);
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),

            if (isSortVisible)
              Positioned(
                bottom: 15,
                left: 0,
                right: 0,
                child: Center(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => _showSelectionWindow(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              app_color,
                              app_color.withValues(alpha: 0.85),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: app_color.withValues(alpha: 0.35),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.swap_vert_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              selectedSortOption.isEmpty ||
                                      selectedSortOption == 'Default'
                                  ? 'Sort'
                                  : selectedSortOption,
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            Visibility(
              visible: _isLoading,
              child: Center(child: AppLogoLoader()),
            ),
            ScrollFab(controller: _scrollFabController),
          ],
        ),
      ),
    );
  }

  List<Color> _dashboardCardGradientColors() {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return [
      colorScheme.surface.withOpacity(isDark ? 0.96 : 1),
      colorScheme.surfaceContainerHighest.withOpacity(isDark ? 0.72 : 0.38),
    ];
  }

  Color _dashboardCardBorderColor() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Theme.of(context).dividerColor.withOpacity(isDark ? 0.7 : 0.55);
  }

  Color _dashboardDetailSurfaceColor() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Theme.of(
      context,
    ).colorScheme.surfaceContainerHighest.withOpacity(isDark ? 0.34 : 0.42);
  }

  Widget buildModernVoucherCard(Sale_purc_cash card, {int index = 0}) {
    final extraCount = getExtraLedgerCount(card.ledgers, card.ledger);

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 400 + (index * 50).clamp(0, 300)),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - value)),
            child: child,
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          splashColor: app_color.withOpacity(0.1),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => TransactionsClicked(
                  vchtype: card.vchname,
                  startdate: startDateString,
                  enddate: endDateString,
                  vchno: card.vchno,
                  vchdate: card.vchdate,
                  ispostdated: card.ispostdated,
                  isoptional: card.isoptional,
                  refno: card.refno,
                  refdate: card.refdate,
                  masterid: card.masterid,
                ),
              ),
            );
          },
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                colors: _dashboardCardGradientColors(),
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
              border: Border.all(color: _dashboardCardBorderColor(), width: 1),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.indigo.shade400,
                              Colors.indigo.shade800,
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.indigo.withOpacity(0.25),
                              blurRadius: 6,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.account_balance_wallet_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              card.ledger,
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                            if (extraCount > 0)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _dashboardDetailSurfaceColor(),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    "+$extraCount more",
                                    style: GoogleFonts.poppins(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            formatAmount(card.amount.toString()),
                            style: GoogleFonts.poppins(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 20,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: _dashboardDetailSurfaceColor(),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Row(
                            children: [
                              Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.teal.shade400,
                                      Colors.teal.shade700,
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.receipt_long_outlined,
                                  color: Colors.white,
                                  size: 14,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  card.vchno.isNotEmpty ? card.vchno : "-",
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          flex: 5,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Container(
                                width: 24,
                                height: 24,
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
                                  Icons.calendar_today_outlined,
                                  color: Colors.white,
                                  size: 14,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  convertDateFormat(card.vchdate),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.right,
                                  style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      if (card.vchname.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: app_color.withOpacity(
                              Theme.of(context).brightness == Brightness.dark
                                  ? 0.18
                                  : 0.08,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: app_color.withOpacity(
                                Theme.of(context).brightness == Brightness.dark
                                    ? 0.42
                                    : 0.3,
                              ),
                            ),
                          ),
                          child: Text(
                            card.vchname,
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: app_color.withOpacity(
                                Theme.of(context).brightness == Brightness.dark
                                    ? 0.95
                                    : 0.7,
                              ),
                            ),
                          ),
                        ),
                      if (card.ispostdated == "1")
                        _buildTag("Post Dated", Colors.orange),
                      if (card.isoptional == "1")
                        _buildTag("Optional", Colors.blue),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 🔹 Tag chip
  Widget _buildTag(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(
          Theme.of(context).brightness == Brightness.dark ? 0.18 : 0.08,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withOpacity(
            Theme.of(context).brightness == Brightness.dark ? 0.42 : 0.3,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.15),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Text(
        label,
        style: GoogleFonts.poppins(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: color.withOpacity(
            Theme.of(context).brightness == Brightness.dark ? 0.95 : 0.7,
          ),
        ),
      ),
    );
  }

  // 🔹 Receivable/Payable Card
  Widget buildAgeingBucketCard(AgeingBucket bucket) {
    final bool isOverdue = bucket.label != 'Not Due' && bucket.label != 'Others';
    final MaterialColor accentColor = bucket.label == 'Not Due'
        ? Colors.teal
        : bucket.label == 'Others'
            ? Colors.blueGrey
            : Colors.deepOrange;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        splashColor: app_color.withOpacity(0.08),
        onTap: () {
          setState(() {
            _selectedAgeingBucket = bucket;
          });
        },
        child: Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: _dashboardCardGradientColors(),
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black12.withOpacity(0.08),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
        border: Border.all(color: _dashboardCardBorderColor()),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
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
                boxShadow: [
                  BoxShadow(
                    color: Colors.black26.withOpacity(0.15),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(
                isOverdue ? Icons.timer_outlined : Icons.check_circle_outline,
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
                    '${bucket.count} bill${bucket.count == 1 ? '' : 's'}',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    formatAmount(bucket.amount.toString()),
                    softWrap: true,
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: getAmountColor(vchtypes),
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ],
        ),
      ),
        ),
      ),
    );
  }

  Widget buildReceivableCard(Receivable_payable card, {int index = 0}) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 400 + (index * 50).clamp(0, 300)),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - value)),
            child: child,
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          splashColor: app_color.withOpacity(0.08),
          onTap: () {},
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                colors: _dashboardCardGradientColors(),
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black12.withOpacity(0.08),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
              border: Border.all(color: _dashboardCardBorderColor()),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.indigo.shade400,
                              Colors.indigo.shade700,
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black26.withOpacity(0.15),
                              blurRadius: 6,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.account_balance_outlined,
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
                              card.ledger,
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                              softWrap: true,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              formatAmount(card.outstanding.toString()),
                              softWrap: true,
                              style: GoogleFonts.poppins(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: getAmountColor(vchtypes),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: _dashboardDetailSurfaceColor(),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Bill No — gets the full row width since it's usually the longest value
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 24,
                              height: 24,
                              margin: const EdgeInsets.only(top: 1),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.blue.shade400,
                                    Colors.blue.shade700,
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.confirmation_number_outlined,
                                color: Colors.white,
                                size: 14,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                card.billno != "null" ? card.billno : "-",
                                softWrap: true,
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Divider(
                          height: 1,
                          thickness: 1,
                          color: Theme.of(
                            context,
                          ).dividerColor.withOpacity(0.3),
                        ),
                        const SizedBox(height: 10),
                        // Date + Bill type side by side
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 24,
                                    height: 24,
                                    margin: const EdgeInsets.only(top: 1),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          Colors.brown.shade400,
                                          Colors.brown.shade500,
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(
                                      Icons.date_range,
                                      color: Colors.white,
                                      size: 14,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      card.billdate != "null"
                                          ? formatdate(card.billdate)
                                          : "-",
                                      softWrap: true,
                                      style: GoogleFonts.poppins(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurface,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 24,
                                    height: 24,
                                    margin: const EdgeInsets.only(top: 1),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          Colors.purple.shade400,
                                          Colors.purple.shade700,
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(
                                      Icons.description_outlined,
                                      color: Colors.white,
                                      size: 14,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      card.billtype != "null"
                                          ? card.billtype
                                          : "-",
                                      softWrap: true,
                                      style: GoogleFonts.poppins(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurface,
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
                  if (_isVisibleduedate &&
                      (card.billtype == 'Agst Ref' ||
                          card.billtype == 'New Ref')) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color:
                            getDueDateColor(
                              formatDueDate(
                                card.billdate,
                                card.billtype,
                                card.duedate,
                              ),
                              vchtypes,
                            ).withOpacity(
                              Theme.of(context).brightness == Brightness.dark
                                  ? 0.18
                                  : 0.1,
                            ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: getDueDateColor(
                            formatDueDate(
                              card.billdate,
                              card.billtype,
                              card.duedate,
                            ),
                            vchtypes,
                          ).withOpacity(0.4),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.calendar_today_rounded,
                            size: 14,
                            color: getDueDateColor(
                              formatDueDate(
                                card.billdate,
                                card.billtype,
                                card.duedate,
                              ),
                              vchtypes,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            "Due: ${formatDueDate(card.billdate, card.billtype, card.duedate)}",
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: getDueDateColor(
                                formatDueDate(
                                  card.billdate,
                                  card.billtype,
                                  card.duedate,
                                ),
                                vchtypes,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Color getDueDateColor(String dueDateStr, String type) {
  try {
    final due = DateFormat("dd-MMM-yy").parse(dueDateStr);
    final now = DateTime.now();
    final diffDays = due.difference(now).inDays;

    if (due.isBefore(now)) return Colors.red;

    if (diffDays <= 7) {
      return type == "Receivable" ? Colors.orange : Colors.deepOrange;
    }

    return type == "Receivable" ? Colors.green : Colors.teal;
  } catch (_) {
    return Colors.grey.shade600;
  }
}

Color getAmountColor(String type) {
  switch (type) {
    case 'Receivable':
      return Colors.green.shade700;
    case 'Payable':
      return Colors.red.shade700;
    default:
      return Colors.blueGrey;
  }
}
