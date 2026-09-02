import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../DashboardClicked.dart';
import '../api/ledger_repository.dart';
import '../api/monthly_bucket_helper.dart';
import '../api/pagination_helper.dart';
import '../api/tally_api_client.dart';
import '../api/voucher_repository.dart';
import 'repository_providers.dart';

/// Riverpod migration of `DashboardClicked.dart`'s `_DashboardClickedPageState`.
///
/// Same verbatim-port `_commit`/`_snapshot` strategy used for
/// `party_clicked_notifier.dart`: every mutating method here is a
/// byte-for-byte port of the original `State` method with `setState(() {
/// ... })` replaced by `_commit(() { ... })`, so the accumulator-style
/// ageing-bucket/party-ageing/top-parties computations keep their exact
/// original mutation order.
///
/// NOT ported here (stay widget-local, unchanged, in `DashboardClicked.dart`):
/// - `TextEditingController`s (`_voucherController`, `searchController`),
///   `ScrollController`s, `GlobalKey`s - Riverpod doesn't need to own these.
/// - `vchtypes` - immutable per-instance config (like `partyname` in
///   `PartyClicked`), never reassigned after construction.
/// - `formatDueDate`/`formatDueDate_Sort`/`convertDateFormat`/
///   `getExtraLedgerCount` - pure render-time helpers with no persisted
///   state (the `_isVisibleduedate` flag they touch is a scratch render
///   var recomputed every build, not real state).
/// - The 8 PDF/CSV export methods - read-only, converted via the
///   alias-variable pattern (`final vm = _s; final x = vm.x;`) instead.
/// - `_selectDateRange`/`_showSelectionWindow` - need `BuildContext`, stay
///   in the widget, calling into this notifier for the resulting mutation.
///
/// Dead fields confirmed unused anywhere in `build()` (grepped against the
/// legacy session-based access-control fields, same pattern as
/// `party_clicked_notifier.dart`) and dropped rather than ported:
/// `SecuritybtnAcessHolder`, `isDashEnable`, `isRolesEnable`, `isUserEnable`,
/// `isRolesVisible`, `isUserVisible`, `email`, `name`, `datetype`,
/// `HttpURL`, `myData`, `counter`/`_isSearchViewVisible` (only referenced by
/// a commented-out block), `startdate_pref`/`enddate_pref`,
/// `_ageingBucketsDefaultOrder`/`_partyAgeingDefaultOrder`/
/// `_topPartiesDefaultOrder` (kept, but as notifier-private fields only -
/// never read outside the sort helpers that restore "Default" order).
class DashboardClickedState {
  final String startDateString;
  final String endDateString;
  final String selectedSortOption;

  final bool isLedgerGroupVisible;
  final String? selectedLedgerGroup;
  final List<LedgerGroup> ledgerGroupList;
  final List<LedgerGroup> filteredLedgerGroupList;

  final bool isAgeingView;
  final bool isAgeingComputing;
  final bool isSwitchingView;
  final List<AgeingBucket> ageingBuckets;
  final AgeingBucket? selectedAgeingBucket;

  final bool isPartyAgeingView;
  final List<PartyAgeingEntry> partyAgeing;
  final PartyAgeingEntry? selectedPartyAgeing;

  final bool isTopPartiesView;
  final bool isSwitchingTopPartiesView;
  final List<TopPartyEntry> topParties;
  final TopPartyEntry? selectedTopParty;

  final List<Receivable_payable> filteredItemsReceivablePayable;
  final List<Sale_purc_cash> filteredItemsSalePurcCash;
  final List<Sale_purc_cash> salesPurcCashList;
  final List<Receivable_payable> receivablePayableList;

  final bool isSalesListVisible;
  final bool isOutstandingListVisible;

  final String? openingValue;
  final String? openingHeading;

  final bool isVisibleNoDataFound;
  final bool isOpeningVisible;
  final bool isSortVisible;

  final String reportSearchQuery;

  final String startDateText;
  final String endDateText;

  final String? company;
  final bool isLoading;

  final String selectedVoucher;
  final List<String> spinnerList;

  const DashboardClickedState({
    required this.startDateString,
    required this.endDateString,
    required this.selectedSortOption,
    required this.isLedgerGroupVisible,
    required this.selectedLedgerGroup,
    required this.ledgerGroupList,
    required this.filteredLedgerGroupList,
    required this.isAgeingView,
    required this.isAgeingComputing,
    required this.isSwitchingView,
    required this.ageingBuckets,
    required this.selectedAgeingBucket,
    required this.isPartyAgeingView,
    required this.partyAgeing,
    required this.selectedPartyAgeing,
    required this.isTopPartiesView,
    required this.isSwitchingTopPartiesView,
    required this.topParties,
    required this.selectedTopParty,
    required this.filteredItemsReceivablePayable,
    required this.filteredItemsSalePurcCash,
    required this.salesPurcCashList,
    required this.receivablePayableList,
    required this.isSalesListVisible,
    required this.isOutstandingListVisible,
    required this.openingValue,
    required this.openingHeading,
    required this.isVisibleNoDataFound,
    required this.isOpeningVisible,
    required this.isSortVisible,
    required this.reportSearchQuery,
    required this.startDateText,
    required this.endDateText,
    required this.company,
    required this.isLoading,
    required this.selectedVoucher,
    required this.spinnerList,
  });
}

class DashboardClickedArgs {
  final String startDateString;
  final String endDateString;
  final String vchtypes;

  const DashboardClickedArgs({
    required this.startDateString,
    required this.endDateString,
    required this.vchtypes,
  });

  @override
  bool operator ==(Object other) =>
      other is DashboardClickedArgs &&
      other.startDateString == startDateString &&
      other.endDateString == endDateString &&
      other.vchtypes == vchtypes;

  @override
  int get hashCode => Object.hash(startDateString, endDateString, vchtypes);
}

class DashboardClickedNotifier extends StateNotifier<DashboardClickedState> {
  final Ref _ref;
  final String vchtypes;

  DashboardClickedNotifier(this._ref, DashboardClickedArgs args)
    : vchtypes = args.vchtypes,
      startDateString = args.startDateString,
      endDateString = args.endDateString,
      super(
        DashboardClickedState(
          startDateString: args.startDateString,
          endDateString: args.endDateString,
          selectedSortOption: '',
          isLedgerGroupVisible: false,
          selectedLedgerGroup: null,
          ledgerGroupList: const [],
          filteredLedgerGroupList: const [],
          isAgeingView: false,
          isAgeingComputing: false,
          isSwitchingView: false,
          ageingBuckets: const [],
          selectedAgeingBucket: null,
          isPartyAgeingView: false,
          partyAgeing: const [],
          selectedPartyAgeing: null,
          isTopPartiesView: false,
          isSwitchingTopPartiesView: false,
          topParties: const [],
          selectedTopParty: null,
          filteredItemsReceivablePayable: const [],
          filteredItemsSalePurcCash: const [],
          salesPurcCashList: const [],
          receivablePayableList: const [],
          isSalesListVisible: false,
          isOutstandingListVisible: false,
          openingValue: '0',
          openingHeading: '',
          isVisibleNoDataFound: false,
          isOpeningVisible: true,
          isSortVisible: false,
          reportSearchQuery: '',
          startDateText: '',
          endDateText: '',
          company: '',
          isLoading: false,
          selectedVoucher: '',
          spinnerList: const [],
        ),
      ) {
    _init();
  }

  void _commit(void Function() fn) {
    fn();
    state = _snapshot();
  }

  DashboardClickedState _snapshot() => DashboardClickedState(
    startDateString: startDateString,
    endDateString: endDateString,
    selectedSortOption: selectedSortOption,
    isLedgerGroupVisible: _isLedgerGroupVisible,
    selectedLedgerGroup: _selectedLedgerGroup,
    ledgerGroupList: List.unmodifiable(ledgerGroupList),
    filteredLedgerGroupList: List.unmodifiable(filteredLedgerGroupList),
    isAgeingView: _isAgeingView,
    isAgeingComputing: _isAgeingComputing,
    isSwitchingView: _isSwitchingView,
    ageingBuckets: List.unmodifiable(_ageingBuckets),
    selectedAgeingBucket: _selectedAgeingBucket,
    isPartyAgeingView: _isPartyAgeingView,
    partyAgeing: List.unmodifiable(_partyAgeing),
    selectedPartyAgeing: _selectedPartyAgeing,
    isTopPartiesView: _isTopPartiesView,
    isSwitchingTopPartiesView: _isSwitchingTopPartiesView,
    topParties: List.unmodifiable(_topParties),
    selectedTopParty: _selectedTopParty,
    filteredItemsReceivablePayable: List.unmodifiable(
      filteredItems_receivable_payable,
    ),
    filteredItemsSalePurcCash: List.unmodifiable(filteredItems_sale_purc_cash),
    salesPurcCashList: List.unmodifiable(sales_purc_cash_list),
    receivablePayableList: List.unmodifiable(receivable_payable_list),
    isSalesListVisible: _isSalesListVisible,
    isOutstandingListVisible: _isOutstandingListVisible,
    openingValue: opening_value,
    openingHeading: openingheading,
    isVisibleNoDataFound: isVisibleNoDataFound,
    isOpeningVisible: _isopeningVisible,
    isSortVisible: isSortVisible,
    reportSearchQuery: _reportSearchQuery,
    startDateText: startdate_text,
    endDateText: enddate_text,
    company: company,
    isLoading: _isLoading,
    selectedVoucher: _selectedvoucher is String ? _selectedvoucher : '',
    spinnerList: List.unmodifiable(spinner_list),
  );

  // ---- verbatim-ported mutable fields (same names as the original State) ----

  String startDateString;
  String endDateString;
  String selectedSortOption = '';

  bool _isLedgerGroupVisible = false;
  String? _selectedLedgerGroup;
  List<LedgerGroup> ledgerGroupList = [];

  bool _isAgeingView = false;
  bool _isAgeingComputing = false;
  bool _isSwitchingView = false;
  List<AgeingBucket> _ageingBuckets = [];
  List<AgeingBucket> _ageingBucketsDefaultOrder = [];
  AgeingBucket? _selectedAgeingBucket;

  bool _isPartyAgeingView = false;
  List<PartyAgeingEntry> _partyAgeing = [];
  List<PartyAgeingEntry> _partyAgeingDefaultOrder = [];
  PartyAgeingEntry? _selectedPartyAgeing;

  bool _isTopPartiesView = false;
  bool _isSwitchingTopPartiesView = false;
  List<TopPartyEntry> _topParties = [];
  List<TopPartyEntry> _topPartiesDefaultOrder = [];
  TopPartyEntry? _selectedTopParty;

  List<Receivable_payable> filteredItems_receivable_payable = [];
  List<Sale_purc_cash> filteredItems_sale_purc_cash = [];
  List<LedgerGroup> filteredLedgerGroupList = [];

  bool _isSalesListVisible = false;
  bool _isOutstandingListVisible = false;

  String? opening_value = "0", openingheading = "";

  bool isVisibleNoDataFound = false;
  bool _isopeningVisible = true;

  bool isSortVisible = false;

  String _reportSearchQuery = '';

  String allparties = 'All Parties', allvchtypes = 'All Voucher Types';

  late String startdate_text = "", enddate_text = "";

  String? company = "";

  bool _isLoading = false;

  dynamic _selectedvoucher = "";
  List<String> spinner_list = [];
  final Map<String, int> _voucherTypeMasterIdByName = {};

  List<Sale_purc_cash> sales_purc_cash_list = [];
  List<Receivable_payable> receivable_payable_list = [];

  LedgerRepository get _ledgerRepository =>
      _ref.read(ledgerRepositoryProvider);
  VoucherRepository get _voucherRepository =>
      _ref.read(voucherRepositoryProvider);

  int getExtraLedgerCount(List<LedgerEntry>? ledgers, String mainLedger) {
    if (ledgers == null || ledgers.isEmpty) return 0;
    return ledgers
        .where((l) => l.ledgername.toLowerCase() != mainLedger.toLowerCase())
        .length;
  }

  // 🔍 SEARCH LOGIC
  void onSearchChanged(String query) {
    final q = query.toLowerCase();
    _commit(() {
      _reportSearchQuery = q;
    });

    if (vchtypes == "Cash" && _isLedgerGroupVisible) {
      _commit(() {
        filteredLedgerGroupList = ledgerGroupList.where((item) {
          return item.ledger.toLowerCase().contains(q);
        }).toList();
      });
    } else if (vchtypes == "Cash" && !_isLedgerGroupVisible) {
      _commit(() {
        filteredItems_sale_purc_cash = sales_purc_cash_list.where((item) {
          return item.ledger.toLowerCase() ==
                  _selectedLedgerGroup?.toLowerCase() &&
              (item.vchno.toLowerCase().contains(q) ||
                  item.vchname.toLowerCase().contains(q) ||
                  item.ledger.toLowerCase().contains(q));
        }).toList();
      });
    } else if (vchtypes == "Receivable" || vchtypes == "Payable") {
      _commit(() {
        filteredItems_receivable_payable = receivable_payable_list.where((
          item,
        ) {
          return item.ledger.toLowerCase().contains(q) ||
              item.billno.toLowerCase().contains(q) ||
              item.billtype.toLowerCase().contains(q);
        }).toList();
      });
    } else if (vchtypes == "Cash") {
      _commit(() {
        filteredLedgerGroupList = ledgerGroupList.where((item) {
          return item.ledger.toLowerCase().contains(q);
        }).toList();
      });
    } else {
      _commit(() {
        filteredItems_sale_purc_cash = sales_purc_cash_list.where((item) {
          return item.vchno.toLowerCase().contains(q) ||
              item.vchname.toLowerCase().contains(q) ||
              item.ledger.toLowerCase().contains(q);
        }).toList();
      });
    }
  }

  List<Sale_purc_cash> searchFilterVouchers(List<Sale_purc_cash> items) {
    if (_reportSearchQuery.isEmpty) return items;
    return items
        .where(
          (v) =>
              v.vchno.toLowerCase().contains(_reportSearchQuery) ||
              v.vchname.toLowerCase().contains(_reportSearchQuery) ||
              v.ledger.toLowerCase().contains(_reportSearchQuery),
        )
        .toList();
  }

  List<Receivable_payable> searchFilterBills(List<Receivable_payable> items) {
    if (_reportSearchQuery.isEmpty) return items;
    return items
        .where(
          (b) =>
              b.ledger.toLowerCase().contains(_reportSearchQuery) ||
              b.billno.toLowerCase().contains(_reportSearchQuery) ||
              b.billtype.toLowerCase().contains(_reportSearchQuery),
        )
        .toList();
  }

  List<AgeingBucket> searchFilterBuckets(List<AgeingBucket> items) {
    if (_reportSearchQuery.isEmpty) return items;
    return items
        .where((b) => b.label.toLowerCase().contains(_reportSearchQuery))
        .toList();
  }

  List<PartyAgeingEntry> searchFilterPartyAgeing(
    List<PartyAgeingEntry> items,
  ) {
    if (_reportSearchQuery.isEmpty) return items;
    return items
        .where((p) => p.ledger.toLowerCase().contains(_reportSearchQuery))
        .toList();
  }

  List<TopPartyEntry> searchFilterTopParties(List<TopPartyEntry> items) {
    if (_reportSearchQuery.isEmpty) return items;
    return items
        .where((p) => p.ledger.toLowerCase().contains(_reportSearchQuery))
        .toList();
  }

  void resetSearch() {
    _commit(() {
      _reportSearchQuery = '';
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

  double getTotalAmount() {
    if (vchtypes == "Receivable" || vchtypes == "Payable") {
      if (_isAgeingView &&
          _isPartyAgeingView &&
          _selectedPartyAgeing != null) {
        return _selectedPartyAgeing!.overdueAmount;
      }
      if (_isAgeingView && _selectedAgeingBucket != null) {
        return _selectedAgeingBucket!.amount;
      }
      double billsTotal = filteredItems_receivable_payable.fold(0.0, (
        sum,
        item,
      ) {
        return sum + item.outstanding;
      });
      double opening = double.tryParse(opening_value ?? "0") ?? 0.0;
      return billsTotal + opening;
    } else if (vchtypes == "Cash" && _isLedgerGroupVisible) {
      double voucherTotal = filteredLedgerGroupList.fold(0.0, (sum, item) {
        return sum + (item.amount + item.opening);
      });
      return voucherTotal;
    } else if (vchtypes == "Cash" && !_isLedgerGroupVisible) {
      double voucherTotal = filteredItems_sale_purc_cash.fold(0.0, (
        sum,
        item,
      ) {
        return sum + item.amount;
      });
      double opening = double.tryParse(opening_value ?? "0") ?? 0.0;
      return voucherTotal + opening;
    } else {
      if (_isTopPartiesView && _selectedTopParty != null) {
        return _selectedTopParty!.amount;
      }
      return filteredItems_sale_purc_cash.fold(0.0, (sum, item) {
        return sum + item.amount;
      });
    }
  }

  Future<void> fetchLedgerGroups() {
    return _fetchLedgerGroupsTallyApi();
  }

  Future<void> _fetchLedgerGroupsTallyApi() async {
    _commit(() {
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
      final groups = await fetchAllPages(
        (page) =>
            TallyApiClient().getForCompany('/groups?page=$page&limit=100'),
      );
      const cashBankReservedNames = {'CASH', 'BANK', 'BANK_OD'};
      final cashBankGroupIds = groups
          .where((g) => cashBankReservedNames.contains(g['reservedName']))
          .map((g) => g['masterId'] as int)
          .toSet();

      final cashBankLedgers = <Map<String, dynamic>>[];
      for (final groupId in cashBankGroupIds) {
        cashBankLedgers.addAll(
          await _ledgerRepository.listLedgers(groupMasterId: groupId),
        );
      }

      double totalOpening = 0;
      final ledgerGroups = <LedgerGroup>[];
      for (final ledger in cashBankLedgers) {
        final opening = parseMoneyField(ledger['openingBalance']);
        final closing = parseMoneyField(ledger['closingBalance']);
        totalOpening += opening;
        ledgerGroups.add(
          LedgerGroup.fromJson({
            'ledger': ledger['name'] ?? '',
            'amount': closing - opening,
            'opening': opening,
          }),
        );
      }

      if (!mounted) return;
      _commit(() {
        opening_value = totalOpening.toString();
        ledgerGroupList = ledgerGroups;
        filteredLedgerGroupList = ledgerGroupList;
        _isLedgerGroupVisible = true;
        _isSalesListVisible = false;
        _isOutstandingListVisible = false;
        isVisibleNoDataFound = ledgerGroups.isEmpty;
      });
    } catch (e) {
      if (!mounted) return;
      _commit(() {
        _isLedgerGroupVisible = false;
        _isSalesListVisible = false;
        _isOutstandingListVisible = false;
        isVisibleNoDataFound = true;
      });
    } finally {
      if (mounted) _commit(() => _isLoading = false);
    }
  }

  void sortByDefault() {
    _commit(() {
      if (filteredItems_sale_purc_cash.isNotEmpty) {
        if (vchtypes == "Cash") {
          filteredItems_sale_purc_cash = sales_purc_cash_list
              .where(
                (e) =>
                    e.ledger.toLowerCase() ==
                    _selectedLedgerGroup!.toLowerCase(),
              )
              .toList();
        } else {
          filteredItems_sale_purc_cash = List.from(sales_purc_cash_list);
        }
      } else if (filteredItems_receivable_payable.isNotEmpty) {
        filteredItems_receivable_payable = List.from(receivable_payable_list);
      }
    });
  }

  void sortByAlphabetAtoZ() {
    _commit(() {
      if (filteredItems_sale_purc_cash.isNotEmpty) {
        if (vchtypes == 'Sales' || vchtypes == 'Purchase') {
          filteredItems_sale_purc_cash.sort(
            (a, b) => a.vchname.compareTo(b.vchname),
          );
        } else {
          filteredItems_sale_purc_cash.sort(
            (a, b) => a.ledger.compareTo(b.ledger),
          );
        }
      } else if (filteredItems_receivable_payable.isNotEmpty) {
        filteredItems_receivable_payable.sort(
          (a, b) => a.ledger.compareTo(b.ledger),
        );
      }
    });
  }

  void sortByAlphabetZtoA() {
    _commit(() {
      if (filteredItems_sale_purc_cash.isNotEmpty) {
        if (vchtypes == 'Sales' || vchtypes == 'Purchase') {
          filteredItems_sale_purc_cash.sort(
            (a, b) => b.vchname.compareTo(a.vchname),
          );
        } else {
          filteredItems_sale_purc_cash.sort(
            (a, b) => b.ledger.compareTo(a.ledger),
          );
        }
      } else if (filteredItems_receivable_payable.isNotEmpty) {
        filteredItems_receivable_payable.sort(
          (a, b) => b.ledger.compareTo(a.ledger),
        );
      }
    });
  }

  void sortByDateLowtoHigh() {
    _commit(() {
      if (filteredItems_sale_purc_cash.isNotEmpty) {
        filteredItems_sale_purc_cash.sort(
          (a, b) => a.vchdate.compareTo(b.vchdate),
        );
      } else if (filteredItems_receivable_payable.isNotEmpty) {
        filteredItems_receivable_payable.sort(
          (a, b) =>
              DateTime.parse(a.billdate).compareTo(DateTime.parse(b.billdate)),
        );
      }
    });
  }

  void sortByDateHightoLow() {
    _commit(() {
      if (filteredItems_sale_purc_cash.isNotEmpty) {
        filteredItems_sale_purc_cash.sort(
          (a, b) => b.vchdate.compareTo(a.vchdate),
        );
      } else if (filteredItems_receivable_payable.isNotEmpty) {
        filteredItems_receivable_payable.sort(
          (a, b) =>
              DateTime.parse(b.billdate).compareTo(DateTime.parse(a.billdate)),
        );
      }
    });
  }

  void sortByAmountLowtoHigh() {
    _commit(() {
      if (filteredItems_sale_purc_cash.isNotEmpty) {
        if (vchtypes == 'Payment') {
          filteredItems_sale_purc_cash.sort(
            (a, b) => b.amount.compareTo(a.amount),
          );
        } else {
          filteredItems_sale_purc_cash.sort(
            (a, b) => a.amount.compareTo(b.amount),
          );
        }
      } else if (filteredItems_receivable_payable.isNotEmpty) {
        if (vchtypes == "Receivable") {
          filteredItems_receivable_payable.sort(
            (a, b) => b.outstanding.compareTo(a.outstanding),
          );
        } else {
          filteredItems_receivable_payable.sort(
            (a, b) => a.outstanding.compareTo(b.outstanding),
          );
        }
      }
    });
  }

  void sortByAmountHightoLow() {
    _commit(() {
      if (filteredItems_sale_purc_cash.isNotEmpty) {
        if (vchtypes == "Payment") {
          filteredItems_sale_purc_cash.sort(
            (a, b) => a.amount.compareTo(b.amount),
          );
        } else {
          filteredItems_sale_purc_cash.sort(
            (a, b) => b.amount.compareTo(a.amount),
          );
        }
      } else if (filteredItems_receivable_payable.isNotEmpty) {
        if (vchtypes == "Receivable") {
          filteredItems_receivable_payable.sort(
            (a, b) => a.outstanding.compareTo(b.outstanding),
          );
        } else {
          filteredItems_receivable_payable.sort(
            (a, b) => b.outstanding.compareTo(a.outstanding),
          );
        }
      }
    });
  }

  void applySortOption(String option) {
    _commit(() => selectedSortOption = option);
    if (_isOutstandingListVisible && _isAgeingView && _isPartyAgeingView) {
      _applyPartyAgeingSort(option);
    } else if (_isOutstandingListVisible && _isAgeingView) {
      _applyAgeingSort(option);
    } else if (_isSalesListVisible && _isTopPartiesView) {
      _applyTopPartiesSort(option);
    } else {
      switch (option) {
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
      _commit(() {
        if (vchtypes == "Cash") {
          _isSalesListVisible = false;
        } else {
          _isSalesListVisible = true;
        }
        _isOutstandingListVisible = false;
      });
    } else if (vchtypes == "Receivable" || vchtypes == "Payable") {
      if (vchtypes == "Receivable") {
        fetchParent_Receivable_Payable();
      } else if (vchtypes == "Payable") {
        fetchParent_Receivable_Payable();
      }
      _commit(() {
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
          fetchLedgerGroups();
        }
      } else if (vchtypes == "Receipt" || vchtypes == "Payment") {
        fetchReceipt_Payment(startDateString, endDateString, vchtypes, "");
      } else if (vchtypes == "Receivable" || vchtypes == "Payable") {
        if (vchtypes == "Receivable") {
          fetchReceivable_payable(
            startDateString,
            endDateString,
            "true",
            "",
          );
        } else if (vchtypes == "Payable") {
          fetchReceivable_payable(
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
            startDateString,
            endDateString,
            "true",
            "",
          );
        } else if (vchtypes == "Payable") {
          fetchReceivable_payable(
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
            fetchLedgerGroups();
          }
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
              startDateString,
              endDateString,
              "true",
              _selectedvoucher,
            );
          } else if (vchtypes == "Payable") {
            fetchReceivable_payable(
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

  Future<void> fetchParent(final String type) {
    return _fetchParentTallyApi();
  }

  Future<void> _fetchParentTallyApi() async {
    _commit(() => _isLoading = true);
    spinner_list.clear();

    try {
      final voucherTypes = await fetchAllPages(
        (page) => TallyApiClient().getForCompany(
          '/voucher-types?page=$page&limit=100',
        ),
      );

      spinner_list.add(allvchtypes);
      spinner_list.addAll(
        voucherTypes.map((v) => (v['name'] ?? '').toString()),
      );

      _voucherTypeMasterIdByName
        ..clear()
        ..addEntries(
          voucherTypes.map(
            (v) => MapEntry(
              (v['name'] ?? '').toString(),
              v['masterId'] as int,
            ),
          ),
        );

      _commit(() {
        _selectedvoucher = spinner_list[0];
      });
      fetchListData();
    } catch (e) {
      if (!mounted) return;
      _commit(() => _isLoading = false);
    }
  }

  Future<void> fetchParent_Receivable_Payable() {
    return _fetchParentReceivablePayableTallyApi();
  }

  Future<void> _fetchParentReceivablePayableTallyApi() async {
    _commit(() => _isLoading = true);
    spinner_list.clear();

    try {
      final ledgers = await _ledgerRepository.listLedgers();
      spinner_list.add(allparties);
      spinner_list.addAll(ledgers.map((l) => (l['name'] ?? '').toString()));

      _commit(() {
        _selectedvoucher = spinner_list[0];
      });
      fetchListData();
    } catch (e) {
      if (!mounted) return;
      _commit(() => _isLoading = false);
    }
  }

  /// Sets the voucher/party filter dropdown to [suggestion] and re-fetches -
  /// verbatim port of the widget's `TypeAheadField.onSelected` body, minus
  /// the `_voucherController.text`/`searchController.clear()` lines (the
  /// widget does those itself, since those controllers stay widget-local).
  void selectVoucher(String suggestion) {
    _commit(() {
      _selectedvoucher = suggestion;
      _reportSearchQuery = '';
    });
    fetchListData();
  }

  /// Verbatim port of the "clear voucher filter" `GestureDetector.onTap`
  /// body, minus `_voucherController.clear()`.
  void clearSelectedVoucher() {
    _commit(() {
      _selectedvoucher = spinner_list.isNotEmpty ? spinner_list.first : '';
    });
  }

  Future<void> fetchSales_purchase_cash(
    final String ledgroup,
    final String startdate,
    final String enddate,
    final String vchtypesArg,
    final String opening,
    final String vchname,
    final String ledger,
  ) {
    return _fetchSalesPurchaseCashTallyApi(
      ledgroup: ledgroup,
      startdate: startdate,
      enddate: enddate,
      vchname: vchname,
      ledger: ledger,
    );
  }

  Future<void> _fetchSalesPurchaseCashTallyApi({
    required String ledgroup,
    required String startdate,
    required String enddate,
    required String vchname,
    required String ledger,
  }) async {
    _commit(() {
      _isLoading = true;
      isSortVisible = false;
    });

    sales_purc_cash_list.clear();
    filteredItems_sale_purc_cash.clear();
    receivable_payable_list.clear();
    filteredItems_receivable_payable.clear();

    try {
      final from = parseCompactDate(startdate);
      final to = parseCompactDate(enddate);

      const salesTypes = {'Sales', 'CreditNote'};
      const purchaseTypes = {'Purchase', 'DebitNote'};
      final allowedTypes = ledgroup == 'Sales Accounts'
          ? salesTypes
          : ledgroup == 'Purchase Accounts'
          ? purchaseTypes
          : null;

      final List<Map<String, dynamic>> vouchers;
      if (vchname.isNotEmpty &&
          _voucherTypeMasterIdByName.containsKey(vchname)) {
        vouchers = await _voucherRepository.listInRange(
          from: from,
          to: to,
          voucherTypeMasterId: _voucherTypeMasterIdByName[vchname],
        );
      } else if (allowedTypes != null) {
        final ids = _voucherTypeMasterIdByName.entries
            .where((e) => allowedTypes.contains(e.key.replaceAll(' ', '')))
            .map((e) => e.value)
            .toSet();
        vouchers = ids.isEmpty
            ? await _voucherRepository.listInRange(from: from, to: to)
            : await _voucherRepository.listInRangeForTypes(
                from: from,
                to: to,
                voucherTypeMasterIds: ids,
              );
      } else {
        vouchers = await _voucherRepository.listInRange(from: from, to: to);
      }

      final items = <Sale_purc_cash>[];
      for (final voucher in vouchers) {
        final voucherType = (voucher['voucherTypeName'] as String? ?? '')
            .replaceAll(' ', '');
        if (allowedTypes != null && !allowedTypes.contains(voucherType)) {
          continue;
        }
        if (vchname.isNotEmpty && voucher['voucherTypeName'] != vchname) {
          continue;
        }

        final entries =
            (voucher['ledgerEntries'] as List?)?.cast<Map<String, dynamic>>() ??
            const [];
        if (entries.isEmpty) continue;

        if (ledger.isNotEmpty &&
            !entries.any((e) => e['ledgerName'] == ledger)) {
          continue;
        }

        final debitTotal = entries
            .where((e) => e['isDebit'] == true)
            .fold<double>(0, (sum, e) => sum + parseMoneyField(e['amount']));

        items.add(
          Sale_purc_cash.fromJson({
            'vchname': voucher['voucherTypeName'] ?? '',
            'vchno': voucher['number'] ?? '',
            'amount': debitTotal,
            'vchdate': voucher['date'] ?? '',
            'ledger': entries.first['ledgerName'] ?? '',
            'isoptional': voucher['isOptional'] ?? false,
            'ispostdated': voucher['isPostDated'] ?? false,
            'refno': voucher['reference'] ?? '',
            'refdate': voucher['referenceDate'] ?? '',
            'masterid': voucher['masterId'] ?? '',
            'ledgers': [
              for (final e in entries)
                {
                  'ledgername': e['ledgerName'] ?? '',
                  'amount': parseMoneyField(e['amount']),
                },
            ],
          }),
        );
      }

      if (!mounted) return;
      _commit(() {
        opening_value = '0';
        sales_purc_cash_list
          ..clear()
          ..addAll(items);
        filteredItems_sale_purc_cash = List.from(sales_purc_cash_list);
        isVisibleNoDataFound = filteredItems_sale_purc_cash.isEmpty;
        isSortVisible = filteredItems_sale_purc_cash.isNotEmpty;
        _isLoading = false;
      });

      if (filteredItems_sale_purc_cash.isNotEmpty) {
        switch (selectedSortOption) {
          case 'Default':
            sortByDefault();
          case 'Newest to Oldest':
            sortByDateHightoLow();
          case 'Oldest to Newest':
            sortByDateLowtoHigh();
          case 'A->Z':
            sortByAlphabetAtoZ();
          case 'Z->A':
            sortByAlphabetZtoA();
          case 'Amount High to Low':
            sortByAmountHightoLow();
          case 'Amount Low to High':
            sortByAmountLowtoHigh();
        }
      }
      if (_isTopPartiesView) _computeTopParties();
    } catch (e) {
      if (!mounted) return;
      _commit(() {
        isVisibleNoDataFound = true;
        isSortVisible = false;
        _isLoading = false;
      });
    }
  }

  Future<void> fetchReceivable_payable(
    final String startdate,
    final String enddate,
    final String isdebit,
    final String ledger,
  ) {
    return _fetchReceivablePayableTallyApi(isdebit: isdebit, ledger: ledger);
  }

  Future<void> _fetchReceivablePayableTallyApi({
    required String isdebit,
    required String ledger,
  }) async {
    _commit(() {
      _isLoading = true;
      isSortVisible = false;
    });

    receivable_payable_list.clear();
    filteredItems_receivable_payable.clear();
    sales_purc_cash_list.clear();
    filteredItems_sale_purc_cash.clear();

    try {
      int? ledgerMasterId;
      if (ledger.isNotEmpty) {
        final ledgers = await _ledgerRepository.listLedgers();
        final match = ledgers.firstWhere(
          (l) => l['name'] == ledger,
          orElse: () => const {},
        );
        ledgerMasterId = match['masterId'] as int?;
      }

      final bills = await _ledgerRepository.outstandingBills(
        ledgerMasterId: ledgerMasterId,
      );

      final wantReceivable = isdebit == 'true';
      final items = <Receivable_payable>[];
      double opening = 0;
      for (final bill in bills) {
        final balance = parseMoneyField(bill['finalBalance']);
        final isReceivable = balance > 0;
        if (isReceivable != wantReceivable) continue;
        opening += balance;
        items.add(
          Receivable_payable.fromJson({
            'ledger': bill['ledgerName'] ?? '',
            'billno': bill['name'] ?? '',
            'billdate': bill['date'] ?? '',
            'billtype': bill['isAdvance'] == true ? 'Advance' : 'New Ref',
            'duedate': bill['dueDate'] ?? '',
            'outstanding': balance,
          }),
        );
      }

      if (!mounted) return;
      _commit(() {
        opening_value = '0';
        receivable_payable_list
          ..clear()
          ..addAll(items);
        filteredItems_receivable_payable = List.from(receivable_payable_list);
        isVisibleNoDataFound = filteredItems_receivable_payable.isEmpty;
        isSortVisible = filteredItems_receivable_payable.isNotEmpty;
        _isLoading = false;
      });

      if (filteredItems_receivable_payable.isNotEmpty) {
        switch (selectedSortOption) {
          case 'Default':
            sortByDefault();
          case 'Newest to Oldest':
            sortByDateHightoLow();
          case 'Oldest to Newest':
            sortByDateLowtoHigh();
          case 'A->Z':
            sortByAlphabetAtoZ();
          case 'Z->A':
            sortByAlphabetZtoA();
          case 'Amount High to Low':
            sortByAmountHightoLow();
          case 'Amount Low to High':
            sortByAmountLowtoHigh();
        }
      }
      if (_isAgeingView) {
        await _computeAgeingBuckets();
        if (_isPartyAgeingView) await _computePartyAgeing();
      }
    } catch (e) {
      if (!mounted) return;
      _commit(() {
        isVisibleNoDataFound = true;
        isSortVisible = false;
        _isLoading = false;
      });
    }
  }

  Future<void> fetchReceipt_Payment(
    final String startdate,
    final String enddate,
    final String vchtypesArg,
    final String vchname,
  ) {
    return _fetchReceiptPaymentTallyApi(
      startdate: startdate,
      enddate: enddate,
      vchtypes: vchtypesArg,
      vchname: vchname,
    );
  }

  Future<void> _fetchReceiptPaymentTallyApi({
    required String startdate,
    required String enddate,
    required String vchtypes,
    required String vchname,
  }) async {
    _commit(() {
      _isLoading = true;
      isSortVisible = false;
    });

    sales_purc_cash_list.clear();
    filteredItems_sale_purc_cash.clear();
    receivable_payable_list.clear();
    filteredItems_receivable_payable.clear();

    try {
      final from = parseCompactDate(startdate);
      final to = parseCompactDate(enddate);

      final narrowByName = vchname.isNotEmpty ? vchname : vchtypes;
      final narrowedTypeId = _voucherTypeMasterIdByName[narrowByName];
      final vouchers = await _voucherRepository.listInRange(
        from: from,
        to: to,
        voucherTypeMasterId: narrowedTypeId,
      );

      final items = <Sale_purc_cash>[];
      for (final voucher in vouchers) {
        if (voucher['voucherTypeName'] != vchtypes) continue;
        if (vchname.isNotEmpty && voucher['voucherTypeName'] != vchname) {
          continue;
        }

        final entries =
            (voucher['ledgerEntries'] as List?)?.cast<Map<String, dynamic>>() ??
            const [];
        if (entries.isEmpty) continue;

        final debitTotal = entries
            .where((e) => e['isDebit'] == true)
            .fold<double>(0, (sum, e) => sum + parseMoneyField(e['amount']));

        items.add(
          Sale_purc_cash.fromJson({
            'vchname': voucher['voucherTypeName'] ?? '',
            'vchno': voucher['number'] ?? '',
            'amount': debitTotal,
            'vchdate': voucher['date'] ?? '',
            'ledger': entries.first['ledgerName'] ?? '',
            'isoptional': voucher['isOptional'] ?? false,
            'ispostdated': voucher['isPostDated'] ?? false,
            'refno': voucher['reference'] ?? '',
            'refdate': voucher['referenceDate'] ?? '',
            'masterid': voucher['masterId'] ?? '',
            'ledgers': [
              for (final e in entries)
                {
                  'ledgername': e['ledgerName'] ?? '',
                  'amount': parseMoneyField(e['amount']),
                },
            ],
          }),
        );
      }

      if (!mounted) return;
      _commit(() {
        sales_purc_cash_list
          ..clear()
          ..addAll(items);
        filteredItems_sale_purc_cash = List.from(sales_purc_cash_list);
        isVisibleNoDataFound = filteredItems_sale_purc_cash.isEmpty;
        isSortVisible = filteredItems_sale_purc_cash.isNotEmpty;
        _isLoading = false;
      });

      if (filteredItems_sale_purc_cash.isNotEmpty) {
        switch (selectedSortOption) {
          case 'Default':
            sortByDefault();
          case 'Newest to Oldest':
            sortByDateHightoLow();
          case 'Oldest to Newest':
            sortByDateLowtoHigh();
          case 'A->Z':
            sortByAlphabetAtoZ();
          case 'Z->A':
            sortByAlphabetZtoA();
          case 'Amount High to Low':
            sortByAmountHightoLow();
          case 'Amount Low to High':
            sortByAmountLowtoHigh();
        }
      }
      if (_isTopPartiesView) _computeTopParties();
    } catch (e) {
      if (!mounted) return;
      _commit(() {
        isVisibleNoDataFound = true;
        isSortVisible = false;
        _isLoading = false;
      });
    }
  }

  bool _isPlausibleAmount(double value) => value.abs() < 1e12;
  bool _isNegligibleAmount(double value) => value.abs() < 0.01;

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
        return _dateFormatDdMmmYy(duedate);
      } catch (_) {
        return DateTime.tryParse(duedate);
      }
    } catch (_) {
      return null;
    }
  }

  DateTime _dateFormatDdMmmYy(String s) {
    // Mirrors DateFormat('dd-MMM-yy').parse(duedate) from the original
    // widget without importing `intl`'s DateFormat into the notifier just
    // for this - falls through to DateTime.tryParse via the caller's catch
    // if this format doesn't match.
    final parts = s.split('-');
    if (parts.length != 3) throw const FormatException('bad date');
    const months = {
      'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6,
      'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12,
    };
    final day = int.parse(parts[0]);
    final month = months[parts[1]];
    if (month == null) throw const FormatException('bad month');
    final yy = int.parse(parts[2]);
    final year = yy < 100 ? 2000 + yy : yy;
    return DateTime(year, month, day);
  }

  Future<void> _computeAgeingBuckets() async {
    _commit(() {
      _isAgeingComputing = true;
    });
    final ageingPrefs = await SharedPreferences.getInstance();
    final h1 = int.tryParse(ageingPrefs.getString('heading1') ?? '30') ?? 30;
    final h2 = int.tryParse(ageingPrefs.getString('heading2') ?? '60') ?? 60;
    final h3 = int.tryParse(ageingPrefs.getString('heading3') ?? '90') ?? 90;
    final h4 = int.tryParse(ageingPrefs.getString('heading4') ?? '120') ?? 120;
    final h5 = int.tryParse(ageingPrefs.getString('heading5') ?? '180') ?? 180;

    final notDue = AgeingBucket('Not Due');
    final b1 = AgeingBucket('0-$h1 Days');
    final b2 = AgeingBucket('$h1-$h2 Days');
    final b3 = AgeingBucket('$h2-$h3 Days');
    final b4 = AgeingBucket('$h3-$h4 Days');
    final b5 = AgeingBucket('$h4-$h5 Days');
    final b6 = AgeingBucket('$h5+ Days');
    final others = AgeingBucket('Others');

    final today = DateTime.now();

    for (final card in filteredItems_receivable_payable) {
      if (_isNegligibleAmount(card.outstanding)) continue;

      final plausible = _isPlausibleAmount(card.outstanding);

      if (card.billtype != 'Agst Ref' && card.billtype != 'New Ref') {
        others.count++;
        if (plausible) others.amount += card.outstanding;
        others.items.add(card);
        continue;
      }

      final dueDate = _parseDueDateSafe(card.billdate, card.duedate);
      if (dueDate == null) {
        others.count++;
        if (plausible) others.amount += card.outstanding;
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
      if (plausible) bucket.amount += card.outstanding;
      bucket.items.add(card);
    }

    final buckets = [notDue, b1, b2, b3, b4, b5, b6, others]
        .where((b) => b.count > 0)
        .toList();

    if (!mounted) return;
    _commit(() {
      _ageingBuckets = buckets;
      _ageingBucketsDefaultOrder = List.from(buckets);
      _selectedAgeingBucket = null;
      selectedSortOption = 'Default';
      _isAgeingComputing = false;
    });
  }

  Future<void> _computePartyAgeing() async {
    final ageingPrefs = await SharedPreferences.getInstance();
    final h1 = int.tryParse(ageingPrefs.getString('heading1') ?? '30') ?? 30;
    final h2 = int.tryParse(ageingPrefs.getString('heading2') ?? '60') ?? 60;
    final h3 = int.tryParse(ageingPrefs.getString('heading3') ?? '90') ?? 90;
    final h4 = int.tryParse(ageingPrefs.getString('heading4') ?? '120') ?? 120;
    final h5 = int.tryParse(ageingPrefs.getString('heading5') ?? '180') ?? 180;

    final bandOrder = [
      '0-$h1 Days',
      '$h1-$h2 Days',
      '$h2-$h3 Days',
      '$h3-$h4 Days',
      '$h4-$h5 Days',
      '$h5+ Days',
    ];

    String bandFor(int daysOverdue) {
      if (daysOverdue <= h1) return bandOrder[0];
      if (daysOverdue <= h2) return bandOrder[1];
      if (daysOverdue <= h3) return bandOrder[2];
      if (daysOverdue <= h4) return bandOrder[3];
      if (daysOverdue <= h5) return bandOrder[4];
      return bandOrder[5];
    }

    final Map<String, PartyAgeingEntry> byLedger = {};
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);

    for (final card in filteredItems_receivable_payable) {
      if (_isNegligibleAmount(card.outstanding)) continue;
      if (card.billtype != 'Agst Ref' && card.billtype != 'New Ref') continue;

      final dueDate = _parseDueDateSafe(card.billdate, card.duedate);
      if (dueDate == null) continue;

      final daysOverdue = todayDate
          .difference(DateTime(dueDate.year, dueDate.month, dueDate.day))
          .inDays;
      if (daysOverdue <= 0) continue;

      final entry = byLedger.putIfAbsent(
        card.ledger,
        () => PartyAgeingEntry(card.ledger)..bandOrder = bandOrder,
      );
      entry.overdueCount++;
      entry.overdueBills.add(card);
      if (daysOverdue > entry.maxDaysOverdue) {
        entry.maxDaysOverdue = daysOverdue;
      }

      if (_isPlausibleAmount(card.outstanding)) {
        entry.overdueAmount += card.outstanding;
        final band = bandFor(daysOverdue);
        entry.bandAmounts[band] =
            (entry.bandAmounts[band] ?? 0) + card.outstanding.abs();
      }
    }

    final parties = byLedger.values.toList()
      ..sort((a, b) => b.overdueAmount.abs().compareTo(a.overdueAmount.abs()));

    if (!mounted) return;
    _commit(() {
      _partyAgeing = parties;
      _partyAgeingDefaultOrder = List.from(parties);
      _selectedPartyAgeing = null;
    });
  }

  void _applyPartyAgeingSort(String option) {
    _commit(() {
      if (_selectedPartyAgeing != null) {
        final bills = _selectedPartyAgeing!.overdueBills;
        switch (option) {
          case 'A->Z':
            bills.sort((a, b) => a.billno.compareTo(b.billno));
            break;
          case 'Z->A':
            bills.sort((a, b) => b.billno.compareTo(a.billno));
            break;
          case 'Amount High to Low':
            bills.sort(
              (a, b) => b.outstanding.abs().compareTo(a.outstanding.abs()),
            );
            break;
          case 'Amount Low to High':
            bills.sort(
              (a, b) => a.outstanding.abs().compareTo(b.outstanding.abs()),
            );
            break;
          case 'Default':
          default:
            break;
        }
      } else {
        switch (option) {
          case 'A->Z':
            _partyAgeing.sort((a, b) => a.ledger.compareTo(b.ledger));
            break;
          case 'Z->A':
            _partyAgeing.sort((a, b) => b.ledger.compareTo(a.ledger));
            break;
          case 'Amount High to Low':
            _partyAgeing.sort(
              (a, b) => b.overdueAmount.abs().compareTo(a.overdueAmount.abs()),
            );
            break;
          case 'Amount Low to High':
            _partyAgeing.sort(
              (a, b) => a.overdueAmount.abs().compareTo(b.overdueAmount.abs()),
            );
            break;
          case 'Default':
          default:
            _partyAgeing = List.from(_partyAgeingDefaultOrder);
            break;
        }
      }
    });
  }

  void _computeTopParties() {
    final Map<String, TopPartyEntry> byLedger = {};

    for (final card in filteredItems_sale_purc_cash) {
      if (_isNegligibleAmount(card.amount)) continue;

      final entry = byLedger.putIfAbsent(
        card.ledger,
        () => TopPartyEntry(card.ledger),
      );
      entry.voucherCount++;
      if (_isPlausibleAmount(card.amount)) {
        entry.amount += card.amount;
      }
      entry.vouchers.add(card);
    }

    final parties = byLedger.values.toList()
      ..sort((a, b) => b.amount.abs().compareTo(a.amount.abs()));

    if (!mounted) return;
    _commit(() {
      _topParties = parties;
      _topPartiesDefaultOrder = List.from(parties);
      _selectedTopParty = null;
      selectedSortOption = 'Default';
    });
  }

  void _applyTopPartiesSort(String option) {
    _commit(() {
      if (_selectedTopParty != null) {
        final vouchers = _selectedTopParty!.vouchers;
        switch (option) {
          case 'Newest to Oldest':
            vouchers.sort((a, b) => b.vchdate.compareTo(a.vchdate));
            break;
          case 'Oldest to Newest':
            vouchers.sort((a, b) => a.vchdate.compareTo(b.vchdate));
            break;
          case 'A->Z':
            vouchers.sort((a, b) => a.vchname.compareTo(b.vchname));
            break;
          case 'Z->A':
            vouchers.sort((a, b) => b.vchname.compareTo(a.vchname));
            break;
          case 'Amount High to Low':
            vouchers.sort((a, b) => b.amount.abs().compareTo(a.amount.abs()));
            break;
          case 'Amount Low to High':
            vouchers.sort((a, b) => a.amount.abs().compareTo(b.amount.abs()));
            break;
          case 'Default':
          default:
            break;
        }
      } else {
        switch (option) {
          case 'A->Z':
            _topParties.sort((a, b) => a.ledger.compareTo(b.ledger));
            break;
          case 'Z->A':
            _topParties.sort((a, b) => b.ledger.compareTo(a.ledger));
            break;
          case 'Amount High to Low':
            _topParties.sort(
              (a, b) => b.amount.abs().compareTo(a.amount.abs()),
            );
            break;
          case 'Amount Low to High':
            _topParties.sort(
              (a, b) => a.amount.abs().compareTo(b.amount.abs()),
            );
            break;
          case 'Default':
          default:
            _topParties = List.from(_topPartiesDefaultOrder);
            break;
        }
      }
    });
  }

  void _applyAgeingSort(String option) {
    _commit(() {
      if (_selectedAgeingBucket != null) {
        final items = _selectedAgeingBucket!.items;
        DateTime dueOf(Receivable_payable c) =>
            _parseDueDateSafe(c.billdate, c.duedate) ??
            DateTime.tryParse(c.billdate) ??
            DateTime(1900);
        switch (option) {
          case 'Newest to Oldest':
            items.sort((a, b) => dueOf(b).compareTo(dueOf(a)));
            break;
          case 'Oldest to Newest':
            items.sort((a, b) => dueOf(a).compareTo(dueOf(b)));
            break;
          case 'A->Z':
            items.sort((a, b) => a.ledger.compareTo(b.ledger));
            break;
          case 'Z->A':
            items.sort((a, b) => b.ledger.compareTo(a.ledger));
            break;
          case 'Amount High to Low':
            items.sort(
              (a, b) => b.outstanding.abs().compareTo(a.outstanding.abs()),
            );
            break;
          case 'Amount Low to High':
            items.sort(
              (a, b) => a.outstanding.abs().compareTo(b.outstanding.abs()),
            );
            break;
          case 'Default':
          default:
            break;
        }
      } else {
        switch (option) {
          case 'A->Z':
            _ageingBuckets.sort((a, b) => a.label.compareTo(b.label));
            break;
          case 'Z->A':
            _ageingBuckets.sort((a, b) => b.label.compareTo(a.label));
            break;
          case 'Amount High to Low':
            _ageingBuckets.sort(
              (a, b) => b.amount.abs().compareTo(a.amount.abs()),
            );
            break;
          case 'Amount Low to High':
            _ageingBuckets.sort(
              (a, b) => a.amount.abs().compareTo(b.amount.abs()),
            );
            break;
          case 'Default':
          default:
            _ageingBuckets = List.from(_ageingBucketsDefaultOrder);
            break;
        }
      }
    });
  }

  /// Toggles the Receivable/Payable Ageing-view icon button - verbatim port
  /// of that `IconButton.onPressed` body (spinner delay included), minus the
  /// `setState`/`mounted` widget coupling (replaced by `_commit`/`ref.mounted`).
  Future<void> toggleAgeingView() async {
    _commit(() => _isSwitchingView = true);
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    final togglingOn = !_isAgeingView;
    _commit(() {
      _isAgeingView = togglingOn;
      _selectedAgeingBucket = null;
      _isPartyAgeingView = false;
      _selectedPartyAgeing = null;
      _isSwitchingView = false;
      selectedSortOption = 'Default';
    });
    if (togglingOn) {
      await _computeAgeingBuckets();
    } else {
      sortByDefault();
    }
  }

  /// Toggles the Sales/Purchase Top-Parties icon button - verbatim port,
  /// same shape as [toggleAgeingView].
  Future<void> toggleTopPartiesView() async {
    _commit(() => _isSwitchingTopPartiesView = true);
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    final togglingOn = !_isTopPartiesView;
    _commit(() {
      _isTopPartiesView = togglingOn;
      _selectedTopParty = null;
      _isSwitchingTopPartiesView = false;
      selectedSortOption = 'Default';
    });
    if (togglingOn) {
      _computeTopParties();
    } else {
      sortByDefault();
    }
  }

  void clearSelectedTopParty() {
    _commit(() {
      _selectedTopParty = null;
      selectedSortOption = 'Default';
      _topParties = List.from(_topPartiesDefaultOrder);
    });
  }

  void clearSelectedPartyAgeing() {
    _commit(() {
      _selectedPartyAgeing = null;
      selectedSortOption = 'Default';
      _partyAgeing = List.from(_partyAgeingDefaultOrder);
    });
  }

  void clearSelectedAgeingBucket() {
    _commit(() {
      _selectedAgeingBucket = null;
      selectedSortOption = 'Default';
      _ageingBuckets = List.from(_ageingBucketsDefaultOrder);
    });
  }

  void selectAgeingBucket(AgeingBucket bucket) {
    _commit(() {
      _selectedAgeingBucket = bucket;
      selectedSortOption = 'Default';
    });
  }

  void selectPartyAgeing(PartyAgeingEntry entry) {
    _commit(() {
      _selectedPartyAgeing = entry;
      selectedSortOption = 'Default';
    });
  }

  void selectTopParty(TopPartyEntry entry) {
    _commit(() {
      _selectedTopParty = entry;
      selectedSortOption = 'Default';
    });
  }

  void togglePartyAgeingMode(bool isPartyMode) {
    _commit(() {
      _isPartyAgeingView = isPartyMode;
      selectedSortOption = 'Default';
    });
    if (isPartyMode && _partyAgeing.isEmpty) {
      _computePartyAgeing();
    }
  }

  /// Cash/Bank "Previous" back-button - verbatim port minus
  /// `searchController.clear()`/`FocusScope.of(context).unfocus()` (widget).
  void backToLedgerGroups() {
    _commit(() {
      _isSalesListVisible = false;
      _isLedgerGroupVisible = true;
    });
    fetchLedgerGroups();
  }

  /// Cash/Bank ledger-group row tap - verbatim port minus
  /// `searchController.clear()`/`FocusScope.of(context).unfocus()`.
  void selectLedgerGroup(String ledgerName) {
    _commit(() {
      _selectedLedgerGroup = ledgerName;
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
  }

  void clearVoucherTypeFilter(String firstSpinnerOption) {
    _commit(() => _selectedvoucher = firstSpinnerOption);
  }

  /// Search-box clear ("x") button - verbatim port minus `searchController.
  /// clear()` and the trailing `setState(() {})` (a plain rebuild trigger,
  /// unnecessary once `resetSearch()` already updates notifier state).
  void clearSearch() {
    resetSearch();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();

    _commit(() {
      company = prefs.getString('company_name');
    });

    try {
      selectedSortOption = prefs.getString('sort') ?? 'Default';
      if (selectedSortOption == 'null') selectedSortOption = 'Default';
    } catch (e) {
      selectedSortOption = 'Default';
    }

    final start = DateTime.parse(startDateString);
    final end = DateTime.parse(endDateString);

    startdate_text = _formatDdMmmYyyy(start);
    enddate_text = _formatDdMmmYyyy(end);

    fetchParentData();

    if (vchtypes == "Receivable" || vchtypes == "Payable") {
      _commit(() => openingheading = 'OnAccount');
    } else {
      _commit(() => openingheading = 'Opening Balance');
    }
  }

  static const _monthNames = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _formatDdMmmYyyy(DateTime d) {
    final day = d.day.toString().padLeft(2, '0');
    return '$day-${_monthNames[d.month - 1]}-${d.year}';
  }

  /// Applies a newly-picked date range - verbatim port of `_selectDateRange`'s
  /// `setState` body, called by the widget after `showDateRangePicker`
  /// resolves (the picker itself needs `BuildContext`, so it stays widget-side).
  void setDateRange(DateTime start, DateTime end) {
    _commit(() {
      final sdf = start.month.toString().padLeft(2, '0');
      final sdfEnd = end.month.toString().padLeft(2, '0');
      final startDay = start.day.toString().padLeft(2, '0');
      final endDay = end.day.toString().padLeft(2, '0');

      startDateString = '${start.year}$sdf$startDay';
      endDateString = '${end.year}$sdfEnd$endDay';

      startdate_text = _formatDdMmmYyyy(start);
      enddate_text = _formatDdMmmYyyy(end);
    });
    fetchListData();
  }
}

final dashboardClickedNotifierProvider = StateNotifierProvider.autoDispose
    .family<DashboardClickedNotifier, DashboardClickedState, DashboardClickedArgs>(
      (ref, args) => DashboardClickedNotifier(ref, args),
    );
